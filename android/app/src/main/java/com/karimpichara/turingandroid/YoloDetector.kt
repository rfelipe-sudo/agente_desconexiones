package com.karimpichara.turingandroid

import android.graphics.Bitmap
import android.graphics.RectF
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtSession
import android.graphics.Canvas
import android.graphics.Color
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

data class LetterboxResult(
    val bitmap: Bitmap,
    val ratio: Float,
    val dx: Float,
    val dy: Float
)

fun letterbox(
    src: Bitmap,
    newWidth: Int,
    newHeight: Int
): LetterboxResult {

    val srcW = src.width
    val srcH = src.height

    val r = minOf(
        newWidth.toFloat() / srcW,
        newHeight.toFloat() / srcH
    )

    val resizedW = (srcW * r).toInt()
    val resizedH = (srcH * r).toInt()

    val resized = Bitmap.createScaledBitmap(src, resizedW, resizedH, true)

    val output = Bitmap.createBitmap(newWidth, newHeight, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(output)

    canvas.drawColor(Color.rgb(114, 114, 114))

    val dx = (newWidth - resizedW) / 2f
    val dy = (newHeight - resizedH) / 2f

    canvas.drawBitmap(resized, dx, dy, null)

    return LetterboxResult(output, r, dx, dy)
}
class YoloDetector(
    private val session: OrtSession,
    private val inputWidth: Int,
    private val inputHeight: Int,
) {
    private val env = ai.onnxruntime.OrtEnvironment.getEnvironment()
    private val inputName = session.inputNames.first()

    fun detect(
        bitmap: Bitmap,
        confThreshold: Float = 0.5f,
        nmsThreshold: Float = 0.45f
    ): List<Pair<RectF, Float>> {

        // --- 1. Letterbox instead of stretching ---
        val (resized, ratio, dx, dy) = letterbox(bitmap, inputWidth, inputHeight)

        val tensor = bitmapToTensor(resized)

        val result = session.run(mapOf(inputName to tensor))
        val output = (result[0].value as Array<Array<FloatArray>>)[0]

        val boxes = mutableListOf<FloatArray>()
        val scores = mutableListOf<Float>()
        val numPredictions = output[0].size

        for (i in 0 until numPredictions) {
            val cx = output[0][i]
            val cy = output[1][i]
            val w = output[2][i]
            val h = output[3][i]
            val conf = output[4][i]

            if (conf < confThreshold) continue

            // YOLO → xyxy (still in letterboxed space)
            var x1 = cx - w / 2f
            var y1 = cy - h / 2f
            var x2 = cx + w / 2f
            var y2 = cy + h / 2f

            // --- 2. Undo letterbox (THIS replaces scaleX/scaleY) ---
            x1 = (x1 - dx) / ratio
            y1 = (y1 - dy) / ratio
            x2 = (x2 - dx) / ratio
            y2 = (y2 - dy) / ratio

            // Clamp to original image
            x1 = x1.coerceIn(0f, bitmap.width.toFloat())
            y1 = y1.coerceIn(0f, bitmap.height.toFloat())
            x2 = x2.coerceIn(0f, bitmap.width.toFloat())
            y2 = y2.coerceIn(0f, bitmap.height.toFloat())

            boxes.add(floatArrayOf(x1, y1, x2, y2))
            scores.add(conf)
        }

        // NMS (now done in original image space — this is actually better)
        val selectedIndices = nms(boxes, scores, nmsThreshold)

        return selectedIndices.map { idx ->
            val b = boxes[idx]
            RectF(b[0], b[1], b[2], b[3]) to scores[idx]
        }
    }

    private fun bitmapToTensor(bitmap: Bitmap): OnnxTensor {
        val batch = 1
        val channels = 3
        val height = bitmap.height
        val width = bitmap.width

        val floatArray = FloatArray(batch * channels * height * width)

        val intValues = IntArray(width * height)
        bitmap.getPixels(intValues, 0, width, 0, 0, width, height)

        val hw = height * width

        for (i in intValues.indices) {
            val pixel = intValues[i]

            val r = ((pixel shr 16) and 0xFF) / 255.0f
            val g = ((pixel shr 8) and 0xFF) / 255.0f
            val b = (pixel and 0xFF) / 255.0f

            // Channel-first layout
            floatArray[i] = r                 // R channel
            floatArray[i + hw] = g            // G channel
            floatArray[i + 2 * hw] = b        // B channel
        }

        return OnnxTensor.createTensor(
            env,
            FloatBuffer.wrap(floatArray),
            longArrayOf(1, 3, height.toLong(), width.toLong())
        )
    }
}

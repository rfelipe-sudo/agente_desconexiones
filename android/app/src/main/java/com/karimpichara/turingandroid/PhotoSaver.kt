package com.karimpichara.turingandroid

import android.content.Context
import android.graphics.Bitmap
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object PhotoSaver {

    private const val MAX_DIMENSION = 800
    private const val JPEG_QUALITY = 70
    private const val PHOTO_DIR = "photos"
    private const val S3_PREFIX = "android-photos"

    fun calculateResizedDimensions(
        width: Int,
        height: Int,
        maxDim: Int = MAX_DIMENSION
    ): Pair<Int, Int> {
        val longest = maxOf(width, height)
        if (longest <= maxDim) return Pair(width, height)
        val scale = maxDim.toFloat() / longest
        return Pair((width * scale).toInt(), (height * scale).toInt())
    }

    fun generateFilename(
        rut: String,
        boxType: String,
        convConf: Float,
        yoloConf: Float
    ): String {
        val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        return "${rut}_${boxType}_${timestamp}_${"%.2f".format(convConf)}_${"%.2f".format(yoloConf)}.jpg"
    }

    fun generateS3Key(boxType: String, filename: String): String {
        return "$S3_PREFIX/$boxType/$filename"
    }

    fun save(
        context: Context,
        bitmap: Bitmap,
        rut: String,
        boxType: String,
        convConf: Float,
        yoloConf: Float
    ): File? {
        val (newW, newH) = calculateResizedDimensions(bitmap.width, bitmap.height)
        val resized = if (newW != bitmap.width || newH != bitmap.height) {
            Bitmap.createScaledBitmap(bitmap, newW, newH, true)
        } else {
            bitmap
        }

        val photoDir = File(context.filesDir, PHOTO_DIR)
        if (!photoDir.exists()) photoDir.mkdirs()

        val file = File(photoDir, generateFilename(rut, boxType, convConf, yoloConf))
        return try {
            FileOutputStream(file).use { out ->
                resized.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, out)
            }
            file
        } catch (_: Exception) {
            null
        } finally {
            if (resized !== bitmap) resized.recycle()
        }
    }
}

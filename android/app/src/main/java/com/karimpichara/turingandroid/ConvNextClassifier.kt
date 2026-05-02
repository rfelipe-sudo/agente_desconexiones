package com.karimpichara.turingandroid

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.RectF
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtSession
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.exp
import java.nio.FloatBuffer

data class BoxType(
    val code: String,
    val name: String,
    val filenamePrefix: String,
    val color: String,
    val description: String? = null
)

class ConvNextClassifier(
    private val session: OrtSession,
) {
    private val env = ai.onnxruntime.OrtEnvironment.getEnvironment()
    private val inputName = session.inputNames.first()

    fun classify(
        bitmap: Bitmap,
        bbox: RectF,
        confThreshold: Float = 0.5f,
    ): Triple<String?, Float, String?> {
        val crop = squareCrop(bitmap, bbox)
        val tensor = cropToTensor(crop)

        val result = session.run(mapOf(inputName to tensor))
        val logits = (result[0].value as Array<FloatArray>)[0]

        val probs = softmax(logits)
        val maxIdx = probs.indices.maxByOrNull { probs[it] } ?: 0
        val maxConf = probs[maxIdx]

//        val label = if (maxConf >= confThreshold) CLASS_NAMES[maxIdx] else "no_detection"

        val label = if (maxConf >= confThreshold) CLASS_NAMES[maxIdx] else "no_detection"

        val boxType = BOX_TYPES.values
            .find { it.filenamePrefix == label }
            ?.code

        val label_name = BOX_TYPES[boxType]?.name

        return Triple(label_name, maxConf, boxType)
    }

    private fun squareCrop(bitmap: Bitmap, bbox: RectF, padding: Int = 10): Bitmap {
        val imgW = bitmap.width
        val imgH = bitmap.height

        val px1 = maxOf(0, bbox.left.toInt() - padding)
        val py1 = maxOf(0, bbox.top.toInt() - padding)
        val px2 = minOf(imgW, bbox.right.toInt() + padding)
        val py2 = minOf(imgH, bbox.bottom.toInt() + padding)

        val boxW = px2 - px1
        val boxH = py2 - py1
        val size = maxOf(boxW, boxH)

        val cx = (px1 + px2) / 2
        val cy = (py1 + py2) / 2

        val sx1 = cx - size / 2
        val sy1 = cy - size / 2
        val sx2 = sx1 + size
        val sy2 = sy1 + size

        val padLeft = maxOf(0, -sx1)
        val padTop = maxOf(0, -sy1)
        val padRight = maxOf(0, sx2 - imgW)
        val padBottom = maxOf(0, sy2 - imgH)

        val cx1 = maxOf(0, sx1)
        val cy1 = maxOf(0, sy1)
        val cx2 = minOf(imgW, sx2)
        val cy2 = minOf(imgH, sy2)

        val crop = Bitmap.createBitmap(bitmap, cx1, cy1, cx2 - cx1, cy2 - cy1)

        val finalCrop = if (padTop > 0 || padBottom > 0 || padLeft > 0 || padRight > 0) {
            val padded = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(padded)
            canvas.drawColor(Color.BLACK)
            canvas.drawBitmap(crop, padLeft.toFloat(), padTop.toFloat(), null)
            crop.recycle()
            padded
        } else {
            crop
        }

        return Bitmap.createScaledBitmap(finalCrop, 320, 320, true)
    }

    private fun cropToTensor(bitmap: Bitmap): OnnxTensor {
        val height = bitmap.height
        val width = bitmap.width

        val floatArray = FloatArray(1 * 3 * height * width)

        val intValues = IntArray(width * height)
        bitmap.getPixels(intValues, 0, width, 0, 0, width, height)

        val hw = height * width

        for (i in intValues.indices) {
            val pixel = intValues[i]

            val r = ((pixel shr 16) and 0xFF) / 255.0f
            val g = ((pixel shr 8) and 0xFF) / 255.0f
            val b = (pixel and 0xFF) / 255.0f

            // Apply ImageNet normalization (ConvNeXt standard)
            floatArray[i] = (r - 0.485f) / 0.229f
            floatArray[i + hw] = (g - 0.456f) / 0.224f
            floatArray[i + 2 * hw] = (b - 0.406f) / 0.225f
        }

        return OnnxTensor.createTensor(
            env,
            FloatBuffer.wrap(floatArray),
            longArrayOf(1, 3, height.toLong(), width.toLong())
        )
    }

    private fun softmax(logits: FloatArray): FloatArray {
        val max = logits.maxOrNull() ?: 0f
        val exps = logits.map { exp(it - max) }
        val sum = exps.sum()
        return exps.map { it / sum }.toFloatArray()
    }

    companion object {
        val CLASS_NAMES = listOf(
            "3zsolutions", "cdoielectroson", "cdoifurukawa", "cdoifiberhome",
            "cdoionnet", "cdoitelefonica", "electroson", "fiberhome", "furukawa",
            "fusion", "huawei", "huaweiv2",
        )

        val BOX_TYPES = mapOf(
            "type_a" to BoxType("type_a", "Electroson", "electroson", "#667eea"),
            "type_b" to BoxType("type_b", "Huawei", "huawei", "#f093fb"),
            "type_c" to BoxType("type_c", "CTO Fusión", "fusion", "#e67e22"),
            "type_d" to BoxType("type_d", "Corning", "corning", "#16a085"),
            "type_e" to BoxType("type_e", "3Z Solutions", "3zsolutions", "#9b59b6"),
            "type_f" to BoxType("type_f", "FiberHome", "fiberhome", "#e74c3c"),
            "type_g" to BoxType("type_g", "Furukawa", "furukawa", "#3498db"),
            "type_h" to BoxType("type_h", "CDOI FiberHome", "cdoifiberhome", "#e91e63"),
            "type_i" to BoxType("type_i", "CDOI Telefónica", "cdoitelefonica", "#00bcd4"),
            "type_j" to BoxType("type_j", "CDOI Electroson", "cdoielectroson", "#ff9800"),
            "type_k" to BoxType("type_k", "CDOI Furukawa", "cdoifurukawa", "#4caf50"),
            "type_l" to BoxType("type_l", "CDOI ONNET", "cdoionnet", "#673ab7"),
            "type_m" to BoxType("type_m", "Fico", "fico", "#009688"),
            "type_n" to BoxType("type_n", "Huawei V2", "huaweiv2", "#ff5722"),
            "type_o" to BoxType("type_o", "CTO en mal estado", "damaged", "#f44336"),
            "unregistered" to BoxType("unregistered", "CTO no registrada", "unregistered", "#95a5a6")
        )
    }
}



//BOX_TYPES = {
//    "type_a": {
//        "code": "type_a",
//        "name": "Electroson",
//        "filename_prefix": "electroson",
//        "color": "#667eea",  # Purple
//        "description": None,  # Will be set below
//    },
//    "type_b": {
//        "code": "type_b",
//        "name": "Huawei",
//        "filename_prefix": "huawei",
//        "color": "#f093fb",  # Pink
//        "description": None,  # Will be set below
//    },
//    "type_c": {
//        "code": "type_c",
//        "name": "CTO Fusión",
//        "filename_prefix": "fusion",
//        "color": "#e67e22",  # Orange
//        "description": None,  # Will be set below (special case - fusion splice box)
//    },
//    "type_d": {
//        "code": "type_d",
//        "name": "Corning",
//        "filename_prefix": "corning",
//        "color": "#16a085",  # Teal/Green
//        "description": None,  # Will be set below
//    },
//    "type_e": {
//        "code": "type_e",
//        "name": "3Z Solutions",
//        "filename_prefix": "3zsolutions",
//        "color": "#9b59b6",  # Purple/Violet
//        "description": None,  # Will be set below
//    },
//    "type_f": {
//        "code": "type_f",
//        "name": "FiberHome",
//        "filename_prefix": "fiberhome",
//        "color": "#e74c3c",  # Red
//        "description": None,  # Will be set below
//    },
//    "type_g": {
//        "code": "type_g",
//        "name": "Furukawa",
//        "filename_prefix": "furukawa",
//        "color": "#3498db",  # Blue
//        "description": None,  # Will be set below
//    },
//    "type_h": {
//        "code": "type_h",
//        "name": "CDOI FiberHome",
//        "filename_prefix": "cdoiofiberhome",
//        "color": "#e91e63",  # Pink/Magenta
//        "description": None,  # Will be set below
//    },
//    "type_i": {
//        "code": "type_i",
//        "name": "CDOI Telefónica",
//        "filename_prefix": "cdoitelefonica",
//        "color": "#00bcd4",  # Cyan
//        "description": None,  # Will be set below
//    },
//    "type_j": {
//        "code": "type_j",
//        "name": "CDOI Electroson",
//        "filename_prefix": "cdoielectroson",
//        "color": "#ff9800",  # Orange
//        "description": None,  # Will be set below
//    },
//    "type_k": {
//        "code": "type_k",
//        "name": "CDOI Furukawa",
//        "filename_prefix": "cdoifurukawa",
//        "color": "#4caf50",  # Green
//        "description": None,  # Will be set below
//    },
//    "type_l": {
//        "code": "type_l",
//        "name": "CDOI ONNET",
//        "filename_prefix": "cdoionnet",
//        "color": "#673ab7",  # Deep Purple
//        "description": None,  # Will be set below
//    },
//    "type_m": {
//        "code": "type_m",
//        "name": "Fico",
//        "filename_prefix": "fico",
//        "color": "#009688",  # Teal
//        "description": None,  # Will be set below
//    },
//    "type_n": {
//        "code": "type_n",
//        "name": "Huawei V2",
//        "filename_prefix": "huaweiv2",
//        "color": "#ff5722",  # Deep Orange
//        "description": None,  # Will be set below
//    },
//    "type_o": {
//        "code": "type_o",
//        "name": "CTO en mal estado",
//        "filename_prefix": "damaged",
//        "color": "#f44336",  # Red
//        "description": None,  # Will be set below - special case with manual cuenta input
//    },
//    "unregistered": {
//        "code": "unregistered",
//        "name": "CTO no registrada",
//        "filename_prefix": "unregistered",
//        "color": "#95a5a6",  # Gray
//        "description": None,  # Special case - unregistered CTO, no AI analysis needed
//    },
//}
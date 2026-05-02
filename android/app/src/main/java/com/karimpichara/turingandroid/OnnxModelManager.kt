package com.karimpichara.turingandroid

import android.content.Context
import ai.onnxruntime.providers.NNAPIFlags
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import ai.onnxruntime.TensorInfo
import java.io.File
import java.io.FileOutputStream
import java.util.EnumSet

class OnnxModelManager(private val context: Context) {

    var yoloSession: OrtSession? = null
        private set
    var convnextSession: OrtSession? = null
        private set

    var yoloInputWidth: Int = 0
        private set
    var yoloInputHeight: Int = 0
        private set

    private val env: OrtEnvironment = OrtEnvironment.getEnvironment()

    fun initialize() {
        val yoloModelPath = copyAsset("yolov8n_cajas/yolo8vn_cajas.onnx")
        val convnextModelPath = copyAsset(
            "convnext_tiny_cajas/convnext_tiny_augmentation_fulltune_noaugment_320x320_black_10.onnx"
        )
        copyAsset(
            "convnext_tiny_cajas/convnext_tiny_augmentation_fulltune_noaugment_320x320_black_10.onnx.data"
        )

        yoloSession = createSessionWithNnapiFallback(yoloModelPath)
        convnextSession = createSessionWithNnapiFallback(convnextModelPath)

        // Read YOLO input shape from model
        val inputInfo = yoloSession!!.inputInfo.values.first()
        val tensorInfo = inputInfo.info as TensorInfo
        val shape = tensorInfo.shape
        // shape = [1, 3, H, W] in NCHW
        yoloInputHeight = shape[2].toInt()
        yoloInputWidth = shape[3].toInt()
    }

    private fun createSessionWithNnapiFallback(modelPath: String): OrtSession {
        return try {
            val options = OrtSession.SessionOptions()
            options.addNnapi(EnumSet.of(NNAPIFlags.USE_FP16))
            env.createSession(modelPath, options)
        } catch (_: Exception) {
            env.createSession(modelPath, OrtSession.SessionOptions())
        }
    }

    private fun copyAsset(assetPath: String): String {
        val outFile = File(context.filesDir, assetPath)
        if (!outFile.exists()) {
            outFile.parentFile?.mkdirs()
            context.assets.open(assetPath).use { input ->
                FileOutputStream(outFile).use { output ->
                    input.copyTo(output)
                }
            }
        }
        return outFile.absolutePath
    }

    companion object {
        private const val TAG = "OnnxModelManager"
    }
}

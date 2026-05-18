package com.karimpichara.turingandroid

import android.Manifest
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Matrix
import android.os.Bundle
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageButton
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import com.creacionestecnologicas.agente_desconexiones.R
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class CtoScanActivity : AppCompatActivity() {
    private lateinit var scanningText: TextView
    private var scanningAnimator: ObjectAnimator? = null
    private lateinit var previewView: PreviewView
    private lateinit var statusText: TextView
    private lateinit var overlayView: DetectionOverlayView

    private val cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val inferenceExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    private val modelsReady = AtomicBoolean(false)
    private lateinit var modelManager: OnnxModelManager
    private var yoloDetector: YoloDetector? = null
    private var convNextClassifier: ConvNextClassifier? = null
    @Volatile private var waitingForUser = false
    @Volatile private var pendingPhotoPath: String? = null
    private var rut: String = ""
    private val areaYoloInput = 640 * 480

    private val latestFrameProcessor = LatestFrameProcessor<Bitmap>(inferenceExecutor) { bitmap ->
        if (waitingForUser) return@LatestFrameProcessor
        if (!modelsReady.get()) return@LatestFrameProcessor

        try {
            val detector = yoloDetector ?: return@LatestFrameProcessor
            val classifier = convNextClassifier ?: return@LatestFrameProcessor

            val yoloDetections = detector.detect(bitmap)
            val results = yoloDetections.map { (bbox, _) -> DetectionResult(bbox) }.toMutableList()

            for (i in results.size - 1 downTo 0) {
                val result = results[i]
                val areaResult = result.bbox.width() * result.bbox.height()
                val ratio = areaResult / areaYoloInput
                if (ratio <= 0.05 || ratio >= 0.5) results.removeAt(i)
            }

            runOnUiThread {
                if (yoloDetections.isNotEmpty()) {
                    statusText.text = "Analizando imagen..."
                } else {
                    statusText.text = getString(R.string.cto_models_loaded)
                }
            }

            for ((bbox, yoloConf) in yoloDetections) {
                startScanningUI()
                val (label, convConf, boxType) = classifier.classify(bitmap, bbox)
                if (convConf >= 0.85 && label != null && boxType != null) {
                    stopScanningUI()
                    waitingForUser = true
                    val photoFile = PhotoSaver.save(this@CtoScanActivity, bitmap, rut, boxType, convConf, yoloConf)
                    pendingPhotoPath = photoFile?.absolutePath
                    runOnUiThread { showPeloDialog(label, boxType) }
                    return@LatestFrameProcessor
                }
            }

            if (yoloDetections.isEmpty()) {
                stopScanningUI()
                return@LatestFrameProcessor
            }
        } catch (_: Exception) {
            // Inference errors son intermitentes; ignorar frame
        }
    }

    private val cameraPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) startCamera()
        else statusText.text = getString(R.string.cto_camera_permission_required)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_cto_scan)

        // RUT viene del Intent (lanzado desde Flutter/CREABOX)
        rut = intent.getStringExtra("RUT_TECNICO") ?: ""

        scanningText = findViewById(R.id.scanningText)
        previewView   = findViewById(R.id.previewView)
        statusText    = findViewById(R.id.statusText)
        overlayView   = findViewById(R.id.overlayView)

        // El rutValue sigue existente en el layout pero oculto (visibility=gone)
        // No necesitamos actualizarlo porque no se muestra al usuario.

        // Botón cerrar (X): vuelve a CREABOX
        val closeButton = findViewById<ImageButton>(R.id.closeButton)
        closeButton.setOnClickListener { finish() }

        // Botón Volver al inicio: cancela el scan y regresa a Flutter home
        findViewById<Button>(R.id.volverInicioScanButton).setOnClickListener {
            val intent = Intent(
                this,
                com.creacionestecnologicas.agente_desconexiones.MainActivity::class.java
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            intent.putExtra("CTO_CANCELLED", true)
            startActivity(intent)
        }

        try {
            modelManager = OnnxModelManager(this)
        } catch (e: Exception) {
            statusText.text = "Error init IA: ${e.javaClass.simpleName}"
            android.util.Log.e("CtoScanActivity", "OnnxModelManager constructor failed", e)
            return
        }

        inferenceExecutor.execute {
            try {
                modelManager.initialize()
                yoloDetector = YoloDetector(
                    modelManager.yoloSession!!,
                    modelManager.yoloInputWidth,
                    modelManager.yoloInputHeight,
                )
                convNextClassifier = ConvNextClassifier(modelManager.convnextSession!!)
                modelsReady.set(true)
                runOnUiThread { statusText.text = getString(R.string.cto_models_loaded) }
            } catch (e: Exception) {
                android.util.Log.e("CtoScanActivity", "Model load failed", e)
                runOnUiThread { statusText.text = getString(R.string.cto_model_load_error) + ": ${e.javaClass.simpleName}" }
            }
        }

        if (hasCameraPermission()) startCamera()
        else cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
    }

    private fun startCamera() {
        try {
            val cameraProviderFuture = ProcessCameraProvider.getInstance(this)
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            cameraProviderFuture.addListener({
                try {
                    val cameraProvider = cameraProviderFuture.get()
                    val preview = Preview.Builder().build().also {
                        it.setSurfaceProvider(previewView.surfaceProvider)
                    }
                    val imageAnalysis = ImageAnalysis.Builder()
                        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                        .build()
                    imageAnalysis.setAnalyzer(cameraExecutor) { imageProxy ->
                        try {
                            val bitmap = imageProxy.toBitmap()
                            val rotation = imageProxy.imageInfo.rotationDegrees
                            imageProxy.close()
                            val rotatedBitmap = if (rotation != 0) {
                                val rotated = rotateBitmap(bitmap, rotation)
                                bitmap.recycle()
                                rotated
                            } else bitmap
                            latestFrameProcessor.submit(rotatedBitmap)
                        } catch (e: Exception) {
                            android.util.Log.e("CtoScanActivity", "Frame analysis error", e)
                        }
                    }
                    cameraProvider.unbindAll()
                    cameraProvider.bindToLifecycle(this, CameraSelector.DEFAULT_BACK_CAMERA, preview, imageAnalysis)
                } catch (e: Exception) {
                    android.util.Log.e("CtoScanActivity", "Camera bind failed", e)
                    runOnUiThread { statusText.text = "Error cámara: ${e.javaClass.simpleName}" }
                }
            }, ContextCompat.getMainExecutor(this))
        } catch (e: Exception) {
            android.util.Log.e("CtoScanActivity", "startCamera failed", e)
            statusText.text = "Error iniciando cámara: ${e.javaClass.simpleName}"
        }
    }

    private fun rotateBitmap(bitmap: Bitmap, degrees: Int): Bitmap {
        val matrix = Matrix().apply { postRotate(degrees.toFloat()) }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    }

    private fun hasCameraPermission() = ContextCompat.checkSelfPermission(
        this, Manifest.permission.CAMERA
    ) == PackageManager.PERMISSION_GRANTED

    override fun onDestroy() {
        super.onDestroy()
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        cameraExecutor.shutdown()
        inferenceExecutor.shutdown()
    }

    private fun startScanningUI() {
        runOnUiThread {
            scanningText.visibility = View.VISIBLE
            scanningAnimator?.cancel()
            scanningAnimator = ObjectAnimator.ofFloat(scanningText, "alpha", 1f, 0.2f).apply {
                duration = 500
                repeatMode = ValueAnimator.REVERSE
                repeatCount = ValueAnimator.INFINITE
                start()
            }
        }
    }

    private fun stopScanningUI() {
        runOnUiThread {
            scanningAnimator?.cancel()
            scanningAnimator = null
            scanningText.visibility = View.GONE
            scanningText.alpha = 1f
        }
    }

    fun showPeloDialog(label: String, boxType: String) {
        AlertDialog.Builder(this)
            .setTitle("Se detectó caja tipo $label")
            .setPositiveButton("Confirmar") { _, _ ->
                waitingForUser = false
                val photoPath = pendingPhotoPath
                pendingPhotoPath = null
                if (photoPath != null) {
                    val file = File(photoPath)
                    if (file.exists()) PhotoUploadManager.enqueueUpload(this, file, boxType)
                }
                val intent = Intent(this, CtoResultsActivity::class.java)
                intent.putExtra("BOX_TYPE", boxType)
                intent.putExtra("RUT", rut)
                startActivity(intent)
            }
            .setNegativeButton("Reescanear") { dialog, _ ->
                dialog.dismiss()
                waitingForUser = false
                pendingPhotoPath?.let { File(it).delete() }
                pendingPhotoPath = null
            }
            .setCancelable(false)
            .show()
    }
}

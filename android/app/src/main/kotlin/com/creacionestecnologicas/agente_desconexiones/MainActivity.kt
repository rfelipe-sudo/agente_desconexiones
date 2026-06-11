package com.creacionestecnologicas.agente_desconexiones

import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.karimpichara.turingandroid.CtoScanActivity
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {

    private val CTO_CHANNEL      = "com.creacionestecnologicas.agente_desconexiones/cto_scan"
    private val LAUNCHER_CHANNEL = "com.creacionestecnologicas.agente_desconexiones/app_launcher"
    private val SOUND_CHANNEL    = "com.creacionestecnologicas.agente_desconexiones/sound"
    private val NAV_CHANNEL      = "com.creacionestecnologicas.agente_desconexiones/navigation"

    private var navChannel: MethodChannel? = null
    private var launcherChannel: MethodChannel? = null

    // Result de Flutter pendiente: se responde en onResume cuando el scanner cierre.
    private var pendingCtoResult: MethodChannel.Result? = null

    private var llegadaPlayer: MediaPlayer? = null

    companion object {
        private const val REQUEST_APP_TECNICO = 9911
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        navChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NAV_CHANNEL)
        deliverNotificationRoute(intent)

        // ── Canal CTO Scan (turing) ──────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CTO_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openCtoScan" -> {
                        val rut = call.argument<String>("rut") ?: ""
                        val intent = Intent(this, CtoScanActivity::class.java)
                        intent.putExtra("RUT_TECNICO", rut)
                        pendingCtoResult = result
                        startActivity(intent)
                        // Responderemos en onResume() cuando el scanner cierre.
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Canal App Launcher (App Técnicos) ────────────────────────────────
        launcherChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LAUNCHER_CHANNEL)
        launcherChannel!!
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isInstalled" -> {
                        val pkg = call.arguments as? String ?: ""
                        val installed = try {
                            packageManager.getPackageInfo(pkg, 0)
                            true
                        } catch (e: PackageManager.NameNotFoundException) {
                            false
                        }
                        result.success(installed)
                    }
                    "launchApp" -> {
                        val pkg = call.arguments as? String ?: ""
                        val intent = packageManager.getLaunchIntentForPackage(pkg)
                        if (intent != null) {
                            startActivity(intent)
                            result.success(null)
                        } else {
                            result.error("NOT_FOUND", "App no instalada: $pkg", null)
                        }
                    }
                    "installApkFromPath" -> {
                        // Flutter ya copió el APK a un archivo temporal y pasa la ruta absoluta.
                        val filePath = call.arguments as? String ?: ""
                        try {
                            val apkFile = File(filePath)
                            val uri = FileProvider.getUriForFile(
                                this,
                                "$packageName.fileprovider",
                                apkFile
                            )
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("INSTALL_ERROR", e.message, null)
                        }
                    }
                    "openAppTecnicoWebView" -> {
                        val url: String
                        val username: String?
                        val password: String?
                        when (val args = call.arguments) {
                            is String -> {
                                url = args
                                username = null
                                password = null
                            }
                            is Map<*, *> -> {
                                url = args["url"] as? String ?: ""
                                username = args["username"] as? String
                                password = args["password"] as? String
                            }
                            else -> {
                                result.error("INVALID", "Argumentos inválidos", null)
                                return@setMethodCallHandler
                            }
                        }
                        if (url.isBlank()) {
                            result.error("INVALID", "URL vacía", null)
                            return@setMethodCallHandler
                        }
                        val intent = Intent(this, AppTecnicoActivity::class.java)
                        intent.putExtra(AppTecnicoActivity.EXTRA_URL, url)
                        if (!username.isNullOrBlank() && !password.isNullOrBlank()) {
                            intent.putExtra(AppTecnicoActivity.EXTRA_AUTO_USERNAME, username)
                            intent.putExtra(AppTecnicoActivity.EXTRA_AUTO_PASSWORD, password)
                        }
                        startActivityForResult(intent, REQUEST_APP_TECNICO)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Canal de sonido nativo (MediaPlayer sobre res/raw) ──────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SOUND_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playAlerta" -> {
                        MaterialAlertNotifier.playAlertaFromDart(this)
                        result.success(null)
                    }
                    "stopAlerta" -> {
                        MaterialAlertNotifier.stopAlerta()
                        result.success(null)
                    }
                    "cancelMaterialNotificacion" -> {
                        MaterialAlertNotifier.cancelMaterialNotification(this)
                        result.success(null)
                    }
                    "playAyuda" -> {
                        MaterialAlertNotifier.playAyudaFromDart(this)
                        result.success(null)
                    }
                    "playMaterialLlegada" -> {
                        try {
                            llegadaPlayer?.stop()
                            llegadaPlayer?.release()
                            val mp = MediaPlayer.create(this, R.raw.material_llegada)
                            llegadaPlayer = mp
                            mp?.setOnCompletionListener {
                                it.release()
                                if (llegadaPlayer === it) llegadaPlayer = null
                            }
                            mp?.start()
                        } catch (_: Exception) {}
                        result.success(null)
                    }
                    "playComunicado" -> {
                        MaterialAlertNotifier.playComunicadoFromDart(this)
                        result.success(null)
                    }
                    "isBatteryOptimizationIgnored" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val pm = getSystemService(POWER_SERVICE) as PowerManager
                            result.success(pm.isIgnoringBatteryOptimizations(packageName))
                        } else {
                            result.success(true)
                        }
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val pm = getSystemService(POWER_SERVICE) as PowerManager
                            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                                val intent = Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:$packageName")
                                )
                                startActivity(intent)
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Cuando el usuario pulsa "Volver al inicio" desde el scanner nativo,
    // el Intent lleva CTO_CANCELLED=true. Limpiamos el resultado pendiente
    // aquí para que onResume() no lo procese como un scan completado.
    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra("CTO_CANCELLED", false)) {
            pendingCtoResult?.error("CTO_CANCELLED", "Scan cancelado por el usuario", null)
            pendingCtoResult = null
        }
        deliverNotificationRoute(intent)
    }

    private fun deliverNotificationRoute(intent: android.content.Intent?) {
        if (intent == null) return

        val accion = intent.getStringExtra("creabox_accion")
        if (accion == "comunicado_creabox") {
            val comunicadoId = intent.getStringExtra("creabox_comunicado_id")
            intent.removeExtra("creabox_accion")
            intent.removeExtra("creabox_comunicado_id")
            navChannel?.invokeMethod(
                "openComunicado",
                mapOf("comunicado_id" to (comunicadoId ?: "")),
            )
            return
        }

        val route = intent.getStringExtra("creabox_route") ?: return
        val solicitudId = intent.getStringExtra("creabox_solicitud_id")
        val ticketId = intent.getStringExtra("creabox_ticket_id")
        intent.removeExtra("creabox_route")
        intent.removeExtra("creabox_solicitud_id")
        intent.removeExtra("creabox_ticket_id")
        val extras = mutableMapOf<String, String>("route" to route)
        solicitudId?.let { extras["solicitud_id"] = it }
        ticketId?.let { extras["ticket_id"] = it }
        if (extras.size > 1) {
            navChannel?.invokeMethod("openRoute", extras)
        } else {
            navChannel?.invokeMethod("openRoute", route)
        }
    }

    override fun onPause() {
        AppVisibility.activityResumed = false
        super.onPause()
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_APP_TECNICO) return
        if (resultCode == AppTecnicoActivity.RESULT_CREDENTIALS_ERROR) {
            launcherChannel?.invokeMethod("credentialsError", null)
        } else {
            launcherChannel?.invokeMethod("appTecnicoClosed", null)
        }
    }

    // Cuando MainActivity vuelve al primer plano (scanner cerrado), notificamos a Flutter.
    override fun onResume() {
        super.onResume()
        AppVisibility.activityResumed = true
        val res = pendingCtoResult ?: return
        pendingCtoResult = null
        // Buscar la imagen que el scanner haya guardado en los últimos 5 min.
        res.success(findLatestScanImage())
    }

    /// Retorna la ruta absoluta de la imagen más reciente creada por el scanner
    /// en los directorios del app (cache, files, external). Null si no encuentra.
    private fun findLatestScanImage(): String? {
        val cutoffMs = System.currentTimeMillis() - 5 * 60 * 1000L
        val imageExts = setOf("jpg", "jpeg", "png")
        val dirs = listOfNotNull(cacheDir, filesDir, externalCacheDir, getExternalFilesDir(null))

        var bestFile: File? = null
        var bestTime = cutoffMs

        for (dir in dirs) {
            if (!dir.exists()) continue
            dir.walkTopDown().maxDepth(6).forEach { file ->
                if (file.isFile &&
                    file.extension.lowercase() in imageExts &&
                    file.lastModified() > bestTime) {
                    bestTime = file.lastModified()
                    bestFile = file
                }
            }
        }
        return bestFile?.absolutePath
    }
}

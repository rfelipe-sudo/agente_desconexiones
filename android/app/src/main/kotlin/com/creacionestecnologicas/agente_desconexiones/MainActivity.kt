package com.creacionestecnologicas.agente_desconexiones

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.karimpichara.turingandroid.CtoScanActivity

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.creacionestecnologicas.agente_desconexiones/cto_scan"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openCtoScan" -> {
                    val rut = call.argument<String>("rut") ?: ""
                    val intent = Intent(this, CtoScanActivity::class.java)
                    intent.putExtra("RUT_TECNICO", rut)
                    startActivity(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}

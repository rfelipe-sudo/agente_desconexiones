package com.creacionestecnologicas.agente_desconexiones

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.PowerManager
import android.util.Log

/**
 * Recibe el broadcast FCM y dispara el sonido nativo antes del handler Flutter.
 */
class MaterialFcmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val extras = intent.extras ?: return
        val pending = goAsync()
        val appContext = context.applicationContext

        Thread {
            var wakeLock: PowerManager.WakeLock? = null
            try {
                val pm = appContext.getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "creabox:material_fcm"
                ).apply { acquire(15_000L) }

                Log.d(TAG, "broadcast FCM recibido")
                MaterialAlertNotifier.handleFromBundle(appContext, extras)
            } catch (e: Exception) {
                Log.w(TAG, "error en receiver: ${e.message}")
            } finally {
                try {
                    if (wakeLock?.isHeld == true) wakeLock.release()
                } catch (_: Exception) {
                }
                pending.finish()
            }
        }.start()
    }

    companion object {
        private const val TAG = "CreaboxFCM"
    }
}

package com.creacionestecnologicas.agente_desconexiones

import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import androidx.multidex.MultiDexApplication

/**
 * Application personalizada que:
 * 1. Instala MultiDex (requerido por ONNX Runtime / CameraX).
 * 2. Crea los canales de notificación Android con sus sonidos personalizados,
 *    de modo que las notificaciones FCM que lleguen incluso con la app cerrada
 *    usen el sonido correcto desde el primer disparo.
 */
class CreaboxApplication : MultiDexApplication() {

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            crearCanalesNotificacion()
        }
    }

    private fun crearCanalesNotificacion() {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager

        val soundUri = Uri.parse(
            "android.resource://$packageName/raw/alerta_urgente"
        )
        val audioAttr = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        // ── Canal material ────────────────────────────────────────────────────
        // Borramos TODOS los canales anteriores + el actual antes de recrear:
        // Android ignora createNotificationChannel() en canales ya existentes,
        // así que hay que borrarlos primero para garantizar el sonido correcto.
        manager.deleteNotificationChannel("mat_alertas")
        manager.deleteNotificationChannel("mat_alertas_2")
        manager.deleteNotificationChannel("mat_alertas_3")
        val canalMaterial = NotificationChannel(
            "mat_alertas_3",
            "Alertas de material",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Alertas de solicitudes de material entre técnicos"
            setSound(soundUri, audioAttr)
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 300, 200, 300)
        }
        manager.createNotificationChannel(canalMaterial)

        // ── Canal alertas operacionales ───────────────────────────────────────
        val canalAlertas = NotificationChannel(
            "alertas",
            "Alertas operacionales",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Alertas de bloqueos y operaciones"
        }
        manager.createNotificationChannel(canalAlertas)
    }
}

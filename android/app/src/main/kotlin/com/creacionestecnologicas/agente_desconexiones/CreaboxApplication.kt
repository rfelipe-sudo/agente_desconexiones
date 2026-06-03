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

        // ── Limpiar canales obsoletos (v1–v5) ─────────────────────────────────
        // Android congela las propiedades al crear el canal; si un APK anterior
        // lo creó sin USAGE_ALARM el sonido nunca suena. Eliminar y recrear con
        // un ID nuevo es la única solución.
        manager.deleteNotificationChannel("mat_alertas")
        manager.deleteNotificationChannel("mat_alertas_2")
        manager.deleteNotificationChannel("mat_alertas_3")
        manager.deleteNotificationChannel("mat_alertas_4")
        manager.deleteNotificationChannel("mat_alertas_5")

        // ── Canal material v6 (permanente) ────────────────────────────────────
        // USAGE_ALARM: el sonido suena incluso con el teléfono en modo vibración.
        val audioAttrAlarma = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        val canalMaterial = NotificationChannel(
            "mat_alertas_6",
            "Alertas de material",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Alertas de solicitudes de material entre técnicos"
            setSound(soundUri, audioAttrAlarma)
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

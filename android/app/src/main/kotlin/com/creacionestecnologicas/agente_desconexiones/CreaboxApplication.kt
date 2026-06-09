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
        manager.deleteNotificationChannel("mat_alertas_6")

        // ── Canal material v7 (permanente) ────────────────────────────────────
        // USAGE_ALARM: el sonido suena incluso con el teléfono en modo vibración.
        // Nuevo ID para evitar canales congelados sin sonido en dispositivos viejos.
        val audioAttrAlarma = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        val canalMaterial = NotificationChannel(
            "mat_alertas_7",
            "Alertas de material",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Alertas de solicitudes de material y traspasos de bodega"
            setSound(soundUri, audioAttrAlarma)
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 300, 200, 300)
            setBypassDnd(true)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(canalMaterial)

        val mushroomUri = Uri.parse(
            "android.resource://$packageName/raw/comunicado_mushroom"
        )
        val canalComunicados = NotificationChannel(
            "comunicados_creabox_1",
            "Comunicados CREABOX",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Comunicados masivos y personalizados con confirmación de lectura"
            setSound(mushroomUri, audioAttrAlarma)
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 200, 150, 200)
            setBypassDnd(true)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(canalComunicados)

        val ayudaMarioUri = Uri.parse(
            "android.resource://$packageName/raw/ayuda_supervisor_mario"
        )
        val canalAyudaSupervisor = NotificationChannel(
            "ayuda_supervisor_1",
            "Ayuda en terreno — supervisor",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Solicitudes de ayuda de técnicos en terreno"
            setSound(ayudaMarioUri, audioAttrAlarma)
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 400, 200, 400)
            setBypassDnd(true)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(canalAyudaSupervisor)

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

package com.creacionestecnologicas.agente_desconexiones

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Bundle
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.RemoteMessage

/**
 * Alerta sonora + notificación para solicitudes de material / guías bodega.
 * Se ejecuta en el hilo FCM nativo (funciona con app en segundo plano o cerrada).
 */
object MaterialAlertNotifier {

    private const val CHANNEL_ID = "mat_alertas_7"
    private const val CHANNEL_COMUNICADOS = "comunicados_creabox_1"
    private const val CHANNEL_AYUDA_SUPERVISOR = "ayuda_supervisor_1"

    private val SOUND_ACTIONS = setOf(
        "solicitud_material",
        "guia_firmada_bodega",
        "sol_comb_flota",
        "sol_comb_jefe_ops",
        "traspaso_bodega",
        "material_sin_respuesta",
    )

    /** Bodeguero: siempre alertar (aunque la UI esté visible). */
    private val BODEGA_ACTIONS = setOf(
        "guia_firmada_bodega",
        "traspaso_bodega",
    )

    /** Supervisor ayuda en terreno: siempre alertar (2º plano / app cerrada). */
    private val SUPERVISOR_AYUDA_ACTIONS = setOf(
        "solicitud_ayuda",
    )

    @Volatile
    private var alertaPlayer: MediaPlayer? = null

    @Volatile
    private var comunicadoPlayer: MediaPlayer? = null

    @Volatile
    private var ayudaPlayer: MediaPlayer? = null

    @Volatile
    private var lastPlayMs = 0L

    @Volatile
    private var lastComunicadoPlayMs = 0L

    @Volatile
    private var lastAyudaPlayMs = 0L

    private const val PLAY_DEBOUNCE_MS = 2500L

    fun handle(context: Context, message: RemoteMessage) {
        handleData(
            context,
            message.data,
            message.notification?.title,
            message.notification?.body,
        )
    }

    /** Parsea extras FCM cuando [RemoteMessage] no está disponible (broadcast). */
    fun handleFromBundle(context: Context, extras: Bundle) {
        val data = extractFcmData(extras)
        if (data.isEmpty()) return
        handleData(context, data, data["title"], data["body"] ?: data["descripcion"])
    }

    private fun extractFcmData(extras: Bundle): Map<String, String> {
        val out = mutableMapOf<String, String>()
        for (key in extras.keySet()) {
            if (key.startsWith("google.") || key == "from" || key == "collapse_key") continue
            extras.getString(key)?.let { out[key] = it }
        }
        return out
    }

    private fun handleData(
        context: Context,
        data: Map<String, String>,
        notificationTitle: String?,
        notificationBody: String?,
    ) {
        val accion = data["accion"] ?: return

        if (accion == "comunicado_creabox") {
            if (!AppVisibility.isUiVisible()) {
                Log.d(TAG, "comunicado_creabox → mushroom (background)")
                playComunicado(context.applicationContext)
                val title = data["title"] ?: notificationTitle ?: "Comunicado CREABOX"
                val body = data["body"]
                    ?: data["descripcion"]
                    ?: notificationBody
                    ?: "Nuevo comunicado para leer y firmar"
                showComunicadoNotification(
                    context.applicationContext,
                    title,
                    body,
                    data,
                )
            } else {
                Log.d(TAG, "comunicado_creabox → skip native (Dart foreground)")
            }
            return
        }

        if (accion == "ayuda_cancelada") {
            Log.d(TAG, "ayuda_cancelada → notificación supervisor")
            val title = data["title"]
                ?: notificationTitle
                ?: "Solicitud de ayuda cancelada"
            val body = data["body"]
                ?: data["descripcion"]
                ?: notificationBody
                ?: "Un técnico canceló su solicitud de ayuda"
            showAyudaSupervisorNotification(
                context.applicationContext,
                title,
                body,
                data,
                49,
            )
            return
        }

        if (accion == "solicitud_ayuda" || accion == "material_sin_respuesta") {
            // Siempre alertar: data_only FCM en background/cerrada + Realtime en foreground.
            Log.d(TAG, "$accion → mario (supervisor, siempre)")
            playAyudaSupervisor(context.applicationContext)
            val title = data["title"]
                ?: notificationTitle
                ?: defaultTitle(accion)
            val body = data["body"]
                ?: data["descripcion"]
                ?: notificationBody
                ?: defaultBody(accion)
            showAyudaSupervisorNotification(
                context.applicationContext,
                title,
                body,
                data,
                if (accion == "material_sin_respuesta") 46 else 48,
            )
            return
        }

        if (accion !in SOUND_ACTIONS) return

        val esBodega = accion in BODEGA_ACTIONS
        val esSupervisorAyuda = accion in SUPERVISOR_AYUDA_ACTIONS

        // Técnicos: si la UI está visible, Dart reproduce el sonido en foreground.
        // Bodeguero / supervisor ayuda: SIEMPRE alertar en 2º plano o app cerrada.
        if (!esBodega && !esSupervisorAyuda && AppVisibility.isUiVisible()) {
            Log.d(TAG, "skip native alert (UI visible) accion=$accion")
            return
        }

        Log.d(TAG, "playAlerta accion=$accion esBodega=$esBodega (background/killed/foreground-bodega)")
        playAlerta(context.applicationContext)

        val title = data["title"]
            ?: notificationTitle
            ?: defaultTitle(accion)
        val body = data["body"]
            ?: data["descripcion"]
            ?: notificationBody
            ?: defaultBody(accion)

        val notifId = when (accion) {
            "solicitud_material" -> 42
            "solicitud_atendida" -> 42
            "guia_firmada_bodega" -> 45
            "traspaso_bodega" -> 44
            "material_sin_respuesta" -> 46
            else -> 43
        }

        showNotification(context.applicationContext, notifId, title, body, accion, data)
    }

    /** Expuesto para MethodChannel — mismo audio USAGE_ALARM que FCM en background. */
    fun playAlertaFromDart(context: Context) {
        playAlerta(context.applicationContext)
    }

    fun playComunicadoFromDart(context: Context) {
        playComunicado(context.applicationContext)
    }

    fun playAyudaFromDart(context: Context) {
        playAyudaSupervisor(context.applicationContext)
    }

    fun stopAlerta() {
        try {
            alertaPlayer?.stop()
            alertaPlayer?.release()
        } catch (_: Exception) {
        } finally {
            alertaPlayer = null
        }
    }

    private fun defaultTitle(accion: String): String = when (accion) {
        "solicitud_material" -> "¡Solicitud de material!"
        "guia_firmada_bodega" -> "Guía firmada — revisar bodega"
        "traspaso_bodega" -> "Nuevo traspaso en bodega"
        "material_sin_respuesta" -> "Material sin atender"
        else -> "¡Solicitud de flota!"
    }

    private fun defaultBody(accion: String): String = when (accion) {
        "solicitud_material" -> "Un colega necesita material"
        "guia_firmada_bodega" -> "Nueva guía pendiente de confirmar"
        "traspaso_bodega" -> "Hay un traspaso pendiente de aprobación"
        "material_sin_respuesta" -> "Un técnico de tu equipo lleva 10 min sin respuesta"
        else -> "Nueva solicitud de flota"
    }

    /** Sonido Mario para ayuda en terreno al supervisor. */
    fun playAyudaSupervisor(context: Context) {
        val now = System.currentTimeMillis()
        if (now - lastAyudaPlayMs < PLAY_DEBOUNCE_MS) return
        lastAyudaPlayMs = now

        try {
            ayudaPlayer?.stop()
            ayudaPlayer?.release()
            val mp = MediaPlayer.create(context, R.raw.ayuda_supervisor_mario) ?: return
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            ayudaPlayer = mp
            mp.setOnCompletionListener {
                it.release()
                if (ayudaPlayer === it) ayudaPlayer = null
            }
            mp.start()
        } catch (_: Exception) {
        }
    }

    /** Sonido de hongo para comunicados (foreground Dart / background FCM). */
    fun playComunicado(context: Context) {
        val now = System.currentTimeMillis()
        if (now - lastComunicadoPlayMs < PLAY_DEBOUNCE_MS) return
        lastComunicadoPlayMs = now

        try {
            comunicadoPlayer?.stop()
            comunicadoPlayer?.release()
            val mp = MediaPlayer.create(context, R.raw.comunicado_mushroom) ?: return
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            comunicadoPlayer = mp
            mp.setOnCompletionListener {
                it.release()
                if (comunicadoPlayer === it) comunicadoPlayer = null
            }
            mp.start()
        } catch (_: Exception) {
        }
    }

    /** MediaPlayer con USAGE_ALARM — suena aunque el teléfono esté en vibración. */
    fun playAlerta(context: Context) {
        val now = System.currentTimeMillis()
        if (now - lastPlayMs < PLAY_DEBOUNCE_MS) return
        lastPlayMs = now

        var wakeLock: PowerManager.WakeLock? = null
        try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "creabox:alerta_sonora"
            ).apply { acquire(20_000L) }

            alertaPlayer?.stop()
            alertaPlayer?.release()
            val mp = MediaPlayer.create(context, R.raw.alerta_urgente) ?: return
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            alertaPlayer = mp
            mp.setOnCompletionListener {
                it.release()
                if (alertaPlayer === it) alertaPlayer = null
                try {
                    if (wakeLock?.isHeld == true) wakeLock.release()
                } catch (_: Exception) {
                }
            }
            mp.start()
        } catch (_: Exception) {
            try {
                if (wakeLock?.isHeld == true) wakeLock.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun showComunicadoNotification(
        context: Context,
        title: String,
        body: String,
        data: Map<String, String>,
    ) {
        try {
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("creabox_accion", "comunicado_creabox")
                data["comunicado_id"]?.let { putExtra("creabox_comunicado_id", it) }
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                47,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            val builder = NotificationCompat.Builder(context, CHANNEL_COMUNICADOS)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setAutoCancel(true)
                .setOnlyAlertOnce(false)
                .setContentIntent(pendingIntent)

            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(47, builder.build())
        } catch (_: Exception) {
        }
    }

    private fun showAyudaSupervisorNotification(
        context: Context,
        title: String,
        body: String,
        data: Map<String, String>,
        notifId: Int = 48,
    ) {
        try {
            val route = if (data["accion"] == "material_sin_respuesta") {
                "/solicitudes-material-supervisor"
            } else {
                "/solicitudes-ayuda"
            }
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("creabox_route", route)
                data["ticket_id"]?.let { putExtra("creabox_ticket_id", it) }
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                notifId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            val builder = NotificationCompat.Builder(context, CHANNEL_AYUDA_SUPERVISOR)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setAutoCancel(true)
                .setOnlyAlertOnce(false)
                .setContentIntent(pendingIntent)

            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(notifId, builder.build())
        } catch (_: Exception) {
        }
    }

    private fun showNotification(
        context: Context,
        id: Int,
        title: String,
        body: String,
        accion: String,
        data: Map<String, String>,
    ) {
        try {
            val route = when (accion) {
                "solicitud_material", "solicitud_cancelada", "solicitud_atendida" -> "/solicitud-material"
                "guia_firmada_bodega", "traspaso_bodega" -> "/bodega"
                "material_sin_respuesta" -> "/solicitudes-material-supervisor"
                "solicitud_ayuda" -> "/solicitudes-ayuda"
                else -> null
            }

            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                if (route != null) putExtra("creabox_route", route)
                data["solicitud_id"]?.let { putExtra("creabox_solicitud_id", it) }
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                id,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setAutoCancel(true)
                .setOnlyAlertOnce(false)
                .setContentIntent(pendingIntent)
            // El sonido lo define el canal mat_alertas_7 (USAGE_ALARM + alerta_urgente).

            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(id, builder.build())
        } catch (_: Exception) {
        }
    }

    /** Cancela la notificación de solicitud de material (id 42). */
    fun cancelMaterialNotification(context: Context) {
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(42)
        } catch (_: Exception) {
        }
    }

    private const val TAG = "CreaboxFCM"
}

package com.creacionestecnologicas.agente_desconexiones

import android.util.Log
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

/**
 * Extiende el servicio del plugin Flutter. Reproduce alerta_urgente en background
 * y delega el reenvío a Dart vía [FlutterFirebaseMessagingService.onMessageReceived].
 */
class CreaboxFirebaseMessagingService : FlutterFirebaseMessagingService() {

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        Log.d(TAG, "onMessageReceived accion=${remoteMessage.data["accion"]} data=${remoteMessage.data}")
        MaterialAlertNotifier.handle(this, remoteMessage)
        super.onMessageReceived(remoteMessage)
    }

    companion object {
        private const val TAG = "CreaboxFCM"
    }
}

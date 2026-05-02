import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificacionService {
  static final NotificacionService _instance = NotificacionService._internal();
  factory NotificacionService() => _instance;
  NotificacionService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  Future<void> inicializar() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        print('📱 Notificación tocada: ${response.payload}');
      },
    );

    // Solicitar permisos en Android 13+
    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    print('✅ Servicio de notificaciones inicializado');
  }

  /// Notificación de alerta CTO - SONIDO FUERTE + REPETICIÓN
  Future<void> mostrarAlertaCTO({
    required String ot,
    required String tecnico,
    required List<String> puertosAfectados,
  }) async {
    final puertosTexto = puertosAfectados.join(', ');
    
    // Canal de MÁXIMA PRIORIDAD con sonido
    final androidDetails = AndroidNotificationDetails(
      'alertas_cto_urgentes',
      'Alertas CTO Urgentes',
      channelDescription: 'Alertas de desconexión en CTO - URGENTE',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      ledColor: const Color.fromARGB(255, 255, 0, 0),
      ledOnMs: 1000,
      ledOffMs: 500,
      fullScreenIntent: true,  // Aparece sobre todo
      ongoing: true,  // No se puede deslizar para quitar
      autoCancel: false,  // No desaparece al tocar
      ticker: '🚨 ALERTA CTO - $ot',
      icon: '@mipmap/ic_launcher',
      // Sonido por defecto del sistema (si quieres sonido personalizado, agrega alarm.mp3 en android/app/src/main/res/raw/)
      sound: null,  // Usa sonido por defecto del sistema
    );
    
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.critical,
    );
    
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    // ID único basado en OT para poder actualizarla
    final notificationId = ot.hashCode.abs() % 100000;
    
    await _notifications.show(
      notificationId,
      '🚨 ALERTA CTO - $ot',
      'Desconexión en $puertosTexto\nTécnico: $tecnico',
      details,
      payload: ot,
    );
    
    print('🔔 [Notificación] Alerta CTO mostrada con sonido: $ot');
  }

  /// Cancelar notificación cuando se atiende
  Future<void> cancelarAlertaCTO(String ot) async {
    final notificationId = ot.hashCode.abs() % 100000;
    await _notifications.cancel(notificationId);
    print('✅ [Notificación] Alerta CTO cancelada: $ot');
  }

  Future<void> mostrarAlertaFraude({
    required String ot,
    required String tipo,
    required String mensaje,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'alertas_fraude',
      'Alertas Fraude',
      channelDescription: 'Alertas de actividad sospechosa',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
    );

    const details = NotificationDetails(android: androidDetails);

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      '⚠️ ALERTA: $tipo',
      'OT: $ot - $mensaje',
      details,
      payload: ot,
    );
  }
}




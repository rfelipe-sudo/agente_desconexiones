import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Servicio de notificaciones locales con sonido y vibración.
/// Funciona incluso cuando el usuario está en otra pantalla dentro de la app
/// o cuando la app está minimizada en segundo plano.
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // Canal v4: sin sonido custom para mayor compatibilidad (usa default del sistema)
  static const _channelId   = 'ayuda_terreno_v4';
  static const _channelName = 'Ayuda en Terreno';
  static const _channelDesc = 'Alertas urgentes de solicitudes de ayuda en terreno';

  // Patrón de vibración: pausa, vibra, pausa, vibra, pausa, vibra
  static final _vibracion = Int64List.fromList(
    [0, 600, 200, 600, 200, 800],
  );

  // ─────────────────────────────────────────────────────────────
  // Inicialización (llamar una vez en main.dart)
  // ─────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(initSettings);

    // Solicitar permiso POST_NOTIFICATIONS (obligatorio en Android 13+)
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    // Canal de alta importancia: sonido por defecto del sistema (más fiable)
    final channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: _vibracion,
      enableLights: true,
      ledColor: const Color(0xFFFF9500),
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
  }

  // ─────────────────────────────────────────────────────────────
  // Notificación para el SUPERVISOR — nueva solicitud recibida
  // ─────────────────────────────────────────────────────────────

  Future<void> alertaSupervisorNuevaSolicitud({
    required String tecnicoNombre,
    required String tipoAyuda,
  }) async {
    await _ensureInit();
    _vibrar();

    await _plugin.show(
      1001,
      '🆘 Nueva solicitud: $tipoAyuda',
      '$tecnicoNombre requiere apoyo inmediato',
      _detallesAndroid(fullScreen: true),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Notificación para el TÉCNICO — supervisor respondió
  // ─────────────────────────────────────────────────────────────

  Future<void> alertaTecnicoRespuesta({
    required String supervisorNombre,
    required String estado,
    int? minutosExtra,
  }) async {
    await _ensureInit();
    _vibrar();

    final (titulo, cuerpo) = switch (estado) {
      'aceptada' => (
          '✅ ¡Supervisor en camino!',
          '$supervisorNombre aceptó tu solicitud y va hacia ti',
        ),
      'rechazada' => (
          '❌ Solicitud rechazada',
          '$supervisorNombre no puede asistirte en este momento',
        ),
      'aceptada_con_tiempo' => (
          '⏳ Aceptado con demora',
          minutosExtra != null
              ? '$supervisorNombre llegará en aprox. $minutosExtra min extra'
              : '$supervisorNombre está en camino pero tomará más tiempo',
        ),
      _ => ('Respuesta recibida', 'Revisa el estado de tu solicitud'),
    };

    await _plugin.show(
      1002,
      titulo,
      cuerpo,
      _detallesAndroid(fullScreen: true),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Helpers internos
  // ─────────────────────────────────────────────────────────────

  NotificationDetails _detallesAndroid({bool fullScreen = false}) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        vibrationPattern: _vibracion,
        fullScreenIntent: fullScreen,
        ticker: 'TrazaBox — Ayuda en Terreno',
        icon: '@mipmap/ic_launcher',
        color: const Color(0xFF00E5FF),
        enableLights: true,
        ledColor: const Color(0xFFFF9500),
        ledOnMs: 500,
        ledOffMs: 300,
        ongoing: false,
      ),
    );
  }

  Future<void> _ensureInit() async {
    if (!_initialized) await init();
  }

  /// Vibración de respaldo (si las notificaciones están silenciadas)
  void _vibrar() {
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 300), HapticFeedback.heavyImpact);
    Future.delayed(const Duration(milliseconds: 600), HapticFeedback.heavyImpact);
  }

  /// Vibración para alertas — pública para llamar desde AyudaService.
  /// Funciona aunque el dispositivo esté en silencio.
  void vibrarParaAlerta() {
    _vibrar();
  }

  Future<void> cancelarTodas() => _plugin.cancelAll();

  /// Notificación genérica (ej: countdown de movimiento de materiales)
  Future<void> mostrarNotificacion({
    required String titulo,
    required String cuerpo,
  }) async {
    await _ensureInit();
    await _plugin.show(
      1003,
      titulo,
      cuerpo,
      _detallesAndroid(fullScreen: false),
    );
  }
}

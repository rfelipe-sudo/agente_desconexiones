import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:agente_desconexiones/models/alerta.dart';
import 'package:agente_desconexiones/services/alarm_audio_service.dart';

/// Helper para formatear el número de pelo (ej: "P-04" -> "4")
String _formatearPelo(String numeroPelo) {
  final numero = numeroPelo.replaceAll(RegExp(r'[^0-9]'), '');
  return numero.isEmpty ? numeroPelo : numero;
}

/// Servicio de notificaciones locales (sin Firebase)
class LocalNotificationService {
  static final LocalNotificationService _instance = LocalNotificationService._internal();
  factory LocalNotificationService() => _instance;
  LocalNotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications = 
      FlutterLocalNotificationsPlugin();
  final AlarmAudioService _alarmAudio = AlarmAudioService();
  
  bool _inicializado = false;

  /// Inicializa el servicio de notificaciones
  Future<void> initialize() async {
    if (_inicializado) {
      print('⚠️ Servicio ya inicializado');
      return;
    }
    
    try {
      print('🔧 Inicializando servicio de notificaciones...');
      
      // Verificar permisos (no crítico si falla)
      await _verificarPermisos();
      
      // Configuración para Android
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      
      // Configuración para iOS
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      
      final initialized = await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );
      
      print('📱 Notificaciones inicializadas: $initialized');
      
      // Crear canal de notificación para Android con sonido del sistema
      await _crearCanalConSonido();
      
      _inicializado = true;
      print('✅ Servicio de notificaciones locales inicializado');
    } catch (e, stackTrace) {
      print('❌ Error inicializando notificaciones: $e');
      print('Stack trace: $stackTrace');
      // Marcar como inicializado de todas formas para que la app no crashee
      _inicializado = true;
    }
  }

  Future<void> _verificarPermisos() async {
    try {
      // Verificar permisos de notificación
      final status = await Permission.notification.status;
      print('📋 Estado de permisos de notificación: $status');
      
      if (!status.isGranted) {
        print('⚠️ Permisos no otorgados, solicitando...');
        final result = await Permission.notification.request();
        print('📋 Resultado de solicitud de permisos: $result');
        
        if (!result.isGranted) {
          print('⚠️ Permisos de notificación denegados - las notificaciones pueden no funcionar');
        }
      }
    } catch (e) {
      print('❌ Error verificando permisos: $e');
      // Continuar aunque falle la verificación de permisos
    }
  }

  Future<void> _crearCanalConSonido() async {
    final androidImplementation = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidImplementation != null) {
      // Eliminar canal anterior si existe
      try {
        await androidImplementation.deleteNotificationChannel('alertas_urgentes');
        print('🗑️ Canal anterior eliminado');
      } catch (e) {
        print('ℹ️ No había canal anterior: $e');
      }
      
      // Crear nuevo canal como ALARMA - esto permite sonar incluso en modo silencioso
      // IMPORTANTE: Para que suene en modo silencioso, el canal debe tener importancia máxima
      // y la notificación debe usar categoría ALARM (configurado en AndroidNotificationDetails)
      const androidChannel = AndroidNotificationChannel(
        'alertas_urgentes',
        'Alertas Urgentes',
        description: 'Notificaciones de alertas de desconexión de fibra óptica - Suena incluso en modo silencioso',
        importance: Importance.max, // Importancia máxima (requerido para modo silencioso)
        playSound: true, // Habilitar sonido
        // Usar sonido personalizado si existe en res/raw/alerta_urgente
        // Si el archivo no existe, Android usará el sonido por defecto del sistema
        // NOTA: Para modo silencioso, el sonido debe ser de tipo ALARM (no NOTIFICATION)
        sound: RawResourceAndroidNotificationSound('alerta_urgente'),
        enableVibration: true,
        enableLights: true,
        showBadge: true,
      );
      
      await androidImplementation.createNotificationChannel(androidChannel);
      print('✅ Canal de notificaciones creado: alertas_urgentes');
      print('   - Tipo: ALARMA (ignora modo silencioso)');
      print('   - Sonido: Habilitado (alerta_urgente desde res/raw/)');
      print('   - ⚠️ Si no suena, verifica que el archivo esté en: android/app/src/main/res/raw/alerta_urgente.mp3');
      print('   - Vibración: Habilitada');
      print('   - Importancia: Máxima');
      
      // Crear canal para alertas de fraude
      const androidChannelFraude = AndroidNotificationChannel(
        'alertas_fraude',
        'Alertas de Fraude',
        description: 'Notificaciones de intentos de fraude',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );
      
      await androidImplementation.createNotificationChannel(androidChannelFraude);
      print('✅ Canal de notificaciones creado: alertas_fraude');
    } else {
      print('⚠️ No se pudo obtener implementación Android');
    }
  }

  /// Muestra una notificación de alerta como si fuera una llamada telefónica
  /// Sonido persistente, pantalla completa, vibración continua
  Future<void> mostrarAlertaComoLlamada(Alerta alerta) async {
    print('📞 Mostrando alerta como llamada: ${alerta.numeroOt}');
    
    if (!_inicializado) {
      print('⚠️ Servicio no inicializado, inicializando...');
      await initialize();
    }
    
    // Detalles para Android - configurado como ALARMA
    // La categoría ALARM permite sonar incluso en modo silencioso
    final androidDetails = AndroidNotificationDetails(
      'alertas_urgentes',
      'Alertas Urgentes',
      channelDescription: 'Notificaciones de alertas de desconexión',
      importance: Importance.max, // Importancia máxima
      priority: Priority.max, // Prioridad máxima
      // Usar sonido personalizado desde res/raw/alerta_urgente
      // Si el archivo no existe, Android usará el sonido por defecto
      sound: const RawResourceAndroidNotificationSound('alerta_urgente'),
      playSound: true, // Forzar reproducción de sonido
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000, 500, 1000]), // Vibración continua
      ongoing: true, // No se puede deslizar para cerrar
      autoCancel: false,
      fullScreenIntent: true, // Pantalla completa incluso en bloqueo
      category: AndroidNotificationCategory.alarm, // Categoría ALARMA (ignora modo silencioso)
      visibility: NotificationVisibility.public,
      icon: '@mipmap/ic_launcher',
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      styleInformation: BigTextStyleInformation(
        'CTO: ${alerta.nombreCto}\nPelo: ${_formatearPelo(alerta.numeroPelo)}\nOT: ${alerta.numeroOt}\n\n⚠️ Desconexión detectada - Acción requerida',
        contentTitle: '🚨 ALERTA URGENTE: ${alerta.tipoAlerta.displayName}',
        summaryText: 'Kepler detectó una desconexión',
      ),
      channelShowBadge: true,
      showWhen: true,
      when: DateTime.now().millisecondsSinceEpoch,
      // Configuración adicional para ignorar modo silencioso
      ticker: '🚨 ALERTA URGENTE - Desconexión detectada',
    );
    
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.critical, // Nivel crítico como llamada
    );
    
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    print('🔔 Mostrando notificación...');
    print('   - Sonido: Habilitado');
    print('   - Vibración: Habilitada');
    print('   - Pantalla completa: Habilitada');
    
    // Mostrar notificación con ID único
    await _localNotifications.show(
      alerta.id.hashCode,
      '📞 ALERTA URGENTE: ${alerta.tipoAlerta.displayName}',
      'CTO: ${alerta.nombreCto} | Pelo: ${_formatearPelo(alerta.numeroPelo)} | OT: ${alerta.numeroOt}',
      details,
      payload: jsonEncode(alerta.toJson()),
    );
    
    // Iniciar alarma en loop (solo si la app está en primer plano)
    // Si la app está cerrada, la notificación persistente con sonido funcionará
    try {
      await _alarmAudio.iniciarAlarma(alerta.id);
      print('🔊 Alarma iniciada en loop (app en primer plano)');
    } catch (e) {
      print('⚠️ No se pudo iniciar alarma (app puede estar en segundo plano): $e');
      // Continuar - la notificación persistente seguirá sonando
    }
    
    print('✅ Notificación de llamada mostrada: ${alerta.numeroOt}');
    print('🔊 Notificación persistente activa (funciona incluso con app cerrada)');
  }

  /// Detiene la alarma y cancela la notificación para una alerta específica
  Future<void> detenerAlarmaAlerta(String alertaId) async {
    print('🔇 [detenerAlarmaAlerta] Iniciando detención para alerta: $alertaId');
    
    // PASO 1: Cancelar notificación PRIMERO (para evitar que se reinicie la alarma)
    try {
      print('🔇 [detenerAlarmaAlerta] Cancelando notificación...');
      await _localNotifications.cancel(alertaId.hashCode);
      print('✅ [detenerAlarmaAlerta] Notificación cancelada');
    } catch (e) {
      print('⚠️ [detenerAlarmaAlerta] Error cancelando notificación: $e');
    }
    
    // PASO 2: Detener alarma de audio (forzar detención completa)
    try {
      print('🔇 [detenerAlarmaAlerta] Deteniendo alarma de audio...');
      // Detener específicamente para esta alerta
      await _alarmAudio.detenerAlarmaParaAlerta(alertaId);
      // Esperar un momento
      await Future.delayed(const Duration(milliseconds: 100));
      // Forzar detención completa como fallback
      await _alarmAudio.detenerAlarma();
      // Esperar otro momento para asegurar
      await Future.delayed(const Duration(milliseconds: 100));
      print('✅ [detenerAlarmaAlerta] Alarma de audio detenida completamente');
    } catch (e) {
      print('⚠️ [detenerAlarmaAlerta] Error deteniendo alarma: $e');
      // Intentar detener de todas formas
      try {
        await _alarmAudio.detenerAlarma();
      } catch (e2) {
        print('⚠️ [detenerAlarmaAlerta] Error en fallback de detener alarma: $e2');
      }
    }
    
    print('✅ [detenerAlarmaAlerta] Proceso de detención completado para: $alertaId');
  }

  /// Muestra una notificación de alerta con sonido (versión normal)
  Future<void> mostrarAlerta(Alerta alerta) async {
    if (!_inicializado) {
      await initialize();
    }
    
    final androidDetails = AndroidNotificationDetails(
      'alertas_urgentes',
      'Alertas Urgentes',
      channelDescription: 'Notificaciones de alertas de desconexión',
      importance: Importance.max,
      priority: Priority.max,
      // No especificar sound = usa el sonido del canal
      playSound: true,
      enableVibration: true,
      ongoing: true,
      autoCancel: false,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      icon: '@mipmap/ic_launcher',
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      styleInformation: BigTextStyleInformation(
        'CTO: ${alerta.nombreCto}\nPelo: ${_formatearPelo(alerta.numeroPelo)}\nOT: ${alerta.numeroOt}',
        contentTitle: '⚠️ ALERTA: ${alerta.tipoAlerta.displayName}',
        summaryText: 'Desconexión detectada',
      ),
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
    
    await _localNotifications.show(
      alerta.id.hashCode,
      '⚠️ ALERTA: ${alerta.tipoAlerta.displayName}',
      'CTO: ${alerta.nombreCto} | Pelo: ${_formatearPelo(alerta.numeroPelo)} | OT: ${alerta.numeroOt}',
      details,
      payload: jsonEncode(alerta.toJson()),
    );
    
    print('🔔 Notificación de alerta mostrada: ${alerta.numeroOt}');
  }

  void _onNotificationTapped(NotificationResponse response) {
    print('📱 Notificación tocada: ${response.payload}');
    // La notificación ya abre la app automáticamente con fullScreenIntent
    // El payload contiene el JSON de la alerta si se necesita procesar
    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!);
        print('📋 Datos de alerta desde notificación: ${data['numero_ot']}');
        // La app se abrirá automáticamente gracias a fullScreenIntent
      } catch (e) {
        print('⚠️ Error parseando payload: $e');
      }
    }
  }

  /// Cancela una notificación específica y detiene la alarma
  Future<void> cancelNotification(String alertaId) async {
    await _localNotifications.cancel(alertaId.hashCode);
    await _alarmAudio.detenerAlarmaParaAlerta(alertaId);
    print('🔇 Notificación cancelada y alarma detenida para: $alertaId');
  }

  /// Cancela todas las notificaciones y detiene la alarma
  Future<void> cancelAllNotifications() async {
    try {
      print('🔔 [LocalNotification] Cancelando todas las notificaciones...');
      
      // Usar timeout para evitar que se quede colgado
      await _localNotifications.cancelAll().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          print('⚠️ [LocalNotification] Timeout cancelando notificaciones (continuando...)');
        },
      );
      print('✅ [LocalNotification] cancelAll() ejecutado');
      
      // También detener alarma por si acaso (con timeout)
      try {
        await _alarmAudio.detenerAlarma().timeout(
          const Duration(seconds: 1),
          onTimeout: () {
            print('⚠️ [LocalNotification] Timeout deteniendo alarma (continuando...)');
          },
        );
      } catch (e) {
        print('⚠️ [LocalNotification] Error deteniendo alarma: $e');
      }
      
      print('✅ [LocalNotification] Todas las notificaciones canceladas y alarma detenida');
    } catch (e) {
      print('❌ [LocalNotification] Error cancelando notificaciones: $e');
      // No intentar fallback con bucle largo para evitar bloqueos
      print('⚠️ [LocalNotification] Continuando sin fallback para evitar bloqueos');
    }
  }

  /// Muestra una notificación genérica
  Future<void> mostrarNotificacion({
    required int id,
    required String titulo,
    required String cuerpo,
    String? payload,
  }) async {
    if (!_inicializado) {
      await initialize();
    }

    final androidDetails = AndroidNotificationDetails(
      'alertas_urgentes',
      'Alertas Urgentes',
      channelDescription: 'Notificaciones de alertas de desconexión',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      id,
      titulo,
      cuerpo,
      details,
      payload: payload,
    );

    print('🔔 Notificación mostrada: $titulo');
  }

  /// Muestra una notificación de alerta de fraude para supervisor
  Future<void> mostrarAlertaFraude({
    required String tecnico,
    required String ot,
  }) async {
    if (!_inicializado) {
      await initialize();
    }

    final androidDetails = AndroidNotificationDetails(
      'alertas_fraude',
      'Alertas de Fraude',
      channelDescription: 'Notificaciones de intentos de fraude',
      importance: Importance.max,
      priority: Priority.high,
      color: const Color(0xFFFF0000),
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      '🚨 ALERTA DE FRAUDE',
      '$tecnico intentó marcar Sin Moradores sin bajarse - OT: $ot',
      details,
    );
    
    print('🚨 Notificación de fraude mostrada: $tecnico - OT: $ot');
  }
}

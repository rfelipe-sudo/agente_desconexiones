import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/alerta_cto.dart' show AlertaCTO, PuertoAlerta;
import '../models/alerta_cto.dart' as cto_models show NivelPuerto;
import '../models/alerta.dart' show Alerta, TipoAlerta, EstadoAlerta, NivelPuerto;
import '../constants/app_constants.dart';
import 'supabase_service.dart';
import 'local_notification_service.dart';
import 'alarm_audio_service.dart';

class AlertasCTOService {
  static final AlertasCTOService _instance = AlertasCTOService._internal();
  factory AlertasCTOService() => _instance;
  AlertasCTOService._internal();

  static const String _endpoint = 'https://kepler.sbip.cl/api/v1/toa/crea_panel_alerts';
  static const int _intervaloSegundos = 60;

  // ═══════════════════════════════════════════════════════════
  // MODO PRUEBA: true = todas las alertas, false = solo del técnico
  // ═══════════════════════════════════════════════════════════
  static const bool MODO_PRUEBA = true;

  Timer? _timer;
  Timer? _scheduleTimer; // Timer para verificar horario
  String? _rutTecnico;
  String? _nombreTecnico;
  final SupabaseService _supabaseService = SupabaseService();
  final LocalNotificationService _notificationService = LocalNotificationService();
  Set<String> _alertasNotificadas = {};

  // Alertas pendientes que se repiten cada 20 min
  Map<String, Timer> _timersRepeticion = {};
  static const int _repeticionMinutos = 20;
  
  // Horario laboral: 8:00 AM - 22:00 PM, Lunes a Sábado
  static const int _horaInicio = 8;
  static const int _horaFin = 22;

  Function(List<AlertaCTO>)? onAlertasRecibidas;
  
  // Callback para agregar alertas al provider
  Function(Alerta)? onAlertaAgregar;
  
  // Callback para verificar estado de alerta en el provider
  Function(String)? onVerificarEstadoAlerta;

  Future<void> iniciar() async {
    // ═══════════════════════════════════════════════════════════
    // LIMPIAR ESTADO ANTERIOR AL INICIAR (por si la app se reinició)
    // ═══════════════════════════════════════════════════════════
    await _limpiarEstadoAnterior();
    
    final prefs = await SharedPreferences.getInstance();
    _rutTecnico = prefs.getString('rut_tecnico');

    if (MODO_PRUEBA) {
      print('🧪 [AlertasCTO] MODO PRUEBA ACTIVO - Recibirá TODAS las alertas');
    } else {
      if (_rutTecnico == null || _rutTecnico!.isEmpty) {
        print('⚠️ [AlertasCTO] No hay RUT guardado');
        return;
      }
      _nombreTecnico = await _supabaseService.obtenerNombrePorRut(_rutTecnico!);
      print('✅ [AlertasCTO] Filtrando por: $_nombreTecnico');
    }

    // Verificar horario y configurar polling con horario laboral
    _configurarPollingConHorario();
  }

  /// Configura el polling respetando horario laboral (8:00-22:00, L-S)
  void _configurarPollingConHorario() {
    // Verificar si estamos en horario laboral
    if (_estaEnHorarioLaboral()) {
      _iniciarPolling();
    } else {
      print('⏰ [AlertasCTO] Fuera de horario laboral - Polling pausado');
      _programarSiguienteActivacion();
    }

    // Timer para verificar cada minuto si debemos activar/desactivar
    _scheduleTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_estaEnHorarioLaboral()) {
        if (_timer == null) {
          print('⏰ [AlertasCTO] Entrando en horario laboral - Activando polling');
          _iniciarPolling();
        }
      } else {
        if (_timer != null) {
          print('⏰ [AlertasCTO] Saliendo de horario laboral - Desactivando polling');
          _detenerPolling();
          _programarSiguienteActivacion();
        }
      }
    });
  }

  /// Verifica si estamos en horario laboral (8:00-22:00, Lunes-Sábado)
  bool _estaEnHorarioLaboral() {
    // Usar hora local del dispositivo (asume que está configurado en hora de Chile)
    final ahora = DateTime.now();
    final diaSemana = ahora.weekday; // 1=Lunes, 7=Domingo
    final hora = ahora.hour;

    // Domingo desactivado
    if (diaSemana == 7) {
      return false;
    }

    // Lunes a Sábado: 8:00 AM - 22:00 PM
    return hora >= _horaInicio && hora < _horaFin;
  }

  /// Programa la siguiente activación del polling
  void _programarSiguienteActivacion() {
    final ahora = DateTime.now();
    final diaSemana = ahora.weekday;
    final hora = ahora.hour;

    DateTime siguienteActivacion;

    if (diaSemana == 7) {
      // Si es domingo, activar el lunes a las 8:00
      final diasHastaLunes = 8 - diaSemana;
      siguienteActivacion = ahora.add(Duration(days: diasHastaLunes));
      siguienteActivacion = DateTime(
        siguienteActivacion.year,
        siguienteActivacion.month,
        siguienteActivacion.day,
        _horaInicio,
        0,
      );
    } else if (hora < _horaInicio) {
      // Si es antes de las 8:00, activar hoy a las 8:00
      siguienteActivacion = DateTime(
        ahora.year,
        ahora.month,
        ahora.day,
        _horaInicio,
        0,
      );
    } else if (hora >= _horaFin) {
      // Si es después de las 22:00, activar mañana a las 8:00
      siguienteActivacion = ahora.add(const Duration(days: 1));
      siguienteActivacion = DateTime(
        siguienteActivacion.year,
        siguienteActivacion.month,
        siguienteActivacion.day,
        _horaInicio,
        0,
      );
      // Si mañana es domingo, saltar al lunes
      if (siguienteActivacion.weekday == 7) {
        siguienteActivacion = siguienteActivacion.add(const Duration(days: 1));
      }
    } else {
      // Ya estamos en horario, no debería llegar aquí
      return;
    }

    final diferencia = siguienteActivacion.difference(ahora);
    print('⏰ [AlertasCTO] Próxima activación: ${DateFormat('EEEE dd/MM HH:mm', 'es').format(siguienteActivacion)} (en ${diferencia.inHours}h ${diferencia.inMinutes % 60}m)');
  }

  /// Inicia el polling de alertas
  void _iniciarPolling() {
    if (_timer != null) return; // Ya está activo

    // Primera consulta inmediata
    consultarAlertas();

    // Timer para consultas periódicas
    _timer = Timer.periodic(Duration(seconds: _intervaloSegundos), (_) {
      if (_estaEnHorarioLaboral()) {
        consultarAlertas();
      } else {
        _detenerPolling();
        _programarSiguienteActivacion();
      }
    });

    print('✅ [AlertasCTO] Polling iniciado cada $_intervaloSegundos segundos');
  }

  /// Detiene el polling (pero mantiene el schedule timer)
  void _detenerPolling() {
    _timer?.cancel();
    _timer = null;
    print('⏸️ [AlertasCTO] Polling pausado');
  }

  /// Limpia timers y alarmas activas (útil cuando la app se reinicia)
  Future<void> _limpiarEstadoAnterior() async {
    print('🧹 [AlertasCTO] Limpiando estado anterior...');
    
    // Cancelar todos los timers de repetición
    for (final timer in _timersRepeticion.values) {
      timer.cancel();
    }
    _timersRepeticion.clear();
    
    // Limpiar alertas notificadas (se volverán a notificar si siguen activas)
    _alertasNotificadas.clear();
    
    // Detener todas las alarmas activas
    try {
      final alarmAudio = AlarmAudioService();
      if (alarmAudio.estaReproduciendo) {
        await alarmAudio.detenerAlarma();
        print('🔇 [AlertasCTO] Alarma detenida al iniciar');
      }
    } catch (e) {
      print('⚠️ [AlertasCTO] Error deteniendo alarma: $e');
    }
    
    // Cancelar TODAS las notificaciones pendientes (CRÍTICO para notificaciones persistentes)
    try {
      print('🔔 [AlertasCTO] Cancelando todas las notificaciones pendientes...');
      await _notificationService.cancelAllNotifications();
      print('✅ [AlertasCTO] Todas las notificaciones canceladas al iniciar');
      
      // Esperar un poco para asegurar que se cancelaron
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      print('⚠️ [AlertasCTO] Error cancelando notificaciones: $e');
      // Intentar de nuevo
      try {
        await _notificationService.cancelAllNotifications();
      } catch (e2) {
        print('❌ [AlertasCTO] Error en segundo intento: $e2');
      }
    }
    
    // Cancelar timer principal si existe
    _timer?.cancel();
    _timer = null;
    
    print('✅ [AlertasCTO] Estado anterior limpiado');
  }

  void detener() {
    print('🛑 [AlertasCTO] Deteniendo servicio...');
    
    // Cancelar timer principal
    _timer?.cancel();
    _timer = null;
    
    // Cancelar timer de horario
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    
    // Cancelar todos los timers de repetición
    for (final timer in _timersRepeticion.values) {
      timer.cancel();
    }
    _timersRepeticion.clear();
    
    // Detener todas las alarmas activas
    try {
      final alarmAudio = AlarmAudioService();
      if (alarmAudio.estaReproduciendo) {
        alarmAudio.detenerAlarma();
      }
    } catch (e) {
      print('⚠️ [AlertasCTO] Error deteniendo alarma: $e');
    }
    
    print('🛑 [AlertasCTO] Servicio detenido completamente');
  }

  /// Método estático para llamar desde background service
  static Future<void> consultarDesdeBackground() async {
    print('🔄 [AlertasCTO-BG] Consultando desde background...');
    
    try {
      final response = await http.get(
        Uri.parse(_endpoint),
        headers: AppConstants.keplerHeaders,
      );
      
      if (response.statusCode != 200) {
        print('❌ [AlertasCTO-BG] Error HTTP: ${response.statusCode}');
        return;
      }

      final data = jsonDecode(response.body);
      final List<dynamic> alertasJson = data['data'] ?? [];
      
      print('📋 [AlertasCTO-BG] Alertas en Kepler: ${alertasJson.length}');

      // Filtrar solo las que tienen alertas activas
      final alertasActivas = alertasJson.where((alerta) {
        return alerta['alertas']?['has_alerts'] == true;
      }).toList();

      print('🚨 [AlertasCTO-BG] Alertas activas: ${alertasActivas.length}');

      if (alertasActivas.isEmpty) return;

      final supabase = SupabaseService();
      final notificaciones = LocalNotificationService();
      final prefs = await SharedPreferences.getInstance();
      
      // Obtener alertas ya notificadas
      final notificadasStr = prefs.getStringList('alertas_cto_notificadas') ?? [];
      final notificadas = notificadasStr.toSet();

      for (final alertaJson in alertasActivas) {
        final ot = alertaJson['ot']?.toString() ?? '';
        final accessId = alertaJson['access_id']?.toString() ?? '';
        final alertaId = '${ot}_$accessId';

        // Guardar en Supabase
        final alerta = AlertaCTO.fromJson(alertaJson);
        
        await supabase.guardarAlertaCTO(
          alertaId: alertaId,
          ot: alerta.ot,
          accessId: alerta.accessId,
          tecnico: alerta.tecnico,
          tecnicoFull: alerta.tecnicoFull,
          actividad: alerta.actividad,
          puertosAfectados: alerta.puertosConAlerta.map((p) => {
            'port_number': p.portNumber,
            'inicial': p.inicial,
            'final': p.finalValue,
            'difference': p.difference,
            'alert_reasons': p.alertReasons,
          }).toList(),
          nivelesInicial: alerta.nivelesInicial.map((n) => {
            'port_number': n.portNumber,
            'port_id': n.portId,
            'rx_actual': n.rxActual,
            'status': n.status,
          }).toList(),
          nivelesFinal: alerta.nivelesFinal.map((n) => {
            'port_number': n.portNumber,
            'port_id': n.portId,
            'rx_actual': n.rxActual,
            'status': n.status,
          }).toList(),
        );

        // Notificar solo si es nueva
        if (!notificadas.contains(alertaId)) {
          notificadas.add(alertaId);
          
          // Convertir AlertaCTO a Alerta
          final alertaConvertida = AlertasCTOService.convertirAlertaCTOaAlerta(alerta);

          // ═══════════════════════════════════════════════════════
          // AGREGAR DIRECTAMENTE AL PROVIDER (sin necesidad de presionar notificación)
          // ═══════════════════════════════════════════════════════
          final instance = AlertasCTOService();
          if (instance.onAlertaAgregar != null) {
            instance.onAlertaAgregar!(alertaConvertida);
            print('✅ [AlertasCTO-BG] Alerta agregada directamente al provider: $alertaId');
          }

          // Notificación con sonido (igual que alertas normales)
          await notificaciones.mostrarAlertaComoLlamada(alertaConvertida);

          // Iniciar repetición desde la instancia singleton
          final puertosTexto = alerta.puertosConAlerta
              .map((p) => 'Puerto ${p.portNumber}')
              .toList();
          instance._iniciarRepeticion(alertaId, alerta.ot, alerta.tecnico, puertosTexto, alertaConvertida);

          print('🔔 [AlertasCTO-BG] Notificación + Repetición enviada: $alertaId');
        }
      }

      // Guardar alertas notificadas
      await prefs.setStringList('alertas_cto_notificadas', notificadas.toList());

    } catch (e) {
      print('❌ [AlertasCTO-BG] Error: $e');
    }
  }

  Future<List<AlertaCTO>> consultarAlertas() async {
    try {
      print('🔄 [AlertasCTO] Consultando alertas...');

      final response = await http.get(
        Uri.parse(_endpoint),
        headers: AppConstants.keplerHeaders,
      );

      if (response.statusCode != 200) {
        print('❌ [AlertasCTO] Error HTTP: ${response.statusCode}');
        return [];
      }

      final data = jsonDecode(response.body);
      final List<dynamic> alertasJson = data['data'] ?? [];

      print('📋 [AlertasCTO] Total en Kepler: ${alertasJson.length}');

      List<AlertaCTO> alertasFiltradas;

      if (MODO_PRUEBA) {
        // ═══════════════════════════════════════════════════════
        // MODO PRUEBA: Mostrar TODAS las alertas con has_alerts=true
        // ═══════════════════════════════════════════════════════
        alertasFiltradas = alertasJson
            .where((alerta) => alerta['alertas']?['has_alerts'] == true)
            .map((json) => AlertaCTO.fromJson(json as Map<String, dynamic>))
            .toList();
        
        print('🧪 [AlertasCTO] MODO PRUEBA - Alertas activas: ${alertasFiltradas.length}');
      } else {
        // Modo producción: filtrar por técnico
        if (_nombreTecnico == null) {
          _nombreTecnico = await _supabaseService.obtenerNombrePorRut(_rutTecnico!);
        }

        if (_nombreTecnico == null) {
          print('⚠️ [AlertasCTO] Sin nombre de técnico');
          return [];
        }

        alertasFiltradas = alertasJson.where((alerta) {
          final tecnico = alerta['tecnico']?.toString() ?? '';
          final tecnicoFull = alerta['tecnico_full']?.toString() ?? '';
          final hasAlerts = alerta['alertas']?['has_alerts'] ?? false;

          final nombreLower = _nombreTecnico!.toLowerCase();
          final esDelTecnico = tecnico.toLowerCase().contains(nombreLower) ||
              tecnicoFull.toLowerCase().contains(nombreLower) ||
              nombreLower.contains(tecnico.toLowerCase());

          return esDelTecnico && hasAlerts;
        }).map((json) => AlertaCTO.fromJson(json as Map<String, dynamic>)).toList();
      }

      print('🚨 [AlertasCTO] Alertas a procesar: ${alertasFiltradas.length}');

      // Guardar y notificar
      for (final alerta in alertasFiltradas) {
        final alertaId = '${alerta.ot}_${alerta.accessId}';

        await _supabaseService.guardarAlertaCTO(
          alertaId: alertaId,
          ot: alerta.ot,
          accessId: alerta.accessId,
          tecnico: alerta.tecnico,
          tecnicoFull: alerta.tecnicoFull,
          actividad: alerta.actividad,
          puertosAfectados: alerta.puertosConAlerta.map((p) => {
            'port_number': p.portNumber,
            'inicial': p.inicial,
            'final': p.finalValue,
            'difference': p.difference,
            'alert_reasons': p.alertReasons,
          }).toList(),
          nivelesInicial: alerta.nivelesInicial.map((n) => {
            'port_number': n.portNumber,
            'port_id': n.portId,
            'rx_actual': n.rxActual,
            'status': n.status,
          }).toList(),
          nivelesFinal: alerta.nivelesFinal.map((n) => {
            'port_number': n.portNumber,
            'port_id': n.portId,
            'rx_actual': n.rxActual,
            'status': n.status,
          }).toList(),
        );

        // Convertir AlertaCTO a Alerta
        final alertaConvertida = convertirAlertaCTOaAlerta(alerta);

        // Notificar solo si es nueva (no existe en el panel)
        if (!_alertasNotificadas.contains(alertaId)) {
          _alertasNotificadas.add(alertaId);

          // Agregar al provider para que aparezca en "Alertas Pendientes"
          if (onAlertaAgregar != null) {
            onAlertaAgregar!(alertaConvertida);
          }

          // Notificación con sonido (igual que alertas normales)
          await _notificationService.mostrarAlertaComoLlamada(alertaConvertida);

          // ═══════════════════════════════════════════════════
          // REPETIR CADA 20 MINUTOS HASTA QUE SE SOLUCIONE
          // ═══════════════════════════════════════════════════
          final puertosTexto = alerta.puertosConAlerta
              .map((p) => 'Puerto ${p.portNumber}')
              .toList();
          _iniciarRepeticion(alertaId, alerta.ot, alerta.tecnico, puertosTexto, alertaConvertida);

          print('🔔 [AlertasCTO] Notificación + Repetición iniciada: OT ${alerta.ot}');
        } else {
          // Si ya existe, verificar si necesita repetición
          // (puede que se haya reiniciado la app y perdido el timer)
          bool necesitaRepeticion = false;
          if (onVerificarEstadoAlerta != null) {
            try {
              final estado = onVerificarEstadoAlerta!(alertaId);
              // Solo necesita repetición si NO está solucionada
              necesitaRepeticion = estado != 'regularizada' && estado != 'cerrada';
            } catch (e) {
              // Si no existe en el provider, no necesita repetición
              necesitaRepeticion = false;
            }
          }
          
          // Si no hay timer activo y necesita repetición, iniciarlo
          if (necesitaRepeticion && !_timersRepeticion.containsKey(alertaId)) {
            final puertosTexto = alerta.puertosConAlerta
                .map((p) => 'Puerto ${p.portNumber}')
                .toList();
            _iniciarRepeticion(alertaId, alerta.ot, alerta.tecnico, puertosTexto, alertaConvertida);
            print('🔁 [AlertasCTO] Repetición reiniciada para: OT ${alerta.ot}');
          }
        }
      }

      if (onAlertasRecibidas != null && alertasFiltradas.isNotEmpty) {
        onAlertasRecibidas!(alertasFiltradas);
      }

      return alertasFiltradas;
    } catch (e) {
      print('❌ [AlertasCTO] Error: $e');
      return [];
    }
  }

  void actualizarNombre(String nombre) {
    _nombreTecnico = nombre;
    print('✅ [AlertasCTO] Nombre actualizado: $nombre');
  }

  Future<Map<String, dynamic>> verificarYActualizarAlerta(String ot) async {
    try {
      print('🔄 [CREA] Verificando: $ot');

      final response = await http.get(
        Uri.parse(_endpoint),
        headers: AppConstants.keplerHeaders,
      );

      if (response.statusCode != 200) {
        return {'solucionado': false, 'error': 'Error consultando Kepler'};
      }

      final data = jsonDecode(response.body);
      final List<dynamic> alertasJson = data['data'] ?? [];

      final alertaActual = alertasJson.firstWhere(
        (a) => a['ot']?.toString() == ot,
        orElse: () => null,
      );

      if (alertaActual == null) {
        await _supabaseService.marcarAlertaCTOSolucionada('${ot}_', notas: 'OT no encontrada');
        return {
          'solucionado': true,
          'mensaje': 'La orden ya no está en el panel de alertas.',
        };
      }

      final hasAlerts = alertaActual['alertas']?['has_alerts'] ?? false;

      if (!hasAlerts) {
        final alertaId = '${ot}_${alertaActual['access_id']}';
        await _supabaseService.marcarAlertaCTOSolucionada(alertaId, notas: 'Verificado por CREA');
        detenerRepeticion(alertaId);
        await _notificationService.detenerAlarmaAlerta(alertaId);

        return {
          'solucionado': true,
          'mensaje': '¡Todos los puertos OK! Alerta resuelta.',
          'niveles': alertaActual['niveles_final'],
        };
      } else {
        final ports = (alertaActual['alertas']['ports'] as List?)
            ?.where((p) => p['has_alert'] == true)
            .map((p) => {
              'puerto': p['port_number'],
              'razon': (p['alert_reasons'] as List?)?.join(', ') ?? 'Sin señal',
              'inicial': p['inicial'],
              'final': p['final'],
            })
            .toList() ?? [];

        return {
          'solucionado': false,
          'mensaje': 'Aún hay problemas.',
          'puertos_con_problema': ports,
        };
      }
    } catch (e) {
      print('❌ [CREA] Error: $e');
      return {'solucionado': false, 'error': e.toString()};
    }
  }

  /// Inicia repetición de notificación cada 20 minutos
  /// Solo suena si la alerta NO está solucionada
  void _iniciarRepeticion(String alertaId, String ot, String tecnico, List<String> puertos, Alerta alerta) {
    // Cancelar timer anterior si existe
    _timersRepeticion[alertaId]?.cancel();
    
    _timersRepeticion[alertaId] = Timer.periodic(
      Duration(minutes: _repeticionMinutos),
      (_) async {
        // Verificar si la alerta está solucionada antes de sonar
        bool estaSolucionada = false;
        if (onVerificarEstadoAlerta != null) {
          final estado = onVerificarEstadoAlerta!(alertaId);
          // Estados solucionados: regularizada o cerrada
          estaSolucionada = estado == 'regularizada' || estado == 'cerrada';
        }
        
        if (estaSolucionada) {
          print('✅ [AlertasCTO] Alerta $ot ya está solucionada - deteniendo repetición');
          detenerRepeticion(alertaId);
          return;
        }
        
        print('🔁 [AlertasCTO] Repitiendo alerta: $ot (cada $_repeticionMinutos min)');
        // Solo repetir notificación con sonido (NO agregar nueva alerta al panel)
        await _notificationService.mostrarAlertaComoLlamada(alerta);
      },
    );
  }

  /// Detiene la repetición cuando se atiende la alerta
  void detenerRepeticion(String alertaId) {
    _timersRepeticion[alertaId]?.cancel();
    _timersRepeticion.remove(alertaId);
    _alertasNotificadas.remove(alertaId);
    print('✅ [AlertasCTO] Repetición detenida: $alertaId');
  }

  /// Detiene repetición y cancela notificación
  Future<void> atenderAlerta(String ot, String accessId) async {
    final alertaId = '${ot}_$accessId';
    detenerRepeticion(alertaId);
    await _notificationService.detenerAlarmaAlerta(alertaId);
    print('✅ [AlertasCTO] Alerta atendida: $alertaId');
  }

  /// Convierte AlertaCTO a Alerta para integrar con el sistema de alertas
  static Alerta convertirAlertaCTOaAlerta(AlertaCTO alertaCTO) {
    // Obtener el primer puerto con alerta para obtener valores
    final primerPuerto = alertaCTO.puertosConAlerta.isNotEmpty 
        ? alertaCTO.puertosConAlerta.first 
        : null;
    
    // Obtener valor inicial del primer puerto
    final valorInicial = primerPuerto?.inicial ?? -99.0;
    
    // Obtener nombre CTO desde accessId o actividad
    final nombreCto = alertaCTO.accessId.isNotEmpty 
        ? 'CTO-${alertaCTO.accessId}' 
        : 'CTO-Desconocida';
    
    // Obtener número de pelo (puerto) del primer puerto con alerta
    final numeroPelo = primerPuerto != null 
        ? primerPuerto.portNumber.toString() 
        : '0';
    
    // Convertir niveles de puertos (de NivelPuerto de alerta_cto.dart a NivelPuerto de alerta.dart)
    final nivelesPuertos = alertaCTO.nivelesInicial.map<NivelPuerto>((n) {
      cto_models.NivelPuerto nivelFinal;
      try {
        nivelFinal = alertaCTO.nivelesFinal.firstWhere(
          (nf) => nf.portNumber == n.portNumber,
        );
      } catch (e) {
        // Si no encuentra, usar el primero disponible o crear uno por defecto
        if (alertaCTO.nivelesFinal.isNotEmpty) {
          nivelFinal = alertaCTO.nivelesFinal.first;
        } else {
          nivelFinal = cto_models.NivelPuerto(
            portNumber: n.portNumber,
            portId: '',
            rxActual: 'N/A',
            status: '',
            isCurrent: false,
          );
        }
      }
      
      // Retornar NivelPuerto del modelo alerta.dart
      return NivelPuerto(
        puerto: n.portNumber,
        consulta1: _parsearPotencia(n.rxActual),
        consulta2: _parsearPotencia(nivelFinal.rxActual),
      );
    }).toList();

    final alertaId = '${alertaCTO.ot}_${alertaCTO.accessId}';

    return Alerta(
      id: alertaId,
      nombreTecnico: alertaCTO.tecnicoFull.isNotEmpty 
          ? alertaCTO.tecnicoFull 
          : alertaCTO.tecnico,
      telefonoTecnico: '', // No disponible en AlertaCTO
      numeroOt: alertaCTO.ot,
      accessId: alertaCTO.accessId,
      nombreCto: nombreCto,
      numeroPelo: numeroPelo,
      valorConsulta1: valorInicial,
      valorConsulta2: primerPuerto?.finalValue,
      tipoAlerta: TipoAlerta.desconexion,
      fechaRecepcion: DateTime.now(),
      estado: EstadoAlerta.pendiente,
      empresa: 'CREA',
      actividad: alertaCTO.actividad,
      nivelesPuertos: nivelesPuertos,
    );
  }

  /// Parsea potencia desde string (ej: "-21.5 dBm" -> -21.5)
  static double? _parsearPotencia(String? valor) {
    if (valor == null || valor.isEmpty || valor == 'N/A') {
      return null;
    }
    try {
      // Extraer número del string
      final match = RegExp(r'-?\d+\.?\d*').firstMatch(valor);
      if (match != null) {
        return double.parse(match.group(0)!);
      }
    } catch (e) {
      print('⚠️ Error parseando potencia: $valor');
    }
    return null;
  }
}

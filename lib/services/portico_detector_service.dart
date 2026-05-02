// ============================================================================
// SERVICIO: DETECTOR DE PÓRTICOS TAG AUTOMÁTICO
// ============================================================================

import 'dart:async';
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/portico.dart';

class PorticoDetectorService {
  static final PorticoDetectorService _instance = PorticoDetectorService._internal();
  factory PorticoDetectorService() => _instance;
  PorticoDetectorService._internal();

  final SupabaseClient _client = Supabase.instance.client;
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  bool _activo = false;
  Timer? _timer;
  List<Portico> _porticos = [];
  final Map<String, DateTime> _ultimosPasos = {}; // portico_id -> última detección
  static const int _cooldownMinutos = 5;
  static const double _distanciaMaximaMetros = 100.0;
  static const Duration _intervaloUbicacion = Duration(seconds: 10);

  bool get estaActivo => _activo;

  /// Iniciar detección de pórticos
  Future<void> iniciar() async {
    if (_activo) return;

    try {
      // Verificar permisos
      final permisos = await _verificarPermisos();
      if (!permisos) {
        print('❌ [PorticoDetector] Permisos de ubicación denegados');
        return;
      }

      // Cargar pórticos
      await _cargarPorticos();

      _activo = true;
      print('✅ [PorticoDetector] Iniciado');

      // Iniciar timer para obtener ubicación cada 10 segundos
      _timer = Timer.periodic(_intervaloUbicacion, (_) => _verificarUbicacion());
    } catch (e) {
      print('❌ [PorticoDetector] Error al iniciar: $e');
      _activo = false;
    }
  }

  /// Detener detección
  void detener() {
    _timer?.cancel();
    _timer = null;
    _activo = false;
    print('🛑 [PorticoDetector] Detenido');
  }

  /// Verificar permisos de ubicación
  Future<bool> _verificarPermisos() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('⚠️ [PorticoDetector] Servicio de ubicación deshabilitado');
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('❌ [PorticoDetector] Permisos denegados permanentemente');
        return false;
      }

      return true;
    } catch (e) {
      print('❌ [PorticoDetector] Error verificando permisos: $e');
      return false;
    }
  }

  /// Cargar pórticos desde Supabase
  Future<void> _cargarPorticos() async {
    try {
      final response = await _client
          .from('porticos_tag')
          .select()
          .eq('activo', true);

      _porticos = (response as List)
          .map((json) => Portico.fromJson(json as Map<String, dynamic>))
          .toList();

      if (_porticos.isNotEmpty) {
        print('✅ [PorticoDetector] ${_porticos.length} pórticos cargados');
      }
    } catch (_) {
      // La tabla porticos_tag puede no estar disponible en este entorno.
      // El servicio continúa sin pórticos cargados.
      _porticos = [];
    }
  }

  /// Verificar ubicación actual y detectar pórticos cercanos
  Future<void> _verificarUbicacion() async {
    if (!_activo) return;

    try {
      final posicion = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );

      await _detectarPorticosCercanos(posicion.latitude, posicion.longitude);
    } catch (e) {
      print('⚠️ [PorticoDetector] Error obteniendo ubicación: $e');
    }
  }

  /// Detectar pórticos cercanos a la ubicación actual
  Future<void> _detectarPorticosCercanos(double lat, double lon) async {
    for (final portico in _porticos) {
      final distancia = calcularDistancia(
        lat,
        lon,
        portico.latitud,
        portico.longitud,
      );

      if (distancia <= _distanciaMaximaMetros) {
        await _registrarPaso(portico, lat, lon);
        break; // Solo registrar un pórtico por verificación
      }
    }
  }

  /// Registrar paso en Supabase
  Future<void> _registrarPaso(Portico portico, double lat, double lon) async {
    try {
      // Verificar cooldown
      final ultimoPaso = _ultimosPasos[portico.id];
      if (ultimoPaso != null) {
        final diferencia = DateTime.now().difference(ultimoPaso);
        if (diferencia.inMinutes < _cooldownMinutos) {
          print('⏳ [PorticoDetector] Cooldown activo para ${portico.nombre}');
          return;
        }
      }

      // Obtener RUT del técnico
      final prefs = await SharedPreferences.getInstance();
      final rutTecnico = prefs.getString('rut_tecnico');

      if (rutTecnico == null || rutTecnico.isEmpty) {
        print('⚠️ [PorticoDetector] No hay RUT configurado');
        return;
      }

      // Preparar datos
      final now = DateTime.now();
      final mesAnno = '${now.year}-${now.month.toString().padLeft(2, '0')}';

      // Insertar en Supabase
      await _client.from('pasos_tag').insert({
        'rut_tecnico': rutTecnico,
        'portico_id': portico.id,
        'portico_codigo': portico.codigo,
        'portico_nombre': portico.nombre,
        'autopista': portico.autopista,
        'tarifa_cobrada': portico.tarifaTs,
        'tipo_tarifa': 'ts',
        'latitud': lat,
        'longitud': lon,
        'fecha_paso': now.toIso8601String(),
        'mes_anno': mesAnno,
      });

      // Actualizar cooldown
      _ultimosPasos[portico.id] = now;

      print('✅ [PorticoDetector] Paso registrado: ${portico.nombre} (${portico.codigo})');

      // Mostrar notificación
      await _mostrarNotificacion(portico);
    } catch (e) {
      print('❌ [PorticoDetector] Error registrando paso: $e');
    }
  }

  /// Mostrar notificación cuando se detecta un pórtico
  Future<void> _mostrarNotificacion(Portico portico) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'portico_detector',
        'Detección de Pórticos',
        channelDescription: 'Notificaciones cuando se detecta un pórtico TAG',
        importance: Importance.low,
        priority: Priority.low,
      );

      const notificationDetails = NotificationDetails(android: androidDetails);

      await _notifications.show(
        portico.hashCode,
        'Pórtico detectado',
        '${portico.nombre} - ${portico.autopista}',
        notificationDetails,
      );
    } catch (e) {
      print('⚠️ [PorticoDetector] Error mostrando notificación: $e');
    }
  }

  /// Calcular distancia entre dos coordenadas (Haversine)
  double calcularDistancia(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295; // pi / 180

    final a = 0.5 -
        math.cos((lat2 - lat1) * p) / 2 +
        math.cos(lat1 * p) *
            math.cos(lat2 * p) *
            (1 - math.cos((lon2 - lon1) * p)) /
            2;

    return 12742 * math.asin(math.sqrt(a)) * 1000; // metros
  }

  /// Recargar pórticos (útil si se actualizan en Supabase)
  Future<void> recargarPorticos() async {
    await _cargarPorticos();
  }

  /// Diagnóstico del servicio
  Future<Map<String, dynamic>> diagnostico() async {
    try {
      // Recargar pórticos si están vacíos
      if (_porticos.isEmpty) {
        await _cargarPorticos();
      }

      final prefs = await SharedPreferences.getInstance();
      final rut = prefs.getString('rut_tecnico');

      Position? posicion;
      try {
        posicion = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
      } catch (e) {
        posicion = null;
      }

      String? porticoMasCercano;
      double? distanciaMinima;

      if (posicion != null && _porticos.isNotEmpty) {
        for (final p in _porticos) {
          final dist = calcularDistancia(
            posicion.latitude,
            posicion.longitude,
            p.latitud,
            p.longitud,
          );
          if (distanciaMinima == null || dist < distanciaMinima) {
            distanciaMinima = dist;
            porticoMasCercano = p.nombre;
          }
        }
      }

      return {
        'servicio_activo': _activo,
        'rut_configurado': rut ?? 'No configurado',
        'porticos_cargados': _porticos.length,
        'ubicacion_actual': posicion != null
            ? '${posicion.latitude}, ${posicion.longitude}'
            : 'No disponible',
        'portico_mas_cercano': porticoMasCercano ?? 'N/A',
        'distancia_metros': distanciaMinima != null
            ? distanciaMinima!.toStringAsFixed(0)
            : 'N/A',
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}


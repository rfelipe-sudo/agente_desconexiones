import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:agente_desconexiones/models/estado_supervisor.dart';
import 'package:agente_desconexiones/services/combustible_supervisor_ruta_service.dart';
import 'package:agente_desconexiones/services/supervisor_rutas_service.dart';

String _nombreDesdeNomina(Map<String, dynamic> t) {
  final n =
      '${t['nombres'] ?? ''} ${t['paterno'] ?? ''} ${t['materno'] ?? ''}'.trim();
  return n.replaceAll(RegExp(r'\s+'), ' ');
}

/// Servicio para estado de actividad del supervisor
class EstadoSupervisorService extends ChangeNotifier {
  static final EstadoSupervisorService _instance = EstadoSupervisorService._internal();
  factory EstadoSupervisorService() => _instance;
  EstadoSupervisorService._internal();

  final _supabase = Supabase.instance.client;
  final _uuid = const Uuid();

  EstadoSupervisor? _estadoActual;
  RealtimeChannel? _canalRealtime;
  StreamSubscription<Position>? _locationSubscription;
  Timer? _countdownTimer;
  Timer? _locationCheckTimer;
  VoidCallback? _onCountdownNotificacion;
  VoidCallback? _onAutoCompletado;

  EstadoSupervisor? get estadoActual => _estadoActual;

  /// Obtener posición GPS
  Future<Position> obtenerPosicion() async {
    final servicioHabilitado = await Geolocator.isLocationServiceEnabled();
    if (!servicioHabilitado) {
      throw Exception('El GPS está desactivado. Actívalo en Configuración.');
    }
    final permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      final nuevo = await Geolocator.requestPermission();
      if (nuevo == LocationPermission.denied) {
        throw Exception('Permiso de ubicación denegado.');
      }
    }
    if (permiso == LocationPermission.deniedForever) {
      throw Exception('Permiso de ubicación denegado permanentemente.');
    }
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 15),
    );
  }

  /// Distancia Haversine en km
  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static const _keyHistorialActivo = 'historial_id_activo';

  /// Iniciar actividad (sin movimiento de materiales)
  Future<void> iniciarActividad({
    required String rutSupervisor,
    required String nombreSupervisor,
    required String actividadValor,
  }) async {
    final pos = await obtenerPosicion();
    final now = DateTime.now().toUtc().toIso8601String();

    await _supabase.from('estado_supervisor_crea').upsert({
      'rut_supervisor': rutSupervisor,
      'nombre_supervisor': nombreSupervisor,
      'actividad': actividadValor,
      'actividad_desde': now,
      'ticket_id_activo': null,
      'rut_tecnico_activo': null,
      'nombre_tecnico_activo': null,
      'tipo_ayuda_activo': null,
      'lat': pos.latitude,
      'lng': pos.longitude,
      'ubicacion_at': now,
      'updated_at': now,
    }, onConflict: 'rut_supervisor');

    final hist = await _supabase
        .from('historial_actividades')
        .insert({
          'rut_supervisor': rutSupervisor,
          'nombre_supervisor': nombreSupervisor,
          'actividad': actividadValor,
          'inicio_at': now,
          'completada': false,
        })
        .select('id')
        .single();
    final histId = hist['id'] as int?;
    if (histId != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyHistorialActivo, histId);
    }

    await cargarEstado(rutSupervisor);
    notifyListeners();
  }

  /// Iniciar movimiento de materiales
  Future<void> iniciarMovimientoMateriales({
    required String rutSupervisor,
    required String nombreSupervisor,
    required String materialOrigen,
    required String materialDestino,
    required double latOrigen,
    required double lngOrigen,
    required double latDestino,
    required double lngDestino,
    required String materialDetalle,
    required int materialCantidad,
    required String rutDestino,
    required String nombreDestino,
  }) async {
    final pos = await obtenerPosicion();
    final ticketId = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();

    // Consultar nombre del técnico desde BD si rutDestino no es BODEGA
    String nombreTecnicoInsert = nombreDestino;
    if (rutDestino != 'BODEGA' && rutDestino.isNotEmpty) {
      try {
        final tecnico = await _supabase
            .from('nomina_tecnicos')
            .select('nombres, paterno, materno')
            .eq('rut', rutDestino)
            .maybeSingle();
        if (tecnico != null) {
          nombreTecnicoInsert = _nombreDesdeNomina(tecnico);
          if (nombreTecnicoInsert.isEmpty) nombreTecnicoInsert = nombreDestino;
        }
      } catch (_) {}
    }

    await _supabase.from('ayuda_terreno_crea').insert({
      'ticket_id': ticketId,
      'rut_tecnico': rutDestino,
      'nombre_tecnico': nombreTecnicoInsert,
      'lat_tecnico': latDestino,
      'lng_tecnico': lngDestino,
      'tipo': 'movimiento_material',
      'estado': 'pendiente',
      'rut_supervisor': rutSupervisor,
      'nombre_supervisor': nombreSupervisor,
      'lat_supervisor': pos.latitude,
      'lng_supervisor': pos.longitude,
      'material_origen': materialOrigen,
      'material_destino': materialDestino,
      'lat_origen': latOrigen,
      'lng_origen': lngOrigen,
      'lat_destino': latDestino,
      'lng_destino': lngDestino,
      'material_detalle': materialDetalle,
      'material_cantidad': materialCantidad,
    });

    await _supabase.from('estado_supervisor_crea').upsert({
      'rut_supervisor': rutSupervisor,
      'nombre_supervisor': nombreSupervisor,
      'actividad': 'movimiento_material',
      'actividad_desde': now,
      'ticket_id_activo': ticketId,
      'rut_tecnico_activo': rutDestino,
      'nombre_tecnico_activo': nombreDestino,
      'tipo_ayuda_activo': 'movimiento_material',
      'lat': pos.latitude,
      'lng': pos.longitude,
      'ubicacion_at': now,
      'updated_at': now,
    }, onConflict: 'rut_supervisor');

    final detalle = '$materialDetalle x$materialCantidad';
    final hist = await _supabase
        .from('historial_actividades')
        .insert({
          'rut_supervisor': rutSupervisor,
          'nombre_supervisor': nombreSupervisor,
          'actividad': 'movimiento_material',
          'ticket_id': ticketId,
          'rut_tecnico': rutDestino,
          'nombre_tecnico': nombreDestino,
          'tipo_ayuda': 'movimiento_material',
          'detalle': detalle,
          'origen': materialOrigen,
          'destino': materialDestino,
          'inicio_at': now,
          'completada': false,
        })
        .select('id')
        .single();
    final histId = hist['id'] as int?;
    if (histId != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyHistorialActivo, histId);
    }

    await cargarEstado(rutSupervisor);
    notifyListeners();

    _iniciarListener100m(rutSupervisor, ticketId, latDestino, lngDestino);
  }

  /// Completar actividad
  /// [autoCompletada] true si se cerró por GPS (countdown 10 min)
  Future<void> completarActividad(String rutSupervisor,
      {bool autoCompletada = false}) async {
    final actividadValor = _estadoActual?.actividad ?? '';
    final partidaLat = _estadoActual?.lat;
    final partidaLng = _estadoActual?.lng;
    final partidaEtiqueta = actividadValor.isNotEmpty &&
            actividadValor != 'sin_actividad'
        ? CombustibleSupervisorRutaService.etiquetaActividad(actividadValor)
        : null;

    final ticketId = _estadoActual?.ticketIdActivo;
    if (ticketId != null && ticketId.isNotEmpty) {
      await _supabase
          .from('ayuda_terreno_crea')
          .update({
            'estado': 'aceptada',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('ticket_id', ticketId);
    }

    await _supabase.from('estado_supervisor_crea').upsert({
      'rut_supervisor': rutSupervisor,
      'actividad': 'sin_actividad',
      'actividad_desde': null,
      'ticket_id_activo': null,
      'rut_tecnico_activo': null,
      'nombre_tecnico_activo': null,
      'tipo_ayuda_activo': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'rut_supervisor');

    final prefs = await SharedPreferences.getInstance();
    final histId = prefs.getInt(_keyHistorialActivo);
    if (histId != null) {
      await _supabase.from('historial_actividades').update({
        'fin_at': DateTime.now().toUtc().toIso8601String(),
        'completada': true,
        'auto_completada': autoCompletada,
      }).eq('id', histId);
      await prefs.remove(_keyHistorialActivo);
    }

    if (actividadValor.isNotEmpty &&
        actividadValor != 'sin_actividad' &&
        actividadValor != 'en_camino' &&
        actividadValor != 'ejecutando') {
      try {
        final pos = await obtenerPosicion();
        await CombustibleSupervisorRutaService.instance
            .registrarTramoAlCompletarActividad(
          rutSupervisor: rutSupervisor,
          actividadValor: actividadValor,
          finLat: pos.latitude,
          finLng: pos.longitude,
          partidaLatFallback: partidaLat,
          partidaLngFallback: partidaLng,
          partidaEtiquetaFallback: partidaEtiqueta,
        );
        SupervisorRutasService().limpiarCache();
      } catch (e) {
        debugPrint('⚠️ [EstadoSupervisor] Tramo combustible al completar: $e');
      }
    }

    _detenerListener100m();
    await cargarEstado(rutSupervisor);
    notifyListeners();
  }

  Future<void> cargarEstado(String rutSupervisor) async {
    try {
      final resp = await _supabase
          .from('estado_supervisor_crea')
          .select()
          .eq('rut_supervisor', rutSupervisor)
          .maybeSingle();
      _estadoActual = resp != null
          ? EstadoSupervisor.fromJson(resp as Map<String, dynamic>)
          : null;
    } catch (e) {
      debugPrint('❌ [EstadoSupervisor] Error cargando: $e');
    }
  }

  /// Suscribirse a cambios en tiempo real
  void suscribirRealtime(String rutSupervisor) {
    _canalRealtime?.unsubscribe();
    _canalRealtime = _supabase
        .channel('estado_supervisor_$rutSupervisor')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'estado_supervisor_crea',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'rut_supervisor',
            value: rutSupervisor,
          ),
          callback: (payload) {
            _estadoActual = EstadoSupervisor.fromJson(
                payload.newRecord as Map<String, dynamic>);
            notifyListeners();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'estado_supervisor_crea',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'rut_supervisor',
            value: rutSupervisor,
          ),
          callback: (payload) {
            _estadoActual = EstadoSupervisor.fromJson(
                payload.newRecord as Map<String, dynamic>);
            notifyListeners();
          },
        )
        .subscribe();
  }

  void cancelarSuscripcion() {
    _canalRealtime?.unsubscribe();
    _canalRealtime = null;
  }

  /// Obtener técnicos del equipo + BODEGA (para solicitudes de ayuda)
  Future<List<Map<String, String>>> obtenerTecnicosParaDestino(
      String rutSupervisor) async {
    try {
      final rutsEquipo = await _supabase
          .from('supervisor_tecnicos_crea')
          .select('rut_tecnico')
          .eq('rut_supervisor', rutSupervisor);
      final ruts = (rutsEquipo as List)
          .map((e) => e['rut_tecnico'] as String)
          .toList();

      if (ruts.isEmpty) {
        return [{'rut': 'BODEGA', 'nombre': 'BODEGA'}];
      }

      final tecnicos = await _supabase
          .from('nomina_tecnicos')
          .select('rut, nombres, paterno, materno')
          .inFilter('rut', ruts)
          .eq('estado_vigencia', 'Vigente')
          .order('paterno');

      final lista = <Map<String, String>>[
        {'rut': 'BODEGA', 'nombre': 'BODEGA'},
      ];
      for (final t in tecnicos as List) {
        final m = Map<String, dynamic>.from(t as Map);
        lista.add({
          'rut': m['rut'] as String? ?? '',
          'nombre': _nombreDesdeNomina(m).isNotEmpty
              ? _nombreDesdeNomina(m)
              : m['rut']?.toString() ?? '',
        });
      }
      return lista;
    } catch (e) {
      debugPrint('❌ [EstadoSupervisor] Error técnicos: $e');
      return [{'rut': 'BODEGA', 'nombre': 'BODEGA'}];
    }
  }

  /// Obtener TODOS los técnicos activos (para movimiento de materiales)
  Future<List<Map<String, String>>> obtenerTodosTecnicosParaMovimiento() async {
    try {
      final tecnicos = await _supabase
          .from('nomina_tecnicos')
          .select('rut, nombres, paterno, materno')
          .eq('estado_vigencia', 'Vigente')
          .order('paterno');

      final lista = <Map<String, String>>[
        {'rut': 'BODEGA', 'nombre': 'BODEGA'},
      ];
      for (final t in tecnicos as List) {
        final m = Map<String, dynamic>.from(t as Map);
        lista.add({
          'rut': m['rut'] as String? ?? '',
          'nombre': _nombreDesdeNomina(m).isNotEmpty
              ? _nombreDesdeNomina(m)
              : m['rut']?.toString() ?? '',
        });
      }
      return lista;
    } catch (e) {
      debugPrint('❌ [EstadoSupervisor] Error todos técnicos: $e');
      return [{'rut': 'BODEGA', 'nombre': 'BODEGA'}];
    }
  }

  /// Listener para auto-completar a 100m (Geolocator.distanceBetween en metros)
  void _iniciarListener100m(
      String rutSupervisor, String ticketId, double latDest, double lngDest) {
    _detenerListener100m();
    bool countdownIniciado = false;

    _locationCheckTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) async {
        if (_estadoActual?.ticketIdActivo != ticketId) return;
        try {
          final pos = await obtenerPosicion();
          final distMetros = Geolocator.distanceBetween(
            pos.latitude, pos.longitude, latDest, lngDest,
          );
          if (distMetros <= 100 && !countdownIniciado) {
            countdownIniciado = true;
            _onCountdownNotificacion?.call();
            _countdownTimer = Timer(const Duration(minutes: 10), () async {
              await completarActividad(rutSupervisor, autoCompletada: true);
              _onAutoCompletado?.call();
            });
          }
        } catch (_) {}
      },
    );
  }

  void _detenerListener100m() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _locationCheckTimer?.cancel();
    _locationCheckTimer = null;
  }

  void setOnCountdownNotificacion(VoidCallback? cb) =>
      _onCountdownNotificacion = cb;
  void setOnAutoCompletado(VoidCallback? cb) => _onAutoCompletado = cb;

  /// Al ACEPTAR ticket de ayuda: upsert estado_supervisor con actividad = 'en_camino'
  Future<void> iniciarAyudaEnCamino({
    required String rutSupervisor,
    required String nombreSupervisor,
    required String ticketId,
    required String rutTecnico,
    required String nombreTecnico,
    required String tipoAyuda,
    required double lat,
    required double lng,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _supabase.from('estado_supervisor_crea').upsert({
      'rut_supervisor': rutSupervisor,
      'nombre_supervisor': nombreSupervisor,
      'actividad': 'en_camino',
      'actividad_desde': now,
      'ticket_id_activo': ticketId,
      'rut_tecnico_activo': rutTecnico,
      'nombre_tecnico_activo': nombreTecnico,
      'tipo_ayuda_activo': tipoAyuda,
      'lat': lat,
      'lng': lng,
      'ubicacion_at': now,
      'updated_at': now,
    }, onConflict: 'rut_supervisor');
    await cargarEstado(rutSupervisor);
    notifyListeners();
  }

  /// Al LLEGAR al técnico: actividad = 'ejecutando' + tramo combustible.
  Future<void> marcarLlegadaAyuda({
    required String rutSupervisor,
    required String ticketId,
    required String nombreTecnico,
  }) async {
    final partidaLat = _estadoActual?.lat;
    final partidaLng = _estadoActual?.lng;
    final now = DateTime.now().toUtc().toIso8601String();
    double? llegadaLat;
    double? llegadaLng;

    try {
      final pos = await obtenerPosicion();
      llegadaLat = pos.latitude;
      llegadaLng = pos.longitude;
      await CombustibleSupervisorRutaService.instance
          .registrarTramoAlMarcarLlegada(
        rutSupervisor: rutSupervisor,
        ticketId: ticketId,
        nombreTecnico: nombreTecnico,
        finLat: pos.latitude,
        finLng: pos.longitude,
        partidaLatFallback: partidaLat,
        partidaLngFallback: partidaLng,
      );
      SupervisorRutasService().limpiarCache();
    } catch (e) {
      debugPrint('⚠️ [EstadoSupervisor] Tramo combustible al llegar: $e');
    }

    await _supabase.from('estado_supervisor_crea').upsert({
      'rut_supervisor': rutSupervisor,
      'actividad': 'ejecutando',
      'actividad_desde': now,
      if (llegadaLat != null) 'lat': llegadaLat,
      if (llegadaLng != null) 'lng': llegadaLng,
      if (llegadaLat != null) 'ubicacion_at': now,
      'updated_at': now,
    }, onConflict: 'rut_supervisor');
    await cargarEstado(rutSupervisor);
    notifyListeners();
  }

  /// Al COMPLETAR o RECHAZAR ticket: limpiar estado_supervisor
  Future<void> limpiarEstadoAyuda(String rutSupervisor) async {
    await _supabase.from('estado_supervisor_crea').upsert({
      'rut_supervisor': rutSupervisor,
      'actividad': 'sin_actividad',
      'actividad_desde': null,
      'ticket_id_activo': null,
      'rut_tecnico_activo': null,
      'nombre_tecnico_activo': null,
      'tipo_ayuda_activo': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'rut_supervisor');
    await cargarEstado(rutSupervisor);
    notifyListeners();
  }

  /// Recovery: verificar si hay actividad en curso al abrir la app
  /// Retorna true si hay actividad activa sin completar
  Future<bool> verificarRecoveryActividad(String rutSupervisor) async {
    final prefs = await SharedPreferences.getInstance();
    final histId = prefs.getInt(_keyHistorialActivo);
    if (histId == null) return false;

    try {
      final resp = await _supabase
          .from('historial_actividades')
          .select()
          .eq('id', histId)
          .maybeSingle();

      if (resp == null) {
        await prefs.remove(_keyHistorialActivo);
        return false;
      }
      final completada = resp['completada'] as bool? ?? true;
      if (completada) {
        await prefs.remove(_keyHistorialActivo);
        return false;
      }
      await cargarEstado(rutSupervisor);
      notifyListeners();

      // Si es movimiento_material, reiniciar listener GPS para auto-completar a 100m
      final ticketId = resp['ticket_id'] as String?;
      if (resp['actividad'] == 'movimiento_material' &&
          ticketId != null &&
          ticketId.isNotEmpty) {
        try {
          final ticket = await _supabase
              .from('ayuda_terreno_crea')
              .select('lat_destino, lng_destino')
              .eq('ticket_id', ticketId)
              .maybeSingle();
          final latDest = (ticket?['lat_destino'] as num?)?.toDouble();
          final lngDest = (ticket?['lng_destino'] as num?)?.toDouble();
          if (latDest != null && lngDest != null) {
            _iniciarListener100m(rutSupervisor, ticketId, latDest, lngDest);
          }
        } catch (_) {}
      }
      return true;
    } catch (e) {
      debugPrint('❌ [EstadoSupervisor] Recovery: $e');
      return false;
    }
  }

  void dispose() {
    cancelarSuscripcion();
    _detenerListener100m();
  }
}

import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/config/constants.dart';
import 'package:agente_desconexiones/services/logistica_service.dart';

class UbicacionService {
  UbicacionService._();
  static final UbicacionService instance = UbicacionService._();

  StreamSubscription<ServiceStatus>? _statusSub;
  bool _gpsActivo = true;

  // ── Upsert ubicación en Supabase ──────────────────────────────────────────

  static Future<void> publicarUbicacion({
    required String rutTecnico,
    required double lat,
    required double lng,
    bool gpsActivo = true,
  }) async {
    try {
      final supabase = Supabase.instance.client;
      print('📡 [UbicSvc] Upsert → rut=$rutTecnico lat=$lat lng=$lng');
      await supabase.from('ubicaciones_activas').upsert({
        'rut_tecnico': rutTecnico,
        'lat':         lat,
        'lng':         lng,
        'gps_activo':  gpsActivo,
        'updated_at':  DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'rut_tecnico');
      print('✅ [UbicSvc] Upsert exitoso');
    } catch (e) {
      print('❌ [UbicSvc] Error en upsert: $e');
    }
  }

  // ── Marcar GPS apagado ────────────────────────────────────────────────────

  static Future<void> marcarGpsApagado(String rutTecnico) async {
    try {
      final supabase = Supabase.instance.client;
      await supabase.from('ubicaciones_activas').upsert({
        'rut_tecnico': rutTecnico,
        'lat':         0.0,
        'lng':         0.0,
        'gps_activo':  false,
        'updated_at':  DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'rut_tecnico');
      await _notificarSupervisoresGpsApagado(rutTecnico);
    } catch (_) {}
  }

  // ── Notificar supervisores cuando GPS se apaga (via Supabase realtime) ───

  static Future<void> _notificarSupervisoresGpsApagado(String rut) async {
    try {
      final supabase = Supabase.instance.client;
      final prefs   = await SharedPreferences.getInstance();
      final nombre  = prefs.getString('nombre_tecnico') ?? rut;

      await supabase.from('alertas_gps_apagado').insert({
        'rut_tecnico':    rut,
        'nombre_tecnico': nombre,
        'created_at':     DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
  }

  // ── Iniciar monitoreo de estado del GPS (foreground) ─────────────────────

  void iniciarMonitoreoEstadoGps(String rutTecnico) {
    _statusSub?.cancel();
    _statusSub = Geolocator.getServiceStatusStream().listen((status) async {
      final activo = status == ServiceStatus.enabled;
      if (!activo && _gpsActivo) {
        // GPS se acaba de apagar
        _gpsActivo = false;
        await marcarGpsApagado(rutTecnico);
      } else if (activo && !_gpsActivo) {
        _gpsActivo = true;
        // GPS volvió a encenderse: publicar posición actual de inmediato
        try {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
          );
          await publicarUbicacion(
            rutTecnico: rutTecnico,
            lat: pos.latitude,
            lng: pos.longitude,
            gpsActivo: true,
          );
        } catch (_) {
          // No se pudo obtener posición, el ciclo de background lo actualizará
        }
      }
    });
  }

  void detener() {
    _statusSub?.cancel();
    _statusSub = null;
  }

  // ── Calcular distancia entre dos coordenadas (Haversine) ─────────────────

  static double distanciaKm(double lat1, double lng1, double lat2, double lng2) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2) / 1000;
  }

  /// `true` si la fila de [ubicaciones_activas] se actualizó recientemente.
  static bool ubicacionVigente(
    String? updatedAtIso, {
    int maxMinutos = kMaterialGpsMaxAntiguedadMinutos,
  }) {
    if (updatedAtIso == null || updatedAtIso.isEmpty) return false;
    final t = DateTime.tryParse(updatedAtIso);
    if (t == null) return false;
    final diff = DateTime.now().toUtc().difference(t.toUtc()).inMinutes;
    return diff >= 0 && diff <= maxMinutos;
  }

  // ── Obtener técnicos dentro del radio con GPS activo ─────────────────────

  static Future<List<Map<String, dynamic>>> obtenerTecnicosCercanos({
    required double latSolicitante,
    required double lngSolicitante,
    double? radioKm = 5.0,
    String? excluirRut,
  }) {
    return obtenerTecnicosOrdenadosPorDistancia(
      latSolicitante: latSolicitante,
      lngSolicitante: lngSolicitante,
      radioKm: radioKm,
      excluirRut: excluirRut,
    );
  }

  /// Técnicos con GPS activo, ordenados por distancia al solicitante.
  /// Si [radioKm] es `null`, no aplica límite de distancia (plantel completo).
  static Future<List<Map<String, dynamic>>> obtenerTecnicosOrdenadosPorDistancia({
    required double latSolicitante,
    required double lngSolicitante,
    double? radioKm = 5.0,
    String? excluirRut,
  }) async {
    try {
      final supabase = Supabase.instance.client;
      final rows = await supabase
          .from('ubicaciones_activas')
          .select()
          .eq('gps_activo', true);

      final List<Map<String, dynamic>> resultado = [];
      for (final row in rows as List) {
        final rut = row['rut_tecnico'] as String? ?? '';
        if (excluirRut != null &&
            LogisticaService.sameRut(rut, excluirRut)) {
          continue;
        }

        if (!ubicacionVigente(row['updated_at'] as String?)) continue;

        final lat = (row['lat'] as num?)?.toDouble() ?? 0;
        final lng = (row['lng'] as num?)?.toDouble() ?? 0;
        if (lat.abs() < 0.0001 && lng.abs() < 0.0001) continue;

        final dist = distanciaKm(latSolicitante, lngSolicitante, lat, lng);
        if (radioKm != null && dist > radioKm) continue;
        resultado.add({...row, 'distancia_km': dist});
      }

      resultado.sort((a, b) =>
          (a['distancia_km'] as double).compareTo(b['distancia_km'] as double));
      return resultado;
    } catch (_) {
      return [];
    }
  }
}

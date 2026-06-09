import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/models/solicitud_material.dart';
import 'package:agente_desconexiones/services/logistica_service.dart';

/// Registra tramos de combustible por entregas de material (GPS real).
/// Partida → encuentro (firma guía) → [opcional] OT iniciada del viajero.
class CombustibleMaterialRutaService {
  CombustibleMaterialRutaService._();
  static final CombustibleMaterialRutaService instance =
      CombustibleMaterialRutaService._();

  final _db = Supabase.instance.client;
  static const _factorCorreccion = 1.30;
  static const _rendimientoKm = 13.0;
  static const _precioLitro = 1500.0;

  // ── Partida del viaje ─────────────────────────────────────────

  /// Guarda GPS de partida en la solicitud (ven_por_el: botón "Voy por el").
  Future<bool> registrarPartidaSolicitud({
    required String solicitudId,
    required String rutViajero,
    required double lat,
    required double lng,
  }) async {
    try {
      await _db.from('solicitudes_material').update({
        'lat_partida': lat,
        'lng_partida': lng,
        'partida_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', solicitudId);
      debugPrint('[MatRuta] partida $rutViajero → ($lat, $lng)');
      return true;
    } catch (e) {
      debugPrint('[MatRuta] error partida: $e');
      return false;
    }
  }

  /// Partida encadenada (fin del viaje anterior) o la guardada en la solicitud.
  Future<({double lat, double lng})?> resolverPartida({
    required SolicitudMaterial sol,
    required String rutViajero,
  }) async {
    if (sol.latPartida != null &&
        sol.lngPartida != null &&
        _coordsValidas(sol.latPartida!, sol.lngPartida!)) {
      return (lat: sol.latPartida!, lng: sol.lngPartida!);
    }

    try {
      final row = await _db
          .from('combustible_ruta_estado')
          .select('lat, lng')
          .eq('rut_tecnico', rutViajero)
          .maybeSingle();
      if (row != null) {
        final lat = (row['lat'] as num?)?.toDouble();
        final lng = (row['lng'] as num?)?.toDouble();
        if (lat != null && lng != null && _coordsValidas(lat, lng)) {
          return (lat: lat, lng: lng);
        }
      }
      for (final entry in await _db
          .from('combustible_ruta_estado')
          .select('rut_tecnico, lat, lng')) {
        final map = entry as Map<String, dynamic>;
        if (!LogisticaService.sameRut(
            map['rut_tecnico'] as String? ?? '', rutViajero)) {
          continue;
        }
        final lat = (map['lat'] as num?)?.toDouble();
        final lng = (map['lng'] as num?)?.toDouble();
        if (lat != null && lng != null && _coordsValidas(lat, lng)) {
          return (lat: lat, lng: lng);
        }
      }
    } catch (e) {
      debugPrint('[MatRuta] error resolverPartida: $e');
    }

    if (sol.modalidad == 'yo_te_lo_llevo' &&
        sol.latEntregador != null &&
        sol.lngEntregador != null &&
        _coordsValidas(sol.latEntregador!, sol.lngEntregador!)) {
      return (lat: sol.latEntregador!, lng: sol.lngEntregador!);
    }

    return null;
  }

  String rutViajero(SolicitudMaterial sol) =>
      sol.modalidad == 'ven_por_el'
          ? sol.rutSolicitante
          : (sol.rutEntregador ?? '');

  // ── Al firmar guía: combustible + tramos ────────────────────

  Future<void> registrarTramosAlFirmar({
    required SolicitudMaterial sol,
    required double? finLat,
    required double? finLng,
    String? guiaId,
  }) async {
    final modalidad = sol.modalidad;
    if (modalidad == null) return;
    if (finLat == null || finLng == null || !_coordsValidas(finLat, finLng)) {
      debugPrint('[MatRuta] sin GPS fin guía — omitiendo tramos');
      return;
    }

    final rutVia = rutViajero(sol);
    if (rutVia.isEmpty) return;

    final partida = await resolverPartida(sol: sol, rutViajero: rutVia);
    if (partida == null) {
      debugPrint('[MatRuta] sin partida GPS para $rutVia');
      return;
    }

    final kmIda = _distanciaKm(
      partida.lat, partida.lng, finLat, finLng,
    );

    final otIniciada = await _ordenIniciadaConCoords(rutVia);
    double kmVuelta = 0;
    String? p4Ot;
    double? p4Lat;
    double? p4Lng;
    var incluyeVuelta = false;

    if (otIniciada != null) {
      p4Ot = otIniciada.orden;
      p4Lat = otIniciada.lat;
      p4Lng = otIniciada.lng;
      if (p4Lat != null && p4Lng != null && _coordsValidas(p4Lat, p4Lng)) {
        kmVuelta = _distanciaKm(finLat, finLng, p4Lat, p4Lng);
        incluyeVuelta = kmVuelta > 0.05;
      }
    }

    final p1Ot = otIniciada?.orden;
    try {
      await _db.from('combustible_materiales').insert({
        'solicitud_id': sol.id,
        'guia_id': guiaId ?? sol.guiaId,
        'modalidad': modalidad,
        'rut_entregador': sol.rutEntregador,
        'rut_solicitante': sol.rutSolicitante,
        'p1_orden_trabajo': p1Ot,
        'p1_lat': partida.lat,
        'p1_lng': partida.lng,
        'p2_lat': finLat,
        'p2_lng': finLng,
        'p3_lat': finLat,
        'p3_lng': finLng,
        'p4_orden_trabajo': incluyeVuelta ? p4Ot : null,
        'p4_lat': incluyeVuelta ? p4Lat : null,
        'p4_lng': incluyeVuelta ? p4Lng : null,
        'km_ida': kmIda,
        'km_vuelta': incluyeVuelta ? kmVuelta : 0,
        'incluye_vuelta': incluyeVuelta,
      });
      debugPrint(
          '[MatRuta] combustible_materiales ida=${kmIda.toStringAsFixed(1)}km '
          'vuelta=${incluyeVuelta ? kmVuelta.toStringAsFixed(1) : "0"}km');
    } catch (e) {
      debugPrint('[MatRuta] error combustible_materiales: $e');
    }

    final fecha = DateTime.now().toIso8601String().substring(0, 10);
    final hora = DateTime.now().toIso8601String().substring(11, 19);
    final etiquetaEncuentro = 'MAT-${sol.id.substring(0, 8)}';

    await _insertarTramo(
      rut: rutVia,
      fecha: fecha,
      desde: 'PARTIDA',
      hasta: etiquetaEncuentro,
      km: kmIda,
      hora: hora,
    );

    if (incluyeVuelta && p4Ot != null) {
      await _insertarTramo(
        rut: rutVia,
        fecha: fecha,
        desde: etiquetaEncuentro,
        hasta: p4Ot,
        km: kmVuelta,
        hora: hora,
      );
      await _guardarPuntoPartidaSiguiente(
        rut: rutVia,
        lat: p4Lat!,
        lng: p4Lng!,
        orden: p4Ot,
      );
    } else {
      await _guardarPuntoPartidaSiguiente(
        rut: rutVia,
        lat: finLat,
        lng: finLng,
        orden: null,
      );
    }
  }

  Future<void> _insertarTramo({
    required String rut,
    required String fecha,
    required String desde,
    required String hasta,
    required double km,
    required String hora,
  }) async {
    if (km < 0.05) return;
    final litros = km / _rendimientoKm;
    final costo = litros * _precioLitro;
    try {
      await _db.from('combustible_tramos').insert({
        'rut_tecnico': rut,
        'fecha': fecha,
        'orden_desde': desde,
        'orden_hasta': hasta,
        'km_tramo': km,
        'litros_tramo': litros,
        'costo_tramo': costo,
        'hora_fin_hasta': hora,
      });
      debugPrint(
          '[MatRuta] tramo $desde→$hasta ${km.toStringAsFixed(1)}km ($rut)');
    } catch (e) {
      debugPrint('[MatRuta] error combustible_tramos: $e');
    }
  }

  Future<void> _guardarPuntoPartidaSiguiente({
    required String rut,
    required double lat,
    required double lng,
    String? orden,
  }) async {
    try {
      await _db.from('combustible_ruta_estado').upsert({
        'rut_tecnico': rut,
        'lat': lat,
        'lng': lng,
        'orden_trabajo': orden,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'rut_tecnico');
    } catch (e) {
      debugPrint('[MatRuta] error ruta_estado: $e');
    }
  }

  Future<({String orden, double? lat, double? lng})?> _ordenIniciadaConCoords(
    String rut,
  ) async {
    try {
      final hoy = DateTime.now();
      final ayer = hoy.subtract(const Duration(days: 1));
      final desde =
          '${ayer.year}-${ayer.month.toString().padLeft(2, '0')}-${ayer.day.toString().padLeft(2, '0')}';

      final rows = await _db
          .from('produccion_creaciones')
          .select(
              'orden_trabajo, estado, coord_x, coord_y, hora_inicio, fecha_proceso')
          .eq('rut_tecnico', rut)
          .gte('fecha_proceso', desde)
          .order('fecha_proceso', ascending: false)
          .order('hora_inicio', ascending: false)
          .limit(20);

      Map<String, dynamic>? mejor;
      for (final raw in rows as List) {
        final row = raw as Map<String, dynamic>;
        final est = (row['estado']?.toString() ?? '').toLowerCase();
        if (est != 'iniciado') continue;
        final ot = row['orden_trabajo']?.toString() ?? '';
        if (ot.isEmpty) continue;
        mejor = row;
        break;
      }
      if (mejor == null) return null;
      final lat = double.tryParse(mejor['coord_y']?.toString() ?? '');
      final lng = double.tryParse(mejor['coord_x']?.toString() ?? '');
      return (
        orden: mejor['orden_trabajo']?.toString() ?? '',
        lat: lat,
        lng: lng,
      );
    } catch (e) {
      debugPrint('[MatRuta] error OT iniciada: $e');
    }
    return null;
  }

  /// Traslados de material del día para el mapa de rutas (flota).
  Future<List<Map<String, dynamic>>> tramosMaterialDelDia(
    String rut,
    String fechaYmd,
  ) async {
    try {
      final rows = await _db
          .from('combustible_materiales')
          .select()
          .or('rut_entregador.eq.$rut,rut_solicitante.eq.$rut')
          .gte('created_at', '${fechaYmd}T00:00:00')
          .lt('created_at', '${_diaSiguiente(fechaYmd)}T00:00:00');

      return (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[MatRuta] error tramosMaterialDelDia: $e');
      return [];
    }
  }

  String _diaSiguiente(String ymd) {
    final p = ymd.split('-');
    final d = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
    final s = d.add(const Duration(days: 1));
    return '${s.year}-${s.month.toString().padLeft(2, '0')}-${s.day.toString().padLeft(2, '0')}';
  }

  double _distanciaKm(double lat1, double lon1, double lat2, double lon2) {
    final m = Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
    return (m / 1000) * _factorCorreccion;
  }

  bool _coordsValidas(double lat, double lng) =>
      lat.abs() > 0.0001 && lng.abs() > 0.0001;
}

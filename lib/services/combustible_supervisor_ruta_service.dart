import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/models/estado_supervisor.dart';
import 'package:agente_desconexiones/services/logistica_service.dart';

/// Tramos de combustible por GPS para supervisores (MI ACTIVIDAD + ayuda en terreno).
/// Encadena partidas vía [combustible_ruta_estado]; omite tramos &lt; 50 m.
class CombustibleSupervisorRutaService {
  CombustibleSupervisorRutaService._();
  static final CombustibleSupervisorRutaService instance =
      CombustibleSupervisorRutaService._();

  final _db = Supabase.instance.client;
  static const _factorCorreccion = 1.30;
  static const _rendimientoKm = 13.0;
  static const _precioLitro = 1500.0;
  static const _kmMinimo = 0.05;

  static String etiquetaActividad(String valor) {
    for (final a in ActividadSupervisor.values) {
      if (a.valorSupabase == valor) return a.displayName;
    }
    if (valor == 'en_camino') return 'En camino (ayuda)';
    if (valor == 'ejecutando') return 'Ejecutando ayuda';
    return valor;
  }

  /// Partida encadenada o coordenadas de respaldo (inicio actividad / aceptar ayuda).
  Future<({double lat, double lng, String etiqueta})?> resolverPartida({
    required String rutSupervisor,
    double? latFallback,
    double? lngFallback,
    String? etiquetaFallback,
  }) async {
    try {
      for (final entry in await _db
          .from('combustible_ruta_estado')
          .select('rut_tecnico, lat, lng, orden_trabajo')) {
        final map = entry as Map<String, dynamic>;
        if (!LogisticaService.sameRut(
            map['rut_tecnico'] as String? ?? '', rutSupervisor)) {
          continue;
        }
        final lat = (map['lat'] as num?)?.toDouble();
        final lng = (map['lng'] as num?)?.toDouble();
        if (lat != null && lng != null && _coordsValidas(lat, lng)) {
          final etq = (map['orden_trabajo'] as String?)?.trim();
          return (
            lat: lat,
            lng: lng,
            etiqueta: etq != null && etq.isNotEmpty ? etq : 'PARTIDA',
          );
        }
      }
    } catch (e) {
      debugPrint('[SupRuta] error resolverPartida: $e');
    }

    if (latFallback != null &&
        lngFallback != null &&
        _coordsValidas(latFallback, lngFallback)) {
      return (
        lat: latFallback,
        lng: lngFallback,
        etiqueta: etiquetaFallback ?? 'PARTIDA',
      );
    }
    return null;
  }

  /// Registra tramo al cerrar actividad (GPS al completar).
  Future<void> registrarTramoAlCompletarActividad({
    required String rutSupervisor,
    required String actividadValor,
    required double finLat,
    required double finLng,
    double? partidaLatFallback,
    double? partidaLngFallback,
    String? partidaEtiquetaFallback,
  }) async {
    final hasta = etiquetaActividad(actividadValor);
    await _registrarTramo(
      rut: rutSupervisor,
      finLat: finLat,
      finLng: finLng,
      etiquetaHasta: hasta,
      partidaLatFallback: partidaLatFallback,
      partidaLngFallback: partidaLngFallback,
      partidaEtiquetaFallback: partidaEtiquetaFallback,
      tipoLeg: 'supervisor_actividad',
    );
  }

  /// Registra tramo al marcar llegada en ayuda en terreno.
  Future<void> registrarTramoAlMarcarLlegada({
    required String rutSupervisor,
    required String ticketId,
    required String nombreTecnico,
    required double finLat,
    required double finLng,
    double? partidaLatFallback,
    double? partidaLngFallback,
  }) async {
    final corto = ticketId.length > 8 ? ticketId.substring(0, 8) : ticketId;
    final hasta = 'AYUDA-$corto (${nombreTecnico.trim()})';
    await _registrarTramo(
      rut: rutSupervisor,
      finLat: finLat,
      finLng: finLng,
      etiquetaHasta: hasta,
      partidaLatFallback: partidaLatFallback,
      partidaLngFallback: partidaLngFallback,
      partidaEtiquetaFallback: 'Aceptación ayuda',
      tipoLeg: 'supervisor_ayuda',
    );
  }

  Future<void> _registrarTramo({
    required String rut,
    required double finLat,
    required double finLng,
    required String etiquetaHasta,
    double? partidaLatFallback,
    double? partidaLngFallback,
    String? partidaEtiquetaFallback,
    required String tipoLeg,
  }) async {
    if (!_coordsValidas(finLat, finLng)) {
      debugPrint('[SupRuta] fin sin GPS válido — omitiendo');
      return;
    }

    final partida = await resolverPartida(
      rutSupervisor: rut,
      latFallback: partidaLatFallback,
      lngFallback: partidaLngFallback,
      etiquetaFallback: partidaEtiquetaFallback,
    );
    if (partida == null) {
      debugPrint('[SupRuta] sin partida para $rut');
      await _guardarPuntoPartidaSiguiente(
        rut: rut,
        lat: finLat,
        lng: finLng,
        etiqueta: etiquetaHasta,
      );
      return;
    }

    final km = _distanciaKm(
      partida.lat, partida.lng, finLat, finLng,
    );

    final fecha = DateTime.now().toIso8601String().substring(0, 10);
    final hora = DateTime.now().toIso8601String().substring(11, 19);

    if (km >= _kmMinimo) {
      final litros = km / _rendimientoKm;
      final costo = litros * _precioLitro;
      try {
        await _db.from('combustible_tramos').insert({
          'rut_tecnico': rut,
          'fecha': fecha,
          'orden_desde': partida.etiqueta,
          'orden_hasta': etiquetaHasta,
          'km_tramo': km,
          'litros_tramo': litros,
          'costo_tramo': costo,
          'hora_fin_hasta': hora,
          'tipo_leg': tipoLeg,
        });
        debugPrint(
            '[SupRuta] tramo ${partida.etiqueta}→$etiquetaHasta '
            '${km.toStringAsFixed(1)}km ($rut)');
      } catch (e) {
        debugPrint('[SupRuta] error combustible_tramos: $e');
        try {
          await _db.from('combustible_tramos').insert({
            'rut_tecnico': rut,
            'fecha': fecha,
            'orden_desde': partida.etiqueta,
            'orden_hasta': etiquetaHasta,
            'km_tramo': km,
            'litros_tramo': litros,
            'costo_tramo': costo,
            'hora_fin_hasta': hora,
          });
        } catch (e2) {
          debugPrint('[SupRuta] insert sin tipo_leg: $e2');
        }
      }
    } else {
      debugPrint('[SupRuta] tramo <50m omitido (${km.toStringAsFixed(2)}km)');
    }

    await _guardarPuntoPartidaSiguiente(
      rut: rut,
      lat: finLat,
      lng: finLng,
      etiqueta: etiquetaHasta,
    );
  }

  Future<void> _guardarPuntoPartidaSiguiente({
    required String rut,
    required double lat,
    required double lng,
    required String etiqueta,
  }) async {
    try {
      await _db.from('combustible_ruta_estado').upsert({
        'rut_tecnico': rut,
        'lat': lat,
        'lng': lng,
        'orden_trabajo': etiqueta,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'rut_tecnico');
    } catch (e) {
      debugPrint('[SupRuta] error ruta_estado: $e');
    }
  }

  /// Tramos del día para mapa de rutas / estanque supervisor.
  Future<List<Map<String, dynamic>>> tramosDelDia(
    String rut,
    String fechaYmd,
  ) async {
    try {
      final rows = await _db
          .from('combustible_tramos')
          .select()
          .eq('rut_tecnico', rut)
          .eq('fecha', fechaYmd)
          .order('created_at');
      return (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[SupRuta] error tramosDelDia: $e');
      return [];
    }
  }

  double _distanciaKm(double lat1, double lon1, double lat2, double lon2) {
    final m = Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
    return (m / 1000) * _factorCorreccion;
  }

  bool _coordsValidas(double lat, double lng) =>
      lat.abs() > 0.0001 && lng.abs() > 0.0001;
}

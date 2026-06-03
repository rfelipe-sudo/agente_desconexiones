import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/ford_ruta.dart';

/// Reemplaza FordApiService: lee OTs desde produccion_creaciones (últimas 2 semanas)
/// y calcula km con Haversine × factor de corrección 1.30.
/// km_diario lo llena pg_cron para la automatización de carga de combustible.
class ProduccionRutasService {
  static const _baseLat = -33.5380;
  static const _baseLng = -70.6882;
  static const _correctionFactor = 1.30;
  static const _cacheTtl = Duration(minutes: 5);

  static final ProduccionRutasService _instance = ProduccionRutasService._();
  factory ProduccionRutasService() => _instance;
  ProduccionRutasService._();

  final _db = Supabase.instance.client;
  final _cache = <String, ({DateTime time, List<FordDiaRuta> data})>{};

  /// OTs de las últimas 2 semanas para [rutTecnico], agrupadas por día.
  Future<List<FordDiaRuta>> getRutasDelTecnico(String rutTecnico) async {
    final cached = _cache[rutTecnico];
    if (cached != null &&
        DateTime.now().difference(cached.time) < _cacheTtl) {
      return cached.data;
    }

    final from = DateTime.now().subtract(const Duration(days: 14));
    final fromStr =
        '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}';

    final rows = await _db
        .from('produccion_creaciones')
        .select(
          'orden_trabajo, fecha_trabajo, rut_tecnico, hora_inicio, hora_fin, '
          'duracion_min, coord_x, coord_y, estado, direccion, zona_trabajo',
        )
        .eq('rut_tecnico', rutTecnico)
        .gte('fecha_trabajo', fromStr)
        .order('fecha_trabajo')
        .order('hora_inicio');

    // Agrupa todas las OTs por fecha (incluye OTs sin coords)
    final byDate = <String, List<Map<String, dynamic>>>{};
    for (final raw in (rows as List)) {
      final row = raw as Map<String, dynamic>;
      final rawDate = row['fecha_trabajo']?.toString() ?? '';
      final fecha = rawDate.contains('T') ? rawDate.split('T')[0] : rawDate;
      if (fecha.isEmpty) continue;
      byDate.putIfAbsent(fecha, () => []).add(row);
    }

    final result = <FordDiaRuta>[];
    for (final entry in byDate.entries) {
      final fecha = entry.key; // "yyyy-mm-dd"
      final rawOts = entry.value;

      final fordOts = rawOts.map(_buildOt).toList();
      final traslados = _buildTraslados(fordOts);
      final km = _computeKm(fordOts);

      // fechaToa: "dd/mm/yy" — formato que usa FordDiaRuta.fecha getter
      final parts = fecha.split('-');
      final fechaToa = parts.length == 3
          ? '${parts[2]}/${parts[1]}/${parts[0].substring(2)}'
          : fecha;

      final duracionTotal = rawOts.fold<double>(
        0,
        (s, r) => s + ((r['duracion_min'] as num?)?.toDouble() ?? 0),
      );

      result.add(FordDiaRuta(
        rut: rutTecnico,
        fechaToa: fechaToa,
        mes: fecha.length >= 7 ? fecha.substring(0, 7) : '',
        kmTotal: km.total,
        kmBodegaIda: km.bodegaIda,
        kmBodegaVuelta: km.bodegaVuelta,
        kmEntreOt: km.entreOt,
        tiempoProductivoMin: duracionTotal,
        tiempoTrasladoMin: 0,
        ots: fordOts,
        traslados: traslados,
      ));
    }

    result.sort((a, b) => a.fecha!.compareTo(b.fecha!));
    _cache[rutTecnico] = (time: DateTime.now(), data: result);
    debugPrint('[ProduccionRutas] ${result.length} días para $rutTecnico');
    return result;
  }

  void limpiarCache() => _cache.clear();

  // ── Builders ──────────────────────────────────────────────────

  FordOt _buildOt(Map<String, dynamic> row) => FordOt(
        orden: row['orden_trabajo']?.toString() ?? '',
        direccion: row['direccion']?.toString() ?? '',
        ciudad: row['zona_trabajo']?.toString() ?? '',
        zona: row['zona_trabajo']?.toString() ?? '',
        coordLat: _parseCoord(row['coord_y']),
        coordLng: _parseCoord(row['coord_x']),
        estado: row['estado']?.toString() ?? '',
        inicio: row['hora_inicio']?.toString() ?? '',
        fin: row['hora_fin']?.toString() ?? '',
        inicioMin: 0,
        finMin: 0,
      );

  double? _parseCoord(dynamic v) {
    if (v == null) return null;
    final d = v is num ? v.toDouble() : double.tryParse(v.toString());
    if (d == null || d == 0) return null;
    return d;
  }

  /// Genera traslados bodega_ida / entre_ot / bodega_vuelta a partir de las
  /// OTs con coordenadas válidas, en orden de hora_inicio.
  List<FordTraslado> _buildTraslados(List<FordOt> ots) {
    final con = ots.where((o) => o.tieneCoords).toList();
    if (con.isEmpty) return [];

    const bodega = FordPunto(
      orden: 'Bodega',
      direccion: 'Avda Lo Espejo 1565',
      ciudad: 'Lo Espejo',
      zona: '',
      inicio: '',
      fin: '',
      estado: '',
    );

    final traslados = <FordTraslado>[];
    var tramo = 0;

    // Base → primera OT
    traslados.add(FordTraslado(
      tipoLeg: 'bodega_ida',
      kmOsrm:
          _hav(_baseLat, _baseLng, con.first.coordLat!, con.first.coordLng!) *
              _correctionFactor,
      tramo: tramo++,
      desde: bodega,
      hasta: _otToPunto(con.first),
    ));

    // OT[i-1] → OT[i]
    for (int i = 1; i < con.length; i++) {
      traslados.add(FordTraslado(
        tipoLeg: 'entre_ot',
        kmOsrm: _hav(
              con[i - 1].coordLat!, con[i - 1].coordLng!,
              con[i].coordLat!, con[i].coordLng!,
            ) *
            _correctionFactor,
        tramo: tramo++,
        desde: _otToPunto(con[i - 1]),
        hasta: _otToPunto(con[i]),
      ));
    }

    // Última OT → base
    traslados.add(FordTraslado(
      tipoLeg: 'bodega_vuelta',
      kmOsrm:
          _hav(con.last.coordLat!, con.last.coordLng!, _baseLat, _baseLng) *
              _correctionFactor,
      tramo: tramo,
      desde: _otToPunto(con.last),
      hasta: bodega,
    ));

    return traslados;
  }

  FordPunto _otToPunto(FordOt o) => FordPunto(
        orden: o.orden,
        direccion: o.direccion,
        ciudad: o.ciudad,
        zona: o.zona,
        inicio: o.inicio,
        fin: o.fin,
        estado: o.estado,
      );

  ({double total, double bodegaIda, double bodegaVuelta, double entreOt})
      _computeKm(List<FordOt> ots) {
    final con = ots.where((o) => o.tieneCoords).toList();
    if (con.isEmpty) {
      return (total: 0, bodegaIda: 0, bodegaVuelta: 0, entreOt: 0);
    }

    final ida =
        _hav(_baseLat, _baseLng, con.first.coordLat!, con.first.coordLng!);
    final vuelta =
        _hav(con.last.coordLat!, con.last.coordLng!, _baseLat, _baseLng);
    var entre = 0.0;
    for (int i = 1; i < con.length; i++) {
      entre += _hav(
        con[i - 1].coordLat!, con[i - 1].coordLng!,
        con[i].coordLat!, con[i].coordLng!,
      );
    }
    final raw = ida + entre + vuelta;
    return (
      total: raw * _correctionFactor,
      bodegaIda: ida * _correctionFactor,
      bodegaVuelta: vuelta * _correctionFactor,
      entreOt: entre * _correctionFactor,
    );
  }

  // ── Haversine ─────────────────────────────────────────────────

  double _hav(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _rad(double deg) => deg * math.pi / 180;
}

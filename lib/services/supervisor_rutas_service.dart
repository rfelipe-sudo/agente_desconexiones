import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/ford_ruta.dart';

/// Rutas del supervisor agrupadas por día desde [combustible_tramos] (GPS real).
class SupervisorRutasService {
  static final SupervisorRutasService _instance = SupervisorRutasService._();
  factory SupervisorRutasService() => _instance;
  SupervisorRutasService._();

  final _db = Supabase.instance.client;
  static const _cacheTtl = Duration(minutes: 5);
  final _cache = <String, ({DateTime time, List<FordDiaRuta> data})>{};

  Future<List<FordDiaRuta>> getRutasDelSupervisor(String rutSupervisor) async {
    final cached = _cache[rutSupervisor];
    if (cached != null &&
        DateTime.now().difference(cached.time) < _cacheTtl) {
      return cached.data;
    }

    final from = DateTime.now().subtract(const Duration(days: 14));
    final fromStr =
        '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}';

    List<Map<String, dynamic>> rows;
    try {
      rows = (await _db
              .from('combustible_tramos')
              .select()
              .eq('rut_tecnico', rutSupervisor)
              .gte('fecha', fromStr)
              .order('fecha')
              .order('created_at'))
          .cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[SupervisorRutas] error: $e');
      return [];
    }

    final byDate = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final fecha = row['fecha']?.toString() ?? '';
      if (fecha.isEmpty) continue;
      byDate.putIfAbsent(fecha, () => []).add(row);
    }

    final result = <FordDiaRuta>[];
    for (final entry in byDate.entries) {
      final fecha = entry.key;
      final traslados = _buildTraslados(entry.value);
      final km = traslados.fold<double>(0, (s, t) => s + t.kmOsrm);

      final parts = fecha.split('-');
      final fechaToa = parts.length == 3
          ? '${parts[2]}/${parts[1]}/${parts[0].substring(2)}'
          : fecha;

      result.add(FordDiaRuta(
        rut: rutSupervisor,
        fechaToa: fechaToa,
        mes: fecha.length >= 7 ? fecha.substring(0, 7) : '',
        kmTotal: km,
        kmBodegaIda: 0,
        kmBodegaVuelta: 0,
        kmEntreOt: km,
        tiempoProductivoMin: 0,
        tiempoTrasladoMin: 0,
        ots: const [],
        traslados: traslados,
      ));
    }

    result.sort((a, b) => a.fecha!.compareTo(b.fecha!));
    _cache[rutSupervisor] = (time: DateTime.now(), data: result);
    debugPrint('[SupervisorRutas] ${result.length} días para $rutSupervisor');
    return result;
  }

  void limpiarCache() => _cache.clear();

  List<FordTraslado> _buildTraslados(List<Map<String, dynamic>> rows) {
    final traslados = <FordTraslado>[];
    var tramo = 0;
    for (final row in rows) {
      final km = (row['km_tramo'] as num?)?.toDouble() ?? 0;
      if (km < 0.05) continue;
      final desde = row['orden_desde']?.toString() ?? 'Partida';
      final hasta = row['orden_hasta']?.toString() ?? 'Destino';
      final tipo = row['tipo_leg']?.toString() ?? 'supervisor_tramo';

      traslados.add(FordTraslado(
        tipoLeg: tipo,
        kmOsrm: km,
        tramo: tramo++,
        desde: FordPunto(
          orden: desde,
          direccion: desde,
          ciudad: '',
          zona: '',
          inicio: row['hora_fin_hasta']?.toString() ?? '',
          fin: '',
          estado: '',
        ),
        hasta: FordPunto(
          orden: hasta,
          direccion: hasta,
          ciudad: '',
          zona: '',
          inicio: '',
          fin: row['hora_fin_hasta']?.toString() ?? '',
          estado: '',
        ),
      ));
    }
    return traslados;
  }
}

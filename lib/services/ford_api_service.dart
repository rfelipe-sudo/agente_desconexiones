import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import '../models/ford_ruta.dart';

class FordApiService {
  static const _baseUrl = 'https://ford.sbip.cl/api/analisis-ruta-cache?limit=50000';
  static const _user = 'ford_api';
  static const _pass = 'Sbip2024!';
  static const _cacheTtl = Duration(minutes: 10);

  static final FordApiService _instance = FordApiService._();
  factory FordApiService() => _instance;
  FordApiService._();

  List<FordDiaRuta>? _cache;
  DateTime? _cacheTime;

  String get _authHeader {
    final creds = base64Encode(utf8.encode('$_user:$_pass'));
    return 'Basic $creds';
  }

  Future<List<FordDiaRuta>> _fetchAll() async {
    final now = DateTime.now();
    if (_cache != null &&
        _cacheTime != null &&
        now.difference(_cacheTime!) < _cacheTtl) {
      return _cache!;
    }

    dev.log('[Ford] fetching $_baseUrl', name: 'Ford');
    final resp = await http.get(
      Uri.parse(_baseUrl),
      headers: {'Authorization': _authHeader},
    ).timeout(const Duration(seconds: 30));

    if (resp.statusCode != 200) {
      throw Exception('Ford API error ${resp.statusCode}');
    }

    final decoded = jsonDecode(resp.body);
    List<dynamic> data;
    if (decoded is List) {
      data = decoded;
    } else if (decoded is Map) {
      final inner = decoded['data'];
      if (inner is Map && inner['registros'] is List) {
        data = inner['registros'] as List<dynamic>;
      } else if (inner is List) {
        data = inner;
      } else {
        throw Exception('Ford API: estructura inesperada');
      }
    } else {
      throw Exception('Ford API: tipo de respuesta inesperado');
    }

    dev.log('[Ford] ${data.length} registros totales', name: 'Ford');
    _cache = data
        .map((e) => FordDiaRuta.fromJson(e as Map<String, dynamic>))
        .toList();
    _cacheTime = now;
    return _cache!;
  }

  String _normalizar(String rut) =>
      rut.replaceAll(RegExp(r'[\.\-\s]'), '').toLowerCase();

  /// Returns the Monday of the ISO week containing [d].
  DateTime _weekStart(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));

  /// All records for [rutTecnico], sorted by date.
  /// Groups by actual date (not the `mes` field, which can be mismatched).
  Future<List<FordDiaRuta>> getRutasDelTecnico(String rutTecnico) async {
    final all = await _fetchAll();
    final rutNorm = _normalizar(rutTecnico);

    // Log de diagnóstico: RUT buscado vs RUTs únicos en el API
    final rutesEnApi = all.map((d) => _normalizar(d.rut)).toSet();
    dev.log('[Ford] buscando rut="$rutNorm" — total registros=${all.length}', name: 'Ford');
    dev.log('[Ford] RUTs en API (${rutesEnApi.length} únicos): ${rutesEnApi.take(10).join(', ')}', name: 'Ford');

    final rutMatch = all.where((d) => _normalizar(d.rut) == rutNorm).toList();
    final rutasFecha = rutMatch.where((d) => d.fecha != null).toList();

    if (rutMatch.isNotEmpty && rutasFecha.isEmpty) {
      dev.log('[Ford] ⚠️ $rutNorm tiene ${rutMatch.length} registros pero todos con fecha_toa inválida. '
          'Ejemplo: "${rutMatch.first.fechaToa}"', name: 'Ford');
    }

    final rutas = rutasFecha;
    rutas.sort((a, b) => a.fecha!.compareTo(b.fecha!));
    dev.log('[Ford] ${rutas.length} registros válidos para $rutNorm', name: 'Ford');
    return rutas;
  }

  /// Records grouped by ISO week start (Monday), sorted oldest → newest.
  /// Only returns the last [maxSemanas] weeks that have data.
  Future<Map<DateTime, List<FordDiaRuta>>> getRutasPorSemana(
    String rutTecnico, {
    int maxSemanas = 4,
  }) async {
    final rutas = await getRutasDelTecnico(rutTecnico);
    final grupos = <DateTime, List<FordDiaRuta>>{};
    for (final dia in rutas) {
      final ws = _weekStart(dia.fecha!);
      grupos.putIfAbsent(ws, () => []).add(dia);
    }
    // Sort desc, take last maxSemanas, then reverse to oldest-first
    final weeks = grupos.keys.toList()..sort((a, b) => b.compareTo(a));
    final selected = weeks.take(maxSemanas).toList()..sort();
    final result = <DateTime, List<FordDiaRuta>>{};
    for (final w in selected) {
      final dias = grupos[w]!;
      dias.sort((a, b) => a.fecha!.compareTo(b.fecha!));
      result[w] = dias;
    }
    dev.log('[Ford] ${result.length} semanas con datos', name: 'Ford');
    return result;
  }

  /// Returns all months available for this technician, sorted desc.
  Future<List<String>> getMesesDisponibles(String rutTecnico) async {
    final rutas = await getRutasDelTecnico(rutTecnico);
    final meses = rutas.map((r) => r.mes).toSet().toList();
    meses.sort((a, b) => b.compareTo(a));
    return meses;
  }

  /// Records for a specific [mes] ("yyyy-mm"), sorted by date.
  Future<List<FordDiaRuta>> getRutasDelMes(
    String rutTecnico,
    String mes,
  ) async {
    final rutas = await getRutasDelTecnico(rutTecnico);
    return rutas.where((r) => r.mes == mes).toList();
  }

  void limpiarCache() {
    _cache = null;
    _cacheTime = null;
  }
}

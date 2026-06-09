// dart run tool/reversa_junio_check.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

const _supabaseUrl = 'https://efvicvqffvxocnrqjxrs.supabase.co';
const _anonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVmdmljdnFmZnZ4b2NucnFqeHJzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjU0Mzc4MjMsImV4cCI6MjA4MTAxMzgyM30._RIVNg4_FoMKDJWbdi8QuS6LSsjjaAapwkTa_9Gb0Cc';

Future<void> main() async {
  final headers = {
    'apikey': _anonKey,
    'Authorization': 'Bearer $_anonKey',
  };

  Future<int> count(String table, String query) async {
    final r = await http.head(
      Uri.parse('$_supabaseUrl/rest/v1/$table?$query&select=id'),
      headers: {...headers, 'Prefer': 'count=exact'},
    );
    final cr = r.headers['content-range'] ?? '';
    final n = cr.contains('/') ? cr.split('/').last : '?';
    return int.tryParse(n) ?? -1;
  }

  Future<List<dynamic>> rows(String table, String query) async {
    final r = await http.get(
      Uri.parse('$_supabaseUrl/rest/v1/$table?$query'),
      headers: headers,
    );
    return jsonDecode(r.body) as List<dynamic>;
  }

  print('=== Kepler get_toa_equipos ===');
  final k = await http.get(
    Uri.parse('https://kepler.sbip.cl/api/v1/toa/get_toa_equipos'),
  );
  print('HTTP ${k.statusCode}');
  final raw = jsonDecode(k.body);
  final items = raw is List ? raw : (raw['data'] as List? ?? []);
  final crea = items.where((x) {
    final m = x as Map<String, dynamic>;
    return m['DESC_EMPRESA'] == 'CREACIONES TECNOLOGICAS' &&
        m['SERIAL_NO'] != null &&
        m['ID_ACTIVIDAD'] != null;
  }).toList();
  print('Total Kepler: ${items.length} | CREA con serial+OT: ${crea.length}');

  print('\n=== Supabase equipos_reversa ===');
  final total = await count('equipos_reversa', '');
  final mayo = await count(
    'equipos_reversa',
    'fecha_desinstalacion=gte.2026-05-01&fecha_desinstalacion=lte.2026-05-31',
  );
  final junio = await count(
    'equipos_reversa',
    'fecha_desinstalacion=gte.2026-06-01&fecha_desinstalacion=lte.2026-06-30',
  );
  print('Total: $total | Mayo 2026: $mayo | Junio 2026: $junio');

  final ultimos = await rows(
    'equipos_reversa',
    'select=serial,ot,tecnico_rut,fecha_desinstalacion,estado&order=fecha_desinstalacion.desc&limit=5',
  );
  print('Últimos registros:');
  for (final e in ultimos) {
    final m = e as Map<String, dynamic>;
    print('  ${m['fecha_desinstalacion']} | ${m['ot']} | ${m['serial']} | ${m['estado']}');
  }

  print('\n=== OTs junio en produccion_creaciones ===');
  final prodJun = await rows(
    'produccion_creaciones',
    'select=orden_trabajo,fecha_trabajo&fecha_trabajo=ilike.*%2F06%2F26&limit=30',
  );
  final otsJun = prodJun
      .map((e) => (e as Map)['orden_trabajo']?.toString() ?? '')
      .where((o) => o.isNotEmpty)
      .toSet()
      .toList();
  print('OTs junio (muestra ${otsJun.length}): ${otsJun.take(8).join(', ')}');

  if (otsJun.isNotEmpty) {
    final ot = otsJun.first;
    final enReversa = await rows(
      'equipos_reversa',
      'select=serial,fecha_desinstalacion,estado&ot=eq.$ot&limit=5',
    );
    print('Reversa para OT $ot: ${enReversa.length} filas -> $enReversa');

    final enKepler = crea.where((x) => (x as Map)['ID_ACTIVIDAD'] == ot).length;
    print('Equipos Kepler para OT $ot: $enKepler');
  }

  print('\n=== KRP /inventario/api/reversa ===');
  final krpGet = await http.get(
    Uri.parse('https://logistica.sbip.cl/inventario/api/reversa'),
  );
  print('GET HTTP ${krpGet.statusCode} (esperado 405 = solo POST)');
}

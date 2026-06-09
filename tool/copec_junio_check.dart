// dart run tool/copec_junio_check.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

const _url = 'https://ford.sbip.cl/api/combustible/copec-auto/detalle';
const _user = 'ford_api';
const _pass = 'Sbip2024!';

Future<void> main() async {
  final creds = base64Encode(utf8.encode('$_user:$_pass'));
  final resp = await http.get(
    Uri.parse(_url),
    headers: {'Authorization': 'Basic $creds'},
  );

  print('HTTP ${resp.statusCode}');
  if (resp.statusCode != 200) {
    print(resp.body.substring(0, resp.body.length.clamp(0, 300)));
    return;
  }

  final raw = jsonDecode(resp.body);
  final List<dynamic> cargas;
  if (raw is List) {
    cargas = raw;
  } else if (raw is Map) {
    cargas = (raw['data'] as List?) ?? [];
  } else {
    print('Formato inesperado: ${raw.runtimeType}');
    return;
  }

  print('Total cargas API: ${cargas.length}');

  final porMes = <String, int>{};
  final junio = <Map<String, dynamic>>[];

  for (final item in cargas) {
    if (item is! Map) continue;
    final m = Map<String, dynamic>.from(item);
    final fecha = m['fecha']?.toString() ?? '';
    if (fecha.isEmpty) continue;

    String mesKey;
    if (fecha.contains('-')) {
      mesKey = fecha.length >= 7 ? fecha.substring(0, 7) : fecha;
    } else {
      mesKey = fecha;
    }
    porMes[mesKey] = (porMes[mesKey] ?? 0) + 1;

    if (fecha.startsWith('2026-06')) {
      junio.add(m);
    }
  }

  print('\nCargas por mes (fecha campo):');
  final meses = porMes.keys.toList()..sort();
  for (final k in meses) {
    print('  $k: ${porMes[k]}');
  }

  print('\n=== Junio 2026 ===');
  print('Cargas con fecha 2026-06-*: ${junio.length}');
  if (junio.isNotEmpty) {
    junio.sort((a, b) => (a['fecha'] ?? '').compareTo(b['fecha'] ?? ''));
    print('Primera: ${junio.first['fecha']} ${junio.first['hora']} | '
        '${junio.first['litros']}L | ${junio.first['rut_conductor']}');
    print('Última:  ${junio.last['fecha']} ${junio.last['hora']} | '
        '${junio.last['litros']}L | ${junio.last['rut_conductor']}');
    final ruts = junio.map((c) => c['rut_conductor']).toSet().length;
    print('Técnicos distintos en junio: $ruts');
  }
}

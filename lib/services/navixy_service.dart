import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/models/navixy_point.dart';
import 'package:agente_desconexiones/services/produccion_service.dart';

/// Resultado de [NavixyService.getTrack]: distingue fallo de API/red de tramo sin puntos.
class NavixyGetTrackResult {
  const NavixyGetTrackResult({
    required this.points,
    required this.fatalError,
  });

  final List<NavixyPoint> points;
  /// Timeout, HTTP distinto de 200, JSON inválido o `success != true`.
  final bool fatalError;
}

/// Navixy API (CREABOX): `POST /track/read` con `hash` y `tracker_id`.
class NavixyService {
  NavixyService._();
  static final NavixyService instance = NavixyService._();

  static const String _base = 'https://api.us.navixy.com/v2';
  static const String _hash = 'd61555b02094f96f49a517ea7d417b52';

  static const Duration _timeout = Duration(seconds: 10);

  final _supabase = Supabase.instance.client;

  /// `tracker_id` del técnico en [navixy_trackers] (no bloqueado).
  Future<int?> getTrackerIdPorRut(String rutTecnico) async {
    final ruts = ProduccionService.rutVariantes(rutTecnico);
    if (ruts.isEmpty) return null;
    try {
      final resp = await _supabase
          .from('navixy_trackers')
          .select('tracker_id')
          .inFilter('rut_tecnico', ruts)
          .eq('bloqueado', false)
          .limit(1)
          .maybeSingle();
      if (resp == null) return null;
      final id = resp['tracker_id'];
      if (id == null) return null;
      if (id is int) return id;
      return int.tryParse(id.toString());
    } catch (e) {
      // Si no existe columna bloqueado, reintentar sin filtro
      try {
        final resp = await _supabase
            .from('navixy_trackers')
            .select('tracker_id')
            .inFilter('rut_tecnico', ruts)
            .limit(1)
            .maybeSingle();
        if (resp == null) return null;
        final id = resp['tracker_id'];
        if (id == null) return null;
        if (id is int) return id;
        return int.tryParse(id.toString());
      } catch (e2) {
        print('⚠️ [Navixy] getTrackerIdPorRut: $e2');
        return null;
      }
    }
  }

  /// Puntos GPS del tramo. [from] y [to]: `"YYYY-MM-DD HH:MM:SS"`.
  Future<NavixyGetTrackResult> getTrack({
    required int trackerId,
    required String from,
    required String to,
  }) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$_base/track/read'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'hash': _hash,
              'tracker_id': trackerId,
              'from': from,
              'to': to,
              'filter': true,
            }),
          )
          .timeout(_timeout);

      if (resp.statusCode != 200) {
        print('⚠️ [Navixy] HTTP ${resp.statusCode}');
        return const NavixyGetTrackResult(points: [], fatalError: true);
      }

      final data = jsonDecode(resp.body);
      if (data is! Map) {
        return const NavixyGetTrackResult(points: [], fatalError: true);
      }
      if (data['success'] != true) {
        return const NavixyGetTrackResult(points: [], fatalError: true);
      }

      final list = data['list'];
      if (list is! List) {
        return const NavixyGetTrackResult(points: [], fatalError: false);
      }

      final puntos = list
          .map((p) => NavixyPoint.fromJson(Map<String, dynamic>.from(p as Map)))
          .where((p) => p.lat.abs() > 0.01 || p.lng.abs() > 0.01)
          .toList();

      puntos.sort((a, b) => a.getTime.compareTo(b.getTime));
      return NavixyGetTrackResult(points: puntos, fatalError: false);
    } catch (e) {
      print('⚠️ [Navixy] getTrack: $e');
      return const NavixyGetTrackResult(points: [], fatalError: true);
    }
  }

  /// [fechaTrabajo] `"DD/MM/YY"` y [hora] `"HH:MM"` o `"HH:MM:SS"`.
  String buildDateTime(String fechaTrabajo, String hora) {
    final partes = fechaTrabajo.split(RegExp(r'[\/\.\-]'));
    if (partes.length < 3) {
      final n = DateTime.now();
      return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')} ${hora.padLeft(5, '0')}:00';
    }
    final dia = partes[0].padLeft(2, '0');
    final mes = partes[1].padLeft(2, '0');
    final anio = partes[2].length == 2 ? '20${partes[2]}' : partes[2];
    final hp = hora.trim().split(':');
    final hh = (hp.isNotEmpty ? hp[0] : '0').padLeft(2, '0');
    final mm = (hp.length > 1 ? hp[1] : '00').replaceAll(RegExp(r'[^0-9]'), '').padLeft(2, '0');
    final ss = hp.length > 2
        ? hp[2].replaceAll(RegExp(r'[^0-9]'), '').padLeft(2, '0')
        : '00';
    return '$anio-$mes-$dia $hh:$mm:$ss';
  }

  /// Hora local un minuto antes de [horaRaw] (`HH:MM`…), para primera OT del día.
  static String horaMenosUnaHora(String horaRaw) {
    final parts = horaRaw.trim().split(':');
    final h = int.tryParse(parts[0]) ?? 0;
    final mm = parts.length > 1 ? parts[1].split(' ').first.padLeft(2, '0') : '00';
    final nh = (h - 1).clamp(0, 23);
    return '${nh.toString().padLeft(2, '0')}:$mm';
  }
}

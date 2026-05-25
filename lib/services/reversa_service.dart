import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

enum KrpResultado { entregado, rechazado, error }

class KrpResult {
  final KrpResultado resultado;
  final int statusCode;
  final String mensaje;
  const KrpResult(this.resultado, this.statusCode, this.mensaje);
}

class ReversaService {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const _krpUrl   = 'https://logistica.sbip.cl/inventario/api/reversa';
  static const _krpToken = '5de53e7b5f89b6b547c5c93d635f162ae2594756';

  // ── KRP ────────────────────────────────────────────────────────

  Future<KrpResult> entregarEnKrp({
    required String serie,
    required String rut,
  }) async {
    try {
      final resp = await http
          .post(
            Uri.parse(_krpUrl),
            headers: {
              'Content-Type': 'application/json',
              'api-token':    _krpToken,
            },
            body: jsonEncode({'serie': serie, 'rut': rut}),
          )
          .timeout(const Duration(seconds: 20));

      if (resp.statusCode == 201) {
        return const KrpResult(KrpResultado.entregado, 201, 'OK');
      }
      if (resp.statusCode == 404) {
        String msg = 'Serie no encontrada en inventario KRP';
        try {
          final body = jsonDecode(resp.body) as Map;
          msg = body['error']?.toString() ?? msg;
        } catch (_) {}
        return KrpResult(KrpResultado.rechazado, 404, msg);
      }
      // Cualquier otro código
      String msg = 'Error desconocido';
      try {
        final body = jsonDecode(resp.body) as Map;
        msg = body['error']?.toString() ?? resp.body;
      } catch (_) {
        msg = resp.body;
      }
      return KrpResult(KrpResultado.error, resp.statusCode, msg);
    } catch (e) {
      return KrpResult(KrpResultado.error, 0, e.toString());
    }
  }

  // ── Supabase estado ────────────────────────────────────────────

  Future<void> marcarEntregado(String serial) async {
    await _supabase.from('equipos_reversa').update({
      'estado':        'entregado',
      'fecha_entrega': DateTime.now().toIso8601String(),
    }).eq('serial', serial);
  }

  Future<void> marcarRechazado(String serial, String motivo) async {
    await _supabase.from('equipos_reversa').update({
      'estado':          'rechazado',
      'motivo_rechazo':  motivo,
      'fecha_entrega':   DateTime.now().toIso8601String(),
    }).eq('serial', serial);
  }

  /// Obtener equipos de reversa del técnico filtrados por mes
  Future<List<Map<String, dynamic>>> obtenerEquiposReversa(
    String tecnicoRut, {
    int? mes,
    int? anno,
  }) async {
    try {
      final now = DateTime.now();
      final mesConsulta = mes ?? now.month;
      final annoConsulta = anno ?? now.year;

      // Calcular rango de fechas del mes
      final inicioMes = DateTime(annoConsulta, mesConsulta, 1);
      final finMes = DateTime(annoConsulta, mesConsulta + 1, 0); // Último día del mes

      print('📦 [Reversa] Consultando RUT: $tecnicoRut');
      print('📦 [Reversa] Mes: $mesConsulta/$annoConsulta');
      print('📦 [Reversa] Rango: ${inicioMes.toIso8601String().split('T')[0]} a ${finMes.toIso8601String().split('T')[0]}');

      final response = await _supabase
          .from('equipos_reversa')
          .select()
          .eq('tecnico_rut', tecnicoRut)
          .gte('fecha_desinstalacion', inicioMes.toIso8601String().split('T')[0])
          .lte('fecha_desinstalacion', finMes.toIso8601String().split('T')[0])
          .order('fecha_desinstalacion', ascending: false);

      print('📦 [Reversa] Respuesta: ${response.runtimeType}');
      print('📦 [Reversa] Cantidad: ${(response as List).length}');

      if ((response as List).isNotEmpty) {
        print('📦 [Reversa] Ejemplo: ${response.first}');
      }

      return List<Map<String, dynamic>>.from(response as List);
    } catch (e, stack) {
      print('❌ [Reversa] Error obteniendo equipos: $e');
      print('❌ [Reversa] Stack: $stack');
      return [];
    }
  }

  /// Obtener resumen de reversa del mes
  Future<Map<String, dynamic>> obtenerResumenReversaMes(
    String tecnicoRut, {
    int? mes,
    int? anno,
  }) async {
    try {
      final now = DateTime.now();
      final mesConsulta = mes ?? now.month;
      final annoConsulta = anno ?? now.year;

      final inicioMes = DateTime(annoConsulta, mesConsulta, 1);
      final finMes = DateTime(annoConsulta, mesConsulta + 1, 0);

      print('📦 [Reversa] Resumen - Consultando RUT: $tecnicoRut');
      print('📦 [Reversa] Resumen - Mes: $mesConsulta/$annoConsulta');

      final response = await _supabase
          .from('equipos_reversa')
          .select()
          .eq('tecnico_rut', tecnicoRut)
          .gte('fecha_desinstalacion', inicioMes.toIso8601String().split('T')[0])
          .lte('fecha_desinstalacion', finMes.toIso8601String().split('T')[0]);

      final equipos = List<Map<String, dynamic>>.from(response as List);
      
      print('📦 [Reversa] Resumen - Equipos encontrados: ${equipos.length}');

      int pendientes = 0;
      int entregados = 0;
      int enRevision = 0;
      int rechazados = 0;
      int recibidos = 0;

      for (var equipo in equipos) {
        final estado = equipo['estado']?.toString() ?? 'pendiente_entrega';
        switch (estado) {
          case 'pendiente_entrega':
          case 'pendiente': // Compatibilidad con modelo EquipoReversa
            pendientes++;
            break;
          case 'entregado':
            entregados++;
            break;
          case 'en_revision':
            enRevision++;
            break;
          case 'rechazado':
            rechazados++;
            break;
          case 'recepcionado_ok':
            recibidos++;
            break;
        }
      }

      return {
        'totalEquipos': equipos.length,
        'pendientes': pendientes,
        'entregados': entregados,
        'enRevision': enRevision,
        'rechazados': rechazados,
        'recibidos': recibidos,
        'porcentajeEntrega': equipos.isNotEmpty
            ? (entregados / equipos.length) * 100
            : 0.0,
      };
    } catch (e) {
      print('❌ [Reversa] Error obteniendo resumen: $e');
      return {
        'totalEquipos': 0,
        'pendientes': 0,
        'entregados': 0,
        'enRevision': 0,
        'rechazados': 0,
        'recibidos': 0,
        'porcentajeEntrega': 0.0,
      };
    }
  }
}


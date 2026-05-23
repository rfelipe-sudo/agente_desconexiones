import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/services/ford_api_service.dart';
import 'package:agente_desconexiones/widgets/combustible_format.dart';

class SolCombustibleService {
  final _db = Supabase.instance.client;

  static const _precioDefault = 1500.0;
  static const _rendKmL       = 12.0;

  // ── Técnico ───────────────────────────────────────────────────────────────

  /// Crea una solicitud adicional. Lanza [StateError] si ya hay una activa.
  Future<Map<String, dynamic>> crearSolicitudAdicional({
    required String rutTecnico,
    required String nombreTecnico,
    required double saldoLitros,
    required double saldoPesos,
  }) async {
    final activa = await _db
        .from('sol_comb_adicional')
        .select('id')
        .eq('rut_solicitante', rutTecnico)
        .not('estado', 'in', '("rechazado_supervisor","rechazado_jefe_ops","completada")')
        .maybeSingle();

    if (activa != null) throw StateError('Ya tienes una solicitud en proceso');

    final precio  = await _fetchPrecioLitro();
    final sugerido = await calcularMontoSugerido(rut: rutTecnico, precioLitroRef: precio);

    final row = await _db
        .from('sol_comb_adicional')
        .insert({
          'rut_solicitante':     rutTecnico,
          'nombre_solicitante':  nombreTecnico,
          'saldo_litros_actual': saldoLitros,
          'saldo_pesos_actual':  saldoPesos.round(),
          'monto_sugerido':      sugerido,
          'estado':              'pendiente_supervisor',
        })
        .select()
        .single();

    unawaited(_notificarSupervisores(rutTecnico, nombreTecnico));
    return row;
  }

  /// Solicitud activa del técnico (null si no hay ninguna en curso).
  Future<Map<String, dynamic>?> solicitudActivaTecnico(String rut) {
    return _db
        .from('sol_comb_adicional')
        .select()
        .eq('rut_solicitante', rut)
        .not('estado', 'in', '("rechazado_supervisor","rechazado_jefe_ops","completada")')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  // ── Supervisor ────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listarParaSupervisor() async {
    final rows = await _db
        .from('sol_comb_adicional')
        .select()
        .eq('estado', 'pendiente_supervisor')
        .order('created_at', ascending: true);
    return (rows as List).cast();
  }

  Future<void> aprobarSupervisor({
    required String solicitudId,
    required String rutSupervisor,
    required int montoAprobado,
  }) async {
    await _db.from('sol_comb_adicional').update({
      'estado':                  'aprobado_supervisor',
      'rut_supervisor':          rutSupervisor,
      'monto_aprobado':          montoAprobado,
      'aprobado_supervisor_at':  DateTime.now().toIso8601String(),
    }).eq('id', solicitudId);
    unawaited(_notificarJefeOps());
  }

  Future<void> rechazarSupervisor({
    required String solicitudId,
    required String rutSupervisor,
    required String motivo,
  }) async {
    final row = await _db
        .from('sol_comb_adicional')
        .update({
          'estado':                      'rechazado_supervisor',
          'rut_supervisor':              rutSupervisor,
          'motivo_rechazo_supervisor':   motivo,
        })
        .eq('id', solicitudId)
        .select('rut_solicitante, nombre_solicitante')
        .single();
    unawaited(_notificarTecnicoRechazo(
      rut: row['rut_solicitante'] as String,
      motivo: motivo,
      paso: 'supervisor',
    ));
  }

  // ── Jefe de Operaciones ────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listarParaJefeOps() async {
    final rows = await _db
        .from('sol_comb_adicional')
        .select()
        .eq('estado', 'aprobado_supervisor')
        .order('created_at', ascending: true);
    return (rows as List).cast();
  }

  Future<void> aprobarJefeOps({
    required String solicitudId,
    required String rutJefeOps,
    required int montoAprobado,
  }) async {
    await _db.from('sol_comb_adicional').update({
      'estado':               'pendiente_flota',
      'rut_jefe_ops':         rutJefeOps,
      'monto_aprobado':       montoAprobado,
      'aprobado_jefe_ops_at': DateTime.now().toIso8601String(),
    }).eq('id', solicitudId);
    unawaited(_notificarFlota());
  }

  Future<void> rechazarJefeOps({
    required String solicitudId,
    required String rutJefeOps,
    required String motivo,
  }) async {
    final row = await _db
        .from('sol_comb_adicional')
        .update({
          'estado':                   'rechazado_jefe_ops',
          'rut_jefe_ops':             rutJefeOps,
          'motivo_rechazo_jefe_ops':  motivo,
        })
        .eq('id', solicitudId)
        .select('rut_solicitante')
        .single();
    unawaited(_notificarTecnicoRechazo(
      rut: row['rut_solicitante'] as String,
      motivo: motivo,
      paso: 'jefe de operaciones',
    ));
  }

  // ── Flota (Abraham) ────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listarOperacionalPendiente() async {
    final rows = await _db
        .from('sol_comb_operacional')
        .select()
        .eq('estado', 'pendiente')
        .order('created_at', ascending: true);
    return (rows as List).cast();
  }

  Future<List<Map<String, dynamic>>> listarAdicionalParaFlota() async {
    final rows = await _db
        .from('sol_comb_adicional')
        .select()
        .eq('estado', 'pendiente_flota')
        .order('created_at', ascending: true);
    return (rows as List).cast();
  }

  Future<void> completarOperacional({
    required int solicitudId,
    required String rutFlota,
  }) async {
    await _db.from('sol_comb_operacional').update({
      'estado':         'completada',
      'completada_por': rutFlota,
      'completada_at':  DateTime.now().toIso8601String(),
    }).eq('id', solicitudId);
  }

  Future<void> completarAdicional({
    required String solicitudId,
    required String rutFlota,
  }) async {
    final row = await _db
        .from('sol_comb_adicional')
        .update({
          'estado':              'completada',
          'rut_flota':           rutFlota,
          'completada_flota_at': DateTime.now().toIso8601String(),
        })
        .eq('id', solicitudId)
        .select('rut_solicitante, monto_aprobado')
        .single();

    unawaited(_notificarTecnicoCompletado(
      rut:   row['rut_solicitante'] as String,
      monto: row['monto_aprobado'] as int? ?? 0,
    ));
  }

  // ── Mantención ────────────────────────────────────────────────────────────

  Future<void> completarMantencion({
    required int solicitudId,
    required String rutFlota,
    String? notas,
  }) async {
    await _db.from('sol_mantencion').update({
      'estado':         'completada',
      'completada_por': rutFlota,
      'completada_at':  DateTime.now().toIso8601String(),
      if (notas != null && notas.isNotEmpty) 'notas_flota': notas,
    }).eq('id', solicitudId);
  }

  // ── Monto sugerido ─────────────────────────────────────────────────────────

  /// Promedio de gasto diario de esta semana × días laborales restantes
  /// (excluye domingos y feriados chilenos).
  /// Si no hay datos esta semana, usa los últimos 7 días como referencia.
  Future<int> calcularMontoSugerido({
    required String rut,
    double? precioLitroRef,
  }) async {
    try {
      final precio = precioLitroRef ?? await _fetchPrecioLitro();
      final ahora  = DateTime.now();
      final hoy    = DateTime(ahora.year, ahora.month, ahora.day);
      final lunes  = hoy.subtract(Duration(days: hoy.weekday - 1));

      final rutas = await FordApiService().getRutasDelTecnico(rut);

      // ── Promedio de la semana actual ──
      double totalCosto    = 0;
      int    diasTrabajados = 0;

      for (final dia in rutas) {
        final f = dia.fecha;
        if (f == null || dia.kmTotal <= 0) continue;
        final fd = DateTime(f.year, f.month, f.day);
        if (fd.isBefore(lunes) || fd.isAfter(hoy)) continue;
        totalCosto += (dia.kmTotal / _rendKmL) * precio;
        diasTrabajados++;
      }

      // Si no hay datos esta semana, retroceder 7 días
      if (diasTrabajados == 0) {
        final inicio7 = hoy.subtract(const Duration(days: 7));
        for (final dia in rutas) {
          final f = dia.fecha;
          if (f == null || dia.kmTotal <= 0) continue;
          final fd = DateTime(f.year, f.month, f.day);
          if (fd.isBefore(inicio7) || fd.isAfter(hoy)) continue;
          totalCosto += (dia.kmTotal / _rendKmL) * precio;
          diasTrabajados++;
        }
      }

      if (diasTrabajados == 0) return (precio * 8).round();
      final avgDiario = totalCosto / diasTrabajados;

      // ── Días laborales restantes (mañana → sábado de esta semana) ──
      final manana = hoy.add(const Duration(days: 1));
      final sabado = lunes.add(const Duration(days: 5));

      final festivosRows = await _db
          .from('festivos_chile')
          .select('fecha')
          .gte('fecha', _dateStr(manana))
          .lte('fecha', _dateStr(sabado));

      final festivos = <String>{
        for (final r in festivosRows as List) r['fecha'] as String,
      };

      int diasRestantes = 0;
      for (var c = manana; !c.isAfter(sabado); c = c.add(const Duration(days: 1))) {
        if (c.weekday != DateTime.sunday && !festivos.contains(_dateStr(c))) {
          diasRestantes++;
        }
      }

      final factor = diasRestantes > 0 ? diasRestantes : 1;
      return (avgDiario * factor).round();
    } catch (_) {
      return 15000;
    }
  }

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── Guardado de FCM token para roles_flota ─────────────────────────────────

  Future<void> guardarTokenFlota({
    required String rut,
    required String token,
  }) async {
    try {
      await _db
          .from('roles_flota')
          .update({'fcm_token': token})
          .eq('rut', rut);
    } catch (e) {
      debugPrint('[SolComb] guardarTokenFlota error: $e');
    }
  }

  // ── FCM helpers ────────────────────────────────────────────────────────────

  Future<void> _notificarSupervisores(String rutTecnico, String nombreTecnico) async {
    try {
      final stcRows = await _db
          .from('supervisor_tecnicos_crea')
          .select('rut_supervisor')
          .eq('rut_tecnico', rutTecnico);
      for (final r in stcRows as List) {
        final rutSup = r['rut_supervisor'] as String? ?? '';
        if (rutSup.isEmpty) continue;
        final tokenRow = await _db
            .from('supervisores_crea')
            .select('fcm_token')
            .eq('rut', rutSup)
            .maybeSingle();
        final token = tokenRow?['fcm_token'] as String?;
        if (token != null && token.isNotEmpty) {
          await _sendFcm(
            token:       token,
            accion:      'sol_comb_adicional',
            titulo:      'Solicitud de combustible',
            descripcion: '$nombreTecnico solicita carga extra',
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _notificarJefeOps() async {
    try {
      final row = await _db
          .from('roles_flota')
          .select('fcm_token')
          .eq('rol', 'jefe_operaciones')
          .eq('activo', true)
          .maybeSingle();
      final token = row?['fcm_token'] as String?;
      if (token != null && token.isNotEmpty) {
        await _sendFcm(
          token:       token,
          accion:      'sol_comb_jefe_ops',
          titulo:      'Solicitud de combustible aprobada',
          descripcion: 'Solicitud aprobada por supervisor — requiere tu revisión',
        );
      }
    } catch (_) {}
  }

  Future<void> _notificarFlota() async {
    try {
      final row = await _db
          .from('roles_flota')
          .select('fcm_token')
          .eq('rol', 'flota')
          .eq('activo', true)
          .maybeSingle();
      final token = row?['fcm_token'] as String?;
      if (token != null && token.isNotEmpty) {
        await _sendFcm(
          token:       token,
          accion:      'sol_comb_flota',
          titulo:      'Carga de combustible autorizada',
          descripcion: 'Hay una solicitud lista para realizar',
        );
      }
    } catch (_) {}
  }

  Future<void> _notificarTecnicoRechazo({
    required String rut,
    required String motivo,
    required String paso,
  }) async {
    try {
      final tokenRow = await _db
          .from('nomina_tecnicos')
          .select('fcm_token')
          .eq('rut', rut)
          .maybeSingle();
      final token = tokenRow?['fcm_token'] as String?;
      if (token != null && token.isNotEmpty) {
        await _sendFcm(
          token:       token,
          accion:      'sol_comb_rechazada',
          titulo:      'Solicitud rechazada',
          descripcion: 'Tu solicitud fue rechazada por $paso: $motivo',
        );
      }
    } catch (_) {}
  }

  Future<void> _notificarTecnicoCompletado({
    required String rut,
    required int monto,
  }) async {
    try {
      final tokenRow = await _db
          .from('nomina_tecnicos')
          .select('fcm_token')
          .eq('rut', rut)
          .maybeSingle();
      final token = tokenRow?['fcm_token'] as String?;
      if (token != null && token.isNotEmpty) {
        await _sendFcm(
          token:       token,
          accion:      'sol_comb_completada',
          titulo:      'Carga de combustible realizada',
          descripcion: 'Tu solicitud fue completada por flota',
        );
      }
    } catch (_) {}
  }

  Future<void> _sendFcm({
    required String token,
    required String accion,
    required String titulo,
    required String descripcion,
  }) async {
    try {
      await _db.functions.invoke('fcm-send', body: {
        'token':       token,
        'accion':      accion,
        'tipo':        titulo,
        'descripcion': descripcion,
      });
    } catch (_) {}
  }

  Future<double> _fetchPrecioLitro() async {
    try {
      final row = await _db
          .from('parametros_combustible')
          .select()
          .limit(1)
          .maybeSingle();
      if (row != null) {
        final p = CombustibleFormat.toDouble(
            row['precio_litro'] ?? row['precio_litro_referencia']);
        if (p > 0) return p;
      }
    } catch (_) {}
    return _precioDefault;
  }
}

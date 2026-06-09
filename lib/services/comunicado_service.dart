import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/screens/comunicado_lectura_screen.dart';
import 'package:agente_desconexiones/services/logistica_service.dart';
import 'package:agente_desconexiones/services/sesion_dispositivo_service.dart';

const String kPrefComunicadoPendiente = 'comunicado_creabox_pendiente';

const _soundChannel = MethodChannel(
  'com.creacionestecnologicas.agente_desconexiones/sound',
);

/// Comunicados masivos/personalizados con confirmación de lectura y firma.
class ComunicadoService {
  ComunicadoService._();
  static final ComunicadoService instance = ComunicadoService._();

  final _db = Supabase.instance.client;
  bool _presentando = false;
  bool _monitorActivo = false;
  RealtimeChannel? _canalNuevos;

  DateTime? _ultimoSonidoComunicado;

  Future<void> _playSonidoComunicado() async {
    final now = DateTime.now();
    if (_ultimoSonidoComunicado != null &&
        now.difference(_ultimoSonidoComunicado!) <
            const Duration(seconds: 3)) {
      return;
    }
    _ultimoSonidoComunicado = now;
    try {
      await _soundChannel.invokeMethod<void>('playComunicado');
    } catch (e) {
      debugPrint('[Comunicado] playComunicado: $e');
    }
  }

  bool _esVigente(String? v) =>
      (v ?? '').trim().toLowerCase() == 'vigente';

  Set<String> _rolesDesdeDestino(dynamic raw) {
    if (raw == null) return {};
    if (raw is List) {
      return raw
          .map((r) => r.toString().trim().toLowerCase())
          .where((r) => r.isNotEmpty)
          .toSet();
    }
    final s = raw.toString().trim();
    if (s.isEmpty) return {};
    return s
        .replaceAll(RegExp(r'[{}"\[\]]'), '')
        .split(',')
        .map((r) => r.trim().toLowerCase())
        .where((r) => r.isNotEmpty)
        .toSet();
  }

  Future<Map<String, dynamic>?> _filaNominaPorRut(String rutCanon) async {
    final row = await _db
        .from('nomina_tecnicos')
        .select('rut, tipo_personal, estado_vigencia')
        .eq('rut', rutCanon)
        .maybeSingle();
    if (row != null) return row;

    final rows = await _db
        .from('nomina_tecnicos')
        .select('rut, tipo_personal, estado_vigencia');
    for (final r in rows as List) {
      final map = Map<String, dynamic>.from(r as Map);
      if (LogisticaService.sameRut(
        map['rut'] as String? ?? '',
        rutCanon,
      )) {
        return map;
      }
    }
    return null;
  }

  Future<Set<String>> _rolesUsuario(String rutCanon) async {
    final roles = <String>{};

    final tec = await _filaNominaPorRut(rutCanon);
    if (tec != null && _esVigente(tec['estado_vigencia'] as String?)) {
      final tipo =
          (tec['tipo_personal'] as String? ?? '').trim().toUpperCase();
      if (tipo == 'ITO') {
        roles.add('ito');
      } else if (tipo == 'TA') {
        roles.add('administrativo');
      } else if (tipo == 'T' || tipo == 'TNE' || tipo.isEmpty) {
        roles.add('tecnico');
      }
    }

    for (final entry in [
      ('supervisor', 'supervisores_crea'),
      ('bodeguero', 'nomina_bodega'),
    ]) {
      final rows = await _db.from(entry.$2).select('rut');
      for (final r in rows as List) {
        final map = Map<String, dynamic>.from(r as Map);
        if (LogisticaService.sameRut(
          map['rut'] as String? ?? '',
          rutCanon,
        )) {
          roles.add(entry.$1);
          break;
        }
      }
    }

    final flotaRows = await _db
        .from('roles_flota')
        .select('rut')
        .eq('activo', true);
    for (final r in flotaRows as List) {
      final map = Map<String, dynamic>.from(r as Map);
      if (LogisticaService.sameRut(map['rut'] as String? ?? '', rutCanon)) {
        roles.add('flota');
        break;
      }
    }

    return roles;
  }

  bool _aplicaARut(
    Map<String, dynamic> c,
    String rutCanon,
    Set<String> rolesUsuario,
  ) {
    final tipo = (c['tipo'] as String? ?? 'masivo').trim().toLowerCase();

    if (tipo == 'personalizado') {
      final destino = c['rut_destino'] as String?;
      if (destino != null &&
          LogisticaService.sameRut(destino, rutCanon)) {
        return true;
      }
      final lista = c['ruts_destino'];
      if (lista is List) {
        for (final r in lista) {
          if (LogisticaService.sameRut(r.toString(), rutCanon)) {
            return true;
          }
        }
      }
      return false;
    }

    if (tipo == 'por_roles') {
      final destinos = _rolesDesdeDestino(c['roles_destino']);
      if (destinos.isEmpty) return false;
      if (destinos.contains('todos')) return true;
      return destinos.intersection(rolesUsuario).isNotEmpty;
    }

    return rolesUsuario.contains('tecnico');
  }

  Future<String?> _rutSesion() async {
    final prefs = await SharedPreferences.getInstance();
    final rut = prefs.getString('rut_tecnico') ??
        prefs.getString('user_rut') ??
        prefs.getString('rut') ??
        '';
    if (rut.isEmpty) return null;
    return LogisticaService.canonicalRut(rut);
  }

  Future<bool> _yaLeido(String comunicadoId, String rutCanon) async {
    final lecturas = await _db
        .from('comunicados_lecturas')
        .select('rut_tecnico')
        .eq('comunicado_id', comunicadoId)
        .eq('estado', 'leido');
    for (final row in lecturas as List) {
      final map = Map<String, dynamic>.from(row as Map);
      if (LogisticaService.sameRut(
        map['rut_tecnico'] as String? ?? '',
        rutCanon,
      )) {
        return true;
      }
    }
    return false;
  }

  Future<Map<String, dynamic>?> _obtenerPorId(
    String comunicadoId,
    String rutCanon,
  ) async {
    final row = await _db
        .from('comunicados_creabox')
        .select()
        .eq('id', comunicadoId)
        .eq('activo', true)
        .maybeSingle();
    if (row == null) return null;

    final map = Map<String, dynamic>.from(row);
    final rolesUsuario = await _rolesUsuario(rutCanon);
    if (!_aplicaARut(map, rutCanon, rolesUsuario)) return null;
    if (await _yaLeido(comunicadoId, rutCanon)) return null;
    return map;
  }

  Future<Map<String, dynamic>?> obtenerPendiente(String rut) async {
    final canon = LogisticaService.canonicalRut(rut);
    if (canon.length < 3) return null;

    final rolesUsuario = await _rolesUsuario(canon);

    final comunicados = await _db
        .from('comunicados_creabox')
        .select()
        .eq('activo', true)
        .order('created_at', ascending: false);

    final lecturas = await _db
        .from('comunicados_lecturas')
        .select('comunicado_id, rut_tecnico')
        .eq('estado', 'leido');

    final leidos = <String>{};
    for (final row in lecturas as List) {
      final map = Map<String, dynamic>.from(row as Map);
      final rutLect = map['rut_tecnico'] as String? ?? '';
      if (!LogisticaService.sameRut(rutLect, canon)) continue;
      final id = map['comunicado_id'] as String?;
      if (id != null) leidos.add(id);
    }

    for (final c in comunicados as List) {
      final map = Map<String, dynamic>.from(c as Map);
      final id = map['id'] as String?;
      if (id == null || leidos.contains(id)) continue;
      if (_aplicaARut(map, canon, rolesUsuario)) return map;
    }
    return null;
  }

  Future<void> marcarLeido({
    required String comunicadoId,
    required String rut,
    required String nombre,
    required String firmaBase64,
  }) async {
    final canon = LogisticaService.canonicalRut(rut);
    final now = DateTime.now().toUtc().toIso8601String();

    Map<String, dynamic>? existente;
    final lecturas = await _db
        .from('comunicados_lecturas')
        .select('id, rut_tecnico')
        .eq('comunicado_id', comunicadoId);
    for (final row in lecturas as List) {
      final map = Map<String, dynamic>.from(row as Map);
      if (LogisticaService.sameRut(
        map['rut_tecnico'] as String? ?? '',
        canon,
      )) {
        existente = map;
        break;
      }
    }

    final payload = {
      'comunicado_id': comunicadoId,
      'rut_tecnico': canon,
      'nombre_tecnico': nombre,
      'estado': 'leido',
      'leido_at': now,
      'firma_base64': firmaBase64,
      'firma_at': now,
    };

    if (existente != null) {
      await _db
          .from('comunicados_lecturas')
          .update(payload)
          .eq('id', existente['id']);
    } else {
      await _db.from('comunicados_lecturas').insert(payload);
    }
  }

  Future<void> marcarPendienteFlag() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefComunicadoPendiente, 'true');
  }

  Future<void> limpiarPendienteFlag() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kPrefComunicadoPendiente);
  }

  /// Escucha nuevos comunicados y re-chequea al reanudar la app.
  Future<void> iniciarMonitor() async {
    if (_monitorActivo) return;
    _monitorActivo = true;

    await _canalNuevos?.unsubscribe();
    _canalNuevos = _db
        .channel('comunicados_creabox_live')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'comunicados_creabox',
          callback: (payload) {
            final id = payload.newRecord['id']?.toString();
            debugPrint('[Comunicado] nuevo en BD: $id');
            unawaited(_playSonidoComunicado());
            unawaited(mostrarInmediato(comunicadoId: id));
          },
        )
        .subscribe((status, [error]) {
          debugPrint('[Comunicado] realtime status=$status error=$error');
        });
  }

  Future<BuildContext?> _esperarContextoNav({
    BuildContext? preferido,
    int intentos = 24,
    Duration paso = const Duration(milliseconds: 250),
  }) async {
    if (preferido != null && preferido.mounted) return preferido;
    for (var i = 0; i < intentos; i++) {
      final ctx = creaboxNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) return ctx;
      await Future.delayed(paso);
    }
    return null;
  }

  /// Muestra el comunicado al instante (FCM / realtime), no al abrir la app.
  Future<void> mostrarInmediato({
    String? comunicadoId,
    BuildContext? context,
    bool reproducirSonido = false,
  }) async {
    if (_presentando) return;

    final rut = await _rutSesion();
    if (rut == null || rut.isEmpty) return;

    Map<String, dynamic>? pendiente;
    if (comunicadoId != null && comunicadoId.isNotEmpty) {
      pendiente = await _obtenerPorId(comunicadoId, rut);
    }
    pendiente ??= await obtenerPendiente(rut);
    if (pendiente == null) return;

    if (reproducirSonido) {
      unawaited(_playSonidoComunicado());
    }

    final ctx = await _esperarContextoNav(
      preferido: context,
      intentos: 50,
      paso: const Duration(milliseconds: 100),
    );
    if (ctx == null || !ctx.mounted) {
      await marcarPendienteFlag();
      return;
    }

    _presentando = true;
    try {
      debugPrint('[Comunicado] mostrando inmediato: ${pendiente['titulo']}');
      await Navigator.of(ctx).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => ComunicadoLecturaScreen(comunicado: pendiente!),
        ),
      );
      await limpiarPendienteFlag();
    } finally {
      _presentando = false;
    }
  }

  /// Solo si quedó pendiente por FCM en background (flag en prefs).
  Future<void> verificarYMostrar([BuildContext? context]) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(kPrefComunicadoPendiente) != 'true') return;
    await mostrarInmediato(context: context);
  }

  Future<void> processPendingComunicado([BuildContext? context]) async {
    await verificarYMostrar(context);
  }
}

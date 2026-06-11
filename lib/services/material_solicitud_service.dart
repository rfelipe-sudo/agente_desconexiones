import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/config/constants.dart';
import 'package:agente_desconexiones/services/alerta_sistema_service.dart';
import 'package:agente_desconexiones/services/logistica_service.dart';
import 'package:agente_desconexiones/services/ubicacion_service.dart';

/// Resultado de notificar destinatarios de una solicitud de material.
class ResultadoNotificacionDestinatarios {
  final int cantidad;
  final bool keplerDisponible;

  const ResultadoNotificacionDestinatarios({
    required this.cantidad,
    required this.keplerDisponible,
  });

  bool get sinDestinatarios => cantidad == 0;
}

class MaterialSolicitudService {
  final _db = Supabase.instance.client;

  /// Umbral mínimo de stock para compartir un tipo de material.
  static double umbralStock(String tipoMaterial) {
    if (tipoMaterial.contains('ONT') || tipoMaterial.contains('Decodificador')) {
      return 3.0;
    }
    if (tipoMaterial.contains('Extensor')) {
      return 2.0;
    }
    return 0.0;
  }

  bool _rutExcluido(String rut, Set<String> excluirRuts) =>
      excluirRuts.any((e) => LogisticaService.sameRut(e, rut));

  (double, double)? _buscarUbicacion(
    String rut,
    Map<String, (double, double)> ubicMap,
  ) {
    final directa = ubicMap[rut];
    if (directa != null) return directa;
    for (final entry in ubicMap.entries) {
      if (LogisticaService.sameRut(entry.key, rut)) return entry.value;
    }
    return null;
  }

  static const _fcmTimeout = Duration(seconds: 8);

  Future<void> _enviarFcmAlerta({
    required String token,
    required String accion,
    required String titulo,
    required String descripcion,
    Map<String, dynamic>? extra,
  }) async {
    await _enviarFcmBatch(
      tokens: [token],
      accion: accion,
      titulo: titulo,
      descripcion: descripcion,
      extra: extra,
    );
  }

  Future<void> _enviarFcmBatch({
    required List<String> tokens,
    required String accion,
    required String titulo,
    required String descripcion,
    Map<String, dynamic>? extra,
  }) async {
    if (tokens.isEmpty) return;
    try {
      await _db.functions.invoke('fcm-send', body: {
        if (tokens.length == 1) 'token': tokens.first else 'tokens': tokens,
        'accion':      accion,
        'tipo':        titulo,
        'title':       titulo,
        'body':        descripcion,
        'descripcion': descripcion,
        'data_only':          true,
        'skip_notification':  true,
        'android_channel_id': 'mat_alertas_7',
        'android_priority':   'high',
        if (extra != null) ...extra,
      }).timeout(_fcmTimeout);
      debugPrint('✅ [Material] FCM $accion → ${tokens.length} dispositivo(s)');
    } catch (e) {
      debugPrint('⚠️ [Material] FCM $accion falló (${tokens.length} dest.): $e');
    }
  }

  /// Encuentra técnicos con stock suficiente en Kepler (toda la nómina, sin
  /// filtro por equipo CREA), aplica distancia/rol y notifica.
  /// Si Kepler no responde: bypass por GPS + rol (sin stock), alerta de sistema.
  /// Con [soloRadio5Km] en `false` notifica a todo el plantel con stock,
  /// ordenado del más cercano al más lejano.
  Future<ResultadoNotificacionDestinatarios> notificarDestinatarios({
    required String solicitudId,
    required String tipoMaterial,
    required double? latSolicitante,
    required double? lngSolicitante,
    required String rutSolicitante,
    String? nombreSolicitante,
    bool soloRadio5Km = true,
  }) async {
    final nombreSol =
        await LogisticaService().nombreDesdeNomina(rutSolicitante);
    nombreSolicitante = nombreSol;

    // Solo técnicos con GPS activo y ubicación reciente (no apagados / sin señal).
    List<dynamic> ubicRows;
    try {
      ubicRows = await _db
          .from('ubicaciones_activas')
          .select('rut_tecnico, lat, lng, updated_at, gps_activo')
          .eq('gps_activo', true);
    } catch (e) {
      debugPrint('⚠️ [Material] notificarDestinatarios: error Supabase ubicaciones ($e)');
      return const ResultadoNotificacionDestinatarios(
        cantidad: 0,
        keplerDisponible: false,
      );
    }

    // Intentar obtener stock de Kepler
    List<TecnicoStock>? stock;
    bool keplerFallo = false;
    try {
      stock = await LogisticaService().fetchStock();
    } catch (e) {
      keplerFallo = true;
      debugPrint('⚠️ [Material] Kepler no disponible, bypass activado ($e)');
      // Registrar fallo y notificar admins (fire-and-forget)
      AlertaSistemaService().registrarFallo(
        modulo:        'kepler_stock',
        tipoError:     'timeout_o_error_conexion',
        mensaje:       'fetchStock falló: $e',
        rutTecnico:    rutSolicitante,
        nombreTecnico: nombreSolicitante,
        solicitudId:   solicitudId,
      );
    }

    // Mapa rut → (lat, lng) — solo GPS vigente
    final Map<String, (double, double)> ubicMap = {};
    for (final u in ubicRows) {
      final rut = u['rut_tecnico'] as String?;
      if (rut == null || rut.isEmpty) continue;
      if (!UbicacionService.ubicacionVigente(u['updated_at'] as String?)) {
        debugPrint('[MatDest] $rut → GPS no vigente (apagado o sin actualizar)');
        continue;
      }
      final lat = (u['lat'] as num?)?.toDouble();
      final lng = (u['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      if (lat.abs() < 0.0001 && lng.abs() < 0.0001) continue;
      ubicMap[rut] = (lat, lng);
    }
    debugPrint('[MatDest] ubicMap: ${ubicMap.length} técnicos con GPS activo vigente');

    // No notificar solicitudes de material a bodega, supervisores ni flota admin.
    // Los ITO en nomina_tecnicos se comportan como técnicos de campo.
    final excluirResults = await Future.wait<dynamic>([
      _db.from('nomina_bodega').select('rut'),
      _db.from('supervisores_crea').select('rut'),
      _db.from('roles_flota').select('rut'),
    ]);
    Set<String> toRutSet(dynamic rows, {String key = 'rut'}) => (rows as List)
        .map((r) => LogisticaService.canonicalRut(r[key] as String? ?? ''))
        .where((r) => r.isNotEmpty)
        .toSet();
    final bodegaRuts     = toRutSet(excluirResults[0]);
    final supervisorRuts = toRutSet(excluirResults[1]);
    final flotaRuts      = toRutSet(excluirResults[2]);
    final excluirRuts    = {...bodegaRuts, ...supervisorRuts, ...flotaRuts};
    debugPrint('[MatDest] excluirRuts: ${excluirRuts.length} (bodega=${bodegaRuts.length} sup=${supervisorRuts.length} flota=${flotaRuts.length})');

    final umbral = umbralStock(tipoMaterial);
    final aplicarRadio = soloRadio5Km && kMaterialFiltroDistanciaActivo;
    debugPrint(
        '[MatDest] tipoMaterial=$tipoMaterial umbral=$umbral keplerFallo=$keplerFallo '
        'stock=${stock?.length ?? "null"} soloRadio5Km=$soloRadio5Km');

    final List<Map<String, dynamic>> destinatarios = [];

    if (!keplerFallo && stock != null) {
      // Flujo normal: stock + distancia opcional + rol
      for (final tecnico in stock) {
        if (LogisticaService.sameRut(tecnico.rut, rutSolicitante)) continue;
        if (_rutExcluido(tecnico.rut, excluirRuts)) {
          debugPrint('[MatDest] ${tecnico.rut} → excluido por rol');
          continue;
        }

        final cantidad = tecnico.stock[tipoMaterial] ?? 0;
        if (cantidad <= umbral) {
          debugPrint('[MatDest] ${tecnico.rut} → stock insuficiente ($tipoMaterial=$cantidad <= $umbral)');
          continue;
        }

        final pos = _buscarUbicacion(tecnico.rut, ubicMap);
        if (pos == null) {
          debugPrint('[MatDest] ${tecnico.rut} → sin GPS activo vigente');
          continue;
        }

        double distOrden = double.infinity;
        if (latSolicitante != null && lngSolicitante != null) {
          distOrden = _distanciaKm(
              latSolicitante, lngSolicitante, pos.$1, pos.$2);
          if (aplicarRadio && distOrden > kMaterialRadioKm) {
            debugPrint('[MatDest] ${tecnico.rut} → demasiado lejos (${distOrden.toStringAsFixed(1)} km)');
            continue;
          }
          debugPrint('[MatDest] ${tecnico.rut} ✓ stock=$cantidad dist=${distOrden.toStringAsFixed(1)}km'
              '${aplicarRadio ? "" : " (plantel)"}');
        } else if (aplicarRadio) {
          debugPrint('[MatDest] ${tecnico.rut} → sin GPS del solicitante');
          continue;
        } else {
          debugPrint('[MatDest] ${tecnico.rut} ✓ stock=$cantidad (plantel, sin GPS solicitante)');
        }

        destinatarios.add({
          'solicitud_id':     solicitudId,
          'rut_tecnico':      tecnico.rut,
          'nombre_tecnico':   tecnico.nombre,
          'stock_disponible': cantidad.toInt(),
          'estado':           'pendiente',
          '_sort_dist':       distOrden,
        });
      }
    } else {
      // Bypass: solo distancia + rol; stock_disponible = -1 (desconocido)
      for (final entry in ubicMap.entries) {
        final rut = entry.key;
        if (LogisticaService.sameRut(rut, rutSolicitante)) continue;
        if (_rutExcluido(rut, excluirRuts)) continue;

        final pos = entry.value;
        double distOrden = double.infinity;
        if (latSolicitante != null && lngSolicitante != null) {
          distOrden = _distanciaKm(
              latSolicitante, lngSolicitante, pos.$1, pos.$2);
          if (aplicarRadio && distOrden > kMaterialRadioKm) continue;
        } else if (aplicarRadio) {
          continue;
        }

        String nombreTecnico = rut;
        try {
          nombreTecnico = await LogisticaService().nombreDesdeNomina(rut);
        } catch (_) {}

        destinatarios.add({
          'solicitud_id':     solicitudId,
          'rut_tecnico':      rut,
          'nombre_tecnico':   nombreTecnico,
          'stock_disponible': -1,
          'estado':           'pendiente',
          '_sort_dist':       distOrden,
        });
      }
    }

    destinatarios.sort((a, b) => (a['_sort_dist'] as double)
        .compareTo(b['_sort_dist'] as double));
    for (final d in destinatarios) {
      d.remove('_sort_dist');
    }

    debugPrint('[MatDest] destinatarios finales: ${destinatarios.length}');
    if (destinatarios.isNotEmpty) {
      await _db.from('solicitudes_material_destinatarios').insert(destinatarios);
    }

    // FCM a los destinatarios calificados
    if (destinatarios.isNotEmpty) {
      final ruts = destinatarios
          .map((d) => d['rut_tecnico'] as String)
          .toList();
      try {
        final tokenRows = await _db
            .from('nomina_tecnicos')
            .select('rut, fcm_token')
            .inFilter('rut', ruts);
        for (final row in (tokenRows as List)) {
          final rut      = row['rut']       as String? ?? '';
          final fcmToken = row['fcm_token'] as String?;
          if (rut.isEmpty || fcmToken == null || fcmToken.isEmpty) continue;
          await _enviarFcmAlerta(
            token:       fcmToken,
            accion:      'solicitud_material',
            titulo:      '¡Solicitud de material!',
            descripcion: 'Se necesita: $tipoMaterial',
            extra:       {'rut': rut, 'solicitud_id': solicitudId},
          );
        }
      } catch (_) {}
    }

    return ResultadoNotificacionDestinatarios(
      cantidad: destinatarios.length,
      keplerDisponible: !keplerFallo && stock != null,
    );
  }

  /// El primer técnico que acepta: cancela los otros destinatarios y actualiza la solicitud.
  /// [idMaterial] es el id interno de Kepler para el ítem a entregar.
  /// [serieEscaneada] solo para ítems seriados (se captura antes de llamar esto).
  Future<void> aceptar({
    required String solicitudId,
    required String rutAceptador,
    required double? lat,
    required double? lng,
    required String modalidad,
    int? idMaterial,
    String? serieEscaneada,
    String? nombreAceptadorSesion,
  }) async {
    final nombreAceptador = await LogisticaService().nombrePorRut(
      rutAceptador,
      fallback: nombreAceptadorSesion,
    );
    await Future.wait([
      _db
          .from('solicitudes_material_destinatarios')
          .update({'estado': 'aceptada'})
          .eq('solicitud_id', solicitudId)
          .eq('rut_tecnico', rutAceptador),
      _db
          .from('solicitudes_material_destinatarios')
          .update({'estado': 'cancelada'})
          .eq('solicitud_id', solicitudId)
          .neq('rut_tecnico', rutAceptador)
          .eq('estado', 'pendiente'),
    ]);

    // Solo actualiza si todavía está pendiente (evitar race condition).
    final updated = await _db
        .from('solicitudes_material')
        .update({
          'estado':            'aceptada',
          'rut_entregador':    rutAceptador,
          'nombre_entregador': nombreAceptador,
          'lat_entregador':    lat,
          'lng_entregador':    lng,
          'modalidad':         modalidad,
          if (modalidad == 'yo_te_lo_llevo' && lat != null && lng != null) ...{
            'lat_partida': lat,
            'lng_partida': lng,
            'partida_at': DateTime.now().toUtc().toIso8601String(),
          },
          if (idMaterial != null) 'id_material': idMaterial,
          if (serieEscaneada != null) 'series': [serieEscaneada],
        })
        .eq('id', solicitudId)
        .eq('estado', 'pendiente')
        .select('tipo_material')
        .maybeSingle();

    if (updated == null) {
      throw StateError(
        'La solicitud ya fue atendida por otro técnico. Intenta con otra.',
      );
    }

    final tipoMaterial =
        updated['tipo_material'] as String? ?? 'material';
    unawaited(notificarAtendidaPorOtro(
      solicitudId:  solicitudId,
      rutAceptador: rutAceptador,
      tipoMaterial: tipoMaterial,
    ));
  }

  /// Avisa a técnicos que no aceptaron: mensaje solo si abrieron la push.
  Future<void> notificarAtendidaPorOtro({
    required String solicitudId,
    required String rutAceptador,
    required String tipoMaterial,
  }) async {
    try {
      final rows = await _db
          .from('solicitudes_material_destinatarios')
          .select('rut_tecnico')
          .eq('solicitud_id', solicitudId)
          .eq('estado', 'cancelada')
          .neq('rut_tecnico', rutAceptador);

      final ruts = (rows as List)
          .map((d) => d['rut_tecnico'] as String? ?? '')
          .where((r) => r.isNotEmpty)
          .toList();
      if (ruts.isEmpty) return;

      final tokenRows = await _db
          .from('nomina_tecnicos')
          .select('fcm_token')
          .inFilter('rut', ruts);

      final tokens = (tokenRows as List)
          .map((row) => row['fcm_token'] as String?)
          .whereType<String>()
          .where((t) => t.isNotEmpty)
          .toList();
      if (tokens.isEmpty) return;

      await _enviarFcmBatch(
        tokens:      tokens,
        accion:      'solicitud_atendida',
        titulo:      'Solicitud atendida',
        descripcion: 'La solicitud de $tipoMaterial ya fue atendida',
        extra:       {'solicitud_id': solicitudId},
      );
      debugPrint('[MatDest] FCM solicitud_atendida → ${ruts.length} técnicos');
    } catch (e) {
      debugPrint('⚠️ [Material] notificarAtendidaPorOtro error: $e');
    }
  }

  /// Emite la guía en bandeja del entregador y solicitante tras OK de bodega.
  Future<void> emitirGuiaTrasAprobacion({
    required String solicitudId,
    required String rutEntregador,
    required String rutSolicitante,
    required String detalleMaterial,
    required String nombreEntregador,
    required String nombreSolicitante,
    String? folioKepler,
  }) async {
    try {
      final logistica = LogisticaService();
      final nombreEnt = await logistica.nombrePorRut(
        rutEntregador,
        fallback: nombreEntregador,
      );
      final nombreSol = await logistica.nombrePorRut(
        rutSolicitante,
        fallback: nombreSolicitante,
      );

      await _db
          .from('solicitudes_bodega')
          .update({
            'estado': 'emitida',
            'nombre_entregador': nombreEnt,
            'nombre_solicitante': nombreSol,
            if (folioKepler != null) 'folio_kepler': folioKepler,
          })
          .eq('solicitud_id', solicitudId)
          .inFilter('estado', ['firmada', 'confirmada_bodega']);

      final ruts = [rutEntregador, rutSolicitante];
      final tokenRows = await _db
          .from('nomina_tecnicos')
          .select('rut, fcm_token')
          .inFilter('rut', ruts);

      final body = '$detalleMaterial · $nombreEnt → $nombreSol';
      for (final row in (tokenRows as List)) {
        final token = row['fcm_token'] as String?;
        if (token == null || token.isEmpty) continue;
        await _enviarFcmAlerta(
          token:       token,
          accion:      'guia_emitida',
          titulo:      'Guía de entrega disponible',
          descripcion: body,
          extra:       {'solicitud_id': solicitudId},
        );
      }
      debugPrint('📦 [Material] guía emitida → entregador y solicitante');
    } catch (e) {
      debugPrint('⚠️ [Material] emitirGuiaTrasAprobacion: $e');
    }
  }

  /// Devuelve el id_material y serie (si aplica) para la categoría solicitada
  /// buscando en el stock actual del técnico entregador.
  /// Para no seriados: toma el primer ítem con saldo suficiente.
  /// Para seriados: devuelve null — B debe escanear la serie antes de llamar aceptar().
  Future<int?> resolverIdMaterial({
    required String rutEntregador,
    required String tipoMaterial,
    required bool esSeriado,
    required int cantidad,
  }) async {
    if (esSeriado) return null; // se resuelve por escaneo
    List<TecnicoStock> stock;
    try {
      stock = await LogisticaService().fetchStock();
    } catch (e) {
      debugPrint('⚠️ [Material] resolverIdMaterial: API logística no disponible ($e)');
      return null;
    }
    final tecnico = stock
        .where((t) => LogisticaService.sameRut(t.rut, rutEntregador))
        .firstOrNull;
    if (tecnico == null) return null;
    try {
      final item = tecnico.itemParaCategoria(tipoMaterial, cantidad: cantidad);
      return item.idMaterial;
    } catch (_) {
      return null;
    }
  }

  /// Cancela una solicitud activa (solicitante o entregador) hasta antes de `completada`.
  Future<void> cancelarSolicitud({
    required String solicitudId,
    required String rutCancelador,
  }) async {
    final row = await _db
        .from('solicitudes_material')
        .select('estado, rut_solicitante, rut_entregador, tipo_material')
        .eq('id', solicitudId)
        .maybeSingle();
    if (row == null) throw StateError('Solicitud no encontrada');

    final estado = row['estado'] as String? ?? '';
    if (estado == 'completada' || estado == 'cancelada') {
      throw StateError('Esta solicitud ya no se puede cancelar');
    }

    final rs = row['rut_solicitante'] as String? ?? '';
    final re = row['rut_entregador'] as String?;
    final autorizado = LogisticaService.sameRut(rutCancelador, rs) ||
        (re != null &&
            re.isNotEmpty &&
            LogisticaService.sameRut(rutCancelador, re));
    if (!autorizado) {
      throw StateError('No tienes permiso para cancelar esta solicitud');
    }

    await _db.from('solicitudes_material').update({
      'estado':        'cancelada',
      'pin_codigo':    null,
      'pin_expira_en': null,
    }).eq('id', solicitudId);

    await notificarCancelacion(
      solicitudId:  solicitudId,
      tipoMaterial: row['tipo_material'] as String? ?? 'material',
    );
  }

  /// Notifica a solicitante, entregador y destinatarios que la solicitud fue cancelada.
  Future<void> notificarCancelacion({
    required String solicitudId,
    required String tipoMaterial,
  }) async {
    try {
      final solRow = await _db
          .from('solicitudes_material')
          .select('rut_solicitante, rut_entregador')
          .eq('id', solicitudId)
          .maybeSingle();

      List<dynamic> rows = await _db
          .from('solicitudes_material_destinatarios')
          .select()
          .eq('solicitud_id', solicitudId)
          .inFilter('estado', ['pendiente', 'aceptada']);

      if (rows.isEmpty) {
        await Future.delayed(const Duration(seconds: 3));
        rows = await _db
            .from('solicitudes_material_destinatarios')
            .select()
            .eq('solicitud_id', solicitudId)
            .inFilter('estado', ['pendiente', 'aceptada']);
      }

      await _db
          .from('solicitudes_material_destinatarios')
          .update({'estado': 'cancelada'})
          .eq('solicitud_id', solicitudId)
          .inFilter('estado', ['pendiente', 'aceptada']);

      final rutsNotificar = <String>{};
      if (solRow != null) {
        final rs = solRow['rut_solicitante'] as String?;
        final re = solRow['rut_entregador'] as String?;
        if (rs != null && rs.isNotEmpty) rutsNotificar.add(rs);
        if (re != null && re.isNotEmpty) rutsNotificar.add(re);
      }
      for (final d in rows) {
        final rut = d['rut_tecnico'] as String?;
        if (rut != null && rut.isNotEmpty) rutsNotificar.add(rut);
      }

      for (final rut in rutsNotificar) {
        try {
          final tokenRow = await _db
              .from('nomina_tecnicos')
              .select('fcm_token')
              .eq('rut', rut)
              .maybeSingle();
          final fcmToken = tokenRow?['fcm_token'] as String?;
          if (fcmToken != null && fcmToken.isNotEmpty) {
            await _enviarFcmAlerta(
              token:       fcmToken,
              accion:      'solicitud_cancelada',
              titulo:      'Transacción cancelada',
              descripcion: 'La solicitud de $tipoMaterial fue cancelada',
              extra:       {'solicitud_id': solicitudId},
            );
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Notifica a bodegueros que hay un traspaso pendiente (FCM data-only → sonido BG).
  Future<void> notificarBodeguerosTraspasoNuevo({
    required String traspasoId,
    required String tipoMaterial,
    required String nombreEntregador,
    required String nombreSolicitante,
  }) async {
    try {
      final rows = await _db.from('nomina_bodega').select('rut, fcm_token');
      final body =
          '$tipoMaterial · $nombreEntregador → $nombreSolicitante';
      for (final row in (rows as List)) {
        final token = row['fcm_token'] as String?;
        if (token == null || token.isEmpty) continue;
        await _enviarFcmAlerta(
          token:       token,
          accion:      'traspaso_bodega',
          titulo:      'Nuevo traspaso en bodega',
          descripcion: body,
          extra:       {'traspaso_id': traspasoId},
        );
      }
      debugPrint('📦 [Material] FCM traspaso_bodega → bodegueros');
    } catch (e) {
      debugPrint('⚠️ [Material] notificarBodeguerosTraspasoNuevo: $e');
    }
  }

  /// Notifica a todos los bodegueros cuando una guía queda firmada (bandeja bodega).
  Future<void> notificarBodeguerosGuiaFirmada({
    required String guiaId,
    required String solicitudId,
    required String detalleMaterial,
    required String nombreEntregador,
    required String nombreSolicitante,
  }) async {
    try {
      final rows = await _db.from('nomina_bodega').select('rut, fcm_token');
      final body =
          '$detalleMaterial · $nombreEntregador → $nombreSolicitante';
      for (final row in (rows as List)) {
        final token = row['fcm_token'] as String?;
        if (token == null || token.isEmpty) continue;
        await _enviarFcmAlerta(
          token:       token,
          accion:      'guia_firmada_bodega',
          titulo:      'Guía firmada — revisar bodega',
          descripcion: body,
          extra:       {
            'guia_id':      guiaId,
            'solicitud_id': solicitudId,
          },
        );
      }
      debugPrint('📦 [Material] FCM guía firmada → bodegueros (${(rows as List).length})');
    } catch (e) {
      debugPrint('⚠️ [Material] notificarBodeguerosGuiaFirmada: $e');
    }
  }

  /// Notifica al supervisor del solicitante si la solicitud sigue `pendiente`
  /// tras 10 minutos sin que nadie la acepte (una sola vez por solicitud).
  Future<bool> notificarSupervisorSinRespuesta({
    required String solicitudId,
    required String rutSolicitante,
    required String tipoMaterial,
  }) async {
    try {
      final row = await _db
          .from('solicitudes_material')
          .select(
              'estado, alerta_supervisor_sin_respuesta_at, nombre_solicitante')
          .eq('id', solicitudId)
          .maybeSingle();
      if (row == null) return false;

      final estado = row['estado'] as String? ?? '';
      if (estado != 'pendiente') return false;
      if (row['alerta_supervisor_sin_respuesta_at'] != null) return false;

      String nombreSol = row['nombre_solicitante'] as String? ?? '';
      try {
        nombreSol =
            await LogisticaService().nombreDesdeNomina(rutSolicitante);
      } catch (_) {}

      final rutCanon = LogisticaService.canonicalRut(rutSolicitante);
      List<dynamic> stcRows = await _db
          .from('supervisor_tecnicos_crea')
          .select('rut_supervisor, rut_tecnico')
          .eq('rut_tecnico', rutCanon);
      if ((stcRows).isEmpty) {
        final todos = await _db
            .from('supervisor_tecnicos_crea')
            .select('rut_supervisor, rut_tecnico');
        stcRows = (todos as List)
            .where((r) => LogisticaService.sameRut(
                  r['rut_tecnico'] as String? ?? '',
                  rutCanon,
                ))
            .toList();
      }

      final supervisores = <String>{};
      for (final r in stcRows) {
        final rutSup =
            LogisticaService.canonicalRut(r['rut_supervisor'] as String? ?? '');
        if (rutSup.isNotEmpty) supervisores.add(rutSup);
      }

      if (supervisores.isEmpty) {
        debugPrint(
            '⚠️ [Material] sin supervisor en CREA para $rutCanon — no se escala');
        return false;
      }

      var enviados = 0;
      for (final rutSup in supervisores) {
        final tokenRow = await _db
            .from('supervisores_crea')
            .select('fcm_token')
            .eq('rut', rutSup)
            .maybeSingle();
        final token = tokenRow?['fcm_token'] as String?;
        if (token == null || token.isEmpty) continue;

        await _enviarFcmSupervisor(
          token:       token,
          accion:      'material_sin_respuesta',
          titulo:      'Material sin atender',
          descripcion:
              '$nombreSol lleva 10 min sin respuesta — solicita $tipoMaterial',
          extra:       {
            'solicitud_id': solicitudId,
            'rut':          rutSup,
          },
        );
        enviados++;
      }

      if (enviados == 0) {
        debugPrint(
            '⚠️ [Material] supervisores sin FCM para solicitud $solicitudId');
        return false;
      }

      await _db
          .from('solicitudes_material')
          .update({
            'alerta_supervisor_sin_respuesta_at':
                DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', solicitudId)
          .eq('estado', 'pendiente')
          .isFilter('alerta_supervisor_sin_respuesta_at', null);

      debugPrint(
          '📣 [Material] FCM material_sin_respuesta → $enviados supervisor(es)');
      return true;
    } catch (e) {
      debugPrint('⚠️ [Material] notificarSupervisorSinRespuesta: $e');
      return false;
    }
  }

  Future<void> _enviarFcmSupervisor({
    required String token,
    required String accion,
    required String titulo,
    required String descripcion,
    Map<String, dynamic>? extra,
  }) async {
    try {
      await _db.functions.invoke('fcm-send', body: {
        'token':              token,
        'accion':             accion,
        'tipo':               titulo,
        'title':              titulo,
        'body':               descripcion,
        'descripcion':        descripcion,
        'android_channel_id': 'mat_alertas_7',
        'android_priority':   'high',
        if (extra != null) ...extra,
      }).timeout(_fcmTimeout);
      debugPrint('✅ [Material] FCM supervisor $accion');
    } catch (e) {
      debugPrint('⚠️ [Material] FCM supervisor $accion falló: $e');
    }
  }

  /// Destinatarios que siguen pendientes (para alerta de 10 minutos).
  Future<List<Map<String, dynamic>>> destinatariosPendientes(
      String solicitudId) async {
    final rows = await _db
        .from('solicitudes_material_destinatarios')
        .select()
        .eq('solicitud_id', solicitudId)
        .eq('estado', 'pendiente');
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// Umbrales de alerta para el bodeguero.
  static const _umbralOnt       = 3;
  static const _umbralDeco      = 5;
  static const _umbralExtensor  = 2;

  /// Consulta el stock del solicitante en Kepler. Si supera algún umbral
  /// (ONT>3, Decodificador>5, Extensor>2) inserta en alertas_auditoria_material.
  /// Se llama en background — nunca lanza hacia el caller.
  Future<void> verificarAlertaStock({
    required String solicitudId,
    required String rutSolicitante,
    required String nombreSolicitante,
    required String tipoMaterial,
  }) async {
    try {
      String nombreTecnico = nombreSolicitante;
      try {
        nombreTecnico =
            await LogisticaService().nombreDesdeNomina(rutSolicitante);
      } catch (_) {}

      final tecnico = await LogisticaService().fetchStockTecnico(rutSolicitante);
      if (tecnico == null || tecnico.sinStock) return;

      final stockOnt  = (tecnico.stock['ONT ZTE']    ?? 0) +
                        (tecnico.stock['ONT Huawei']  ?? 0);
      final stockDecoClaro =
          tecnico.stock['Decodificador Claro'] ?? 0;
      final stockDecoVtr =
          tecnico.stock['Decodificador VTR'] ?? 0;
      final stockDeco = stockDecoClaro + stockDecoVtr;
      final stockExt  = tecnico.stock['Extensor']      ?? 0;

      if (stockOnt <= _umbralOnt &&
          stockDeco <= _umbralDeco &&
          stockExt  <= _umbralExtensor) return;

      await _db.from('alertas_auditoria_material').insert({
        'solicitud_id':        solicitudId,
        'rut_tecnico':         rutSolicitante,
        'nombre_tecnico':      nombreTecnico,
        'tipo_material':       tipoMaterial,
        'stock_ont':           stockOnt,
        'stock_decodificador': stockDeco,
        'stock_deco_claro':    stockDecoClaro,
        'stock_deco_vtr':      stockDecoVtr,
        'stock_extensor':      stockExt,
        'estado':              'pendiente',
      });

      debugPrint('🟠 [AlertaStock] alerta generada: $rutSolicitante '
          'ONT=$stockOnt Deco=$stockDeco Ext=$stockExt');
    } catch (e) {
      debugPrint('⚠️ [AlertaStock] error: $e');
    }
  }

  double _distanciaKm(double lat1, double lon1, double lat2, double lon2) {
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

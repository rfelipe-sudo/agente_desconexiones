import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/services/alerta_sistema_service.dart';
import 'package:agente_desconexiones/services/logistica_service.dart';

class MaterialSolicitudService {
  final _db = Supabase.instance.client;

  /// Encuentra técnicos cercanos con stock suficiente y los notifica.
  /// Si la API de Kepler no responde, hace bypass: aplica solo filtro de
  /// distancia y rol (sin filtro de stock), y registra un fallo de sistema.
  Future<void> notificarDestinatarios({
    required String solicitudId,
    required String tipoMaterial,
    required double? latSolicitante,
    required double? lngSolicitante,
    required String rutSolicitante,
    String? nombreSolicitante,
  }) async {
    // Fetch ubicaciones (siempre necesario, independiente de Kepler)
    List<dynamic> ubicRows;
    try {
      ubicRows = await _db
          .from('tecnicos_ubicacion')
          .select('tecnico_id, latitud, longitud');
    } catch (e) {
      debugPrint('⚠️ [Material] notificarDestinatarios: error Supabase ubicaciones ($e)');
      return;
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

    // Mapa rut → (lat, lng)
    final Map<String, (double, double)> ubicMap = {};
    for (final u in ubicRows) {
      final rut = u['tecnico_id'] as String?;
      final lat = (u['latitud']  as num?)?.toDouble();
      final lng = (u['longitud'] as num?)?.toDouble();
      if (rut != null && lat != null && lng != null) {
        ubicMap[rut] = (lat, lng);
      }
    }
    debugPrint('[MatDest] ubicMap: ${ubicMap.length} técnicos con posición');

    // Excluir bodega, supervisores, ITOs y perfiles administrativos de flota
    final excluirResults = await Future.wait<dynamic>([
      _db.from('nomina_bodega').select('rut'),
      _db.from('supervisores_crea').select('rut'),
      _db.from('equipos_crea').select('rut_tecnico').eq('rol', 'ito'),
      _db.from('roles_flota').select('rut'),
    ]);
    Set<String> toRutSet(dynamic rows, {String key = 'rut'}) => (rows as List)
        .map((r) => r[key] as String? ?? '')
        .where((r) => r.isNotEmpty)
        .toSet();
    final bodegaRuts     = toRutSet(excluirResults[0]);
    final supervisorRuts = toRutSet(excluirResults[1]);
    final itoRuts        = toRutSet(excluirResults[2], key: 'rut_tecnico');
    final flotaRuts      = toRutSet(excluirResults[3]);
    final excluirRuts    = {...bodegaRuts, ...supervisorRuts, ...itoRuts, ...flotaRuts};
    debugPrint('[MatDest] excluirRuts: ${excluirRuts.length} (bodega=${bodegaRuts.length} sup=${supervisorRuts.length} ito=${itoRuts.length} flota=${flotaRuts.length})');

    // Umbrales por tipo: ONT/Deco necesitan tener >3 para compartir (son costosos),
    // Extensor >2, el resto (consumibles: grampas, pasacables, etc.) >0 es suficiente.
    final double umbral;
    if (tipoMaterial.contains('ONT') || tipoMaterial.contains('Decodificador')) {
      umbral = 3.0;
    } else if (tipoMaterial.contains('Extensor')) {
      umbral = 2.0;
    } else {
      umbral = 0.0; // consumibles: grampa, pasacable, cáncamo, roseta, etc.
    }
    debugPrint('[MatDest] tipoMaterial=$tipoMaterial umbral=$umbral keplerFallo=$keplerFallo stock=${stock?.length ?? "null"}');

    final List<Map<String, dynamic>> destinatarios = [];

    if (!keplerFallo && stock != null) {
      // Flujo normal: stock + distancia + rol
      for (final tecnico in stock) {
        if (tecnico.rut == rutSolicitante) continue;
        if (excluirRuts.contains(tecnico.rut)) {
          debugPrint('[MatDest] ${tecnico.rut} → excluido por rol');
          continue;
        }

        final cantidad = tecnico.stock[tipoMaterial] ?? 0;
        if (cantidad <= umbral) {
          debugPrint('[MatDest] ${tecnico.rut} → stock insuficiente ($tipoMaterial=$cantidad <= $umbral)');
          continue;
        }

        if (latSolicitante != null && lngSolicitante != null) {
          final pos = ubicMap[tecnico.rut];
          if (pos == null) {
            debugPrint('[MatDest] ${tecnico.rut} → sin ubicación en tecnicos_ubicacion');
            continue;
          }
          final dist = _distanciaKm(latSolicitante, lngSolicitante, pos.$1, pos.$2);
          if (dist > 5.0) {
            debugPrint('[MatDest] ${tecnico.rut} → demasiado lejos (${dist.toStringAsFixed(1)} km)');
            continue;
          }
          debugPrint('[MatDest] ${tecnico.rut} ✓ stock=$cantidad dist=${dist.toStringAsFixed(1)}km');
        }

        destinatarios.add({
          'solicitud_id':     solicitudId,
          'rut_tecnico':      tecnico.rut,
          'nombre_tecnico':   tecnico.nombre,
          'stock_disponible': cantidad.toInt(),
          'estado':           'pendiente',
        });
      }
    } else {
      // Bypass: solo distancia + rol; stock_disponible = -1 (desconocido)
      for (final entry in ubicMap.entries) {
        final rut = entry.key;
        if (rut == rutSolicitante) continue;
        if (excluirRuts.contains(rut)) continue;

        if (latSolicitante != null && lngSolicitante != null) {
          final pos = entry.value;
          final dist = _distanciaKm(latSolicitante, lngSolicitante, pos.$1, pos.$2);
          if (dist > 5.0) continue;
        }

        // Nombre del técnico: intentar obtener de nomina_tecnicos
        String nombreTecnico = rut;
        try {
          final row = await _db
              .from('nomina_tecnicos')
              .select('nombres')
              .eq('rut', rut)
              .maybeSingle();
          if (row != null) nombreTecnico = row['nombres'] as String? ?? rut;
        } catch (_) {}

        destinatarios.add({
          'solicitud_id':     solicitudId,
          'rut_tecnico':      rut,
          'nombre_tecnico':   nombreTecnico,
          'stock_disponible': -1,
          'estado':           'pendiente',
        });
      }
    }

    // ── Segundo pase: técnicos con GPS cercanos que Kepler no conoce ──────────
    // Si Kepler corrió OK pero un técnico tiene posición GPS y no fue alcanzado
    // por el primer pase (no está en supervisor_tecnicos_crea), igual lo notificamos.
    if (!keplerFallo && latSolicitante != null && lngSolicitante != null) {
      final yaNotificados = destinatarios.map((d) => d['rut_tecnico'] as String).toSet();
      for (final entry in ubicMap.entries) {
        final rut = entry.key;
        if (rut == rutSolicitante) continue;
        if (excluirRuts.contains(rut)) continue;
        if (yaNotificados.contains(rut)) continue;

        final dist = _distanciaKm(latSolicitante, lngSolicitante, entry.value.$1, entry.value.$2);
        if (dist > 5.0) continue;

        String nombreTecnico = rut;
        try {
          final row = await _db
              .from('nomina_tecnicos')
              .select('nombres')
              .eq('rut', rut)
              .maybeSingle();
          if (row != null) nombreTecnico = row['nombres'] as String? ?? rut;
        } catch (_) {}

        debugPrint('[MatDest] $rut ✓ GPS-pase2 dist=${dist.toStringAsFixed(1)}km (sin stock Kepler)');
        destinatarios.add({
          'solicitud_id':     solicitudId,
          'rut_tecnico':      rut,
          'nombre_tecnico':   nombreTecnico,
          'stock_disponible': -1,
          'estado':           'pendiente',
        });
      }
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
          try {
            await _db.functions.invoke('fcm-send', body: {
              'token':       fcmToken,
              'accion':      'solicitud_material',
              'tipo':        'Solicitud de material',
              'descripcion': 'Se necesita: $tipoMaterial',
              'rut':         rut,
            });
          } catch (_) {}
        }
      } catch (_) {}
    }
  }

  /// El primer técnico que acepta: cancela los otros destinatarios y actualiza la solicitud.
  /// [idMaterial] es el id interno de Kepler para el ítem a entregar.
  /// [serieEscaneada] solo para ítems seriados (se captura antes de llamar esto).
  Future<void> aceptar({
    required String solicitudId,
    required String rutAceptador,
    required String nombreAceptador,
    required double? lat,
    required double? lng,
    required String modalidad,
    int? idMaterial,
    String? serieEscaneada,
  }) async {
    await _db
        .from('solicitudes_material_destinatarios')
        .update({'estado': 'aceptada'})
        .eq('solicitud_id', solicitudId)
        .eq('rut_tecnico', rutAceptador);

    await _db
        .from('solicitudes_material_destinatarios')
        .update({'estado': 'cancelada'})
        .eq('solicitud_id', solicitudId)
        .neq('rut_tecnico', rutAceptador)
        .eq('estado', 'pendiente');

    // Solo actualiza si todavía está pendiente (evitar race condition)
    await _db.from('solicitudes_material').update({
      'estado':            'aceptada',
      'rut_entregador':    rutAceptador,
      'nombre_entregador': nombreAceptador,
      'lat_entregador':    lat,
      'lng_entregador':    lng,
      'modalidad':         modalidad,
      if (idMaterial != null) 'id_material': idMaterial,
      if (serieEscaneada != null) 'series': [serieEscaneada],
    }).eq('id', solicitudId).eq('estado', 'pendiente');
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
    final tecnico = stock.where((t) => t.rut == rutEntregador).firstOrNull;
    if (tecnico == null) return null;
    try {
      final item = tecnico.itemParaCategoria(tipoMaterial, cantidad: cantidad);
      return item.idMaterial;
    } catch (_) {
      return null;
    }
  }

  /// Notifica a todos los destinatarios pendientes que la solicitud fue cancelada.
  /// Llama fire-and-forget desde _cancelar(); los errores individuales se ignoran.
  Future<void> notificarCancelacion({
    required String solicitudId,
    required String tipoMaterial,
  }) async {
    try {
      // Leer destinatarios ANTES de actualizar para tener sus datos.
      // Si aún no se insertaron (usuario canceló muy rápido), esperar hasta 3 s.
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

      // Marcar destinatarios como cancelados en DB
      await _db
          .from('solicitudes_material_destinatarios')
          .update({'estado': 'cancelada'})
          .eq('solicitud_id', solicitudId)
          .inFilter('estado', ['pendiente', 'aceptada']);

      // Enviar FCM para limpiar notificación en bandeja del destinatario
      for (final d in rows) {
        try {
          final tokenRow = await _db
              .from('nomina_tecnicos')
              .select('fcm_token')
              .eq('rut', d['rut_tecnico'] as String)
              .maybeSingle();
          final fcmToken = tokenRow?['fcm_token'] as String?;
          if (fcmToken != null && fcmToken.isNotEmpty) {
            await _db.functions.invoke('fcm-send', body: {
              'token':       fcmToken,
              'accion':      'solicitud_cancelada',
              'descripcion': 'La solicitud de $tipoMaterial fue cancelada',
            });
          }
        } catch (_) {}
      }
    } catch (_) {}
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
      final allStock = await LogisticaService().fetchStock();
      final tecnico  = allStock.where((t) => t.rut == rutSolicitante).firstOrNull;
      if (tecnico == null) return;

      final stockOnt  = (tecnico.stock['ONT ZTE']    ?? 0) +
                        (tecnico.stock['ONT Huawei']  ?? 0);
      final stockDeco = tecnico.stock['Decodificador'] ?? 0;
      final stockExt  = tecnico.stock['Extensor']      ?? 0;

      if (stockOnt <= _umbralOnt &&
          stockDeco <= _umbralDeco &&
          stockExt  <= _umbralExtensor) return;

      await _db.from('alertas_auditoria_material').insert({
        'solicitud_id':       solicitudId,
        'rut_tecnico':        rutSolicitante,
        'nombre_tecnico':     nombreSolicitante,
        'tipo_material':      tipoMaterial,
        'stock_ont':          stockOnt,
        'stock_decodificador': stockDeco,
        'stock_extensor':     stockExt,
        'estado':             'pendiente',
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

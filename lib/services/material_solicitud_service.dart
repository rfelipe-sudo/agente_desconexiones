import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/services/logistica_service.dart';

class MaterialSolicitudService {
  final _db = Supabase.instance.client;

  /// Encuentra técnicos cercanos con stock suficiente y los notifica.
  Future<void> notificarDestinatarios({
    required String solicitudId,
    required String tipoMaterial,
    required double? latSolicitante,
    required double? lngSolicitante,
    required String rutSolicitante,
  }) async {
    // Fetch en paralelo: stock logístico + ubicaciones
    final results = await Future.wait<dynamic>([
      LogisticaService().fetchStock(),
      _db.from('tecnicos_ubicacion').select('tecnico_id, latitud, longitud'),
    ]);
    final stock    = results[0] as List<TecnicoStock>;
    final ubicRows = results[1] as List<dynamic>;

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

    final esExtensor = tipoMaterial.contains('Extensor');
    final umbral     = esExtensor ? 3.0 : 5.0;

    // Excluir bodega, supervisores e ITOs
    final excluirResults = await Future.wait<dynamic>([
      _db.from('nomina_bodega').select('rut'),
      _db.from('supervisores_crea').select('rut'),
      _db.from('equipos_crea').select('rut').eq('rol', 'ito'),
    ]);
    Set<String> toRutSet(dynamic rows) => (rows as List)
        .map((r) => r['rut'] as String? ?? '')
        .where((r) => r.isNotEmpty)
        .toSet();
    final bodegaRuts     = toRutSet(excluirResults[0]);
    final supervisorRuts = toRutSet(excluirResults[1]);
    final itoRuts        = toRutSet(excluirResults[2]);
    final excluirRuts    = {...bodegaRuts, ...supervisorRuts, ...itoRuts};

    final List<Map<String, dynamic>> destinatarios = [];

    for (final tecnico in stock) {
      if (tecnico.rut == rutSolicitante) continue;
      if (excluirRuts.contains(tecnico.rut)) continue;

      final cantidad = tecnico.stock[tipoMaterial] ?? 0;
      if (cantidad <= umbral) continue;

      // Filtro de distancia (solo si tenemos ambas posiciones)
      if (latSolicitante != null && lngSolicitante != null) {
        final pos = ubicMap[tecnico.rut];
        if (pos == null) continue; // sin ubicación conocida → omitir
        final dist = _distanciaKm(latSolicitante, lngSolicitante, pos.$1, pos.$2);
        if (dist > 5.0) continue;
      }

      destinatarios.add({
        'solicitud_id':     solicitudId,
        'rut_tecnico':      tecnico.rut,
        'nombre_tecnico':   tecnico.nombre,
        'stock_disponible': cantidad.toInt(),
        'estado':           'pendiente',
      });
    }

    if (destinatarios.isNotEmpty) {
      await _db.from('solicitudes_material_destinatarios').insert(destinatarios);
    }

    // FCM solo a los destinatarios calificados (stock suficiente + dentro de 5 km)
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
    final stock = await LogisticaService().fetchStock();
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
      final rows = await _db
          .from('solicitudes_material_destinatarios')
          .select()
          .eq('solicitud_id', solicitudId)
          .inFilter('estado', ['pendiente', 'aceptada']);

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

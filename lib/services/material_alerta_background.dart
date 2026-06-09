import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/services/ayuda_service.dart';
import 'package:agente_desconexiones/services/material_alerta_estado.dart';

/// Alertas de material en segundo plano (isolate del foreground service o handler FCM).
/// Usa el canal nativo [mat_alertas_7] creado en CreaboxApplication.kt.
@pragma('vm:entry-point')
class MaterialAlertaBackground {
  MaterialAlertaBackground._();

  static const _channelId = 'mat_alertas_7';
  static const _ayudaChannelId = 'ayuda_supervisor_1';
  static FlutterLocalNotificationsPlugin? _plugin;
  static bool _init = false;

  static const _accionesSonoras = {
    'solicitud_material',
    'guia_firmada_bodega',
    'sol_comb_flota',
    'sol_comb_jefe_ops',
    'traspaso_bodega',
  };

  static const _accionesAyudaSupervisor = {
    'solicitud_ayuda',
    'material_sin_respuesta',
    'ayuda_cancelada',
  };

  static Future<void> _ensureInit() async {
    if (_init) return;
    _plugin = FlutterLocalNotificationsPlugin();
    await _plugin!.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ));
    _init = true;
  }

  /// Muestra notificación con sonido del canal mat_alertas_7 (USAGE_ALARM).
  @pragma('vm:entry-point')
  static Future<void> mostrarDesdeFcm(Map<String, dynamic> data) async {
    final accion = data['accion']?.toString();
    if (accion == null) return;
    if (!_accionesSonoras.contains(accion) &&
        !_accionesAyudaSupervisor.contains(accion)) {
      return;
    }

    final title = data['title']?.toString() ??
        data['tipo']?.toString() ??
        _tituloDefault(accion);
    final body = data['body']?.toString() ??
        data['descripcion']?.toString() ??
        _cuerpoDefault(accion);

    await mostrar(accion: accion, title: title, body: body, data: data);
  }

  @pragma('vm:entry-point')
  static Future<void> mostrar({
    required String accion,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    if (!_accionesSonoras.contains(accion) &&
        !_accionesAyudaSupervisor.contains(accion)) {
      return;
    }
    try {
      await _ensureInit();
      final esAyuda = _accionesAyudaSupervisor.contains(accion);
      final notifId = switch (accion) {
        'solicitud_material' => 42,
        'guia_firmada_bodega' => 45,
        'traspaso_bodega' => 44,
        'solicitud_ayuda' => 48,
        'material_sin_respuesta' => 46,
        'ayuda_cancelada' => 49,
        _ => 43,
      };

      final androidDetails = AndroidNotificationDetails(
        esAyuda ? _ayudaChannelId : _channelId,
        esAyuda ? 'Ayuda en terreno — supervisor' : 'Alertas de material',
        channelDescription: esAyuda
            ? 'Solicitudes de ayuda de técnicos en terreno'
            : 'Alertas de solicitudes de material entre técnicos',
        importance: Importance.max,
        priority: Priority.max,
        playSound: accion != 'ayuda_cancelada',
        sound: accion == 'ayuda_cancelada'
            ? null
            : RawResourceAndroidNotificationSound(
                esAyuda ? 'ayuda_supervisor_mario' : 'alerta_urgente',
              ),
        enableVibration: true,
        vibrationPattern: Int64List.fromList(
          esAyuda ? [0, 400, 200, 400] : [0, 300, 200, 300],
        ),
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
        fullScreenIntent: true,
      );

      await _plugin!.show(
        notifId,
        title,
        body,
        NotificationDetails(android: androidDetails),
        payload: jsonEncode(data ?? {'accion': accion, 'title': title, 'body': body}),
      );
      debugPrint('🔔 [MatBG] alerta mostrada accion=$accion');
    } catch (e) {
      debugPrint('🔔 [MatBG] error mostrando alerta: $e');
    }
  }

  /// Monitor ayuda en terreno para supervisor (foreground service / app minimizada).
  @pragma('vm:entry-point')
  static StreamSubscription<List<Map<String, dynamic>>>? iniciarMonitorAyudaSupervisor(
    String rutSupervisor,
  ) {
    if (rutSupervisor.isEmpty) return null;

    final alerteados = <String>{};
    var init = false;
    Set<String> rutsEquipo = {};

    debugPrint('🆘 [AyudaBG] monitor supervisor rut=$rutSupervisor');

    Future<void> cargarEquipo() async {
      try {
        rutsEquipo.clear();
        final lista = await AyudaService().obtenerRutsEquipo(rutSupervisor);
        rutsEquipo.addAll(lista);
      } catch (e) {
        debugPrint('🆘 [AyudaBG] error cargando equipo: $e');
      }
    }

    bool esParaMi(Map<String, dynamic> row) {
      final tipo = row['tipo']?.toString() ?? '';
      if (tipo == 'movimiento_material') return false;
      final estado = row['estado']?.toString() ?? '';
      if (estado != 'pendiente') return false;
      final rutTec = row['rut_tecnico']?.toString() ?? '';
      final rutSup = row['rut_supervisor']?.toString() ?? '';
      if (AyudaService.mismoRut(rutSup, rutSupervisor)) return true;
      if (rutsEquipo.any((r) => AyudaService.mismoRut(r, rutTec))) return true;
      return rutsEquipo.isEmpty && rutSup.isEmpty;
    }

    unawaited(cargarEquipo());

    return Supabase.instance.client
        .from('ayuda_terreno_crea')
        .stream(primaryKey: ['ticket_id'])
        .order('created_at', ascending: false)
        .listen(
      (rows) async {
        if (!init) {
          for (final row in rows) {
            final tid = row['ticket_id']?.toString();
            if (tid != null) alerteados.add(tid);
          }
          init = true;
          debugPrint('🆘 [AyudaBG] carga inicial ${rows.length} tickets');
          return;
        }
        if (rutsEquipo.isEmpty) await cargarEquipo();
        for (final row in rows) {
          if (!esParaMi(row)) continue;
          final tid = row['ticket_id']?.toString();
          if (tid == null || alerteados.contains(tid)) continue;
          alerteados.add(tid);
          final nombre = row['nombre_tecnico']?.toString() ?? 'Técnico';
          final tipo = row['tipo']?.toString() ?? 'ayuda';
          debugPrint('🆘 [AyudaBG] ✅ nueva ayuda $tid → Mario');
          await mostrar(
            accion: 'solicitud_ayuda',
            title: '¡Solicitud de ayuda en terreno!',
            body: '$nombre necesita ayuda — $tipo',
            data: {'accion': 'solicitud_ayuda', 'ticket_id': tid},
          );
        }
      },
      onError: (Object e) => debugPrint('🆘 [AyudaBG] error stream: $e'),
    );
  }

  /// Monitor Supabase en el isolate del foreground service (app minimizada).
  @pragma('vm:entry-point')
  static StreamSubscription<List<Map<String, dynamic>>>? iniciarMonitorSupabase(
    String rutTecnico,
  ) {
    if (rutTecnico.isEmpty) return null;

    final alerteadas = <String>{};
    var init = false;
    var persistLoaded = false;

    debugPrint('🔔 [MatBG] monitor Supabase rut=$rutTecnico');

    return Supabase.instance.client
        .from('solicitudes_material_destinatarios')
        .stream(primaryKey: ['id'])
        .eq('rut_tecnico', rutTecnico)
        .listen(
      (rows) async {
        if (!persistLoaded) {
          alerteadas.addAll(await MaterialAlertaEstado.load());
          persistLoaded = true;
        }
        if (!init) {
          if (rows.isEmpty) return;
          for (final row in rows) {
            final sid = row['solicitud_id']?.toString();
            if (sid != null) alerteadas.add(sid);
          }
          await MaterialAlertaEstado.markAllSeen(alerteadas);
          init = true;
          debugPrint('🔔 [MatBG] carga inicial ${alerteadas.length} solicitudes');
          return;
        }
        for (final row in rows) {
          final sid = row['solicitud_id']?.toString();
          final estado = row['estado']?.toString() ?? '';
          if (sid == null || estado != 'pendiente') continue;
          if (alerteadas.contains(sid)) continue;
          alerteadas.add(sid);
          await MaterialAlertaEstado.markSeen(sid);
          debugPrint('🔔 [MatBG] ✅ nueva solicitud $sid (background service)');
          await mostrar(
            accion: 'solicitud_material',
            title: '¡Solicitud de material!',
            body: 'Un colega necesita material',
            data: {'accion': 'solicitud_material', 'solicitud_id': sid},
          );
        }
      },
      onError: (Object e) => debugPrint('🔔 [MatBG] error stream: $e'),
    );
  }

  static String _tituloDefault(String accion) => switch (accion) {
        'solicitud_material' => '¡Solicitud de material!',
        'guia_firmada_bodega' => 'Guía firmada — revisar bodega',
        'traspaso_bodega' => 'Nuevo traspaso en bodega',
        'solicitud_ayuda' => '¡Solicitud de ayuda en terreno!',
        'material_sin_respuesta' => 'Material sin atender',
        'ayuda_cancelada' => 'Solicitud de ayuda cancelada',
        _ => '¡Solicitud de flota!',
      };

  static String _cuerpoDefault(String accion) => switch (accion) {
        'solicitud_material' => 'Un colega necesita material',
        'guia_firmada_bodega' => 'Nueva guía pendiente de confirmar',
        'traspaso_bodega' => 'Hay un traspaso pendiente de aprobación',
        'solicitud_ayuda' => 'Un técnico de tu equipo necesita ayuda',
        'material_sin_respuesta' =>
          'Un técnico de tu equipo lleva 10 min sin respuesta',
        'ayuda_cancelada' => 'Un técnico canceló su solicitud de ayuda',
        _ => 'Nueva solicitud de flota',
      };
}

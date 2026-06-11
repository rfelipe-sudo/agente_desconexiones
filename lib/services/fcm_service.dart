import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/config/constants.dart';
import 'package:agente_desconexiones/providers/alerta_provider.dart';
import 'package:agente_desconexiones/services/sesion_dispositivo_service.dart';
import 'package:agente_desconexiones/services/material_alerta_background.dart';
import 'package:agente_desconexiones/services/material_alerta_estado.dart';
import 'package:agente_desconexiones/services/comunicado_service.dart';
import 'package:agente_desconexiones/services/ayuda_service.dart';
import 'package:agente_desconexiones/services/logistica_service.dart';

/// Canal Android creado en CreaboxApplication.kt (USAGE_ALARM).
const _materialChannelId = 'mat_alertas_7';

/// Handler de mensajes FCM cuando la app está en **background o terminated**.
/// El sonido lo reproduce [MaterialAlertNotifier] en Kotlin; aquí solo prefs.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  if (message.data['accion'] == 'pin_intercambio') {
    final pin = message.data['pin']?.toString();
    if (pin != null && pin.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kPrefPendingPin, pin);
    }
  }
  if (message.data['accion'] == 'solicitud_atendida') {
    await FcmService.procesarSolicitudAtendidaSilenciosa(message.data);
  }
  if (message.data['accion'] == 'ayuda_cancelada') {
    await FcmService.procesarAyudaCanceladaSilenciosa(message.data);
  }
  await _aplicarAccion(message.data);
  await MaterialAlertaBackground.mostrarDesdeFcm(message.data);
  debugPrint('[FCM-BG] accion=${message.data['accion']} data=${message.data}');
}

/// Muestra (o cancela) una notificación local con sonido personalizado.
/// ID fijo 42 para solicitudes de material, lo que permite reemplazarla o
/// cancelarla cuando la solicitud cambia de estado.
/// Funciona tanto en foreground como en background (con WidgetsFlutterBinding
/// ya inicializado antes de llamar esta función).
Future<void> _mostrarNotificacionLocal(Map<String, dynamic> data) async {
  final accion = data['accion']?.toString();
  if (accion == null) return;

  final esMaterial    = accion == 'solicitud_material';
  final esCancelacion = accion == 'solicitud_cancelada';
  final esGuiaBodega  = accion == 'guia_firmada_bodega';
  final esFlota          = accion == 'sol_comb_flota' || accion == 'sol_comb_jefe_ops';
  final esTraspasoBodega = accion == 'traspaso_bodega';
  if (!esMaterial && !esCancelacion && !esGuiaBodega && !esFlota && !esTraspasoBodega) {
    return;
  }

  final flnp = FlutterLocalNotificationsPlugin();
  await flnp.initialize(const InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  ));

  final String title;
  final String body;
  final int    notifId;
  if (esMaterial) {
    title   = data['title']?.toString() ?? '¡Solicitud de material!';
    body    = data['body']?.toString() ?? data['descripcion']?.toString() ?? 'Un colega necesita material';
    notifId = 42;
  } else if (esCancelacion) {
    title   = 'Solicitud cancelada';
    body    = data['body']?.toString() ?? data['descripcion']?.toString() ?? 'La solicitud fue cancelada';
    notifId = 42;
  } else if (esGuiaBodega) {
    title   = data['title']?.toString() ?? 'Guía firmada — revisar bodega';
    body    = data['body']?.toString() ?? data['descripcion']?.toString() ?? 'Nueva guía pendiente de confirmar';
    notifId = 45;
  } else if (esTraspasoBodega) {
    title   = data['tipo']?.toString() ?? 'Nuevo traspaso en bodega';
    body    = data['body']?.toString() ?? data['descripcion']?.toString() ?? 'Hay un traspaso pendiente de aprobación';
    notifId = 44;
  } else {
    title   = data['tipo']?.toString() ?? '¡Solicitud de flota!';
    body    = data['body']?.toString() ?? data['descripcion']?.toString() ?? 'Nueva solicitud de flota';
    notifId = 43;
  }

  final androidDetails = AndroidNotificationDetails(
    _materialChannelId,
    'Alertas de material',
    channelDescription: 'Alertas de solicitudes de material entre técnicos',
    importance: Importance.high,
    priority: Priority.high,
    playSound: esMaterial || esGuiaBodega || esFlota || esTraspasoBodega,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 300, 200, 300]),
    category: AndroidNotificationCategory.alarm,
  );

  await flnp.show(
    notifId,
    title,
    body,
    NotificationDetails(android: androidDetails),
    payload: jsonEncode(data),
  );
}

/// Clave SharedPreferences que indica que hay una solicitud de material pendiente.
const String kPrefSolicitudMaterialPendiente = 'solicitud_material_pendiente';

/// Clave SharedPreferences: guía firmada pendiente en bandeja bodeguero.
const String kPrefGuiaBodegaPendiente = 'guia_bodega_pendiente';

/// Ruta pendiente al abrir la app desde una notificación (tap).
const String kPrefPendingRoute = 'fcm_pending_route';

/// PIN recibido en background antes de que el solicitante abra la app.
const String kPrefPendingPin = 'fcm_pending_pin';
const String kPrefPinVistoPrefix = 'pin_visto_';

/// Aplica la acción de un mensaje FCM al SharedPreferences.
/// Acciones soportadas:
/// - `bloquear_card`      → activar bloqueo "Mis Actividades"
/// - `desbloquear_card`   → resolver bloqueo
/// - `solicitud_material` → marcar solicitud de material pendiente
/// - `guia_firmada_bodega` → marcar guía pendiente para bodeguero
Future<void> _aplicarAccion(Map<String, dynamic> data) async {
  final accion = data['accion']?.toString();
  if (accion == null || accion.isEmpty) return;
  final prefs = await SharedPreferences.getInstance();
  if (accion == 'bloquear_card') {
    await prefs.setString(kPrefAlertaBloqueoMisActividades, 'true');
  } else if (accion == 'desbloquear_card') {
    await prefs.setString(kPrefAlertaBloqueoMisActividades, 'false');
  } else if (accion == 'solicitud_material') {
    await prefs.setString(kPrefSolicitudMaterialPendiente, 'true');
  } else if (accion == 'guia_firmada_bodega') {
    await prefs.setString(kPrefGuiaBodegaPendiente, 'true');
  } else if (accion == 'comunicado_creabox') {
    await prefs.setString(kPrefComunicadoPendiente, 'true');
  } else if (accion == 'solicitud_ayuda' || accion == 'ayuda_cancelada') {
    await prefs.setString(kPrefPendingRoute, '/solicitudes-ayuda');
  }
}

class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  static const _soundChannel = MethodChannel(
    'com.creacionestecnologicas.agente_desconexiones/sound',
  );

  static const _navChannel = MethodChannel(
    'com.creacionestecnologicas.agente_desconexiones/navigation',
  );

  static final FlutterLocalNotificationsPlugin _flnp =
      FlutterLocalNotificationsPlugin();
  static bool _flnpInit = false;

  /// IDs de solicitudes ya sonadas — compartido con SolicitudMaterialScreen
  /// para evitar que el stream de la pantalla vuelva a sonar si ya sonó aquí.
  static final Set<String> solicitudesNotificadas = {};

  StreamSubscription<List<Map<String, dynamic>>>? _pinSub;
  String? _pinUltimo;
  String? _pinMonitorSolicitudId;

  AlertaProvider? _alertaProvider;
  bool _initialized = false;

  // Monitor de solicitudes de material (stream, igual que PIN monitor)
  StreamSubscription<List<Map<String, dynamic>>>? _solicitudStreamSub;
  final Set<String> _solicitudesAlerteadas = {};
  bool _solicitudInit = false;
  String? _solicitudMonitorRut;

  // Monitor guías firmadas para bodeguero (stream solicitudes_bodega)
  StreamSubscription<List<Map<String, dynamic>>>? _bodegaGuiaSub;
  final Set<String> _guiasBodegaAlerteadas = {};
  bool _bodegaGuiaInit = false;

  // Monitor de traspasos (stream, igual que PIN monitor)
  StreamSubscription<List<Map<String, dynamic>>>? _traspasoSubA;
  StreamSubscription<List<Map<String, dynamic>>>? _traspasoSubB;
  final Map<String, String> _traspasoEstados = {};
  final Map<String, bool>   _traspasoSapOk   = {};
  final Set<String>         _traspasoIdsInit  = {};
  String? _traspasoMonitorRut;

  /// Conecta el provider para que los handlers en foreground puedan
  /// notificar cambios a la UI sin esperar a un refresh manual.
  void setAlertaProvider(AlertaProvider provider) {
    _alertaProvider = provider;
  }

  /// Monitor de solicitudes de material usando .stream() — mismo mecanismo
  /// que el PIN monitor, funciona sin REPLICA IDENTITY FULL.
  /// Suena cuando llega una solicitud nueva pendiente.
  Future<void> initSolicitudMonitor() async {
    debugPrint('🔔 [SOL] initSolicitudMonitor llamado');
    final prefs = await SharedPreferences.getInstance();
    final rut = prefs.getString('rut_tecnico') ??
        prefs.getString('user_rut') ??
        prefs.getString('rut');
    debugPrint('🔔 [SOL] rut encontrado en prefs: $rut');
    if (rut == null || rut.isEmpty) {
      debugPrint('🔔 [SOL] ⚠️  RUT vacío — monitor no iniciado');
      return;
    }

    // Ya está corriendo para el mismo rut — no resetear
    if (_solicitudStreamSub != null && _solicitudMonitorRut == rut) {
      debugPrint('🔔 [SOL] ya activo para rut=$rut — sin resetear');
      return;
    }

    _solicitudMonitorRut = rut;
    await _solicitudStreamSub?.cancel();
    _solicitudStreamSub = null;
    _solicitudesAlerteadas
      ..clear()
      ..addAll(await MaterialAlertaEstado.load());
    _solicitudInit = false;

    debugPrint('🔔 [SOL] creando stream para rut=$rut en solicitudes_material_destinatarios');
    _solicitudStreamSub = Supabase.instance.client
        .from('solicitudes_material_destinatarios')
        .stream(primaryKey: ['id'])
        .eq('rut_tecnico', rut)
        .listen(
      (rows) async {
        final pendientes = rows
            .where((r) => r['estado'] == 'pendiente')
            .toList();
        debugPrint('🔔 [SOL] stream disparado → ${pendientes.length} pendientes (${rows.length} total), _solicitudInit=$_solicitudInit');
        if (!_solicitudInit) {
          if (pendientes.isEmpty && rows.isEmpty) return;
          for (final row in pendientes) {
            final sId = row['solicitud_id'] as String?;
            if (sId != null) _solicitudesAlerteadas.add(sId);
          }
          await MaterialAlertaEstado.markAllSeen(_solicitudesAlerteadas);
          _solicitudInit = true;
          debugPrint('🔔 [SOL] carga inicial OK — ${pendientes.length} pendientes marcadas');
          return;
        }
        for (final row in pendientes) {
          final sId = row['solicitud_id'] as String?;
          debugPrint('🔔 [SOL] fila pendiente: solicitud_id=$sId');
          if (sId == null) continue;
          if (_solicitudesAlerteadas.contains(sId)) {
            debugPrint('🔔 [SOL] solicitud $sId ya alerteada, ignorando');
            continue;
          }
          _solicitudesAlerteadas.add(sId);
          solicitudesNotificadas.add(sId);
          await MaterialAlertaEstado.markSeen(sId);
          debugPrint('🔔 [SOL] ✅ nueva solicitud $sId → invoking playAlerta');
          try {
            _soundChannel.invokeMethod<void>('playAlerta');
          } catch (e) {
            debugPrint('🔔 [SOL] ❌ error playAlerta: $e');
          }
        }
      },
      onError: (Object e) {
        debugPrint('🔔 [SOL] ❌ error en stream: $e');
      },
    );
    debugPrint('🔔 [SOL] stream suscrito OK');
  }

  /// Monitor de guías firmadas en `solicitudes_bodega` para el bodeguero.
  /// Suena cuando llega una guía nueva con estado `firmada` (app en primer plano).
  Future<void> initBodegaGuiaMonitor() async {
    debugPrint('📦 [BOD] initBodegaGuiaMonitor');
    if (_bodegaGuiaSub != null) {
      debugPrint('📦 [BOD] ya activo — sin resetear');
      return;
    }

    _guiasBodegaAlerteadas.clear();
    _bodegaGuiaInit = false;

    _bodegaGuiaSub = Supabase.instance.client
        .from('solicitudes_bodega')
        .stream(primaryKey: ['id'])
        .eq('estado', 'firmada')
        .listen(
      (rows) {
        debugPrint('📦 [BOD] stream guías firmadas → ${rows.length} filas');
        if (!_bodegaGuiaInit) {
          for (final row in rows) {
            final id = row['id']?.toString();
            if (id != null) _guiasBodegaAlerteadas.add(id);
          }
          _bodegaGuiaInit = true;
          debugPrint('📦 [BOD] carga inicial — ${rows.length} guías marcadas');
          return;
        }
        for (final row in rows) {
          final id = row['id']?.toString();
          if (id == null || _guiasBodegaAlerteadas.contains(id)) continue;
          _guiasBodegaAlerteadas.add(id);
          debugPrint('📦 [BOD] ✅ guía firmada $id → playAlerta');
          try {
            _soundChannel.invokeMethod<void>('playAlerta');
          } catch (e) {
            debugPrint('📦 [BOD] error playAlerta: $e');
          }
        }
      },
      onError: (Object e) => debugPrint('📦 [BOD] error stream: $e'),
    );
  }

  void detenerBodegaGuiaMonitor() {
    _bodegaGuiaSub?.cancel();
    _bodegaGuiaSub = null;
    _guiasBodegaAlerteadas.clear();
    _bodegaGuiaInit = false;
  }

  // Monitor traspasos pendientes para bodeguero (realtime + sonido).
  StreamSubscription<List<Map<String, dynamic>>>? _bodegaTraspasoSub;
  final Set<String> _traspasosBodegaAlerteados = {};

  // Monitor ayuda en terreno para supervisor (app minimizada, mismo patrón bodeguero)
  StreamSubscription<List<Map<String, dynamic>>>? _supervisorAyudaSub;
  final Set<String> _ayudaTicketsAlerteados = {};
  final Map<String, String> _ayudaEstadosPorTicket = {};
  final Set<String> _ayudaCancelacionesAlerteadas = {};
  bool _supervisorAyudaInit = false;
  String? _supervisorAyudaRut;
  bool _bodegaTraspasoInit = false;

  Future<void> initBodegaTraspasoMonitor() async {
    debugPrint('📦 [BOD] initBodegaTraspasoMonitor');
    if (_bodegaTraspasoSub != null) return;

    _traspasosBodegaAlerteados.clear();
    _bodegaTraspasoInit = false;

    _bodegaTraspasoSub = Supabase.instance.client
        .from('traspasos_bodega')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .listen(
      (rows) {
        if (!_bodegaTraspasoInit) {
          for (final row in rows) {
            final id = row['id']?.toString();
            if (id != null) _traspasosBodegaAlerteados.add(id);
          }
          _bodegaTraspasoInit = true;
          debugPrint('📦 [BOD] traspasos carga inicial ${rows.length}');
          return;
        }
        for (final row in rows) {
          final id = row['id']?.toString();
          final estado = row['estado'] as String? ?? '';
          if (id == null || estado != 'pendiente') continue;
          if (_traspasosBodegaAlerteados.contains(id)) continue;
          _traspasosBodegaAlerteados.add(id);
          debugPrint('📦 [BOD] ✅ traspaso pendiente $id → playAlerta');
          try {
            _soundChannel.invokeMethod<void>('playAlerta');
          } catch (e) {
            debugPrint('📦 [BOD] error playAlerta traspaso: $e');
          }
        }
      },
      onError: (Object e) => debugPrint('📦 [BOD] error stream traspasos: $e'),
    );
  }

  void detenerBodegaTraspasoMonitor() {
    _bodegaTraspasoSub?.cancel();
    _bodegaTraspasoSub = null;
    _traspasosBodegaAlerteados.clear();
    _bodegaTraspasoInit = false;
  }

  /// Stream de ayuda en terreno para supervisor — respaldo cuando Realtime se corta
  /// en segundo plano (mismo patrón que [initBodegaTraspasoMonitor]).
  Future<void> initSupervisorAyudaMonitor() async {
    final rut = await AyudaService.resolverRutSupervisorSesion();
    if (rut.isEmpty) return;
    if (_supervisorAyudaSub != null && _supervisorAyudaRut == rut) return;

    debugPrint('🆘 [SUP] initSupervisorAyudaMonitor rut=$rut');
    await _supervisorAyudaSub?.cancel();
    _supervisorAyudaRut = rut;
    _ayudaTicketsAlerteados.clear();
    _ayudaEstadosPorTicket.clear();
    _ayudaCancelacionesAlerteadas.clear();
    _supervisorAyudaInit = false;

    Set<String> rutsEquipo = {};
    try {
      final lista = await AyudaService().obtenerRutsEquipo(rut);
      rutsEquipo.addAll(lista);
    } catch (e) {
      debugPrint('🆘 [SUP] error cargando equipo: $e');
    }

    bool esParaMi(Map<String, dynamic> row) {
      if ((row['tipo']?.toString() ?? '') == 'movimiento_material') return false;
      if ((row['estado']?.toString() ?? '') != 'pendiente') return false;
      final rutTec = row['rut_tecnico']?.toString() ?? '';
      final rutSup = row['rut_supervisor']?.toString() ?? '';
      if (AyudaService.mismoRut(rutSup, rut)) return true;
      if (rutsEquipo.any((r) => AyudaService.mismoRut(r, rutTec))) return true;
      return rutsEquipo.isEmpty && rutSup.isEmpty;
    }

    bool perteneceAMi(Map<String, dynamic> row) {
      if ((row['tipo']?.toString() ?? '') == 'movimiento_material') return false;
      final rutTec = row['rut_tecnico']?.toString() ?? '';
      final rutSup = row['rut_supervisor']?.toString() ?? '';
      if (AyudaService.mismoRut(rutSup, rut)) return true;
      if (rutsEquipo.any((r) => AyudaService.mismoRut(r, rutTec))) return true;
      return rutsEquipo.isEmpty && rutSup.isEmpty;
    }

    _supervisorAyudaSub = Supabase.instance.client
        .from('ayuda_terreno_crea')
        .stream(primaryKey: ['ticket_id'])
        .order('created_at', ascending: false)
        .listen(
      (rows) async {
        if (!_supervisorAyudaInit) {
          for (final row in rows) {
            final tid = row['ticket_id']?.toString();
            if (tid == null) continue;
            final estado = row['estado']?.toString() ?? '';
            _ayudaEstadosPorTicket[tid] = estado;
            _ayudaTicketsAlerteados.add(tid);
          }
          _supervisorAyudaInit = true;
          debugPrint('🆘 [SUP] ayuda carga inicial ${rows.length}');
          return;
        }
        for (final row in rows) {
          final tid = row['ticket_id']?.toString();
          if (tid == null) continue;
          final estado = row['estado']?.toString() ?? '';
          final prev = _ayudaEstadosPorTicket[tid];
          _ayudaEstadosPorTicket[tid] = estado;

          if (prev != null &&
              prev != 'cancelada' &&
              estado == 'cancelada' &&
              perteneceAMi(row) &&
              !_ayudaCancelacionesAlerteadas.contains(tid)) {
            _ayudaCancelacionesAlerteadas.add(tid);
            final nombre = row['nombre_tecnico']?.toString() ?? 'Técnico';
            final tipo = row['tipo']?.toString() ?? 'ayuda';
            debugPrint('🆘 [SUP] ✅ ayuda cancelada $tid');
            await procesarAyudaCanceladaSilenciosa({
              'ticket_id': tid,
              'body': '$nombre canceló su solicitud — $tipo',
            });
            await MaterialAlertaBackground.mostrar(
              accion: 'ayuda_cancelada',
              title: 'Solicitud de ayuda cancelada',
              body: '$nombre canceló su solicitud — $tipo',
              data: {'accion': 'ayuda_cancelada', 'ticket_id': tid},
            );
            continue;
          }

          final esNuevaPendiente =
              estado == 'pendiente' && prev != 'pendiente';
          if (!esNuevaPendiente || !esParaMi(row)) continue;
          if (_ayudaTicketsAlerteados.contains(tid)) continue;
          _ayudaTicketsAlerteados.add(tid);
          debugPrint('🆘 [SUP] ✅ ayuda $tid → playAyuda');
          try {
            await _soundChannel.invokeMethod<void>('playAyuda');
          } catch (e) {
            debugPrint('🆘 [SUP] error playAyuda: $e');
          }
          final nombre = row['nombre_tecnico']?.toString() ?? 'Técnico';
          final tipo = row['tipo']?.toString() ?? 'ayuda';
          await MaterialAlertaBackground.mostrar(
            accion: 'solicitud_ayuda',
            title: '¡Solicitud de ayuda en terreno!',
            body: '$nombre necesita ayuda — $tipo',
            data: {'accion': 'solicitud_ayuda', 'ticket_id': tid},
          );
        }
      },
      onError: (Object e) => debugPrint('🆘 [SUP] error stream ayuda: $e'),
    );
  }

  void detenerSupervisorAyudaMonitor() {
    _supervisorAyudaSub?.cancel();
    _supervisorAyudaSub = null;
    _ayudaTicketsAlerteados.clear();
    _ayudaEstadosPorTicket.clear();
    _ayudaCancelacionesAlerteadas.clear();
    _supervisorAyudaInit = false;
    _supervisorAyudaRut = null;
  }

  /// Monitor de traspasos via .stream() para técnico A y B.
  /// Muestra snack cuando estado cambia a aprobado (KRP) o sap_ok pasa a true.
  Future<void> initTraspasoMonitor(String rut) async {
    debugPrint('📦 [TRP] initTraspasoMonitor llamado para rut=$rut');

    // Ya está corriendo para el mismo rut — no resetear
    if (_traspasoSubA != null && _traspasoMonitorRut == rut) {
      debugPrint('📦 [TRP] ya activo para rut=$rut — sin resetear');
      return;
    }

    _traspasoMonitorRut = rut;
    await _traspasoSubA?.cancel();
    await _traspasoSubB?.cancel();
    _traspasoEstados.clear();
    _traspasoSapOk.clear();
    _traspasoIdsInit.clear();

    void procesarRows(List<Map<String, dynamic>> rows) {
      debugPrint('📦 [TRP] stream disparado → ${rows.length} filas');
      for (final row in rows) {
        final id = row['id'] as String?;
        if (id == null) continue;
        final estado = row['estado'] as String? ?? 'pendiente';
        final sapOk  = row['sap_ok']  as bool?   ?? false;
        debugPrint('📦 [TRP] fila id=$id estado=$estado sapOk=$sapOk init=${_traspasoIdsInit.contains(id)}');

        if (!_traspasoIdsInit.contains(id)) {
          _traspasoIdsInit.add(id);
          _traspasoEstados[id] = estado;
          _traspasoSapOk[id]   = sapOk;
          debugPrint('📦 [TRP] id=$id registrado (primera vez, sin notificar)');
          continue;
        }

        final estadoPrev = _traspasoEstados[id] ?? 'pendiente';
        final sapOkPrev  = _traspasoSapOk[id]   ?? false;
        debugPrint('📦 [TRP] id=$id cambio: estado $estadoPrev→$estado  sapOk $sapOkPrev→$sapOk');

        if (estadoPrev == 'pendiente' && estado == 'aprobado') {
          debugPrint('📦 [TRP] ✅ KRP aprobado → mostrando snack');
          _mostrarSnackTraspasoAprobado(
            'TRANSFERENCIA EN KRP LISTA, TRANSFERENCIA EN TOA EN PROCESO');
        }
        if (!sapOkPrev && sapOk) {
          debugPrint('📦 [TRP] ✅ SAP confirmado → mostrando snack');
          _mostrarSnackTraspasoAprobado('TRANSFERENCIA EN TOA REALIZADA ✓');
        }

        _traspasoEstados[id] = estado;
        _traspasoSapOk[id]   = sapOk;
      }
    }

    _traspasoSubA = Supabase.instance.client
        .from('traspasos_bodega')
        .stream(primaryKey: ['id'])
        .eq('rut_tecnico_a', rut)
        .listen(
          procesarRows,
          onError: (Object e) => debugPrint('📦 [TRP] ❌ error subA: $e'),
        );

    _traspasoSubB = Supabase.instance.client
        .from('traspasos_bodega')
        .stream(primaryKey: ['id'])
        .eq('rut_tecnico_b', rut)
        .listen(
          procesarRows,
          onError: (Object e) => debugPrint('📦 [TRP] ❌ error subB: $e'),
        );

    debugPrint('📦 [TRP] streams A y B suscritos para rut=$rut');
  }

  /// Monitor de PIN para el solicitante (A).
  /// Usa .stream() sobre el ID de la solicitud — mismo mecanismo que _subPropia,
  /// funciona sin REPLICA IDENTITY FULL y sin que la tabla esté en la publicación.
  Future<void> initPinMonitor(String rut, String solicitudId) async {
    debugPrint('[PIN] initPinMonitor → rut=$rut solicitudId=$solicitudId');
    if (_pinSub != null && _pinMonitorSolicitudId == solicitudId) {
      debugPrint('[PIN] monitor ya activo para $solicitudId');
      return;
    }
    await _pinSub?.cancel();
    _pinSub    = null;
    _pinUltimo = null;
    _pinMonitorSolicitudId = solicitudId;

    _pinSub = Supabase.instance.client
        .from('solicitudes_material')
        .stream(primaryKey: ['id'])
        .eq('id', solicitudId)
        .listen((rows) async {
      debugPrint('[PIN] stream disparado → ${rows.length} filas');
      if (rows.isEmpty) return;
      final raw = rows.first;
      final pin = raw['pin_codigo']?.toString();
      debugPrint('[PIN] pin_codigo=$pin  _pinUltimo=$_pinUltimo');
      if (pin == null || pin.isEmpty) return;
      if (pin == _pinUltimo) return;
      if (await _pinYaMostrado(solicitudId, pin)) return;
      _pinUltimo = pin;
      await _marcarPinMostrado(solicitudId, pin);
      await detenerPinMonitor();
      final ctx = creaboxNavigatorKey.currentContext;
      debugPrint('[PIN] ctx=${ctx != null ? 'disponible' : 'NULL — no se puede mostrar dialog'}');
      if (ctx == null) return;
      debugPrint('[PIN] mostrando dialog con PIN=$pin');
      showPinDialog(ctx, pin);
    });
    debugPrint('[PIN] stream suscrito OK');
  }

  static Future<bool> _pinYaMostrado(String solicitudId, String pin) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$kPrefPinVistoPrefix$solicitudId') == pin;
  }

  static Future<void> _marcarPinMostrado(String solicitudId, String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$kPrefPinVistoPrefix$solicitudId', pin);
  }

  /// Borra deduplicación para que un PIN renovado vuelva a mostrarse al solicitante.
  static Future<void> limpiarPinMostrado(String solicitudId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$kPrefPinVistoPrefix$solicitudId');
    instance._pinUltimo = null;
  }

  /// Muestra el PIN al solicitante (deduplica por sesión y por solicitud).
  static Future<void> showPinDialogIfNeeded(
    BuildContext ctx,
    String pin, {
    String? solicitudId,
  }) async {
    if (pin.isEmpty) return;
    if (pin == instance._pinUltimo) return;
    if (solicitudId != null && await _pinYaMostrado(solicitudId, pin)) return;
    instance._pinUltimo = pin;
    if (solicitudId != null) await _marcarPinMostrado(solicitudId, pin);
    unawaited(instance.detenerPinMonitor());
    showPinDialog(ctx, pin);
  }

  static void showPinDialog(BuildContext ctx, String pin) {
    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF112240),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.lock_open, color: Color(0xFF00D4AA), size: 22),
            SizedBox(width: 8),
            Text('Tu PIN de confirmación',
                style: TextStyle(color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Díselo al técnico que te entregó el material:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Text(
              pin,
              style: const TextStyle(
                color: Color(0xFF00D4AA),
                fontSize: 48,
                fontWeight: FontWeight.bold,
                letterSpacing: 10,
              ),
            ),
            const SizedBox(height: 8),
            const Text('Válido por 15 minutos',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              unawaited(_irAHomeTrasPin());
            },
            child: const Text('Entendido',
                style: TextStyle(color: Color(0xFF00D4AA))),
          ),
        ],
      ),
    );
  }

  static Future<void> _irAHomeTrasPin() async {
    await instance.detenerPinMonitor();
    final nav = creaboxNavigatorKey.currentState;
    if (nav != null) {
      nav.pushNamedAndRemoveUntil('/home', (route) => false);
    }
  }

  static Future<void> procesarSolicitudAtendidaSilenciosa(
    Map<String, dynamic> data,
  ) async {
    final sid = data['solicitud_id']?.toString();
    if (sid == null || sid.isEmpty) return;

    solicitudesNotificadas.remove(sid);
    await MaterialAlertaEstado.unmarkSeen(sid);
    await cancelMaterialNotificacion();

    final opened = await MaterialAlertaEstado.wasOpened(sid);
    await MaterialAlertaEstado.clearOpened(sid);
    if (opened) {
      final ctx = creaboxNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        _mostrarSnackSolicitudAtendida(
          ctx,
          data['body']?.toString() ??
              data['descripcion']?.toString() ??
              'La solicitud ya fue atendida',
        );
      }
    }
  }

  static void _mostrarSnackSolicitudAtendida(BuildContext ctx, String msg) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFF59E0B),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        margin: const EdgeInsets.all(12),
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(msg,
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  /// Aviso al supervisor cuando el técnico cancela ayuda en terreno.
  static Future<void> procesarAyudaCanceladaSilenciosa(
    Map<String, dynamic> data,
  ) async {
    await instance._initLocalNotifications();
    final tid = data['ticket_id']?.toString();
    if (tid != null && tid.isNotEmpty) {
      await _flnp.cancel(48);
      await _flnp.cancel(1001);
    }

    final ctx = creaboxNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;

    final msg = data['body']?.toString() ??
        data['descripcion']?.toString() ??
        'Un técnico canceló su solicitud de ayuda';

    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        margin: const EdgeInsets.all(12),
        content: Row(
          children: [
            const Icon(Icons.cancel_outlined, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(msg,
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  /// Cierra alertas y muestra aviso cuando una transacción de material fue cancelada.
  static Future<void> procesarSolicitudCanceladaSilenciosa(
    Map<String, dynamic> data,
  ) async {
    final sid = data['solicitud_id']?.toString();
    if (sid != null && sid.isNotEmpty) {
      solicitudesNotificadas.remove(sid);
      await MaterialAlertaEstado.unmarkSeen(sid);
    }
    await cancelMaterialNotificacion();
    await instance.detenerPinMonitor();

    final ctx = creaboxNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;

    final msg = data['body']?.toString() ??
        data['descripcion']?.toString() ??
        'La transacción de material fue cancelada';

    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        margin: const EdgeInsets.all(12),
        content: Row(
          children: [
            const Icon(Icons.cancel_outlined, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(msg,
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  /// Toca el sonido de alerta de material. Llamable desde cualquier parte de la app.
  static Future<void> playAlerta() async {
    try {
      await _soundChannel.invokeMethod<void>('playAlerta');
    } catch (e) {
      debugPrint('[FCM] playAlerta: $e');
    }
  }

  static Future<void> stopAlerta() async {
    try {
      await _soundChannel.invokeMethod<void>('stopAlerta');
    } catch (e) {
      debugPrint('[FCM] stopAlerta: $e');
    }
  }

  /// Detiene el sonido y cancela la notificación local de solicitud de material.
  static Future<void> cancelMaterialNotificacion() async {
    await stopAlerta();
    try {
      await _soundChannel.invokeMethod<void>('cancelMaterialNotificacion');
    } catch (e) {
      debugPrint('[FCM] cancelMaterialNotificacion nativo: $e');
    }
    try {
      await instance._initLocalNotifications();
      await _flnp.cancel(42);
    } catch (e) {
      // En release con R8, flutter_local_notifications puede fallar; el nativo ya canceló.
      debugPrint('[FCM] cancelMaterialNotificacion flnp: $e');
    }
  }

  /// Toca el sonido de ayuda en terreno (supervisor recibe solicitud / técnico ve que llegó).
  static Future<void> playAyuda() async {
    try {
      await _soundChannel.invokeMethod<void>('playAyuda');
    } catch (e) {
      debugPrint('[FCM] playAyuda: $e');
    }
  }

  /// Toca el sonido de llegada de material (el que esperó escucha que el otro ya llegó).
  static Future<void> playMaterialLlegada() async {
    try {
      await _soundChannel.invokeMethod<void>('playMaterialLlegada');
    } catch (e) {
      debugPrint('[FCM] playMaterialLlegada: $e');
    }
  }

  /// Sonido de hongo para comunicados CREABOX.
  static Future<void> playComunicado() async {
    try {
      await _soundChannel.invokeMethod<void>('playComunicado');
    } catch (e) {
      debugPrint('[FCM] playComunicado: $e');
    }
  }

  void _mostrarSnackTraspasoAprobado(String mensaje) {
    final ctx = creaboxNavigatorKey.currentContext;
    if (ctx == null) return;
    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: const Color(0xFF0D1B2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF22C55E), size: 48),
            ),
            const SizedBox(height: 16),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22C55E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.of(dialogContext, rootNavigator: true).pop(),
                child: const Text('OK',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// Detiene el monitor de PIN (cuando ya no hay solicitud activa).
  Future<void> detenerPinMonitor() async {
    await _pinSub?.cancel();
    _pinSub    = null;
    _pinUltimo = null;
    _pinMonitorSolicitudId = null;
  }

  Future<void> _solicitarExencionBateria() async {
    try {
      final ignorado =
          await _soundChannel.invokeMethod<bool>('isBatteryOptimizationIgnored') ?? false;
      if (!ignorado) {
        await _soundChannel.invokeMethod<void>('requestIgnoreBatteryOptimizations');
      }
    } catch (_) {}
  }

  /// Limpia flags FCM obsoletos al volver a primer plano (sin repetir sonido).
  Future<void> onAppResumed() async {
    try {
      unawaited(syncFcmTokenDispositivo());
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(kPrefSolicitudMaterialPendiente) == 'true') {
        await prefs.remove(kPrefSolicitudMaterialPendiente);
        debugPrint('[FCM] onAppResumed → flag material limpiado (sin re-sonar)');
      }
      if (prefs.getString(kPrefGuiaBodegaPendiente) == 'true') {
        await prefs.remove(kPrefGuiaBodegaPendiente);
        debugPrint('[FCM] onAppResumed → flag guía bodega limpiado');
      }
      await processPendingNavigation();
      await processPendingPin();
      await ComunicadoService.instance.processPendingComunicado();
    } catch (e) {
      debugPrint('[FCM] onAppResumed error: $e');
    }
  }

  /// Navega según la acción del push (tap en notificación).
  Future<void> handleNotificationOpen(Map<String, dynamic> data) async {
    final accion = data['accion']?.toString() ?? '';

    if (accion == 'pin_intercambio') {
      final pin = data['pin']?.toString();
      final sid = data['solicitud_id']?.toString();
      if (pin != null && pin.isNotEmpty) {
        _pinUltimo = pin;
        final ctx = creaboxNavigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          await showPinDialogIfNeeded(ctx, pin, solicitudId: sid);
        } else {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(kPrefPendingPin, pin);
          if (sid != null) await _marcarPinMostrado(sid, pin);
        }
      }
      await _navegarARuta('/solicitud-material');
      return;
    }

    if (accion == 'solicitud_material') {
      final sid = data['solicitud_id']?.toString();
      if (sid != null && sid.isNotEmpty) {
        await MaterialAlertaEstado.markOpened(sid);
      }
      await _navegarARuta('/solicitud-material');
    } else if (accion == 'material_sin_respuesta') {
      await _navegarARuta('/solicitudes-material-supervisor');
    } else if (accion == 'solicitud_ayuda' || accion == 'ayuda_cancelada') {
      await _navegarARuta('/solicitudes-ayuda');
    } else if (accion == 'solicitud_cancelada') {
      await _navegarARuta('/solicitud-material');
    } else if (accion == 'guia_emitida') {
      await _navegarARuta('/solicitud-material');
    } else if (accion == 'guia_firmada_bodega' || accion == 'traspaso_bodega') {
      await _navegarARuta('/bodega');
    } else if (accion == 'comunicado_creabox') {
      await ComunicadoService.instance.mostrarInmediato(
        comunicadoId: data['comunicado_id']?.toString(),
        reproducirSonido: true,
      );
    }
  }

  Future<void> _navegarARuta(String route) async {
    final ctx = creaboxNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kPrefPendingRoute, route);
      debugPrint('[FCM] ruta pendiente guardada: $route');
      return;
    }
    debugPrint('[FCM] navegando a $route');
    Navigator.of(ctx).pushNamed(route);
  }

  Future<void> processPendingNavigation() async {
    final prefs = await SharedPreferences.getInstance();
    final route = prefs.getString(kPrefPendingRoute);
    if (route == null || route.isEmpty) return;
    await prefs.remove(kPrefPendingRoute);
    await _navegarARuta(route);
  }

  Future<void> processPendingPin([BuildContext? context]) async {
    final prefs = await SharedPreferences.getInstance();
    final pin = prefs.getString(kPrefPendingPin);
    if (pin == null || pin.isEmpty) return;
    await prefs.remove(kPrefPendingPin);
    final ctx = context ?? creaboxNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      await showPinDialogIfNeeded(ctx, pin);
    } else {
      await prefs.setString(kPrefPendingPin, pin);
    }
  }

  Future<void> _initLocalNotifications() async {
    if (_flnpInit) return;
    await _flnp.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final data = jsonDecode(payload) as Map<String, dynamic>;
          unawaited(handleNotificationOpen(data));
        } catch (e) {
          debugPrint('[FCM] payload notif inválido: $e');
        }
      },
    );
    _flnpInit = true;
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await _initLocalNotifications();

    _navChannel.setMethodCallHandler((call) async {
      if (call.method == 'openComunicado') {
        final args = call.arguments;
        if (args is Map) {
          final id = args['comunicado_id']?.toString();
          unawaited(ComunicadoService.instance.mostrarInmediato(
            comunicadoId: (id != null && id.isNotEmpty) ? id : null,
            reproducirSonido: true,
          ));
        }
      } else if (call.method == 'openRoute') {
        final args = call.arguments;
        if (args is Map) {
          final route = args['route']?.toString();
          final sid = args['solicitud_id']?.toString();
          if (sid != null && sid.isNotEmpty) {
            await MaterialAlertaEstado.markOpened(sid);
          }
          if (route != null && route.isNotEmpty) {
            await _navegarARuta(route);
          }
        } else {
          final route = args as String?;
          if (route != null && route.isNotEmpty) {
            await _navegarARuta(route);
          }
        }
      }
    });

    // El canal mat_alertas_7 lo crea CreaboxApplication.kt con USAGE_ALARM.
    // No se recrea desde Dart para evitar race condition que congele el canal
    // sin USAGE_ALARM (Android congela propiedades en la primera creación).

    // Permisos (Android 13+).
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Exención de battery optimization — necesario en OEMs agresivos (Xiaomi,
    // Samsung, Huawei) para que FCM llegue cuando la app está en background.
    unawaited(_solicitarExencionBateria());

    // Foreground.
    FirebaseMessaging.onMessage.listen(_onForeground);

    // Tap sobre la notificación cuando la app estaba en background.
    FirebaseMessaging.onMessageOpenedApp.listen(_onOpened);

    // Mensaje inicial (app abierta desde tap, estado terminated).
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      await _onOpened(initial);
    }

    // Re-registrar el token si Firebase lo rota (reinstalación, restore de
    // backup, expiración, etc).
    FirebaseMessaging.instance.onTokenRefresh.listen((nuevoToken) {
      debugPrint('==== FCM TOKEN REFRESCADO: $nuevoToken ====');
      unawaited(_registrarTokenConRutDePrefs(nuevoToken));
    });

    // Sincroniza token en Supabase (técnico / bodega / flota) en cada arranque.
    unawaited(_registrarTokenActualSiHayRut());
  }

  Future<void> _onForeground(RemoteMessage m) async {
    debugPrint('[FCM] foreground: ${m.data}');

    if (m.data['accion'] == 'pin_intercambio') {
      debugPrint('[PIN] FCM foreground → pin_intercambio recibido');
      final pin = m.data['pin']?.toString();
      final sid = m.data['solicitud_id']?.toString();
      debugPrint('[PIN] FCM pin=$pin  _pinUltimo=$_pinUltimo');
      if (pin != null && pin.isNotEmpty && pin != _pinUltimo) {
        final ctx = creaboxNavigatorKey.currentContext;
        debugPrint('[PIN] FCM ctx=${ctx != null ? 'disponible' : 'NULL'}');
        if (ctx != null) {
          await showPinDialogIfNeeded(ctx, pin, solicitudId: sid);
        }
      }
    }

    if (m.data['accion'] == 'solicitud_atendida') {
      await procesarSolicitudAtendidaSilenciosa(m.data);
    }

    if (m.data['accion'] == 'solicitud_cancelada') {
      await procesarSolicitudCanceladaSilenciosa(m.data);
    }

    if (m.data['accion'] == 'ayuda_cancelada') {
      await procesarAyudaCanceladaSilenciosa(m.data);
      await MaterialAlertaBackground.mostrarDesdeFcm(m.data);
    }

    await _aplicarAccion(m.data);
    await _sincronizarSupabase(m.data);
    await _alertaProvider?.refrescar();
    if (m.data['accion'] == 'solicitud_material' ||
        m.data['accion'] == 'guia_firmada_bodega' ||
        m.data['accion'] == 'traspaso_bodega') {
      try { await _soundChannel.invokeMethod<void>('playAlerta'); } catch (_) {}
    }
    if (m.data['accion'] == 'sol_comb_flota' || m.data['accion'] == 'sol_comb_jefe_ops') {
      try { await _soundChannel.invokeMethod<void>('playAlerta'); } catch (_) {}
    }
    if (m.data['accion'] == 'material_sin_respuesta' ||
        m.data['accion'] == 'solicitud_ayuda') {
      try { await _soundChannel.invokeMethod<void>('playAyuda'); } catch (_) {}
    }
    if (m.data['accion'] == 'traspaso_aprobado') {
      _mostrarSnackTraspasoAprobado(m.data['descripcion']?.toString() ?? 'Traspaso aprobado por bodega');
    }
    if (m.data['accion'] == 'krp_aprobado') {
      _mostrarSnackTraspasoAprobado(m.data['descripcion']?.toString() ?? 'TRANSFERENCIA EN KRP LISTA, TRANSFERENCIA EN TOA EN PROCESO');
    }
    if (m.data['accion'] == 'sap_confirmado') {
      _mostrarSnackTraspasoAprobado(m.data['descripcion']?.toString() ?? 'TRANSFERENCIA EN TOA REALIZADA ✓');
    }
    if (m.data['accion'] == 'guia_emitida') {
      final ctx = creaboxNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          backgroundColor: const Color(0xFF22C55E),
          content: Text(
            m.data['body']?.toString() ??
                'Guía de entrega disponible en Ayuda de material',
          ),
        ));
      }
    }

    if (m.data['accion'] == 'comunicado_creabox') {
      unawaited(FcmService.playComunicado());
      unawaited(ComunicadoService.instance.mostrarInmediato(
        comunicadoId: m.data['comunicado_id']?.toString(),
      ));
    }

    // No llamar _mostrarNotificacionLocal en foreground: el sistema FCM ya mostró
    // la notificación (notification+data). playAlerta/snack ya manejan el feedback.
  }

  Future<void> _onOpened(RemoteMessage m) async {
    debugPrint('[FCM] opened: ${m.data}');
    await _aplicarAccion(m.data);
    await handleNotificationOpen(m.data);
    await _sincronizarSupabase(m.data);
    await _alertaProvider?.refrescar();
  }

  /// Sincroniza el estado del bloqueo en la tabla `alertas_fcm` de Supabase.
  /// Solo se llama desde foreground/opened (donde Supabase ya está inicializado).
  Future<void> _sincronizarSupabase(Map<String, dynamic> data) async {
    final accion = data['accion']?.toString();
    if (accion == null) return;
    final prefs = await SharedPreferences.getInstance();
    final rut = prefs.getString('rut_tecnico') ??
        prefs.getString('user_rut') ??
        prefs.getString('rut');
    if (rut == null || rut.isEmpty) return;
    try {
      final db = Supabase.instance.client;
      if (accion == 'bloquear_card') {
        await db.from('alertas_fcm').upsert({
          'rut_tecnico':  rut,
          'activa':       true,
          'tipo':         data['tipo']?.toString(),
          'descripcion':  data['descripcion']?.toString(),
          'card_id':      data['card_id']?.toString() ?? 'mis_actividades',
          'bloqueado_en': DateTime.now().toIso8601String(),
          'resuelto_en':  null,
          'resuelto_por': null,
          'updated_at':   DateTime.now().toIso8601String(),
        }, onConflict: 'rut_tecnico');
      } else if (accion == 'desbloquear_card') {
        await db.from('alertas_fcm').upsert({
          'rut_tecnico':  rut,
          'activa':       false,
          'resuelto_en':  DateTime.now().toIso8601String(),
          'resuelto_por': 'fcm',
          'updated_at':   DateTime.now().toIso8601String(),
        }, onConflict: 'rut_tecnico');
      }
      debugPrint('[FCM] alertas_fcm sincronizado: $accion para $rut');
    } catch (e) {
      debugPrint('[FCM] error sincronizando alertas_fcm: $e');
    }
  }

  /// Obtiene el token FCM actual del dispositivo (puede tardar unos segundos
  /// la primera vez).
  Future<String?> getToken() async {
    return FirebaseMessaging.instance.getToken();
  }

  /// Registra (o re-registra) el token contra Kepler.
  /// Solo hace POST si el token cambió respecto al guardado en
  /// SharedPreferences (`fcm_token_registrado`).
  ///
  /// Devuelve `true` si el registro tuvo éxito o no hizo falta (token igual),
  /// `false` si la llamada HTTP falló.
  Future<bool> registrarTokenSiCambio({required String rut}) async {
    final token = await getToken();
    if (token == null || token.isEmpty) return false;

    await _syncFcmTokenEnSupabase(rut: rut, token: token);

    final prefs = await SharedPreferences.getInstance();
    final anterior = prefs.getString(kPrefFcmTokenRegistrado);
    if (anterior == token) {
      debugPrint('[FCM] token sin cambios en Kepler, no se reenvía');
      return true;
    }

    final ok = await _postToken(token: token, rut: rut);
    if (ok) {
      await prefs.setString(kPrefFcmTokenRegistrado, token);
      debugPrint('[FCM] token registrado en Kepler');
    }
    return ok;
  }

  /// Variante de `registrarTokenSiCambio` que toma el RUT desde
  /// `SharedPreferences` en lugar de recibirlo por parámetro. Pensada para
  /// los flujos automáticos (refresh de token y arranque): si todavía no hay
  /// RUT guardado (primera apertura antes del login), no hace nada — el
  /// registro lo cubrirá `registro_rut_screen.dart` cuando el usuario
  /// confirme su RUT.
  Future<void> _registrarTokenActualSiHayRut() async {
    final token = await getToken();
    if (token == null || token.isEmpty) {
      debugPrint('==== FCM TOKEN: (vacío, Firebase aún no entregó token) ====');
      return;
    }
    debugPrint('==== FCM TOKEN: $token ====');
    await _registrarTokenConRutDePrefs(token);
  }

  Future<void> _registrarTokenConRutDePrefs(String token) async {
    final prefs = await SharedPreferences.getInstance();
    final rut = prefs.getString('rut_tecnico') ??
        prefs.getString('user_rut') ??
        prefs.getString('rut');
    if (rut == null || rut.isEmpty) {
      debugPrint('[FCM] sin RUT en prefs, registro diferido al login');
      return;
    }

    await _syncFcmTokenEnSupabase(rut: rut, token: token);

    // Registrar en Kepler (best-effort, solo si cambió)
    final anterior = prefs.getString(kPrefFcmTokenRegistrado);
    if (anterior == token) {
      debugPrint('[FCM] token sin cambios en Kepler, no se reenvía');
      return;
    }
    final ok = await _postToken(token: token, rut: rut);
    if (ok) {
      await prefs.setString(kPrefFcmTokenRegistrado, token);
      debugPrint('[FCM] token registrado en Kepler');
    }
  }

  /// Sincroniza el token FCM del celular en Supabase para cualquier rol
  /// (técnico, bodeguero, flota). Silencioso — se llama en cada arranque.
  Future<void> syncFcmTokenDispositivo() async {
    final token = await getToken();
    if (token == null || token.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final rut = prefs.getString('rut_tecnico') ??
        prefs.getString('user_rut') ??
        prefs.getString('rut');
    if (rut == null || rut.isEmpty) return;
    await _syncFcmTokenEnSupabase(rut: rut, token: token);
  }

  /// Alias histórico — mismo comportamiento que [syncFcmTokenDispositivo].
  Future<void> registrarTokenBodeguero() => syncFcmTokenDispositivo();

  Future<void> _syncFcmTokenEnSupabase({
    required String rut,
    required String token,
  }) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'registrar-fcm-dispositivo',
        body: {'rut': rut, 'fcm_token': token},
      );
      return;
    } catch (_) {
      // Edge no desplegada aún — fallback directo (puede fallar por RLS)
    }

    final variantes = {
      rut,
      LogisticaService.canonicalRut(rut),
      LogisticaService.canonicalRut(rut).replaceAll('-', ''),
    }.where((s) => s.isNotEmpty).toList();

    for (final table in [
      'nomina_tecnicos',
      'nomina_bodega',
      'roles_flota',
      'supervisores_crea',
    ]) {
      try {
        final rows = await Supabase.instance.client
            .from(table)
            .select('rut')
            .inFilter('rut', variantes);
        for (final row in rows as List) {
          final dbRut = (row as Map)['rut']?.toString();
          if (dbRut == null || dbRut.isEmpty) continue;
          await Supabase.instance.client
              .from(table)
              .update({'fcm_token': token})
              .eq('rut', dbRut);
        }
      } catch (_) {}
    }
  }

  Future<bool> _postToken({required String token, required String rut}) async {
    final basicAuth =
        base64.encode(utf8.encode('$kKeplerUser:$kKeplerPassword'));
    try {
      final r = await http
          .post(
            Uri.parse('$kKeplerBaseUrl$kKeplerRegisterTokenPath'),
            headers: {
              'Authorization': 'Basic $basicAuth',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'fcm_token': token,
              'rut': rut,
              'platform': kFcmPlatform,
            }),
          )
          .timeout(const Duration(seconds: 15));
      debugPrint('[FCM] register-token: ${r.statusCode}');
      return r.statusCode >= 200 && r.statusCode < 300;
    } catch (e) {
      debugPrint('[FCM] register-token failed: $e');
      return false;
    }
  }
}

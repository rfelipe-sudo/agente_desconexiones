import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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

/// Handler de mensajes FCM cuando la app está en **background o terminated**.
/// La notificación ya la muestra el sistema operativo (notification+data FCM).
/// Aquí solo persiste la acción en SharedPreferences.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await _aplicarAccion(message.data);
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
  if (!esMaterial && !esCancelacion) return;

  final flnp = FlutterLocalNotificationsPlugin();
  await flnp.initialize(const InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  ));

  // Garantizar que el canal existe con el sonido correcto.
  // deleteNotificationChannel + create es la única forma de forzar la
  // actualización si el canal fue creado previamente sin sonido.
  final androidPlugin = flnp.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.deleteNotificationChannel('mat_alertas_3');
  await androidPlugin?.createNotificationChannel(AndroidNotificationChannel(
    'mat_alertas_3',
    'Alertas de material',
    description: 'Alertas de solicitudes de material entre técnicos',
    importance: Importance.high,
    sound: const RawResourceAndroidNotificationSound('alerta_urgente'),
    playSound: true,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 300, 200, 300]),
  ));

  final title = esMaterial
      ? (data['title']?.toString() ?? '¡Solicitud de material!')
      : 'Solicitud cancelada';
  final body = data['body']?.toString()
      ?? data['descripcion']?.toString()
      ?? (esMaterial ? 'Un colega necesita material' : 'La solicitud fue cancelada');

  // Reemplaza la notificación 42 (nueva solicitud → cancelada, o nueva solicitud).
  final androidDetails = AndroidNotificationDetails(
    'mat_alertas_3',
    'Alertas de material',
    channelDescription: 'Alertas de solicitudes de material entre técnicos',
    importance: Importance.high,
    priority: Priority.high,
    sound: const RawResourceAndroidNotificationSound('alerta_urgente'),
    playSound: esMaterial, // sin alarma para el aviso de cancelación
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 300, 200, 300]),
  );

  await flnp.show(42, title, body, NotificationDetails(android: androidDetails));
}

/// Clave SharedPreferences que indica que hay una solicitud de material pendiente.
const String kPrefSolicitudMaterialPendiente = 'solicitud_material_pendiente';

/// Aplica la acción de un mensaje FCM al SharedPreferences.
/// Acciones soportadas:
/// - `bloquear_card`      → activar bloqueo "Mis Actividades"
/// - `desbloquear_card`   → resolver bloqueo
/// - `solicitud_material` → marcar solicitud de material pendiente
Future<void> _aplicarAccion(Map<String, dynamic> data) async {
  final accion = data['accion']?.toString();
  if (accion == null || accion.isEmpty) return;
  final prefs = await SharedPreferences.getInstance();
  if (accion == 'bloquear_card') {
    await prefs.setString(kPrefAlertaBloqueoMisActividades, 'true');
  } else if (accion == 'desbloquear_card') {
    await prefs.setString(kPrefAlertaBloqueoMisActividades, 'false');
  } else if (accion == 'solicitud_material') {
    // Marca que hay una solicitud de material para mostrar al abrir la app
    await prefs.setString(kPrefSolicitudMaterialPendiente, 'true');
  }
}

class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  static const _soundChannel = MethodChannel(
    'com.creacionestecnologicas.agente_desconexiones/sound',
  );

  /// IDs de solicitudes ya sonadas — compartido con SolicitudMaterialScreen
  /// para evitar que el stream de la pantalla vuelva a sonar si ya sonó aquí.
  static final Set<String> solicitudesNotificadas = {};

  StreamSubscription<List<Map<String, dynamic>>>? _pinSub;
  String? _pinUltimo;

  AlertaProvider? _alertaProvider;
  bool _initialized = false;

  // Monitor de solicitudes de material (stream, igual que PIN monitor)
  StreamSubscription<List<Map<String, dynamic>>>? _solicitudStreamSub;
  final Set<String> _solicitudesAlerteadas = {};
  bool _solicitudInit = false;
  String? _solicitudMonitorRut;

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
    _solicitudesAlerteadas.clear();
    _solicitudInit = false;

    debugPrint('🔔 [SOL] creando stream para rut=$rut en solicitudes_material_destinatarios');
    _solicitudStreamSub = Supabase.instance.client
        .from('solicitudes_material_destinatarios')
        .stream(primaryKey: ['id'])
        .eq('rut_tecnico', rut)
        .listen(
      (rows) {
        debugPrint('🔔 [SOL] stream disparado → ${rows.length} filas, _solicitudInit=$_solicitudInit');
        if (!_solicitudInit) {
          for (final row in rows) {
            final sId = row['solicitud_id'] as String?;
            if (sId != null) _solicitudesAlerteadas.add(sId);
          }
          _solicitudInit = true;
          debugPrint('🔔 [SOL] carga inicial OK — ${rows.length} solicitudes marcadas como vistas');
          return;
        }
        for (final row in rows) {
          final sId    = row['solicitud_id'] as String?;
          final estado = row['estado'] as String? ?? '';
          debugPrint('🔔 [SOL] fila: solicitud_id=$sId estado=$estado');
          if (sId == null || estado != 'pendiente') continue;
          if (_solicitudesAlerteadas.contains(sId)) {
            debugPrint('🔔 [SOL] solicitud $sId ya alerteada, ignorando');
            continue;
          }
          _solicitudesAlerteadas.add(sId);
          solicitudesNotificadas.add(sId);
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
    await _pinSub?.cancel();
    _pinSub    = null;
    _pinUltimo = null;

    _pinSub = Supabase.instance.client
        .from('solicitudes_material')
        .stream(primaryKey: ['id'])
        .eq('id', solicitudId)
        .listen((rows) {
      debugPrint('[PIN] stream disparado → ${rows.length} filas');
      if (rows.isEmpty) return;
      final raw = rows.first;
      debugPrint('[PIN] row keys: ${raw.keys.toList()}');
      final pin = raw['pin_codigo']?.toString();
      debugPrint('[PIN] pin_codigo=$pin  _pinUltimo=$_pinUltimo');
      if (pin == null || pin.isEmpty) return;
      if (pin == _pinUltimo) return;
      _pinUltimo = pin;
      final ctx = creaboxNavigatorKey.currentContext;
      debugPrint('[PIN] ctx=${ctx != null ? 'disponible' : 'NULL — no se puede mostrar dialog'}');
      if (ctx == null) return;
      debugPrint('[PIN] mostrando dialog con PIN=$pin');
      _mostrarDialogPin(ctx, pin);
    });
    debugPrint('[PIN] stream suscrito OK');
  }

  static void _mostrarDialogPin(BuildContext ctx, String pin) {
    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
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
            const Text('Válido por 3 minutos',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Entendido',
                style: TextStyle(color: Color(0xFF00D4AA))),
          ),
        ],
      ),
    );
  }

  void _mostrarSnackTraspasoAprobado(String mensaje) {
    final ctx = creaboxNavigatorKey.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      backgroundColor: const Color(0xFF22C55E),
      duration: const Duration(seconds: 5),
      content: Row(children: [
        const Icon(Icons.check_circle_outline, color: Colors.white),
        const SizedBox(width: 8),
        Expanded(child: Text(mensaje,
            style: const TextStyle(color: Colors.white, fontSize: 13))),
      ]),
    ));
  }

  /// Detiene el monitor de PIN (cuando ya no hay solicitud activa).
  Future<void> detenerPinMonitor() async {
    await _pinSub?.cancel();
    _pinSub    = null;
    _pinUltimo = null;
  }

  /// Configura todos los handlers de FCM.
  /// Llamar desde main.dart **después** de `Firebase.initializeApp()`.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Permisos (Android 13+).
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

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
      _registrarTokenConRutDePrefs(nuevoToken);
    });

    // Registrar también el token actual al arrancar. Cubre el caso de que el
    // token haya cambiado mientras la app estaba cerrada (ej. tras reinstalar)
    // sin que aún haya pasado por la pantalla de login. Fire-and-forget para
    // no bloquear el arranque.
    unawaited(_registrarTokenActualSiHayRut());
  }

  Future<void> _onForeground(RemoteMessage m) async {
    debugPrint('[FCM] foreground: ${m.data}');

    // Mostrar PIN antes de cualquier await — el contexto debe capturarse
    // de forma sincrónica para evitar uso de BuildContext tras gap async.
    if (m.data['accion'] == 'pin_intercambio') {
      debugPrint('[PIN] FCM foreground → pin_intercambio recibido');
      debugPrint('[PIN] FCM data: ${m.data}');
      final pin = m.data['pin']?.toString();
      debugPrint('[PIN] FCM pin=$pin  _pinUltimo=$_pinUltimo');
      if (pin != null && pin.isNotEmpty && pin != _pinUltimo) {
        _pinUltimo = pin;
        final ctx = creaboxNavigatorKey.currentContext;
        debugPrint('[PIN] FCM ctx=${ctx != null ? 'disponible' : 'NULL'}');
        if (ctx != null) _mostrarDialogPin(ctx, pin);
      }
    }

    await _aplicarAccion(m.data);
    await _sincronizarSupabase(m.data);
    await _alertaProvider?.refrescar();
    if (m.data['accion'] == 'solicitud_material') {
      try { await _soundChannel.invokeMethod<void>('playAlerta'); } catch (_) {}
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
    await _mostrarNotificacionLocal(m.data);
  }

  Future<void> _onOpened(RemoteMessage m) async {
    debugPrint('[FCM] opened: ${m.data}');
    await _aplicarAccion(m.data);
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

    // Guardar en Supabase siempre — edge functions necesitan este token
    try {
      await Supabase.instance.client
          .from('nomina_tecnicos')
          .update({'fcm_token': token})
          .eq('rut', rut);
      debugPrint('[FCM] token guardado en nomina_tecnicos (registrarTokenSiCambio)');
    } catch (e) {
      debugPrint('[FCM] error guardando token en Supabase: $e');
    }

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

    // Guardar en Supabase siempre — edge functions necesitan este token
    // independiente de si Kepler acepta el registro
    try {
      await Supabase.instance.client
          .from('nomina_tecnicos')
          .update({'fcm_token': token})
          .eq('rut', rut);
      debugPrint('[FCM] token guardado en nomina_tecnicos');
    } catch (e) {
      debugPrint('[FCM] no se pudo guardar token en Supabase: $e');
    }

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

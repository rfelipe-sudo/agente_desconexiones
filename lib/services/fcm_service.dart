import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agente_desconexiones/config/constants.dart';
import 'package:agente_desconexiones/providers/alerta_provider.dart';

/// Handler de mensajes FCM cuando la app está en **background o terminated**.
/// Debe ser top-level y annotated con `@pragma('vm:entry-point')`.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // En background no tenemos provider; persistimos directamente.
  await _aplicarAccion(message.data);
}

/// Aplica la acción de un mensaje FCM al SharedPreferences.
/// Acciones soportadas:
/// - `bloquear_card`   → activar bloqueo "Mis Actividades"
/// - `desbloquear_card` → resolver bloqueo
Future<void> _aplicarAccion(Map<String, dynamic> data) async {
  final accion = data['accion']?.toString();
  if (accion == null || accion.isEmpty) return;
  final prefs = await SharedPreferences.getInstance();
  if (accion == 'bloquear_card') {
    await prefs.setString(kPrefAlertaBloqueoMisActividades, 'true');
  } else if (accion == 'desbloquear_card') {
    await prefs.setString(kPrefAlertaBloqueoMisActividades, 'false');
  }
}

class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  AlertaProvider? _alertaProvider;
  bool _initialized = false;

  /// Conecta el provider para que los handlers en foreground puedan
  /// notificar cambios a la UI sin esperar a un refresh manual.
  void setAlertaProvider(AlertaProvider provider) {
    _alertaProvider = provider;
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
    await _aplicarAccion(m.data);
    await _alertaProvider?.refrescar();
  }

  Future<void> _onOpened(RemoteMessage m) async {
    debugPrint('[FCM] opened: ${m.data}');
    await _aplicarAccion(m.data);
    await _alertaProvider?.refrescar();
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

    final prefs = await SharedPreferences.getInstance();
    final anterior = prefs.getString(kPrefFcmTokenRegistrado);
    if (anterior == token) {
      debugPrint('[FCM] token sin cambios, no se reenvía');
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
    final anterior = prefs.getString(kPrefFcmTokenRegistrado);
    if (anterior == token) {
      debugPrint('[FCM] token sin cambios, no se reenvía');
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

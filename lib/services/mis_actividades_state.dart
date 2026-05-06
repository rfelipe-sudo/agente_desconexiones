import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Singleton que mantiene vivo el `WebViewController` de la pantalla
/// "Mis Actividades" para que cuando el técnico salga a otra herramienta
/// y vuelva, conserve el estado: cookies, página actual, scroll, formularios.
///
/// **Trade-off**: el WebView usa ~80–150 MB de RAM mientras está vivo.
/// Si en celus low-end el sistema mata la app, retroceder al modo
/// "recordar URL" y aceptar que se vuelva a hacer login al volver.
class MisActividadesState extends ChangeNotifier {
  static final MisActividadesState instance = MisActividadesState._();
  MisActividadesState._();

  WebViewController? _controller;
  String? _ultimaUrl;
  bool _loading = true;
  bool _hasError = false;

  WebViewController? get controller => _controller;
  String? get ultimaUrl => _ultimaUrl;
  bool get loading => _loading;
  bool get hasError => _hasError;

  /// Listener opcional para mensajes que el JS de autollenado emite por
  /// el canal `creaboxLog`. Útil para mostrar un mini-overlay durante
  /// pruebas y diagnosticar dónde se atasca el flujo.
  void Function(String msg)? onAutologinLog;

  /// Listener para cambios de etapa del autologin. Valores posibles:
  /// `'loading'` (en pantalla SSO/email/password), `'mfa'` (esperando
  /// aprobación del Authenticator), `'kmsi'` (mantener sesión iniciada),
  /// `'done'` (fuera de login).
  void Function(String stage)? onAutologinStage;

  /// Devuelve el controller si ya existe, o lo crea con la URL de inicio.
  WebViewController obtenerOCrear({
    required String urlInicial,
    void Function(String url)? onPageStarted,
    void Function(String url)? onPageFinished,
    void Function(String url)? onUrlChange,
  }) {
    final existing = _controller;
    if (existing != null) {
      // Controller ya vivo — devolvemos. Los callbacks viejos siguen vigentes
      // pero podemos sobrescribir el log handler.
      return existing;
    }
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0A1628))
      ..addJavaScriptChannel(
        'creaboxLog',
        onMessageReceived: (msg) {
          onAutologinLog?.call(msg.message);
        },
      )
      ..addJavaScriptChannel(
        'creaboxStage',
        onMessageReceived: (msg) {
          onAutologinStage?.call(msg.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            _loading = true;
            _hasError = false;
            _ultimaUrl = url;
            notifyListeners();
            onPageStarted?.call(url);
          },
          onPageFinished: (url) {
            _loading = false;
            _ultimaUrl = url;
            notifyListeners();
            onPageFinished?.call(url);
          },
          onUrlChange: (change) {
            final u = change.url;
            if (u != null) {
              _ultimaUrl = u;
              onUrlChange?.call(u);
            }
          },
          onWebResourceError: (_) {
            _loading = false;
            _hasError = true;
            notifyListeners();
          },
        ),
      )
      ..loadRequest(Uri.parse(urlInicial));
    _controller = c;
    _ultimaUrl = urlInicial;
    return c;
  }

  void marcarLoading(bool v) {
    if (_loading != v) {
      _loading = v;
      notifyListeners();
    }
  }

  void marcarError(bool v) {
    if (_hasError != v) {
      _hasError = v;
      notifyListeners();
    }
  }

  /// Recargar manualmente.
  Future<void> recargar() async {
    final c = _controller;
    if (c != null) {
      _hasError = false;
      _loading = true;
      notifyListeners();
      await c.reload();
    }
  }

  /// Si querés liberar memoria explícitamente (ej. logout), llamá esto.
  void destruir() {
    _controller = null;
    _ultimaUrl = null;
    _loading = true;
    _hasError = false;
    notifyListeners();
  }
}


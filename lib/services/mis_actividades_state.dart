import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// Singleton que mantiene vivo el `WebViewController` de la pantalla
/// "Mis Actividades" para que cuando el técnico salga a otra herramienta
/// y vuelva, conserve el estado: cookies, página actual, scroll, formularios.
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

  void Function(String msg)? onAutologinLog;
  void Function(String stage)? onAutologinStage;

  String autologinStage = 'idle';
  bool entradaCancelada = false;

  /// Espera sesión TOA lista (o interacción MFA/picker) para quitar cortina del Home.
  Future<void> esperarCortinaHome({Duration timeout = const Duration(seconds: 90)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (entradaCancelada) return;
      switch (autologinStage) {
        case 'done':
        case 'mfa':
        case 'picker':
          return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  /// Devuelve el controller si ya existe, o lo crea con la URL de inicio.
  WebViewController obtenerOCrear({
    required String urlInicial,
    void Function(String url)? onPageStarted,
    void Function(String url)? onPageFinished,
    void Function(String url)? onUrlChange,
  }) {
    _onPageStarted = onPageStarted;
    _onPageFinished = onPageFinished;
    _onUrlChange = onUrlChange;

    final existing = _controller;
    if (existing != null) {
      unawaited(_configurarPlataforma(existing));
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
          autologinStage = msg.message;
          onAutologinStage?.call(msg.message);
          notifyListeners();
        },
      );
    _aplicarNavigationDelegate(c);
    unawaited(_configurarPlataforma(c));
    c.loadRequest(Uri.parse(urlInicial));
    _controller = c;
    _ultimaUrl = urlInicial;
    return c;
  }

  void Function(String url)? _onPageStarted;
  void Function(String url)? _onPageFinished;
  void Function(String url)? _onUrlChange;

  void _aplicarNavigationDelegate(WebViewController c) {
    c.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (url) {
          _loading = true;
          _hasError = false;
          _ultimaUrl = url;
          notifyListeners();
          _onPageStarted?.call(url);
        },
        onPageFinished: (url) {
          _loading = false;
          _hasError = false;
          _ultimaUrl = url;
          notifyListeners();
          _onPageFinished?.call(url);
        },
        onUrlChange: (change) {
          final u = change.url;
          if (u != null) {
            _ultimaUrl = u;
            _onUrlChange?.call(u);
          }
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame != true) return;
          debugPrint(
            '[MisActividades] error frame principal: '
            '${error.url ?? "?"} → ${error.description}',
          );
          _loading = false;
          _hasError = true;
          notifyListeners();
        },
      ),
    );
  }

  Future<void> _configurarPlataforma(WebViewController c) async {
    final platform = c.platform;
    if (platform is! AndroidWebViewController) return;
    await platform.setMixedContentMode(MixedContentMode.alwaysAllow);
    final cookies = AndroidWebViewCookieManager(
      const PlatformWebViewCookieManagerCreationParams(),
    );
    await cookies.setAcceptThirdPartyCookies(platform, true);
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

  Future<void> recargar() async {
    final c = _controller;
    if (c != null) {
      _hasError = false;
      _loading = true;
      notifyListeners();
      await c.reload();
    }
  }

  void destruir() {
    _controller = null;
    _ultimaUrl = null;
    _loading = true;
    _hasError = false;
    notifyListeners();
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:agente_desconexiones/providers/alerta_provider.dart';
import 'package:agente_desconexiones/services/mis_actividades_state.dart';
import 'package:agente_desconexiones/services/toa_auth_service.dart';

/// Etapa actual del flujo SSO inferida por dominio de la URL.
enum _Etapa { etadirect, microsoftEntra, otra }

class MisActividadesScreen extends StatefulWidget {
  const MisActividadesScreen({super.key});

  @override
  State<MisActividadesScreen> createState() => _MisActividadesScreenState();
}

class _MisActividadesScreenState extends State<MisActividadesScreen>
    with WidgetsBindingObserver {
  static const _urlInicial = 'https://vtr.etadirect.com';

  late final MisActividadesState _state;
  late final WebViewController _controller;

  /// Credenciales de TOA del técnico, cargadas async desde Supabase.
  Map<String, String>? _credToa;
  bool _credLoaded = false;
  bool _credSnackbarShown = false;

  Timer? _pollTimer;

  /// Últimos mensajes del JS de autollenado para mostrar en debug overlay.
  final List<String> _autologinLogs = [];

  /// Etapa del autologin reportada por el JS (o por Dart cuando detectamos
  /// dominio). Valores: 'idle', 'loading', 'mfa', 'kmsi', 'done'.
  String _stage = 'idle';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _state = MisActividadesState.instance;
    _state.onAutologinLog = _onAutologinLog;
    _state.onAutologinStage = _onAutologinStage;

    _controller = _state.obtenerOCrear(
      urlInicial: _urlInicial,
      onPageStarted: (_) {},
      onPageFinished: (url) async {
        await _arrancarAutologin(url);
      },
      onUrlChange: (_) {},
    );

    _cargarCredencialesToa();

    // Si el controller ya estaba vivo de antes, dispara el ciclo con la URL
    // actual.
    final urlActual = _state.ultimaUrl;
    if (urlActual != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _arrancarAutologin(urlActual);
      });
    }
  }

  void _onAutologinLog(String msg) {
    if (!mounted) return;
    setState(() {
      _autologinLogs.add('${DateTime.now().toIso8601String().substring(11, 19)}  $msg');
      if (_autologinLogs.length > 6) {
        _autologinLogs.removeRange(0, _autologinLogs.length - 6);
      }
    });
  }

  void _onAutologinStage(String stage) {
    if (!mounted) return;
    if (_stage != stage) setState(() => _stage = stage);
  }

  /// Mostrar la cortina opaca cuando el autologin está corriendo y el
  /// usuario no necesita interactuar (loading o KMSI). En MFA se quita
  /// para que apruebe la notificación del Authenticator.
  // ignore: unused_element
  bool get _mostrarCortina => _stage == 'loading' || _stage == 'kmsi';

  String get _cortinaTitulo {
    switch (_stage) {
      case 'kmsi':
        return 'Recordando tu sesión…';
      case 'loading':
      default:
        return 'Cargando datos…';
    }
  }

  String get _cortinaSubtitulo {
    switch (_stage) {
      case 'kmsi':
        return 'Marcando "no volver a preguntar".';
      case 'loading':
      default:
        return 'Iniciando sesión en TOA. Esto puede tardar unos segundos.';
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    // **Importante**: NO disponemos del controller. Vive en el singleton.
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<AlertaProvider>().refrescar();
    }
  }

  Future<void> _cargarCredencialesToa() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rut = (prefs.getString('rut_tecnico') ??
              prefs.getString('rut') ??
              prefs.getString('user_rut') ??
              '')
          .trim();
      if (rut.isEmpty) {
        _credLoaded = true;
        return;
      }
      final creds = await ToaAuthService().getCredenciales(rut);
      if (!mounted) return;
      setState(() {
        _credToa = creds;
        _credLoaded = true;
      });
    } catch (_) {
      _credLoaded = true;
    }
  }

  /// Inicia (o reinicia) el ciclo de autollenado. Inyecta el JS de
  /// inmediato y arranca un timer que reinyecta cada 1.5 s mientras
  /// estemos en un dominio de login (etadirect o microsoftonline).
  Future<void> _arrancarAutologin(String url) async {
    if (!_credLoaded) await _esperarCargaCreds();
    if (!mounted) return;

    final etapa = _detectarEtapa(url);
    if (etapa == _Etapa.otra) {
      // Salimos del flujo de login → cancelar polling y bajar la cortina.
      _pollTimer?.cancel();
      if (mounted && _stage != 'done') {
        setState(() => _stage = 'done');
      }
      return;
    }
    // Subir la cortina apenas detectamos dominio de login.
    if (mounted && (_stage == 'idle' || _stage == 'done')) {
      setState(() => _stage = 'loading');
    }

    if (_credToa == null) {
      if (!_credSnackbarShown) {
        _credSnackbarShown = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Credenciales TOA no encontradas, ingresa manualmente.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    // Inyección inmediata.
    await _inyectarJsAutologin(_credToa!);

    // Polling persistente: cada 1.5 s mientras estemos en login.
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (t) async {
      if (!mounted) {
        t.cancel();
        return;
      }
      final actual = _state.ultimaUrl ?? '';
      if (_detectarEtapa(actual) == _Etapa.otra || _stage == 'done') {
        t.cancel();
        return;
      }
      await _inyectarJsAutologin(_credToa!);
    });
  }

  Future<void> _esperarCargaCreds() async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!_credLoaded && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  _Etapa _detectarEtapa(String url) {
    final u = url.toLowerCase();
    if (u.contains('login.microsoftonline.com')) return _Etapa.microsoftEntra;
    if (u.contains('etadirect.com')) return _Etapa.etadirect;
    return _Etapa.otra;
  }

  /// JS unificado, idempotente, sin lock. Lo seguro es llamarlo muchas
  /// veces (lo hace el polling cada 1.5 s). Cada llamada:
  ///   - Mata el observer anterior si quedó.
  ///   - Procesa el dominio actual (etadirect o microsoftonline).
  ///   - Reinstala un MutationObserver para reaccionar a cambios SPA.
  ///   - Reporta cada acción al canal `creaboxLog` para diagnóstico.
  Future<void> _inyectarJsAutologin(Map<String, String> creds) async {
    final userLit = jsonEncode(creds['usuario'] ?? '');
    final emailLit = jsonEncode(creds['email'] ?? creds['usuario'] ?? '');
    final passLit = jsonEncode(creds['pass'] ?? '');

    final js = '''
(function() {
  var USUARIO = $userLit;
  var EMAIL = $emailLit;
  var PASS = $passLit;

  function log(msg) { try { creaboxLog.postMessage(msg); } catch(_) {} }
  function postStage(s) {
    if (window.__creabox_last_stage === s) return;
    window.__creabox_last_stage = s;
    try { creaboxStage.postMessage(s); } catch(_) {}
  }
  function detectStage() {
    var host = location.hostname.toLowerCase();
    if (host.indexOf('etadirect.com') >= 0) {
      // Distinguir entre la pantalla de login y la app de TOA: si no hay
      // form SSO en el DOM, ya estamos dentro de la app.
      var loginVisible = !!(
        document.getElementById('sign-in-with-sso') ||
        document.getElementById('sso_username') ||
        document.getElementById('organization') ||
        document.getElementById('continue-with-sso')
      );
      return loginVisible ? 'loading' : 'done';
    }
    if (host.indexOf('login.microsoftonline.com') >= 0) {
      var bodyTxt = (document.body.innerText || '').toLowerCase();
      var hasMfaText =
        bodyTxt.indexOf('aprobar') >= 0 ||
        bodyTxt.indexOf('aprueba') >= 0 ||
        bodyTxt.indexOf('verifica tu identidad') >= 0 ||
        bodyTxt.indexOf('verificar tu identidad') >= 0 ||
        bodyTxt.indexOf('approve sign-in') >= 0 ||
        bodyTxt.indexOf('approve sign in') >= 0 ||
        bodyTxt.indexOf('verify your identity') >= 0 ||
        bodyTxt.indexOf('open your authenticator') >= 0 ||
        bodyTxt.indexOf('abre la aplicaci') >= 0 ||
        bodyTxt.indexOf('coincida') >= 0;
      var hasOtp = !!document.querySelector('input[name="otc"]');
      if (hasMfaText || hasOtp) return 'mfa';
      var inKmsi = bodyTxt.indexOf('mantener la sesi') >= 0 ||
                   bodyTxt.indexOf('stay signed in') >= 0;
      if (inKmsi) return 'kmsi';
      return 'loading';
    }
    return 'done';
  }

  // Mata observer anterior si quedó vivo.
  if (window.__creabox_obs) {
    try { window.__creabox_obs.disconnect(); } catch(_) {}
    window.__creabox_obs = null;
  }

  function setVal(el, v) {
    var s = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    s.call(el, v);
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    el.dispatchEvent(new Event('keyup', { bubbles: true }));
  }
  function visible(el) { return el && el.offsetParent !== null; }

  function processEtadirect() {
    var step2 = document.getElementById('second-step-container-sso');
    var ssoUser = document.getElementById('sso_username');
    var continueBtn = document.getElementById('continue-with-sso');
    var ssoBtn = document.getElementById('sign-in-with-sso');

    if (visible(step2) && ssoUser) {
      if (ssoUser.value !== USUARIO) {
        setVal(ssoUser, USUARIO);
        log('etadirect: rellené sso_username');
        setTimeout(function() {
          var b = document.getElementById('continue-with-sso');
          if (b && !b.disabled && visible(b)) { b.click(); log('etadirect: click Continuar'); }
        }, 500);
      } else if (continueBtn && !continueBtn.disabled && visible(continueBtn)) {
        continueBtn.click();
        log('etadirect: click Continuar (ya lleno)');
      }
      return;
    }
    if (visible(ssoBtn) && !ssoBtn.disabled) {
      ssoBtn.click();
      log('etadirect: click Conectarse con SSO');
    }
  }

  // Pantalla "Selección de la cuenta" / "Pick an account": Microsoft muestra
  // tiles con las cuentas previamente usadas en este WebView. No hay input de
  // email, así que processEntra() no avanzaba. Clickeamos el tile del EMAIL
  // del técnico, o "Usar otra cuenta" si no hay match.
  function processAccountPicker() {
    var bodyTxt = (document.body.innerText || '').toLowerCase();
    var pickerVisible =
      bodyTxt.indexOf('selecci') >= 0 && bodyTxt.indexOf('cuenta') >= 0 ||
      bodyTxt.indexOf('pick an account') >= 0 ||
      bodyTxt.indexOf('choose an account') >= 0 ||
      !!document.getElementById('tilesHolder') ||
      !!document.querySelector('[data-test-id^="accountTile"]');
    if (!pickerVisible) return false;

    var emailLow = (EMAIL || '').toLowerCase();

    // 1) Tile específico de la cuenta deseada.
    var tileSelectors = [
      '[data-test-id^="accountTile"]',
      '#tilesHolder .tile',
      '#tilesHolder div[role="button"]',
      '.tile-container [role="button"]',
      'div[role="button"]'
    ];
    for (var i = 0; i < tileSelectors.length; i++) {
      var nodes = document.querySelectorAll(tileSelectors[i]);
      for (var j = 0; j < nodes.length; j++) {
        var n = nodes[j];
        if (!visible(n)) continue;
        var txt = (n.innerText || '').toLowerCase();
        if (emailLow && txt.indexOf(emailLow) >= 0) {
          try { n.click(); log('entra: click tile cuenta ' + EMAIL); return true; } catch(_) {}
        }
      }
    }

    // 2) "Usar otra cuenta" / "Use another account": forzar pantalla de email.
    var otraSelectors = [
      '[data-test-id="otherTile"]',
      '#otherTile',
      '#otherTileText',
      '.use-another-account'
    ];
    for (var k = 0; k < otraSelectors.length; k++) {
      var o = document.querySelector(otraSelectors[k]);
      if (o && visible(o)) {
        try { o.click(); log('entra: click "Usar otra cuenta"'); return true; } catch(_) {}
      }
    }
    // Fallback por texto: cualquier botón visible cuyo texto contenga
    // "otra cuenta" / "another account".
    var btns = document.querySelectorAll('div[role="button"], button, a');
    for (var m = 0; m < btns.length; m++) {
      var b = btns[m];
      if (!visible(b)) continue;
      var t = (b.innerText || '').toLowerCase();
      if (t.indexOf('otra cuenta') >= 0 || t.indexOf('another account') >= 0 ||
          t.indexOf('different account') >= 0) {
        try { b.click(); log('entra: click "otra cuenta" (texto)'); return true; } catch(_) {}
      }
    }
    return false;
  }

  function processEntra() {
    if (processAccountPicker()) return;

    var emailEl = document.querySelector('input[name="loginfmt"], input#i0116');
    var passEl = document.querySelector('input[name="passwd"], input#i0118');
    var siBtn = document.querySelector('input#idSIButton9, button#idSIButton9');
    var bodyTxt = (document.body.innerText || '').toLowerCase();

    if (visible(emailEl) && (!emailEl.value || emailEl.value !== EMAIL)) {
      setVal(emailEl, EMAIL);
      log('entra: rellené email');
      setTimeout(function() {
        var b = document.querySelector('input#idSIButton9, button#idSIButton9');
        if (b && visible(b) && !b.disabled) { b.click(); log('entra: click Siguiente (email)'); }
      }, 600);
      return;
    }
    if (visible(passEl) && !passEl.value) {
      setVal(passEl, PASS);
      log('entra: rellené password');
      setTimeout(function() {
        var b = document.querySelector('input#idSIButton9, button#idSIButton9');
        if (b && visible(b) && !b.disabled) { b.click(); log('entra: click Iniciar sesión'); }
      }, 600);
      return;
    }
    // KMSI: detección por texto ("¿Quieres mantener la sesión iniciada?")
    var inKmsi = (bodyTxt.includes('sesi') && bodyTxt.includes('iniciada')) ||
                 bodyTxt.includes('stay signed in');
    if (inKmsi && siBtn && visible(siBtn)) {
      var kmsi = document.querySelector('#KmsiCheckboxField, input[name="DontShowAgain"]');
      if (kmsi && !kmsi.checked) {
        try { kmsi.click(); log('entra: marqué "no volver a preguntar"'); } catch(_) {}
      }
      setTimeout(function() {
        var b = document.querySelector('input#idSIButton9, button#idSIButton9');
        if (b && visible(b) && !b.disabled) { b.click(); log('entra: click Sí (mantener sesión)'); }
      }, 400);
    }
  }

  function process() {
    postStage(detectStage());
    var host = location.hostname.toLowerCase();
    if (host.indexOf('etadirect.com') >= 0) {
      processEtadirect();
    } else if (host.indexOf('login.microsoftonline.com') >= 0) {
      processEntra();
    }
  }

  process();

  var obs = new MutationObserver(process);
  try {
    obs.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['style', 'class', 'disabled'] });
    window.__creabox_obs = obs;
  } catch(_) {}
})();
''';
    try {
      await _controller.runJavaScript(js);
    } catch (_) {}
  }

  // ─── Modal alerta + banner pruebas + token FCM (mantienen comportamiento)

  void _mostrarModalAlerta() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF0D1B2A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.orange.withValues(alpha: 0.4), width: 1),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 22),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.orange.withValues(alpha: 0.15),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.5), width: 2),
                  ),
                  child: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 44),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'ALERTA DE DESCONEXIÓN\nPENDIENTE DE RESOLVER',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Tienes una alerta de desconexión pendiente de resolver. Resuelve para avanzar o comunícate con tu coordinador.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 26),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/asistente-cto', arguments: 'potencias');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E88E5),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'REVISAR ESTADO DE CTO',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'CERRAR',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bloqueada = context.watch<AlertaProvider>().misActividadesBloqueada;

    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      appBar: AppBar(
        title: const Text(
          'Mis Actividades',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF0D1B2A),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (bloqueada)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.6)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock, size: 14, color: Colors.orange),
                      SizedBox(width: 4),
                      Text(
                        'BLOQUEADA',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar',
            onPressed: bloqueada ? _mostrarModalAlerta : _state.recargar,
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _state,
        builder: (context, _) {
          final loading = _state.loading;
          final hasError = _state.hasError;
          return Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    AbsorbPointer(
                      absorbing: bloqueada,
                      child: Stack(
                        children: [
                          if (!hasError) WebViewWidget(controller: _controller),
                          if (loading && !hasError)
                            const Center(
                              child: CircularProgressIndicator(color: Color(0xFF00D9FF)),
                            ),
                          if (hasError)
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.wifi_off, size: 64, color: Color(0xFF5C7A99)),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'No se pudo cargar la página',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Verifica tu conexión e intenta nuevamente.',
                                      style: TextStyle(color: Color(0xFF8FA8C8), fontSize: 14),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 24),
                                    ElevatedButton.icon(
                                      onPressed: _state.recargar,
                                      icon: const Icon(Icons.refresh),
                                      label: const Text('Reintentar'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF00D9FF),
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (bloqueada)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (_) => _mostrarModalAlerta(),
                          onPanDown: (_) => _mostrarModalAlerta(),
                          child: Container(color: Colors.black.withValues(alpha: 0.04)),
                        ),
                      ),
                    // Cortina "Cargando datos…" y overlay debug del autologin
                    // ocultos a pedido. La lógica subyacente sigue corriendo
                    // (stage + logs en `_autologinLogs`); solo se quita el
                    // render. Para reactivarlo volver a poner los `if`.
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ignore: unused_element
  Widget _cortinaCargando() {
    return Container(
      color: const Color(0xFF0A1628),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0A84FF), Color(0xFF00D4AA)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0A84FF).withValues(alpha: 0.35),
                      blurRadius: 30,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Center(
                  child: SizedBox(
                    width: 60,
                    height: 60,
                    child: CircularProgressIndicator(
                      strokeWidth: 5,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                _cortinaTitulo,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _cortinaSubtitulo,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF8FA8C8),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1B2A),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF1E3A5F)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline, color: Color(0xFF00D9FF), size: 14),
                    SizedBox(width: 6),
                    Text(
                      'Sesión segura · CREABOX',
                      style: TextStyle(
                        color: Color(0xFF00D9FF),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _autologinDebugOverlay() {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x4400D9FF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.bug_report, color: Color(0xFF00D9FF), size: 14),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Autollenado SSO (debug)',
                    style: TextStyle(
                      color: Color(0xFF00D9FF),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _autologinLogs.clear()),
                  child: const Icon(Icons.close, color: Color(0xFF8FA8C8), size: 14),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ..._autologinLogs.map((m) => Text(
                  m,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontFamily: 'monospace',
                    height: 1.3,
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

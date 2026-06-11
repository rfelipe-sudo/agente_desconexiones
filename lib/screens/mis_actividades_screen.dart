import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:agente_desconexiones/providers/alerta_provider.dart';
import 'package:agente_desconexiones/screens/consumo_screen.dart';
import 'package:agente_desconexiones/services/mis_actividades_state.dart';
import 'package:agente_desconexiones/services/recetas_consumo_service.dart';
import 'package:agente_desconexiones/services/toa_auth_service.dart';
import 'package:agente_desconexiones/services/toa_autologin_js.dart';
import 'package:agente_desconexiones/widgets/cortina_carga_card.dart';

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
  Timer? _pickerBurstTimer;
  Timer? _autologinTimeoutTimer;
  bool _reinicioFlujoEnCurso = false;
  String? _ultimaUrlInyectada;
  DateTime? _ultimaInyeccionAt;
  bool _webViewListo = false;

  static const _cortinaColor = Color(0xFF3B82F6);

  /// Etapa del autologin. Valores: 'idle', 'loading', 'mfa', 'kmsi', 'picker', 'done'.
  String _stage = 'loading';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _state = MisActividadesState.instance;
    _state.entradaCancelada = false;
    _state.onAutologinLog = null;
    _state.onAutologinStage = _onAutologinStage;
    unawaited(_gateEntrada());
  }

  Future<void> _gateEntrada() async {
    if (await _tieneOrdenesPendientesConsumo()) {
      _state.entradaCancelada = true;
      if (!mounted) return;
      await _mostrarDialogoConsumoPendiente();
      return;
    }
    _inicializarWebView();
    _cargarCredencialesToa();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_arrancarAutologin(_state.ultimaUrl ?? _urlInicial));
    });
  }

  void _inicializarWebView() {
    _controller = _state.obtenerOCrear(
      urlInicial: _urlInicial,
      onPageStarted: (_) {},
      onPageFinished: (url) => unawaited(_arrancarAutologin(url)),
      onUrlChange: (url) {
        final etapa = _detectarEtapa(url);
        if (etapa == _Etapa.etadirect || etapa == _Etapa.microsoftEntra) {
          unawaited(_arrancarAutologin(url));
        }
      },
    );
    _webViewListo = true;
  }

  Future<bool> _tieneOrdenesPendientesConsumo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rut = (prefs.getString('rut_tecnico') ??
              prefs.getString('rut') ??
              prefs.getString('user_rut') ??
              '')
          .trim();
      if (rut.isEmpty) return false;
      final ots =
          await RecetasConsumoService().getOtsPendienteConsumo(rut: rut);
      return ots.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _mostrarDialogoConsumoPendiente() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF0D1B2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Tienes órdenes pendientes de consumo. '
                'Presiona OK, consume tus órdenes y vuelve a abrir tus actividades. '
                'Mientras tu consumo no esté en cero no podrás ver tus actividades.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ConsumoScreen(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00D9FF),
                    foregroundColor: const Color(0xFF0A1628),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  void _onAutologinStage(String stage) {
    if (stage == 'error_aad' || stage == 'signed_out') {
      unawaited(_reiniciarFlujoToa(motivo: stage));
      return;
    }
    if (stage == 'picker') {
      unawaited(_intentarClickPickerAutomatico());
    } else {
      _pickerBurstTimer?.cancel();
    }
    if (stage == 'done') {
      _pollTimer?.cancel();
      _autologinTimeoutTimer?.cancel();
    }
    if (!mounted) return;
    if (_stage != stage) setState(() => _stage = stage);
  }

  /// En picker Microsoft: intenta "Usar otra cuenta"; si no avanza, limpia cookies.
  Future<void> _intentarClickPickerAutomatico() async {
    if (_credToa == null) return;
    _pickerBurstTimer?.cancel();
    await ToaAutologinJs.inject(_controller, _credToa!);
    await ToaAutologinJs.useAnotherAccount(_controller);
    _pickerBurstTimer = Timer(const Duration(seconds: 2), () async {
      if (!mounted || _stage != 'picker') return;
      await _recuperarPickerConCookies();
    });
  }

  /// Limpia cookies y reinicia SSO desde etadirect (nunca recargar URL Microsoft).
  Future<void> _recuperarPickerConCookies() async {
    await _reiniciarFlujoToa(motivo: 'picker_cookies', limpiarCookies: true);
  }

  Future<void> _confirmarPickerCuenta() async {
    await _recuperarPickerConCookies();
  }

  /// Reinicia el flujo SSO desde cero. Evita bucles si ya hay uno en curso.
  Future<void> _reiniciarFlujoToa({
    required String motivo,
    bool limpiarCookies = false,
  }) async {
    if (_reinicioFlujoEnCurso || !mounted) return;
    _reinicioFlujoEnCurso = true;
    _pollTimer?.cancel();
    _pickerBurstTimer?.cancel();
    _autologinTimeoutTimer?.cancel();
    _ultimaUrlInyectada = null;
    try {
      if (limpiarCookies) {
        await WebViewCookieManager().clearCookies();
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      if (!mounted) return;
      await _controller.loadRequest(Uri.parse(_urlInicial));
      await Future<void>.delayed(const Duration(seconds: 2));
      if (_credToa != null && mounted) {
        await _arrancarAutologin(_urlInicial);
      }
    } finally {
      _reinicioFlujoEnCurso = false;
    }
  }

  /// Cortina interna (si se abre sin wrapper del Home). MFA/picker sin cortina.
  bool get _mostrarCortina =>
      _webViewListo && (_stage == 'loading' || _stage == 'kmsi');

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
    _pickerBurstTimer?.cancel();
    _autologinTimeoutTimer?.cancel();
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
      if (creds != null) {
        unawaited(_arrancarAutologin(_state.ultimaUrl ?? _urlInicial));
      }
    } catch (_) {
      _credLoaded = true;
    }
  }

  /// Reinyecta JS en cada ciclo (como el flujo original que funcionaba).
  Future<void> _arrancarAutologin(String url) async {
    if (!_webViewListo) return;
    if (!_credLoaded) await _esperarCargaCreds();
    if (!mounted || _reinicioFlujoEnCurso) return;

    if (_esPaginaCierreSesionMicrosoft(url)) {
      unawaited(_reiniciarFlujoToa(motivo: 'cierre_sesion_url'));
      return;
    }

    final etapa = _detectarEtapa(url);
    if (etapa == _Etapa.otra) {
      _pollTimer?.cancel();
      _autologinTimeoutTimer?.cancel();
      if (mounted && _stage != 'done') {
        setState(() => _stage = 'done');
      }
      return;
    }
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

    // Evitar saturar el WebView: no reinyectar si misma URL hace < 2 s.
    final ahora = DateTime.now();
    if (_ultimaUrlInyectada == url &&
        _ultimaInyeccionAt != null &&
        ahora.difference(_ultimaInyeccionAt!) < const Duration(seconds: 2)) {
      return;
    }
    _ultimaUrlInyectada = url;
    _ultimaInyeccionAt = ahora;

    await ToaAutologinJs.inject(_controller, _credToa!);

    _pollTimer?.cancel();
    _autologinTimeoutTimer?.cancel();
    _autologinTimeoutTimer = Timer(const Duration(seconds: 75), () {
      if (!mounted) return;
      if (_stage == 'loading' || _stage == 'picker' || _stage == 'kmsi') {
        unawaited(_reiniciarFlujoToa(motivo: 'timeout'));
      }
    });
    _pollTimer = Timer.periodic(const Duration(milliseconds: 2500), (t) async {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_reinicioFlujoEnCurso) return;
      final actual = _state.ultimaUrl ?? '';
      if (_esPaginaCierreSesionMicrosoft(actual)) {
        t.cancel();
        unawaited(_reiniciarFlujoToa(motivo: 'cierre_sesion_poll'));
        return;
      }
      final etapaActual = _detectarEtapa(actual);
      if (etapaActual == _Etapa.otra || _stage == 'done') {
        t.cancel();
        _autologinTimeoutTimer?.cancel();
        return;
      }
      if (_credToa != null &&
          (_stage == 'loading' || _stage == 'picker' || _stage == 'mfa' || _stage == 'kmsi')) {
        await _arrancarAutologin(actual);
      }
    });
  }

  bool _esPaginaCierreSesionMicrosoft(String url) {
    final u = url.toLowerCase();
    if (!u.contains('microsoftonline.com') &&
        !u.contains('login.live.com') &&
        !u.contains('login.microsoft.com')) {
      return false;
    }
    return u.contains('logout') ||
        u.contains('signedout') ||
        u.contains('clearstate') ||
        u.contains('sesion-terminada') ||
        u.contains('session-terminat');
  }

  Future<void> _esperarCargaCreds() async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!_credLoaded && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  _Etapa _detectarEtapa(String url) {
    final u = url.toLowerCase();
    if (u.contains('login.microsoftonline.com') ||
        u.contains('login.live.com') ||
        u.contains('login.microsoft.com')) {
      return _Etapa.microsoftEntra;
    }
    if (u.contains('etadirect.com') ||
        u.contains('oraclecloud.com') ||
        u.contains('oracle.com')) {
      return _Etapa.etadirect;
    }
    return _Etapa.otra;
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
            icon: const Icon(Icons.login),
            tooltip: 'Continuar login',
            onPressed: bloqueada
                ? _mostrarModalAlerta
                : () {
                    if (_credToa != null) {
                      unawaited(ToaAutologinJs.inject(_controller, _credToa!));
                    }
                  },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar',
            onPressed: bloqueada ? _mostrarModalAlerta : _state.recargar,
          ),
        ],
      ),
      body: _webViewListo
          ? AnimatedBuilder(
        animation: _state,
        builder: (context, _) {
          final loading = _state.loading;
          final hasError = _state.hasError;
          final enLoginMicrosoft =
              _detectarEtapa(_state.ultimaUrl ?? '') == _Etapa.microsoftEntra;
          return Stack(
            children: [
              AbsorbPointer(
                absorbing: bloqueada,
                child: Stack(
                  children: [
                    if (!hasError) WebViewWidget(controller: _controller),
                    if (loading && !hasError && !enLoginMicrosoft && !_mostrarCortina)
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
              if (_stage == 'picker' && _credToa != null && !bloqueada)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 24,
                  child: _bannerConfirmacionPicker(),
                ),
              if (_mostrarCortina)
                Positioned.fill(
                  child: CortinaCargaCard(
                    accentColor: _cortinaColor,
                    titulo: _cortinaTitulo,
                    subtitulo: _cortinaSubtitulo,
                  ),
                ),
            ],
          );
        },
      )
          : const CortinaCargaCard(
              accentColor: _cortinaColor,
              titulo: 'Mis Actividades',
              subtitulo: 'Verificando acceso…',
            ),
    );
  }

  Widget _bannerConfirmacionPicker() {
    final email = (_credToa?['email'] ?? _credToa?['usuario'] ?? '').trim();
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: const Color(0xFF0D1B2A),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF00D9FF).withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Selección de cuenta Microsoft',
              style: TextStyle(
                color: Color(0xFF8FA8C8),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '¿Continuar con\n$email?',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Se abrirá el formulario de email y contraseña automáticamente.',
              style: TextStyle(color: Color(0xFF8FA8C8), fontSize: 11, height: 1.3),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: () => unawaited(_confirmarPickerCuenta()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00D9FF),
                  foregroundColor: const Color(0xFF0A1628),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Sí, continuar',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

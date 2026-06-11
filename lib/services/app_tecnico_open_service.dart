import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agente_desconexiones/services/app_tecnico_launcher.dart';
import 'package:agente_desconexiones/services/app_tecnico_local_server.dart';
import 'package:agente_desconexiones/services/app_tecnico_web_service.dart';
import 'package:agente_desconexiones/services/toa_auth_service.dart';

/// Abre App Técnico desde Home: cortina al instante, sin pantalla puente.
class AppTecnicoOpenService {
  AppTecnicoOpenService._();
  static final AppTecnicoOpenService instance = AppTecnicoOpenService._();

  final _localServer = AppTecnicoLocalServer();
  final _status = ValueNotifier<String>('Preparando App Técnico…');
  final _progress = ValueNotifier<double>(0);

  OverlayEntry? _overlay;
  bool _opening = false;

  /// Llamar al tocar el botón en Home — muestra cortina de inmediato.
  Future<void> openFromHome(BuildContext context) async {
    if (_opening) return;
    _opening = true;

    AppTecnicoLauncher.ensureNativeCallbacksRegistered();
    AppTecnicoLauncher.onCredentialsError = onCredentialsErrorFromNative;
    AppTecnicoLauncher.onClosed = onNativeClosed;

    _showCortina(context);

    try {
      if (!Platform.isAndroid) {
        throw Exception('App Técnico solo está disponible en Android.');
      }

      _setProgress(0.02, 'Obteniendo credenciales…');
      final creds = await _cargarCredenciales();

      final wwwDir = await AppTecnicoWebService.ensureWwwExtracted(
        onProgress: (p, status) => _setProgress(p, status),
      );

      _setProgress(0.95, 'Iniciando servidor local…');
      final appUrl = await _localServer.start(wwwDir);

      _setProgress(1, creds != null
          ? 'Abriendo App Técnico e ingresando…'
          : 'Abriendo App Técnico…');

      await AppTecnicoLauncher.openEmbeddedWebView(
        appUrl,
        autoUsername: creds?['usuario'],
        autoPassword: creds?['pass'],
      );

      _hideCortina();
    } catch (e) {
      _hideCortina();
      await _localServer.stop();
      if (context.mounted) {
        await _showErrorDialog(context, e.toString());
      }
    } finally {
      _opening = false;
    }
  }

  void onNativeClosed() {
    unawaited(_localServer.stop());
  }

  void onCredentialsErrorFromNative() {
    unawaited(_localServer.stop());
  }

  void _setProgress(double p, String status) {
    _progress.value = p;
    _status.value = status;
  }

  void _showCortina(BuildContext context) {
    _hideCortina();
    _status.value = 'Preparando App Técnico…';
    _progress.value = 0;

    final overlay = Overlay.of(context, rootOverlay: true);
    _overlay = OverlayEntry(
      builder: (ctx) => Material(
        color: const Color(0xFF0A1628),
        child: SafeArea(
          child: ValueListenableBuilder<String>(
            valueListenable: _status,
            builder: (_, status, __) => ValueListenableBuilder<double>(
              valueListenable: _progress,
              builder: (_, progress, __) => _CortinaBody(
                status: status,
                progress: progress,
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_overlay!);
  }

  void _hideCortina() {
    _overlay?.remove();
    _overlay = null;
  }

  Future<Map<String, String>?> _cargarCredenciales() async {
    final prefs = await SharedPreferences.getInstance();
    final rut = (prefs.getString('rut_tecnico') ??
            prefs.getString('rut') ??
            prefs.getString('user_rut') ??
            '')
        .trim();
    if (rut.isEmpty) return null;
    return ToaAuthService().getCredenciales(rut);
  }

  Future<void> _showErrorDialog(BuildContext context, String message) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1B2A),
        title: const Text(
          'Error',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          message,
          style: const TextStyle(color: Color(0xFF8FA8C8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Aceptar',
              style: TextStyle(color: Color(0xFFE30613)),
            ),
          ),
        ],
      ),
    );
  }
}

class _CortinaBody extends StatelessWidget {
  const _CortinaBody({
    required this.status,
    required this.progress,
  });

  final String status;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFE30613), Color(0xFFB8050F)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE30613).withValues(alpha: 0.35),
                    blurRadius: 30,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Center(
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              status,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: progress > 0 ? progress.clamp(0.0, 1.0) : null,
              color: const Color(0xFFE30613),
              backgroundColor: Colors.white12,
            ),
            if (progress > 0 && progress < 1) ...[
              const SizedBox(height: 8),
              Text(
                '${(progress * 100).round()}%',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
            const SizedBox(height: 20),
            const Text(
              'Primera vez puede tardar 1–2 min.\nCREABOX sigue respondiendo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

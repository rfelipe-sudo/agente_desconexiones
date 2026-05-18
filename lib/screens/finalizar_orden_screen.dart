import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const _bg      = Color(0xFF0A1628);
const _surface = Color(0xFF0D1B2A);
const _accent  = Color(0xFF00D9FF);
const _danger  = Color(0xFFEF4444);
const _textDim = Color(0xFF8FA8C8);
const _border  = Color(0xFF1E3A5F);

const _pkgTecnicos  = 'com.vtrapp.tecnico';
const _assetApkPath = 'assets/apk/tecnicos.apk'; // path para rootBundle

class FinalizarOrdenScreen extends StatefulWidget {
  const FinalizarOrdenScreen({super.key});

  @override
  State<FinalizarOrdenScreen> createState() => _FinalizarOrdenScreenState();
}

class _FinalizarOrdenScreenState extends State<FinalizarOrdenScreen> {
  static const _channel = MethodChannel(
    'com.creacionestecnologicas.agente_desconexiones/app_launcher',
  );

  bool _verificando = true;
  bool _instalado   = false;
  bool _instalando  = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _verificarYAbrir();
  }

  Future<void> _verificarYAbrir() async {
    setState(() { _verificando = true; _error = null; });
    try {
      final instalado = await _channel.invokeMethod<bool>('isInstalled', _pkgTecnicos) ?? false;
      if (!mounted) return;
      setState(() { _instalado = instalado; _verificando = false; });
      if (instalado) await _abrirApp();
    } on PlatformException catch (e) {
      if (mounted) setState(() { _error = e.message; _verificando = false; });
    }
  }

  Future<void> _abrirApp() async {
    try {
      await _channel.invokeMethod('launchApp', _pkgTecnicos);
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _instalarApp() async {
    setState(() { _instalando = true; _error = null; });
    try {
      // 1. Leer el APK desde Flutter assets (rootBundle maneja descompresión).
      final bytes = await rootBundle.load(_assetApkPath);

      // 2. Escribir en directorio de caché del dispositivo.
      final cacheDir = await getTemporaryDirectory();
      final apkFile  = File('${cacheDir.path}/apk/tecnicos.apk');
      await apkFile.parent.create(recursive: true);
      await apkFile.writeAsBytes(bytes.buffer.asUint8List(), flush: true);

      // 3. Pedir a Kotlin que abra el instalador con la ruta absoluta.
      await _channel.invokeMethod('installApkFromPath', apkFile.path);
      if (mounted) setState(() => _instalando = false);
    } on PlatformException catch (e) {
      if (mounted) setState(() { _error = e.message; _instalando = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _instalando = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Finalizar Orden',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
      body: Center(child: _buildContent()),
    );
  }

  Widget _buildContent() {
    if (_verificando) {
      return _StatusView(
        icon: const CircularProgressIndicator(color: _accent, strokeWidth: 2.5),
        title: 'Verificando app...',
        subtitle: 'Comprobando si App Técnicos está instalada',
      );
    }

    if (_error != null) {
      return _StatusView(
        icon: const Icon(Icons.error_outline, color: _danger, size: 56),
        title: 'Error',
        subtitle: _error!,
        action: TextButton.icon(
          onPressed: _verificarYAbrir,
          icon: const Icon(Icons.refresh, color: _accent),
          label: const Text('Reintentar', style: TextStyle(color: _accent)),
        ),
      );
    }

    if (_instalado) {
      return _StatusView(
        icon: const CircularProgressIndicator(color: _accent, strokeWidth: 2.5),
        title: 'Abriendo App Técnicos...',
        subtitle: 'Volvé a CREABOX cuando termines',
        action: TextButton.icon(
          onPressed: _abrirApp,
          icon: const Icon(Icons.open_in_new, color: _accent),
          label: const Text('Abrir de nuevo', style: TextStyle(color: _accent)),
        ),
      );
    }

    // No instalada → mostrar botón de instalación
    return _StatusView(
      icon: const Icon(Icons.install_mobile, color: _accent, size: 56),
      title: 'App Técnicos no instalada',
      subtitle: 'Necesitás instalar App Técnicos para finalizar la orden.',
      action: _instalando
          ? const CircularProgressIndicator(color: _accent, strokeWidth: 2.5)
          : FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: _bg,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _instalarApp,
              icon: const Icon(Icons.download),
              label: const Text(
                'Instalar App Técnicos',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
    );
  }
}

class _StatusView extends StatelessWidget {
  const _StatusView({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final Widget icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88, height: 88,
            decoration: BoxDecoration(
              color: const Color(0xFF0D1B2A),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _border),
            ),
            child: Center(child: icon),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: const TextStyle(color: _textDim, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[
            const SizedBox(height: 28),
            action!,
          ],
        ],
      ),
    );
  }
}

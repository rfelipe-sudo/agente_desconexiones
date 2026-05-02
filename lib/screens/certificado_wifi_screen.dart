import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Certificado CreaCheck WiFi v3: mismo HTML/CSS que `assets/certificado/certificado_wifi_v3.html`.
///
/// Si [htmlOverride] no es null, se usa ese documento (p. ej. datos dinámicos).
class CertificadoWifiScreen extends StatefulWidget {
  const CertificadoWifiScreen({super.key, this.htmlOverride});

  final String? htmlOverride;

  @override
  State<CertificadoWifiScreen> createState() => _CertificadoWifiScreenState();
}

class _CertificadoWifiScreenState extends State<CertificadoWifiScreen> {
  WebViewController? _controller;
  bool _loading = true;
  String? _error;

  static const _assetPath = 'assets/certificado/certificado_wifi_v3.html';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (kIsWeb) {
      setState(() {
        _error =
            'El certificado HTML se visualiza en la app para Android o iOS.';
        _loading = false;
      });
      return;
    }

    try {
      final html = widget.htmlOverride?.isNotEmpty == true
          ? widget.htmlOverride!
          : await rootBundle.loadString(_assetPath);

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFFD0D7E2));

      await controller.loadHtmlString(
        html,
        baseUrl: 'https://fonts.googleapis.com/',
      );

      if (!mounted) return;
      setState(() {
        _controller = controller;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el certificado: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFD0D7E2),
      appBar: AppBar(
        title: const Text('Certificado WiFi'),
        backgroundColor: const Color(0xFF0D1B2A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF1e293b)),
                ),
              ),
            )
          : _loading || _controller == null
              ? const Center(child: CircularProgressIndicator())
              : WebViewWidget(controller: _controller!),
    );
  }
}

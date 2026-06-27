import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Configuración de SSID/clave WiFi vía interfaz web de la ONT.
class WifiCredencialesScreen extends StatefulWidget {
  const WifiCredencialesScreen({super.key});

  @override
  State<WifiCredencialesScreen> createState() => _WifiCredencialesScreenState();
}

class _WifiCredencialesScreenState extends State<WifiCredencialesScreen> {
  static const _ontHost = '192.168.1.1';
  static const _ontUser = 'root';
  static const _ontPassword = 'VAdtzq39';
  static String get _base => 'http://$_ontHost';

  final _ssid24 = TextEditingController();
  final _psk24 = TextEditingController();
  final _ssid5 = TextEditingController();
  final _psk5 = TextEditingController();

  /// Conexión inicial / reintento.
  _OntPhase _phase = _OntPhase.loading;
  String? _errorMessage;

  /// Mientras se guardan cambios (formulario ya visible).
  bool _saving = false;

  String? _sessionCookie;

  static final _wifiArrRe = RegExp(
    r'new stWlanWifi\("([^"]+)","[^"]+","[^"]+","([^"]+)"',
  );
  static final _pskRe = RegExp(
    r'new stPreSharedKey\("([^"]+)","([^"]+)"',
  );

  @override
  void initState() {
    super.initState();
    _conectarAutomatico();
  }

  @override
  void dispose() {
    _ssid24.dispose();
    _psk24.dispose();
    _ssid5.dispose();
    _psk5.dispose();
    super.dispose();
  }

  bool _is24GHzPath(String path) {
    return RegExp(r'WLANConfiguration\.1(\.|$)').hasMatch(path) &&
        !RegExp(r'WLANConfiguration\.1[0-9]').hasMatch(path);
  }

  bool _is5GHzPath(String path) {
    return RegExp(r'WLANConfiguration\.5(\.|$)').hasMatch(path) &&
        !RegExp(r'WLANConfiguration\.5[0-9]').hasMatch(path);
  }

  String? _cookieFromResponse(http.Response r) {
    final raw = r.headers['set-cookie'];
    if (raw == null || raw.trim().isEmpty) return null;
    final first = raw.split(';').first.trim();
    if (first.contains('=')) return first;
    return null;
  }

  _ParsedWlan _parseWlanHtml(String html) {
    final out = _ParsedWlan();
    for (final m in _wifiArrRe.allMatches(html)) {
      final path = m.group(1)!;
      final ssid = m.group(2)!;
      if (_is24GHzPath(path)) out.ssid24 = ssid;
      if (_is5GHzPath(path)) out.ssid5 = ssid;
    }
    for (final m in _pskRe.allMatches(html)) {
      final path = m.group(1)!;
      final key = m.group(2)!;
      if (_is24GHzPath(path)) out.psk24 = key;
      if (_is5GHzPath(path)) out.psk5 = key;
    }
    return out;
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red[800] : Colors.green[800],
      ),
    );
  }

  InputDecoration _fieldDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
      filled: true,
      fillColor: const Color(0xFF0D1B2A),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF1E3A5F)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF00D9FF)),
      ),
    );
  }

  Widget _gradientButton({
    required String label,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF00D9FF), Color(0xFF0099CC)],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(12),
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _conectarAutomatico() async {
    setState(() {
      _phase = _OntPhase.loading;
      _errorMessage = null;
    });

    try {
      final loginUri = Uri.parse('$_base/login.cgi');
      final loginResp = await http
          .post(
            loginUri,
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body:
                'UserName=${Uri.encodeQueryComponent(_ontUser)}&PassWord=${Uri.encodeQueryComponent(_ontPassword)}',
          )
          .timeout(const Duration(seconds: 20));

      final cookie = _cookieFromResponse(loginResp);
      if (cookie == null || cookie.isEmpty) {
        if (!mounted) return;
        setState(() {
          _phase = _OntPhase.error;
          _errorMessage =
              'No se recibió sesión de la ONT. Comprueba que estés en su WiFi.';
        });
        return;
      }

      final wlanUri = Uri.parse('$_base/html/amp/wlanbasic/WlanBasic.asp');
      final htmlResp = await http
          .get(
            wlanUri,
            headers: {'Cookie': cookie},
          )
          .timeout(const Duration(seconds: 20));

      if (htmlResp.statusCode != 200) {
        if (!mounted) return;
        setState(() {
          _phase = _OntPhase.error;
          _errorMessage =
              'Error al leer la configuración WiFi (código ${htmlResp.statusCode}).';
        });
        return;
      }

      final parsed = _parseWlanHtml(htmlResp.body);
      if (!mounted) return;
      setState(() {
        _sessionCookie = cookie;
        _phase = _OntPhase.connected;
        _ssid24.text = parsed.ssid24 ?? '';
        _psk24.text = parsed.psk24 ?? '';
        _ssid5.text = parsed.ssid5 ?? '';
        _psk5.text = parsed.psk5 ?? '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _OntPhase.error;
        _errorMessage = 'Error de conexión: $e';
      });
    }
  }

  Uri _buildSetUri({
    required int band,
    required String ssid,
    required String preSharedKey,
  }) {
    final y = 'InternetGatewayDevice.LANDevice.1.WLANConfiguration.$band';
    final z = '$y.WPS';
    final k = '$y.PreSharedKey.1';
    return Uri.parse('$_base/html/amp/wlanbasic/set.cgi').replace(
      queryParameters: {
        'c1': 'InternetGatewayDevice.X_HW_DEBUG.WLANConfigAction',
        'w': 'InternetGatewayDevice.X_HW_DEBUG.AMP.WifiCoverSetWlanBasic',
        'y': y,
        'z': z,
        'k': k,
        'c2': 'InternetGatewayDevice.X_HW_DEBUG.WLANConfigAction',
        'RequestFile': 'html/amp/wlanbasic/WlanBasic.asp',
        'SSID': ssid,
        'PreSharedKey': preSharedKey,
      },
    );
  }

  Future<void> _guardar() async {
    final cookie = _sessionCookie;
    if (cookie == null || cookie.isEmpty) {
      _snack('Sesión no válida. Reintenta la carga.', error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final uri24 = _buildSetUri(
        band: 1,
        ssid: _ssid24.text.trim(),
        preSharedKey: _psk24.text.trim(),
      );
      final uri5 = _buildSetUri(
        band: 5,
        ssid: _ssid5.text.trim(),
        preSharedKey: _psk5.text.trim(),
      );

      final headers = {'Cookie': cookie};
      final r24 = await http.get(uri24, headers: headers).timeout(
            const Duration(seconds: 20),
          );
      final r5 = await http.get(uri5, headers: headers).timeout(
            const Duration(seconds: 20),
          );

      final ok = r24.statusCode == 200 && r5.statusCode == 200;
      if (ok) {
        _snack('Cambios guardados correctamente');
      } else {
        _snack('Error al guardar', error: true);
      }
    } catch (e) {
      _snack('Error de conexión: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      appBar: AppBar(
        title: const Text('Configurar Red WiFi'),
        backgroundColor: const Color(0xFF0D1B2A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          switch (_phase) {
            _OntPhase.loading => _buildLoadingBody(),
            _OntPhase.error => _buildErrorBody(),
            _OntPhase.connected => _buildFormBody(),
          },
          if (_saving)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x66000000),
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFF00D9FF)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingBody() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Color(0xFF00D9FF)),
          SizedBox(height: 24),
          Text(
            'Conectando con la ONT…',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBody() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, size: 56, color: Colors.red[300]),
            const SizedBox(height: 20),
            Text(
              _errorMessage ?? 'No se pudo conectar.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            const SizedBox(height: 28),
            _gradientButton(
              label: 'Reintentar',
              onPressed: _saving ? null : _conectarAutomatico,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Chip(
            avatar: const Icon(Icons.check_circle, color: Colors.white, size: 18),
            label: const Text('✓ Conectado a ONT'),
            backgroundColor: Colors.green[800],
            labelStyle: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _ssid24,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration(hint: 'Nombre red 2.4GHz'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _psk24,
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration(hint: 'Contraseña red 2.4GHz'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ssid5,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration(hint: 'Nombre red 5GHz'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _psk5,
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration(hint: 'Contraseña red 5GHz'),
          ),
          const SizedBox(height: 28),
          _gradientButton(
            label: 'Guardar Cambios',
            onPressed: _saving ? null : _guardar,
          ),
        ],
      ),
    );
  }
}

enum _OntPhase { loading, error, connected }

class _ParsedWlan {
  String? ssid24;
  String? ssid5;
  String? psk24;
  String? psk5;
}

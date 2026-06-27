import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import 'package:agente_desconexiones/services/cert_builder.dart';
import 'package:agente_desconexiones/services/coverage_calculator.dart';
import 'package:agente_desconexiones/services/coverage_floor_plan.dart';
import 'package:agente_desconexiones/services/nyquist_service.dart';
import 'package:agente_desconexiones/services/ont_wifi_service.dart';
import 'package:agente_desconexiones/services/wifi_neighbor_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _Paso { modelo, estado, conectando, contexto, escaneando, resultado }

const _kBg = Color(0xFF0A1628);
const _kPanel = Color(0xFF0D1B2A);
const _kBorder = Color(0xFF1E3A5F);
const _kDim = Color(0xFF8FA8C8);
const _kAccent = Color(0xFF00D9FF);

/// Pantalla de análisis de cobertura WiFi (ONT + escaneo + score).
class WifiCoberturaScreen extends StatefulWidget {
  const WifiCoberturaScreen({super.key});

  @override
  State<WifiCoberturaScreen> createState() => _WifiCoberturaScreenState();
}

class _WifiCoberturaScreenState extends State<WifiCoberturaScreen>
    with TickerProviderStateMixin {
  bool _modoCliente = false;

  String _tipoPropiedad = '';
  String _tamano = '';
  String _construccion = '';

  List<OntDevice> _devices = [];
  List<WifiNeighbor> _neighbors = [];
  List<OntNeighbour> _ontNeighbours = []; // redes vecinas reportadas por la ONT
  int _score = 0;
  bool _tieneDecoEn24g = false;
  String _recomendacionExtensor = '';

  int _countdown = 60;
  Timer? _timer;
  Timer? _msgTimer;

  _Paso _paso = _Paso.modelo;

  int _scanMsgIndex = 0;
  double _flashOpacity = 0;

  // Estado del nuevo flujo (modelo → estado → conectando → resultado)
  String _conectandoMensaje = 'Conectando con la ONT...';
  String? _errorConexion;

  late final AnimationController _radarController;
  late final AnimationController _pulseController;

  final OntWifiService _ontWifi = OntWifiService();
  final WifiNeighborService _neighborService = WifiNeighborService();

  static const _scanMsgs = [
    'Conectando a ONT...',
    'Detectando dispositivos...',
    'Escaneando redes vecinas...',
    'Calculando interferencias...',
    'Generando mapa de cobertura...',
  ];

  String get _construccionEfectiva {
    if (_construccion.isEmpty) return 'Madera';
    return _construccion;
  }

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _msgTimer?.cancel();
    _radarController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  bool get _puedeIniciar =>
      _tipoPropiedad.isNotEmpty &&
      _tamano.isNotEmpty &&
      _construccion.isNotEmpty;

  void _iniciarEscaneo() {
    setState(() {
      _paso = _Paso.escaneando;
      _devices = [];
      _neighbors = [];
      _countdown = 60;
      _scanMsgIndex = 0;
      _flashOpacity = 0;
    });

    _timer?.cancel();
    _msgTimer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        if (_countdown > 0) _countdown--;
      });
    });

    _msgTimer = Timer.periodic(const Duration(seconds: 5), (t) {
      if (!mounted || _paso != _Paso.escaneando) {
        t.cancel();
        return;
      }
      setState(() => _scanMsgIndex = (_scanMsgIndex + 1) % _scanMsgs.length);
    });

    Future.wait([
      _fetchOntSafe().then((d) {
        if (mounted) setState(() => _devices = d);
      }),
      _neighborService.scan().then((n) {
        if (mounted) setState(() => _neighbors = n);
      }),
      Future.delayed(const Duration(seconds: 60)),
    ]).then((_) async {
      _timer?.cancel();
      _msgTimer?.cancel();
      if (!mounted) return;
      _computeMetrics();
      await _flashSecuencia();
      if (!mounted) return;
      setState(() => _paso = _Paso.resultado);
    });
  }

  Future<List<OntDevice>> _fetchOntSafe() async {
    try {
      final ok = await _ontWifi.login();
      if (!ok) return [];
      return await _ontWifi.getDevices();
    } catch (_) {
      return [];
    }
  }

  void _computeMetrics() {
    final c = _construccionEfectiva;
    _tieneDecoEn24g = _devices.any(
      (d) => d.esDecodificador && !d.es5GHz && !d.esCableado,
    );
    _score = CoverageCalculator.calcularScore(
      devices: _devices,
      neighbors: _neighbors,
      construccion: c,
    );
    _recomendacionExtensor = CoverageCalculator.recomendacionExtensor(
      _devices,
      c,
      _neighbors,
    );
  }

  Future<void> _flashSecuencia() async {
    setState(() => _flashOpacity = 1.0);
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    setState(() => _flashOpacity = 0.0);
    await Future.delayed(const Duration(milliseconds: 200));
  }

  Color _colorScore(bool condicional) {
    if (condicional) return const Color(0xFFDC2626);
    if (_score >= 90) return const Color(0xFF10B981);
    if (_score >= 75) return const Color(0xFF00D9FF);
    if (_score >= 60) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    if (_modoCliente && _paso == _Paso.resultado) {
      return _buildModoCliente();
    }
    switch (_paso) {
      case _Paso.modelo:
        return _buildModelo();
      case _Paso.estado:
        return _buildEstado();
      case _Paso.conectando:
        return _buildConectando();
      case _Paso.contexto:
        return _buildContexto();
      case _Paso.escaneando:
        return _buildEscaneando();
      case _Paso.resultado:
        return _buildResultadoTecnico();
    }
  }

  // ─── PANTALLA SELECCIÓN DE MODELO DE ONT ──────────────────────────

  Widget _buildModelo() {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: const Text('Cobertura WiFi'),
        backgroundColor: _kPanel,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Text(
                'Selecciona la marca de la ONT',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Solo necesitamos saber el modelo para usar los endpoints correctos.',
                style: GoogleFonts.poppins(fontSize: 13, color: _kDim),
              ),
              const SizedBox(height: 24),
              _modeloCard(
                titulo: 'Huawei HG8145X6',
                subtitulo: 'Firmware Claro Chile',
                disponible: true,
                accent: _kAccent,
                onTap: () => setState(() {
                  _paso = _Paso.estado;
                  _errorConexion = null;
                }),
              ),
              const SizedBox(height: 12),
              _modeloCard(
                titulo: 'Askey',
                subtitulo: 'Próximamente',
                disponible: false,
                accent: _kDim,
                onTap: null,
              ),
              const SizedBox(height: 12),
              _modeloCard(
                titulo: 'ZTE',
                subtitulo: 'Próximamente',
                disponible: false,
                accent: _kDim,
                onTap: null,
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _kPanel,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, color: _kDim, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'El reporte y el certificado se generan a partir de la lectura directa de la ONT, '
                        'sin necesidad de caminar la casa.',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: _kDim,
                          height: 1.3,
                        ),
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

  Widget _modeloCard({
    required String titulo,
    required String subtitulo,
    required bool disponible,
    required Color accent,
    VoidCallback? onTap,
  }) {
    return Material(
      color: _kPanel,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: _kBorder),
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withValues(alpha: 0.4)),
                ),
                child: Icon(Icons.router, color: accent, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          titulo,
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (!disponible)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _kDim.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'BETA',
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _kDim,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitulo,
                      style: GoogleFonts.poppins(fontSize: 12, color: _kDim),
                    ),
                  ],
                ),
              ),
              if (disponible) const Icon(Icons.chevron_right, color: _kDim),
            ],
          ),
        ),
      ),
    );
  }

  // ─── PANTALLA ESTADO (¿Estás conectado a la ONT?) ─────────────────

  Widget _buildEstado() {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: const Text('Cobertura WiFi'),
        backgroundColor: _kPanel,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _paso = _Paso.modelo),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Text(
                '¿Estás conectado a la WiFi de la ONT?',
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Tu celular debe estar conectado a la red WiFi de la ONT para que la app pueda leer los dispositivos conectados.',
                style: GoogleFonts.poppins(fontSize: 13, color: _kDim, height: 1.4),
              ),
              if (_errorConexion != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                    border: Border.all(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Color(0xFFEF4444), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorConexion!,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 28),
              _btnEstadoSi(),
              const SizedBox(height: 14),
              _btnEstadoNo(),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _kPanel,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.wifi, color: _kDim, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'La ONT del cliente debe estar a 192.168.1.50 (red por defecto Claro). Si tu WiFi tiene otra IP, no podremos llegar a ella.',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: _kDim,
                          height: 1.3,
                        ),
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

  Widget _btnEstadoSi() {
    return Material(
      color: const Color(0xFF10B981),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: _conectarYEscanear,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 10),
              Text(
                'Sí, estoy conectado',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _btnEstadoNo() {
    return Material(
      color: _kPanel,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: _mostrarInstruccionesConexion,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            border: Border.all(color: _kBorder),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.settings, color: _kDim),
              const SizedBox(width: 10),
              Text(
                'No, conectar primero',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _mostrarInstruccionesConexion() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _kPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _kBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Cómo conectarte a la WiFi de la ONT',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              _instrPaso(1, 'Sal de la app y entra a Ajustes del celular.'),
              _instrPaso(2, 'Toca WiFi y busca la red de la ONT del cliente (suele ser "Claro_XXXXXX" o similar).'),
              _instrPaso(3, 'Conéctate ingresando la clave que vino con la instalación.'),
              _instrPaso(4, 'Vuelve aquí y toca "Sí, estoy conectado".'),
              const SizedBox(height: 18),
              Material(
                color: _kAccent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    alignment: Alignment.center,
                    child: Text(
                      'Entendido',
                      style: GoogleFonts.poppins(
                        color: Colors.black,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _instrPaso(int n, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: _kAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kAccent.withValues(alpha: 0.4)),
            ),
            child: Center(
              child: Text(
                '$n',
                style: GoogleFonts.poppins(
                  color: _kAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              texto,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── PANTALLA CONECTANDO ───────────────────────────────────────────

  Widget _buildConectando() {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: const Text('Cobertura WiFi'),
        backgroundColor: _kPanel,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: _kAccent),
              const SizedBox(height: 24),
              Text(
                _conectandoMensaje,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Esto suele tardar entre 5 y 15 segundos.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(color: _kDim, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Lógica de conexión + scrape ───────────────────────────────────

  /// Verifica si la ONT en `192.168.1.50` responde HTTP en <5 s.
  Future<bool> _ontReachable() async {
    try {
      final r = await http
          .get(Uri.parse('http://192.168.1.50/'))
          .timeout(const Duration(seconds: 5));
      return r.statusCode > 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> _conectarYEscanear() async {
    setState(() {
      _paso = _Paso.conectando;
      _devices = [];
      _neighbors = [];
      _ontNeighbours = [];
      _errorConexion = null;
      _conectandoMensaje = 'Conectando con la ONT...';
    });

    // Defaults para el cálculo de cobertura (ya no se preguntan al técnico).
    _construccion = _construccion.isNotEmpty ? _construccion : 'Albañilería';
    _tipoPropiedad = _tipoPropiedad.isNotEmpty ? _tipoPropiedad : 'casa1';
    _tamano = _tamano.isNotEmpty ? _tamano : 'med';

    // Paso 1: ¿llegamos a la ONT?
    final reachable = await _ontReachable();
    if (!mounted) return;
    if (!reachable) {
      setState(() {
        _paso = _Paso.estado;
        _errorConexion =
            'No se pudo llegar a la ONT (192.168.1.50). Verifica que tu celular esté conectado a su red WiFi.';
      });
      return;
    }

    setState(() => _conectandoMensaje = 'Iniciando sesión en la ONT...');

    // Paso 2: login + scrape
    try {
      final ok = await _ontWifi.login();
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _paso = _Paso.estado;
          _errorConexion =
              'La ONT respondió pero rechazó las credenciales. Probablemente cambió la clave de instalación.';
        });
        return;
      }
      setState(() => _conectandoMensaje = 'Leyendo dispositivos conectados...');
      _devices = await _ontWifi.getDevices();

      setState(() => _conectandoMensaje = 'Leyendo redes vecinas reportadas por la ONT...');
      _ontNeighbours = await _ontWifi.getNeighbours();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _paso = _Paso.estado;
        _errorConexion = 'Error al consultar la ONT: $e';
      });
      return;
    }

    setState(() => _conectandoMensaje = 'Escaneando WiFi del entorno (celular)...');

    try {
      _neighbors = await _neighborService.scan();
    } catch (_) {
      _neighbors = [];
    }

    if (!mounted) return;
    _computeMetrics();
    setState(() => _paso = _Paso.resultado);
  }

  // ─── Sheet "Generar Certificado": pide datos del domicilio + crea HTML ──

  Future<void> _abrirSheetCertificado() async {
    var tipo = _tipoPropiedad.isNotEmpty ? _tipoPropiedad : 'casa1';
    var tamano = _tamano.isNotEmpty ? _tamano : 'med';
    var construccion = _construccion.isNotEmpty ? _construccion : 'Albañilería';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            Widget chip(String label, String value, String selected, void Function(String) onTap) {
              final sel = selected == value;
              return Padding(
                padding: const EdgeInsets.only(right: 6, bottom: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => setSheet(() => onTap(value)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? _kAccent.withValues(alpha: 0.18) : Colors.white10,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: sel ? _kAccent : Colors.white24,
                        width: sel ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: sel ? _kAccent : Colors.white,
                        fontSize: 12,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              );
            }

            Widget label(String t) => Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 6),
              child: Text(t, style: const TextStyle(color: _kDim, fontSize: 12, fontWeight: FontWeight.w600)),
            );

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _kBorder,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Generar certificado',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Solo necesitamos características del domicilio. La OT y el resto de los datos los traemos de Supabase y del scrape.',
                      style: TextStyle(color: _kDim, fontSize: 12),
                    ),
                    label('Tipo de propiedad'),
                    Wrap(children: [
                      chip('🏠 Casa 1 piso', 'casa1', tipo, (v) => tipo = v),
                      chip('🏘 Casa 2 pisos', 'casa2', tipo, (v) => tipo = v),
                      chip('🏢 Departamento', 'depto', tipo, (v) => tipo = v),
                      chip('🏪 Local', 'local', tipo, (v) => tipo = v),
                    ]),
                    label('Tamaño aproximado'),
                    Wrap(children: [
                      chip('Pequeño −60m²', 'peq', tamano, (v) => tamano = v),
                      chip('Mediano 60-100m²', 'med', tamano, (v) => tamano = v),
                      chip('Grande +100m²', 'gra', tamano, (v) => tamano = v),
                    ]),
                    label('Material de construcción'),
                    Wrap(children: [
                      chip('🪵 Madera', 'Madera', construccion, (v) => construccion = v),
                      chip('🧱 Albañilería', 'Albañilería', construccion, (v) => construccion = v),
                      chip('🏗 Hormigón', 'Hormigón', construccion, (v) => construccion = v),
                    ]),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: Material(
                        color: _kAccent,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () async {
                            // Aplica selecciones al estado del screen para que el score
                            // se recalcule con el material correcto.
                            setState(() {
                              _tipoPropiedad = tipo;
                              _tamano = tamano;
                              _construccion = construccion;
                            });
                            _computeMetrics();
                            final html = await _renderCertHtml();
                            if (!sheetCtx.mounted) return;
                            Navigator.of(sheetCtx).pop();
                            if (!mounted) return;
                            Navigator.of(context).pushNamed(
                              '/certificado-wifi',
                              arguments: html,
                            );
                          },
                          child: const Center(
                            child: Text(
                              'Generar certificado',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<String> _renderCertHtml() async {
    final prefs = await SharedPreferences.getInstance();
    final rut = prefs.getString('rut_tecnico') ?? '';
    final nombre = prefs.getString('nombre_tecnico') ?? '';

    // OT y tipo de orden desde produccion_crea (Supabase) por RUT.
    String? ot;
    String? tipoOrden;
    if (rut.isNotEmpty) {
      try {
        final r = await NyquistService().buscarAccessIdPorRut(rut);
        ot = r?['orden_de_trabajo'];
        tipoOrden = r?['tipo_red_producto'];
      } catch (_) {}
    }

    return buildCertificadoHtml(CertContext(
      devices: _devices,
      ontNeighbours: _ontNeighbours,
      localNeighbours: _neighbors,
      score: _score,
      veredicto: CoverageCalculator.veredicto(_score, _tieneDecoEn24g),
      tipoPropiedad: _tipoPropiedad,
      tamano: _tamano,
      construccion: _construccion,
      ordenTrabajo: (ot == null || ot.isEmpty) ? null : ot,
      tipoOrden: (tipoOrden == null || tipoOrden.isEmpty) ? null : tipoOrden,
      ontModelo: _ontWifi.ontModel,
      ontSerial: _ontWifi.ontSerial,
      ontMac: _ontWifi.ontMac,
      tecnicoRut: rut.isEmpty ? null : rut,
      tecnicoNombre: nombre.isEmpty ? null : nombre,
      recomendacionExtensor:
          _recomendacionExtensor.isEmpty ? null : _recomendacionExtensor,
    ));
  }

  // ─── PANTALLA CONTEXTO ─────────────────────────────────────────────

  Widget _buildContexto() {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: const Text('Cobertura WiFi'),
        backgroundColor: _kPanel,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cuéntanos sobre\nla instalación',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                  height: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '3 preguntas rápidas para calibrar el análisis',
              style: TextStyle(color: _kDim, fontSize: 13),
            ),
            const SizedBox(height: 24),
            _label('Tipo de propiedad'),
            _chipRow([
              _ChipOpt('🏠 Casa 1 piso', 'casa1', _tipoPropiedad, (v) {
                setState(() => _tipoPropiedad = v);
              }),
              _ChipOpt('🏘 Casa 2 pisos', 'casa2', _tipoPropiedad, (v) {
                setState(() => _tipoPropiedad = v);
              }),
              _ChipOpt('🏢 Departamento', 'depto', _tipoPropiedad, (v) {
                setState(() => _tipoPropiedad = v);
              }),
              _ChipOpt('🏪 Local', 'local', _tipoPropiedad, (v) {
                setState(() => _tipoPropiedad = v);
              }),
            ]),
            const SizedBox(height: 20),
            _label('Tamaño aproximado'),
            _chipRow([
              _ChipOpt('📐 Pequeño -60m²', 'peq', _tamano, (v) {
                setState(() => _tamano = v);
              }),
              _ChipOpt('📐 Mediano 60-100m²', 'med', _tamano, (v) {
                setState(() => _tamano = v);
              }),
              _ChipOpt('📐 Grande +100m²', 'gra', _tamano, (v) {
                setState(() => _tamano = v);
              }),
            ]),
            const SizedBox(height: 20),
            _label('Tipo de construcción'),
            _chipRow([
              _ChipOpt('🪵 Madera', 'Madera', _construccion, (v) {
                setState(() => _construccion = v);
              }),
              _ChipOpt('🧱 Albañilería', 'Albañilería', _construccion, (v) {
                setState(() => _construccion = v);
              }),
              _ChipOpt('🏗 Hormigón', 'Hormigón', _construccion, (v) {
                setState(() => _construccion = v);
              }),
            ]),
            const SizedBox(height: 6),
            Text(
              'Afecta la penetración de señal y el radio de cobertura',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: _puedeIniciar
                      ? const LinearGradient(
                          colors: [Color(0xFF00D9FF), Color(0xFF0099CC)],
                        )
                      : null,
                  color: _puedeIniciar ? null : Colors.grey[800],
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _puedeIniciar ? _iniciarEscaneo : null,
                    child: const Center(
                      child: Text(
                        'Iniciar Análisis →',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          t,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      );

  Widget _chipRow(List<_ChipOpt> opts) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: opts
          .map(
            (o) => _ChoiceChip(
              label: o.label,
              value: o.value,
              selected: o.current == o.value,
              onTap: () => o.onSelect(o.value),
            ),
          )
          .toList(),
    );
  }

  // ─── ESCANEANDO ────────────────────────────────────────────────────

  Widget _buildEscaneando() {
    final n = CoverageCalculator.factorMaterial[_construccionEfectiva] ?? 2.4;
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _radarController,
            builder: (context, _) {
              return CustomPaint(
                painter: _RadarPainter(
                  animation: _radarController,
                  devices: _devices,
                  materialFactor: n,
                ),
                child: const SizedBox.expand(),
              );
            },
          ),
          Positioned(
            top: 48,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0x99000000),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_countdown}s',
                style: GoogleFonts.shareTechMono(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 56,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: Text(
                _scanMsgs[_scanMsgIndex],
                key: ValueKey(_scanMsgIndex),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _flashOpacity,
                duration: const Duration(milliseconds: 150),
                child: Container(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── RESULTADO TÉCNICO ─────────────────────────────────────────────

  Widget _buildResultadoTecnico() {
    final cond = _tieneDecoEn24g;
    final scoreColor = _colorScore(cond);
    final veredicto = CoverageCalculator.veredicto(_score, cond);
    final decoMal = _devices.where(
      (d) => d.esDecodificador && !d.es5GHz && !d.esCableado,
    );

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kPanel,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Cobertura WiFi'),
        actions: [
          TextButton(
            onPressed: _abrirSheetCertificado,
            child: const Text(
              '📄 Certificado',
              style: TextStyle(color: _kAccent),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _modoCliente = true),
            child: const Text(
              '👁 Mostrar al Cliente',
              style: TextStyle(color: _kAccent),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _secScore(scoreColor, veredicto, cond),
            if (cond && decoMal.isNotEmpty) _alertaDeco24(decoMal.first.name),
            const SizedBox(height: 20),
            _secRadios(),
            if (_recomendacionExtensor.isNotEmpty) ...[
              const SizedBox(height: 12),
              _cardRecomendacion(),
            ],
            const SizedBox(height: 20),
            _secHeatmap(),
            const SizedBox(height: 20),
            _secMapa(),
            if (_ontNeighbours.isNotEmpty) ...[
              const SizedBox(height: 20),
              _secVecinosOnt(),
            ],
            const SizedBox(height: 20),
            _secDispositivos(),
            const SizedBox(height: 20),
            _secRf(),
            const SizedBox(height: 20),
            _secObservaciones(),
          ],
        ),
      ),
    );
  }

  Widget _secScore(Color scoreColor, String veredicto, bool cond) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          height: 88,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: _score / 100,
                  strokeWidth: 8,
                  backgroundColor: Colors.white12,
                  color: scoreColor,
                ),
              ),
              Text(
                '$_score',
                style: GoogleFonts.rajdhani(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: scoreColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                veredicto,
                style: TextStyle(
                  color: scoreColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (cond)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '⚠️ Certificación Condicional',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _alertaDeco24(String nombre) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x33DC2626),
        border: const Border(
          left: BorderSide(color: Color(0xFFDC2626), width: 4),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '🚨 $nombre conectado en 2.4GHz — debe migrar a 5GHz',
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
  }

  Widget _secRadios() {
    final c = _construccionEfectiva;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Radio de Cobertura por Banda',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...['5 GHz', '2.4 GHz'].map((banda) {
          final vecinos = banda == '5 GHz'
              ? _neighbors.where((w) => w.es5GHz).length
              : _neighbors.where((w) => !w.es5GHz).length;
          final radios = CoverageCalculator.radiosEfectivos(banda, c, vecinos);
          final rf = CoverageCalculator.factorRuido(vecinos);
          final pct = ((1 - rf) * 100).round();
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildSegmentosCard(banda, vecinos, pct, radios),
          );
        }),
      ],
    );
  }

  Widget _buildSegmentosCard(
    String banda,
    int vecinos,
    int pctReduccion,
    List<double> radios,
  ) {
    final ex = radios[0];
    final bu = radios[1];
    return Card(
      color: _kPanel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _kBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  banda,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$vecinos vecinos',
                  style: const TextStyle(color: _kDim, fontSize: 12),
                ),
                const Spacer(),
                Text(
                  '-$pctReduccion% RF',
                  style: GoogleFonts.shareTechMono(
                    color: _kAccent,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _segmento(
                    '🟢',
                    'Excelente',
                    ex.toStringAsFixed(0),
                    'Hasta ${ex.toStringAsFixed(0)} m',
                    'm',
                  ),
                ),
                Expanded(
                  child: _segmento(
                    '🟡',
                    'Buena',
                    bu.toStringAsFixed(0),
                    'Hasta ${bu.toStringAsFixed(0)} m',
                    'm',
                  ),
                ),
                Expanded(
                  child: _segmento(
                    '🔴',
                    'Insuficiente',
                    '—',
                    'Más allá de buena',
                    '',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Base: ${CoverageCalculator.radiosBase[_construccionEfectiva]![banda]![0].toStringAsFixed(0)} / ${CoverageCalculator.radiosBase[_construccionEfectiva]![banda]![1].toStringAsFixed(0)} m · ajuste RF ${CoverageCalculator.factorRuido(_neighbors.where((w) => banda == '5 GHz' ? w.es5GHz : !w.es5GHz).length).toStringAsFixed(2)}',
              style: GoogleFonts.shareTechMono(
                color: _kDim,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segmento(
    String emoji,
    String label,
    String metros,
    String nota,
    String unit,
  ) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: _kDim, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Text(
          metros == '—' ? '—' : '$metros$unit',
          style: GoogleFonts.rajdhani(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          nota,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _kDim, fontSize: 9),
        ),
      ],
    );
  }

  Widget _cardRecomendacion() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x33F59E0B),
        borderRadius: BorderRadius.circular(8),
        border: const Border(
          left: BorderSide(color: Color(0xFFFF6B35), width: 4),
        ),
      ),
      child: Text(
        '💡 $_recomendacionExtensor',
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
  }

  Widget _secMapa() {
    final wifiDevs = _devices.where((d) => !d.esCableado).toList()
      ..sort((a, b) => a.rssi.compareTo(b.rssi)); // peor RSSI primero
    final cableados = _devices.where((d) => d.esCableado).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Mapa de cobertura',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _devices.isEmpty
              ? 'No se detectaron dispositivos. Verifica la conexión a la ONT.'
              : 'Potencia real reportada por la ONT (${_devices.length} dispositivo${_devices.length == 1 ? "" : "s"}).',
          style: const TextStyle(color: _kDim, fontSize: 12),
        ),
        const SizedBox(height: 12),
        if (wifiDevs.isNotEmpty) ...[
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2.4,
            children: wifiDevs.map(_mapaTile).toList(),
          ),
          const SizedBox(height: 10),
          _mapaLeyenda(),
        ],
        if (cableados.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF00D9FF).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFF00D9FF).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.cable, color: _kAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${cableados.length} dispositivo${cableados.length == 1 ? "" : "s"} por cable (sin lectura RSSI)',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _mapaTile(OntDevice d) {
    final color = d.colorCalidad;
    final mostrar = d.rssiKnown;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(_iconoTipo(d), style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  d.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                mostrar ? '${d.rssi} dBm' : 'sin lectura',
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                d.banda,
                style: const TextStyle(color: _kDim, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mapaLeyenda() {
    Widget chip(Color c, String label) => Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(color: _kDim, fontSize: 10)),
            ],
          ),
        );
    return Wrap(
      children: [
        chip(const Color(0xFF10B981), '≥ −60 Excelente'),
        chip(const Color(0xFFF59E0B), '−61 a −70 Buena'),
        chip(const Color(0xFFFF6B35), '−71 a −75 Marginal'),
        chip(const Color(0xFFEF4444), '< −75 Crítico'),
      ],
    );
  }

  Widget _secDispositivos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Dispositivos',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        ..._devices.map(_cardDispositivo),
      ],
    );
  }

  Widget _cardDispositivo(OntDevice d) {
    final n = CoverageCalculator.factorMaterial[_construccionEfectiva] ?? 2.4;
    final dist = d.distanciaMetros(n);
    final deco24 = d.esDecodificador && !d.es5GHz && !d.esCableado;
    final border = deco24
        ? Border.all(color: const Color(0xFFDC2626), width: 2)
        : Border.all(color: _kBorder);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: deco24 ? const Color(0x22DC2626) : _kPanel,
        borderRadius: BorderRadius.circular(10),
        border: border,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_iconoTipo(d), style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${d.mac} · ${d.serieEstimada}',
                  style: const TextStyle(color: _kDim, fontSize: 11),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (d.esDecodificador)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: d.es5GHz
                              ? const Color(0xFF1E3A5F)
                              : const Color(0xFFDC2626),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          d.es5GHz ? '5 GHz ✓' : '2.4 GHz ✗',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    if (d.esCableado)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green[800],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '📎 Cableado',
                          style: TextStyle(color: Colors.white, fontSize: 10),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'RSSI ${d.rssi} dBm · ${d.calidad} · ${d.esCableado ? '0' : dist.toStringAsFixed(1)} m',
                  style: const TextStyle(color: _kDim, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _iconoTipo(OntDevice d) {
    if (d.name.toLowerCase().contains('ont')) return '📡';
    if (d.esDecodificador) return '📺';
    if (d.esExtensor) return '🔁';
    return '💻';
  }

  Widget _secRf() {
    final n5 = _neighbors.where((w) => w.es5GHz).length;
    final total = _neighbors.length;
    final rf = CoverageCalculator.factorRuido(total);
    final pct = ((1 - rf) * 100).round();
    final canal5 =
        n5 > 8 ? 'Congestionado' : 'Limpio';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Entorno RF',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _miniRfCard(
                'Redes vecinas',
                '$total',
              ),
            ),
            Expanded(
              child: _miniRfCard(
                'Canal 5GHz',
                canal5,
              ),
            ),
            Expanded(
              child: _miniRfCard(
                'Reducción RF',
                '$pct%',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _miniRfCard(String title, String value) {
    return Card(
      color: _kPanel,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _kDim, fontSize: 10),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: GoogleFonts.shareTechMono(
                color: Colors.white,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  CoverageFloorPlan get _floorPlan => CoverageFloorPlan(
        tipoPropiedad: _tipoPropiedad.isNotEmpty ? _tipoPropiedad : 'casa1',
        tamano: _tamano.isNotEmpty ? _tamano : 'med',
        construccion: _construccionEfectiva,
        vecinos5g: _neighbors.where((w) => w.es5GHz).length,
        devices: _devices,
        banda: '5 GHz',
      );

  Widget _secHeatmap() {
    final plan = _floorPlan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Plano de cobertura',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          plan.subtitulo,
          style: const TextStyle(color: _kDim, fontSize: 12),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 1.45,
            child: CustomPaint(
              painter: _FloorPlanHeatmapPainter(plan: plan),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _mapaLeyenda(),
        const SizedBox(height: 16),
        const Text(
          'Vista radial (dispositivos ONT)',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Cada punto es un cliente WiFi reportado por la ONT.',
          style: TextStyle(color: _kDim, fontSize: 11),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 1.5,
            child: CustomPaint(
              painter: _HeatmapRealPainter(devices: _devices),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _secVecinosOnt() {
    final vecinos = [..._ontNeighbours]
      ..sort((a, b) => (b.rssiDbm ?? -200).compareTo(a.rssiDbm ?? -200));
    final fuertes = vecinos.where((v) => (v.rssiDbm ?? -200) > -40).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Redes vecinas (vista de la ONT)',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${vecinos.length} red${vecinos.length == 1 ? "" : "es"} detectada${vecinos.length == 1 ? "" : "s"}.',
          style: const TextStyle(color: _kDim, fontSize: 12),
        ),
        if (fuertes.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.12),
              border: Border.all(
                color: const Color(0xFFEF4444).withValues(alpha: 0.5),
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFEF4444), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Interferencia RF severa detectada',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Hay ${fuertes.length} red${fuertes.length == 1 ? "" : "es"} vecina${fuertes.length == 1 ? "" : "s"} con señal mayor a −40 dBm: ${fuertes.map((v) => '"${v.displayName}" (${v.bandaUI}, ${v.rssiDbm} dBm)').join(', ')}. Esto degrada el rendimiento WiFi del cliente, especialmente si comparten canal.',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: _kPanel,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kBorder),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Row(
                  children: const [
                    Expanded(flex: 4, child: Text('SSID',
                        style: TextStyle(color: _kDim, fontSize: 11, fontWeight: FontWeight.w600))),
                    Expanded(flex: 2, child: Text('Banda',
                        style: TextStyle(color: _kDim, fontSize: 11, fontWeight: FontWeight.w600))),
                    Expanded(flex: 2, child: Text('Canal',
                        style: TextStyle(color: _kDim, fontSize: 11, fontWeight: FontWeight.w600))),
                    Expanded(flex: 2, child: Text('RSSI',
                        style: TextStyle(color: _kDim, fontSize: 11, fontWeight: FontWeight.w600))),
                  ],
                ),
              ),
              const Divider(height: 1, color: _kBorder),
              ...vecinos.take(15).map((v) => _vecinoRow(v)),
              if (vecinos.length > 15)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    '+ ${vecinos.length - 15} red${vecinos.length - 15 == 1 ? "" : "es"} más con menor señal',
                    style: const TextStyle(color: _kDim, fontSize: 11, fontStyle: FontStyle.italic),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _vecinoRow(OntNeighbour v) {
    final rssi = v.rssiDbm ?? -200;
    final color = rssi >= -50
        ? const Color(0xFFEF4444)
        : rssi >= -65
            ? const Color(0xFFF59E0B)
            : _kDim;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              v.displayName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              v.bandaUI,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              v.channel?.toString() ?? '-',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              v.rssiDbm != null ? '${v.rssiDbm} dBm' : '-',
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _secObservaciones() {
    final obs = <String>[];

    if (_tieneDecoEn24g) {
      obs.add('🔴 Decodificador en 2.4 GHz: migrar a 5 GHz.');
    }
    for (final d in _devices) {
      if (d.esDecodificador && d.es5GHz && !d.esCableado) {
        obs.add('🟢 ${d.name}: deco en 5 GHz correcto.');
      }
    }
    if (_devices.any((d) => d.esCableado && d.esExtensor)) {
      obs.add('🟢 Extensor con conexión cableada detectado.');
    }
    final interf = _neighborService.interferencia2g(_neighbors) +
        _neighborService.interferencia5g(_neighbors);
    if (interf > 6) {
      obs.add('🟡 Interferencia RF elevada en el entorno ($interf redes fuertes).');
    }
    if (_recomendacionExtensor.isNotEmpty) {
      obs.add('ℹ️ $_recomendacionExtensor');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Observaciones',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...obs.map(
          (o) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '• $o',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  // ─── MODO CLIENTE ──────────────────────────────────────────────────

  Widget _buildModoCliente() {
    final cond = _tieneDecoEn24g;
    final scoreColor = _colorScore(cond);
    final veredicto = CoverageCalculator.veredicto(_score, cond);
    final decos = _devices.where((d) => d.esDecodificador).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF060D1A),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
              child: Column(
                children: [
                  if (_devices.where((d) => !d.esCableado).isNotEmpty) ...[
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 2.4,
                      children: (_devices.where((d) => !d.esCableado).toList()
                            ..sort((a, b) => a.rssi.compareTo(b.rssi)))
                          .map(_mapaTile)
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$_score',
                        style: GoogleFonts.rajdhani(
                          fontSize: 72,
                          fontWeight: FontWeight.bold,
                          color: scoreColor,
                        ),
                      ),
                      Text(
                        '/100',
                        style: GoogleFonts.rajdhani(
                          fontSize: 24,
                          color: _kDim,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    cond ? '⚠️ Requiere Atención' : veredicto,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: cond ? const Color(0xFFDC2626) : scoreColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (decos.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: decos.map((d) {
                        final emoji = d.rssi >= -60
                            ? '🟢'
                            : d.rssi >= -70
                                ? '🟡'
                                : '🔴';
                        final mal = d.esDecodificador &&
                            !d.es5GHz &&
                            !d.esCableado;
                        return Chip(
                          backgroundColor: mal
                              ? const Color(0xFFDC2626)
                              : _kPanel,
                          label: Text(
                            '$emoji ${d.displayName} · ${d.calidad}${mal ? " ⚠️" : ""}',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    _score >= 75 && !cond
                        ? '✓ Tu instalación está certificada'
                        : '⚠️ Se requiere ajuste en la instalación',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _score >= 75 && !cond
                          ? const Color(0xFF10B981)
                          : const Color(0xFFEF4444),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0x1AFFFFFF),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => setState(() => _modoCliente = false),
                child: const Text('← Volver'),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0x1AFFFFFF),
                  foregroundColor: Colors.white,
                ),
                onPressed: () =>
                    Navigator.of(context).pushNamed('/certificado-wifi'),
                child: const Text('📄 Certificado'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Chips contexto ────────────────────────────────────────────────

class _ChipOpt {
  const _ChipOpt(this.label, this.value, this.current, this.onSelect);

  final String label;
  final String value;
  final String current;
  final void Function(String) onSelect;
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF0D2241) : const Color(0xFF0D1B2A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? const Color(0xFF00D9FF) : const Color(0xFF1E3A5F),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
      ),
    );
  }
}

// ─── Radar painter ─────────────────────────────────────────────────

/// Plano de planta con heatmap simulado (sin recorrido del técnico).
class _FloorPlanHeatmapPainter extends CustomPainter {
  _FloorPlanHeatmapPainter({required this.plan});
  final CoverageFloorPlan plan;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF04091a),
    );

    final cellW = size.width / CoverageFloorPlan.gridCols;
    final cellH = size.height / CoverageFloorPlan.gridRows;

    for (var row = 0; row < CoverageFloorPlan.gridRows; row++) {
      for (var col = 0; col < CoverageFloorPlan.gridCols; col++) {
        final nx = (col + 0.5) / CoverageFloorPlan.gridCols;
        final ny = (row + 0.5) / CoverageFloorPlan.gridRows;
        if (plan.roomAt(nx, ny) == null) continue;
        final rssi = plan.rssiGrid[row][col];
        final color = CoverageFloorPlan.colorForRssi(rssi);
        canvas.drawRect(
          Rect.fromLTWH(col * cellW, row * cellH, cellW + 0.5, cellH + 0.5),
          Paint()..color = color.withValues(alpha: 0.42),
        );
      }
    }

    final wallP = Paint()
      ..color = const Color(0xFF7DD3FC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    for (final room in plan.rooms) {
      final r = Rect.fromLTRB(
        room.rect.left * size.width,
        room.rect.top * size.height,
        room.rect.right * size.width,
        room.rect.bottom * size.height,
      );
      canvas.drawRect(r, wallP);

      final tp = TextPainter(
        text: TextSpan(
          text: room.label,
          style: TextStyle(
            color: room.ontRoom ? const Color(0xFF00D9FF) : const Color(0xAAFFFFFF),
            fontSize: 10,
            fontWeight: room.ontRoom ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: r.width - 8);
      tp.paint(canvas, Offset(r.left + 6, r.top + 6));
    }

    final ont = Offset(
      plan.ontCenter.dx * size.width,
      plan.ontCenter.dy * size.height,
    );
    canvas.drawCircle(
      ont,
      22,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x6600D9FF), Color(0x0000D9FF)],
        ).createShader(Rect.fromCircle(center: ont, radius: 22)),
    );
    canvas.drawCircle(ont, 9, Paint()..color = const Color(0xFF00D9FF));
    final ontTp = TextPainter(
      text: const TextSpan(
        text: 'ONT',
        style: TextStyle(
          color: Color(0xFF00D9FF),
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    ontTp.paint(canvas, Offset(ont.dx - ontTp.width / 2, ont.dy + 14));
  }

  @override
  bool shouldRepaint(covariant _FloorPlanHeatmapPainter old) => old.plan != plan;
}

/// Heatmap radial con data REAL: ONT al centro, devices posicionados por
/// hash(MAC) (ángulo estable) y RSSI (radio = distancia inferida).
class _HeatmapRealPainter extends CustomPainter {
  _HeatmapRealPainter({required this.devices});
  final List<OntDevice> devices;

  @override
  void paint(Canvas canvas, Size size) {
    // Fondo glassmorphic dark.
    final bg = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFF0a1628), Color(0xFF04091a)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Offset.zero & size, bg);

    // Grid sutil
    final gridP = Paint()
      ..color = const Color(0x1100D9FF)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridP);
    }
    for (double y = 0; y < size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridP);
    }

    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final maxR = math.min(size.width, size.height * 1.4) * 0.42;

    // Anillos: −60, −70, −80
    final ringP = Paint()
      ..color = const Color(0x447DD3FC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    void ring(double frac, String lbl) {
      canvas.drawCircle(Offset(cx, cy), maxR * frac, ringP);
      final tp = TextPainter(
        text: TextSpan(
          text: lbl,
          style: const TextStyle(color: Color(0x887DD3FC), fontSize: 9, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx + maxR * frac - tp.width - 4, cy - tp.height - 2));
    }
    ring(1 / 3, '−60');
    ring(2 / 3, '−70');
    ring(1.0, '−80');

    // ONT al centro
    final wifi = devices.where((d) => !d.esCableado && d.rssiKnown).toList();
    for (final d in wifi) {
      final rssi = d.rssi.clamp(-90, -30);
      final radial = (-30 - rssi) / 60.0; // 0..1
      final hash = d.mac.hashCode.abs();
      final angle = (hash % 360) * math.pi / 180.0;
      final pos = Offset(cx + math.cos(angle) * maxR * radial,
          cy + math.sin(angle) * maxR * radial);

      // Halo difuso
      final glow = Paint()
        ..shader = RadialGradient(
          colors: [
            d.colorCalidad.withValues(alpha: 0.55),
            d.colorCalidad.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: pos, radius: 38))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
      canvas.drawCircle(pos, 38, glow);

      // Punto
      canvas.drawCircle(pos, 6, Paint()..color = d.colorCalidad);
      canvas.drawCircle(
        pos,
        6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0x66FFFFFF),
      );

      // Label compacto
      final shortName = d.displayName.length > 10
          ? '${d.displayName.substring(0, 9)}…'
          : d.displayName;
      final tp = TextPainter(
        text: TextSpan(
          text: '$shortName · ${d.rssi}dBm',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final lblBg = Paint()
        ..color = const Color(0xCC0a1628);
      final lblOffset = Offset(pos.dx - tp.width / 2, pos.dy + 12);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(lblOffset.dx - 4, lblOffset.dy - 1, tp.width + 8, tp.height + 2),
          const Radius.circular(4),
        ),
        lblBg,
      );
      tp.paint(canvas, lblOffset);
    }

    // ONT al centro (después de los devices, para que quede arriba)
    canvas.drawCircle(
      Offset(cx, cy),
      18,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0x6600D9FF),
            const Color(0x0000D9FF),
          ],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: 18)),
    );
    canvas.drawCircle(Offset(cx, cy), 8, Paint()..color = const Color(0xFF00D9FF));
    final ontTp = TextPainter(
      text: const TextSpan(
        text: 'ONT',
        style: TextStyle(
          color: Color(0xFF00D9FF),
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    ontTp.paint(canvas, Offset(cx - ontTp.width / 2, cy + 14));

    if (wifi.isEmpty) {
      final tp = TextPainter(
        text: const TextSpan(
          text: 'Sin clientes WiFi para graficar',
          style: TextStyle(color: Color(0x887DD3FC), fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset((size.width - tp.width) / 2, size.height - tp.height - 12),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapRealPainter old) =>
      old.devices != devices;
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.animation,
    required this.devices,
    required this.materialFactor,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final List<OntDevice> devices;
  final double materialFactor;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    const maxR = 180.0;

    for (final r in [80.0, 130.0, 180.0]) {
      _drawDashedCircle(
        canvas,
        c,
        r,
        Paint()
          ..color = const Color(0x2600C8FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }

    final angle = animation.value * 2 * math.pi;
    final len = maxR * 0.95;
    final p2 = c + Offset(math.cos(angle - math.pi / 2), math.sin(angle - math.pi / 2)) * len;

    final grad = ui.Gradient.linear(
      c,
      p2,
      [
        const Color(0x00FFFFFF),
        const Color(0xCC00C8FF),
      ],
    );
    canvas.drawLine(
      c,
      p2,
      Paint()
        ..shader = grad
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawCircle(
      c,
      6,
      Paint()..color = const Color(0xFF00D9FF),
    );

    final total = devices.length;
    if (total == 0) return;
    for (var i = 0; i < total; i++) {
      final d = devices[i];
      final ang = i * (2 * math.pi / total);
      final dist = math.min(
        160.0,
        d.distanciaMetros(materialFactor) * 10,
      );
      final pos = c +
          Offset(
            math.cos(ang - math.pi / 2),
            math.sin(ang - math.pi / 2),
          ) *
              dist;
      canvas.drawCircle(
        pos,
        6,
        Paint()..color = d.colorCalidad,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: '${d.name.isEmpty ? "?" : d.name}\n${d.rssi} dBm',
          style: const TextStyle(color: Colors.white70, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos + const Offset(8, -8));
    }
  }

  void _drawDashedCircle(Canvas canvas, Offset c, double r, Paint paint) {
    const dash = 0.35;
    const gap = 0.22;
    var a = 0.0;
    while (a < 2 * math.pi) {
      final sweep = math.min(dash, 2 * math.pi - a);
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        a - math.pi / 2,
        sweep,
        false,
        paint,
      );
      a += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.devices != devices ||
      oldDelegate.materialFactor != materialFactor;
}


import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:agente_desconexiones/services/coverage_calculator.dart';
import 'package:agente_desconexiones/services/ont_wifi_service.dart';
import 'package:agente_desconexiones/services/wifi_neighbor_service.dart';

enum _Paso { contexto, escaneando, resultado }

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
  int _score = 0;
  bool _tieneDecoEn24g = false;
  String _recomendacionExtensor = '';

  int _countdown = 60;
  Timer? _timer;
  Timer? _msgTimer;

  _Paso _paso = _Paso.contexto;

  int _scanMsgIndex = 0;
  double _flashOpacity = 0;

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
      case _Paso.contexto:
        return _buildContexto();
      case _Paso.escaneando:
        return _buildEscaneando();
      case _Paso.resultado:
        return _buildResultadoTecnico();
    }
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
            onPressed: () =>
                Navigator.of(context).pushNamed('/certificado-wifi'),
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
            _secMapa(),
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
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 200,
            width: double.infinity,
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _CoveragePainter(
                    devices: _devices,
                    construccion: _construccionEfectiva,
                    neighbors: _neighbors,
                    pulse: _pulseController.value,
                  ),
                  child: const SizedBox.expand(),
                );
              },
            ),
          ),
        ),
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
                  d.name.isEmpty ? '(sin nombre)' : d.name,
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
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 280,
                      width: double.infinity,
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, _) {
                          return CustomPaint(
                            painter: _CoveragePainter(
                              devices: _devices,
                              construccion: _construccionEfectiva,
                              neighbors: _neighbors,
                              pulse: _pulseController.value,
                            ),
                            child: const SizedBox.expand(),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
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
                            '$emoji ${d.name.isEmpty ? "Deco" : d.name} · ${d.calidad}${mal ? " ⚠️" : ""}',
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

// ─── Coverage map painter ──────────────────────────────────────────

class _CoveragePainter extends CustomPainter {
  _CoveragePainter({
    required this.devices,
    required this.construccion,
    required this.neighbors,
    required this.pulse,
  });

  final List<OntDevice> devices;
  final String construccion;
  final List<WifiNeighbor> neighbors;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF060D1A);
    canvas.drawRect(Offset.zero & size, bg);

    for (double x = 0; x < size.width; x += 30) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = const Color(0x0D00C8FF)
          ..strokeWidth = 1,
      );
    }
    for (double y = 0; y < size.height; y += 30) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = const Color(0x0D00C8FF)
          ..strokeWidth = 1,
      );
    }

    final ont = Offset(40, size.height / 2);
    final nMat = CoverageCalculator.factorMaterial[construccion] ?? 2.4;
    final vec5 = neighbors.where((w) => w.es5GHz).length;
    final vec24 = neighbors.where((w) => !w.es5GHz).length;
    final r5 = CoverageCalculator.radiosEfectivos('5 GHz', construccion, vec5);
    final r24 = CoverageCalculator.radiosEfectivos('2.4 GHz', construccion, vec24);

    final scale = 8.0;
    _drawRing(canvas, ont, r5[0] * scale, const Color(0x6610B981));
    _drawRing(canvas, ont, r5[1] * scale, const Color(0x4DF59E0B));
    _drawRingDashed(canvas, ont, r24[0] * scale, const Color(0x3300C8FF));
    _drawRingDashed(canvas, ont, r24[1] * scale, const Color(0x1F00C8FF));

    var wifiIdx = 0;
    final wifiCount = devices.where((d) => !d.esCableado).length;
    for (final d in devices) {
      if (d.esCableado) continue;
      final ang = wifiCount > 0
          ? wifiIdx * (2 * math.pi / wifiCount)
          : 0.0;
      wifiIdx++;
      final distPx = math.min(
        80.0,
        d.distanciaMetros(nMat) * 8,
      );
      final pos = ont +
          Offset(
            math.cos(ang - math.pi / 2),
            math.sin(ang - math.pi / 2),
          ) *
              distPx;

      final g = RadialGradient(
        colors: [
          d.colorCalidad.withValues(alpha: 0.6),
          d.colorCalidad.withValues(alpha: 0.0),
        ],
      );
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.drawCircle(
        Offset.zero,
        28,
        Paint()
          ..shader = g.createShader(Rect.fromCircle(center: Offset.zero, radius: 28))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
      );
      canvas.restore();

      final decoMal = d.esDecodificador && !d.es5GHz && !d.esCableado;
      canvas.drawCircle(
        pos,
        5,
        Paint()
          ..color = decoMal ? const Color(0xFFDC2626) : d.colorCalidad,
      );
      if (decoMal) {
        final tp = TextPainter(
          text: const TextSpan(text: '⚠️', style: TextStyle(fontSize: 10)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, pos + const Offset(6, -4));
      }
      final label = TextPainter(
        text: TextSpan(
          text: '${d.name.isEmpty ? "?" : d.name}\n${d.distanciaMetros(nMat).toStringAsFixed(1)} m',
          style: const TextStyle(color: Colors.white70, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, pos + const Offset(8, 6));
    }

    final radioBuena5 = r5[1];
    final hayMuro = devices.any(
      (d) =>
          !d.esCableado && d.distanciaMetros(nMat) > radioBuena5,
    );
    if (hayMuro) {
      final x = size.width * 0.6;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = Colors.white24
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
      final tp = TextPainter(
        text: const TextSpan(
          text: 'muro',
          style: TextStyle(color: Colors.white38, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + 4, size.height / 2 - 20));
    }

    final pr = 7 + pulse * 3;
    canvas.drawCircle(
      ont,
      pr,
      Paint()
        ..color = const Color(0x4400D9FF)
        ..style = PaintingStyle.stroke,
    );
    canvas.drawCircle(
      ont,
      7,
      Paint()..color = const Color(0xFF00D9FF),
    );
    final ontLabel = TextPainter(
      text: const TextSpan(text: '📡 ONT'),
      textDirection: TextDirection.ltr,
    )..layout();
    ontLabel.paint(canvas, ont + const Offset(10, -8));

    _labelRings(canvas, ont, r5, r24, scale);
  }

  void _drawRing(Canvas canvas, Offset c, double r, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(c, r, paint);
  }

  void _drawRingDashed(Canvas canvas, Offset c, double r, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    const dash = 0.4;
    const gap = 0.25;
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

  void _labelRings(
    Canvas canvas,
    Offset ont,
    List<double> r5,
    List<double> r24,
    double scale,
  ) {
    void drawLabel(String t, double radius) {
      final tp = TextPainter(
        text: TextSpan(
          text: t,
          style: const TextStyle(color: Colors.white24, fontSize: 8),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, ont + Offset(radius * scale - 10, 0));
    }

    drawLabel('${r5[0].toStringAsFixed(0)}m 5G', r5[0]);
    drawLabel('${r24[0].toStringAsFixed(0)}m 2G', r24[0]);
  }

  @override
  bool shouldRepaint(covariant _CoveragePainter oldDelegate) =>
      oldDelegate.devices != devices ||
      oldDelegate.pulse != pulse ||
      oldDelegate.construccion != construccion ||
      oldDelegate.neighbors != neighbors;
}

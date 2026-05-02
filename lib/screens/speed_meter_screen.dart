// ============================================================================
// PANTALLA
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/speed_measurement_service.dart';

enum TestPhase { idle, download, upload, done }

class SpeedMeterScreen extends StatefulWidget {
  const SpeedMeterScreen({Key? key}) : super(key: key);

  @override
  State<SpeedMeterScreen> createState() => _SpeedMeterScreenState();
}

class _SpeedMeterScreenState extends State<SpeedMeterScreen>
    with TickerProviderStateMixin {
  final _service = SpeedTestService();

  TestPhase _phase = TestPhase.idle;
  String _status = 'Listo para medir';
  double _displaySpeed = 0;

  double _downloadRaw = 0;
  double _downloadCalibrated = 0;
  double _uploadRaw = 0;
  double _uploadCalibrated = 0;

  double _downloadFactor = 11.0; // Factor fijo descarga
  double _uploadFactor = 8.5; // Factor fijo subida
  bool _isCalibrated = true; // Siempre "calibrado" con factores fijos

  AnimationController? _pulseCtrl;

  @override
  void initState() {
    super.initState();
    try {
      _pulseCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1000),
      )..repeat(reverse: true);
    } catch (e) {
      print('Error inicializando AnimationController: $e');
      _pulseCtrl = null;
    }
    _loadFactors();
  }

  @override
  void dispose() {
    _pulseCtrl?.dispose();
    _service.stop();
    super.dispose();
  }

  Future<void> _loadFactors() async {
    // Factores fijos - no se cargan desde SharedPreferences
    setState(() {
      _downloadFactor = 11.0; // Factor fijo descarga
      _uploadFactor = 8.5; // Factor fijo subida
      _isCalibrated = true; // Siempre calibrado
    });
  }

  Future<void> _saveFactors(double down, double up) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('speed_download_factor', down);
    await prefs.setDouble('speed_upload_factor', up);
    await prefs.setBool('speed_calibrated', true);
    setState(() {
      _downloadFactor = down;
      _uploadFactor = up;
      _isCalibrated = true;
    });
  }

  Future<void> _runTest() async {
    if (!mounted) return;
    
    setState(() {
      _phase = TestPhase.download;
      _displaySpeed = 0;
      _downloadRaw = 0;
      _downloadCalibrated = 0;
      _uploadRaw = 0;
      _uploadCalibrated = 0;
    });

    try {
      // === DESCARGA ===
      final downRaw = await _service.runDownloadTest(
        onSpeedUpdate: (s) {
          if (mounted) {
            setState(() => _displaySpeed = s * _downloadFactor);
          }
        },
        onStatus: (s) {
          if (mounted) {
            setState(() => _status = s);
          }
        },
      );

      if (mounted) {
        setState(() {
          _downloadRaw = downRaw;
          _downloadCalibrated = downRaw * _downloadFactor;
        });
      }

      await Future.delayed(const Duration(milliseconds: 500));

      // === SUBIDA ===
      if (mounted) {
        setState(() {
          _phase = TestPhase.upload;
          _displaySpeed = 0;
        });
      }

      final upRaw = await _service.runUploadTest(
        onSpeedUpdate: (s) {
          if (mounted) {
            setState(() => _displaySpeed = s * _uploadFactor);
          }
        },
        onStatus: (s) {
          if (mounted) {
            setState(() => _status = s);
          }
        },
      );

      if (mounted) {
        setState(() {
          _uploadRaw = upRaw;
          _uploadCalibrated = upRaw * _uploadFactor;
          _phase = TestPhase.done;
          _status = 'Completado';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = TestPhase.done;
          _status = 'Error: $e';
        });
      }
    }
  }

  void _showCalibration() {
    final downCtrl = TextEditingController();
    final upCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('CALIBRAR', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _calibrationField(
                icon: Icons.download,
                color: const Color(0xFF0A84FF),
                label: 'DESCARGA',
                raw: _downloadRaw,
                controller: downCtrl,
              ),
              const SizedBox(height: 16),
              _calibrationField(
                icon: Icons.upload,
                color: const Color(0xFF00D4AA),
                label: 'SUBIDA',
                raw: _uploadRaw,
                controller: upCtrl,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              final dv = double.tryParse(downCtrl.text);
              final uv = double.tryParse(upCtrl.text);
              
              double nd = _downloadFactor;
              double nu = _uploadFactor;
              
              if (dv != null && dv > 0 && _downloadRaw > 0) {
                nd = dv / _downloadRaw;
              }
              if (uv != null && uv > 0 && _uploadRaw > 0) {
                nu = uv / _uploadRaw;
              }
              
              _saveFactors(nd, nu);
              setState(() {
                _downloadCalibrated = _downloadRaw * nd;
                _uploadCalibrated = _uploadRaw * nu;
              });
              
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('↓${nd.toStringAsFixed(2)}x  ↑${nu.toStringAsFixed(2)}x'),
                  backgroundColor: const Color(0xFF00D4AA),
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00D4AA)),
            child: const Text('GUARDAR', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Widget _calibrationField({
    required IconData icon,
    required Color color,
    required String label,
    required double raw,
    required TextEditingController controller,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Raw: ${raw.toStringAsFixed(0)} Mbps',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white, fontSize: 20),
            decoration: InputDecoration(
              hintText: 'Speedtest $label',
              hintStyle: const TextStyle(color: Colors.white24),
              suffixText: 'Mbps',
              suffixStyle: const TextStyle(color: Colors.white54),
              isDense: true,
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: color),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getColor(double speed) {
    if (speed >= 600) return const Color(0xFF00D4AA);
    if (speed >= 400) return const Color(0xFF0A84FF);
    if (speed >= 200) return Colors.amber;
    if (speed > 0) return const Color(0xFFFF6B6B);
    return Colors.white24;
  }

  @override
  Widget build(BuildContext context) {
    final isTesting = _phase == TestPhase.download || _phase == TestPhase.upload;
    // Cuando está completado, mostrar velocidad calibrada de descarga
    final speedToShow = _phase == TestPhase.done ? _downloadCalibrated : _displaySpeed;
    final color = _getColor(speedToShow);

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'SPEED TEST',
          style: TextStyle(letterSpacing: 4, fontWeight: FontWeight.w300),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
        // Botón de calibrar oculto - factores fijos
        // actions: [
        //   if (_phase == TestPhase.done)
        //     IconButton(
        //       icon: const Icon(Icons.tune),
        //       onPressed: _showCalibration,
        //     ),
        // ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 8),
                _buildCalibrationBadge(),
                const SizedBox(height: 20),
                _buildGauge(color, isTesting, speedToShow),
                const SizedBox(height: 24),
                _buildStatus(color, isTesting),
                const SizedBox(height: 24),
                if (_phase == TestPhase.done) _buildResults(),
                const SizedBox(height: 24),
                _buildButton(isTesting),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCalibrationBadge() {
    if (!_isCalibrated) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.amber.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline, color: Colors.amber, size: 16),
            SizedBox(width: 6),
            Text('Sin calibrar', style: TextStyle(color: Colors.amber, fontSize: 12)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF00D4AA).withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, color: Color(0xFF00D4AA), size: 16),
          const SizedBox(width: 6),
          Text(
            '↓${_downloadFactor.toStringAsFixed(1)}x  ↑${_uploadFactor.toStringAsFixed(1)}x',
            style: const TextStyle(
              color: Color(0xFF00D4AA),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGauge(Color color, bool isTesting, double speedToShow) {
    if (_pulseCtrl == null) {
      // Fallback si no hay AnimationController
      return Container(
        width: 280,
        height: 280,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF161B22),
          border: Border.all(
            color: color.withOpacity(isTesting ? 0.8 : 0.5),
            width: isTesting ? 5 : 4,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(isTesting ? 0.4 : 0.2),
              blurRadius: isTesting ? 60 : 30,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isTesting)
              Icon(
                _phase == TestPhase.download ? Icons.download : Icons.upload,
                color: color.withOpacity(0.7),
                size: 28,
              ),
            Text(
              speedToShow > 0 ? speedToShow.toStringAsFixed(0) : '—',
              style: TextStyle(
                color: color,
                fontSize: 76,
                fontWeight: FontWeight.w200,
                fontFamily: 'monospace',
              ),
            ),
            Text(
              'Mbps',
              style: TextStyle(
                color: color.withOpacity(0.7),
                fontSize: 18,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      );
    }
    
    return AnimatedBuilder(
      animation: _pulseCtrl!,
      builder: (_, __) {
        final pulseValue = _pulseCtrl?.value ?? 0.0;
        final pulse = isTesting ? 1 + pulseValue * 0.012 : 1.0;
        final glow = isTesting ? 0.5 + pulseValue * 0.2 : 0.3;

        return Transform.scale(
          scale: pulse,
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF161B22),
              border: Border.all(
                color: color.withOpacity(isTesting ? 0.8 : 0.5),
                width: isTesting ? 5 : 4,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(glow),
                  blurRadius: isTesting ? 60 : 30,
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isTesting)
                  Icon(
                    _phase == TestPhase.download ? Icons.download : Icons.upload,
                    color: color.withOpacity(0.7),
                    size: 28,
                  ),
                Text(
                  speedToShow > 0 ? speedToShow.toStringAsFixed(0) : '—',
                  style: TextStyle(
                    color: color,
                    fontSize: 76,
                    fontWeight: FontWeight.w200,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  'Mbps',
                  style: TextStyle(
                    color: color.withOpacity(0.7),
                    fontSize: 18,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatus(Color color, bool isTesting) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isTesting) ...[
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Text(
          _status.toUpperCase(),
          style: TextStyle(
            color: isTesting ? color : Colors.white54,
            fontSize: 12,
            letterSpacing: 2,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildResults() {
    final downOk = _downloadCalibrated >= 600;
    final upOk = _uploadCalibrated >= 100;
    final allOk = downOk && upOk;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // Descarga
          Row(
            children: [
              const Icon(Icons.download, color: Color(0xFF0A84FF), size: 20),
              const SizedBox(width: 8),
              const Text(
                'DESCARGA',
                style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1),
              ),
              const Spacer(),
              Text(
                '${_downloadRaw.toStringAsFixed(0)}',
                style: const TextStyle(color: Colors.white38, fontSize: 14),
              ),
              Text(
                ' → ${_downloadCalibrated.toStringAsFixed(0)} Mbps',
                style: TextStyle(
                  color: downOk ? const Color(0xFF00D4AA) : Colors.amber,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Subida
          Row(
            children: [
              const Icon(Icons.upload, color: Color(0xFF00D4AA), size: 20),
              const SizedBox(width: 8),
              const Text(
                'SUBIDA',
                style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1),
              ),
              const Spacer(),
              Text(
                '${_uploadRaw.toStringAsFixed(0)}',
                style: const TextStyle(color: Colors.white38, fontSize: 14),
              ),
              Text(
                ' → ${_uploadCalibrated.toStringAsFixed(0)} Mbps',
                style: TextStyle(
                  color: upOk ? const Color(0xFF00D4AA) : Colors.amber,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          const Divider(color: Colors.white12),
          const SizedBox(height: 12),
          
          // Veredicto
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: allOk
                  ? const Color(0xFF00D4AA).withOpacity(0.15)
                  : Colors.amber.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  allOk ? Icons.check_circle : Icons.warning_amber,
                  color: allOk ? const Color(0xFF00D4AA) : Colors.amber,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  allOk ? 'INSTALACIÓN GIGABIT OK' : 'VERIFICAR INSTALACIÓN',
                  style: TextStyle(
                    color: allOk ? const Color(0xFF00D4AA) : Colors.amber,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _copy,
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copiar resultado'),
            style: TextButton.styleFrom(foregroundColor: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _buildButton(bool isTesting) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: isTesting ? null : _runTest,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00D4AA),
            foregroundColor: Colors.black,
            disabledBackgroundColor: const Color(0xFF161B22),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
          ),
          child: isTesting
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white54),
                      ),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'MIDIENDO...',
                      style: TextStyle(color: Colors.white54, letterSpacing: 2),
                    ),
                  ],
                )
              : Text(
                  _phase == TestPhase.done ? 'MEDIR DE NUEVO' : 'INICIAR TEST',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                  ),
                ),
        ),
      ),
    );
  }

  void _copy() {
    final allOk = _downloadCalibrated >= 600 && _uploadCalibrated >= 100;
    final text = '''
═══ SPEED TEST ═══
↓ Descarga: ${_downloadCalibrated.toStringAsFixed(0)} Mbps
↑ Subida: ${_uploadCalibrated.toStringAsFixed(0)} Mbps
${allOk ? '✓ GIGABIT OK' : '⚠ VERIFICAR'}
══════════════════
''';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copiado'),
        backgroundColor: Color(0xFF00D4AA),
      ),
    );
  }
}

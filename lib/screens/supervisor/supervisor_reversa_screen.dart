import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/services/reversa_service.dart';

class SupervisorReversaScreen extends StatefulWidget {
  const SupervisorReversaScreen({super.key});

  @override
  State<SupervisorReversaScreen> createState() =>
      _SupervisorReversaScreenState();
}

class _SupervisorReversaScreenState extends State<SupervisorReversaScreen> {
  static const _bg      = Color(0xFF0A0F1E);
  static const _surface = Color(0xFF0D1B2A);
  static const _textDim = Color(0xFF8FA8C8);
  static const _orange  = Color(0xFFFF6B35);

  final _svc = ReversaService();

  List<Map<String, dynamic>> _equipos = [];
  bool _cargando = true;
  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  @override
  void initState() {
    super.initState();
    _suscribir();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _suscribir() {
    _sub = Supabase.instance.client
        .from('equipos_reversa')
        .stream(primaryKey: ['id'])
        .eq('estado', 'pendiente_supervision')
        .listen((rows) {
      if (!mounted) return;
      setState(() {
        _equipos = rows
            .where((r) => r['estado'] == 'pendiente_supervision')
            .toList();
        _cargando = false;
      });
    });
  }

  // Agrupa equipos por tecnico_nombre
  Map<String, List<Map<String, dynamic>>> get _porTecnico {
    final Map<String, List<Map<String, dynamic>>> mapa = {};
    for (final eq in _equipos) {
      final nombre = eq['tecnico_nombre'] as String? ?? eq['tecnico_rut'] as String? ?? 'Sin nombre';
      mapa.putIfAbsent(nombre, () => []).add(eq);
    }
    return mapa;
  }

  Future<void> _escanear() async {
    final serial = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => const _ScannerSheet(),
    );
    if (serial == null || serial.isEmpty || !mounted) return;

    final eq = _equipos.firstWhere(
      (e) => (e['serial'] as String?)?.toUpperCase() == serial.toUpperCase(),
      orElse: () => {},
    );

    if (eq.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Serie $serial no encontrada en solicitudes pendientes'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _mostrarConfirmacion(eq);
  }

  Future<void> _mostrarConfirmacion(Map<String, dynamic> eq) async {
    final serial  = eq['serial'] as String;
    final tecnico = eq['tecnico_nombre'] as String? ?? eq['tecnico_rut'] as String? ?? '-';

    final accion = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('Serie encontrada',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow('Serie',   serial),
            _InfoRow('Técnico', tecnico),
            _InfoRow('Tipo',    eq['tipo_equipo'] as String? ?? '-'),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: _orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _orange.withValues(alpha: 0.4)),
              ),
              child: const Text(
                '¿Mover a bodega?',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'rechazar'),
            child: const Text('Rechazar',
                style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'aceptar'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Aceptar',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (accion == null || !mounted) return;

    if (accion == 'aceptar') {
      await _aceptar(eq);
    } else {
      await _rechazar(eq);
    }
  }

  Future<void> _aceptar(Map<String, dynamic> eq) async {
    final serial = eq['serial'] as String;
    final rut    = eq['tecnico_rut'] as String? ?? '';

    try {
      final krpResult = await _svc.entregarEnKrp(serie: serial, rut: rut);

      switch (krpResult.resultado) {
        case KrpResultado.entregado:
          await _svc.marcarEntregado(serial);
          setState(() => _equipos.removeWhere((e) => e['serial'] == serial));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ $serial entregado correctamente'),
                backgroundColor: Colors.green,
              ),
            );
          }

        case KrpResultado.rechazado:
          await _svc.marcarRechazado(serial, krpResult.mensaje);
          setState(() => _equipos.removeWhere((e) => e['serial'] == serial));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Serie rechazada por KRP: ${krpResult.mensaje}'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
              ),
            );
          }

        case KrpResultado.error:
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'Error ${krpResult.statusCode} en KRP, favor contacta al administrador'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 6),
              ),
            );
          }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _rechazar(Map<String, dynamic> eq) async {
    final serial = eq['serial'] as String;
    try {
      await _svc.marcarRechazado(serial, 'Rechazado en supervisión');
      setState(() => _equipos.removeWhere((e) => e['serial'] == serial));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Equipo marcado como rechazado'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        title: const Text('Reversa — Supervisión',
            style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _escanear,
        backgroundColor: _orange,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Escanear serie'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: _orange))
          : _equipos.isEmpty
              ? const Center(
                  child: Text('Sin solicitudes pendientes',
                      style: TextStyle(color: _textDim, fontSize: 15)))
              : _buildLista(),
    );
  }

  Widget _buildLista() {
    final tecnicos = _porTecnico;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: tecnicos.entries.map((entry) {
        return _TecnicoCard(
          nombre:  entry.key,
          equipos: entry.value,
          orange:  _orange,
        );
      }).toList(),
    );
  }
}

// ── Card por técnico ──────────────────────────────────────────

class _TecnicoCard extends StatelessWidget {
  const _TecnicoCard({
    required this.nombre,
    required this.equipos,
    required this.orange,
  });

  final String nombre;
  final List<Map<String, dynamic>> equipos;
  final Color orange;

  static const _surface = Color(0xFF0D1B2A);
  static const _textDim = Color(0xFF8FA8C8);

  String _fmtFecha(dynamic val) {
    if (val == null) return '-';
    try {
      final dt = DateTime.parse(val as String);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return val.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: orange.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header técnico
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: orange.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(
              children: [
                const Icon(Icons.engineering, color: Colors.white70, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(nombre,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${equipos.length}',
                      style: TextStyle(
                          color: orange,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                ),
              ],
            ),
          ),
          // Lista de equipos
          ...equipos.map((eq) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.router, color: Colors.white38, size: 16),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            eq['serial'] as String? ?? '-',
                            style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'monospace',
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${eq['tipo_equipo'] ?? '-'}  ·  ${_fmtFecha(eq['fecha_desinstalacion'])}',
                            style: const TextStyle(color: _textDim, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ── Scanner sheet ─────────────────────────────────────────────

class _ScannerSheet extends StatefulWidget {
  const _ScannerSheet();

  @override
  State<_ScannerSheet> createState() => _ScannerSheetState();
}

class _ScannerSheetState extends State<_ScannerSheet>
    with SingleTickerProviderStateMixin {
  static const _textDim = Color(0xFF8FA8C8);
  static const _accent  = Color(0xFFFF6B35);

  final MobileScannerController _ctrl = MobileScannerController();
  bool _scanned = false;

  late final AnimationController _lineCtrl;
  late final Animation<double>    _lineAnim;

  @override
  void initState() {
    super.initState();
    _lineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _lineAnim = CurvedAnimation(parent: _lineCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _lineCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.65,
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.qr_code_scanner, color: _accent, size: 18),
                SizedBox(width: 8),
                Text('Escanear serie del equipo',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth;
                    final h = constraints.maxHeight;
                    const stripH  = 64.0;
                    final stripTop = (h - stripH) / 2;
                    final scanWindow = Rect.fromLTWH(0, stripTop, w, stripH);

                    return Stack(
                      children: [
                        MobileScanner(
                          controller: _ctrl,
                          scanWindow: scanWindow,
                          onDetect: (capture) {
                            if (_scanned) return;
                            final raw = capture.barcodes.firstOrNull?.rawValue;
                            if (raw != null && raw.isNotEmpty) {
                              _scanned = true;
                              Navigator.pop(context, raw);
                            }
                          },
                        ),
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _ScanOverlayPainter(scanWindow: scanWindow),
                          ),
                        ),
                        AnimatedBuilder(
                          animation: _lineAnim,
                          builder: (_, __) {
                            final lineY = stripTop + _lineAnim.value * stripH;
                            return Positioned(
                              top: lineY - 1.5,
                              left: 0, right: 0,
                              child: Container(
                                height: 3,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [
                                    Colors.transparent,
                                    Colors.red.withValues(alpha: 0.85),
                                    Colors.red,
                                    Colors.red.withValues(alpha: 0.85),
                                    Colors.transparent,
                                  ]),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.red.withValues(alpha: 0.55),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        Positioned(
                          top: stripTop + stripH + 14,
                          left: 0, right: 0,
                          child: Text(
                            'Alinea el código con la línea roja',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: _textDim)),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  const _ScanOverlayPainter({required this.scanWindow});
  final Rect scanWindow;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black54;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, scanWindow.top), paint);
    canvas.drawRect(
        Rect.fromLTWH(0, scanWindow.bottom, size.width, size.height - scanWindow.bottom), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text('$label: ',
              style: const TextStyle(color: Color(0xFF8FA8C8), fontSize: 13)),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

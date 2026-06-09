import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/screens/bodega/bodega_auditoria_form_screen.dart';

class BodegaAlertasStockScreen extends StatefulWidget {
  const BodegaAlertasStockScreen({super.key});

  @override
  State<BodegaAlertasStockScreen> createState() =>
      _BodegaAlertasStockScreenState();
}

class _BodegaAlertasStockScreenState extends State<BodegaAlertasStockScreen>
    with SingleTickerProviderStateMixin {
  static const _bg      = Color(0xFF0A0F1E);
  static const _surface = Color(0xFF0D1B2A);
  static const _accent  = Color(0xFF00D9FF);
  static const _textDim = Color(0xFF8FA8C8);
  static const _orange  = Color(0xFFF59E0B);
  static const _green   = Color(0xFF22C55E);

  final _db = Supabase.instance.client;

  late final TabController _tabController;

  List<Map<String, dynamic>> _pendientes = [];
  List<Map<String, dynamic>> _auditadas  = [];
  bool _loading = true;

  // Datos del auditor (bodeguero actual)
  String _rutAuditor    = '';
  String _nombreAuditor = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      _cargar();
    });
    _cargarAuditor().then((_) => _cargar());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _cargarAuditor() async {
    final prefs = await SharedPreferences.getInstance();
    final rut   = prefs.getString('rut_tecnico') ??
                  prefs.getString('user_rut') ?? '';
    final row   = await _db
        .from('nomina_bodega')
        .select('nombre')
        .eq('rut', rut)
        .maybeSingle();
    if (mounted) {
      setState(() {
        _rutAuditor    = rut;
        _nombreAuditor = row?['nombre'] as String? ?? rut;
      });
    }
  }

  Future<void> _cargar() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      if (_tabController.index == 0) {
        final rows = await _db
            .from('alertas_auditoria_material')
            .select()
            .eq('estado', 'pendiente')
            .order('created_at', ascending: false);
        if (mounted) {
          setState(() {
            _pendientes = List<Map<String, dynamic>>.from(rows);
            _loading    = false;
          });
        }
      } else {
        final rows = await _db
            .from('alertas_auditoria_material')
            .select('*, auditorias_material(*)')
            .eq('estado', 'revisada')
            .order('created_at', ascending: false);
        if (mounted) {
          setState(() {
            _auditadas = List<Map<String, dynamic>>.from(rows);
            _loading   = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatFecha(String? ts) {
    if (ts == null) return '—';
    try {
      return DateFormat('dd MMM yyyy HH:mm', 'es')
          .format(DateTime.parse(ts).toLocal());
    } catch (_) {
      return ts;
    }
  }

  Future<void> _abrirFormulario(Map<String, dynamic> alerta) async {
    if (_rutAuditor.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Cargando datos del auditor…'),
        duration: Duration(seconds: 1),
      ));
      return;
    }
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BodegaAuditoriaFormScreen(
          alertaId:      alerta['id'] as String,
          rutTecnico:    alerta['rut_tecnico']    as String? ?? '',
          nombreTecnico: alerta['nombre_tecnico'] as String? ?? '',
          rutAuditor:    _rutAuditor,
          nombreAuditor: _nombreAuditor,
        ),
      ),
    );
    if (result == true && mounted) {
      _tabController.animateTo(1);
      _cargar();
    }
  }

  Future<void> _verPdf(String? pdfB64) async {
    if (pdfB64 == null || pdfB64.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('PDF no disponible'),
      ));
      return;
    }
    final bytes = base64Decode(pdfB64);
    await Printing.sharePdf(
      bytes: Uint8List.fromList(bytes),
      filename: 'auditoria_material.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: _orange, size: 20),
          SizedBox(width: 8),
          Text('Alertas de Stock',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: _accent),
            onPressed: _cargar,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _orange,
          labelColor: _orange,
          unselectedLabelColor: _textDim,
          tabs: [
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.pending_actions_rounded, size: 16),
                const SizedBox(width: 6),
                const Text('Pendientes'),
                if (_pendientes.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  _Badge(_pendientes.length, _orange),
                ],
              ]),
            ),
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.fact_check_rounded, size: 16),
                const SizedBox(width: 6),
                const Text('Auditados'),
              ]),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTabPendientes(),
          _buildTabAuditados(),
        ],
      ),
    );
  }

  // ── Tab 0: Pendientes ─────────────────────────────────────────────────────

  Widget _buildTabPendientes() {
    if (_loading) {
      return const Center(
          child:
              CircularProgressIndicator(color: _orange, strokeWidth: 2));
    }
    if (_pendientes.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle_outline_rounded,
              size: 56, color: _green.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          const Text('Sin alertas pendientes',
              style: TextStyle(color: _textDim, fontSize: 15)),
        ]),
      );
    }
    return RefreshIndicator(
      color: _orange,
      backgroundColor: _surface,
      onRefresh: _cargar,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _pendientes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final a = _pendientes[i];
          return _AlertaPendienteCard(
            data: a,
            fechaFormateada: _formatFecha(a['created_at'] as String?),
            onRevisar: () => _abrirFormulario(a),
          );
        },
      ),
    );
  }

  // ── Tab 1: Auditados ──────────────────────────────────────────────────────

  Widget _buildTabAuditados() {
    if (_loading) {
      return const Center(
          child:
              CircularProgressIndicator(color: _green, strokeWidth: 2));
    }
    if (_auditadas.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.inventory_2_outlined,
              size: 56, color: _green.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          const Text('Sin auditorías completadas',
              style: TextStyle(color: _textDim, fontSize: 15)),
        ]),
      );
    }
    return RefreshIndicator(
      color: _green,
      backgroundColor: _surface,
      onRefresh: _cargar,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _auditadas.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final a    = _auditadas[i];
          final aud  = a['auditorias_material'] as Map<String, dynamic>?;
          return _AlertaAuditadaCard(
            alerta:          a,
            auditoria:       aud,
            fechaAlerta:     _formatFecha(a['created_at'] as String?),
            fechaAuditoria:  _formatFecha(aud?['fecha_auditoria'] as String?),
            onVerPdf: () => _verPdf(aud?['pdf_base64'] as String?),
          );
        },
      ),
    );
  }
}

// ── Badge de conteo ───────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final int   count;
  final Color color;
  const _Badge(this.count, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: TextStyle(
            color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}

// ── Card: alerta pendiente ────────────────────────────────────────────────────

class _AlertaPendienteCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String               fechaFormateada;
  final VoidCallback         onRevisar;

  static const _surface = Color(0xFF0D1B2A);
  static const _textDim = Color(0xFF8FA8C8);
  static const _orange  = Color(0xFFF59E0B);
  static const _accent  = Color(0xFF00D9FF);

  const _AlertaPendienteCard({
    required this.data,
    required this.fechaFormateada,
    required this.onRevisar,
  });

  @override
  Widget build(BuildContext context) {
    final tecnico   = data['nombre_tecnico'] as String? ?? '—';
    final rut       = data['rut_tecnico']    as String? ?? '';
    final tipo      = data['tipo_material']  as String? ?? '—';
    final stockOnt       = (data['stock_ont']          as num? ?? 0).toDouble();
    final stockDecoClaro = (data['stock_deco_claro'] as num?)?.toDouble();
    final stockDecoVtr   = (data['stock_deco_vtr']   as num?)?.toDouble();
    final stockDecoTotal =
        (data['stock_decodificador'] as num? ?? 0).toDouble();
    final stockExt = (data['stock_extensor'] as num? ?? 0).toDouble();

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _orange.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _orange.withValues(alpha: 0.08),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(11)),
          ),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded,
                size: 16, color: _orange),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                'Solicitud de material con stock',
                style: TextStyle(
                    color: _orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 0.3),
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('PENDIENTE',
                  style: TextStyle(
                      color: _orange,
                      fontSize: 9,
                      fontWeight: FontWeight.bold)),
            ),
          ]),
        ),
        // Cuerpo
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.person_rounded, size: 13, color: _textDim),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '$tecnico · $rut',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.inventory_2_rounded,
                  size: 13, color: _textDim),
              const SizedBox(width: 5),
              Text('Solicitó: $tipo',
                  style: const TextStyle(color: _textDim, fontSize: 12)),
            ]),
            const SizedBox(height: 8),
            const Text('Stock al momento de la solicitud:',
                style: TextStyle(color: _textDim, fontSize: 11)),
            const SizedBox(height: 4),
            _StockRow(label: 'ONT', valor: stockOnt, umbral: 3),
            if (stockDecoClaro != null && stockDecoVtr != null) ...[
              _StockRow(
                  label: 'Decodificador Claro',
                  valor: stockDecoClaro,
                  umbral: 5),
              _StockRow(
                  label: 'Decodificador VTR',
                  valor: stockDecoVtr,
                  umbral: 5),
            ] else if (stockDecoTotal > 0)
              _StockRow(
                  label: 'Decodificador (total)',
                  valor: stockDecoTotal,
                  umbral: 5),
            _StockRow(label: 'Extensor', valor: stockExt, umbral: 2),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.schedule_rounded, size: 11, color: _textDim),
              const SizedBox(width: 4),
              Text(fechaFormateada,
                  style:
                      const TextStyle(color: _textDim, fontSize: 10)),
            ]),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onRevisar,
                icon: const Icon(Icons.search_rounded, size: 14),
                label: const Text('Revisar',
                    style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: BorderSide(color: _accent.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── Card: alerta auditada ─────────────────────────────────────────────────────

class _AlertaAuditadaCard extends StatelessWidget {
  final Map<String, dynamic>  alerta;
  final Map<String, dynamic>? auditoria;
  final String                fechaAlerta;
  final String                fechaAuditoria;
  final VoidCallback          onVerPdf;

  static const _surface = Color(0xFF0D1B2A);
  static const _border  = Color(0xFF1E3A5F);
  static const _textDim = Color(0xFF8FA8C8);
  static const _orange  = Color(0xFFF59E0B);
  static const _green   = Color(0xFF22C55E);
  static const _red     = Color(0xFFEF4444);

  const _AlertaAuditadaCard({
    required this.alerta,
    required this.auditoria,
    required this.fechaAlerta,
    required this.fechaAuditoria,
    required this.onVerPdf,
  });

  @override
  Widget build(BuildContext context) {
    final tecnico      = alerta['nombre_tecnico'] as String? ?? '—';
    final rut          = alerta['rut_tecnico']    as String? ?? '';
    final tipo         = alerta['tipo_material']  as String? ?? '—';
    final stockOnt       = (alerta['stock_ont'] as num? ?? 0).toDouble();
    final stockDecoClaro =
        (alerta['stock_deco_claro'] as num?)?.toDouble();
    final stockDecoVtr =
        (alerta['stock_deco_vtr'] as num?)?.toDouble();
    final stockDecoTotal =
        (alerta['stock_decodificador'] as num? ?? 0).toDouble();
    final stockExt = (alerta['stock_extensor'] as num? ?? 0).toDouble();
    final nombreAuditor = auditoria?['nombre_auditor'] as String? ?? '—';
    final obs = auditoria?['observaciones'] as String? ?? '';

    // Diferencias del JSONB
    final items =
        (auditoria?['items_auditados'] as List?)
            ?.map((e) => e as Map<String, dynamic>)
            .where((i) {
              final delta =
                  ((i['fisico'] as num? ?? 0) - (i['esperado'] as num? ?? 0));
              return delta != 0;
            })
            .toList() ??
        [];

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _green.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _green.withValues(alpha: 0.07),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(11)),
          ),
          child: Row(children: [
            const Icon(Icons.fact_check_rounded,
                size: 16, color: _green),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('Auditoría completada',
                  style: TextStyle(
                      color: _green,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 0.3)),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('AUDITADA',
                  style: TextStyle(
                      color: _green,
                      fontSize: 9,
                      fontWeight: FontWeight.bold)),
            ),
          ]),
        ),
        // Cuerpo
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Técnico
            _InfoRow(icon: Icons.person_rounded,
                text: '$tecnico · $rut'),
            const SizedBox(height: 5),
            // Por qué saltó la alerta
            _InfoRow(icon: Icons.inventory_2_rounded,
                text: 'Solicitó: $tipo con stock en bodega'),
            const SizedBox(height: 5),
            // Fecha de la alerta
            _InfoRow(icon: Icons.notifications_rounded,
                label: 'Alerta:', text: fechaAlerta, color: _orange),
            const SizedBox(height: 5),
            // Fecha de la auditoría
            _InfoRow(icon: Icons.fact_check_rounded,
                label: 'Auditoría:', text: fechaAuditoria, color: _green),
            const SizedBox(height: 5),
            // Auditor
            _InfoRow(icon: Icons.badge_rounded,
                label: 'Auditor:', text: nombreAuditor),

            // Stock snapshot
            const SizedBox(height: 8),
            const Text('Stock al momento de la alerta:',
                style: TextStyle(color: _textDim, fontSize: 11)),
            const SizedBox(height: 4),
            _StockRow(label: 'ONT', valor: stockOnt, umbral: 3),
            if (stockDecoClaro != null && stockDecoVtr != null) ...[
              _StockRow(
                  label: 'Decodificador Claro',
                  valor: stockDecoClaro,
                  umbral: 5),
              _StockRow(
                  label: 'Decodificador VTR',
                  valor: stockDecoVtr,
                  umbral: 5),
            ] else if (stockDecoTotal > 0)
              _StockRow(
                  label: 'Decodificador (total)',
                  valor: stockDecoTotal,
                  umbral: 5),
            _StockRow(label: 'Extensor', valor: stockExt, umbral: 2),

            // Diferencias encontradas
            if (items.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Diferencias encontradas:',
                        style: TextStyle(
                            color: _textDim,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    ...items.map((i) {
                      final esp =
                          (i['esperado'] as num? ?? 0).toDouble();
                      final fis =
                          (i['fisico'] as num? ?? 0).toDouble();
                      final d = fis - esp;
                      final color = d < 0 ? _red : _orange;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(children: [
                          Expanded(
                              child: Text(
                                  i['categoria'] as String? ?? '',
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12))),
                          Text(
                              'K:${esp.toInt()} F:${fis.toInt()} '
                              '(${d > 0 ? '+' : ''}${d.toInt()})',
                              style: TextStyle(
                                  color: color,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ]),
                      );
                    }),
                  ],
                ),
              ),
            ],

            // Observaciones
            if (obs.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _border),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Observaciones:',
                          style: TextStyle(
                              color: _textDim,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(obs,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                    ]),
              ),
            ],

            // Botón PDF
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onVerPdf,
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                label: const Text('Ver PDF de auditoría',
                    style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green.withValues(alpha: 0.15),
                  foregroundColor: _green,
                  side: BorderSide(color: _green.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── Helpers compartidos ───────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String?  label;
  final String   text;
  final Color    color;

  static const _textDim = Color(0xFF8FA8C8);

  const _InfoRow({
    required this.icon,
    required this.text,
    this.label,
    this.color = _textDim,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 5),
      if (label != null) ...[
        Text(label!,
            style: const TextStyle(color: _textDim, fontSize: 12)),
        const SizedBox(width: 4),
      ],
      Expanded(
        child: Text(
          text,
          style: TextStyle(
              color: label != null ? Colors.white : Colors.white,
              fontWeight: label != null
                  ? FontWeight.w600
                  : FontWeight.normal,
              fontSize: 12),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ]);
  }
}

class _StockRow extends StatelessWidget {
  final String label;
  final double valor;
  final int    umbral;

  static const _textDim = Color(0xFF8FA8C8);
  static const _red     = Color(0xFFEF4444);
  static const _green   = Color(0xFF22C55E);

  const _StockRow({
    required this.label,
    required this.valor,
    required this.umbral,
  });

  @override
  Widget build(BuildContext context) {
    final supera = valor > umbral;
    final color  = supera ? _red : _green;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(children: [
        Icon(
          supera
              ? Icons.arrow_upward_rounded
              : Icons.check_rounded,
          size: 11,
          color: color,
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 100,
          child: Text(label,
              style: const TextStyle(color: _textDim, fontSize: 11)),
        ),
        Text(
          '${valor.toStringAsFixed(0)} unid.',
          style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: supera ? FontWeight.bold : FontWeight.normal),
        ),
        if (supera) ...[
          const SizedBox(width: 4),
          Text('(máx. $umbral)',
              style:
                  const TextStyle(color: _textDim, fontSize: 10)),
        ],
      ]),
    );
  }
}

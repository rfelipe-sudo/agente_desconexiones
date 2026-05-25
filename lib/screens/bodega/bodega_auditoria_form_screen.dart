import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:signature/signature.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/models/solicitud_material.dart';
import 'package:agente_desconexiones/services/auditoria_pdf_service.dart';
import 'package:agente_desconexiones/services/logistica_service.dart';

// ── Modelo interno ────────────────────────────────────────────────────────

class _SerieAjena {
  final String serie;
  final String? enTecnico;
  const _SerieAjena(this.serie, this.enTecnico);
}

class _ItemAuditoria {
  final String categoria;
  final bool   esSeriado;
  final double esperadoKepler;
  final List<String> seriesKepler;

  double fisicoContado = 0;
  final List<String>     seriesEncontradas  = [];
  final List<_SerieAjena> seriesNoEnTecnico = [];

  _ItemAuditoria({
    required this.categoria,
    required this.esSeriado,
    required this.esperadoKepler,
    required this.seriesKepler,
  }) : fisicoContado = esSeriado ? 0 : 0;

  double get fisico => esSeriado
      ? (seriesEncontradas.length + seriesNoEnTecnico.length).toDouble()
      : fisicoContado;

  double get delta => fisico - esperadoKepler;

  List<String> get seriesFaltantes => seriesKepler
      .where((s) =>
          !seriesEncontradas.any((e) => e.toUpperCase() == s.toUpperCase()) &&
          !seriesNoEnTecnico.any((a) => a.serie.toUpperCase() == s.toUpperCase()))
      .toList();

  Map<String, dynamic> toJson() => {
    'categoria':           categoria,
    'es_seriado':          esSeriado,
    'esperado':            esperadoKepler,
    'fisico':              fisico,
    'delta':               delta,
    'series_kepler':       seriesKepler,
    'series_encontradas':  seriesEncontradas,
    'series_no_en_tecnico': seriesNoEnTecnico
        .map((a) => {'serie': a.serie, 'en_tecnico': a.enTecnico ?? '?'})
        .toList(),
    'series_faltantes':    seriesFaltantes,
  };
}

// ── Pantalla principal ─────────────────────────────────────────────────────

class BodegaAuditoriaFormScreen extends StatefulWidget {
  final String alertaId;
  final String rutTecnico;
  final String nombreTecnico;
  final String rutAuditor;
  final String nombreAuditor;

  const BodegaAuditoriaFormScreen({
    super.key,
    required this.alertaId,
    required this.rutTecnico,
    required this.nombreTecnico,
    required this.rutAuditor,
    required this.nombreAuditor,
  });

  @override
  State<BodegaAuditoriaFormScreen> createState() =>
      _BodegaAuditoriaFormScreenState();
}

class _BodegaAuditoriaFormScreenState
    extends State<BodegaAuditoriaFormScreen> {
  static const _bg      = Color(0xFF0A0F1E);
  static const _surface = Color(0xFF0D1B2A);
  static const _border  = Color(0xFF1E3A5F);
  static const _accent  = Color(0xFF00D9FF);
  static const _textDim = Color(0xFF8FA8C8);
  static const _green   = Color(0xFF22C55E);
  static const _orange  = Color(0xFFF59E0B);
  static const _red     = Color(0xFFEF4444);

  final _db  = Supabase.instance.client;
  final _obsCtrl = TextEditingController();

  late final SignatureController _firmaAuditorCtrl;
  late final SignatureController _firmaAudiadoCtrl;

  List<_ItemAuditoria>  _items        = [];
  Map<String, String>   _indiceSeries = {}; // SERIE_UPPER → nombre técnico
  bool   _cargando  = true;
  bool   _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _firmaAuditorCtrl = SignatureController(
      penStrokeWidth: 2.5,
      penColor: Colors.white,
      exportBackgroundColor: const Color(0xFF0D1B2A),
    );
    _firmaAudiadoCtrl = SignatureController(
      penStrokeWidth: 2.5,
      penColor: Colors.white,
      exportBackgroundColor: const Color(0xFF0D1B2A),
    );
    _cargar();
  }

  @override
  void dispose() {
    _obsCtrl.dispose();
    _firmaAuditorCtrl.dispose();
    _firmaAudiadoCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = null; });
    try {
      final result = await LogisticaService().fetchStockConIndice();
      _indiceSeries = result.serieDueno;

      final tecnico = result.tecnicos
          .where((t) => t.rut == widget.rutTecnico)
          .firstOrNull;

      final items = <_ItemAuditoria>[];
      for (final mat in kMateriales) {
        final cantidad = tecnico?.stock[mat.nombre] ?? 0;
        final seriesKepler = mat.esSeriado
            ? (tecnico?.seriadosPorCategoria(mat.nombre)
                    .map((i) => i.serie ?? '')
                    .where((s) => s.isNotEmpty)
                    .toList() ??
                [])
            : <String>[];

        items.add(_ItemAuditoria(
          categoria:      mat.nombre,
          esSeriado:      mat.esSeriado,
          esperadoKepler: cantidad.toDouble(),
          seriesKepler:   seriesKepler,
        ));
      }

      if (mounted) {
        setState(() {
          _items    = items;
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error    = 'Error al cargar stock: $e';
        });
      }
    }
  }

  // ── Escanear serie (para seriados) ──────────────────────────────────────

  Future<void> _escanearSerie(_ItemAuditoria item) async {
    final serie = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _ScannerSheet(),
    );
    if (serie == null || serie.isEmpty || !mounted) return;
    await _procesarSerie(item, serie);
  }

  Future<void> _procesarSerie(_ItemAuditoria item, String serie) async {
    final s = serie.trim().toUpperCase();
    if (item.seriesEncontradas.any((e) => e.toUpperCase() == s) ||
        item.seriesNoEnTecnico.any((a) => a.serie.toUpperCase() == s)) {
      _snack('Serie $serie ya registrada');
      return;
    }

    // ¿Está en el saldo Kepler del técnico?
    final enPropio = item.seriesKepler.any((k) => k.toUpperCase() == s);
    if (enPropio) {
      setState(() => item.seriesEncontradas.add(serie));
      return;
    }

    // Buscar en qué técnico aparece (índice global incluye techs no registrados)
    final nombreDueno = _indiceSeries[s];

    setState(() => item.seriesNoEnTecnico
        .add(_SerieAjena(serie, nombreDueno)));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: _orange,
        content: Text(nombreDueno != null
            ? 'Serie $serie → en saldo de $nombreDueno'
            : 'Serie $serie → no encontrada en ningún técnico'),
      ));
    }
  }

  // ── Guardar auditoría ──────────────────────────────────────────────────

  Future<void> _guardar() async {
    if (_firmaAuditorCtrl.isEmpty) {
      _snack('Firma del auditor requerida');
      return;
    }
    if (_firmaAudiadoCtrl.isEmpty) {
      _snack('Firma del auditado requerida');
      return;
    }

    setState(() => _guardando = true);
    try {
      final firmaAuditorPng  = await _firmaAuditorCtrl.toPngBytes();
      final firmaAudiadoPng  = await _firmaAudiadoCtrl.toPngBytes();
      final firmaAuditorB64  = firmaAuditorPng  != null ? base64Encode(firmaAuditorPng)  : null;
      final firmaAudiadoB64  = firmaAudiadoPng  != null ? base64Encode(firmaAudiadoPng)  : null;

      final now = DateTime.now();
      final itemsJson = _items.map((i) => i.toJson()).toList();

      final pdfBytes = await AuditoriaPdfService.generar(
        nombreTecnico:   widget.nombreTecnico,
        rutTecnico:      widget.rutTecnico,
        nombreAuditor:   widget.nombreAuditor,
        rutAuditor:      widget.rutAuditor,
        fechaAuditoria:  now,
        itemsAuditados:  itemsJson,
        observaciones:   _obsCtrl.text.trim(),
        firmaAuditorB64: firmaAuditorB64,
        firmaAudiadoB64: firmaAudiadoB64,
      );

      final pdfB64 = base64Encode(pdfBytes);

      // Insertar auditoría
      final row = await _db.from('auditorias_material').insert({
        'alerta_id':       widget.alertaId,
        'rut_tecnico':     widget.rutTecnico,
        'nombre_tecnico':  widget.nombreTecnico,
        'rut_auditor':     widget.rutAuditor,
        'nombre_auditor':  widget.nombreAuditor,
        'fecha_auditoria': now.toIso8601String(),
        'items_auditados': itemsJson,
        'observaciones':   _obsCtrl.text.trim(),
        'firma_auditor':   firmaAuditorB64,
        'firma_auditado':  firmaAudiadoB64,
        'pdf_base64':      pdfB64,
      }).select('id').single();

      final auditoriaId = (row as Map)['id'] as String;

      // Marcar alerta como revisada y vincular auditoría
      await _db.from('alertas_auditoria_material').update({
        'estado':       'revisada',
        'auditoria_id': auditoriaId,
      }).eq('id', widget.alertaId);

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _guardando = false);
      _snack('Error al guardar: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: _red));
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Auditoría de Material',
              style: TextStyle(color: Colors.white, fontSize: 15,
                  fontWeight: FontWeight.bold)),
          Text(widget.nombreTecnico,
              style: const TextStyle(color: _textDim, fontSize: 11)),
        ]),
        actions: [
          if (!_cargando && _error == null)
            TextButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _accent))
                  : const Text('GUARDAR',
                      style: TextStyle(color: _accent,
                          fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : _error != null
              ? _buildError()
              : _buildForm(),
    );
  }

  Widget _buildError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, color: _red, size: 48),
        const SizedBox(height: 12),
        Text(_error!, style: const TextStyle(color: Colors.white70),
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _cargar,
          style: ElevatedButton.styleFrom(backgroundColor: _accent),
          child: const Text('Reintentar',
              style: TextStyle(color: Colors.black)),
        ),
      ]),
    ),
  );

  Widget _buildForm() {
    final noSeriados = _items.where((i) => !i.esSeriado).toList();
    final seriados   = _items.where((i) => i.esSeriado).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Info técnico ──
        _seccion('TÉCNICO AUDITADO'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: _boxDeco(),
          child: Row(children: [
            const Icon(Icons.person_rounded, color: _textDim, size: 16),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.nombreTecnico,
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w600, fontSize: 13)),
              Text(widget.rutTecnico,
                  style: const TextStyle(color: _textDim, fontSize: 11)),
            ]),
          ]),
        ),
        const SizedBox(height: 20),

        // ── No seriados ──
        _seccion('MATERIALES NO SERIADOS'),
        const SizedBox(height: 8),
        Container(
          decoration: _boxDeco(),
          child: Column(
            children: noSeriados.asMap().entries.map((e) {
              final isLast = e.key == noSeriados.length - 1;
              return _buildNoSeriadoFila(e.value, isLast);
            }).toList(),
          ),
        ),
        const SizedBox(height: 20),

        // ── Seriados ──
        _seccion('EQUIPOS SERIADOS'),
        const SizedBox(height: 8),
        ...seriados.map(_buildSeriadoCard),
        const SizedBox(height: 20),

        // ── Observaciones ──
        _seccion('OBSERVACIONES'),
        const SizedBox(height: 8),
        Container(
          decoration: _boxDeco(),
          child: TextField(
            controller: _obsCtrl,
            maxLines: 4,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Notas, diferencias explicadas, acuerdos...',
              hintStyle: TextStyle(color: _textDim, fontSize: 12),
              contentPadding: EdgeInsets.all(12),
              border: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 20),

        // ── Firmas ──
        _seccion('FIRMAS'),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _buildFirmaPad(
              'Auditor', widget.nombreAuditor, _firmaAuditorCtrl)),
          const SizedBox(width: 12),
          Expanded(child: _buildFirmaPad(
              'Auditado', widget.nombreTecnico, _firmaAudiadoCtrl)),
        ]),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Fila no seriado ────────────────────────────────────────────────────

  Widget _buildNoSeriadoFila(_ItemAuditoria item, bool isLast) {
    final conStock = item.esperadoKepler > 0;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            const Icon(Icons.cable_outlined, color: _textDim, size: 14),
            const SizedBox(width: 8),
            Expanded(
              child: Text(item.categoria,
                  style: TextStyle(
                      color: conStock ? Colors.white : _textDim,
                      fontSize: 13)),
            ),
            // Kepler qty
            Text('Kepler: ${item.esperadoKepler.toInt()}',
                style: const TextStyle(color: _textDim, fontSize: 11)),
            const SizedBox(width: 10),
            // Contador
            SizedBox(
              width: 90,
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                _CounterBtn(
                  icon: Icons.remove,
                  onTap: item.fisicoContado > 0
                      ? () => setState(() => item.fisicoContado--)
                      : null,
                ),
                Expanded(
                  child: Text(
                    item.fisicoContado.toInt().toString(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: _deltaColor(item.delta),
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                  ),
                ),
                _CounterBtn(
                  icon: Icons.add,
                  onTap: () => setState(() => item.fisicoContado++),
                ),
              ]),
            ),
          ]),
        ),
        if (!isLast) const Divider(height: 1, indent: 36, color: _border),
      ],
    );
  }

  // ── Card seriado ──────────────────────────────────────────────────────

  Widget _buildSeriadoCard(_ItemAuditoria item) {
    final delta = item.delta;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: _boxDeco(
          border: delta < 0 ? _red.withValues(alpha: 0.5) : null),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(children: [
            const Icon(Icons.memory_outlined, color: _textDim, size: 14),
            const SizedBox(width: 8),
            Expanded(
              child: Text(item.categoria,
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            // Contadores rápidos
            _BadgeCont('K', item.esperadoKepler.toInt(), _accent),
            const SizedBox(width: 6),
            _BadgeCont('F', item.fisico.toInt(),
                item.fisico >= item.esperadoKepler ? _green : _red),
            if (delta != 0) ...[
              const SizedBox(width: 6),
              _BadgeCont(
                  delta > 0 ? '+${delta.toInt()}' : delta.toInt().toString(),
                  null,
                  _deltaColor(delta)),
            ],
          ]),
        ),

        // Series encontradas (en saldo del técnico)
        if (item.seriesEncontradas.isNotEmpty) ...[
          const Divider(height: 1, color: _border),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: Text('Encontradas en saldo (${item.seriesEncontradas.length})',
                style: const TextStyle(color: _green, fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
          ...item.seriesEncontradas.map((s) => _SerieTile(
              serie: s, color: _green, icono: Icons.check_circle_rounded)),
        ],

        // Series de otro técnico
        if (item.seriesNoEnTecnico.isNotEmpty) ...[
          const Divider(height: 1, color: _border),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: Text('En saldo de otro técnico (${item.seriesNoEnTecnico.length})',
                style: const TextStyle(color: _orange, fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
          ...item.seriesNoEnTecnico.map((a) => _SerieTile(
              serie: a.serie,
              color: _orange,
              icono: Icons.swap_horiz_rounded,
              subtitulo: a.enTecnico != null ? 'Saldo: ${a.enTecnico}' : 'No encontrada en Kepler')),
        ],

        // Series faltantes (en Kepler pero no encontradas)
        if (item.seriesFaltantes.isNotEmpty) ...[
          const Divider(height: 1, color: _border),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: Text('No encontradas físicamente (${item.seriesFaltantes.length})',
                style: const TextStyle(color: _red, fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
          ...item.seriesFaltantes.map((s) =>
              _SerieTile(serie: s, color: _red, icono: Icons.cancel_rounded)),
        ],

        // Botón escanear
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _escanearSerie(item),
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 15),
                label: const Text('Escanear serie',
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
            if (item.seriesEncontradas.isNotEmpty ||
                item.seriesNoEnTecnico.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.undo_rounded, size: 18, color: _textDim),
                tooltip: 'Quitar última serie',
                onPressed: () => setState(() {
                  if (item.seriesNoEnTecnico.isNotEmpty) {
                    item.seriesNoEnTecnico.removeLast();
                  } else if (item.seriesEncontradas.isNotEmpty) {
                    item.seriesEncontradas.removeLast();
                  }
                }),
              ),
          ]),
        ),
      ]),
    );
  }

  // ── Firma pad ─────────────────────────────────────────────────────────

  Widget _buildFirmaPad(
      String titulo, String nombre, SignatureController ctrl) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(titulo,
          style: const TextStyle(color: _textDim, fontSize: 11,
              fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text(nombre,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          overflow: TextOverflow.ellipsis),
      const SizedBox(height: 6),
      Container(
        height: 120,
        decoration: _boxDeco(),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Signature(
            controller: ctrl,
            backgroundColor: _surface,
          ),
        ),
      ),
      const SizedBox(height: 4),
      GestureDetector(
        onTap: () => setState(() => ctrl.clear()),
        child: const Text('Limpiar',
            style: TextStyle(color: _textDim, fontSize: 10,
                decoration: TextDecoration.underline)),
      ),
    ]);
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  Widget _seccion(String titulo) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(children: [
      Container(width: 3, height: 13,
          decoration: BoxDecoration(color: _accent,
              borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Text(titulo,
          style: const TextStyle(color: _accent, fontSize: 11,
              fontWeight: FontWeight.bold, letterSpacing: 0.8)),
    ]),
  );

  BoxDecoration _boxDeco({Color? border}) => BoxDecoration(
    color: _surface,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: border ?? _border),
  );

  Color _deltaColor(double delta) =>
      delta < 0 ? _red : delta > 0 ? _orange : _green;
}

// ── Widgets pequeños ──────────────────────────────────────────────────────

class _CounterBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _CounterBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: onTap != null
              ? const Color(0xFF1E3A5F)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 14,
            color: onTap != null ? Colors.white : const Color(0xFF1E3A5F)),
      ),
    );
  }
}

class _BadgeCont extends StatelessWidget {
  final String label;
  final int? valor;
  final Color color;
  const _BadgeCont(this.label, this.valor, this.color);

  @override
  Widget build(BuildContext context) {
    final text = valor != null ? '$label:$valor' : label;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: TextStyle(color: color, fontSize: 10,
              fontWeight: FontWeight.bold)),
    );
  }
}

class _SerieTile extends StatelessWidget {
  final String serie;
  final Color  color;
  final IconData icono;
  final String? subtitulo;
  const _SerieTile({
    required this.serie,
    required this.color,
    required this.icono,
    this.subtitulo,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 3, 14, 3),
      child: Row(children: [
        Icon(icono, size: 12, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(serie,
                style: TextStyle(color: color, fontSize: 12,
                    fontWeight: FontWeight.w500)),
            if (subtitulo != null)
              Text(subtitulo!,
                  style: const TextStyle(
                      color: Color(0xFF8FA8C8), fontSize: 10)),
          ]),
        ),
      ]),
    );
  }
}

// ── Scanner sheet — franja estrecha (igual que guia_entrega_screen) ──────────

class _ScannerSheet extends StatefulWidget {
  const _ScannerSheet();

  @override
  State<_ScannerSheet> createState() => _ScannerSheetState();
}

class _ScannerSheetState extends State<_ScannerSheet>
    with SingleTickerProviderStateMixin {
  static const _surface = Color(0xFF0D1B2A);
  static const _accent  = Color(0xFF00D9FF);
  static const _textDim = Color(0xFF8FA8C8);

  final MobileScannerController _ctrl       = MobileScannerController();
  final TextEditingController   _manualCtrl = TextEditingController();
  bool _scanned = false;

  late final AnimationController _lineCtrl;
  late final Animation<double>   _lineAnim;

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
    _manualCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(children: [
        const SizedBox(height: 12),
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
              color: Colors.white24, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Escanear número de serie',
              style: TextStyle(color: Colors.white,
                  fontWeight: FontWeight.bold, fontSize: 14)),
        ),
        const SizedBox(height: 12),

        // ── Área de cámara con franja estrecha ────────────────────
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
                  final scanWindow =
                      Rect.fromLTWH(0, stripTop, w, stripH);

                  return Stack(children: [
                    MobileScanner(
                      controller: _ctrl,
                      scanWindow: scanWindow,
                      onDetect: (capture) {
                        if (_scanned) return;
                        final raw =
                            capture.barcodes.firstOrNull?.rawValue;
                        if (raw != null && raw.isNotEmpty) {
                          _scanned = true;
                          Navigator.pop(context, raw);
                        }
                      },
                    ),

                    // Overlay oscuro fuera de la franja
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _ScanOverlayPainter(
                            scanWindow: scanWindow),
                      ),
                    ),

                    // Línea roja animada (efecto láser)
                    AnimatedBuilder(
                      animation: _lineAnim,
                      builder: (_, __) {
                        final lineY =
                            stripTop + _lineAnim.value * stripH;
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

                    // Instrucción bajo la franja
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
                          shadows: const [
                            Shadow(color: Colors.black, blurRadius: 8),
                          ],
                        ),
                      ),
                    ),
                  ]);
                },
              ),
            ),
          ),
        ),

        // ── Ingreso manual ────────────────────────────────────────
        Container(
          color: _surface,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _manualCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Ingresar serie manualmente',
                  hintStyle: const TextStyle(color: _textDim),
                  filled: true,
                  fillColor: Colors.white10,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                final v = _manualCtrl.text.trim();
                if (v.isNotEmpty) Navigator.pop(context, v);
              },
              child: const Text('OK',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── Overlay para el scanner — oscurece fuera de [scanWindow] ─────────────────

class _ScanOverlayPainter extends CustomPainter {
  final Rect scanWindow;
  const _ScanOverlayPainter({required this.scanWindow});

  @override
  void paint(Canvas canvas, Size size) {
    final shadow = Paint()..color = const Color(0xBB000000);

    canvas.drawRect(
        Rect.fromLTRB(0, 0, size.width, scanWindow.top), shadow);
    canvas.drawRect(
        Rect.fromLTRB(0, scanWindow.bottom, size.width, size.height), shadow);

    // Borde fino de la franja activa
    canvas.drawRect(
      scanWindow,
      Paint()
        ..color = Colors.red.withValues(alpha: 0.35)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke,
    );

    // Esquinas rojas
    final corner = Paint()
      ..color = Colors.red
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const cl = 20.0;

    final l = scanWindow.left;
    final r = scanWindow.right;
    final t = scanWindow.top;
    final b = scanWindow.bottom;

    canvas.drawLine(Offset(l, t + cl), Offset(l, t), corner);
    canvas.drawLine(Offset(l, t), Offset(l + cl, t), corner);
    canvas.drawLine(Offset(r - cl, t), Offset(r, t), corner);
    canvas.drawLine(Offset(r, t), Offset(r, t + cl), corner);
    canvas.drawLine(Offset(l, b - cl), Offset(l, b), corner);
    canvas.drawLine(Offset(l, b), Offset(l + cl, b), corner);
    canvas.drawLine(Offset(r - cl, b), Offset(r, b), corner);
    canvas.drawLine(Offset(r, b), Offset(r, b - cl), corner);
  }

  @override
  bool shouldRepaint(_ScanOverlayPainter old) =>
      old.scanWindow != scanWindow;
}

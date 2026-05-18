import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'package:agente_desconexiones/services/guia_pdf_service.dart';

/// Vista de guía firmada para el bodeguero.
/// Permite ver el detalle y exportar/compartir el PDF con el folio Kepler.
class BodegaGuiaScreen extends StatefulWidget {
  final Map<String, dynamic> guia;
  final String? folioKepler;

  const BodegaGuiaScreen({
    super.key,
    required this.guia,
    this.folioKepler,
  });

  @override
  State<BodegaGuiaScreen> createState() => _BodegaGuiaScreenState();
}

class _BodegaGuiaScreenState extends State<BodegaGuiaScreen> {
  static const _bg      = Color(0xFF0A0F1E);
  static const _surface = Color(0xFF0D1B2A);
  static const _border  = Color(0xFF1E3A5F);
  static const _accent  = Color(0xFF00D9FF);
  static const _green   = Color(0xFF22C55E);
  static const _textDim = Color(0xFF8FA8C8);

  bool _generandoPdf = false;

  String get _folio =>
      widget.folioKepler ?? widget.guia['folio_kepler'] as String? ?? '';

  Future<void> _abrirPdf() async {
    setState(() => _generandoPdf = true);
    try {
      final bytes = await _buildPdf();
      if (!mounted) return;
      final fecha = (widget.guia['fecha'] as String? ?? '').replaceAll('-', '');
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (ctx) => Scaffold(
            backgroundColor: _bg,
            appBar: AppBar(
              backgroundColor: _surface,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
              title: const Text('Guía de entrega',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.share_outlined, color: _accent),
                  tooltip: 'Compartir PDF',
                  onPressed: () => Printing.sharePdf(
                      bytes: bytes, filename: 'guia_$fecha.pdf'),
                ),
              ],
            ),
            body: PdfPreview(
              build: (_) async => bytes,
              allowSharing: false,
              allowPrinting: false,
              canChangePageFormat: false,
              canChangeOrientation: false,
              initialPageFormat: PdfPageFormat.a4,
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al generar PDF: $e'),
                backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _generandoPdf = false);
    }
  }

  Future<Uint8List> _buildPdf() =>
      GuiaPdfService.generar(guia: widget.guia, folio: _folio);

  // ── UI ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final g              = widget.guia;
    final detalle        = g['detalle_material'] as String? ?? '';
    final cantidad       = g['cantidad']?.toString() ?? '';
    final entregador     = g['nombre_entregador']  as String? ?? '';
    final rutEntregador  = g['rut_entregador']     as String? ?? '';
    final solicitante    = g['nombre_solicitante'] as String? ?? '';
    final rutSolicitante = g['rut_solicitante']    as String? ?? '';
    final lugar          = g['lugar'] as String? ?? '';
    final fecha          = g['fecha']?.toString() ?? '';
    final horaRaw        = g['hora']?.toString()  ?? '';
    final hora           = horaRaw.length >= 5 ? horaRaw.substring(0, 5) : horaRaw;
    final series         = (g['series'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final firmaEb64      = g['firma_entregador']  as String?;
    final firmaSb64      = g['firma_solicitante'] as String?;
    final estado         = g['estado'] as String? ?? '';
    final folio          = _folio;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: const Text('Guía de Entrega',
            style: TextStyle(color: Colors.white, fontSize: 16,
                fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_generandoPdf)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                      color: _accent, strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined, color: _accent),
              tooltip: 'Ver / Compartir PDF',
              onPressed: _abrirPdf,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Estado + folio ───────────────────────────────────
          _tarjeta(children: [
            Row(children: [
              Icon(
                estado.contains('confirm') ? Icons.verified_rounded
                    : Icons.check_circle_outline,
                color: _green, size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(
                estado == 'confirmada_bodega' ? 'Confirmada por bodega'
                    : estado == 'firmada' ? 'Firmada — pendiente bodega'
                    : estado.toUpperCase(),
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.bold, fontSize: 14),
              )),
            ]),
            if (folio.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Folio Kepler',
                      style: TextStyle(color: Color(0xFFF59E0B),
                          fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(folio,
                      style: const TextStyle(color: Colors.white,
                          fontSize: 15, fontWeight: FontWeight.bold)),
                ]),
              ),
            ],
          ]),

          const SizedBox(height: 12),

          // ── Datos del traspaso ───────────────────────────────
          _label('DATOS DEL TRASPASO'),
          _tarjeta(children: [
            _filaUI('Material',  detalle),
            _filaUI('Cantidad',  cantidad),
            if (series.isNotEmpty) _filaUI('Series', series.join(', ')),
            _filaUI('Fecha',     '$fecha  $hora'),
            _filaUI('Lugar',     lugar),
          ]),

          const SizedBox(height: 12),

          // ── Partes ───────────────────────────────────────────
          _label('PARTES'),
          _tarjeta(children: [
            _filaUI('Entregador (B)', '$entregador · $rutEntregador'),
            _filaUI('Solicitante (A)', '$solicitante · $rutSolicitante'),
          ]),

          const SizedBox(height: 12),

          // ── Firmas ───────────────────────────────────────────
          _label('FIRMAS'),
          Row(children: [
            Expanded(child: _firmaCard('Entregador (B)', firmaEb64)),
            const SizedBox(width: 12),
            Expanded(child: _firmaCard('Solicitante (A)', firmaSb64)),
          ]),

          const SizedBox(height: 20),

          // ── Botón PDF ────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: _bg,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: _generandoPdf
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2,
                          color: Color(0xFF0A0F1E)))
                  : const Icon(Icons.picture_as_pdf_outlined, size: 20),
              label: Text(_generandoPdf ? 'Generando…' : 'Ver / Compartir PDF',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              onPressed: _generandoPdf ? null : _abrirPdf,
            ),
          ),

          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  Widget _tarjeta({required List<Widget> children}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _border),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );

  Widget _label(String texto) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(texto,
        style: const TextStyle(color: _accent, fontSize: 11,
            fontWeight: FontWeight.bold, letterSpacing: 0.8)),
  );

  Widget _filaUI(String label, String valor) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 120,
          child: Text(label,
              style: const TextStyle(color: _textDim, fontSize: 12))),
      Expanded(child: Text(valor,
          style: const TextStyle(color: Colors.white, fontSize: 12))),
    ]),
  );

  Widget _firmaCard(String titulo, String? b64) {
    Uint8List? bytes;
    if (b64 != null && b64.isNotEmpty) {
      try { bytes = base64Decode(b64); } catch (_) {}
    }
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: _border.withValues(alpha: 0.5),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          ),
          child: Center(child: Text(titulo,
              style: const TextStyle(color: _textDim,
                  fontSize: 11, fontWeight: FontWeight.w600))),
        ),
        Expanded(
          child: bytes != null
              ? Padding(padding: const EdgeInsets.all(4),
                  child: Image.memory(bytes, fit: BoxFit.contain))
              : const Center(
                  child: Icon(Icons.gesture, color: _textDim, size: 24)),
        ),
      ]),
    );
  }
}

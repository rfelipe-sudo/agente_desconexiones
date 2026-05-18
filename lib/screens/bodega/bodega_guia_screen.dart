import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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

  Future<Uint8List> _buildPdf() async {
    final g           = widget.guia;
    final firmaEb64   = g['firma_entregador']  as String?;
    final firmaSb64   = g['firma_solicitante'] as String?;
    final fecha       = g['fecha'] as String? ?? '';
    final horaRaw     = g['hora']  as String? ?? '';
    final hora        = horaRaw.length >= 5 ? horaRaw.substring(0, 5) : horaRaw;
    final series      = (g['series'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final folio       = _folio;
    final observacion = folio.isNotEmpty
        ? 'Intercambio aprobado — Folio Kepler: $folio'
        : '';

    final imgE = (firmaEb64 != null && firmaEb64.isNotEmpty)
        ? pw.MemoryImage(base64Decode(firmaEb64)) : null;
    final imgS = (firmaSb64 != null && firmaSb64.isNotEmpty)
        ? pw.MemoryImage(base64Decode(firmaSb64)) : null;

    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // ── Encabezado ──────────────────────────────────────
          pw.Center(
            child: pw.Text('GUÍA DE ENTREGA DE MATERIAL',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text('CREABOX — Operaciones de fibra óptica',
                style: pw.TextStyle(fontSize: 10, color: PdfColors.blueGrey600)),
          ),
          if (folio.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Center(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                decoration: pw.BoxDecoration(
                  color: PdfColors.amber100,
                  border: pw.Border.all(color: PdfColors.amber700, width: 1),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text('Folio Kepler: $folio',
                    style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.brown800)),
              ),
            ),
          ],
          pw.SizedBox(height: 12),
          pw.Divider(),
          pw.SizedBox(height: 10),

          // ── Fecha / lugar ────────────────────────────────────
          pw.Row(children: [
            pw.Text('Fecha: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.Text(fecha, style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(width: 20),
            pw.Text('Hora: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.Text(hora, style: const pw.TextStyle(fontSize: 10)),
          ]),
          pw.SizedBox(height: 4),
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Lugar: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.Expanded(child: pw.Text(g['lugar'] as String? ?? 'Sin GPS',
                style: const pw.TextStyle(fontSize: 10))),
          ]),
          pw.SizedBox(height: 14),

          // ── Partes ───────────────────────────────────────────
          pw.Text('PARTES',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold,
                  fontSize: 11, color: PdfColors.blueGrey700)),
          pw.Divider(height: 8, thickness: 0.5),
          _fila('Solicitante (recibe)', g['nombre_solicitante'] as String? ?? ''),
          _fila('RUT solicitante',      g['rut_solicitante']    as String? ?? ''),
          _fila('Entregador',           g['nombre_entregador']  as String? ?? ''),
          _fila('RUT entregador',       g['rut_entregador']     as String? ?? ''),
          pw.SizedBox(height: 14),

          // ── Material ─────────────────────────────────────────
          pw.Text('MATERIAL',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold,
                  fontSize: 11, color: PdfColors.blueGrey700)),
          pw.Divider(height: 8, thickness: 0.5),
          _fila('Descripción', g['detalle_material'] as String? ?? ''),
          _fila('Cantidad',    g['cantidad']?.toString() ?? ''),
          if (series.isNotEmpty) _fila('Series', series.join(', ')),
          if (folio.isNotEmpty) _fila('Folio Kepler', folio),
          if (observacion.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('Observaciones:',
                    style: pw.TextStyle(fontSize: 9, color: PdfColors.blueGrey600,
                        fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 2),
                pw.Text(observacion, style: const pw.TextStyle(fontSize: 9)),
              ]),
            ),
          ],
          pw.SizedBox(height: 20),

          // ── Firmas ───────────────────────────────────────────
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                pw.Text('Firma del entregador',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                pw.SizedBox(height: 2),
                pw.Text(g['nombre_entregador'] as String? ?? '',
                    style: const pw.TextStyle(fontSize: 9)),
                pw.SizedBox(height: 6),
                pw.Container(
                  width: 180, height: 80,
                  decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.blueGrey300)),
                  child: imgE != null
                      ? pw.Image(imgE, fit: pw.BoxFit.contain)
                      : pw.SizedBox(),
                ),
              ])),
              pw.SizedBox(width: 20),
              pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                pw.Text('Firma del solicitante',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                pw.SizedBox(height: 2),
                pw.Text(g['nombre_solicitante'] as String? ?? '',
                    style: const pw.TextStyle(fontSize: 9)),
                pw.SizedBox(height: 6),
                pw.Container(
                  width: 180, height: 80,
                  decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.blueGrey300)),
                  child: imgS != null
                      ? pw.Image(imgS, fit: pw.BoxFit.contain)
                      : pw.SizedBox(),
                ),
              ])),
            ],
          ),

          pw.Spacer(),
          pw.Divider(),
          pw.Text('CREABOX — Documento generado automáticamente',
              style: pw.TextStyle(fontSize: 8, color: PdfColors.blueGrey400)),
        ],
      ),
    ));
    return doc.save();
  }

  pw.Widget _fila(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.SizedBox(width: 130,
          child: pw.Text('$label:',
              style: pw.TextStyle(fontSize: 9, color: PdfColors.blueGrey600))),
      pw.Expanded(
          child: pw.Text(value,
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
    ]),
  );

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

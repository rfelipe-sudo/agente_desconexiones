import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class GuiaPdfService {
  static Future<Uint8List> generar({
    required Map<String, dynamic> guia,
    String? folio,
  }) async {
    final g           = guia;
    final firmaEb64   = g['firma_entregador']  as String?;
    final firmaSb64   = g['firma_solicitante'] as String?;
    final fecha       = g['fecha'] as String? ?? '';
    final horaRaw     = g['hora']  as String? ?? '';
    final hora        = horaRaw.length >= 5 ? horaRaw.substring(0, 5) : horaRaw;
    final series      = (g['series'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final folioPdf    = folio ?? g['folio_kepler'] as String? ?? '';
    final observacion = folioPdf.isNotEmpty
        ? 'Intercambio aprobado — Folio Kepler: $folioPdf'
        : '';

    final imgE = (firmaEb64 != null && firmaEb64.isNotEmpty)
        ? pw.MemoryImage(base64Decode(firmaEb64)) : null;
    final imgS = (firmaSb64 != null && firmaSb64.isNotEmpty)
        ? pw.MemoryImage(base64Decode(firmaSb64)) : null;

    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Center(
            child: pw.Text('GUÍA DE ENTREGA DE MATERIAL',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text('CREABOX — Operaciones de fibra óptica',
                style: pw.TextStyle(fontSize: 10, color: PdfColors.blueGrey600)),
          ),
          if (folioPdf.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Center(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                decoration: pw.BoxDecoration(
                  color: PdfColors.amber100,
                  border: pw.Border.all(color: PdfColors.amber700, width: 1),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text('Folio Kepler: $folioPdf',
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
          pw.Text('PARTES',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold,
                  fontSize: 11, color: PdfColors.blueGrey700)),
          pw.Divider(height: 8, thickness: 0.5),
          _fila('Solicitante (recibe)', g['nombre_solicitante'] as String? ?? ''),
          _fila('RUT solicitante',      g['rut_solicitante']    as String? ?? ''),
          _fila('Entregador',           g['nombre_entregador']  as String? ?? ''),
          _fila('RUT entregador',       g['rut_entregador']     as String? ?? ''),
          pw.SizedBox(height: 14),
          pw.Text('MATERIAL',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold,
                  fontSize: 11, color: PdfColors.blueGrey700)),
          pw.Divider(height: 8, thickness: 0.5),
          _fila('Descripción', g['detalle_material'] as String? ?? ''),
          _fila('Cantidad',    g['cantidad']?.toString() ?? ''),
          if (series.isNotEmpty) _fila('Series', series.join(', ')),
          if (folioPdf.isNotEmpty) _fila('Folio Kepler', folioPdf),
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

  static pw.Widget _fila(String label, String value) => pw.Padding(
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
}

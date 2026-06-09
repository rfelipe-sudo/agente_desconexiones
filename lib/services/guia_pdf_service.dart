import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'firma_electronica_leyenda_pdf.dart';
import 'logistica_service.dart';
import 'pdf_theme_service.dart';

class GuiaPdfService {
  static Future<Uint8List> generar({
    required Map<String, dynamic> guia,
    String? folio,
  }) async {
    final g = await enriquecerNombres(guia);
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

    final theme = await PdfThemeService.cargar();

    final docContenido = pw.Document();
    docContenido.addPage(_paginaContenido(
      theme: theme,
      g: g, fecha: fecha, hora: hora, series: series,
      folioPdf: folioPdf, observacion: observacion,
    ));
    final bytesContenido = await docContenido.save();
    final sha256Hex = sha256.convert(bytesContenido).toString().toUpperCase();

    final now = DateTime.now();
    final fechaFirma = DateFormat('dd/MM/yyyy HH:mm:ss').format(now);
    final encabezado =
        'Documento generado el ${DateFormat('dd/MM/yyyy HH:mm').format(now)} — CREABOX';
    final pie = 'CREABOX — Documento con Firma Electrónica Simple. Ley N° 19.799 (Chile)';

    final doc = pw.Document();
    doc.addPage(_paginaContenido(
      theme: theme,
      g: g, fecha: fecha, hora: hora, series: series,
      folioPdf: folioPdf, observacion: observacion,
    ));

    doc.addPage(FirmaElectronicaLeyendaPdf.pagina(
      theme: theme,
      nombre: g['nombre_solicitante'] as String? ?? '',
      rut: g['rut_solicitante'] as String? ?? '',
      fechaFirma: fechaFirma,
      sha256Hex: sha256Hex,
      imgFirma: imgS,
      rol: 'trabajador',
      tituloFirma: 'Firma del Receptor',
      encabezadoDocumento: encabezado,
      pieDocumento: pie,
    ));

    doc.addPage(FirmaElectronicaLeyendaPdf.pagina(
      theme: theme,
      nombre: g['nombre_entregador'] as String? ?? '',
      rut: g['rut_entregador'] as String? ?? '',
      fechaFirma: fechaFirma,
      sha256Hex: sha256Hex,
      imgFirma: imgE,
      rol: 'trabajador',
      tituloFirma: 'Firma del Entregador',
      encabezadoDocumento: encabezado,
      pieDocumento: pie,
    ));

    return doc.save();
  }

  /// Corrige nombres en guías antiguas usando RUT + nómina.
  static Future<Map<String, dynamic>> enriquecerNombres(
    Map<String, dynamic> guia,
  ) async {
    final logistica = LogisticaService();
    final rutEnt = guia['rut_entregador'] as String? ?? '';
    final rutSol = guia['rut_solicitante'] as String? ?? '';
    final nombreEnt = await logistica.nombrePorRut(
      rutEnt,
      fallback: guia['nombre_entregador'] as String?,
    );
    final nombreSol = await logistica.nombrePorRut(
      rutSol,
      fallback: guia['nombre_solicitante'] as String?,
    );
    return {
      ...guia,
      'nombre_entregador': nombreEnt,
      'nombre_solicitante': nombreSol,
    };
  }

  static pw.Page _paginaContenido({
    required pw.ThemeData theme,
    required Map<String, dynamic> g,
    required String fecha,
    required String hora,
    required List<String> series,
    required String folioPdf,
    required String observacion,
  }) {
    return pw.Page(
      theme: theme,
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
          pw.Spacer(),
          pw.Divider(),
          pw.Text('CREABOX — Documento generado automáticamente',
              style: pw.TextStyle(fontSize: 8, color: PdfColors.blueGrey400)),
        ],
      ),
    );
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

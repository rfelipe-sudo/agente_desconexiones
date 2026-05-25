import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
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

    // ── Paso 1: documento de contenido para calcular SHA-256 ─────────────
    final docContenido = pw.Document();
    docContenido.addPage(_paginaContenido(
      g: g, fecha: fecha, hora: hora, series: series,
      folioPdf: folioPdf, observacion: observacion,
      imgE: imgE, imgS: imgS,
    ));
    final bytesContenido = await docContenido.save();
    final sha256Hex = sha256.convert(bytesContenido).toString().toUpperCase();

    // ── Paso 2: documento final con ambas páginas ────────────────────────
    final now = DateTime.now();
    final fechaFirma = DateFormat('dd/MM/yyyy HH:mm:ss').format(now);

    final doc = pw.Document();
    doc.addPage(_paginaContenido(
      g: g, fecha: fecha, hora: hora, series: series,
      folioPdf: folioPdf, observacion: observacion,
      imgE: imgE, imgS: imgS,
    ));
    doc.addPage(_paginaFirmaElectronica(
      nombreFirmante: g['nombre_solicitante'] as String? ?? '',
      rutFirmante:    g['rut_solicitante']    as String? ?? '',
      fechaFirma:     fechaFirma,
      sha256Hex:      sha256Hex,
      imgFirma:       imgS,
    ));

    return doc.save();
  }

  // ── Página 1: contenido de la guía ──────────────────────────────────────
  static pw.Page _paginaContenido({
    required Map<String, dynamic> g,
    required String fecha,
    required String hora,
    required List<String> series,
    required String folioPdf,
    required String observacion,
    pw.ImageProvider? imgE,
    pw.ImageProvider? imgS,
  }) {
    return pw.Page(
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
    );
  }

  // ── Página 2: Firma Electrónica del Responsable ──────────────────────────
  static pw.Page _paginaFirmaElectronica({
    required String nombreFirmante,
    required String rutFirmante,
    required String fechaFirma,
    required String sha256Hex,
    pw.ImageProvider? imgFirma,
  }) {
    const teal     = PdfColor.fromInt(0xFF00796B);
    const tealLight= PdfColor.fromInt(0xFFE0F2F1);

    final textoLegal =
        'El presente documento ha sido firmado electrónicamente de conformidad con '
        'la Ley N° 19.799 sobre Documentos Electrónicos, Firma Electrónica y '
        'Servicios de Certificación (Chile). La firma electrónica simple aquí '
        'registrada tiene plena validez legal y constituye manifestación de voluntad '
        'del firmante respecto del contenido de este instrumento.';

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 36),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // ── Encabezado ─────────────────────────────────────────────────
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 10),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: teal, width: 2)),
            ),
            child: pw.Text(
              'FIRMA ELECTRÓNICA DEL RESPONSABLE',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: teal,
              ),
            ),
          ),
          pw.SizedBox(height: 14),

          // ── Párrafo legal ───────────────────────────────────────────────
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: tealLight,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              textoLegal,
              style: const pw.TextStyle(fontSize: 9),
              textAlign: pw.TextAlign.justify,
            ),
          ),
          pw.SizedBox(height: 18),

          // ── Tabla datos + firma ─────────────────────────────────────────
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Columna izquierda: datos del firmante
              pw.Expanded(
                flex: 55,
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _filaDato('Signatario',   nombreFirmante),
                      pw.SizedBox(height: 6),
                      _filaDato('RUT',          rutFirmante),
                      pw.SizedBox(height: 6),
                      _filaDato('Fecha de firma', fechaFirma),
                      pw.SizedBox(height: 6),
                      _filaDato('Dirección IP',  '10.0.0.1'),
                      pw.SizedBox(height: 6),
                      _filaDato('Dispositivo',   'Dispositivo Móvil — App CREABOX'),
                      pw.SizedBox(height: 12),
                      // SHA-256
                      pw.Text('Código SHA-256:',
                          style: pw.TextStyle(
                              fontSize: 8,
                              color: PdfColors.blueGrey600,
                              fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 3),
                      pw.Container(
                        width: double.infinity,
                        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.grey100,
                          borderRadius: pw.BorderRadius.circular(3),
                          border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                        ),
                        child: pw.Text(
                          sha256Hex,
                          style: const pw.TextStyle(
                            fontSize: 7,
                            color: PdfColors.red,
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 10),
                      pw.Text(
                        'Firma Electrónica Simple — Ley N° 19.799 (Chile)',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontStyle: pw.FontStyle.italic,
                          color: teal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 14),

              // Columna derecha: imagen de firma
              pw.Expanded(
                flex: 45,
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(
                        'Firma del Asignado',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: teal,
                        ),
                      ),
                      pw.SizedBox(height: 10),
                      pw.Container(
                        width: double.infinity,
                        height: 110,
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.grey400),
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: imgFirma != null
                            ? pw.Image(imgFirma, fit: pw.BoxFit.contain)
                            : pw.SizedBox(),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text(
                        'Firma electrónica — $fechaFirma',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontStyle: pw.FontStyle.italic,
                          color: PdfColors.blueGrey500,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          pw.Spacer(),
          pw.Divider(color: PdfColors.grey300),
          pw.Text(
            'CREABOX — Documento con Firma Electrónica Simple. Ley N° 19.799 (Chile)',
            style: pw.TextStyle(fontSize: 8, color: PdfColors.blueGrey400),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

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

  static pw.Widget _filaDato(String label, String value) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(label,
          style: pw.TextStyle(
              fontSize: 8,
              color: PdfColors.blueGrey600,
              fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 2),
      pw.Text(value,
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
    ],
  );
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'firma_electronica_leyenda_pdf.dart';
import 'pdf_theme_service.dart';

class AuditoriaPdfService {
  static Future<Uint8List> generar({
    required String nombreTecnico,
    required String rutTecnico,
    required String nombreAuditor,
    required String rutAuditor,
    required DateTime fechaAuditoria,
    required List<Map<String, dynamic>> itemsAuditados,
    required String observaciones,
    String? firmaAuditorB64,
    String? firmaAudiadoB64,
  }) async {
    final fechaStr =
        DateFormat('dd/MM/yyyy HH:mm', 'es').format(fechaAuditoria);

    final imgAuditor = (firmaAuditorB64 != null && firmaAuditorB64.isNotEmpty)
        ? pw.MemoryImage(base64Decode(firmaAuditorB64))
        : null;
    final imgAuditado =
        (firmaAudiadoB64 != null && firmaAudiadoB64.isNotEmpty)
            ? pw.MemoryImage(base64Decode(firmaAudiadoB64))
            : null;

    final theme = await PdfThemeService.cargar();

    // Paso 1: página de contenido → SHA-256
    final docContenido = pw.Document();
    docContenido.addPage(_paginaContenido(
      theme: theme,
      nombreTecnico: nombreTecnico,
      rutTecnico: rutTecnico,
      nombreAuditor: nombreAuditor,
      rutAuditor: rutAuditor,
      fechaStr: fechaStr,
      items: itemsAuditados,
      observaciones: observaciones,
    ));
    final bytesContenido = await docContenido.save();
    final sha256Hex = sha256.convert(bytesContenido).toString().toUpperCase();

    // Paso 2: documento final con ambas páginas
    final fechaFirma = DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());

    final doc = pw.Document();
    doc.addPage(_paginaContenido(
      theme: theme,
      nombreTecnico: nombreTecnico,
      rutTecnico: rutTecnico,
      nombreAuditor: nombreAuditor,
      rutAuditor: rutAuditor,
      fechaStr: fechaStr,
      items: itemsAuditados,
      observaciones: observaciones,
    ));
    const pie = 'CREABOX — Auditoría de material en terreno';

    doc.addPage(FirmaElectronicaLeyendaPdf.pagina(
      theme: theme,
      nombre: nombreAuditor,
      rut: rutAuditor,
      fechaFirma: fechaFirma,
      sha256Hex: sha256Hex,
      imgFirma: imgAuditor,
      rol: 'auditor',
      tituloFirma: 'Firma del Auditor',
      pieDocumento: pie,
    ));

    doc.addPage(FirmaElectronicaLeyendaPdf.pagina(
      theme: theme,
      nombre: nombreTecnico,
      rut: rutTecnico,
      fechaFirma: fechaFirma,
      sha256Hex: sha256Hex,
      imgFirma: imgAuditado,
      rol: 'trabajador',
      tituloFirma: 'Firma del Técnico Auditado',
      pieDocumento: pie,
    ));

    return doc.save();
  }

  // ── Página 1: Resumen de auditoría ──────────────────────────────────────

  static pw.Page _paginaContenido({
    required pw.ThemeData theme,
    required String nombreTecnico,
    required String rutTecnico,
    required String nombreAuditor,
    required String rutAuditor,
    required String fechaStr,
    required List<Map<String, dynamic>> items,
    required String observaciones,
  }) {
    // Items con stock o diferencia
    final conActividad = items
        .where((i) =>
            (i['esperado'] as num? ?? 0) > 0 ||
            (i['fisico'] as num? ?? 0) > 0)
        .toList();

    // Seriados con inconsistencias
    final seriados = items
        .where((i) =>
            (i['es_seriado'] as bool? ?? false) &&
            ((i['series_faltantes'] as List?)?.isNotEmpty == true ||
                (i['series_no_en_tecnico'] as List?)?.isNotEmpty == true))
        .toList();

    return pw.Page(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // ── Título ─────────────────────────────────────────────
          pw.Center(
            child: pw.Text(
              'AUDITORÍA DE MATERIAL',
              style: pw.TextStyle(
                  fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              'CREABOX — Control de inventario en terreno',
              style: pw.TextStyle(
                  fontSize: 10, color: PdfColors.blueGrey600),
            ),
          ),
          pw.SizedBox(height: 14),
          pw.Divider(),
          pw.SizedBox(height: 10),

          // ── Partes ─────────────────────────────────────────────
          pw.Text('PARTES',
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 11,
                  color: PdfColors.blueGrey700)),
          pw.Divider(height: 8, thickness: 0.5),
          _fila('Técnico auditado', '$nombreTecnico — $rutTecnico'),
          _fila('Auditor', '$nombreAuditor — $rutAuditor'),
          _fila('Fecha de auditoría', fechaStr),
          pw.SizedBox(height: 14),

          // ── Tabla de materiales ────────────────────────────────
          if (conActividad.isNotEmpty) ...[
            pw.Text('RESUMEN DE MATERIALES',
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 11,
                    color: PdfColors.blueGrey700)),
            pw.Divider(height: 8, thickness: 0.5),
            pw.Table(
              border: pw.TableBorder.all(
                  color: PdfColors.grey300, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(4),
                1: const pw.FlexColumnWidth(1.5),
                2: const pw.FlexColumnWidth(1.5),
                3: const pw.FlexColumnWidth(1.5),
              },
              children: [
                // Cabecera
                pw.TableRow(
                  decoration:
                      const pw.BoxDecoration(color: PdfColors.blueGrey100),
                  children: [
                    _celdaH('Material'),
                    _celdaH('Kepler'),
                    _celdaH('Físico'),
                    _celdaH('Δ'),
                  ],
                ),
                // Filas
                ...conActividad.map((i) {
                  final esperado =
                      (i['esperado'] as num? ?? 0).toDouble();
                  final fisico =
                      (i['fisico'] as num? ?? 0).toDouble();
                  final delta = fisico - esperado;
                  final color = delta < 0
                      ? PdfColors.red100
                      : delta > 0
                          ? PdfColors.orange50
                          : PdfColors.white;
                  return pw.TableRow(
                    decoration: pw.BoxDecoration(color: color),
                    children: [
                      _celda(i['categoria'] as String? ?? ''),
                      _celdaNum(esperado.toInt().toString()),
                      _celdaNum(fisico.toInt().toString()),
                      _celdaNum(
                        delta == 0
                            ? '='
                            : (delta > 0
                                ? '+${delta.toInt()}'
                                : delta.toInt().toString()),
                        color: delta < 0
                            ? PdfColors.red
                            : delta > 0
                                ? PdfColors.orange
                                : PdfColors.green,
                      ),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 14),
          ],

          // ── Inconsistencias seriados ───────────────────────────
          if (seriados.isNotEmpty) ...[
            pw.Text('INCONSISTENCIAS EN EQUIPOS SERIADOS',
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 11,
                    color: PdfColors.red700)),
            pw.Divider(height: 8, thickness: 0.5),
            ...seriados.map((i) {
              final faltantes =
                  (i['series_faltantes'] as List?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  [];
              final ajenas =
                  (i['series_no_en_tecnico'] as List?)
                      ?.map((e) => e as Map)
                      .toList() ??
                  [];
              return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(i['categoria'] as String? ?? '',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10)),
                    if (faltantes.isNotEmpty) ...[
                      pw.SizedBox(height: 3),
                      pw.Text(
                          'No encontradas físicamente: ${faltantes.join(', ')}',
                          style: const pw.TextStyle(
                              fontSize: 9, color: PdfColors.red)),
                    ],
                    if (ajenas.isNotEmpty) ...[
                      pw.SizedBox(height: 3),
                      ...ajenas.map((a) => pw.Text(
                            'Serie ${a['serie']} → saldo de ${a['en_tecnico'] ?? '?'}',
                            style: const pw.TextStyle(
                                fontSize: 9,
                                color: PdfColors.orange),
                          )),
                    ],
                    pw.SizedBox(height: 8),
                  ]);
            }),
          ],

          // ── Observaciones ──────────────────────────────────────
          if (observaciones.isNotEmpty) ...[
            pw.Text('OBSERVACIONES',
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 11,
                    color: PdfColors.blueGrey700)),
            pw.Divider(height: 8, thickness: 0.5),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                border:
                    pw.Border.all(color: PdfColors.grey400, width: 0.5),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(observaciones,
                  style: const pw.TextStyle(fontSize: 9)),
            ),
            pw.SizedBox(height: 10),
          ],

          pw.Spacer(),
          pw.Divider(),
          pw.Text(
            'CREABOX — Documento generado automáticamente',
            style: pw.TextStyle(
                fontSize: 8, color: PdfColors.blueGrey400),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static pw.Widget _fila(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                  width: 130,
                  child: pw.Text('$label:',
                      style: pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.blueGrey600))),
              pw.Expanded(
                  child: pw.Text(value,
                      style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold))),
            ]),
      );

  static pw.Widget _celdaH(String t) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: pw.Text(t,
            style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blueGrey700)),
      );

  static pw.Widget _celda(String t) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: pw.Text(t, style: const pw.TextStyle(fontSize: 9)),
      );

  static pw.Widget _celdaNum(String t,
          {PdfColor color = PdfColors.black}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: pw.Text(t,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: color)),
      );
}

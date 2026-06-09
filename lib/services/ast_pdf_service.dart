import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/ast_registro.dart';
import '../utils/image_compress_util.dart';
import 'firma_electronica_leyenda_pdf.dart';
import 'logistica_service.dart';
import 'pdf_theme_service.dart';

/// Genera PDF AST con el mismo layout que el formato Creaciones Tecnológicas:
/// Pág. 1 — formulario tabular · Pág. 2 — foto del área.
class AstPdfService {
  static const _border = PdfColors.grey700;
  static const _headerBg = PdfColor.fromInt(0xFFE8EEF5);
  static const _fontSize = 8.5;
  static const _headerSize = 9.0;

  static String nombreArchivo(ASTRegistro r) {
    final ot = r.ordenTrabajo.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final ts = _fechaIso(r.fechaHora).replaceAll(RegExp(r'[:.]'), '-');
    return 'AST_${ot}_$ts.pdf';
  }

  static String nombreArchivoDesdeMap(Map<String, dynamic> row) =>
      nombreArchivo(ASTRegistro.fromMap(row));

  static Future<Uint8List> generarDesdeMap(Map<String, dynamic> row) async {
    return generar(ASTRegistro.fromMap(row));
  }

  static Future<Uint8List> generar(ASTRegistro r) async {
    final fotoBytes = ImageCompressUtil.bytesFromPayload(r.fotoArea);
    final firmaBytes = ImageCompressUtil.bytesFromPayload(r.firma);

    pw.ImageProvider? imgFoto;
    pw.ImageProvider? imgFirma;
    if (fotoBytes != null) imgFoto = pw.MemoryImage(fotoBytes);
    if (firmaBytes != null) imgFirma = pw.MemoryImage(firmaBytes);

    final nombreTecnico = await LogisticaService().nombrePorRut(
      r.rutTecnico,
      fallback: r.nombreTecnico,
    );

    final empresaTitulo = r.empresa.trim().isNotEmpty
        ? r.empresa.trim()
        : 'Creaciones Tecnologicas SPA';
    final tagline = empresaTitulo.toLowerCase();
    final fechaLocal = r.fechaHora.toLocal();
    final theme = await PdfThemeService.cargar();

    final paginaFormulario = pw.Page(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Text(
                'ANÁLISIS DE TRABAJO SEGURO',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Center(
              child: pw.Text(
                '— $tagline',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                'Análisis de trabajo seguro - $empresaTitulo',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
              ),
            ),
            pw.SizedBox(height: 14),
            _tituloSeccion('Información del trabajo'),
            pw.SizedBox(height: 4),
            _tabla([
              _fila3('Tecnico', 'Rut', 'Empresa', header: true),
              _fila3(nombreTecnico, r.rutTecnico, r.empresa),
              _fila3('Orden de trabajo', 'Actividad', 'Lugar Actividad', header: true),
              _fila3(
                r.ordenTrabajo,
                r.actividad.isNotEmpty ? r.actividad : '—',
                _lugarPdf(r.lugarActividad),
              ),
              _fila2('Tareas a realizar', 'Fecha', header: true),
              _fila2(_joinComma(r.tareasRealizar), _fechaIso(r.fechaHora)),
            ]),
            pw.SizedBox(height: 10),
            _tituloSeccion(
              'Identificación de riesgos y medidas según tareas A realizar',
            ),
            pw.SizedBox(height: 4),
            _tabla([
              _fila2('Riesgos identificados', 'Medidas de control', header: true),
              _fila2(
                _joinComma(r.riesgosIdentificados),
                _joinComma(r.medidasControl),
              ),
            ]),
            pw.SizedBox(height: 8),
            _tabla([
              _fila2('Equipos de protección', 'Dispositivos de seguridad', header: true),
              _fila2(
                _joinComma(r.equiposProteccion),
                _joinComma(r.dispositivosSeguridad),
              ),
            ]),
            pw.SizedBox(height: 8),
            _tabla([
              _fila3(
                'Herramientas a utilizar',
                'Herramienta en mal estado',
                '¿Cuál?',
                header: true,
              ),
              _fila3(
                _joinComma(r.herramientasUtilizar),
                _herramientaMalEstado(r.estadoHerramientas).$1,
                _herramientaMalEstado(r.estadoHerramientas).$2,
              ),
            ]),
            pw.SizedBox(height: 8),
            _tabla([
              _fila2('Condiciones críticas', 'Condiciones climáticas', header: true),
              _fila2(
                _condCriticasPdf(r.condicionesCriticas),
                _condClimaticasPdf(r.condicionesClimaticas),
              ),
            ]),
            pw.SizedBox(height: 10),
            pw.Text(
              'Observaciones:',
              style: pw.TextStyle(
                fontSize: _headerSize,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              r.observaciones.trim().isEmpty ? ' ' : r.observaciones.trim(),
              style: const pw.TextStyle(fontSize: _fontSize),
            ),
          ],
        ),
      );

    final paginaFoto = imgFoto != null
        ? _paginaFoto(imgFoto, empresaTitulo, theme: theme)
        : null;

    final docContenido = pw.Document()..addPage(paginaFormulario);
    if (paginaFoto != null) docContenido.addPage(paginaFoto);
    final sha256Hex =
        sha256.convert(await docContenido.save()).toString().toUpperCase();
    final fechaFirma = DateFormat('dd/MM/yyyy HH:mm:ss').format(fechaLocal);
    final encabezado =
        'Documento generado el ${DateFormat('dd/MM/yyyy HH:mm').format(fechaLocal)} — CREABOX';

    final doc = pw.Document()..addPage(paginaFormulario);
    if (paginaFoto != null) doc.addPage(paginaFoto);

    doc.addPage(FirmaElectronicaLeyendaPdf.pagina(
      theme: theme,
      nombre: nombreTecnico,
      rut: r.rutTecnico,
      fechaFirma: fechaFirma,
      sha256Hex: sha256Hex,
      imgFirma: imgFirma,
      rol: 'trabajador',
      tituloFirma: 'Firma del Asignado',
      encabezadoDocumento: encabezado,
      pieDocumento:
          'CREABOX — Documento con Firma Electrónica Simple. Ley N° 19.799 (Chile)',
    ));

    return doc.save();
  }

  static pw.Page _paginaFoto(
    pw.ImageProvider imgFoto,
    String empresaTitulo, {
    required pw.ThemeData theme,
  }) {
    return pw.Page(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            'Imagen del lugar de trabajo',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Expanded(
            child: pw.Center(
              child: pw.Image(imgFoto, fit: pw.BoxFit.contain),
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Center(
            child: pw.Text(
              'Análisis de trabajo seguro - $empresaTitulo',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers de formato (referencia Creaciones Tecnológicas) ──

  static String _joinComma(List<String> items) {
    if (items.isEmpty) return '—';
    return items.join(', ');
  }

  static String _fechaIso(DateTime dt) {
    final l = dt.toLocal();
    final us = l.microsecond.toString().padLeft(6, '0');
    return '${l.year}-'
        '${l.month.toString().padLeft(2, '0')}-'
        '${l.day.toString().padLeft(2, '0')}T'
        '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}:'
        '${l.second.toString().padLeft(2, '0')}.$us';
  }

  static String _lugarPdf(String lugar) {
    if (lugar.isEmpty) return '—';
    if (lugar.toLowerCase().contains('edificio')) return 'Edificio';
    if (lugar == 'Calle') return 'Calle';
    if (lugar == 'Poste') return 'Poste';
    return lugar;
  }

  static (String, String) _herramientaMalEstado(String estado) {
    final s = estado.trim();
    if (s.isEmpty ||
        s.toLowerCase().contains('todas en buen') ||
        s.toLowerCase() == 'no') {
      return ('No', '');
    }
    return ('Sí', s);
  }

  static String _condCriticasPdf(String v) {
    final s = v.trim();
    if (s.isEmpty || s.toLowerCase() == 'ninguna') {
      return 'No existen observaciones asociadas';
    }
    return s;
  }

  static String _condClimaticasPdf(String v) {
    final s = v.trim();
    if (s.isEmpty ||
        s.toLowerCase() == 'despejado' ||
        s.toLowerCase() == 'nublado') {
      return 'No se identifican restricciones climáticas '
          'para continuar con la actividad.';
    }
    return s;
  }

  // ── Widgets PDF ──────────────────────────────────────────────

  static pw.Widget _tituloSeccion(String titulo) {
    return pw.Text(
      titulo,
      style: pw.TextStyle(
        fontSize: _headerSize,
        fontWeight: pw.FontWeight.bold,
      ),
    );
  }

  static pw.TableRow _fila2(String a, String b, {bool header = false}) {
    return pw.TableRow(
      children: [
        _celda(a, esEncabezado: header),
        _celda(b, esEncabezado: header),
      ],
    );
  }

  static pw.TableRow _fila3(String a, String b, String c, {bool header = false}) {
    return pw.TableRow(
      children: [
        _celda(a, esEncabezado: header),
        _celda(b, esEncabezado: header),
        _celda(c, esEncabezado: header),
      ],
    );
  }

  static pw.Widget _celda(String text, {bool esEncabezado = false}) {
    return pw.Container(
      color: esEncabezado ? _headerBg : PdfColors.white,
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: _fontSize,
          fontWeight: esEncabezado ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  static pw.Widget _tabla(List<pw.TableRow> rows) {
    final cols = rows.first.children?.length ?? 2;
    final widths = cols == 3
        ? const {
            0: pw.FlexColumnWidth(1),
            1: pw.FlexColumnWidth(1),
            2: pw.FlexColumnWidth(1),
          }
        : const {
            0: pw.FlexColumnWidth(1),
            1: pw.FlexColumnWidth(1),
          };

    return pw.Table(
      border: pw.TableBorder.all(color: _border, width: 0.4),
      columnWidths: widths,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
      children: rows,
    );
  }
}

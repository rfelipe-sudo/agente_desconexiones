import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Leyenda y página de firma electrónica simple — Ley N° 19.799 (Chile).
/// Layout alineado al acta FORD (última página del documento de referencia).
class FirmaElectronicaLeyendaPdf {
  FirmaElectronicaLeyendaPdf._();

  static const _gris = PdfColors.grey700;
  static const _grisClaro = PdfColors.grey600;

  /// SHA-256 en bloques de 8 caracteres separados por guión (formato FORD).
  static String formatSha256(String hex) {
    final h = hex.replaceAll(RegExp(r'[^A-Fa-f0-9]'), '').toUpperCase();
    if (h.length < 64) return h;
    final partes = <String>[];
    for (var i = 0; i < 64; i += 8) {
      partes.add(h.substring(i, i + 8));
    }
    return partes.join('-');
  }

  /// Párrafo legal personalizado (Ley 19.799 Chile).
  static String parrafoLegal({
    required String nombre,
    required String rut,
    String rol = 'trabajador',
  }) {
    final nombreLimpio = nombre.trim().isEmpty ? 'el firmante' : nombre.trim();
    final rutLimpio = rut.trim().isEmpty ? '—' : rut.trim();
    return 'El $rol $nombreLimpio (RUT: $rutLimpio) suscribió el presente '
        'documento electrónicamente en la fecha y condiciones que se indican a '
        'continuación. Esta firma electrónica simple es válida de conformidad con '
        'la Ley N° 19.799 sobre Documentos Electrónicos, Firma Electrónica y '
        'Servicios de Certificación (Chile).';
  }

  /// Última página del documento: firma electrónica del responsable.
  static pw.Page pagina({
    required pw.ThemeData theme,
    required String nombre,
    required String rut,
    required String fechaFirma,
    required String sha256Hex,
    pw.ImageProvider? imgFirma,
    String rol = 'trabajador',
    String tituloEncabezado = 'Firma Electrónica del Responsable',
    String tituloFirma = 'Firma del Asignado',
    String? ip,
    String? dispositivo,
    String? pieDocumento,
    String? encabezadoDocumento,
  }) {
    final textoLegal = parrafoLegal(nombre: nombre, rut: rut, rol: rol);
    final shaFormateado = formatSha256(sha256Hex);

    return pw.Page(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 44, vertical: 40),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (encabezadoDocumento != null && encabezadoDocumento.isNotEmpty) ...[
            pw.Text(
              encabezadoDocumento,
              style: pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
            ),
            pw.SizedBox(height: 16),
          ],
          pw.Text(
            tituloEncabezado,
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            textoLegal,
            style: const pw.TextStyle(fontSize: 9.5, height: 1.45),
            textAlign: pw.TextAlign.justify,
          ),
          pw.SizedBox(height: 18),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 55,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _lineaDato('Signatario', nombre),
                    pw.SizedBox(height: 8),
                    _lineaDato('RUT', rut),
                    pw.SizedBox(height: 8),
                    _lineaDato('Fecha de firma', fechaFirma),
                    pw.SizedBox(height: 8),
                    _lineaDato('Dirección IP', ip ?? '—'),
                    pw.SizedBox(height: 8),
                    _lineaDato(
                      'Dispositivo',
                      dispositivo ?? 'Dispositivo Móvil — App CREABOX',
                    ),
                    pw.SizedBox(height: 14),
                    pw.Text(
                      'Código SHA-256:',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: _grisClaro,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      shaFormateado,
                      style: const pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.red800,
                        height: 1.35,
                      ),
                    ),
                    pw.SizedBox(height: 12),
                    pw.Text(
                      'Firma Electrónica Simple — Ley N° 19.799 (Chile)',
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        fontStyle: pw.FontStyle.italic,
                        color: _gris,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 20),
              pw.Expanded(
                flex: 45,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      tituloFirma,
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.black,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                    pw.SizedBox(height: 12),
                    pw.Container(
                      width: double.infinity,
                      height: 120,
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
                      ),
                      child: imgFirma != null
                          ? pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Image(imgFirma, fit: pw.BoxFit.contain),
                            )
                          : pw.SizedBox(),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'Firma electrónica — $fechaFirma',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontStyle: pw.FontStyle.italic,
                        color: _grisClaro,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.Spacer(),
          if (pieDocumento != null && pieDocumento.isNotEmpty)
            pw.Text(
              pieDocumento,
              style: pw.TextStyle(fontSize: 7.5, color: PdfColors.grey500),
            ),
        ],
      ),
    );
  }

  static pw.Widget _lineaDato(String etiqueta, String valor) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '$etiqueta:',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: _grisClaro,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            valor.trim().isEmpty ? '—' : valor.trim(),
            style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
          ),
        ],
      );
}

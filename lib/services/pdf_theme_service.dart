import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Fuentes con soporte Unicode para PDFs (español, Ley N° 19.799, guiones, etc.).
class PdfThemeService {
  PdfThemeService._();

  static pw.Font? _base;
  static pw.Font? _bold;
  static pw.Font? _italic;

  static Future<pw.ThemeData> cargar() async {
    _base ??= await PdfGoogleFonts.notoSansRegular();
    _bold ??= await PdfGoogleFonts.notoSansBold();
    _italic ??= await PdfGoogleFonts.notoSansItalic();
    return pw.ThemeData.withFont(
      base: _base!,
      bold: _bold!,
      italic: _italic!,
    );
  }
}

/// Utilidades para RUT chileno (formato, limpieza, dígito verificador).
class RutHelper {
  RutHelper._();

  /// Formato visual: `12.345.678-9`
  static String formatear(String input) {
    final l = limpiar(input);
    final idx = l.indexOf('-');
    if (idx <= 0) {
      final solo = _soloDigitosYk(input);
      if (solo.length < 2) return input;
      final cuerpo = solo.substring(0, solo.length - 1);
      final dv = solo.substring(solo.length - 1);
      return '${_cuerpoConPuntos(cuerpo)}-$dv';
    }
    final cuerpo = l.substring(0, idx);
    final dv = l.substring(idx + 1);
    if (cuerpo.isEmpty) return input;
    return '${_cuerpoConPuntos(cuerpo)}-$dv';
  }

  static String _cuerpoConPuntos(String cuerpo) {
    final rev = cuerpo.split('').reversed.join();
    final buf = StringBuffer();
    for (var i = 0; i < rev.length; i++) {
      if (i > 0 && i % 3 == 0) buf.write('.');
      buf.write(rev[i]);
    }
    return buf.toString().split('').reversed.join();
  }

  /// Solo caracteres alfanuméricos del RUT (sin puntos ni guión).
  static String _soloDigitosYk(String s) {
    return s
        .replaceAll(RegExp(r'[^0-9kK]'), '')
        .toUpperCase();
  }

  /// Para Supabase: `12345678-9` (sin puntos, con guión antes del DV).
  /// Quita ceros a la izquierda del cuerpo (`018534498-3` → `18534498-3`) para validar bien el DV.
  static String limpiar(String rut) {
    final raw = rut.replaceAll(RegExp(r'[\s.]'), '').toUpperCase();
    if (raw.isEmpty) return '';
    String cuerpo;
    String dv;
    if (raw.contains('-')) {
      final parts = raw.split('-');
      if (parts.length != 2) return raw;
      cuerpo = parts[0];
      dv = parts[1];
    } else {
      if (raw.length < 2) return raw;
      cuerpo = raw.substring(0, raw.length - 1);
      dv = raw.substring(raw.length - 1);
    }
    cuerpo = cuerpo.replaceFirst(RegExp(r'^0+'), '');
    if (cuerpo.isEmpty) cuerpo = '0';
    return '$cuerpo-$dv';
  }

  /// Valida formato y dígito verificador módulo 11.
  static bool validar(String rut) {
    final l = limpiar(rut);
    final idx = l.indexOf('-');
    if (idx <= 0) return false;
    final cuerpo = l.substring(0, idx);
    final dvIn = l.substring(idx + 1);
    if (cuerpo.isEmpty || cuerpo.length > 8) return false;
    if (!RegExp(r'^\d+$').hasMatch(cuerpo)) return false;
    if (dvIn.length != 1) return false;

    final esperado = _calcularDv(cuerpo);
    final dvChar = dvIn.toUpperCase();
    return dvChar == esperado;
  }

  static String _calcularDv(String cuerpo) {
    var suma = 0;
    var mult = 2;
    for (var i = cuerpo.length - 1; i >= 0; i--) {
      suma += int.parse(cuerpo[i]) * mult;
      mult = mult == 7 ? 2 : mult + 1;
    }
    final resto = 11 - (suma % 11);
    if (resto == 11) return '0';
    if (resto == 10) return 'K';
    return '$resto';
  }
}

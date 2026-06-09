/// Fechas Supabase (UTC) → hora local Chile (Santiago).
class FechaChile {
  FechaChile._();

  static DateTime parse(String iso) => DateTime.parse(iso).toLocal();

  static String corto(DateTime dt) {
    final l = dt.toLocal();
    final d = l.day.toString().padLeft(2, '0');
    final m = l.month.toString().padLeft(2, '0');
    final h = l.hour.toString().padLeft(2, '0');
    final min = l.minute.toString().padLeft(2, '0');
    return '$d/$m/${l.year}  $h:$min';
  }
}

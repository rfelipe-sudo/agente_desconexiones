import 'package:shared_preferences/shared_preferences.dart';

/// Tickets de ayuda en terreno ya alertados (persiste entre sesiones).
class AyudaAlertaEstado {
  AyudaAlertaEstado._();

  static const _keySeen = 'ayuda_tickets_alerteados_v1';

  static Future<Set<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_keySeen) ?? []).toSet();
  }

  static Future<bool> wasSeen(String ticketId) async {
    if (ticketId.isEmpty) return false;
    return (await load()).contains(ticketId);
  }

  static Future<void> markSeen(String ticketId) async {
    if (ticketId.isEmpty) return;
    final set = await load();
    if (set.add(ticketId)) {
      await _save(set);
    }
  }

  static Future<void> markAllSeen(Iterable<String> ids) async {
    final set = await load();
    var changed = false;
    for (final id in ids) {
      if (id.isEmpty) continue;
      if (set.add(id)) changed = true;
    }
    if (changed) await _save(set);
  }

  static Future<void> unmarkSeen(String ticketId) async {
    if (ticketId.isEmpty) return;
    final set = await load();
    if (set.remove(ticketId)) {
      await _save(set);
    }
  }

  static Future<void> _save(Set<String> set) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keySeen, set.toList());
  }
}

import 'package:shared_preferences/shared_preferences.dart';

/// IDs de solicitudes de material ya alertadas (persiste entre sesiones).
class MaterialAlertaEstado {
  MaterialAlertaEstado._();

  static const _keySeen   = 'material_solicitudes_alerteadas_v1';
  static const _keyOpened = 'material_solicitudes_abiertas_v1';

  static Future<Set<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_keySeen) ?? []).toSet();
  }

  static Future<void> markSeen(String solicitudId) async {
    if (solicitudId.isEmpty) return;
    final set = await load();
    if (set.add(solicitudId)) {
      await _saveSeen(set);
    }
  }

  static Future<void> markAllSeen(Iterable<String> ids) async {
    final set = await load();
    var changed = false;
    for (final id in ids) {
      if (id.isEmpty) continue;
      if (set.add(id)) changed = true;
    }
    if (changed) await _saveSeen(set);
  }

  static Future<void> unmarkSeen(String solicitudId) async {
    if (solicitudId.isEmpty) return;
    final set = await load();
    if (set.remove(solicitudId)) {
      await _saveSeen(set);
    }
  }

  /// Usuario abrió la push (tap), no solo escuchó la alerta.
  static Future<void> markOpened(String solicitudId) async {
    if (solicitudId.isEmpty) return;
    final set = await _loadOpened();
    if (set.add(solicitudId)) {
      await _saveOpened(set);
    }
  }

  static Future<bool> wasOpened(String solicitudId) async {
    if (solicitudId.isEmpty) return false;
    return (await _loadOpened()).contains(solicitudId);
  }

  static Future<void> clearOpened(String solicitudId) async {
    if (solicitudId.isEmpty) return;
    final set = await _loadOpened();
    if (set.remove(solicitudId)) {
      await _saveOpened(set);
    }
  }

  static Future<Set<String>> _loadOpened() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_keyOpened) ?? []).toSet();
  }

  static Future<void> _saveSeen(Set<String> set) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keySeen, set.toList());
  }

  static Future<void> _saveOpened(Set<String> set) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyOpened, set.toList());
  }
}

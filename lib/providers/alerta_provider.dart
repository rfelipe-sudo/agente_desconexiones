import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agente_desconexiones/config/constants.dart';

/// Estado del bloqueo "Mis Actividades" cuando hay una alerta de desconexión
/// pendiente. El estado se persiste en SharedPreferences para sobrevivir a
/// kills de la app y handlers FCM en background.
class AlertaProvider extends ChangeNotifier {
  bool _misActividadesBloqueada = false;

  bool get misActividadesBloqueada => _misActividadesBloqueada;

  /// Lee el flag persistido. Llamar al iniciar el provider en main.dart.
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kPrefAlertaBloqueoMisActividades);
    _misActividadesBloqueada = raw == 'true';
    notifyListeners();
  }

  /// Vuelve a leer SharedPreferences (útil cuando un handler FCM
  /// background actualizó el flag y la UI vuelve a foreground).
  Future<void> refrescar() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kPrefAlertaBloqueoMisActividades);
    final nuevo = raw == 'true';
    if (nuevo != _misActividadesBloqueada) {
      _misActividadesBloqueada = nuevo;
      notifyListeners();
    }
  }

  /// Activa el bloqueo (llega 'bloquear_card' por FCM).
  Future<void> activar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefAlertaBloqueoMisActividades, 'true');
    if (!_misActividadesBloqueada) {
      _misActividadesBloqueada = true;
      notifyListeners();
    }
  }

  /// Resuelve el bloqueo (llega 'desbloquear_card' por FCM).
  Future<void> resolver() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefAlertaBloqueoMisActividades, 'false');
    if (_misActividadesBloqueada) {
      _misActividadesBloqueada = false;
      notifyListeners();
    }
  }
}

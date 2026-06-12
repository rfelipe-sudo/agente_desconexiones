import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agente_desconexiones/config/constants.dart';

/// Estado del bloqueo "Mis Actividades" cuando hay una alerta pendiente.
/// El estado se persiste en SharedPreferences para sobrevivir a
/// kills de la app y handlers FCM en background.
class AlertaProvider extends ChangeNotifier {
  bool _misActividadesBloqueada = false;
  String? _tituloAlerta;
  String? _descripcionAlerta;

  bool get misActividadesBloqueada => _misActividadesBloqueada;
  String? get tituloAlerta => _tituloAlerta;
  String? get descripcionAlerta => _descripcionAlerta;

  /// Lee el flag persistido. Llamar al iniciar el provider en main.dart.
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kPrefAlertaBloqueoMisActividades);
    _misActividadesBloqueada = raw == 'true';
    _tituloAlerta = prefs.getString(kPrefAlertaBloqueoTitulo);
    _descripcionAlerta = prefs.getString(kPrefAlertaBloqueoDescripcion);
    notifyListeners();
  }

  /// Vuelve a leer SharedPreferences (útil cuando un handler FCM
  /// background actualizó el flag y la UI vuelve a foreground).
  Future<void> refrescar() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kPrefAlertaBloqueoMisActividades);
    final nuevo = raw == 'true';
    final titulo = prefs.getString(kPrefAlertaBloqueoTitulo);
    final descripcion = prefs.getString(kPrefAlertaBloqueoDescripcion);
    if (nuevo != _misActividadesBloqueada ||
        titulo != _tituloAlerta ||
        descripcion != _descripcionAlerta) {
      _misActividadesBloqueada = nuevo;
      _tituloAlerta = titulo;
      _descripcionAlerta = descripcion;
      notifyListeners();
    }
  }

  /// Activa el bloqueo (llega 'bloquear_card' por FCM).
  Future<void> activar({String? titulo, String? descripcion}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefAlertaBloqueoMisActividades, 'true');
    if (titulo != null) {
      await prefs.setString(kPrefAlertaBloqueoTitulo, titulo);
      _tituloAlerta = titulo;
    }
    if (descripcion != null) {
      await prefs.setString(kPrefAlertaBloqueoDescripcion, descripcion);
      _descripcionAlerta = descripcion;
    }
    if (!_misActividadesBloqueada) {
      _misActividadesBloqueada = true;
      notifyListeners();
    }
  }

  /// Resuelve el bloqueo (llega 'desbloquear_card' por FCM).
  Future<void> resolver() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefAlertaBloqueoMisActividades, 'false');
    await prefs.remove(kPrefAlertaBloqueoTitulo);
    await prefs.remove(kPrefAlertaBloqueoDescripcion);
    _tituloAlerta = null;
    _descripcionAlerta = null;
    if (_misActividadesBloqueada) {
      _misActividadesBloqueada = false;
      notifyListeners();
    }
  }
}

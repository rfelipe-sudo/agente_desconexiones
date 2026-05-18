import 'package:shared_preferences/shared_preferences.dart';
import 'package:agente_desconexiones/models/creavox_tecnico.dart';
import 'package:agente_desconexiones/models/creavox_orden.dart';

class CreavoxSessionService {
  static const _keyTecnico = 'creavox_tecnico_session';
  static const _keyOrden = 'creavox_orden_activa';
  static const _keyLoggedIn = 'creavox_is_logged_in';

  static final CreavoxSessionService _instance =
      CreavoxSessionService._internal();
  factory CreavoxSessionService() => _instance;
  CreavoxSessionService._internal();

  SharedPreferences? _prefs;
  CreavoxTecnico? _tecnico;
  CreavoxOrden? _orden;

  Future<void> inicializar() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _cargar();
  }

  Future<void> _cargar() async {
    try {
      final t = _prefs?.getString(_keyTecnico);
      if (t != null) _tecnico = CreavoxTecnico.fromJsonString(t);
      final o = _prefs?.getString(_keyOrden);
      if (o != null) _orden = CreavoxOrden.fromJsonString(o);
    } catch (_) {}
  }

  Future<void> iniciarSesion(CreavoxTecnico tecnico) async {
    await inicializar();
    _tecnico = tecnico;
    await _prefs?.setString(_keyTecnico, tecnico.toJsonString());
    await _prefs?.setBool(_keyLoggedIn, true);
  }

  Future<void> cerrarSesion() async {
    await inicializar();
    _tecnico = null;
    _orden = null;
    await _prefs?.remove(_keyTecnico);
    await _prefs?.remove(_keyOrden);
    await _prefs?.setBool(_keyLoggedIn, false);
  }

  Future<void> guardarOrden(CreavoxOrden orden) async {
    await inicializar();
    _orden = orden;
    await _prefs?.setString(_keyOrden, orden.toJsonString());
  }

  bool isLoggedIn() =>
      _tecnico != null && (_prefs?.getBool(_keyLoggedIn) ?? false);

  CreavoxTecnico? getTecnico() => _tecnico;
  CreavoxOrden? getOrden() => _orden;
}

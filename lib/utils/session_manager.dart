import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/utils/device_helper.dart';
import 'package:agente_desconexiones/utils/rut_helper.dart';

/// Lectura de la sesión CREABOX desde SharedPreferences en tiempo real
/// (sin caché en memoria de valores).
class SessionManager {
  SessionManager._();

  /// Último RUT para el cual [nombre_tecnico]/[user_nombre] son válidos (evita nombre de otro técnico).
  static const String _kNombreAtadoRut = 'crea_nombre_atado_rut';

  static Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  /// Si el RUT actual no coincide con el último guardado de nombre, borra nombres en caché
  /// y los vuelve a cargar desde `dispositivos_autorizados` (fuente del panel CREABOX).
  static Future<void> asegurarNombreCoherenteConRutActual() async {
    final prefs = await _prefs();
    final rut = prefs.getString('rut_tecnico') ?? '';
    if (rut.isEmpty) {
      await prefs.remove(_kNombreAtadoRut);
      return;
    }
    final rutLimpio = RutHelper.limpiar(rut);
    final atadoRaw = prefs.getString(_kNombreAtadoRut);
    final atadoLimpio =
        (atadoRaw == null || atadoRaw.isEmpty) ? '' : RutHelper.limpiar(atadoRaw);
    if (atadoLimpio == rutLimpio) return;

    print(
        '🔁 [Sesión] Nombre cacheado no corresponde al RUT ($atadoRaw → $rutLimpio); refrescando desde panel');

    await prefs.remove('user_nombre');
    await prefs.remove('nombre_tecnico');

    try {
      final imei = await obtenerIdDispositivo();
      final row = await Supabase.instance.client
          .from('dispositivos_autorizados')
          .select('nombre_tecnico, rut_tecnico')
          .eq('imei', imei)
          .maybeSingle();

      if (row == null) {
        await prefs.setString(_kNombreAtadoRut, rutLimpio);
        return;
      }

      final rutDb = row['rut_tecnico']?.toString() ?? '';
      final rutDbL = rutDb.isEmpty ? '' : RutHelper.limpiar(rutDb);
      if (rutDbL != rutLimpio) {
        await prefs.setString(_kNombreAtadoRut, rutLimpio);
        return;
      }

      final n = row['nombre_tecnico']?.toString().trim();
      if (n != null && n.isNotEmpty) {
        await prefs.setString('user_nombre', n);
        await prefs.setString('nombre_tecnico', n);
      }
      await prefs.setString(_kNombreAtadoRut, rutLimpio);
    } catch (e) {
      print('⚠️ [Sesión] asegurarNombreCoherenteConRutActual: $e');
      await prefs.setString(_kNombreAtadoRut, rutLimpio);
    }
  }

  /// Llamar siempre que se persistan nombre y RUT juntos (registro, splash, panel).
  static Future<void> marcarNombreGuardadoParaRut(String rut) async {
    final r = rut.trim();
    if (r.isEmpty) return;
    final prefs = await _prefs();
    await prefs.setString(_kNombreAtadoRut, RutHelper.limpiar(r));
  }

  static Future<void> limpiarMarcadorNombreAtado() async {
    final prefs = await _prefs();
    await prefs.remove(_kNombreAtadoRut);
  }

  /// Precarga la instancia de prefs (opcional).
  static Future<void> init() async {
    await _prefs();
  }

  static Future<String> getNombreTecnico() async {
    final p = await _prefs();
    // Preferir `nombre_tecnico` (misma clave que CREA/Supabase); evita nombre viejo si `user_nombre` quedó desfasado.
    final n = p.getString('nombre_tecnico') ?? p.getString('user_nombre') ?? '';
    return n;
  }

  static Future<String> getRutTecnico() async {
    final p = await _prefs();
    return p.getString('rut_tecnico') ?? '';
  }

  static Future<String> getTipoPersonal() async {
    final p = await _prefs();
    return p.getString('tipo_personal') ?? '';
  }

  static Future<String> getRol() async {
    final p = await _prefs();
    final r = p.getString('user_rol') ?? p.getString('rol_usuario') ?? 'tecnico';
    return r.isEmpty ? 'tecnico' : r;
  }

  static Future<bool> esSupervisor() async {
    final r = await getRol();
    return r == 'supervisor' || r == 'ito';
  }

  static Future<String> getIniciales() async {
    final n = (await getNombreTecnico()).trim();
    final partes = n.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (partes.length >= 2) {
      return '${partes[0][0]}${partes[1][0]}'.toUpperCase();
    }
    return n.isNotEmpty ? n[0].toUpperCase() : '?';
  }

  static Future<bool> estaRegistrado() async {
    final r = await getRutTecnico();
    return r.isNotEmpty;
  }
}

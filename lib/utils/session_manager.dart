import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/services/logistica_service.dart';
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
    return p.getString('rut_tecnico') ??
        p.getString('user_rut') ??
        '';
  }

  /// RUT + nombre del técnico logueado (misma fuente que el home).
  /// Evita mostrar otro nombre en saldo / solicitudes de material.
  static Future<({String rut, String nombre})> identidadSesionMaterial() async {
    await asegurarNombreCoherenteConRutActual();
    final p = await _prefs();
    final rutRaw = p.getString('rut_tecnico') ?? p.getString('user_rut') ?? '';
    final rut = rutRaw.isEmpty ? '' : LogisticaService.canonicalRut(rutRaw);
    var nombre =
        (p.getString('nombre_tecnico') ?? p.getString('user_nombre') ?? '')
            .trim()
            .replaceAll(RegExp(r'\s+'), ' ');

    if (rut.isNotEmpty) {
      try {
        final desdeNomina = await LogisticaService().nombreDesdeNomina(rut);
        if (desdeNomina.isNotEmpty) {
          if (desdeNomina != nombre) {
            print(
                '🔁 [Sesión] Nombre prefs "$nombre" → nómina "$desdeNomina" ($rut)');
          }
          nombre = desdeNomina;
          await p.setString('nombre_tecnico', nombre);
          await p.setString('user_nombre', nombre);
          await marcarNombreGuardadoParaRut(rut);
        }
      } catch (e) {
        print('⚠️ [Sesión] identidadSesionMaterial sin nómina para $rut: $e');
      }
    }

    return (rut: rut, nombre: nombre);
  }

  /// RUT + nombre del bodeguero logueado (dispositivo → nómina bodega).
  /// Evita que quede el RUT/nombre de otro usuario al cambiar de cuenta en el mismo teléfono.
  static Future<({String rut, String nombre})> identidadBodeguero() async {
    await asegurarNombreCoherenteConRutActual();
    final p = await _prefs();

    var rut = '';
    var nombre = '';

    try {
      final imei = await obtenerIdDispositivo();
      final row = await Supabase.instance.client
          .from('dispositivos_autorizados')
          .select('rut_tecnico, nombre_tecnico')
          .eq('imei', imei)
          .maybeSingle();

      if (row != null) {
        final rutDb = row['rut_tecnico']?.toString().trim() ?? '';
        final nomDb = row['nombre_tecnico']?.toString().trim() ?? '';
        if (rutDb.isNotEmpty) {
          rut = LogisticaService.canonicalRut(rutDb);
          if (nomDb.isNotEmpty) nombre = nomDb;

          final prefsRut = LogisticaService.canonicalRut(
            p.getString('rut_tecnico') ?? p.getString('user_rut') ?? '',
          );
          if (prefsRut.isNotEmpty && prefsRut != rut) {
            print(
              '🔁 [Sesión Bodega] prefs RUT $prefsRut → dispositivo $rut',
            );
          }
          await p.setString('rut_tecnico', rut);
          await p.setString('user_rut', rut);
          if (nombre.isNotEmpty) {
            await p.setString('nombre_tecnico', nombre);
            await p.setString('user_nombre', nombre);
          }
          await marcarNombreGuardadoParaRut(rut);
        }
      }
    } catch (e) {
      print('⚠️ [Sesión Bodega] dispositivos_autorizados: $e');
    }

    if (rut.isEmpty) {
      final rutRaw = p.getString('rut_tecnico') ?? p.getString('user_rut') ?? '';
      rut = rutRaw.isEmpty ? '' : LogisticaService.canonicalRut(rutRaw);
      nombre =
          (p.getString('nombre_tecnico') ?? p.getString('user_nombre') ?? '')
              .trim()
              .replaceAll(RegExp(r'\s+'), ' ');
    }

    if (rut.isNotEmpty) {
      try {
        final desdeNomina = await LogisticaService().nombreDesdeNomina(rut);
        if (desdeNomina.isNotEmpty) {
          if (desdeNomina != nombre) {
            print(
              '🔁 [Sesión Bodega] nombre "$nombre" → nómina "$desdeNomina" ($rut)',
            );
          }
          nombre = desdeNomina;
          await p.setString('nombre_tecnico', nombre);
          await p.setString('user_nombre', nombre);
          await marcarNombreGuardadoParaRut(rut);
        }
      } catch (e) {
        print('⚠️ [Sesión Bodega] sin nómina para $rut: $e');
      }
    }

    return (rut: rut, nombre: nombre);
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

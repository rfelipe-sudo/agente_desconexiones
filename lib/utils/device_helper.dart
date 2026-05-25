import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_device_imei/flutter_device_imei.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/utils/rut_helper.dart';
import 'package:agente_desconexiones/services/produccion_service.dart';

/// Resultado de [verificarDispositivoSupabase].
class DeviceVerificationResult {
  const DeviceVerificationResult({
    required this.autorizado,
    required this.estado,
    required this.mensaje,
    this.rutTecnico,
    this.nombreTecnico,
    this.tipoPersonal,
    this.esVigente,
  });

  final bool autorizado;
  final String estado;
  final String mensaje;
  final String? rutTecnico;
  final String? nombreTecnico;
  final String? tipoPersonal;
  final bool? esVigente;
}

/// Identificador **único del hardware** para el panel (`dispositivos_autorizados.imei` / `p_imei`).
///
/// - Android: intenta [FlutterDeviceImei] (IMEI real en versiones antiguas con permiso;
///   en Android 10+ suele devolver el mismo ANDROID_ID que Settings.Secure).
/// - Fallback: [AndroidDeviceInfo.id].
/// - iOS: UUID de vendor vía plugin o [IosDeviceInfo.identifierForVendor].
///
/// **No** usar número de teléfono: dos técnicos pueden compartir línea corporativa;
/// el desambiguado es **este id + RUT** en backend.
Future<String> obtenerIdDispositivo() async {
  try {
    if (kIsWeb) {
      return 'web_unknown';
    }
    if (Platform.isAndroid) {
      try {
        final pluginId = await FlutterDeviceImei.instance.getIMEI();
        final v = (pluginId ?? '').trim();
        if (v.isNotEmpty && v != 'unknown') {
          print('📱 [Device] Identificador panel (plugin): len=${v.length} prefijo=${v.length > 6 ? v.substring(0, 6) : v}…');
          return v;
        }
      } catch (e) {
        print('⚠️ [Device] FlutterDeviceImei: $e — usando fallback');
      }
      final info = await DeviceInfoPlugin().androidInfo;
      final id = info.id.trim();
      print('📱 [Device] Identificador panel (androidId): len=${id.length}');
      return id;
    }
    if (Platform.isIOS) {
      try {
        final pluginId = await FlutterDeviceImei.instance.getIMEI();
        final v = (pluginId ?? '').trim();
        if (v.isNotEmpty && v != 'unknown') return v;
      } catch (_) {}
      final info = await DeviceInfoPlugin().iosInfo;
      return info.identifierForVendor ?? 'ios_unknown';
    }
    return 'unknown';
  } catch (e) {
    return 'error_${DateTime.now().millisecondsSinceEpoch}';
  }
}

/// Parámetros estándar para `verificar_dispositivo` (incluye `p_android_id` duplicado si el RPC lo acepta).
Future<Map<String, dynamic>> construirParamsVerificarDispositivo({
  required String rutTecnico,
  String? nombreTecnico,
  String? modelo,
}) async {
  final deviceId = await obtenerIdDispositivo();
  final m = modelo ?? await obtenerModeloDispositivo();
  return {
    'p_imei': deviceId,
    'p_android_id': deviceId,
    'p_rut_tecnico': rutTecnico,
    'p_nombre_tecnico': nombreTecnico,
    'p_modelo': m,
  };
}

/// Ejecuta `verificar_dispositivo`; si el RPC aún no tiene `p_android_id`, reintenta sin esa clave.
Future<dynamic> rpcVerificarDispositivo(
  SupabaseClient client, {
  required String rutTecnico,
  String? nombreTecnico,
}) async {
  final full = await construirParamsVerificarDispositivo(
    rutTecnico: rutTecnico,
    nombreTecnico: nombreTecnico,
  );
  try {
    return await client.rpc('verificar_dispositivo', params: full);
  } catch (e) {
    print('⚠️ [Device] verificar_dispositivo con p_android_id falló ($e); reintentando sin p_android_id');
    final minimal = <String, dynamic>{
      'p_imei': full['p_imei'],
      'p_rut_tecnico': full['p_rut_tecnico'],
      'p_nombre_tecnico': full['p_nombre_tecnico'],
      'p_modelo': full['p_modelo'],
    };
    return await client.rpc('verificar_dispositivo', params: minimal);
  }
}

/// Fabricante y modelo (ej. "samsung SM-G991B").
Future<String> obtenerModeloDispositivo() async {
  try {
    if (kIsWeb) {
      return 'Web';
    }
    if (Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      return '${info.manufacturer} ${info.model}'.trim();
    }
    if (Platform.isIOS) {
      final info = await DeviceInfoPlugin().iosInfo;
      return '${info.name} ${info.model}'.trim();
    }
    return 'unknown';
  } catch (e) {
    return 'unknown';
  }
}

Map<String, dynamic>? _parseRpcPrimeraFila(dynamic res) {
  if (res == null) return null;
  if (res is List) {
    if (res.isEmpty) return null;
    final f = res.first;
    if (f is Map<String, dynamic>) return Map<String, dynamic>.from(f);
    if (f is Map) return Map<String, dynamic>.from(f);
    return null;
  }
  if (res is Map<String, dynamic>) return Map<String, dynamic>.from(res);
  if (res is Map) return Map<String, dynamic>.from(res);
  return null;
}

/// Llama al RPC `verificar_dispositivo` (máx. [timeout]).
Future<DeviceVerificationResult?> verificarDispositivoSupabase({
  String? rutTecnico,
  String? nombreTecnico,
  Duration timeout = const Duration(seconds: 3),
}) async {
  try {
    final client = Supabase.instance.client;
    final raw = await rpcVerificarDispositivo(
      client,
      rutTecnico: rutTecnico ?? '',
      nombreTecnico: nombreTecnico,
    ).timeout(timeout);

    final data = _parseRpcPrimeraFila(raw);
    if (data == null) return null;

    final autorizado = data['autorizado'] == true;
    final estado = data['estado']?.toString() ?? 'bloqueado';
    final mensaje = data['mensaje']?.toString() ?? '';

    return DeviceVerificationResult(
      autorizado: autorizado,
      estado: estado,
      mensaje: mensaje,
      rutTecnico: data['rut_tecnico']?.toString(),
      nombreTecnico: data['nombre_tecnico']?.toString(),
      tipoPersonal: data['tipo_personal']?.toString(),
      esVigente: data['es_vigente'] is bool
          ? data['es_vigente'] as bool
          : null,
    );
  } catch (e) {
    print('[IMEI] Error verificando dispositivo: $e');
    return null;
  }
}

/// Si este [imei] ya figura en `dispositivos_autorizados` con otro RUT distinto de
/// [rutLimpio] (mismo criterio que [RutHelper.limpiar]), devuelve un mensaje para el usuario.
/// Si no hay fila, el RUT en BD está vacío o coincide, retorna `null` (sin conflicto).
Future<String?> comprobarConflictoDispositivoRut(String rutLimpio) async {
  try {
    final client = Supabase.instance.client;
    final imei = await obtenerIdDispositivo();
    final row = await client
        .from('dispositivos_autorizados')
        .select('rut_tecnico')
        .eq('imei', imei)
        .maybeSingle();

    if (row == null) return null;

    final dbRaw = row['rut_tecnico']?.toString().trim() ?? '';
    if (dbRaw.isEmpty) return null;

    final dbLimpio = RutHelper.limpiar(dbRaw);
    if (dbLimpio.isEmpty) return null;
    if (dbLimpio == rutLimpio) return null;

    final mostrar = RutHelper.formatear(dbLimpio);
    return 'Este teléfono ya está registrado con el RUT $mostrar. '
        'Solo puedes ingresar con ese mismo RUT.';
  } catch (e) {
    print('[Device] comprobarConflictoDispositivoRut: $e');
    return null;
  }
}

/// Si el RPC no encuentra al técnico, intenta [nomina_tecnicos] y [produccion_crea]
/// con las mismas variantes de formato que el resto de la app.
Future<Map<String, dynamic>?> _validarRutFallbackTablas(
  String limpio,
) async {
  try {
    final client = Supabase.instance.client;
    final variantes = ProduccionService.rutVariantes(limpio).toSet()
      ..add(limpio)
      ..add(limpio.replaceAll('-', ''));
    final lista = variantes.where((s) => s.isNotEmpty).toList();
    if (lista.isEmpty) return null;

    final nom = await client
        .from('nomina_tecnicos')
        .select('rut, nombres, paterno, materno')
        .inFilter('rut', lista)
        .limit(1)
        .maybeSingle();

    if (nom != null) {
      final nombre = '${nom['nombres'] ?? ''} ${nom['paterno'] ?? ''} ${nom['materno'] ?? ''}'
          .trim()
          .replaceAll(RegExp(r'\s+'), ' ');
      if (nombre.isNotEmpty) {
        print('[RUT] Fallback nomina_tecnicos OK: $nombre');
        return {
          'existe': true,
          'nombre': nombre,
        };
      }
    }

    final prod = await client
        .from('produccion_crea')
        .select('rut_tecnico, tecnico')
        .inFilter('rut_tecnico', lista)
        .limit(1)
        .maybeSingle();

    if (prod != null && prod['tecnico'] != null) {
      final nombre = prod['tecnico'].toString().trim();
      if (nombre.isNotEmpty) {
        print('[RUT] Fallback produccion_crea OK: $nombre');
        return {
          'existe': true,
          'nombre': nombre,
        };
      }
    }

    // Fallback plantel_tecnicos (bodegueros, supervisores, etc.)
    final plantel = await client
        .from('plantel_tecnicos')
        .select('rut, nombre_completo, cargo, estado, es_plantel_vigente')
        .inFilter('rut', lista)
        .limit(1)
        .maybeSingle();

    if (plantel != null && plantel['nombre_completo'] != null) {
      final nombre = plantel['nombre_completo'].toString().trim();
      if (nombre.isNotEmpty) {
        final vigente = plantel['es_plantel_vigente'] == true ||
            plantel['estado']?.toString().toLowerCase() == 'activo';
        print('[RUT] Fallback plantel_tecnicos OK: $nombre (${plantel['cargo']})');
        return {
          'existe': true,
          'nombre': nombre,
          'tipo_personal': plantel['cargo']?.toString() ?? '',
          'es_vigente': vigente,
          'rol': 'tecnico',
        };
      }
    }
  } catch (e) {
    print('[RUT] Error fallback nomina/produccion/plantel: $e');
  }
  return null;
}

/// RPC `validar_rut_tecnico` (nómina CREA); si no encuentra, [nomina_tecnicos] / [produccion_crea].
Future<Map<String, dynamic>?> validarRutTecnicoSupabase(
  String pRut, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final limpio = RutHelper.limpiar(pRut);
  if (limpio.isEmpty) return null;

  final client = Supabase.instance.client;

  Future<Map<String, dynamic>?> llamarRpc(String r) async {
    try {
      final raw = await client
          .rpc(
            'validar_rut_tecnico',
            params: {'p_rut': r},
          )
          .timeout(timeout);
      return _parseRpcPrimeraFila(raw);
    } catch (e) {
      print('[RUT] RPC validar_rut_tecnico("$r"): $e');
      return null;
    }
  }

  Map<String, dynamic>? rpcPrimera = await llamarRpc(limpio);
  if (rpcPrimera != null && rpcPrimera['existe'] == true) return rpcPrimera;

  final sinGuion = limpio.replaceAll('-', '');
  Map<String, dynamic>? rpcSegunda;
  if (sinGuion != limpio) {
    rpcSegunda = await llamarRpc(sinGuion);
    if (rpcSegunda != null && rpcSegunda['existe'] == true) return rpcSegunda;
  }

  final fb = await _validarRutFallbackTablas(limpio);
  if (fb != null) return fb;

  return rpcSegunda ?? rpcPrimera;
}

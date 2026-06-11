import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/solicitud_material.dart';
import 'logistica_service.dart';

// ── Modelos ──────────────────────────────────────────────────────────────────

class RecetaMaterial {
  final int id;
  final String nombre;
  final String sku;
  final String skuExterno;
  final double cantidadMax;
  final bool esSeriado;
  final String marca;
  final String modelo;

  const RecetaMaterial({
    required this.id,
    required this.nombre,
    required this.sku,
    required this.skuExterno,
    required this.cantidadMax,
    required this.esSeriado,
    required this.marca,
    required this.modelo,
  });

  factory RecetaMaterial.fromJson(Map<String, dynamic> j) => RecetaMaterial(
        id: (j['id_material'] as num).toInt(),
        nombre: j['nombre']?.toString() ?? '',
        sku: j['sku']?.toString() ?? '',
        skuExterno: j['sku_externo']?.toString() ?? '',
        cantidadMax: (j['cantidad_max'] as num? ?? 0).toDouble(),
        esSeriado: j['es_seriado'] as bool? ?? false,
        marca: j['marca']?.toString() ?? '',
        modelo: j['modelo']?.toString() ?? '',
      );

  /// Mapea a categoría `kMateriales` (misma lógica que saldo Kepler).
  String? categoriaConsumo() {
    final cat = LogisticaService.categorizar(nombre, sku: sku);
    if (cat != null) return cat;

    final n = nombre.toUpperCase();

    if (!esSeriado) {
      return _categoriaNoSeriadoPorNombre(n);
    }

    final mar = marca.toUpperCase();
    final mod = modelo.toUpperCase();

    if (n.contains('EXTENSOR') ||
        mod.contains('K562') ||
        mod.contains('H3601')) {
      return 'Extensor';
    }
    if (n.contains(' ONT') ||
        n.startsWith('ONT') ||
        n.contains(' ONU') ||
        n.startsWith('ONU') ||
        n.contains('GPON')) {
      if (mar.contains('HUAWEI') || n.contains('HUAWEI')) {
        return 'ONT Huawei';
      }
      if (mar.contains('ZTE') || n.contains('ZTE')) return 'ONT ZTE';
      return 'ONT ZTE';
    }
    if (n.contains('DECO') ||
        n.contains('DECODIFICADOR') ||
        n.contains('STB') ||
        n.contains('CPE') ||
        n.contains('FUSE')) {
      final skuNorm = sku.trim().toUpperCase();
      if (LogisticaService.skusDecodificadorClaro.contains(skuNorm) ||
          n.contains('CLARO')) {
        return 'Decodificador Claro';
      }
      return 'Decodificador VTR';
    }
    if (mar.contains('HUAWEI')) return 'ONT Huawei';
    if (mar.contains('ZTE')) return 'ONT ZTE';
    if (mar.contains('CLARO')) return 'Decodificador Claro';
    if (mar.isNotEmpty) return 'Decodificador VTR';
    return null;
  }

  static String? _categoriaNoSeriadoPorNombre(String n) {
    const aliases = <String, String>{
      'DROP 100': 'Drop 100m',
      'DROP 150': 'Drop 150m',
      'DROP 200': 'Drop 200m',
      'DROP 220': 'Drop 200m',
      'DROP 300': 'Drop 300m',
      'FICHA ABONADO': 'Ficha de abonado',
      'FICHA DE ABONADO': 'Ficha de abonado',
      'SOPORTE DROP': 'Soportes drop',
      'SOPORTES DROP': 'Soportes drop',
      'CANCAMO': 'Cáncamos',
      'CÁNCAMO': 'Cáncamos',
      'AMARRA': 'Amarras plásticas',
      'PASAMURO NEGRO': 'Pasacable negro',
      'PASACABLE NEGRO': 'Pasacable negro',
      'PASAMURO BLANCO': 'Pasacable blanco',
      'PASACABLE BLANCO': 'Pasacable blanco',
      'GRAMPA NEGRA': 'Grampa negra',
      'GRAMPA BLANCA': 'Grampa blanca',
      'ROSETA': 'Roseta',
      'CONECTOR DE CAMPO': 'Conector de campo',
      'JUMPER': 'Jumper',
      'ADAPTADOR USB': 'Micro USB',
      'MICRO USB': 'Micro USB',
      'CABLE UTP': 'Cable UTP',
      'RJ45': 'Conector RJ45',
    };

    for (final e in aliases.entries) {
      if (n.contains(e.key)) return e.value;
    }

    for (final km in kMateriales.where((m) => !m.esSeriado)) {
      final kn = km.nombre.toUpperCase();
      if (n.contains(kn) || kn.contains(n)) return km.nombre;
      final palabras = kn.split(' ').where((p) => p.length > 3);
      if (palabras.isNotEmpty && palabras.every((p) => n.contains(p))) {
        return km.nombre;
      }
    }
    return null;
  }
}

class Receta {
  final int id;
  final String nombre;
  final List<RecetaMaterial> materiales;

  const Receta({
    required this.id,
    required this.nombre,
    required this.materiales,
  });

  factory Receta.fromJson(Map<String, dynamic> j) => Receta(
        id: (j['id_receta'] as num).toInt(),
        nombre: j['nombre']?.toString() ?? '',
        materiales: (j['materiales'] as List? ?? [])
            .map((m) => RecetaMaterial.fromJson(m as Map<String, dynamic>))
            .toList(),
      );

  RecetaMaterial? materialPorId(int idMaterial) {
    for (final m in materiales) {
      if (m.id == idMaterial) return m;
    }
    return null;
  }
}

/// OT pendiente de registrar consumo de material (respuesta KRP).
class OrdenPendienteConsumo {
  final int id;
  final String codigoExterno;
  final int idReceta;
  final int idTrabajador;
  final String tipoActividad;
  final String nombreCliente;
  final String direccionCliente;
  final String comunaCliente;
  final String fechaCierre;
  final bool finalizada;

  const OrdenPendienteConsumo({
    required this.id,
    required this.codigoExterno,
    required this.idReceta,
    required this.idTrabajador,
    required this.tipoActividad,
    required this.nombreCliente,
    required this.direccionCliente,
    required this.comunaCliente,
    required this.fechaCierre,
    required this.finalizada,
  });

  factory OrdenPendienteConsumo.fromJson(Map<String, dynamic> j) =>
      OrdenPendienteConsumo(
        id: (j['id'] as num).toInt(),
        codigoExterno: j['codigo_externo']?.toString() ?? '',
        idReceta: (j['id_receta'] as num?)?.toInt() ?? 0,
        idTrabajador: (j['id_trabajador'] as num?)?.toInt() ?? 0,
        tipoActividad: j['tipo_actividad']?.toString() ?? '',
        nombreCliente: j['nombre_cliente']?.toString() ?? '',
        direccionCliente: j['direccion_cliente']?.toString() ?? '',
        comunaCliente: j['comuna_cliente']?.toString() ?? '',
        fechaCierre: j['fecha_cierre']?.toString() ?? '',
        finalizada: j['finalizada'] as bool? ?? false,
      );
}

class ConsumoResult {
  final bool exito;
  final String mensaje;
  const ConsumoResult({required this.exito, required this.mensaje});
}

// ── Servicio ─────────────────────────────────────────────────────────────────

class RecetasConsumoService {
  static const _apiToken = '5de53e7b5f89b6b547c5c93d635f162ae2594756';
  static const _baseUrl = 'https://logistica.sbip.cl/movimientos/ot_api';
  static const _recetasUrl = '$_baseUrl/get_recetas';
  static const _consumoUrl = '$_baseUrl/consume_ot';
  static const _trabajadoresUrl = 'http://logistica.sbip.cl/get_all_trabajadores';
  static const _krpApiBase = 'https://logistica.sbip.cl/api/tecnico';
  // Mismas credenciales que /api/get_all_materiales (TransferenciasService).
  static const _krpApiUser = 'bmCgfkIydlMu';
  static const _krpApiPass = 'bfoBIkNKSHDCThgpEWEF';

  Map<String, String> get _headersOtApi => {
        'api-token': _apiToken,
        'Content-Type': 'application/json',
      };

  Map<String, String> get _headersKrpApi => {
        'Authorization': 'Basic ${base64Encode(utf8.encode('$_krpApiUser:$_krpApiPass'))}',
        'Content-Type': 'application/json',
      };

  // ── OTs pendientes ─────────────────────────────────────────────────────────

  Future<List<OrdenPendienteConsumo>> getOtsPendienteConsumo({
    required String rut,
    int page = 1,
    int perPage = 50,
  }) async {
    final rutCanon = _canonicalRut(rut);
    if (rutCanon.isEmpty) {
      throw Exception('RUT de técnico inválido');
    }

    final uri = Uri.parse(
      '$_krpApiBase/$rutCanon/ordenes_trabajo/pendientes_consumo',
    ).replace(queryParameters: {
      'page': '$page',
      'per_page': '$perPage',
    });

    debugPrint('[ConsumoKRP] GET $uri');

    final resp = await http
        .get(uri, headers: _headersKrpApi)
        .timeout(const Duration(seconds: 25));

    if (resp.statusCode != 200) {
      throw Exception('Error cargando OTs pendientes (${resp.statusCode})');
    }

    final parsed = _parseOtsPendientes(resp.body);
    if (parsed == null) {
      throw Exception('Respuesta inválida de OTs pendientes');
    }

    debugPrint('[ConsumoKRP] ${parsed.length} OTs pendientes');
    return parsed;
  }

  List<OrdenPendienteConsumo>? _parseOtsPendientes(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return null;

    if (decoded['success'] == false) {
      throw Exception(
          decoded['error']?.toString() ?? 'KRP rechazó la consulta de OTs');
    }

    final lista = decoded['data'];
    if (lista is! List) return null;

    return lista
        .whereType<Map>()
        .map((o) => OrdenPendienteConsumo.fromJson(
            Map<String, dynamic>.from(o)))
        .where((o) => o.codigoExterno.isNotEmpty)
        .toList();
  }

  // ── Recetas ────────────────────────────────────────────────────────────────

  Future<List<Receta>> getRecetas() async {
    final resp = await http
        .get(Uri.parse(_recetasUrl), headers: _headersOtApi)
        .timeout(const Duration(seconds: 20));

    if (resp.statusCode != 200) {
      throw Exception('Error cargando recetas (${resp.statusCode})');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final lista = data['recetas'] as List? ?? [];
    return lista
        .map((r) => Receta.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  List<RecetaMaterial> materialesParaReceta(
    List<Receta> recetas,
    int idReceta,
  ) {
    for (final r in recetas) {
      if (r.id == idReceta) return r.materiales;
    }
    return const [];
  }

  String? nombreReceta(List<Receta> recetas, int idReceta) {
    for (final r in recetas) {
      if (r.id == idReceta) return r.nombre;
    }
    return null;
  }

  // ── Id trabajador KRP ──────────────────────────────────────────────────────

  Future<int?> resolverIdTrabajador(String rut) async {
    final rutNorm = _normRut(rut);
    if (rutNorm.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    final prefKey = 'krp_id_trabajador_$rutNorm';
    final cached = prefs.getInt(prefKey);
    if (cached != null) return cached;

    try {
      final resp = await http
          .get(Uri.parse(_trabajadoresUrl))
          .timeout(const Duration(seconds: 20));

      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final lista = data['data'] as List? ?? [];

      for (final t in lista) {
        if (_normRut(t['rut']?.toString() ?? '') == rutNorm) {
          final id = (t['id'] as num).toInt();
          await prefs.setInt(prefKey, id);
          return id;
        }
      }
    } catch (_) {}
    return null;
  }

  // ── Envío de consumo ───────────────────────────────────────────────────────

  Future<ConsumoResult> submitConsumo({
    required String ordenDeTrabajo,
    required int idTrabajador,
    required List<List<dynamic>> noSeriados,
    required List<List<dynamic>> seriados,
  }) async {
    final payload = {
      'orden_de_trabajo': ordenDeTrabajo.trim(),
      'id_trabajador': idTrabajador,
      'no_seriados': noSeriados,
      'seriados': seriados,
    };

    debugPrint(
      '[Consumo] POST $_consumoUrl\n'
      '  OT: ${ordenDeTrabajo.trim()}\n'
      '  id_trabajador: $idTrabajador\n'
      '  no_seriados: ${noSeriados.length} · seriados: ${seriados.length}',
    );

    try {
      final resp = await http
          .post(
            Uri.parse(_consumoUrl),
            headers: _headersOtApi,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 30));

      debugPrint(
        '[Consumo] resp ${resp.statusCode}: '
        '${resp.body.length > 500 ? '${resp.body.substring(0, 500)}…' : resp.body}',
      );

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final rechazo = _mensajeRechazoEnBody(resp.body);
        if (rechazo != null) {
          return ConsumoResult(
            exito: false,
            mensaje: 'KRP rechazó el consumo (HTTP ${resp.statusCode}): $rechazo',
          );
        }
        return const ConsumoResult(exito: true, mensaje: 'Consumo registrado');
      }

      String msg = 'HTTP ${resp.statusCode}';
      try {
        final b = jsonDecode(resp.body);
        if (b is Map<String, dynamic>) {
          msg = b['error']?.toString() ??
              b['message']?.toString() ??
              b['detail']?.toString() ??
              b['mensaje']?.toString() ??
              msg;
        }
      } catch (_) {
        if (resp.body.isNotEmpty) {
          msg = resp.body.length > 300
              ? '${resp.body.substring(0, 300)}…'
              : resp.body;
        }
      }
      return ConsumoResult(exito: false, mensaje: msg);
    } catch (e) {
      debugPrint('[Consumo] error de red: $e');
      return ConsumoResult(exito: false, mensaje: e.toString());
    }
  }

  /// Algunos endpoints responden 200 con `success: false` en el JSON.
  String? _mensajeRechazoEnBody(String body) {
    if (body.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if (map['success'] == false || map['ok'] == false) {
        return map['error']?.toString() ??
            map['message']?.toString() ??
            map['detail']?.toString() ??
            map['mensaje']?.toString() ??
            'respuesta success=false sin detalle';
      }
    } catch (_) {}
    return null;
  }

  static String _normRut(String rut) =>
      rut.replaceAll(RegExp(r'[.\- ]'), '').toUpperCase();

  /// Formato URL KRP: 12345678-9
  static String _canonicalRut(String rut) {
    final k = _normRut(rut);
    if (k.length < 2) return rut.trim();
    return '${k.substring(0, k.length - 1)}-${k.substring(k.length - 1)}';
  }
}

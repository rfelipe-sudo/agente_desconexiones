import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Puerto del endpoint Kepler Traza con el nivel inicial de potencia
class PuertoKepler {
  final int portNumber;
  final double inicial;
  final bool isCurrent;
  /// ID físico del puerto en la CTO, ej: "1/4/9/12" (viene de niveles_inicial)
  final String? portId;

  const PuertoKepler({
    required this.portNumber,
    required this.inicial,
    required this.isCurrent,
    this.portId,
  });

  factory PuertoKepler.fromJson(Map<String, dynamic> json) {
    return PuertoKepler(
      portNumber: (json['port_number'] as num).toInt(),
      inicial: (json['inicial'] as num).toDouble(),
      isCurrent: json['is_current'] as bool? ?? false,
      portId: json['port_id']?.toString(),
    );
  }

  /// Último segmento del portId (ej: "1/4/9/12" → "12"), null si no aplica.
  String? get portSuffix {
    if (portId == null || !portId!.contains('/')) return null;
    return portId!.split('/').last;
  }
}

/// Un puerto del CTO con su estado y niveles RX
class PuertoCTO {
  final int numero;
  final String? portId;
  final String? status;
  final String? description;
  final double? rxActual;
  final double? rxBefore;

  PuertoCTO({
    required this.numero,
    this.portId,
    this.status,
    this.description,
    this.rxActual,
    this.rxBefore,
  });

  bool get activo => portId != null && portId!.isNotEmpty;
  bool get ok => status == 'OK';

  /// Último segmento del portId (ej: "1/1/3/12" → "12"), para cruzar con Kepler.
  String? get portSuffix {
    if (portId == null || !portId!.contains('/')) return null;
    return portId!.split('/').last;
  }

  double? get rxDelta {
    if (rxActual == null || rxBefore == null) return null;
    return rxActual! - rxBefore!;
  }

  static double? _parseRx(String? val) {
    if (val == null || val.isEmpty) return null;
    // Formato: "-23.468 dBm"
    return double.tryParse(val.replaceAll(RegExp(r'[^0-9.\-]'), '').trim());
  }

  factory PuertoCTO.fromJson(int numero, Map<String, dynamic> result) {
    final n = numero.toString();
    return PuertoCTO(
      numero: numero,
      portId: result['u_cto_port${n}_ID']?.toString(),
      status: result['u_cto_port${n}_status']?.toString(),
      description: result['u_cto_port${n}_description_status']?.toString(),
      rxActual: _parseRx(result['u_cto_port${n}_rx_actual']?.toString()),
      rxBefore: _parseRx(result['u_cto_port${n}_rx_before']?.toString()),
    );
  }
}

/// Resultado completo de la consulta al estado del vecino (CTO)
class EstadoCTO {
  final String accessId;
  final String vnoId;
  final int totalPuertos;
  final int puertosOk;
  final int puertosNok;
  final double porcentajeOk;
  final List<PuertoCTO> puertos;

  EstadoCTO({
    required this.accessId,
    required this.vnoId,
    required this.totalPuertos,
    required this.puertosOk,
    required this.puertosNok,
    required this.porcentajeOk,
    required this.puertos,
  });

  factory EstadoCTO.fromJson(Map<String, dynamic> json) {
    final dynamic resultRaw = json['result'];
    final Map<String, dynamic> r;
    if (resultRaw is Map<String, dynamic>) {
      r = resultRaw;
    } else if (resultRaw is List && resultRaw.isNotEmpty && resultRaw.first is Map) {
      r = Map<String, dynamic>.from(resultRaw.first as Map);
    } else {
      throw Exception('Campo "result" inválido en respuesta CTO');
    }
    final puertos = List.generate(16, (i) => PuertoCTO.fromJson(i + 1, r))
        .where((p) => p.activo)
        .toList();
    return EstadoCTO(
      accessId: r['u_access_id_vno']?.toString() ?? '',
      vnoId: r['u_id_vno']?.toString() ?? '',
      totalPuertos: int.tryParse(r['u_cto_quantity_access']?.toString() ?? '0') ?? 0,
      puertosOk: int.tryParse(r['u_cto_quantity_access_ok']?.toString() ?? '0') ?? 0,
      puertosNok: int.tryParse(r['u_cto_quantity_access_nok']?.toString() ?? '0') ?? 0,
      porcentajeOk: double.tryParse(r['u_cto_percentage_access_ok']?.toString() ?? '0') ?? 0,
      puertos: puertos,
    );
  }
}

/// Servicio para consultar la API Nyquist (estado CTO / vecino)
/// Las credenciales se almacenan en la tabla configuracion_app de Supabase
class NyquistService {
  static final NyquistService _instance = NyquistService._internal();
  factory NyquistService() => _instance;
  NyquistService._internal();

  final _supabase = Supabase.instance.client;

  // Valores por defecto (si configuracion_app no tiene las claves en Supabase)
  static const String _defaultUser     = '0npVpRUG7MegtpmfdDuJ3A';
  static const String _defaultPassword = 'Ddw3u241Y0MN_x7ezZixKIJtk1ZRHpG6Zz2tCYrhXVg';
  static const String _defaultBaseUrl  = 'https://nyquisttraza.sbip.cl';
  static const String _defaultVnoId   = '02';

  // Cache en memoria para no releer Supabase en cada consulta
  String? _user;
  String? _password;
  String? _baseUrl;
  String? _vnoId;

  /// Carga las credenciales desde Supabase (si no están en caché)
  Future<void> _cargarCredenciales() async {
    if (_user != null) return; // Ya cargadas

    try {
      final response = await _supabase
          .from('configuracion_app')
          .select('clave, valor')
          .inFilter('clave', ['nyquist_user', 'nyquist_password', 'nyquist_base_url', 'nyquist_vno_id']);

      final lista = List<Map<String, dynamic>>.from(response as List);
      for (var item in lista) {
        switch (item['clave']) {
          case 'nyquist_user':     _user    = item['valor']; break;
          case 'nyquist_password': _password = item['valor']; break;
          case 'nyquist_base_url': _baseUrl  = item['valor']; break;
          case 'nyquist_vno_id':   _vnoId    = item['valor']; break;
        }
      }
      print('✅ [Nyquist] Credenciales cargadas desde Supabase');
      print('   → nyquist_user: ${_user?.isNotEmpty == true ? "✅ (${_user!.length} chars)" : "❌ VACÍO"}');
      print('   → nyquist_password: ${_password?.isNotEmpty == true ? "✅ (${_password!.length} chars)" : "❌ VACÍO"}');
      print('   → nyquist_base_url: ${_baseUrl ?? "❌ VACÍO (usará default)"}');
      print('   → nyquist_vno_id: ${_vnoId ?? "❌ VACÍO (usará 02)"}');
    } catch (e) {
      print('❌ [Nyquist] Error cargando credenciales: $e');
      rethrow;
    }
  }

  /// Construye el access_id a partir del número de OT.
  /// Carga las credenciales primero para usar el vno_id de Supabase.
  /// Formato: "{vnoId}-{ot}"  → ej: "02-1-3FCTFPHL"
  Future<String> buildAccessId(String ot) async {
    await _cargarCredenciales();
    final vno = (_vnoId?.isNotEmpty == true) ? _vnoId! : _defaultVnoId;
    return '$vno-$ot';
  }

  /// CREABOX: orden iniciada desde `produccion_crea` (Kepler/Nyquist).
  /// Retorna mapa compatible con Asistente CTO: access_id, orden_de_trabajo, tipo_red_producto.
  Future<Map<String, String>?> buscarAccessIdPorRut(String rut) async {
    try {
      await _cargarCredenciales();
      final vno = (_vnoId?.isNotEmpty == true) ? _vnoId! : _defaultVnoId;

      print('🔍 [Nyquist/CREA] produccion_crea para RUT: $rut');

      final response = await _supabase
          .from('produccion_crea')
          .select('orden_trabajo, access_id, tipo_orden')
          .eq('rut_tecnico', rut)
          .eq('estado', 'Iniciado')
          .not('access_id', 'is', null)
          .neq('access_id', '')
          .order('hora_inicio', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;

      final tipoRed = response['tipo_orden']?.toString() ?? '';
      final accessRaw = response['access_id']?.toString().trim() ?? '';
      final ot = response['orden_trabajo']?.toString().trim() ?? '';

      var accessFull = accessRaw;
      if (accessRaw.isNotEmpty) {
        final tienePrefijoVno = RegExp(r'^\d{1,2}-').hasMatch(accessRaw);
        accessFull = tienePrefijoVno ? accessRaw : '$vno-$accessRaw';
      }

      print('🔍 [Nyquist/CREA] OT: "$ot" | AccessID: "$accessFull"');

      return {
        'access_id': accessFull,
        'id_actividad': ot,
        'tipo_red_producto': tipoRed,
        'orden_de_trabajo': ot,
      };
    } catch (e, stack) {
      print('❌ [Nyquist] Error en buscarAccessIdPorRut: $e');
      print('❌ [Nyquist] Stack: $stack');
      return null;
    }
  }

  /// Busca un access_id en la tabla por Orden de Trabajo (uso supervisor/ITO).
  /// Retorna mapa con access_id prefijado, tipo_red_producto, etc. o null.
  Future<Map<String, String>?> buscarAccessIdPorOT(String ot) async {
    try {
      await _cargarCredenciales();
      final vno = (_vnoId?.isNotEmpty == true) ? _vnoId! : _defaultVnoId;

      print('🔍 [Nyquist-Sup] Buscando por OT: $ot');

      final response = await _supabase
          .from('produccion_crea')
          .select('access_id, tipo_orden, orden_trabajo, estado')
          .eq('orden_trabajo', ot)
          .order('hora_inicio', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) {
        print('🔍 [Nyquist-Sup] OT no encontrada: $ot');
        return null;
      }

      final accessIdCorto = response['access_id']?.toString().trim() ?? '';
      final tipoRed = response['tipo_orden']?.toString() ?? '';
      print('✅ [Nyquist-Sup] OT=$ot → AccessID=$accessIdCorto | TipoRed=$tipoRed');

      var accessFull = accessIdCorto;
      if (accessIdCorto.isNotEmpty &&
          !RegExp(r'^\d{1,2}-').hasMatch(accessIdCorto)) {
        accessFull = '$vno-$accessIdCorto';
      }

      return {
        'access_id': accessFull,
        'tipo_red_producto': tipoRed,
        'orden_de_trabajo': ot,
        'id_actividad': response['orden_trabajo']?.toString() ?? '',
        'estado': response['estado']?.toString() ?? '',
      };
    } catch (e) {
      print('❌ [Nyquist-Sup] Error en buscarAccessIdPorOT: $e');
      return null;
    }
  }

  /// Obtiene el tipo_red_producto del técnico (sin requerir orden iniciada,
  /// útil para la card de producción).
  Future<String?> obtenerTipoRedTecnico(String rut) async {
    try {
      final response = await _supabase
          .from('produccion_crea')
          .select('tipo_orden')
          .eq('rut_tecnico', rut)
          .order('hora_inicio', ascending: false)
          .limit(1)
          .maybeSingle();
      return response?['tipo_orden']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Consulta el estado del vecino para un access_id dado
  Future<EstadoCTO> consultarEstado(String accessId) async {
    await _cargarCredenciales();

    final user     = (_user?.isNotEmpty == true)     ? _user!     : _defaultUser;
    final password = (_password?.isNotEmpty == true) ? _password! : _defaultPassword;
    final baseUrl  = (_baseUrl?.isNotEmpty == true)  ? _baseUrl!  : _defaultBaseUrl;

    final bytes = utf8.encode('$user:$password');
    final basicAuth = base64.encode(bytes);

    final url = Uri.parse('$baseUrl/onfide/estado-vecino?access_id=$accessId');

    print('🌐 [Nyquist] Llamando: $url');
    print('🌐 [Nyquist] User presente: ${user.isNotEmpty} | Pass presente: ${password.isNotEmpty}');

    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Basic $basicAuth',
        'Content-Type': 'application/json',
      },
    ).timeout(const Duration(seconds: 45));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    print('📡 [Nyquist] Respuesta raw (primeros 300 chars): ${response.body.substring(0, response.body.length.clamp(0, 300))}');

    final dynamic decoded = jsonDecode(response.body);

    // La API puede devolver un Map o una List con un único elemento
    final Map<String, dynamic> json;
    if (decoded is Map<String, dynamic>) {
      json = decoded;
    } else if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
      json = Map<String, dynamic>.from(decoded.first as Map);
    } else {
      throw Exception('Formato de respuesta inesperado del CTO: ${response.body.substring(0, response.body.length.clamp(0, 200))}');
    }

    if (json['success'] != true) {
      throw Exception('API error: ${json['error']}');
    }

    return EstadoCTO.fromJson(json);
  }

  /// Invalida la caché de credenciales (útil si se cambian en Supabase)
  void invalidarCache() {
    _user = _password = _baseUrl = _vnoId = null;
  }

  // ── Kepler Traza ──────────────────────────────────────────────────────────

  static const String _keplerTrazaApiKey =
      'GqRWZIJ7132PJCWCdvXmrYsGCCST-eAnwFMEsnXSrSl_Bq9vpPc8Hml4_X-o9axg';
  static const String _keplerTrazaBaseUrl = 'https://keplertraza.sbip.cl';

  /// Hora de la consulta inicial según Kepler (se actualiza en fetchIniciales).
  String? lastKeplerHoraInicial;

  /// Obtiene los niveles iniciales por puerto desde Kepler Traza.
  /// [accessId] es el access_id corto sin prefijo VNO, ej: "1-3IRTCLXQ"
  Future<List<PuertoKepler>> fetchIniciales(String accessId) async {
    final url = Uri.parse(
        '$_keplerTrazaBaseUrl/api/v1/toa/panel_order/$accessId');
    print('🌐 [Kepler] Consultando iniciales: $url');

    final response = await http.get(url, headers: {
      'Authorization': 'Bearer $_keplerTrazaApiKey',
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 30));

    print('🌐 [Kepler] HTTP: ${response.statusCode}');
    print('🌐 [Kepler] Content-Type: ${response.headers['content-type']}');
    print('🌐 [Kepler] Body (400 chars): ${response.body.substring(0, response.body.length.clamp(0, 400))}');

    if (response.statusCode != 200) {
      throw Exception('Error Kepler Traza: HTTP ${response.statusCode}');
    }

    // Detectar respuesta HTML (redirect de auth o error de proxy)
    final bodyTrimmed = response.body.trim();
    if (bodyTrimmed.startsWith('<')) {
      throw Exception(
          'Kepler Traza devolvió HTML (posible error de autenticación o endpoint incorrecto).\n'
          'Body: ${bodyTrimmed.substring(0, bodyTrimmed.length.clamp(0, 200))}');
    }

    final dynamic decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Respuesta Kepler inesperada: ${response.body.substring(0, 200)}');
    }

    // Guardar la hora de la consulta inicial reportada por Kepler
    lastKeplerHoraInicial = decoded['horario_consulta_inicial']?.toString();

    final alertas = decoded['alertas'];
    if (alertas is! Map<String, dynamic>) {
      throw Exception('Campo "alertas" no encontrado en respuesta Kepler');
    }

    final ports = alertas['ports'];
    if (ports is! List) return [];

    // Construir mapa portNumber → portId desde niveles_inicial (tiene el ID físico)
    final Map<int, String?> portIdByNumber = {};
    final nivelesInicial = decoded['niveles_inicial'];
    if (nivelesInicial is List) {
      for (final item in nivelesInicial.whereType<Map>()) {
        final pn = (item['port_number'] as num?)?.toInt();
        final pid = item['port_id']?.toString();
        if (pn != null) portIdByNumber[pn] = pid;
      }
    }

    final result = ports
        .whereType<Map>()
        .map((p) {
          final map = Map<String, dynamic>.from(p);
          // Inyectar port_id al mapa antes de parsear
          final pn = (map['port_number'] as num?)?.toInt();
          if (pn != null && portIdByNumber.containsKey(pn)) {
            map['port_id'] = portIdByNumber[pn];
          }
          return PuertoKepler.fromJson(map);
        })
        .where((p) => p.inicial != 0.0)
        .toList();

    print('✅ [Kepler] ${result.length} puertos con inicial válido');
    return result;
  }
}

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

/// Una fila de la tabla `produccion_crea` representando una OT del técnico.
/// Usada por el historial de "Revisar Estado CTO".
class OrdenHistorial {
  const OrdenHistorial({
    required this.ordenTrabajo,
    required this.accessIdPrefijado,
    required this.tipoOrden,
    required this.estado,
    required this.fechaReferencia,
    this.horaInicio,
    this.horaTermino,
  });

  /// Número de OT (ej. "1-3FCTFPHL").
  final String ordenTrabajo;

  /// Access ID con prefijo VNO. Vacío si la fila no tiene access_id asignado.
  final String accessIdPrefijado;

  final String tipoOrden;
  final String estado;

  /// La fecha que se usa para agrupar en la UI: `hora_termino` si existe,
  /// si no `hora_inicio`.
  final DateTime fechaReferencia;

  final DateTime? horaInicio;
  final DateTime? horaTermino;

  bool get tieneAccessId => accessIdPrefijado.isNotEmpty;
  bool get esIniciada => estado.toLowerCase() == 'iniciado';
}

/// Orden activa del técnico devuelta por Kepler `get_pelo_db/$rut`. Trae
/// los puertos con la numeración FÍSICA correcta (la misma que la web).
class KeplerActiveOrder {
  final String accessIdCorto;       // "1-3KSLBJ7G"
  final String accessIdPrefijado;   // "02-1-3KSLBJ7G"
  final EstadoCTO estado;

  const KeplerActiveOrder({
    required this.accessIdCorto,
    required this.accessIdPrefijado,
    required this.estado,
  });
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

/// Servicio para consultar la API Nyquist (estado CTO / vecino).
///
/// Credenciales hardcodeadas, idéntico al módulo `turing-android` original.
/// **No** se leen desde Supabase — el lookup de `produccion_crea` por RUT/OT
/// sí usa Supabase porque es data del propio CREABOX, no del proveedor.
class NyquistService {
  static final NyquistService _instance = NyquistService._internal();
  factory NyquistService() => _instance;
  NyquistService._internal();

  final _supabase = Supabase.instance.client;

  // Credenciales Basic Auth para Nyquist (turing-android baseline).
  static const String _nyquistUser     = '0npVpRUG7MegtpmfdDuJ3A';
  static const String _nyquistPassword = 'Ddw3u241Y0MN_x7ezZixKIJtk1ZRHpG6Zz2tCYrhXVg';
  // Endpoint correcto: nyquist.sbip.cl (no nyquistbio).
  static const String _nyquistBaseUrl  = 'https://nyquist.sbip.cl';
  static const String _nyquistVnoId    = '02';

  /// Construye el access_id a partir del número de OT.
  /// Formato: "{vnoId}-{ot}"  → ej: "02-1-3FCTFPHL"
  String buildAccessId(String ot) => '$_nyquistVnoId-$ot';

  /// CREABOX: busca un access_id activo en `tabla_access_id` por RUT del
  /// técnico. La tabla solo tiene 3 columnas: `rut_tecnico`, `access_id`,
  /// `orden_trabajo` — sin estado/fecha/tipo. Por eso devolvemos cualquier
  /// fila válida (la más reciente que el motor entregue), sin filtros de
  /// estado ni `tipo_red_producto`.
  Future<Map<String, String>?> buscarAccessIdPorRut(String rut) async {
    try {
      print('🔍 [Nyquist/CREA] tabla_access_id para RUT: $rut');

      final response = await _supabase
          .from('tabla_access_id')
          .select('rut_tecnico, access_id, orden_trabajo, fecha_trabajo')
          .eq('rut_tecnico', rut)
          .not('access_id', 'is', null)
          .neq('access_id', '')
          .order('fecha_trabajo', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) {
        print('🔍 [Nyquist/CREA] sin filas en tabla_access_id para RUT=$rut');
        return null;
      }

      // En tabla_access_id el access_id viene PELADO (sin VNO). Nyquist
      // exige el prefijo "{VNO}-" siempre, así que lo anteponemos.
      final accessRaw = response['access_id']?.toString().trim() ?? '';
      final accessFull = accessRaw.isEmpty ? '' : '$_nyquistVnoId-$accessRaw';
      final ot = response['orden_trabajo']?.toString().trim() ?? '';

      print('🔍 [Nyquist/CREA] OT: "$ot" | AccessID raw: "$accessRaw" → "$accessFull"');

      return {
        'access_id': accessFull,
        'id_actividad': ot,
        // tabla_access_id no expone tipo_red_producto. Devolvemos vacío para
        // que el screen no caiga en `tecnologia_incompatible`.
        'tipo_red_producto': '',
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
      const vno = _nyquistVnoId;

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

  /// Trae las órdenes del técnico desde `tabla_access_id`, filtradas a los
  /// últimos [dias] días por `fecha_trabajo` y ordenadas descendente.
  /// La tabla no tiene `estado` ni `tipo_orden`, así que esos campos quedan
  /// vacíos en el resultado.
  Future<List<OrdenHistorial>> buscarHistorialPorRut(
    String rut, {
    int dias = 30,
  }) async {
    final r = rut.trim();
    if (r.isEmpty) return [];

    // Sin prefiltro de fecha: si la columna `fecha_trabajo` viene como
    // `date` (no `timestamptz`), el `gte` con `toIso8601String()` falla.
    // Mejor traemos todo y ordenamos local; el filtro de [dias] lo
    // aplicamos después contra la fecha parseada.
    List<dynamic> rows;
    try {
      final resp = await _supabase
          .from('tabla_access_id')
          .select('rut_tecnico, access_id, orden_trabajo, fecha_trabajo')
          .eq('rut_tecnico', r)
          .order('fecha_trabajo', ascending: false);
      rows = List<dynamic>.from(resp as List);
    } catch (e) {
      print('❌ [Nyquist/CREA] historial error: $e');
      rows = <dynamic>[];
    }

    print('🔍 [Nyquist/CREA] historial RUT="$r" → ${rows.length} filas');
    if (rows.isNotEmpty) {
      final f = (rows.first as Map);
      print('🔍 [Nyquist/CREA] sample row → '
          'fecha_trabajo=${f['fecha_trabajo']} | '
          'access_id=${f['access_id']} | '
          'orden_trabajo=${f['orden_trabajo']}');
    }
    final hoyLog = DateTime.now();
    print('🔍 [Nyquist/CREA] now=$hoyLog (local). Detalle por fila:');
    for (var i = 0; i < rows.length && i < 5; i++) {
      final raw = rows[i] as Map;
      final fc = raw['fecha_trabajo'];
      print('  [$i] raw=$fc | ot=${raw['orden_trabajo']}');
    }

    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      if (s.isEmpty) return null;
      // Cualquier cadena que empiece por `YYYY-MM-DD` la tratamos como
      // fecha LOCAL pura, ignorando hora/timezone. Cubre `date`,
      // `timestamp` y `timestamptz` de Postgres por igual y evita el
      // shift de zona horaria que descalza el filtro de "hoy" (ej:
      // "2026-05-05T00:00:00Z" → 2026-05-04 20:00 en Chile).
      final ymd = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
      if (ymd != null) {
        return DateTime(
          int.parse(ymd.group(1)!),
          int.parse(ymd.group(2)!),
          int.parse(ymd.group(3)!),
        );
      }
      // Formato chileno `dd/MM/yy` o `dd/MM/yyyy` (con o sin hora detrás).
      // Acepta año de 2 o 4 dígitos: "26" se asume 2026, "2026" tal cual.
      final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2,4})').firstMatch(s);
      if (m != null) {
        var y = int.parse(m.group(3)!);
        if (y < 100) y += 2000;
        return DateTime(y, int.parse(m.group(2)!), int.parse(m.group(1)!));
      }
      return null;
    }

    final corte = DateTime.now().subtract(Duration(days: dias));
    final out = <OrdenHistorial>[];
    for (final m in rows.whereType<Map>()) {
      final raw = Map<String, dynamic>.from(m);
      final ot = (raw['orden_trabajo'] ?? '').toString().trim();
      final accessRaw = (raw['access_id'] ?? '').toString().trim();
      // Mismo criterio que buscarAccessIdPorRut: prefijar siempre con VNO.
      final accessFull = accessRaw.isEmpty ? '' : '$_nyquistVnoId-$accessRaw';
      final fecha = parseDate(raw['fecha_trabajo']);
      // Filtro de [dias] aplicado en cliente (sólo si pudimos parsear fecha).
      if (fecha != null && fecha.isBefore(corte)) continue;
      out.add(OrdenHistorial(
        ordenTrabajo: ot,
        accessIdPrefijado: accessFull,
        tipoOrden: '',
        estado: '',
        fechaReferencia: fecha ?? DateTime.now(),
        horaInicio: fecha,
        horaTermino: null,
      ));
    }
    return out;
  }

  /// Consulta el estado del vecino para un access_id dado.
  /// Credenciales hardcodeadas (idéntico a turing-android).
  Future<EstadoCTO> consultarEstado(String accessId) async {
    final basicAuth = base64.encode(utf8.encode('$_nyquistUser:$_nyquistPassword'));
    final url = Uri.parse('$_nyquistBaseUrl/onfide/estado-vecino?access_id=$accessId');

    print('🌐 [Nyquist] GET $url');

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

    print('📡 [Nyquist] Respuesta (300 chars): ${response.body.substring(0, response.body.length.clamp(0, 300))}');

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

  // ── Kepler v2 (orden activa por RUT) ───────────────────────────────────

  /// Endpoint que devuelve la **orden activa** del técnico, con la
  /// numeración FÍSICA de puertos (port1..port8 con gaps en los no usados),
  /// idéntica a la que muestra la web. Esto resuelve la inconsistencia con
  /// Nyquist, que usa una numeración compacta por sufijo de `position`.
  ///
  /// Devuelve `null` si Kepler no encuentra la orden o no hay snapshot
  /// con datos de puertos. Lanza excepción solo en errores de red/HTTP.
  ///
  /// El resultado expone:
  /// - `accessIdCorto`   ej. "1-3KSLBJ7G"
  /// - `accessIdPrefijado` ej. "02-1-3KSLBJ7G"
  /// - `estado`          un `EstadoCTO` listo para pintar la tabla.
  Future<KeplerActiveOrder?> fetchActiveOrderFromKepler(String rut) async {
    final url = Uri.parse('https://keplerv2.sbip.cl/api/v1/toa/get_pelo_db/$rut');
    print('🌐 [Kepler/get_pelo_db] $url');

    final response = await http.get(url).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Kepler get_pelo_db HTTP ${response.statusCode}');
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) return null;
    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      print('🌐 [Kepler/get_pelo_db] sin "data" para RUT=$rut');
      return null;
    }

    // Snapshot con datos: completado > final > intermedio > inicial.
    Map<String, dynamic>? niveles;
    String? snapKey;
    for (final key in const [
      'niveles_completado',
      'niveles_final',
      'niveles_intermedio',
      'niveles_inicial',
    ]) {
      final n = data[key];
      if (n is Map<String, dynamic>) {
        final hasData = List<int>.generate(16, (i) => i + 1)
            .any((i) => n['u_cto_port${i}_ID'] != null);
        if (hasData) { niveles = n; snapKey = key; break; }
      }
    }
    if (niveles == null) {
      print('🌐 [Kepler/get_pelo_db] data sin niveles_*');
      return null;
    }
    print('🌐 [Kepler/get_pelo_db] usando snapshot=$snapKey');

    final accessIdCorto = data['access_id']?.toString() ?? '';
    final accessIdPrefijado =
        niveles['u_access_id_vno']?.toString() ??
            (accessIdCorto.isEmpty ? '' : '$_nyquistVnoId-$accessIdCorto');

    // Reusamos EstadoCTO.fromJson — espera un mapa con clave `result`.
    final estado = EstadoCTO.fromJson({'result': niveles});

    return KeplerActiveOrder(
      accessIdCorto: accessIdCorto,
      accessIdPrefijado: accessIdPrefijado,
      estado: estado,
    );
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

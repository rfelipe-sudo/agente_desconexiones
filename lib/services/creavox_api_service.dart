import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:agente_desconexiones/models/creavox_tecnico.dart';
import 'package:agente_desconexiones/models/creavox_orden.dart';

class CreavoxApiService {
  static const _faradayUrl = 'https://faraday.sbip.cl/toa';
  static const _keplerUrl = 'https://kepler.sbip.cl/api/v1/toa';
  static const _faradayUser = 'jon';
  static const _faradayPass = 'athan';
  static const _timeout = Duration(seconds: 30);

  Map<String, String> get _faradayHeaders => {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$_faradayUser:$_faradayPass'))}',
        'Content-Type': 'application/json',
      };

  Future<CreavoxTecnico?> loginTecnico(String rut) async {
    try {
      final resp = await http
          .get(Uri.parse('$_faradayUrl/tecnicos_supervisores'),
              headers: _faradayHeaders)
          .timeout(_timeout);

      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final lista = data['tecnicos_supervisores'] as List<dynamic>? ?? [];

      final rutNorm = rut.replaceAll(RegExp(r'[.\-]'), '');
      final match = lista.firstWhere(
        (t) =>
            (t['rut_tecnico'] as String)
                .replaceAll(RegExp(r'[.\-]'), '') ==
            rutNorm,
        orElse: () => null,
      );

      if (match == null) return null;

      final tecnico = CreavoxTecnico(
        rutTecnico: match['rut_tecnico'].toString(),
        nombreTecnico: match['nombre_tecnico'].toString(),
        nombreSupervisor: match['nombre_supervisor'].toString(),
        rutSupervisor: '',
        active: match['active'] as bool? ?? true,
      );

      return tecnico.active ? tecnico : null;
    } catch (_) {
      return null;
    }
  }

  Future<CreavoxOrden?> getOrdenActiva(String rutTecnico) async {
    try {
      final resp = await http
          .get(Uri.parse('$_keplerUrl/get_data_toa_other_enterprise'),
              headers: {'Content-Type': 'application/json'})
          .timeout(_timeout);

      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final ordenes = data['data'] as List<dynamic>? ?? [];

      final rutNorm = rutTecnico.replaceAll(RegExp(r'[.\-]'), '');
      final match = ordenes.firstWhere(
        (o) =>
            (o['Rut_tecnico']?.toString() ?? '')
                .replaceAll(RegExp(r'[.\-]'), '') ==
            rutNorm,
        orElse: () => null,
      );

      if (match == null) return null;

      return CreavoxOrden(
        ordenDeTrabajo: match['Orden_de_Trabajo']?.toString() ?? '',
        nombreCompletoCliente:
            match['Nombre Completo Cliente']?.toString() ?? '',
        direccion: match['Dirección']?.toString() ?? '',
        zonaDeTrabajo: match['Zona de trabajo']?.toString() ?? '',
        tipoActividad: match['tipo_actividad']?.toString() ?? '',
        coordX: _coord(match['Coord_X']),
        coordY: _coord(match['Coord_Y']),
        telefonoInternacional: _phone(match['Teléfono Celular']),
        rutTecnico: match['Rut_tecnico']?.toString(),
        estado: match['Estado']?.toString() ?? 'asignada',
      );
    } catch (_) {
      return null;
    }
  }

  static double _coord(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  static String _phone(dynamic p) {
    if (p == null) return '';
    var s = p.toString().replaceAll(RegExp(r'[^\d]'), '');
    if (s.length == 9 && !s.startsWith('56')) s = '56$s';
    if (!s.startsWith('+')) s = '+$s';
    return s;
  }
}

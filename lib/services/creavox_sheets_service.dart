import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:agente_desconexiones/models/ast_registro.dart' show ASTRegistro;
import 'package:agente_desconexiones/services/creavox_session_service.dart';

class CreavoxSheetsService {
  static const _scriptUrl =
      'https://script.google.com/macros/s/AKfycbwI8CPXG_FKdncHmGjI-xgyVhDh0OChg_z12NMKhGMorj7MVjJf04o59VEvmMyo4iDU/exec';

  final _session = CreavoxSessionService();

  Future<bool> guardarAST(ASTRegistro registro, {File? foto, File? firma}) async {
    try {
      final tecnico = _session.getTecnico();

      String? fotoBase64;
      if (foto != null && await foto.exists()) {
        fotoBase64 = base64Encode(await foto.readAsBytes());
      }

      String? firmaBase64;
      if (firma != null && await firma.exists()) {
        firmaBase64 = base64Encode(await firma.readAsBytes());
      }

      final data = {
        'tipo': 'ast',
        'timestamp': registro.fechaHora.toIso8601String(),
        'rut_tecnico': tecnico?.rutTecnico ?? '',
        'orden_trabajo': registro.ordenTrabajo,
        'nombre_tecnico': registro.nombreTecnico,
        'cargo': registro.cargo,
        'empresa': registro.empresa,
        'lugar_actividad': registro.lugarActividad,
        'tareas_realizar': registro.tareasRealizar.join(', '),
        'riesgos_identificados': registro.riesgosIdentificados.join(', '),
        'medidas_control': registro.medidasControl.join(', '),
        'equipos_proteccion': registro.equiposProteccion.join(', '),
        'dispositivos_seguridad': registro.dispositivosSeguridad.join(', '),
        'herramientas_utilizar': registro.herramientasUtilizar.join(', '),
        'estado_herramientas': registro.estadoHerramientas,
        'condiciones_criticas': registro.condicionesCriticas,
        'condiciones_climaticas': registro.condicionesClimaticas,
        'observaciones': registro.observaciones,
        'latitud': registro.latitud,
        'longitud': registro.longitud,
        if (fotoBase64 != null) 'foto_base64': fotoBase64,
        if (firmaBase64 != null) 'firma_base64': firmaBase64,
      };

      final resp = await http
          .post(
            Uri.parse(_scriptUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 30));

      return resp.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:agente_desconexiones/constants/app_constants.dart';
import 'package:agente_desconexiones/models/alerta.dart';

/// Servicio para comunicarse con el panel Kepler
class KeplerApiService {
  static final KeplerApiService _instance = KeplerApiService._internal();
  factory KeplerApiService() => _instance;
  KeplerApiService._internal();

  String? _authToken;
  
  /// Configura el token de autenticación
  void setAuthToken(String token) {
    _authToken = token;
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_authToken != null) 'Authorization': 'Bearer $_authToken',
  };

  /// Obtiene las alertas pendientes del técnico
  Future<List<Alerta>> obtenerAlertasPendientes(String tecnicoId) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}${AppConstants.alertasEndpoint}?tecnico_id=$tecnicoId&estado=pendiente'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => Alerta.fromWebhook(json)).toList();
      } else {
        throw Exception('Error obteniendo alertas: ${response.statusCode}');
      }
    } catch (e) {
      print('Error en obtenerAlertasPendientes: $e');
      rethrow;
    }
  }

  /// Obtiene las alertas escaladas para el supervisor
  Future<List<Alerta>> obtenerAlertasEscaladas() async {
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}${AppConstants.alertasEndpoint}?estado=escalada'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => Alerta.fromWebhook(json)).toList();
      } else {
        throw Exception('Error obteniendo alertas escaladas: ${response.statusCode}');
      }
    } catch (e) {
      print('Error en obtenerAlertasEscaladas: $e');
      rethrow;
    }
  }

  /// Actualiza el estado de una alerta
  Future<void> actualizarEstadoAlerta(String alertaId, EstadoAlerta estado) async {
    try {
      final response = await http.patch(
        Uri.parse('${AppConstants.apiBaseUrl}${AppConstants.alertasEndpoint}/$alertaId'),
        headers: _headers,
        body: jsonEncode({
          'estado': estado.name,
          'fecha_actualizacion': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Error actualizando alerta: ${response.statusCode}');
      }
    } catch (e) {
      print('Error en actualizarEstadoAlerta: $e');
      rethrow;
    }
  }

  /// Posterga una alerta (solo se puede hacer 1 vez, 5 minutos)
  Future<void> postergarAlerta(String alertaId) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}${AppConstants.alertasEndpoint}/$alertaId/postergar'),
        headers: _headers,
        body: jsonEncode({
          'minutos': 5,
          'fecha_postergacion': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Error postergando alerta: ${response.statusCode}');
      }
    } catch (e) {
      print('Error en postergarAlerta: $e');
      rethrow;
    }
  }

  /// Escala una alerta al supervisor
  Future<void> escalarAlerta(String alertaId, String motivo) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}${AppConstants.alertasEndpoint}/$alertaId/escalar'),
        headers: _headers,
        body: jsonEncode({
          'motivo': motivo,
          'fecha_escalamiento': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Error escalando alerta: ${response.statusCode}');
      }
    } catch (e) {
      print('Error en escalarAlerta: $e');
      rethrow;
    }
  }

  /// Verifica el estado de una CTO en el panel
  Future<bool> verificarEstadoCto(String accessId) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}${AppConstants.verificarEstadoEndpoint}?access_id=$accessId'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['regularizado'] == true;
      } else {
        throw Exception('Error verificando CTO: ${response.statusCode}');
      }
    } catch (e) {
      print('Error en verificarEstadoCto: $e');
      rethrow;
    }
  }

  /// Sube fotos georeferenciadas para una alerta de churn
  Future<void> subirFotosAlerta(String alertaId, List<String> fotoPaths, Map<String, double> ubicacion) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConstants.apiBaseUrl}${AppConstants.alertasEndpoint}/$alertaId/fotos'),
      );
      
      request.headers.addAll(_headers);
      
      request.fields['latitud'] = ubicacion['latitud'].toString();
      request.fields['longitud'] = ubicacion['longitud'].toString();
      request.fields['fecha'] = DateTime.now().toIso8601String();
      
      for (var i = 0; i < fotoPaths.length; i++) {
        request.files.add(
          await http.MultipartFile.fromPath('foto_$i', fotoPaths[i]),
        );
      }
      
      final response = await request.send();
      
      if (response.statusCode != 200) {
        throw Exception('Error subiendo fotos: ${response.statusCode}');
      }
    } catch (e) {
      print('Error en subirFotosAlerta: $e');
      rethrow;
    }
  }

  /// Registra el token FCM del dispositivo
  Future<void> registrarTokenFcm(String usuarioId, String fcmToken) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/api/usuarios/$usuarioId/fcm-token'),
        headers: _headers,
        body: jsonEncode({
          'fcm_token': fcmToken,
          'plataforma': 'flutter',
          'fecha_registro': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Error registrando token FCM: ${response.statusCode}');
      }
    } catch (e) {
      print('Error en registrarTokenFcm: $e');
      rethrow;
    }
  }

  /// Cierra una alerta como resuelta
  Future<void> cerrarAlerta(String alertaId, {String? notas}) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}${AppConstants.alertasEndpoint}/$alertaId/cerrar'),
        headers: _headers,
        body: jsonEncode({
          'fecha_cierre': DateTime.now().toIso8601String(),
          if (notas != null) 'notas': notas,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Error cerrando alerta: ${response.statusCode}');
      }
    } catch (e) {
      print('Error en cerrarAlerta: $e');
      rethrow;
    }
  }
}


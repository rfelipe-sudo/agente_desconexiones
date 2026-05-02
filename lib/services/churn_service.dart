import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:agente_desconexiones/constants/app_constants.dart';
import 'package:agente_desconexiones/services/kepler_api_service.dart';
import 'package:agente_desconexiones/services/tecnico_service.dart';

/// Estados del flujo CHURN
enum EstadoChurn {
  idle,
  detectado,
  capturandoFotos,
  enviandoACalidad,
  esperandoValidacion,
  aprobado,
  rechazado,
  timeout,
  error,
}

/// Resultado de la validación de calidad
enum ResultadoValidacion {
  aprobado,
  rechazado,
  timeout,
  error,
}

/// Servicio para manejar el flujo completo de CHURN
class ChurnService extends ChangeNotifier {
  static final ChurnService _instance = ChurnService._internal();
  factory ChurnService() => _instance;
  ChurnService._internal();

  final ImagePicker _picker = ImagePicker();
  final KeplerApiService _keplerApi = KeplerApiService();

  EstadoChurn _estado = EstadoChurn.idle;
  EstadoChurn get estado => _estado;

  List<File> _fotosTomadas = [];
  List<File> get fotosTomadas => List.unmodifiable(_fotosTomadas);

  String? _ticketId;
  String? get ticketId => _ticketId;

  String? _comentarioCalidad;
  String? get comentarioCalidad => _comentarioCalidad;

  DateTime? _inicioEspera;
  DateTime? get inicioEspera => _inicioEspera;

  Timer? _timerValidacion;
  Timer? _timerCountdown;

  int _tiempoRestanteSegundos = 300; // 5 minutos
  int get tiempoRestanteSegundos => _tiempoRestanteSegundos;

  /// Detecta que se requiere flujo CHURN
  void detectarChurn() {
    _estado = EstadoChurn.detectado;
    _fotosTomadas.clear();
    _ticketId = null;
    _comentarioCalidad = null;
    _tiempoRestanteSegundos = 300;
    notifyListeners();
    print('📷 CHURN detectado - Iniciando flujo de captura de fotos');
  }

  /// Toma una foto usando SOLO la cámara (sin galería)
  Future<File?> tomarFoto() async {
    try {
      _setEstado(EstadoChurn.capturandoFotos);

      final XFile? foto = await _picker.pickImage(
        source: ImageSource.camera, // SOLO CÁMARA
        imageQuality: 80,
        maxWidth: 1920,
        maxHeight: 1080,
      );

      if (foto != null) {
        final file = File(foto.path);
        _fotosTomadas.add(file);
        print('📷 Foto tomada: ${foto.path} (Total: ${_fotosTomadas.length})');
        notifyListeners();
        return file;
      }

      _setEstado(EstadoChurn.detectado);
      return null;
    } catch (e) {
      print('❌ Error tomando foto: $e');
      _setEstado(EstadoChurn.error);
      return null;
    }
  }

  /// Elimina una foto de la lista
  void eliminarFoto(int index) {
    if (index >= 0 && index < _fotosTomadas.length) {
      _fotosTomadas.removeAt(index);
      notifyListeners();
      print('🗑️ Foto eliminada (Total: ${_fotosTomadas.length})');
    }
  }

  /// Envía las fotos a Calidad
  Future<String?> enviarACalidad({
    required String ot,
    String? tecnico,
  }) async {
    // Obtener nombre del técnico registrado si no se proporciona
    String nombreTecnico = tecnico ?? '';
    if (nombreTecnico.isEmpty) {
      final tecnicoRegistrado = await TecnicoService.verificarRegistro();
      nombreTecnico = tecnicoRegistrado?.nombre ?? 'Técnico';
      print('👤 Usando nombre de técnico registrado para CHURN: $nombreTecnico');
    }
    if (_fotosTomadas.isEmpty) {
      print('⚠️ No hay fotos para enviar');
      return null;
    }

    try {
      _setEstado(EstadoChurn.enviandoACalidad);

      // Crear request multipart
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('https://kepler.sbip.cl/api/v1/app/churn/evidencia'),
      );
      
      // Agregar headers con Authorization Bearer
      request.headers.addAll(AppConstants.keplerHeaders);

      request.fields['ot'] = ot;
      request.fields['tecnico'] = nombreTecnico;
      request.fields['timestamp'] = DateTime.now().toIso8601String();
      request.fields['cantidad_fotos'] = _fotosTomadas.length.toString();

      // Adjuntar fotos
      for (int i = 0; i < _fotosTomadas.length; i++) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'foto_$i',
            _fotosTomadas[i].path,
          ),
        );
      }

      print('📤 Enviando ${_fotosTomadas.length} fotos a Calidad...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body);
        _ticketId = json['ticket_id'] as String?;
        print('✅ Fotos enviadas. Ticket ID: $_ticketId');
        
        // Iniciar espera de validación
        _iniciarEsperaValidacion();
        return _ticketId;
      } else {
        print('❌ Error enviando fotos: ${response.statusCode} - ${response.body}');
        _setEstado(EstadoChurn.error);
        return null;
      }
    } catch (e) {
      print('❌ Error enviando fotos a Calidad: $e');
      _setEstado(EstadoChurn.error);
      return null;
    }
  }

  /// Inicia la espera de validación (máximo 5 minutos)
  void _iniciarEsperaValidacion() {
    _setEstado(EstadoChurn.esperandoValidacion);
    _inicioEspera = DateTime.now();
    _tiempoRestanteSegundos = 300; // 5 minutos

    // Timer para consultar estado cada 15 segundos
    _timerValidacion = Timer.periodic(const Duration(seconds: 15), (timer) async {
      if (_ticketId == null) {
        timer.cancel();
        return;
      }

      try {
        final resultado = await consultarEstadoValidacion(_ticketId!);
        
        if (resultado != null) {
          timer.cancel();
          _timerCountdown?.cancel();
          
          switch (resultado) {
            case ResultadoValidacion.aprobado:
              _setEstado(EstadoChurn.aprobado);
              break;
            case ResultadoValidacion.rechazado:
              _setEstado(EstadoChurn.rechazado);
              break;
            case ResultadoValidacion.timeout:
              _setEstado(EstadoChurn.timeout);
              break;
            case ResultadoValidacion.error:
              _setEstado(EstadoChurn.error);
              break;
          }
        }
      } catch (e) {
        print('❌ Error consultando estado: $e');
      }
    });

    // Timer para countdown
    _timerCountdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_tiempoRestanteSegundos > 0) {
        _tiempoRestanteSegundos--;
        notifyListeners();
      } else {
        timer.cancel();
        _timerValidacion?.cancel();
        _setEstado(EstadoChurn.timeout);
      }
    });
  }

  /// Consulta el estado de validación de un ticket
  Future<ResultadoValidacion?> consultarEstadoValidacion(String ticketId) async {
    try {
      final response = await http.get(
        Uri.parse('https://kepler.sbip.cl/api/v1/app/churn/estado/$ticketId'),
        headers: AppConstants.keplerHeaders,
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final estado = json['estado'] as String?;
        _comentarioCalidad = json['comentario'] as String?;

        print('📊 Estado de validación: $estado');

        switch (estado) {
          case 'aprobado':
            return ResultadoValidacion.aprobado;
          case 'rechazado':
            return ResultadoValidacion.rechazado;
          case 'pendiente':
            return null; // Sigue esperando
          default:
            return ResultadoValidacion.error;
        }
      } else {
        print('❌ Error consultando estado: ${response.statusCode}');
        return ResultadoValidacion.error;
      }
    } catch (e) {
      print('❌ Error consultando estado de validación: $e');
      return ResultadoValidacion.error;
    }
  }

  /// Reinicia el flujo para tomar más fotos (cuando es rechazado)
  void reiniciarParaMasFotos() {
    _fotosTomadas.clear();
    _ticketId = null;
    _comentarioCalidad = null;
    _tiempoRestanteSegundos = 300;
    _setEstado(EstadoChurn.detectado);
    _timerValidacion?.cancel();
    _timerCountdown?.cancel();
    print('🔄 Reiniciando flujo CHURN para tomar más fotos');
  }

  /// Cancela el flujo CHURN
  void cancelar() {
    _timerValidacion?.cancel();
    _timerCountdown?.cancel();
    _fotosTomadas.clear();
    _ticketId = null;
    _comentarioCalidad = null;
    _tiempoRestanteSegundos = 300;
    _setEstado(EstadoChurn.idle);
    print('❌ Flujo CHURN cancelado');
  }

  /// Obtiene el mensaje para el agente según el resultado
  String obtenerMensajeParaAgente() {
    switch (_estado) {
      case EstadoChurn.aprobado:
        return 'Calidad aprobó las fotos. Puedes continuar con la instalación. ¡Buen trabajo!';
      case EstadoChurn.rechazado:
        return 'Calidad necesita más fotos. ¿Puedes tomar algunas adicionales más claras?';
      case EstadoChurn.timeout:
        return 'No tuve respuesta de calidad en 5 minutos. Voy a escalar esto a tu supervisor para que te apoyen.';
      case EstadoChurn.error:
        return 'Hubo un error procesando las fotos. Por favor, intenta de nuevo.';
      default:
        return '';
    }
  }

  void _setEstado(EstadoChurn nuevoEstado) {
    _estado = nuevoEstado;
    notifyListeners();
  }

  @override
  void dispose() {
    _timerValidacion?.cancel();
    _timerCountdown?.cancel();
    super.dispose();
  }
}


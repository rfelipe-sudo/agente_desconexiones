import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:agente_desconexiones/models/alerta.dart';
import 'package:agente_desconexiones/services/elevenlabs_service.dart';
import 'package:agente_desconexiones/services/kepler_api_service.dart';
import 'package:agente_desconexiones/services/alerta_contexto_service.dart';
import 'package:agente_desconexiones/services/churn_service.dart';
import 'package:agente_desconexiones/services/tecnico_service.dart';
import 'package:agente_desconexiones/services/alertas_cto_service.dart';

/// Estados del agente CREA
enum CreaState {
  idle,
  connecting,
  listening,
  speaking,
  processing,
  error,
  disconnected,
}

/// Servicio para interactuar con el agente de voz CREA via ElevenLabs
class CreaAgentService extends ChangeNotifier {
  static final CreaAgentService _instance = CreaAgentService._internal();
  factory CreaAgentService() => _instance;
  CreaAgentService._internal();

  final ElevenLabsService _elevenLabs = ElevenLabsService();
  final KeplerApiService _keplerApi = KeplerApiService();
  final AlertaContextoService _contextoService = AlertaContextoService();
  final ChurnService _churnService = ChurnService();
  final AlertasCTOService _alertasCTOService = AlertasCTOService();
  
  CreaState _state = CreaState.idle;
  CreaState get state => _state;
  
  String _lastTranscript = '';
  String get lastTranscript => _lastTranscript;
  String _lastTranscriptAdded = ''; // Para evitar duplicados
  String _lastResponseAdded  = ''; // Para evitar duplicados de respuestas
  
  String _agentResponse = '';
  String get agentResponse => _agentResponse;
  
  Alerta? _alertaActual;
  Alerta? get alertaActual => _alertaActual;
  
  bool _tecnicoAceptoVolverAContactar = false;
  bool get tecnicoAceptoVolverAContactar => _tecnicoAceptoVolverAContactar;
  
  bool _requiereFotoOtraCompania = false;
  bool get requiereFotoOtraCompania => _requiereFotoOtraCompania;
  
  Timer? _progresoTimer;
  
  StreamSubscription? _transcriptSub;
  StreamSubscription? _responseSub;
  StreamSubscription? _eventSub;
  
  final StreamController<String> _transcriptController = 
      StreamController<String>.broadcast();
  Stream<String> get transcriptStream => _transcriptController.stream;
  
  final StreamController<String> _responseController = 
      StreamController<String>.broadcast();
  Stream<String> get responseStream => _responseController.stream;

  bool get isConnected => _elevenLabs.state == ElevenLabsState.connected ||
                          _elevenLabs.state == ElevenLabsState.listening ||
                          _elevenLabs.state == ElevenLabsState.speaking;

  bool get isMuted => _elevenLabs.isMuted;

  /// Envía un mensaje de texto al agente
  void enviarMensajeTexto(String texto) {
    _elevenLabs.sendTextMessage(texto);
  }

  /// Inicia una sesión con el agente CREA para una alerta
  /// [esperar3Minutos] Si es true, después de verificar comunicación espera 3 minutos y vuelve a llamar
  /// [esReconexion] Si es true, indica que es una segunda llamada/reconexión (no debe repetir el script inicial)
  Future<bool> iniciarSesion(Alerta alerta, {bool esperar3Minutos = false, bool esReconexion = false}) async {
    _alertaActual = alerta;
    _setState(CreaState.connecting);
    
    try {
      // PASO 1: Obtener el estado guardado de esa alerta
      var estadoContexto = _contextoService.obtenerEstado(alerta.numeroOt);
      
      // PASO 2: Si no existe estado → es "nueva"
      if (estadoContexto == EstadoContextoAlerta.nueva) {
        await _contextoService.marcarComoNueva(alerta);
        print('📝 Alerta ${alerta.numeroOt} marcada como NUEVA (primera conversación)');
      }
      
      // IMPORTANTE: Si es reconexión, SIEMPRE forzar en_progreso para usar el mensaje de seguimiento
      // Esto asegura que el agente use el script de reconexión, no el inicial
      if (esReconexion && estadoContexto != EstadoContextoAlerta.regularizada) {
        estadoContexto = EstadoContextoAlerta.enProgreso;
        print('🔄 RECONEXIÓN detectada - Forzando estado a EN_PROGRESO para mensaje de seguimiento');
      }
      
      // Obtener nombre del técnico registrado en la app
      final tecnicoRegistrado = await TecnicoService.verificarRegistro();
      final nombreTecnico = tecnicoRegistrado?.nombre ?? alerta.nombreTecnico;
      print('👤 Usando nombre de técnico registrado: $nombreTecnico');
      
      // PASO 3: Calcular el primer mensaje según el estado de la alerta
      final mensajeInicial = _contextoService.calcularPrimerMensaje(
        alerta,
        nombreTecnico,
      );
      print('💬 Primer mensaje calculado para estado: ${estadoContexto.name}');
      print('💬 FirstMessage: $mensajeInicial');
      
      // Preparar contexto de la alerta para el agente
      // IMPORTANTE: Los nombres deben coincidir EXACTAMENTE con las variables del agente en ElevenLabs
      // Extraer solo el número del pelo (ej: "P-04" -> "4", "4" -> "4")
      final peloNumero = alerta.numeroPelo.replaceAll(RegExp(r'[^0-9]'), '');
      
      // Formatear el valor de consulta para que el agente lo entienda correctamente
      // Si es negativo, mantener el signo negativo
      final valorConsultaStr = alerta.valorConsulta1.toStringAsFixed(2);
      
      final customData = {
        'nombre_tecnico': nombreTecnico,
        'numero_pelo': peloNumero.isEmpty ? alerta.numeroPelo.replaceAll(RegExp(r'[^0-9]'), '') : peloNumero, // Solo el número, sin "P-"
        'valor_consulta1': valorConsultaStr, // Formato con 2 decimales
        'es_reconexion': esReconexion ? 'si' : 'no', // Indicar si es una reconexión
        'tipo_llamada': esReconexion ? 'reconexion' : 'inicial', // Tipo de llamada para el agente
        // Variable adicional para hacer más explícito el cambio de script
        'es_segunda_llamada': esReconexion ? 'si' : 'no', // Variable adicional para el agente
        // Contexto de la alerta
        'estado_contexto': estadoContexto.name, // "nueva", "en_progreso", "regularizada"
        'mensaje_inicial': mensajeInicial, // Mensaje inicial según el estado (usar este mensaje al iniciar)
      };
      
      print('📤 Enviando variables dinámicas al agente:');
      print('   - nombre_tecnico: ${customData['nombre_tecnico']}');
      print('   - numero_pelo: ${customData['numero_pelo']}');
      print('   - valor_consulta1: ${customData['valor_consulta1']}');
      print('   - es_reconexion: ${customData['es_reconexion']} (${esReconexion ? "RECONEXIÓN" : "LLAMADA INICIAL"})');
      print('   - tipo_llamada: ${customData['tipo_llamada']} (${esReconexion ? "RECONEXIÓN" : "LLAMADA INICIAL"})');
      print('   - es_segunda_llamada: ${customData['es_segunda_llamada']}');
      print('   - estado_contexto: ${customData['estado_contexto']}');
      print('   - mensaje_inicial: ${customData['mensaje_inicial']}');
      print('⚠️ IMPORTANTE: El agente debe usar estas variables para cambiar el script según el tipo de llamada');
      print('⚠️ Si tipo_llamada == "reconexion" o es_reconexion == "si", NO debe repetir el saludo inicial completo');
      print('⚠️ El agente debe usar el mensaje_inicial según el estado_contexto');
      
      // PASO 3: Iniciar sesión con ElevenLabs pasando el firstMessage dinámico
      // El mensaje_inicial se pasa como variable dinámica para que el agente lo use
      final connected = await _elevenLabs.connect(customData: customData);
      
      if (!connected) {
        _setState(CreaState.error);
        return false;
      }
      
      // Suscribirse a eventos de ElevenLabs
      _setupListeners();
      
      // Iniciar escucha
      await _elevenLabs.startListening();
      
      _setState(CreaState.listening);
      
      // PASO 4: Después de iniciar la sesión, actualizar estado a "en_progreso" si era "nueva"
      // Esto actualiza el ultimoContacto con DateTime.now()
      if (estadoContexto == EstadoContextoAlerta.nueva) {
        await _contextoService.marcarComoEnProgreso(alerta);
        print('📝 Alerta ${alerta.numeroOt} actualizada a EN_PROGRESO después de iniciar sesión');
      } else if (estadoContexto == EstadoContextoAlerta.enProgreso) {
        // Si ya estaba en progreso, actualizar solo el ultimoContacto
        await _contextoService.actualizarContexto(alerta, nuevoEstado: EstadoContextoAlerta.enProgreso);
        print('📝 Último contacto actualizado para ${alerta.numeroOt}');
      }
      
      // SIEMPRE iniciar timer de 3 minutos en cada interacción (primera llamada o reconexión)
      // Esto permite que el agente vuelva a contactar cada 3 minutos
      _iniciarTimer3Minutos();
      
      print('✅ Sesión CREA iniciada para CTO ${alerta.nombreCto}');
      return true;
      
    } catch (e) {
      print('❌ Error iniciando sesión CREA: $e');
      _setState(CreaState.error);
      return false;
    }
  }

  /// Configura los listeners de ElevenLabs
  void _setupListeners() {
    // Limpiar listeners anteriores
    _transcriptSub?.cancel();
    _responseSub?.cancel();
    _eventSub?.cancel();
    // NO limpiar _lastTranscriptAdded para evitar duplicados en reconexión
    
    // Escuchar transcripciones del usuario
    _transcriptSub = _elevenLabs.transcriptStream.listen((text) {
      // Evitar duplicados
      if (text.isNotEmpty && text != _lastTranscriptAdded) {
        _lastTranscript = text;
        _lastTranscriptAdded = text;
        _transcriptController.add(text);
        notifyListeners();
        
        // Analizar si el técnico reporta algo especial
        _analizarIntencion(text);
      }
    });
    
    // Escuchar respuestas del agente
    _responseSub = _elevenLabs.responseStream.listen((text) {
      if (text.isEmpty || text == _lastResponseAdded) return;
      _lastResponseAdded = text;
      _agentResponse = text;
      _responseController.add(text);
      notifyListeners();

      // Detectar si el agente menciona CHURN o cambio de compañía
      _detectarChurnEnRespuestaAgente(text);
    });
    
    // Escuchar cambios de estado
    _elevenLabs.addListener(_onElevenLabsStateChange);
  }

  /// Maneja cambios de estado de ElevenLabs
  void _onElevenLabsStateChange() {
    switch (_elevenLabs.state) {
      case ElevenLabsState.listening:
        _setState(CreaState.listening);
        break;
      case ElevenLabsState.speaking:
        _setState(CreaState.speaking);
        break;
      case ElevenLabsState.processing:
        _setState(CreaState.processing);
        break;
      case ElevenLabsState.disconnected:
        _setState(CreaState.disconnected);
        break;
      case ElevenLabsState.error:
        _setState(CreaState.error);
        break;
      default:
        break;
    }
  }

  /// Analiza la intención del técnico
  void _analizarIntencion(String texto) {
    final textoLower = texto.toLowerCase();
    
    // Detectar si el técnico reporta churn
    if (textoLower.contains('churn') || 
        textoLower.contains('baja') || 
        textoLower.contains('cancelación')) {
      _manejarChurn();
      return;
    }
    
    // Detectar CTO dañada
    if (textoLower.contains('dañad') || 
        textoLower.contains('rota') || 
        textoLower.contains('vandalismo')) {
      _manejarCtoDanada();
      return;
    }
    
    // Detectar otra compañía (cliente tenía otra empresa)
    if (textoLower.contains('otra compañía') || 
        textoLower.contains('otra compania') ||
        textoLower.contains('otra empresa') ||
        textoLower.contains('cliente tenía') ||
        textoLower.contains('cliente tenia') ||
        textoLower.contains('competencia') ||
        textoLower.contains('otro proveedor')) {
      _manejarOtraCompania();
      return;
    }
    
    // Detectar terceros trabajando
    if (textoLower.contains('tercero') || 
        textoLower.contains('competencia trabajando')) {
      _manejarTerceros();
      return;
    }
    
    // Detectar cuando técnico acepta volver a contactar cuando esté OK
    if (textoLower.contains('cuando esté ok') || 
        textoLower.contains('cuando este ok') ||
        textoLower.contains('cuando esté listo') ||
        textoLower.contains('cuando este listo') ||
        textoLower.contains('te aviso cuando') ||
        textoLower.contains('te llamo cuando') ||
        textoLower.contains('te contacto cuando')) {
      _manejarAceptaVolverAContactar();
      return;
    }
    
    // Detectar trabajo completado
    if (textoLower.contains('listo') || 
        textoLower.contains('terminé') || 
        textoLower.contains('regularizado') ||
        textoLower.contains('conectado')) {
      _verificarRegularizacion();
      return;
    }
  }

  void _manejarChurn() {
    if (_alertaActual != null) {
      _alertaActual = _alertaActual!.copyWith(
        tipoAlerta: TipoAlerta.churn,
      );
      notifyListeners();
    }
  }

  void _manejarCtoDanada() {
    _escalarASupervisor('CTO reportada como dañada');
  }

  void _manejarTerceros() {
    _escalarASupervisor('Terceros trabajando en la CTO');
  }

  void _manejarOtraCompania() {
    // Cuando el técnico menciona que el cliente tenía otra compañía
    _requiereFotoOtraCompania = true;
    _churnService.detectarChurn();
    notifyListeners();
    print('📷 Se requiere fotografía por otra compañía - CHURN detectado');
  }

  /// Detecta si el agente menciona CHURN en su respuesta
  void _detectarChurnEnRespuestaAgente(String respuesta) {
    final respuestaLower = respuesta.toLowerCase();
    
    // Detectar frases clave que indican que el agente está pidiendo fotos de CHURN
    if (respuestaLower.contains('toma fotos') ||
        respuestaLower.contains('tomar fotos') ||
        respuestaLower.contains('fotos de los equipos') ||
        respuestaLower.contains('fotos de evidencia') ||
        respuestaLower.contains('cambio de compañía') ||
        respuestaLower.contains('otra compañía') ||
        respuestaLower.contains('otra empresa') ||
        respuestaLower.contains('equipos de la otra') ||
        (respuestaLower.contains('churn') && respuestaLower.contains('foto'))) {
      
      _churnService.detectarChurn();
      _requiereFotoOtraCompania = true;
      notifyListeners();
      print('📷 CHURN detectado en respuesta del agente - Iniciando flujo de fotos');
    }
  }

  void _manejarAceptaVolverAContactar() {
    // Cuando el técnico acepta volver a contactar cuando esté OK
    _tecnicoAceptoVolverAContactar = true;
    notifyListeners();
    print('✅ Técnico aceptó volver a contactar cuando esté OK');
    
    // Cortar la llamada automáticamente después de un momento
    Future.delayed(const Duration(seconds: 3), () {
      finalizarSesion();
    });
  }

  Future<void> _verificarRegularizacion() async {
    if (_alertaActual == null) return;
    
    _setState(CreaState.processing);
    
    try {
      // Consultar API de Kepler para verificar estado
      final regularizado = await _keplerApi.verificarEstadoCto(
        _alertaActual!.accessId,
      );
      
      if (regularizado) {
        _alertaActual = _alertaActual!.copyWith(
          estado: EstadoAlerta.regularizada,
        );
        
        // El agente de ElevenLabs manejará la respuesta de confirmación
        
        // Cerrar sesión después de un momento
        Future.delayed(const Duration(seconds: 10), () {
          finalizarSesion();
        });
      }
      
      _setState(CreaState.listening);
    } catch (e) {
      print('Error verificando regularización: $e');
      _setState(CreaState.listening);
    }
  }

  void _escalarASupervisor(String motivo) async {
    if (_alertaActual == null) return;
    
    try {
      await _keplerApi.escalarAlerta(
        _alertaActual!.id,
        motivo,
      );
      
      _alertaActual = _alertaActual!.copyWith(
        estado: EstadoAlerta.escalada,
        motivoEscalamiento: motivo,
        fechaEscalada: DateTime.now(),
      );
      
      notifyListeners();
    } catch (e) {
      print('Error escalando alerta: $e');
    }
  }

  void _iniciarTimerProgreso() {
    _progresoTimer?.cancel();
    _progresoTimer = Timer(
      const Duration(minutes: 20),
      () {
        // El agente de ElevenLabs debería preguntar automáticamente
        // basándose en sus instrucciones
        print('⏰ 20 minutos transcurridos - el agente debería preguntar progreso');
      },
    );
  }

  /// Inicia timer de 3 minutos para volver a contactar al técnico
  void _iniciarTimer3Minutos() {
    _progresoTimer?.cancel();
    print('⏰ Iniciando timer de 3 minutos - volverá a contactar al técnico');
    
    _progresoTimer = Timer(
      const Duration(minutes: 3),
      () async {
        print('⏰ 3 minutos transcurridos - volviendo a contactar al técnico');
        
        // Cerrar sesión actual
        await finalizarSesion();
        
        // Esperar un momento y volver a iniciar sesión
        await Future.delayed(const Duration(seconds: 2));
        
        if (_alertaActual != null) {
          // Volver a iniciar sesión (esperar 3 minutos nuevamente, marcando como reconexión)
          await iniciarSesion(_alertaActual!, esperar3Minutos: true, esReconexion: true);
        }
      },
    );
  }

  /// Registra fotos georeferenciadas para la alerta actual
  Future<void> registrarFotos(List<String> fotoPaths) async {
    if (_alertaActual == null) return;
    
    _alertaActual = _alertaActual!.copyWith(
      fotosGeoreferenciadas: fotoPaths,
    );
    
    // Si era por otra compañía, marcar como completado
    if (_requiereFotoOtraCompania) {
      _requiereFotoOtraCompania = false;
    }
    
    notifyListeners();
  }

  /// Activa/desactiva el micrófono
  void toggleMute() {
    _elevenLabs.toggleMute();
    notifyListeners();
  }

  /// Pausa la escucha: silencia el micrófono sin detener el stream.
  /// Mantiene la sesión ElevenLabs activa para que procese mensajes de texto.
  Future<void> pausarEscucha() async {
    if (!_elevenLabs.isMuted) _elevenLabs.toggleMute();
    _setState(CreaState.idle);
  }

  /// Reanuda la escucha: quita el silencio del micrófono.
  Future<void> reanudarEscucha() async {
    if (_elevenLabs.isMuted) _elevenLabs.toggleMute();
    _setState(CreaState.listening);
  }

  /// Finaliza la sesión con el agente
  Future<void> finalizarSesion() async {
    print('👋 Finalizando sesión CREA...');
    
    _progresoTimer?.cancel();
    _progresoTimer = null;
    
    // Si la alerta no está regularizada, mantener como en progreso
    if (_alertaActual != null) {
      final estadoContexto = _contextoService.obtenerEstado(_alertaActual!.numeroOt);
      if (estadoContexto != EstadoContextoAlerta.regularizada) {
        await _contextoService.marcarComoEnProgreso(_alertaActual!);
        print('📝 Alerta marcada como en_progreso (no regularizada)');
      }
    }
    
    // Desconectar de ElevenLabs
    await _elevenLabs.disconnect();
    
    // Limpiar listeners
    _transcriptSub?.cancel();
    _responseSub?.cancel();
    _eventSub?.cancel();
    _elevenLabs.removeListener(_onElevenLabsStateChange);
    
    _setState(CreaState.disconnected);
    _lastTranscript = '';
    _agentResponse = '';
    // NO limpiar _alertaActual ni _tecnicoAceptoVolverAContactar aquí
    // Se limpiarán cuando se marque como solucionada
    
    notifyListeners();
  }
  
  /// Verifica el estado de la alerta y marca como solucionada si está OK
  /// Retorna true si está OK y se marcó como solucionada, false si no está OK
  Future<bool> verificarYMarcarSolucionada() async {
    if (_alertaActual == null) return false;
    
    _setState(CreaState.processing);
    
    try {
      print('🔍 Verificando estado de la alerta ${_alertaActual!.numeroOt}...');
      
      // Si es una alerta CTO, usar el método específico de verificación
      if (_alertaActual!.tipoAlerta == TipoAlerta.desconexion || 
          _alertaActual!.tipoAlerta == TipoAlerta.ctoDanada) {
        final resultado = await _alertasCTOService.verificarYActualizarAlerta(
          _alertaActual!.numeroOt,
        );
        
        if (resultado['solucionado'] == true) {
          print('✅ Alerta CTO solucionada - ${resultado['mensaje']}');
          // Marcar como regularizada en el contexto
          if (_alertaActual != null) {
            await _contextoService.marcarComoRegularizada(_alertaActual!);
          }
          _tecnicoAceptoVolverAContactar = false;
          _requiereFotoOtraCompania = false;
          _setState(CreaState.disconnected);
          return true;
        } else {
          print('⚠️ Alerta CTO aún pendiente - ${resultado['mensaje']}');
          // Mantener como en progreso si no está solucionada
          if (_alertaActual != null) {
            await _contextoService.marcarComoEnProgreso(_alertaActual!);
          }
          _tecnicoAceptoVolverAContactar = false;
          _setState(CreaState.idle);
          // Reiniciar la conversación
          await iniciarSesion(_alertaActual!);
          return false;
        }
      }
      
      // Para otros tipos de alertas, usar el método original
      final regularizado = await _keplerApi.verificarEstadoCto(
        _alertaActual!.accessId,
      );
      
      if (regularizado) {
        print('✅ Alerta está regularizada - marcando como solucionada');
        // Marcar como regularizada en el contexto
        if (_alertaActual != null) {
          await _contextoService.marcarComoRegularizada(_alertaActual!);
        }
        _tecnicoAceptoVolverAContactar = false;
        _requiereFotoOtraCompania = false;
        _setState(CreaState.disconnected);
        return true;
      } else {
        print('⚠️ Alerta NO está regularizada - reiniciando conversación');
        // Mantener como en progreso si no está regularizada
        if (_alertaActual != null) {
          await _contextoService.marcarComoEnProgreso(_alertaActual!);
        }
        _tecnicoAceptoVolverAContactar = false;
        _setState(CreaState.idle);
        // Reiniciar la conversación
        await iniciarSesion(_alertaActual!);
        return false;
      }
    } catch (e) {
      print('❌ Error verificando estado: $e');
      _setState(CreaState.error);
      return false;
    }
  }
  
  /// Marca la alerta como solucionada (llamado desde la UI después de verificación)
  void marcarAlertaSolucionada() {
    _tecnicoAceptoVolverAContactar = false;
    _requiereFotoOtraCompania = false;
    _alertaActual = null;
    notifyListeners();
  }

  void _setState(CreaState newState) {
    _state = newState;
    notifyListeners();
  }

  @override
  void dispose() {
    finalizarSesion();
    _transcriptController.close();
    _responseController.close();
    super.dispose();
  }
}

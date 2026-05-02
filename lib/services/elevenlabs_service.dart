import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';

/// Configuración del agente CREA en ElevenLabs
class ElevenLabsConfig {
  // Agent ID para alertas de desconexión
  static const String agentIdAlertas = 'agent_9501kbtjcvw3fgr9p0kpbgdzvg90';
  // Agent ID para asistente de terreno
  static const String agentIdTerreno = 'agent_3301k492mf80esga21httqh7z4sh';
  
  static const String apiKey = 'sk_4c1cdfad7a436c963223ffcde72387839b6d38f687026731';
  static const String wsBaseUrl = 'wss://api.elevenlabs.io/v1/convai/conversation';
  
  static String get wsUrl => '$wsBaseUrl?agent_id=$agentIdAlertas';
  
  static String wsUrlForAgent(String agentId) => '$wsBaseUrl?agent_id=$agentId';
}

/// Estados de la conversación con ElevenLabs
enum ElevenLabsState {
  disconnected,
  connecting,
  connected,
  listening,
  processing,
  speaking,
  error,
}

/// Evento de conversación
class ConversationEvent {
  final String type;
  final String? text;
  final Uint8List? audio;
  final Map<String, dynamic>? metadata;

  ConversationEvent({
    required this.type,
    this.text,
    this.audio,
    this.metadata,
  });
}

/// Servicio para comunicación con ElevenLabs Conversational AI
class ElevenLabsService extends ChangeNotifier {
  WebSocketChannel? _channel;
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  
  ElevenLabsState _state = ElevenLabsState.disconnected;
  ElevenLabsState get state => _state;
  
  String _conversationId = '';
  String get conversationId => _conversationId;
  
  bool _isMuted = false;
  bool get isMuted => _isMuted;
  
  String? _lastError;
  String? get lastError => _lastError;
  
  String _lastUserTranscript = ''; // Para evitar duplicados de user_transcript
  
  // Streams para eventos
  final StreamController<ConversationEvent> _eventController = 
      StreamController<ConversationEvent>.broadcast();
  Stream<ConversationEvent> get eventStream => _eventController.stream;
  
  final StreamController<String> _transcriptController = 
      StreamController<String>.broadcast();
  Stream<String> get transcriptStream => _transcriptController.stream;
  
  final StreamController<String> _responseController = 
      StreamController<String>.broadcast();
  Stream<String> get responseStream => _responseController.stream;
  
  StreamSubscription? _recordingSubscription;
  
  // Buffer para audio de respuesta
  final List<Uint8List> _audioBuffer = [];
  bool _isPlayingResponse = false;
  bool _isBuffering = false;
  Timer? _bufferTimer;
  static const int _minBufferSize = 3; // Mínimo de chunks antes de reproducir

  /// Inicia la conexión con el agente
  /// [agentId] - ID del agente a usar. Si es null, usa el agente por defecto (alertas)
  Future<bool> connect({Map<String, dynamic>? customData, String? agentId}) async {
    if (_state == ElevenLabsState.connected || 
        _state == ElevenLabsState.connecting) {
      return true;
    }
    
    _setState(ElevenLabsState.connecting);
    _lastError = null;
    
    try {
      // Verificar permisos de micrófono
      final micPermission = await Permission.microphone.request();
      if (!micPermission.isGranted) {
        _setError('Permiso de micrófono denegado');
        return false;
      }
      
      // Usar agentId proporcionado o el por defecto
      final targetAgentId = agentId ?? ElevenLabsConfig.agentIdAlertas;
      final wsUrl = ElevenLabsConfig.wsUrlForAgent(targetAgentId);
      
      print('🔌 Conectando a ElevenLabs...');
      print('📍 URL: $wsUrl');
      print('🤖 Agent ID: $targetAgentId');
      
      // Conectar WebSocket con headers de autenticación
      final uri = Uri.parse(wsUrl);
      
      _channel = IOWebSocketChannel.connect(
        uri,
        headers: {
          'xi-api-key': ElevenLabsConfig.apiKey,
        },
      );
      
      // Esperar la conexión
      await _channel!.ready;
      
      print('✅ WebSocket conectado');
      
      // Escuchar mensajes del WebSocket
      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
      );
      
      // Enviar mensaje de inicialización con contexto
      // Extraer mensaje_inicial si existe para enviarlo como firstMessage
      final dynamicVars = Map<String, dynamic>.from(customData ?? {});
      final mensajeInicial = dynamicVars.remove('mensaje_inicial') as String?;
      
      final initMessage = <String, dynamic>{
        'type': 'conversation_initiation_client_data',
        'dynamic_variables': dynamicVars,
      };
      
      // Si hay mensaje_inicial, enviarlo como first_message en conversation_config_override
      // Formato correcto según API de ElevenLabs:
      // conversation_config_override.agent.first_message (snake_case)
      if (mensajeInicial != null && mensajeInicial.isNotEmpty) {
        initMessage['conversation_config_override'] = {
          'agent': {
            'first_message': mensajeInicial,  // snake_case (formato correcto de ElevenLabs)
          },
        };
        print('📤 ✅ Enviando first_message en conversation_config_override.agent.first_message');
        print('📤 Mensaje: $mensajeInicial');
        print('📤 Longitud: ${mensajeInicial.length} caracteres');
      } else {
        print('⚠️ No hay mensaje_inicial para enviar como first_message');
      }
      
      print('📤 Enviando init completo: ${jsonEncode(initMessage).substring(0, jsonEncode(initMessage).length > 500 ? 500 : jsonEncode(initMessage).length)}...');
      _sendMessage(initMessage);
      
      _setState(ElevenLabsState.connected);
      return true;
      
    } catch (e) {
      print('❌ Error conectando a ElevenLabs: $e');
      _setError('Error de conexión: $e');
      return false;
    }
  }

  /// Maneja mensajes entrantes del WebSocket
  void _handleMessage(dynamic message) {
    try {
      print('📥 Mensaje recibido: ${message.runtimeType}');
      
      if (message is String) {
        print('📥 JSON: $message');
        final data = jsonDecode(message) as Map<String, dynamic>;
        _processJsonMessage(data);
      } else if (message is List<int>) {
        // Audio binario recibido
        print('🔊 Audio chunk recibido: ${message.length} bytes');
        _handleAudioChunk(Uint8List.fromList(message));
      }
    } catch (e) {
      print('❌ Error procesando mensaje: $e');
    }
  }

  /// Procesa mensajes JSON del agente
  void _processJsonMessage(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    print('📨 Tipo de mensaje: $type');
    
    switch (type) {
      case 'conversation_initiation_metadata':
        // El conversation_id está dentro de conversation_initiation_metadata_event
        final metadata = data['conversation_initiation_metadata_event'] as Map<String, dynamic>?;
        _conversationId = metadata?['conversation_id'] ?? data['conversation_id'] ?? '';
        print('✅ Conversación iniciada: $_conversationId');
        _eventController.add(ConversationEvent(
          type: 'connected',
          metadata: data,
        ));
        // NO iniciar escucha aquí, ya se inicia en connect()
        break;
        
      case 'user_transcript':
        final transcript = data['user_transcript'] as String?;
        if (transcript != null && transcript.isNotEmpty) {
          print('🎤 Usuario: $transcript');
          // Verificar si ya se agregó este transcript para evitar duplicados
          if (_lastUserTranscript != transcript) {
            _lastUserTranscript = transcript;
            _transcriptController.add(transcript);
            _eventController.add(ConversationEvent(
              type: 'user_transcript',
              text: transcript,
            ));
          } else {
            print('⚠️ Transcript duplicado ignorado: $transcript');
          }
        }
        break;
        
      case 'agent_response':
        // La respuesta viene en agent_response_event.agent_response
        final responseEvent = data['agent_response_event'] as Map<String, dynamic>?;
        final response = responseEvent?['agent_response'] as String? ?? data['agent_response'] as String?;
        if (response != null && response.isNotEmpty) {
          print('🤖 Agente: $response');
          _responseController.add(response);
          _setState(ElevenLabsState.speaking);
          _eventController.add(ConversationEvent(
            type: 'agent_response',
            text: response,
          ));
        }
        break;
        
      case 'audio':
        // El audio viene en audio_event.audio_base_64
        final audioEvent = data['audio_event'] as Map<String, dynamic>?;
        final audioBase64 = audioEvent?['audio_base_64'] as String?;
        if (audioBase64 != null && audioBase64.isNotEmpty) {
          print('🔊 Audio recibido: ${audioBase64.length} chars');
          try {
            final audioBytes = base64Decode(audioBase64);
            _handleAudioChunk(audioBytes);
          } catch (e) {
            print('❌ Error decodificando audio: $e');
          }
        }
        break;
        
      case 'interruption':
        print('⚡ Interrupción detectada');
        _stopPlayback();
        _setState(ElevenLabsState.listening);
        break;
        
      case 'ping':
        // Responder al ping con el formato correcto
        final pingEvent = data['ping_event'] as Map<String, dynamic>?;
        final eventId = pingEvent?['event_id'] ?? data['event_id'];
        print('🏓 Ping recibido, respondiendo pong...');
        _sendMessage({
          'type': 'pong',
          'event_id': eventId,
        });
        break;
        
      case 'error':
        final errorMsg = data['message'] ?? data['error'] ?? 'Error desconocido';
        print('❌ Error del agente: $errorMsg');
        _setError(errorMsg.toString());
        break;
        
      default:
        print('📨 Mensaje no manejado: $type - $data');
    }
  }

  /// Maneja chunks de audio recibidos
  void _handleAudioChunk(Uint8List audioData) {
    print('🎵 Agregando audio al buffer: ${audioData.length} bytes (Total: ${_audioBuffer.length + 1} chunks)');
    _audioBuffer.add(audioData);
    
    // Si no estamos reproduciendo, iniciar buffer timer o reproducir si hay suficiente
    if (!_isPlayingResponse && !_isBuffering) {
      // Si tenemos suficiente buffer, reproducir inmediatamente
      if (_audioBuffer.length >= _minBufferSize) {
        _playBufferedAudio();
      } else {
        // Esperar un poco más para acumular más chunks
        _bufferTimer?.cancel();
        _bufferTimer = Timer(const Duration(milliseconds: 100), () {
          if (_audioBuffer.isNotEmpty && !_isPlayingResponse) {
            _playBufferedAudio();
          }
        });
      }
    }
  }

  /// Reproduce el audio del buffer
  Future<void> _playBufferedAudio() async {
    if (_audioBuffer.isEmpty || _isPlayingResponse) return;
    
    _bufferTimer?.cancel();
    _isBuffering = true;
    _isPlayingResponse = true;
    _setState(ElevenLabsState.speaking);
    
    // Pausar la grabación mientras reproducimos (evita conflictos de audio en Android)
    await _pauseRecording();
    
    try {
      // Acumular todos los chunks disponibles en un solo buffer
      // Esto evita cortes entre chunks
      final List<Uint8List> chunksToPlay = [];
      
      // Tomar todos los chunks disponibles del buffer
      while (_audioBuffer.isNotEmpty) {
        chunksToPlay.add(_audioBuffer.removeAt(0));
      }
      
      if (chunksToPlay.isEmpty) return;
      
      print('▶️ Reproduciendo ${chunksToPlay.length} chunks concatenados');
      
      // Concatenar todos los chunks PCM en uno solo
      int totalLength = 0;
      for (final chunk in chunksToPlay) {
        totalLength += chunk.length;
      }
      
      final concatenatedPcm = Uint8List(totalLength);
      int offset = 0;
      for (final chunk in chunksToPlay) {
        concatenatedPcm.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }
      
      print('▶️ Audio concatenado: ${concatenatedPcm.length} bytes PCM');
      
      // Convertir PCM concatenado a WAV
      final wavData = _pcmToWav(concatenatedPcm, sampleRate: 16000, channels: 1, bitsPerSample: 16);
      print('▶️ Convertido a WAV: ${wavData.length} bytes');
      
      // Crear source desde bytes WAV y reproducir
      final audioSource = _AudioBytesSource(wavData);
      await _player.setAudioSource(audioSource);
      
      // Pre-buffer antes de reproducir para evitar cortes iniciales
      await _player.load();
      await Future.delayed(const Duration(milliseconds: 50)); // Pequeño delay para pre-buffer
      
      await _player.play();
      
      // Esperar a que termine la reproducción
      await _player.playerStateStream
          .timeout(const Duration(seconds: 30))
          .firstWhere(
            (state) => state.processingState == ProcessingState.completed,
          );
      
      print('✅ Audio reproducido completamente');
      
      // Si hay más chunks en el buffer, reproducirlos inmediatamente
      if (_audioBuffer.isNotEmpty) {
        print('🔄 Hay más audio en buffer, reproduciendo...');
        _isPlayingResponse = false; // Permitir siguiente reproducción
        _playBufferedAudio();
        return;
      }
      
    } catch (e) {
      print('❌ Error reproduciendo audio: $e');
    } finally {
      _isPlayingResponse = false;
      _isBuffering = false;
      _setState(ElevenLabsState.listening);
      
      // Reiniciar la grabación después de reproducir
      await _resumeRecording();
    }
  }
  
  /// Pausa la grabación temporalmente
  Future<void> _pauseRecording() async {
    print('⏸️ Pausando grabación...');
    await _recordingSubscription?.cancel();
    _recordingSubscription = null;
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
  }
  
  /// Reanuda la grabación
  Future<void> _resumeRecording() async {
    print('▶️ Intentando reanudar grabación...');
    print('▶️ Estado actual: $_state, channel: ${_channel != null}, isPlaying: $_isPlayingResponse');
    
    if (_state == ElevenLabsState.disconnected || 
        _state == ElevenLabsState.error ||
        _channel == null) {
      print('⚠️ No se puede reanudar - estado inválido');
      return;
    }
    
    try {
      // Verificar permisos
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        print('❌ Sin permiso de micrófono para reanudar');
        return;
      }
      
      // Detener si ya está grabando
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
      
      final config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      );
      
      final stream = await _recorder.startStream(config);
      print('✅ Stream de grabación creado');
      
      int chunkCount = 0;
      int sentCount = 0;
      _recordingSubscription = stream.listen((chunk) {
        chunkCount++;
        
        // Log inicial para confirmar que llegan datos
        if (chunkCount <= 5) {
          print('🎙️ [Resume] Chunk #$chunkCount: ${chunk.length} bytes');
        }
        
        if (_channel != null && 
            !_isMuted && 
            chunk.isNotEmpty &&
            _state != ElevenLabsState.error &&
            _state != ElevenLabsState.disconnected &&
            !_isPlayingResponse) {
          sentCount++;
          
          if (sentCount <= 5 || sentCount % 30 == 0) {
            print('📤 [Resume] Enviando chunk #$sentCount (${chunk.length} bytes)');
          }
          
          try {
            final base64Audio = base64Encode(chunk);
            _channel!.sink.add(jsonEncode({
              'user_audio_chunk': base64Audio,
            }));
          } catch (e) {
            print('❌ Error enviando audio: $e');
          }
        }
      }, onError: (e) {
        print('❌ Error en stream de audio: $e');
      }, onDone: () {
        print('🔇 [Resume] Stream terminado');
      });
      
      print('✅ Grabación reanudada exitosamente');
    } catch (e) {
      print('❌ Error reanudando grabación: $e');
    }
  }

  /// Inicia la grabación de audio
  Future<void> startListening() async {
    if (_state == ElevenLabsState.disconnected || 
        _state == ElevenLabsState.error) {
      print('⚠️ No se puede iniciar escucha en estado: $_state');
      return;
    }
    
    try {
      print('🎤 Iniciando grabación...');
      
      // Verificar permisos
      final hasPermission = await _recorder.hasPermission();
      print('🎤 Permiso de micrófono: $hasPermission');
      
      if (!hasPermission) {
        print('❌ No hay permiso de micrófono');
        _setError('No hay permiso de micrófono');
        return;
      }
      
      // Detener si ya está grabando
      if (await _recorder.isRecording()) {
        print('⚠️ Ya estaba grabando, deteniendo...');
        await _recorder.stop();
      }
      
      // Configurar grabación - PCM 16-bit, 16kHz, mono
      final config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      );
      
      // Iniciar stream de grabación
      final stream = await _recorder.startStream(config);
      
      _setState(ElevenLabsState.listening);
      print('✅ Grabación iniciada - Stream configurado');
      
      // Enviar audio en chunks al WebSocket
      int chunkCount = 0;
      int sentCount = 0;
      _recordingSubscription = stream.listen((chunk) {
        chunkCount++;
        
        // Log inicial para confirmar que llegan datos del micrófono
        if (chunkCount <= 5) {
          print('🎙️ Chunk #$chunkCount del micrófono: ${chunk.length} bytes');
        }
        
        // Solo enviar audio si estamos conectados, no reproduciendo, y no en estado de error
        if (_channel != null && 
            !_isMuted && 
            chunk.isNotEmpty &&
            !_isPlayingResponse &&
            _state != ElevenLabsState.error &&
            _state != ElevenLabsState.disconnected) {
          sentCount++;
          
          // Log cada 30 chunks enviados
          if (sentCount <= 5 || sentCount % 30 == 0) {
            print('📤 Enviando chunk #$sentCount (${chunk.length} bytes) - Playing: $_isPlayingResponse');
          }
          
          try {
            // Enviar audio como base64
            final base64Audio = base64Encode(chunk);
            _channel!.sink.add(jsonEncode({
              'user_audio_chunk': base64Audio,
            }));
          } catch (e) {
            print('❌ Error enviando audio: $e');
          }
        } else if (chunkCount <= 10) {
          // Log para debugging inicial
          print('⏸️ Chunk #$chunkCount NO enviado - isPlaying: $_isPlayingResponse, state: $_state');
        }
      }, onError: (e) {
        print('❌ Error en stream de audio: $e');
      }, onDone: () {
        print('🔇 Stream de audio terminado');
      });
      
    } catch (e) {
      print('❌ Error iniciando grabación: $e');
      _setError('Error de micrófono: $e');
    }
  }

  /// Detiene la grabación de audio
  Future<void> stopListening() async {
    print('🔇 Deteniendo grabación...');
    
    await _recordingSubscription?.cancel();
    _recordingSubscription = null;
    
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
    
    if (_state == ElevenLabsState.listening) {
      _setState(ElevenLabsState.connected);
    }
  }

  /// Activa/desactiva el micrófono
  void toggleMute() {
    _isMuted = !_isMuted;
    notifyListeners();
    print(_isMuted ? '🔇 Micrófono silenciado' : '🎤 Micrófono activado');
  }

  /// Detiene la reproducción de audio
  void _stopPlayback() {
    _player.stop();
    _audioBuffer.clear();
    _isPlayingResponse = false;
  }

  /// Envía un mensaje de texto al agente
  void sendTextMessage(String text) {
    print('📤 Enviando texto: $text');
    _sendMessage({
      'type': 'user_message',
      'user_message': text,
    });
    // NO agregar manualmente al transcriptController aquí
    // El servidor confirmará el mensaje a través del stream 'user_transcript'
    // y se agregará automáticamente en el handler de eventos
  }

  /// Envía mensaje al WebSocket
  void _sendMessage(Map<String, dynamic> message) {
    if (_channel != null) {
      final jsonMsg = jsonEncode(message);
      _channel!.sink.add(jsonMsg);
    }
  }

  /// Desconecta del agente
  Future<void> disconnect() async {
    print('👋 Desconectando de ElevenLabs...');
    
    await stopListening();
    _stopPlayback();
    
    await _channel?.sink.close();
    _channel = null;
    
    _conversationId = '';
    _lastUserTranscript = ''; // Limpiar último transcript
    _setState(ElevenLabsState.disconnected);
  }

  void _handleError(dynamic error) {
    print('❌ Error WebSocket: $error');
    _setError('Error de conexión: $error');
  }

  void _handleDone() {
    print('🔌 WebSocket cerrado inesperadamente');
    print('🔌 Estado anterior: $_state');
    print('🔌 Conversation ID: $_conversationId');
    
    // Intentar obtener el código de cierre si está disponible
    if (_channel != null) {
      print('🔌 Close code: ${_channel!.closeCode}');
      print('🔌 Close reason: ${_channel!.closeReason}');
    }
    
    if (_state != ElevenLabsState.disconnected) {
      _setError('Conexión cerrada inesperadamente');
    }
  }

  void _setState(ElevenLabsState newState) {
    print('📊 Estado: $_state -> $newState');
    _state = newState;
    notifyListeners();
  }

  void _setError(String message) {
    _lastError = message;
    _state = ElevenLabsState.error;
    _eventController.add(ConversationEvent(
      type: 'error',
      text: message,
    ));
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    _recorder.dispose();
    _player.dispose();
    _eventController.close();
    _transcriptController.close();
    _responseController.close();
    super.dispose();
  }
}

/// Convierte PCM raw a WAV agregando el header
Uint8List _pcmToWav(Uint8List pcmData, {int sampleRate = 16000, int channels = 1, int bitsPerSample = 16}) {
  final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  final blockAlign = channels * bitsPerSample ~/ 8;
  final dataSize = pcmData.length;
  final fileSize = 36 + dataSize;
  
  final header = ByteData(44);
  
  // RIFF header
  header.setUint8(0, 0x52); // R
  header.setUint8(1, 0x49); // I
  header.setUint8(2, 0x46); // F
  header.setUint8(3, 0x46); // F
  header.setUint32(4, fileSize, Endian.little);
  header.setUint8(8, 0x57);  // W
  header.setUint8(9, 0x41);  // A
  header.setUint8(10, 0x56); // V
  header.setUint8(11, 0x45); // E
  
  // fmt chunk
  header.setUint8(12, 0x66); // f
  header.setUint8(13, 0x6D); // m
  header.setUint8(14, 0x74); // t
  header.setUint8(15, 0x20); // (space)
  header.setUint32(16, 16, Endian.little); // Chunk size
  header.setUint16(20, 1, Endian.little);  // Audio format (PCM)
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, byteRate, Endian.little);
  header.setUint16(32, blockAlign, Endian.little);
  header.setUint16(34, bitsPerSample, Endian.little);
  
  // data chunk
  header.setUint8(36, 0x64); // d
  header.setUint8(37, 0x61); // a
  header.setUint8(38, 0x74); // t
  header.setUint8(39, 0x61); // a
  header.setUint32(40, dataSize, Endian.little);
  
  // Combinar header + data
  final wav = Uint8List(44 + dataSize);
  wav.setRange(0, 44, header.buffer.asUint8List());
  wav.setRange(44, 44 + dataSize, pcmData);
  
  return wav;
}

/// Source de audio desde bytes para just_audio
class _AudioBytesSource extends StreamAudioSource {
  final Uint8List _bytes;

  _AudioBytesSource(this._bytes);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _bytes.length;
    
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_bytes.sublist(start, end)),
      contentType: 'audio/wav',
    );
  }
}

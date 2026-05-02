import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:agente_desconexiones/constants/app_colors.dart';
import 'package:agente_desconexiones/services/elevenlabs_service.dart';

/// Pantalla de Asistente CREA de Terreno (conectado a ElevenLabs)
class AsistenteCreaTerrenoScreen extends StatefulWidget {
  const AsistenteCreaTerrenoScreen({super.key});

  @override
  State<AsistenteCreaTerrenoScreen> createState() => _AsistenteCreaTerrenoScreenState();
}

class _AsistenteCreaTerrenoScreenState extends State<AsistenteCreaTerrenoScreen>
    with SingleTickerProviderStateMixin {
  final ElevenLabsService _elevenLabs = ElevenLabsService();
  late AnimationController _pulseController;
  
  final List<_ConversationMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();
  StreamSubscription? _transcriptSub;
  StreamSubscription? _responseSub;
  StreamSubscription? _eventSub;
  
  bool _isConnecting = false;
  bool _isConnected = false;
  bool _modoChat = false; // false = voz, true = chat
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    // Escuchar transcripciones del técnico
    _transcriptSub = _elevenLabs.transcriptStream.listen((text) {
      if (text.isNotEmpty) {
        _addMessage(text, isUser: true);
      }
    });
    
    // Escuchar respuestas del agente
    _responseSub = _elevenLabs.responseStream.listen((text) {
      if (text.isNotEmpty) {
        _addMessage(text, isUser: false);
      }
    });
    
    // Escuchar eventos de estado
    _eventSub = _elevenLabs.eventStream.listen((event) {
      if (event.type == 'agent_response') {
        if (event.text != null && event.text!.isNotEmpty) {
          _addMessage(event.text!, isUser: false);
        }
      }
    });
    
    // Escuchar cambios de estado
    _elevenLabs.addListener(_onStateChanged);
    
    // Iniciar conversación automáticamente
    _iniciarAsistente();
  }

  void _onStateChanged() {
    setState(() {
      _isConnected = _elevenLabs.state == ElevenLabsState.connected ||
                     _elevenLabs.state == ElevenLabsState.listening ||
                     _elevenLabs.state == ElevenLabsState.speaking;
    });
  }

  Future<void> _iniciarAsistente() async {
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    try {
      // Conectar con ElevenLabs usando el agent_id del asistente de terreno
      final customData = {
        'tipo': 'asistente_terreno',
        'contexto': 'Asistencia técnica en terreno',
      };

      final connected = await _elevenLabs.connect(
        customData: customData,
        agentId: ElevenLabsConfig.agentIdTerreno,
      );
      
      if (connected) {
        await _elevenLabs.startListening();
        setState(() {
          _isConnecting = false;
          _isConnected = true;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Conectado con asistente CREA de terreno'),
              backgroundColor: AppColors.alertSuccess,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        setState(() {
          _isConnecting = false;
          _errorMessage = _elevenLabs.lastError ?? 'Error desconocido al conectar';
        });
      }
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _errorMessage = 'Error: $e';
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.alertUrgent,
          ),
        );
      }
    }
  }

  void _addMessage(String text, {required bool isUser}) {
    setState(() {
      _messages.add(_ConversationMessage(
        text: text,
        isUser: isUser,
        timestamp: DateTime.now(),
      ));
    });
    
    // Scroll al final
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _enviarMensajeTexto() {
    final texto = _textController.text.trim();
    if (texto.isEmpty) return;
    
    // Enviar mensaje de texto al agente
    // El mensaje se agregará automáticamente a través del stream transcriptStream
    _elevenLabs.sendTextMessage(texto);
    _textController.clear();
  }

  void _toggleModo() {
    setState(() {
      _modoChat = !_modoChat;
    });
    
    if (_modoChat) {
      // Cambiar a modo chat: pausar micrófono
      _elevenLabs.stopListening();
    } else {
      // Cambiar a modo voz: reanudar micrófono
      _elevenLabs.startListening();
    }
  }

  Future<void> _finalizarSesion() async {
    await _elevenLabs.disconnect();
    setState(() {
      _isConnected = false;
      _messages.clear();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scrollController.dispose();
    _textController.dispose();
    _transcriptSub?.cancel();
    _responseSub?.cancel();
    _eventSub?.cancel();
    _elevenLabs.removeListener(_onStateChanged);
    _elevenLabs.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Row(
          children: [
            Icon(Icons.mic, color: AppColors.creaVoice),
            SizedBox(width: 12),
            Text('Asistente CREA - Terreno'),
          ],
        ),
        actions: [
          if (_isConnected)
            IconButton(
              icon: const Icon(Icons.call_end, color: Colors.red),
              onPressed: _finalizarSesion,
              tooltip: 'Finalizar sesión',
            ),
        ],
      ),
      body: Column(
        children: [
          // Indicador de estado
          if (_isConnecting || _isConnected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: _isConnected 
                  ? AppColors.alertSuccess.withOpacity(0.2)
                  : AppColors.alertWarning.withOpacity(0.2),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isConnected 
                          ? AppColors.alertSuccess
                          : AppColors.alertWarning,
                    ),
                  ).animate(onPlay: (controller) => controller.repeat())
                    .scale(duration: 1000.ms, begin: const Offset(1, 1), end: const Offset(1.2, 1.2)),
                  const SizedBox(width: 12),
                  Text(
                    _isConnecting 
                        ? 'Conectando con asistente...'
                        : 'Conectado - El asistente te está escuchando',
                    style: TextStyle(
                      color: _isConnected 
                          ? AppColors.alertSuccess
                          : AppColors.alertWarning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          
          // Mensajes de conversación
          Expanded(
            child: _messages.isEmpty && !_isConnecting
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return _buildMessageBubble(_messages[index]);
                    },
                  ),
          ),
          
          // Error message
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(16),
              color: AppColors.alertUrgent.withOpacity(0.2),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: AppColors.alertUrgent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: AppColors.alertUrgent),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () {
                      setState(() {
                        _errorMessage = null;
                      });
                    },
                  ),
                ],
              ),
            ),
          
          // Mostrar indicador de carga si está conectando
          if (_isConnecting)
            Container(
              padding: const EdgeInsets.all(24),
              child: const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(
                      color: AppColors.creaVoice,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Conectando con asistente...',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          
          // Controles inferiores (solo si está conectado)
          if (_isConnected && !_isConnecting) _buildBottomControls(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              gradient: AppColors.creaGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.mic,
              size: 64,
              color: Colors.white,
            ),
          ).animate().scale(delay: 200.ms, duration: 600.ms),
          const SizedBox(height: 32),
          const Text(
            'Asistente CREA de Terreno',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 400.ms),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Asistente de voz para ayuda técnica en terreno.\nPresiona el botón para iniciar.',
              style: TextStyle(
                fontSize: 16,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ).animate().fadeIn(delay: 600.ms),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(_ConversationMessage message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: message.isUser 
            ? MainAxisAlignment.end 
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: AppColors.creaGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mic, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: message.isUser 
                    ? AppColors.creaVoice.withOpacity(0.2)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: message.isUser 
                      ? AppColors.creaVoice
                      : Colors.transparent,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.text,
                    style: TextStyle(
                      color: message.isUser 
                          ? AppColors.textPrimary
                          : AppColors.textPrimary,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(message.timestamp),
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (message.isUser) ...[
            const SizedBox(width: 12),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.creaVoice.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person, color: AppColors.creaVoice, size: 20),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    
    if (diff.inSeconds < 60) {
      return 'Ahora';
    } else if (diff.inMinutes < 60) {
      return 'Hace ${diff.inMinutes}m';
    } else {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.surfaceBorder),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Toggle modo voz/chat
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () {
                    if (_modoChat) _toggleModo();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: !_modoChat ? AppColors.creaVoice : AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.mic,
                          color: !_modoChat ? Colors.white : AppColors.textSecondary,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Voz',
                          style: TextStyle(
                            color: !_modoChat ? Colors.white : AppColors.textSecondary,
                            fontWeight: !_modoChat ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () {
                    if (!_modoChat) _toggleModo();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _modoChat ? AppColors.creaVoice : AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          color: _modoChat ? Colors.white : AppColors.textSecondary,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Chat',
                          style: TextStyle(
                            color: _modoChat ? Colors.white : AppColors.textSecondary,
                            fontWeight: _modoChat ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Controles según el modo
            if (_modoChat) ...[
              // Modo Chat: Campo de texto
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: 'Escribe tu mensaje...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: AppColors.surfaceBorder),
                        ),
                        filled: true,
                        fillColor: AppColors.background,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _enviarMensajeTexto(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _enviarMensajeTexto,
                    icon: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: AppColors.creaGradient,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.send,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _finalizarSesion,
                    icon: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.alertUrgent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.call_end,
                        color: AppColors.alertUrgent,
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              // Modo Voz: Indicador de estado
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        gradient: _elevenLabs.state == ElevenLabsState.listening
                            ? AppColors.creaGradient
                            : _elevenLabs.state == ElevenLabsState.speaking
                                ? const LinearGradient(
                                    colors: [
                                      AppColors.creaSpeaking,
                                      Color(0xFF1976D2),
                                    ],
                                  )
                                : null,
                        color: (_elevenLabs.state != ElevenLabsState.listening &&
                                _elevenLabs.state != ElevenLabsState.speaking)
                            ? AppColors.surfaceLight
                            : null,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: (_elevenLabs.state == ElevenLabsState.listening ||
                                  _elevenLabs.state == ElevenLabsState.speaking)
                              ? Colors.transparent
                              : AppColors.surfaceBorder,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _elevenLabs.state == ElevenLabsState.listening
                                ? Icons.mic
                                : _elevenLabs.state == ElevenLabsState.speaking
                                    ? Icons.volume_up
                                    : Icons.mic_none,
                            color: (_elevenLabs.state == ElevenLabsState.listening ||
                                    _elevenLabs.state == ElevenLabsState.speaking)
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _elevenLabs.state == ElevenLabsState.listening
                                ? 'ESCUCHANDO...'
                                : _elevenLabs.state == ElevenLabsState.speaking
                                    ? 'ASISTENTE ESTÁ HABLANDO...'
                                    : 'ESPERANDO...',
                            style: TextStyle(
                              color: (_elevenLabs.state == ElevenLabsState.listening ||
                                      _elevenLabs.state == ElevenLabsState.speaking)
                                  ? Colors.white
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _finalizarSesion,
                    icon: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.alertUrgent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.call_end,
                        color: AppColors.alertUrgent,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConversationMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  _ConversationMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

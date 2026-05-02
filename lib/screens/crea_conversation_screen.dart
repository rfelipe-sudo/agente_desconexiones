import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:agente_desconexiones/constants/app_colors.dart';
import 'package:agente_desconexiones/models/alerta.dart';
import 'package:agente_desconexiones/services/crea_agent_service.dart';
import 'package:agente_desconexiones/services/churn_service.dart';
import 'package:agente_desconexiones/screens/camera_screen.dart';
import 'package:agente_desconexiones/screens/churn_fotos_screen.dart';
import 'package:agente_desconexiones/providers/alertas_provider.dart';

class CreaConversationScreen extends StatefulWidget {
  final Alerta alerta;
  final bool esperar3Minutos; // Si es true, espera 3 minutos y vuelve a llamar
  final bool esReconexion; // Si es true, indica que es una segunda llamada/reconexión

  const CreaConversationScreen({
    super.key, 
    required this.alerta,
    this.esperar3Minutos = false,
    this.esReconexion = false,
  });

  @override
  State<CreaConversationScreen> createState() => _CreaConversationScreenState();
}

class _CreaConversationScreenState extends State<CreaConversationScreen>
    with SingleTickerProviderStateMixin {
  late CreaAgentService _creaService;
  late AnimationController _pulseController;
  
  final List<_ConversationMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();
  StreamSubscription? _transcriptSub;
  StreamSubscription? _responseSub;
  String _lastResponseText = ''; // Para evitar duplicados
  String _lastTranscriptText = ''; // Para evitar duplicados en mensajes de texto
  
  bool _isInitializing = true;
  String? _errorMessage;
  bool _modoChat = false; // false = voz, true = chat

  @override
  void initState() {
    super.initState();
    _creaService = CreaAgentService();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    // Iniciar sesión con CREA (las suscripciones se crearán dentro de _initializeCrea)
    _initializeCrea();
  }

  Future<void> _initializeCrea() async {
    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });
    
    // Cancelar suscripciones anteriores antes de reiniciar
    _transcriptSub?.cancel();
    _responseSub?.cancel();
    // NO limpiar _lastResponseText ni _lastTranscriptText para evitar duplicados en reconexión
    
    // Re-suscribirse a los streams
    _transcriptSub = _creaService.transcriptStream.listen((text) {
      if (text.isNotEmpty && text != _lastTranscriptText) {
        _lastTranscriptText = text;
        _addMessage(text, isUser: true);
      }
    });
    
    _responseSub = _creaService.responseStream.listen((text) {
      if (text.isNotEmpty && text != _lastResponseText) {
        _lastResponseText = text;
        _addMessage(text, isUser: false);
        // Detectar si el agente solicita fotos (sin mencionar WhatsApp)
        _detectarSolicitudFotos(text);
      }
    });
    
    final success = await _creaService.iniciarSesion(
      widget.alerta,
      esperar3Minutos: widget.esperar3Minutos,
      esReconexion: widget.esReconexion,
    );
    
    setState(() {
      _isInitializing = false;
      if (!success) {
        _errorMessage = 'No se pudo conectar con el agente CREA.\n'
            'Verifica tu conexión a internet.';
      }
    });
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
    _creaService.enviarMensajeTexto(texto);
    _textController.clear();
  }

  void _toggleModo() {
    setState(() {
      _modoChat = !_modoChat;
    });
    
    if (_modoChat) {
      // Cambiar a modo chat: pausar micrófono
      _creaService.pausarEscucha();
    } else {
      // Cambiar a modo voz: reanudar micrófono
      _creaService.reanudarEscucha();
    }
  }

  /// Detecta si el agente solicita fotos (sin mencionar WhatsApp)
  void _detectarSolicitudFotos(String respuestaAgente) {
    final textoLower = respuestaAgente.toLowerCase();
    
    // Detectar si el agente solicita fotos (sin mencionar WhatsApp)
    // Solo detectar frases que claramente solicitan tomar fotos
    if (textoLower.contains('tomar foto') ||
        textoLower.contains('tomar fotograf') ||
        textoLower.contains('necesito foto') ||
        textoLower.contains('necesito fotograf') ||
        textoLower.contains('toma una foto') ||
        textoLower.contains('toma fotograf') ||
        textoLower.contains('captura una foto') ||
        textoLower.contains('haz una foto')) {
      
      // Si el servicio ya requiere fotos, no hacer nada (evitar duplicados)
      if (_creaService.requiereFotoOtraCompania) {
        return;
      }
      
      // Marcar que se requieren fotos y abrir cámara automáticamente
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _tomarFotos();
        }
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scrollController.dispose();
    _textController.dispose();
    _transcriptSub?.cancel();
    _responseSub?.cancel();
    _lastResponseText = ''; // Limpiar al destruir
    _lastTranscriptText = ''; // Limpiar al destruir
    super.dispose();
  }

  Future<void> _tomarFotos() async {
    // Verificar si es flujo CHURN
    final churnService = Provider.of<ChurnService>(context, listen: false);
    if (churnService.estado == EstadoChurn.detectado || 
        churnService.estado == EstadoChurn.capturandoFotos ||
        _creaService.requiereFotoOtraCompania) {
      // Usar flujo CHURN
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ChurnFotosScreen(alerta: widget.alerta),
        ),
      );
      return;
    }
    
    // Pausar escucha mientras toma fotos
    await _creaService.pausarEscucha();
    
    final fotos = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => const CameraScreen(),
      ),
    );
    
    if (fotos != null && fotos.isNotEmpty) {
      await _creaService.registrarFotos(fotos);
      _addMessage('📷 Se registraron ${fotos.length} foto(s)', isUser: true);
    }
    
    // Reanudar escucha
    await _creaService.reanudarEscucha();
  }

  void _finalizarConversacion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Finalizar Conversación'),
        content: const Text(
          '¿Deseas finalizar la conversación con CREA?\n\n'
          'La alerta quedará en el estado actual.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.alertUrgent,
            ),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      await _creaService.finalizarSesion();
      // NO cerrar la alerta aquí - solo cerrar la conversación
      // La alerta se cerrará solo cuando el agente verifique que está OK
      if (mounted) {
        Navigator.of(context).pop(); // Solo volver a la pantalla anterior, no eliminar la alerta
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: AppColors.creaGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.support_agent,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Agente CREA',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                ListenableBuilder(
                  listenable: _creaService,
                  builder: (context, _) {
                    return Text(
                      _getStateText(_creaService.state),
                      style: TextStyle(
                        fontSize: 12,
                        color: _getStateColor(_creaService.state),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Botón de mute
          ListenableBuilder(
            listenable: _creaService,
            builder: (context, _) {
              return IconButton(
                icon: Icon(
                  _creaService.isMuted ? Icons.mic_off : Icons.mic,
                  color: _creaService.isMuted 
                      ? AppColors.alertUrgent 
                      : AppColors.textPrimary,
                ),
                onPressed: () => _creaService.toggleMute(),
                tooltip: _creaService.isMuted 
                    ? 'Activar micrófono' 
                    : 'Silenciar micrófono',
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: _finalizarConversacion,
          ),
        ],
      ),
      body: Column(
        children: [
          // Info de la alerta
          _buildAlertaHeader(),
          
          // Estado de conexión o error
          if (_isInitializing)
            _buildConnectingIndicator()
          else if (_errorMessage != null)
            _buildErrorBanner()
          else ...[
            // Visualización del agente
            _buildAgentVisualization(),
            
            // Historial de conversación
            Expanded(
              child: _buildConversationHistory(),
            ),
            
            // Controles inferiores
            _buildBottomControls(),
          ],
        ],
      ),
    );
  }

  Widget _buildAlertaHeader() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.router, color: AppColors.creaVoice, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'CTO ${widget.alerta.nombreCto} • Pelo ${_formatearPelo(widget.alerta.numeroPelo)}',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.alertInfo.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'EN ATENCIÓN',
              style: TextStyle(
                color: AppColors.alertInfo,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectingIndicator() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 60,
              height: 60,
              child: CircularProgressIndicator(
                color: AppColors.creaVoice,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Conectando con CREA...',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Preparando asistente de voz',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Expanded(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.alertUrgent.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.error_outline,
                  color: AppColors.alertUrgent,
                  size: 48,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Error de conexión',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage ?? 'Error desconocido',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _initializeCrea,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.creaVoice,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Debug info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Verifica:\n'
                  '• Conexión a internet\n'
                  '• Permiso de micrófono\n'
                  '• Agent ID correcto',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAgentVisualization() {
    return ListenableBuilder(
      listenable: _creaService,
      builder: (context, _) {
        final state = _creaService.state;
        final color = _getStateColor(state);
        
        return Container(
          height: 180,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.2),
                AppColors.surface,
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Ondas de audio animadas
              if (state == CreaState.speaking || state == CreaState.listening)
                ...List.generate(3, (index) {
                  return AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final scale = 1.0 + (_pulseController.value * 0.3 * (index + 1));
                      return Container(
                        width: 80 * scale,
                        height: 80 * scale,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: color.withValues(alpha: 0.3 - (index * 0.1)),
                            width: 2,
                          ),
                        ),
                      );
                    },
                  );
                }),
              
              // Icono central
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.7)],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Icon(
                  _getStateIcon(state),
                  color: Colors.white,
                  size: 40,
                ),
              ),
              
              // Indicador de mute
              if (_creaService.isMuted)
                Positioned(
                  top: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.alertUrgent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.mic_off, color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'MUDO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              
              // Texto del estado
              Positioned(
                bottom: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _getStateText(state),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ).animate().fadeIn().scale(begin: const Offset(0.9, 0.9));
      },
    );
  }

  Widget _buildConversationHistory() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 16),
            const Text(
              'Esperando conversación...',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'CREA te hablará en unos segundos',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        return _buildMessageBubble(message)
            .animate()
            .fadeIn(duration: 300.ms)
            .slideX(begin: message.isUser ? 0.1 : -0.1);
      },
    );
  }

  Widget _buildMessageBubble(_ConversationMessage message) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          gradient: message.isUser
              ? const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                )
              : AppColors.creaGradient,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(message.isUser ? 16 : 4),
            bottomRight: Radius.circular(message.isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Indicador de quién habla
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  message.isUser ? Icons.person : Icons.support_agent,
                  color: Colors.white.withValues(alpha: 0.7),
                  size: 12,
                ),
                const SizedBox(width: 4),
                Text(
                  message.isUser ? 'Tú' : 'CREA',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              message.text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(message.timestamp),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Consumer<ChurnService>(
      builder: (context, churnService, _) {
        return ListenableBuilder(
          listenable: _creaService,
          builder: (context, _) {
            // Verificar si hay flujo CHURN activo
            final churnActivo = churnService.estado == EstadoChurn.detectado ||
                churnService.estado == EstadoChurn.capturandoFotos ||
                churnService.estado == EstadoChurn.esperandoValidacion;
            
            final requiereFoto = _creaService.requiereFotoOtraCompania ||
                widget.alerta.tipoAlerta.requiereFotos ||
                widget.alerta.tipoAlerta == TipoAlerta.churn ||
                churnActivo;
        
        final mostrarBotonSolucionada = _creaService.tecnicoAceptoVolverAContactar;
        
        // Si el técnico aceptó volver a contactar, mostrar solo el botón "Alerta Solucionada"
        if (mostrarBotonSolucionada) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(
                top: BorderSide(color: AppColors.surfaceBorder),
              ),
            ),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _marcarAlertaSolucionada,
                  icon: const Icon(Icons.check_circle),
                  label: const Text(
                    'ALERTA SOLUCIONADA',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.alertSuccess,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        
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
                      // Botón de cámara (para churn o otra compañía)
                      if (requiereFoto)
                        IconButton(
                          onPressed: _tomarFotos,
                          icon: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.alertWarning.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              color: AppColors.alertWarning,
                            ),
                          ),
                          tooltip: _creaService.requiereFotoOtraCompania 
                              ? 'Tomar foto (otra compañía)' 
                              : 'Tomar foto',
                        ),
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
                        onPressed: _finalizarConversacion,
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
                      // Botón de cámara (para churn o otra compañía)
                      if (requiereFoto)
                        IconButton(
                          onPressed: _tomarFotos,
                          icon: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.alertWarning.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              color: AppColors.alertWarning,
                            ),
                          ),
                          tooltip: _creaService.requiereFotoOtraCompania 
                              ? 'Tomar foto (otra compañía)' 
                              : 'Tomar foto',
                        ),
                      Expanded(
                        child: ListenableBuilder(
                          listenable: _creaService,
                          builder: (context, _) {
                            final isListening = _creaService.state == CreaState.listening;
                            final isSpeaking = _creaService.state == CreaState.speaking;
                            
                            return Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                gradient: isListening 
                                    ? AppColors.creaGradient 
                                    : isSpeaking
                                        ? const LinearGradient(
                                            colors: [
                                              AppColors.creaSpeaking,
                                              Color(0xFF1976D2),
                                            ],
                                          )
                                        : null,
                                color: (!isListening && !isSpeaking) 
                                    ? AppColors.surfaceLight 
                                    : null,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isListening || isSpeaking
                                      ? Colors.transparent 
                                      : AppColors.surfaceBorder,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isListening 
                                        ? Icons.mic 
                                        : isSpeaking 
                                            ? Icons.volume_up 
                                            : Icons.mic_none,
                                    color: (isListening || isSpeaking)
                                        ? Colors.white 
                                        : AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    isListening 
                                        ? 'ESCUCHANDO...' 
                                        : isSpeaking
                                            ? 'CREA ESTÁ HABLANDO...'
                                            : 'ESPERANDO...',
                                    style: TextStyle(
                                      color: (isListening || isSpeaking)
                                          ? Colors.white 
                                          : AppColors.textSecondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _finalizarConversacion,
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
          },
        );
      },
    );
  }

  Future<void> _marcarAlertaSolucionada() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Verificar y Marcar como Solucionada'),
        content: const Text(
          'Se activará el agente CREA para verificar el estado de la alerta.\n\n'
          'Si está OK, se moverá al historial.\n'
          'Si no está OK, se reiniciará la conversación.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.alertSuccess,
            ),
            child: const Text('Verificar'),
          ),
        ],
      ),
    );
    
    if (confirmed == true && mounted) {
      // Mostrar indicador de carga
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                color: AppColors.creaVoice,
              ),
              const SizedBox(height: 16),
              const Text(
                'Activando agente CREA...',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'Verificando estado de la alerta',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
      
      // Activar agente y verificar
      final estaOk = await _creaService.verificarYMarcarSolucionada();
      
      if (mounted) {
        Navigator.pop(context); // Cerrar diálogo de carga
      }
      
      if (estaOk) {
        // Está OK - marcar como solucionada y mover al historial
        final alertasProvider = context.read<AlertasProvider>();
        final success = await alertasProvider.marcarComoSolucionada(widget.alerta);
        
        if (success) {
          _creaService.marcarAlertaSolucionada();
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Alerta verificada y marcada como solucionada'),
                backgroundColor: AppColors.alertSuccess,
              ),
            );
            
            // Volver a la pantalla principal
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⚠️ Error al marcar la alerta como solucionada'),
                backgroundColor: AppColors.alertWarning,
              ),
            );
          }
        }
      } else {
        // NO está OK - la alerta permanece en atención, NO se elimina
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ La alerta aún no está regularizada. La alerta permanece en atención.'),
              backgroundColor: AppColors.alertWarning,
            ),
          );
          
          // Reiniciar conversación con CREA
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            // Reiniciar la sesión con CREA
            await _creaService.finalizarSesion();
            await Future.delayed(const Duration(seconds: 1));
            await _creaService.iniciarSesion(widget.alerta, esperar3Minutos: false);
          }
        }
      }
    } else {
      // Error al verificar - la alerta permanece en atención
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Error al verificar el estado. La alerta permanece en atención.'),
            backgroundColor: AppColors.alertWarning,
          ),
        );
      }
    }
  }

  String _getStateText(CreaState state) {
    switch (state) {
      case CreaState.idle:
        return 'Inactivo';
      case CreaState.connecting:
        return 'Conectando...';
      case CreaState.listening:
        return 'Escuchando';
      case CreaState.speaking:
        return 'Hablando';
      case CreaState.processing:
        return 'Procesando...';
      case CreaState.error:
        return 'Error';
      case CreaState.disconnected:
        return 'Desconectado';
    }
  }

  Color _getStateColor(CreaState state) {
    switch (state) {
      case CreaState.idle:
      case CreaState.disconnected:
        return AppColors.textMuted;
      case CreaState.connecting:
      case CreaState.processing:
        return AppColors.alertWarning;
      case CreaState.listening:
        return AppColors.creaListening;
      case CreaState.speaking:
        return AppColors.creaSpeaking;
      case CreaState.error:
        return AppColors.alertUrgent;
    }
  }

  IconData _getStateIcon(CreaState state) {
    switch (state) {
      case CreaState.idle:
      case CreaState.disconnected:
        return Icons.power_settings_new;
      case CreaState.connecting:
        return Icons.sync;
      case CreaState.listening:
        return Icons.mic;
      case CreaState.speaking:
        return Icons.volume_up;
      case CreaState.processing:
        return Icons.psychology;
      case CreaState.error:
        return Icons.error_outline;
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _formatearPelo(String numeroPelo) {
    // Extraer solo el número del pelo (ej: "P-04" -> "4", "4" -> "4")
    final numero = numeroPelo.replaceAll(RegExp(r'[^0-9]'), '');
    return numero.isEmpty ? numeroPelo : numero;
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

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:agente_desconexiones/constants/app_colors.dart';
import 'package:agente_desconexiones/services/elevenlabs_service.dart';

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
  // null = aún no eligió, true = voz, false = texto
  bool? _modoVoz;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Transcripciones del técnico (voz → texto reconocido)
    _transcriptSub = _elevenLabs.transcriptStream.listen((text) {
      if (text.isNotEmpty) _addMessage(text, isUser: true);
    });

    // Respuestas del agente: SIEMPRE al chat, modo voz o texto
    _responseSub = _elevenLabs.responseStream.listen((text) {
      if (text.isNotEmpty) _addMessage(text, isUser: false);
    });

    // eventStream: sin lógica de mensajes aquí (evita duplicados)
    _eventSub = _elevenLabs.eventStream.listen((_) {});

    _elevenLabs.addListener(_onStateChanged);

    // Mostrar diálogo de selección de modo al abrir
    WidgetsBinding.instance.addPostFrameCallback((_) => _mostrarDialogoModo());
  }

  void _onStateChanged() {
    setState(() {
      _isConnected = _elevenLabs.state == ElevenLabsState.connected ||
          _elevenLabs.state == ElevenLabsState.listening ||
          _elevenLabs.state == ElevenLabsState.speaking;
    });
  }

  // ── Selección de modo ────────────────────────────────────────────────────────

  Future<void> _mostrarDialogoModo() async {
    final elegido = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '¿Cómo querés interactuar?',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Elegí el modo antes de conectar.\nPodés ver las respuestas de CREA en el chat en ambos modos.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: _BotonModo(
                  icono: Icons.mic,
                  label: 'Voz',
                  descripcion: 'Hablá con CREA',
                  color: AppColors.creaVoice,
                  onTap: () => Navigator.of(ctx).pop(true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BotonModo(
                  icono: Icons.chat_bubble_outline,
                  label: 'Texto',
                  descripcion: 'Escribile a CREA',
                  color: const Color(0xFF10B981),
                  onTap: () => Navigator.of(ctx).pop(false),
                ),
              ),
            ]),
          ],
        ),
      ),
    );

    if (elegido == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    setState(() => _modoVoz = elegido);
    _iniciarAsistente(conVoz: elegido);
  }

  // ── Conexión ─────────────────────────────────────────────────────────────────

  Future<void> _iniciarAsistente({required bool conVoz}) async {
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    try {
      if (!conVoz) _elevenLabs.setTextOnlyMode();
      final connected = await _elevenLabs.connect(
        customData: {'tipo': 'asistente_terreno', 'contexto': 'Asistencia técnica en terreno'},
        agentId: ElevenLabsConfig.agentIdTerreno,
      );

      if (!connected) {
        setState(() {
          _isConnecting = false;
          _errorMessage = _elevenLabs.lastError ?? 'Error desconocido al conectar';
        });
        return;
      }

      // Voz: micrófono real. Texto: flujo de silencio para mantener VAD activo
      // y que user_message sea procesado por el servidor.
      if (conVoz) {
        await _elevenLabs.startListening();
      } else {
        // Pequeña espera para que el servidor complete el handshake inicial.
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) _elevenLabs.startTextMode();
      }

      setState(() {
        _isConnecting = false;
        _isConnected = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(conVoz
                ? '✅ Conectado — CREA te escucha por voz'
                : '✅ Conectado — Escribile a CREA'),
            backgroundColor: AppColors.alertSuccess,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _errorMessage = 'Error: $e';
      });
    }
  }

  // ── Mensajes ─────────────────────────────────────────────────────────────────

  void _addMessage(String text, {required bool isUser}) {
    setState(() {
      _messages.add(_ConversationMessage(
        text: text,
        isUser: isUser,
        timestamp: DateTime.now(),
      ));
    });
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
    if (texto.isEmpty || !_isConnected) return;
    _elevenLabs.sendTextMessage(texto);
    _textController.clear();
  }

  Future<void> _finalizarSesion() async {
    await _elevenLabs.disconnect();
    setState(() {
      _isConnected = false;
      _messages.clear();
      _modoVoz = null;
    });
    if (mounted) _mostrarDialogoModo();
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

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            if (_isConnected) await _elevenLabs.disconnect();
            if (mounted) Navigator.of(context).pop();
          },
        ),
        title: Row(
          children: [
            Icon(
              _modoVoz == true ? Icons.mic : Icons.chat_bubble_outline,
              color: AppColors.creaVoice,
            ),
            const SizedBox(width: 12),
            Text(_modoVoz == true
                ? 'Asistente CREA — Voz'
                : 'Asistente CREA — Chat'),
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
          if (_isConnecting || _isConnected) _buildBannerEstado(),

          // Chat
          Expanded(
            child: _messages.isEmpty && !_isConnecting
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _buildMessageBubble(_messages[i]),
                  ),
          ),

          // Error
          if (_errorMessage != null) _buildBannerError(),

          // Cargando
          if (_isConnecting) _buildCargando(),

          // Controles
          if (_isConnected && !_isConnecting) _buildControles(),
        ],
      ),
    );
  }

  Widget _buildBannerEstado() {
    final color = _isConnected ? AppColors.alertSuccess : AppColors.alertWarning;
    final texto = _isConnecting
        ? 'Conectando con asistente...'
        : _modoVoz == true
            ? 'CREA te escucha — respondé también por chat'
            : 'CREA está lista — escribile abajo';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: color.withOpacity(0.15),
      child: Row(children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ).animate(onPlay: (c) => c.repeat()).scale(
            duration: 1000.ms,
            begin: const Offset(1, 1),
            end: const Offset(1.3, 1.3)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(texto,
              style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      ]),
    );
  }

  Widget _buildBannerError() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: AppColors.alertUrgent.withOpacity(0.15),
      child: Row(children: [
        const Icon(Icons.error_outline, color: AppColors.alertUrgent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(_errorMessage!,
              style: const TextStyle(color: AppColors.alertUrgent)),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          onPressed: () => setState(() => _errorMessage = null),
        ),
      ]),
    );
  }

  Widget _buildCargando() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: const [
        CircularProgressIndicator(color: AppColors.creaVoice),
        SizedBox(height: 12),
        Text('Conectando con asistente...',
            style: TextStyle(color: AppColors.textSecondary)),
      ]),
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
                gradient: AppColors.creaGradient, shape: BoxShape.circle),
            child: Icon(
              _modoVoz == true ? Icons.mic : Icons.chat_bubble_outline,
              size: 64, color: Colors.white,
            ),
          ).animate().scale(delay: 200.ms, duration: 600.ms),
          const SizedBox(height: 32),
          Text(
            _modoVoz == true
                ? 'Hablá con CREA'
                : 'Escribile a CREA',
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ).animate().fadeIn(delay: 400.ms),
          const SizedBox(height: 8),
          Text(
            _modoVoz == true
                ? 'CREA te escucha. Sus respuestas también\naparecen acá abajo.'
                : 'Escribí tu mensaje y CREA te responde\ntambién por escrito.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 600.ms),
        ],
      ),
    );
  }

  Widget _buildControles() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.surfaceBorder)),
      ),
      child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // En modo voz: indicador de estado + botón colgar
          if (_modoVoz == true) _buildControlesVoz(),
          // En ambos modos: campo de texto siempre visible
          const SizedBox(height: 8),
          _buildCampoTexto(),
        ]),
      ),
    );
  }

  Widget _buildControlesVoz() {
    final escuchando = _elevenLabs.state == ElevenLabsState.listening;
    final hablando   = _elevenLabs.state == ElevenLabsState.speaking;
    final color = hablando
        ? AppColors.creaSpeaking
        : escuchando
            ? AppColors.creaVoice
            : AppColors.surfaceLight;
    final label = hablando
        ? 'CREA ESTÁ HABLANDO...'
        : escuchando
            ? 'ESCUCHANDO...'
            : 'ESPERANDO...';

    return Row(children: [
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(
              hablando ? Icons.volume_up : Icons.mic,
              color: (hablando || escuchando) ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                  color: (hablando || escuchando) ? Colors.white : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                )),
          ]),
        ),
      ),
      const SizedBox(width: 8),
      _botonColgar(),
    ]);
  }

  Widget _buildCampoTexto() {
    return Row(children: [
      Expanded(
        child: TextField(
          controller: _textController,
          enabled: _isConnected,
          decoration: InputDecoration(
            hintText: _modoVoz == true
                ? 'También podés escribir...'
                : 'Escribí tu mensaje...',
            hintStyle: const TextStyle(color: AppColors.textSecondary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide(color: AppColors.surfaceBorder),
            ),
            filled: true,
            fillColor: AppColors.background,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          ),
          style: const TextStyle(color: AppColors.textPrimary),
          maxLines: null,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _enviarMensajeTexto(),
        ),
      ),
      const SizedBox(width: 8),
      IconButton(
        onPressed: _isConnected ? _enviarMensajeTexto : null,
        icon: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            gradient: _isConnected ? AppColors.creaGradient : null,
            color: _isConnected ? null : AppColors.surfaceLight,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.send,
              color: _isConnected ? Colors.white : AppColors.textSecondary,
              size: 20),
        ),
      ),
      if (_modoVoz != true) _botonColgar(),
    ]);
  }

  Widget _botonColgar() {
    return IconButton(
      onPressed: _finalizarSesion,
      icon: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.alertUrgent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.call_end, color: AppColors.alertUrgent),
      ),
    );
  }

  Widget _buildMessageBubble(_ConversationMessage msg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment:
            msg.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!msg.isUser) ...[
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                  gradient: AppColors.creaGradient, shape: BoxShape.circle),
              child: const Icon(Icons.mic, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: msg.isUser
                    ? AppColors.creaVoice.withOpacity(0.2)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: msg.isUser
                      ? AppColors.creaVoice
                      : Colors.transparent,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(msg.text,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          height: 1.4)),
                  const SizedBox(height: 3),
                  Text(_formatTime(msg.timestamp),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
            ),
          ),
          if (msg.isUser) ...[
            const SizedBox(width: 10),
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: AppColors.creaVoice.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person,
                  color: AppColors.creaVoice, size: 18),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes}m';
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}

// ── Widgets auxiliares ────────────────────────────────────────────────────────

class _BotonModo extends StatelessWidget {
  const _BotonModo({
    required this.icono,
    required this.label,
    required this.descripcion,
    required this.color,
    required this.onTap,
  });
  final IconData icono;
  final String label;
  final String descripcion;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icono, color: color, size: 36),
          const SizedBox(height: 8),
          Text(label,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 4),
          Text(descripcion,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

class _ConversationMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  const _ConversationMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

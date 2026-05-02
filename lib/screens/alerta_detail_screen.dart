import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:agente_desconexiones/constants/app_colors.dart';
import 'package:agente_desconexiones/models/alerta.dart';
import 'package:agente_desconexiones/providers/alertas_provider.dart';
import 'package:agente_desconexiones/screens/crea_conversation_screen.dart';
import 'package:agente_desconexiones/services/alerta_contexto_service.dart';
import 'package:agente_desconexiones/services/alertas_cto_service.dart';
import 'package:agente_desconexiones/models/alerta_cto.dart' as cto_models;
import 'package:intl/intl.dart';

class AlertaDetailScreen extends StatefulWidget {
  final Alerta alerta;

  const AlertaDetailScreen({super.key, required this.alerta});

  @override
  State<AlertaDetailScreen> createState() => _AlertaDetailScreenState();
}

class _AlertaDetailScreenState extends State<AlertaDetailScreen> {
  late Alerta _alerta;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _alerta = widget.alerta;
    
    // Marcar como nueva si es la primera vez que se abre esta alerta
    _marcarAlertaComoNuevaSiEsPrimeraVez();
    
    // Actualizar cada segundo si está pendiente
    if (_alerta.estado == EstadoAlerta.pendiente) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  /// Marca la alerta como nueva si es la primera vez que se abre
  Future<void> _marcarAlertaComoNuevaSiEsPrimeraVez() async {
    final contextoService = AlertaContextoService();
    final estadoContexto = contextoService.obtenerEstado(_alerta.numeroOt);
    
    // Si no existe contexto, es la primera vez que se abre
    if (estadoContexto == EstadoContextoAlerta.nueva) {
      await contextoService.marcarComoNueva(_alerta);
      print('📝 Alerta ${_alerta.numeroOt} marcada como nueva (primera vez)');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _atenderAlerta() async {
    final alertasProvider = context.read<AlertasProvider>();
    
    // Mostrar diálogo de confirmación
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Atender Alerta'),
        content: const Text(
          'Se conectará con el agente CREA para verificar la comunicación.\n\n'
          'Tendrás 3 minutos para resolver la alerta antes de que el agente vuelva a contactarte.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.alertUrgent,
            ),
            child: const Text('Atender'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    final success = await alertasProvider.atenderAlerta(_alerta);
    
    if (success && mounted) {
      setState(() {
        _alerta = _alerta.copyWith(
          estado: EstadoAlerta.enAtencion,
          fechaAtendida: DateTime.now(),
        );
      });
      
      // Navegar a conversación con CREA para verificar comunicación
      // Siempre esperar 3 minutos en cada interacción
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CreaConversationScreen(
            alerta: _alerta,
            esperar3Minutos: true, // Siempre esperar 3 minutos en cada interacción
            esReconexion: false, // Primera llamada
          ),
        ),
      );
    }
  }

  Future<void> _postergarAlerta() async {
    final alertasProvider = context.read<AlertasProvider>();
    
    if (!alertasProvider.puedePostergarse(_alerta)) {
      _showError('Esta alerta ya fue postergada anteriormente');
      return;
    }
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Postergar Alerta'),
        content: const Text(
          '¿Deseas postergar esta alerta por 5 minutos?\n\n'
          'Nota: Solo puedes postergar una vez por alerta.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.postergar,
            ),
            child: const Text('Postergar'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      final success = await alertasProvider.postergarAlerta(_alerta);
      if (success && mounted) {
        Navigator.pop(context);
        _showSuccess('Alerta postergada por 5 minutos');
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.alertUrgent,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.alertSuccess,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1628), // Fondo oscuro estilo Kepler
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1B2A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '← Volver',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 14,
          ),
        ),
        titleSpacing: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header con OT
            _buildHeader(),
            
            // Info boxes en fila
            _buildInfoRow(),
            
            // Botones de acción
            _buildActionButtonsKepler(),
            
            // Comentarios de resolución
            if (_alerta.comentarioResolucion != null || _alerta.notas != null)
              _buildComentarios(),
            
            // Tabla de niveles de puertos
            _buildNivelesTabla(),
            
            const SizedBox(height: 24),
            
            // Countdown si es pendiente
            if (_alerta.estado == EstadoAlerta.pendiente ||
                _alerta.estado == EstadoAlerta.postergada)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildCountdown(),
              ),
            
            const SizedBox(height: 100), // Espacio para los botones flotantes
          ],
        ),
      ),
      // Botones flotantes de acción
      bottomNavigationBar: (_alerta.estado == EstadoAlerta.pendiente ||
              _alerta.estado == EstadoAlerta.postergada ||
              _alerta.estado == EstadoAlerta.enAtencion)
          ? _buildBottomActions()
          : null,
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF0D1B2A),
        border: Border(
          bottom: BorderSide(color: Color(0xFF1E3A5F), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Orden de Trabajo: ${_alerta.numeroOt}',
            style: const TextStyle(
              color: Color(0xFFFF6B35), // Naranja estilo Kepler
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildInfoRow() {
    final tiempoEjec = _alerta.tiempoEjecucion;
    final tiempoStr = tiempoEjec != null
        ? '${tiempoEjec.inHours}:${(tiempoEjec.inMinutes % 60).toString().padLeft(2, '0')}'
        : '-';
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildInfoBox('EMPRESA', _alerta.empresa ?? 'CREA', width: 100),
            _buildInfoBox('TÉCNICO', _alerta.nombreTecnico, width: 150),
            _buildInfoBox('ACTIVIDAD', _alerta.actividad ?? _alerta.tipoAlerta.displayName, width: 100),
            _buildInfoBox('ACCESS ID', _alerta.accessId, width: 120),
            _buildInfoBox('ESTADO', _alerta.estado == EstadoAlerta.enAtencion ? 'Ejecutando' : _alerta.estado.displayName, width: 80),
            _buildInfoBox('FECHA', DateFormat('dd/MM/yyyy').format(_alerta.fechaRecepcion), width: 100),
            _buildInfoBox('TIEMPO', tiempoStr, width: 80),
            _buildInfoBox('PELO', _formatearPelo(_alerta.numeroPelo), width: 60, isHighlighted: true),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 100.ms);
  }

  Widget _buildInfoBox(String label, String value, {double width = 100, bool isHighlighted = false}) {
    return Container(
      width: width,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        border: Border.all(
          color: isHighlighted ? const Color(0xFF00D9FF) : const Color(0xFF1E3A5F),
          width: isHighlighted ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF5C7A99),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.isEmpty ? '-' : value,
            style: TextStyle(
              color: isHighlighted ? const Color(0xFF00D9FF) : Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtonsKepler() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Botón Actualizar Consulta2
          Expanded(
            child: _buildKeplerButton(
              icon: Icons.refresh,
              label: 'Actualizar',
              color: const Color(0xFF00D9FF),
              onPressed: _actualizarConsultaKepler,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms);
  }

  Widget _buildKeplerButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }

  Widget _buildComentarios() {
    final comentario = _alerta.comentarioResolucion ?? _alerta.notas ?? '';
    
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E3A5F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.comment, color: Color(0xFF00D9FF), size: 18),
              const SizedBox(width: 8),
              const Text(
                'Comentarios de Resolución',
                style: TextStyle(
                  color: Color(0xFF00D9FF),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF162942),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF1E3A5F)),
            ),
            child: Text(
              comentario.isEmpty ? 'Sin comentarios' : comentario,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Usuario: WebUser | Fecha: ${DateFormat('HH:mm').format(_alerta.fechaRecepcion)}',
            style: const TextStyle(
              color: Color(0xFF5C7A99),
              fontSize: 11,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 300.ms);
  }

  Widget _buildNivelesTabla() {
    // Crear datos de ejemplo si no hay niveles reales
    final niveles = _alerta.nivelesPuertos ?? _generarNivelesDemo();
    
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E3A5F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título de la tabla
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFF1E3A5F)),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.table_chart, color: Color(0xFF00D9FF), size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Detalles de Alertas y Niveles de Puertos',
                  style: TextStyle(
                    color: Color(0xFF00D9FF),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          
          // Encabezado de la tabla
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: const BoxDecoration(
              color: Color(0xFF162942),
              border: Border(
                bottom: BorderSide(color: Color(0xFF1E3A5F)),
              ),
            ),
            child: Row(
              children: [
                _buildTableHeader('Puerto', flex: 1),
                _buildTableHeader('Consulta1 (Inicial)', flex: 2),
                _buildTableHeader('Consulta2 (Final)', flex: 2),
                _buildTableHeader('Diferencia', flex: 2),
                _buildTableHeader('Estado', flex: 2),
              ],
            ),
          ),
          
          // Filas de datos
          ...niveles.asMap().entries.map((entry) {
            final index = entry.key;
            final nivel = entry.value;
            // Determinar si este puerto es el pelo de la OT actual
            final peloOT = int.tryParse(_alerta.numeroPelo.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
            final esPeloOT = nivel.puerto == peloOT;
            // El pelo 2 siempre se marca en rojo si tiene consulta2 = 0
            final esPelo2ConCero = nivel.puerto == 2 && nivel.consulta2 == 0.0;
            return _buildTableRow(nivel, isAlternate: index % 2 == 1, esPeloOT: esPeloOT, esPelo2ConCero: esPelo2ConCero);
          }),
        ],
      ),
    ).animate().fadeIn(delay: 400.ms);
  }

  List<NivelPuerto> _generarNivelesDemo() {
    // Generar datos de demostración basados en la alerta
    final peloNum = int.tryParse(_alerta.numeroPelo.replaceAll(RegExp(r'[^0-9]'), '')) ?? 2;
    
    return List.generate(8, (index) {
      final puerto = index + 1;
      final esPeloAfectado = puerto == peloNum;
      
      // IMPORTANTE: El pelo 2 SIEMPRE debe tener consulta2 = 0 (identificar desconexión de terceros)
      if (puerto == 2) {
        // Pelo 2 - cliente nuestro, consulta2 = 0 (identificar desconexión de terceros)
        return NivelPuerto(
          puerto: puerto,
          consulta1: -21.30,
          consulta2: 0.0, // SIEMPRE 0 para identificar desconexión de terceros
        );
      } else if (esPeloAfectado) {
        // Puerto afectado (pelo de la OT) - muestra -21.20 en ambas consultas
        return NivelPuerto(
          puerto: puerto,
          consulta1: -21.20, // Valor inicial según la imagen
          consulta2: -21.20, // Segunda consulta (no perdió señal, solo muestra el valor)
        );
      } else if (puerto <= 5) {
        // Puertos con valores normales
        final base = -20.0 - (puerto * 0.5);
        return NivelPuerto(
          puerto: puerto,
          consulta1: base,
          consulta2: base + 0.3,
        );
      } else {
        // Puertos sin medición
        return NivelPuerto(
          puerto: puerto,
          consulta1: null,
          consulta2: puerto == 7 ? -20.0 : null,
        );
      }
    });
  }

  Widget _buildTableHeader(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF8FA8C8),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildTableRow(NivelPuerto nivel, {bool isAlternate = false, bool esPeloOT = false, bool esPelo2ConCero = false}) {
    final consulta1Str = nivel.consulta1?.toStringAsFixed(2) ?? '-';
    final consulta2Str = nivel.consulta2?.toStringAsFixed(2) ?? '-';
    final diferencia = nivel.diferencia;
    final diferenciaStr = diferencia.toStringAsFixed(2);
    final senalPerdida = nivel.senalPerdida;
    
    // Colores:
    // - ROJO (#FF4444) para señal perdida o pelo 2 con consulta2 = 0
    // - AMARILLO (#FFD600) para pelo de la OT (si no tiene señal perdida y no es pelo 2 con cero)
    const colorRojo = Color(0xFFFF4444);
    const colorAmarillo = Color(0xFFFFD600);
    
    Color? rowColor;
    Color? borderLeftColor;
    
    // PRIORIDAD 1: Pelo 2 con consulta2 = 0 siempre se marca en ROJO
    if (esPelo2ConCero) {
      rowColor = colorRojo.withOpacity(0.2);
      borderLeftColor = colorRojo;
    } else if (esPeloOT) {
      // Pelo de la OT = AMARILLO (si no es pelo 2 con cero)
      rowColor = colorAmarillo.withOpacity(0.15);
      borderLeftColor = colorAmarillo;
    } else if (senalPerdida) {
      // Señal perdida en otro pelo (no el de la OT) = ROJO
      rowColor = colorRojo.withOpacity(0.2);
      borderLeftColor = colorRojo;
    }
    
    final bgColor = rowColor ?? (isAlternate ? const Color(0xFF0F2238) : const Color(0xFF0D1B2A));
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(
            color: borderLeftColor ?? const Color(0xFF1E3A5F), 
            width: (senalPerdida || esPeloOT || esPelo2ConCero) ? 1 : 0.5,
          ),
          left: borderLeftColor != null 
              ? BorderSide(color: borderLeftColor, width: 4) 
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          // Puerto - resaltado según estado
          Expanded(
            flex: 1,
            child: (senalPerdida || esPeloOT || esPelo2ConCero)
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (senalPerdida || esPelo2ConCero) ? colorRojo : colorAmarillo,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      nivel.puerto.toString(),
                      style: TextStyle(
                        color: (senalPerdida || esPelo2ConCero) ? Colors.white : Colors.black,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : Text(
                    nivel.puerto.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
          ),
          // Consulta1
          Expanded(
            flex: 2,
            child: Text(
              consulta1Str,
              style: TextStyle(
                color: (senalPerdida || esPeloOT || esPelo2ConCero) ? Colors.white : Colors.white70,
                fontSize: 13,
                fontWeight: (senalPerdida || esPeloOT || esPelo2ConCero) ? FontWeight.w600 : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // Consulta2
          Expanded(
            flex: 2,
            child: Text(
              consulta2Str,
              style: TextStyle(
                color: (senalPerdida || esPeloOT || esPelo2ConCero) ? Colors.white : Colors.white70,
                fontSize: 13,
                fontWeight: (senalPerdida || esPeloOT || esPelo2ConCero) ? FontWeight.w600 : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // Diferencia
          Expanded(
            flex: 2,
            child: Text(
              diferenciaStr,
              style: TextStyle(
                color: (senalPerdida || esPelo2ConCero) ? colorRojo : const Color(0xFF4CAF50),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // Estado
          Expanded(
            flex: 2,
            child: (senalPerdida || esPelo2ConCero)
                ? FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.warning_amber,
                          color: colorRojo,
                          size: 14,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          'Perdida',
                          style: TextStyle(
                            color: colorRojo,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                : const Icon(
                    Icons.check,
                    color: Color(0xFF4CAF50),
                    size: 18,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountdown() {
    final restante = _alerta.tiempoRestanteEscalamiento;
    final minutos = restante.inMinutes;
    final segundos = restante.inSeconds % 60;
    final esUrgente = restante.inSeconds < 60;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: esUrgente
              ? [const Color(0xFFFF6B35), const Color(0xFFFF8E53)]
              : [const Color(0xFFFFA726), const Color(0xFFFFD93D)],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: (esUrgente ? const Color(0xFFFF6B35) : const Color(0xFFFFA726))
                .withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            esUrgente ? Icons.warning_amber : Icons.timer,
            color: Colors.white,
            size: 40,
          )
              .animate(onPlay: (c) => c.repeat())
              .shake(duration: 500.ms, delay: 500.ms),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  esUrgente ? '¡ATENCIÓN URGENTE!' : 'Tiempo para escalar',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  restante.inSeconds <= 0
                      ? 'Escalando...'
                      : '${minutos.toString().padLeft(2, '0')}:${segundos.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn().scale(begin: const Offset(0.95, 0.95));
  }

  String _formatearPelo(String numeroPelo) {
    // Extraer solo el número del pelo (ej: "P-04" -> "4", "4" -> "4")
    final numero = numeroPelo.replaceAll(RegExp(r'[^0-9]'), '');
    return numero.isEmpty ? numeroPelo : numero;
  }

  Widget _buildBottomActions() {
    final alertasProvider = context.watch<AlertasProvider>();
    final puedePostergarse = alertasProvider.puedePostergarse(_alerta);
    final estaEnAtencion = _alerta.estado == EstadoAlerta.enAtencion;
    
    // Si está en atención, mostrar solo botón para volver a contactar al agente
    if (estaEnAtencion) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Color(0xFF0D1B2A),
          border: Border(
            top: BorderSide(color: Color(0xFF1E3A5F)),
          ),
        ),
        child: SafeArea(
          child: ElevatedButton.icon(
            onPressed: _volverAContactarAgente,
            icon: const Icon(Icons.phone_in_talk, size: 24),
            label: const Text(
              'VOLVER A CONTACTAR AL AGENTE',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      );
    }
    
    // Si está pendiente o postergada, mostrar botones de postergar y atender
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF0D1B2A),
        border: Border(
          top: BorderSide(color: Color(0xFF1E3A5F)),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Botón Postergar
            Expanded(
              child: OutlinedButton.icon(
                onPressed: puedePostergarse ? _postergarAlerta : null,
                icon: const Icon(Icons.schedule, size: 20),
                label: Text(
                  puedePostergarse ? 'POSTERGAR 5 MIN' : 'YA POSTERGADA',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: puedePostergarse
                      ? const Color(0xFFFFA726)
                      : Colors.grey,
                  side: BorderSide(
                    color: puedePostergarse
                        ? const Color(0xFFFFA726)
                        : Colors.grey,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Botón Atender
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: _atenderAlerta,
                icon: const Icon(Icons.phone_in_talk, size: 24),
                label: const Text(
                  'ATENDER ALERTA',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _volverAContactarAgente() async {
    // Navegar directamente a conversación con CREA (marcando como reconexión)
    // Siempre esperar 3 minutos en cada interacción
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreaConversationScreen(
          alerta: _alerta,
          esperar3Minutos: true, // Siempre esperar 3 minutos en cada interacción
          esReconexion: true, // Indicar que es una reconexión
        ),
      ),
    );
  }

  /// Actualiza la consulta desde Kepler y refresca los datos
  Future<void> _actualizarConsultaKepler() async {
    try {
      // Mostrar indicador de carga
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Text('Actualizando consulta desde Kepler...'),
            ],
          ),
          duration: Duration(seconds: 3),
          backgroundColor: Color(0xFF00D9FF),
        ),
      );

      // Llamar al servicio para verificar y actualizar la alerta
      final alertasCTOService = AlertasCTOService();
      final resultado = await alertasCTOService.verificarYActualizarAlerta(_alerta.numeroOt);

      if (!mounted) return;

      if (resultado['solucionado'] == true) {
        // La alerta fue solucionada
        _showSuccess(resultado['mensaje'] ?? 'Alerta resuelta');
        
        // Actualizar estado de la alerta en el provider
        final alertasProvider = context.read<AlertasProvider>();
        await alertasProvider.marcarComoSolucionada(_alerta);
        
        // Actualizar UI
        setState(() {
          _alerta = _alerta.copyWith(
            estado: EstadoAlerta.regularizada,
            comentarioResolucion: resultado['mensaje'] ?? 'Verificado por CREA',
          );
        });
      } else {
        // La alerta aún está activa - consultar alertas CTO para obtener datos actualizados
        try {
          final alertasActualizadas = await alertasCTOService.consultarAlertas();
          
          // Buscar la alerta actual en los resultados
          cto_models.AlertaCTO? alertaActualizada;
          try {
            alertaActualizada = alertasActualizadas.firstWhere(
              (a) => a.ot == _alerta.numeroOt,
            );
          } catch (e) {
            // No se encontró la alerta en los resultados
            print('⚠️ Alerta ${_alerta.numeroOt} no encontrada en resultados actualizados');
          }
          
          if (alertaActualizada != null) {
            // Convertir AlertaCTO a Alerta para actualizar los niveles
            final alertaConvertida = AlertasCTOService.convertirAlertaCTOaAlerta(alertaActualizada);
            
            // Actualizar UI con los nuevos datos
            setState(() {
              _alerta = _alerta.copyWith(
                nivelesPuertos: alertaConvertida.nivelesPuertos,
                valorConsulta2: alertaConvertida.valorConsulta2,
              );
            });
            
            _showSuccess('Consulta actualizada desde Kepler');
          } else {
            _showSuccess(resultado['mensaje'] ?? 'Consulta actualizada');
          }
        } catch (e) {
          print('⚠️ Error obteniendo alertas actualizadas: $e');
          _showSuccess(resultado['mensaje'] ?? 'Consulta actualizada');
        }
      }
    } catch (e) {
      if (!mounted) return;
      _showError('Error al actualizar: ${e.toString()}');
      print('❌ Error actualizando consulta: $e');
    }
  }
}

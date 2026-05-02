import 'package:flutter/material.dart';
import 'package:agente_desconexiones/constants/app_colors.dart';
import 'package:agente_desconexiones/models/alerta.dart';
import 'package:intl/intl.dart';

class AlertaCard extends StatelessWidget {
  final Alerta alerta;
  final VoidCallback? onTap;

  const AlertaCard({
    super.key,
    required this.alerta,
    this.onTap,
  });

  String _formatearPelo(String numeroPelo) {
    // Extraer solo el número del pelo (ej: "P-04" -> "4", "4" -> "4")
    final numero = numeroPelo.replaceAll(RegExp(r'[^0-9]'), '');
    return numero.isEmpty ? numeroPelo : numero;
  }

  @override
  Widget build(BuildContext context) {
    final esUrgente = alerta.estado == EstadoAlerta.pendiente &&
        alerta.tiempoRestanteEscalamiento.inSeconds < 60;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1B2A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _getBorderColor(),
            width: alerta.estado == EstadoAlerta.pendiente ? 2 : 1,
          ),
          boxShadow: alerta.estado == EstadoAlerta.pendiente
              ? [
                  BoxShadow(
                    color: _getBorderColor().withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Barra lateral de estado
              Container(
                width: 6,
                decoration: BoxDecoration(
                  color: _getBorderColor(),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(11),
                    bottomLeft: Radius.circular(11),
                  ),
                ),
              ),
              
              // Contenido principal
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // Número de OT destacado
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Label OT
                            const Text(
                              'ORDEN DE TRABAJO',
                              style: TextStyle(
                                color: Color(0xFF5C7A99),
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Número de OT grande
                            Text(
                              alerta.numeroOt,
                              style: TextStyle(
                                color: esUrgente 
                                    ? const Color(0xFFFF6B35) 
                                    : Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Info secundaria compacta
                            Row(
                              children: [
                                _buildMiniChip(
                                  'Pelo ${_formatearPelo(alerta.numeroPelo)}',
                                  const Color(0xFF00D9FF),
                                ),
                                const SizedBox(width: 8),
                                _buildMiniChip(
                                  alerta.tipoAlerta.displayName,
                                  _getBorderColor(),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      
                      // Lado derecho: tiempo y flecha
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (alerta.estado == EstadoAlerta.pendiente) ...[
                            // Countdown
                            _buildCountdown(),
                          ] else ...[
                            // Estado
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _getBorderColor().withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                alerta.estado.displayName,
                                style: TextStyle(
                                  color: _getBorderColor(),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Icon(
                            Icons.chevron_right,
                            color: const Color(0xFF5C7A99),
                            size: 28,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildCountdown() {
    final restante = alerta.tiempoRestanteEscalamiento;
    final esUrgente = restante.inSeconds < 60;
    
    if (restante.inSeconds <= 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFF6B35).withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber, color: Color(0xFFFF6B35), size: 14),
            SizedBox(width: 4),
            Text(
              'ESCALANDO',
              style: TextStyle(
                color: Color(0xFFFF6B35),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
    
    final minutos = restante.inMinutes;
    final segundos = restante.inSeconds % 60;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: esUrgente 
            ? const Color(0xFFFF6B35).withOpacity(0.2)
            : const Color(0xFF1E3A5F),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer,
            color: esUrgente ? const Color(0xFFFF6B35) : const Color(0xFF00D9FF),
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            '${minutos.toString().padLeft(2, '0')}:${segundos.toString().padLeft(2, '0')}',
            style: TextStyle(
              color: esUrgente ? const Color(0xFFFF6B35) : Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Color _getBorderColor() {
    switch (alerta.estado) {
      case EstadoAlerta.pendiente:
        return const Color(0xFFFF6B35); // Naranja
      case EstadoAlerta.postergada:
        return const Color(0xFFFFA726); // Naranja claro
      case EstadoAlerta.enAtencion:
        return const Color(0xFF00D9FF); // Cyan
      case EstadoAlerta.enRevisionCalidad:
        return const Color(0xFFFFC107); // Amarillo/Ámbar (en revisión)
      case EstadoAlerta.escalada:
        return const Color(0xFFAB47BC); // Morado
      case EstadoAlerta.regularizada:
      case EstadoAlerta.cerrada:
        return const Color(0xFF4CAF50); // Verde
    }
  }
}

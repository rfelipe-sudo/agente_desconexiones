import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:agente_desconexiones/constants/app_colors.dart';
import 'package:agente_desconexiones/models/solicitud_ayuda.dart';
import 'package:agente_desconexiones/services/ayuda_service.dart';

/// Pantalla de historial de solicitudes de ayuda
class AyudaHistorialScreen extends StatelessWidget {
  const AyudaHistorialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Row(
          children: [
            Icon(Icons.history, color: Color(0xFF4CAF50)),
            SizedBox(width: 12),
            Text('Historial de Ayuda'),
          ],
        ),
      ),
      body: Consumer<AyudaService>(
        builder: (context, ayudaService, _) {
          final historial = ayudaService.historial;

          if (historial.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history,
                    size: 64,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No hay solicitudes en el historial',
                    style: TextStyle(
                      fontSize: 18,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: historial.length,
            itemBuilder: (context, index) {
              final solicitud = historial[index];
              return _buildSolicitudCard(solicitud, index)
                  .animate()
                  .fadeIn(delay: (index * 50).ms)
                  .slideX(begin: -0.1);
            },
          );
        },
      ),
    );
  }

  Widget _buildSolicitudCard(SolicitudAyuda solicitud, int index) {
    Color estadoColor;
    IconData estadoIcon;

    switch (solicitud.estado) {
      case EstadoSolicitud.completada:
        estadoColor = Colors.green;
        estadoIcon = Icons.check_circle;
        break;
      case EstadoSolicitud.cancelada:
        estadoColor = Colors.red;
        estadoIcon = Icons.cancel;
        break;
      default:
        estadoColor = Colors.orange;
        estadoIcon = Icons.access_time;
    }

    IconData tipoIcon;
    Color tipoColor;

    switch (solicitud.tipo) {
      case TipoAyuda.ducto:
        tipoIcon = Icons.block;
        tipoColor = const Color(0xFFFF6B35);
        break;
      case TipoAyuda.fusion:
        tipoIcon = Icons.cable;
        tipoColor = const Color(0xFF4CAF50);
        break;
      case TipoAyuda.zonaRoja:
        tipoIcon = Icons.warning_amber_rounded;
        tipoColor = const Color(0xFFE53935);
        break;
      case TipoAyuda.crucePeligroso:
        tipoIcon = Icons.inventory_2;
        tipoColor = const Color(0xFFFFB347);
        break;
      case TipoAyuda.altura:
        tipoIcon = Icons.height;
        tipoColor = const Color(0xFF42A5F5);
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header con tipo y estado
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: tipoColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(tipoIcon, color: tipoColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      solicitud.tipo.displayName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('dd/MM/yyyy HH:mm').format(solicitud.fechaCreacion),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: estadoColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(estadoIcon, color: estadoColor, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      solicitud.estado.displayName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: estadoColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Información del supervisor si fue asignado
          if (solicitud.supervisorNombre != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.support_agent,
                    size: 20,
                    color: Color(0xFF4CAF50),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Supervisor',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          solicitud.supervisorNombre!,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (solicitud.distanciaKm != null) ...[
                    const Icon(
                      Icons.straighten,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${solicitud.distanciaKm!.toStringAsFixed(1)} km',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          
          // Ticket ID
          Row(
            children: [
              const Icon(
                Icons.tag,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                'Ticket: ${solicitud.ticketId}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}





















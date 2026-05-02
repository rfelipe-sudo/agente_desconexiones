import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:agente_desconexiones/services/churn_service.dart';
import 'package:agente_desconexiones/models/alerta.dart';
import 'package:agente_desconexiones/providers/alertas_provider.dart';

/// Pantalla para captura de fotos de evidencia CHURN
class ChurnFotosScreen extends StatefulWidget {
  final Alerta alerta;

  const ChurnFotosScreen({
    Key? key,
    required this.alerta,
  }) : super(key: key);

  @override
  State<ChurnFotosScreen> createState() => _ChurnFotosScreenState();
}

class _ChurnFotosScreenState extends State<ChurnFotosScreen> {
  @override
  void initState() {
    super.initState();
    // Asegurar que el servicio esté en estado detectado
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final churnService = Provider.of<ChurnService>(context, listen: false);
      if (churnService.estado == EstadoChurn.idle) {
        churnService.detectarChurn();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📷 Fotos de Evidencia CHURN'),
        backgroundColor: Colors.orange,
      ),
      body: Consumer<ChurnService>(
        builder: (context, churnService, child) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Información
                Card(
                  color: Colors.orange.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Toma fotos de los equipos de la otra compañía',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'OT: ${widget.alerta.numeroOt}',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${churnService.fotosTomadas.length} foto${churnService.fotosTomadas.length != 1 ? 's' : ''} tomada${churnService.fotosTomadas.length != 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Grid de fotos tomadas
                Expanded(
                  child: churnService.fotosTomadas.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.camera_alt_outlined,
                                size: 80,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No hay fotos tomadas',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 0.75,
                          ),
                          itemCount: churnService.fotosTomadas.length,
                          itemBuilder: (context, index) {
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    churnService.fotosTomadas[index],
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Material(
                                    color: Colors.red,
                                    shape: const CircleBorder(),
                                    child: IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.white),
                                      onPressed: () {
                                        churnService.eliminarFoto(index);
                                      },
                                      iconSize: 20,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
                const SizedBox(height: 16),

                // Botones de acción
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: churnService.estado == EstadoChurn.capturandoFotos
                            ? null
                            : () async {
                                await churnService.tomarFoto();
                              },
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Tomar Foto'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: churnService.fotosTomadas.isEmpty ||
                                churnService.estado == EstadoChurn.enviandoACalidad
                            ? null
                            : () async {
                                // El servicio obtendrá automáticamente el nombre del técnico registrado
                                final ticketId = await churnService.enviarACalidad(
                                  ot: widget.alerta.numeroOt,
                                );

                                if (ticketId != null && mounted) {
                                  // Actualizar estado de la alerta a "en revisión de calidad"
                                  final alertasProvider = Provider.of<AlertasProvider>(context, listen: false);
                                  alertasProvider.actualizarEstadoAlerta(
                                    widget.alerta.id,
                                    EstadoAlerta.enRevisionCalidad,
                                  );
                                  
                                  // Navegar a pantalla de espera
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ChurnEsperaScreen(
                                        alerta: widget.alerta.copyWith(
                                          estado: EstadoAlerta.enRevisionCalidad,
                                        ),
                                        ticketId: ticketId,
                                      ),
                                    ),
                                  );
                                }
                              },
                        icon: const Icon(Icons.send),
                        label: const Text('Enviar a Calidad'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Pantalla de espera de validación de Calidad
class ChurnEsperaScreen extends StatefulWidget {
  final Alerta alerta;
  final String ticketId;

  const ChurnEsperaScreen({
    Key? key,
    required this.alerta,
    required this.ticketId,
  }) : super(key: key);

  @override
  State<ChurnEsperaScreen> createState() => _ChurnEsperaScreenState();
}

class _ChurnEsperaScreenState extends State<ChurnEsperaScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⏳ Esperando Validación'),
        backgroundColor: Colors.blue,
      ),
      body: Consumer<ChurnService>(
        builder: (context, churnService, child) {
          final minutos = churnService.tiempoRestanteSegundos ~/ 60;
          final segundos = churnService.tiempoRestanteSegundos % 60;

          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Spinner
                const CircularProgressIndicator(
                  strokeWidth: 4,
                ),
                const SizedBox(height: 32),

                // Título
                const Text(
                  'Enviando evidencia a Calidad...',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Timer countdown
                Text(
                  'Tiempo restante: ${minutos.toString().padLeft(2, '0')}:${segundos.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
                const SizedBox(height: 32),

                // Thumbnails de fotos enviadas
                if (churnService.fotosTomadas.isNotEmpty) ...[
                  const Text(
                    'Fotos enviadas:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: churnService.fotosTomadas.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              churnService.fotosTomadas[index],
                              width: 100,
                              height: 100,
                              fit: BoxFit.cover,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 32),
                ],

                // Estado actual
                _buildEstadoActual(churnService),

                const SizedBox(height: 32),

                // Botón cancelar (opcional)
                TextButton(
                  onPressed: () {
                    churnService.cancelar();
                    Navigator.pop(context);
                  },
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEstadoActual(ChurnService churnService) {
    switch (churnService.estado) {
      case EstadoChurn.esperandoValidacion:
        return const Text(
          'Esperando respuesta de Calidad...',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        );
      case EstadoChurn.aprobado:
        return Column(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 48),
            const SizedBox(height: 8),
            const Text(
              '✅ Calidad aprobó las fotos',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            if (churnService.comentarioCalidad != null) ...[
              const SizedBox(height: 8),
              Text(
                churnService.comentarioCalidad!,
                style: const TextStyle(fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                // Actualizar estado a regularizada si fue aprobado
                final alertasProvider = Provider.of<AlertasProvider>(context, listen: false);
                alertasProvider.actualizarEstadoAlerta(
                  widget.alerta.id,
                  EstadoAlerta.regularizada,
                );
                Navigator.pop(context);
              },
              child: const Text('Continuar'),
            ),
          ],
        );
      case EstadoChurn.rechazado:
        return Column(
          children: [
            const Icon(Icons.cancel, color: Colors.red, size: 48),
            const SizedBox(height: 8),
            const Text(
              '❌ Calidad rechazó las fotos',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            if (churnService.comentarioCalidad != null) ...[
              const SizedBox(height: 8),
              Text(
                churnService.comentarioCalidad!,
                style: const TextStyle(fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                churnService.reiniciarParaMasFotos();
                Navigator.pop(context);
              },
              child: const Text('Tomar Más Fotos'),
            ),
          ],
        );
      case EstadoChurn.timeout:
        return Column(
          children: [
            const Icon(Icons.access_time, color: Colors.orange, size: 48),
            const SizedBox(height: 8),
            const Text(
              '⏱️ Sin respuesta de Calidad',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Se escalará a supervisor',
              style: TextStyle(fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Aceptar'),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }
}


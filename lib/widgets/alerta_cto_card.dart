import 'package:flutter/material.dart';
import '../models/alerta_cto.dart';
import '../services/alertas_cto_service.dart';

class AlertaCTOCard extends StatelessWidget {
  final AlertaCTO alerta;
  final VoidCallback? onRefrescar;

  const AlertaCTOCard({
    super.key,
    required this.alerta,
    this.onRefrescar,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      elevation: 4,
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '🚨 ALERTA DESCONEXIÓN CTO',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade800,
                    ),
                  ),
                ),
                if (onRefrescar != null)
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.blue),
                    onPressed: onRefrescar,
                    tooltip: 'Refrescar estado vecinos',
                  ),
              ],
            ),

            const Divider(),

            // Info de la orden
            _buildInfoRow('OT', alerta.ot),
            _buildInfoRow('Actividad', alerta.actividad),
            _buildInfoRow('Inicio', alerta.inicio),
            _buildInfoRow('Ejecución', alerta.ejecucion),

            const SizedBox(height: 12),

            // Puertos con alerta
            Text(
              'PUERTOS CON PROBLEMAS:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 8),

            ...alerta.puertosConAlerta.map((puerto) => _buildPuertoAlerta(puerto)),

            const SizedBox(height: 12),

            // Tabla de potencias
            Text(
              'POTENCIAS:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),

            _buildTablaPotencias(),

            const SizedBox(height: 12),

            // Horarios de consulta
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  _buildInfoRow('Consulta inicial', alerta.horarioConsultaInicial),
                  _buildInfoRow('Consulta final', alerta.horarioConsultaFinal),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Botón ATENDER ALERTA
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final service = AlertasCTOService();
                  await service.atenderAlerta(alerta.ot, alerta.accessId);
                  
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('✅ Alerta ${alerta.ot} atendida - Notificaciones detenidas'),
                        backgroundColor: Colors.green,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                    
                    // Refrescar si hay callback
                    if (onRefrescar != null) {
                      onRefrescar!();
                    }
                  }
                },
                icon: const Icon(Icons.check_circle, color: Colors.white),
                label: const Text(
                  'ATENDER ALERTA',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
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

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPuertoAlerta(PuertoAlerta puerto) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.power_off, color: Colors.red, size: 20),
              const SizedBox(width: 8),
              Text(
                'Puerto ${puerto.portNumber}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (puerto.isCurrent)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'ACTUAL',
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Razón: ${puerto.alertReasons.join(", ")}',
            style: TextStyle(color: Colors.red.shade700),
          ),
          const SizedBox(height: 4),
          // Usar SingleChildScrollView para evitar overflow
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildPotenciaChip('Inicial', puerto.inicial, Colors.grey),
                const SizedBox(width: 8),
                _buildPotenciaChip('Final', puerto.finalValue, Colors.red),
                const SizedBox(width: 8),
                _buildPotenciaChip('Δ', puerto.difference, Colors.orange),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPotenciaChip(String label, double value, Color color) {
    final valorStr = value == 0.0 ? 'Sin señal' : '${value.toStringAsFixed(2)} dBm';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color),
      ),
      child: Text(
        '$label: $valorStr',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildTablaPotencias() {
    // ═══════════════════════════════════════════════════════
    // MOSTRAR TODOS LOS 8 PUERTOS (1-8), NO SOLO LOS CON DATOS
    // ═══════════════════════════════════════════════════════
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.grey.shade200,
            child: const Row(
              children: [
                Expanded(flex: 1, child: Text('Puerto', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                Expanded(flex: 2, child: Text('Inicial', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                Expanded(flex: 2, child: Text('Final', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              ],
            ),
          ),
          // Rows - Mostrar puertos 1-8 siempre
          ...List.generate(8, (index) {
            final portNumber = index + 1; // Puertos del 1 al 8
            
            // Buscar nivel inicial para este puerto
            final nivelInicial = alerta.nivelesInicial.firstWhere(
              (n) => n.portNumber == portNumber,
              orElse: () => NivelPuerto(
                portNumber: portNumber,
                portId: '',
                rxActual: 'N/A',
                status: '',
                isCurrent: false,
              ),
            );
            
            // Buscar nivel final para este puerto
            final nivelFinal = alerta.nivelesFinal.firstWhere(
              (n) => n.portNumber == portNumber,
              orElse: () => NivelPuerto(
                portNumber: portNumber,
                portId: '',
                rxActual: 'N/A',
                status: '',
                isCurrent: false,
              ),
            );

            final esAlerta = alerta.puertosConAlerta.any((p) => p.portNumber == portNumber);

            return Container(
              padding: const EdgeInsets.all(8),
              color: esAlerta ? Colors.red.shade50 : null,
              child: Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: Row(
                      children: [
                        Text('$portNumber', style: const TextStyle(fontSize: 12)),
                        if (nivelFinal.isCurrent)
                          const Text(' ★', style: TextStyle(color: Colors.blue, fontSize: 10)),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      nivelInicial.rxActual,
                      style: TextStyle(
                        fontSize: 11,
                        color: nivelInicial.rxActual == 'N/A' ? Colors.grey : null,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      nivelFinal.rxActual,
                      style: TextStyle(
                        fontSize: 11,
                        color: esAlerta ? Colors.red : (nivelFinal.rxActual == 'N/A' ? Colors.grey : null),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}




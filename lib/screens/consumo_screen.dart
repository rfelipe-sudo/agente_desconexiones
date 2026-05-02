import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/krp_consumo_service.dart';
import '../models/consumo_material.dart';
import 'finalizar_orden_screen.dart';

/// Pantalla de estadísticas de consumo de materiales
class ConsumoScreen extends StatefulWidget {
  const ConsumoScreen({super.key});

  @override
  State<ConsumoScreen> createState() => _ConsumoScreenState();
}

class _ConsumoScreenState extends State<ConsumoScreen> {
  // final _service = KrpConsumoService(); // PAUSADO
  
  bool _cargando = true;
  String? _rutTecnico;
  Map<String, dynamic> _estadisticas = {};
  // List<ConsumoMaterial> _historial = []; // PAUSADO
  List<Map<String, dynamic>> _historial = [];

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    try {
      setState(() => _cargando = true);

      // Obtener RUT del técnico
      final prefs = await SharedPreferences.getInstance();
      _rutTecnico = prefs.getString('rut_tecnico');

      if (_rutTecnico != null) {
        final now = DateTime.now();
        
        // CONSUMO PAUSADO - valores por defecto
        final stats = <String, dynamic>{};
        final historial = <Map<String, dynamic>>[];
        
        // // Cargar estadísticas del mes
        // final stats = await _service.obtenerEstadisticasMes(
        //   rutTecnico: _rutTecnico!,
        //   mes: now.month,
        //   anno: now.year,
        // );

        // // Cargar historial reciente
        // final historial = await _service.obtenerHistorialConsumos(
        //   rutTecnico: _rutTecnico!,
        //   limit: 10,
        // );

        setState(() {
          _estadisticas = stats;
          _historial = historial;
          _cargando = false;
        });
      } else {
        setState(() => _cargando = false);
      }
    } catch (e) {
      print('❌ Error cargando datos de consumo: $e');
      setState(() => _cargando = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando datos: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final nombreMes = _getNombreMes(now.month);
    final total = _estadisticas['total'] ?? 0;
    final porTipo = _estadisticas['por_tipo'] as Map<String, dynamic>? ?? {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Consumo Órdenes'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargarDatos,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargarDatos,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Card(
                      elevation: 4,
                      color: Colors.blue[700],
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Text(
                              'Consumo $nombreMes ${now.year}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '$total',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Text(
                              'Órdenes totales',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Distribución por tipo
                    const Text(
                      'Distribución por Tipo',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),

                    _buildTipoOrden(
                      icon: Icons.add_circle,
                      color: Colors.green,
                      tipo: 'Altas',
                      cantidad: '${porTipo['Alta'] ?? 0}',
                      porcentaje: _calcularPorcentaje(porTipo['Alta'] ?? 0, total),
                    ),
                    _buildTipoOrden(
                      icon: Icons.build,
                      color: Colors.orange,
                      tipo: 'Reparaciones',
                      cantidad: '${porTipo['Reparación'] ?? 0}',
                      porcentaje: _calcularPorcentaje(porTipo['Reparación'] ?? 0, total),
                    ),
                    _buildTipoOrden(
                      icon: Icons.swap_horiz,
                      color: Colors.purple,
                      tipo: 'Migraciones',
                      cantidad: '${porTipo['Migración'] ?? 0}',
                      porcentaje: _calcularPorcentaje(porTipo['Migración'] ?? 0, total),
                    ),
                    _buildTipoOrden(
                      icon: Icons.settings,
                      color: Colors.blue,
                      tipo: 'Modificaciones',
                      cantidad: '${porTipo['Modificación'] ?? 0}',
                      porcentaje: _calcularPorcentaje(porTipo['Modificación'] ?? 0, total),
                    ),

                    const SizedBox(height: 24),

                    // Historial reciente
                    if (_historial.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Historial Reciente',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          TextButton(
                            onPressed: () {
                              // TODO: Navegar a historial completo
                            },
                            child: const Text('Ver todo'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ..._historial.take(5).map((consumo) => _buildHistorialCard(consumo)),
                    ],

                    const SizedBox(height: 24),

                    // Botón para finalizar nueva orden
                    ElevatedButton.icon(
                      onPressed: _mostrarDialogoNuevaOrden,
                      icon: const Icon(Icons.add),
                      label: const Text('FINALIZAR NUEVA ORDEN'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.all(16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTipoOrden({
    required IconData icon,
    required Color color,
    required String tipo,
    required String cantidad,
    required String porcentaje,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.2),
          child: Icon(icon, color: color),
        ),
        title: Text(tipo),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              cantidad,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                porcentaje,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistorialCard(Map<String, dynamic> consumo) { // ConsumoMaterial consumo) {
    Color estadoColor = Colors.grey;
    final esConfirmado = consumo['esConfirmado'] == true;
    final esRechazado = consumo['esRechazado'] == true;
    
    if (esConfirmado) {
      estadoColor = Colors.green;
    } else if (esRechazado) {
      estadoColor = Colors.red;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          _getIconoTipo(consumo['tipoOrden'] ?? ''),
          color: _getColorTipo(consumo['tipoOrden'] ?? ''),
        ),
        title: Text('OT: ${consumo['ordenTrabajo'] ?? 'N/A'}'),
        subtitle: Text(
          '${consumo['tipoOrden'] ?? 'N/A'} • ${_formatearFecha(consumo['fechaConsumo'] ?? '')}\n'
          '${consumo['totalMateriales'] ?? 0} materiales consumidos',
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: estadoColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            (consumo['estado'] ?? 'PENDIENTE').toString().toUpperCase(),
            style: TextStyle(
              color: estadoColor,
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
        ),
        onTap: () {
          // TODO: Ver detalle del consumo
        },
      ),
    );
  }

  void _mostrarDialogoNuevaOrden() {
    final controllerOT = TextEditingController();
    String tipoOrden = 'Alta';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finalizar Nueva Orden'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controllerOT,
              decoration: const InputDecoration(
                labelText: 'Número de OT',
                hintText: 'Ej: 1-3EU0KT95',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: tipoOrden,
              decoration: const InputDecoration(
                labelText: 'Tipo de Orden',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Alta', child: Text('Alta')),
                DropdownMenuItem(value: 'Migración', child: Text('Migración')),
                DropdownMenuItem(value: 'Reparación', child: Text('Reparación')),
                DropdownMenuItem(value: 'Modificación', child: Text('Modificación')),
              ],
              onChanged: (value) {
                if (value != null) tipoOrden = value;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controllerOT.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Ingresa el número de OT')),
                );
                return;
              }

              Navigator.pop(context);

              // CONSUMO PAUSADO - Comentar navegación a FinalizarOrdenScreen
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Funcionalidad de consumo pausada temporalmente')),
              );
              
              // // Navegar a pantalla de finalización
              // final resultado = await Navigator.push<bool>(
              //   context,
              //   MaterialPageRoute(
              //     builder: (_) => FinalizarOrdenScreen(
              //       codigoOrden: controllerOT.text,
              //       tipoOrden: tipoOrden,
              //       rutTecnico: _rutTecnico ?? '',
              //     ),
              //   ),
              // );

              // // Si se finalizó exitosamente, recargar datos
              // if (resultado == true) {
              //   _cargarDatos();
              // }
            },
            child: const Text('CONTINUAR'),
          ),
        ],
      ),
    );
  }

  String _calcularPorcentaje(int cantidad, int total) {
    if (total == 0) return '0%';
    final porcentaje = (cantidad / total * 100).toStringAsFixed(0);
    return '$porcentaje%';
  }

  IconData _getIconoTipo(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'alta':
      case 'instalacion':
        return Icons.add_circle;
      case 'reparación':
      case 'reparacion':
        return Icons.build;
      case 'migración':
      case 'migracion':
        return Icons.swap_horiz;
      case 'modificación':
      case 'modificacion':
        return Icons.settings;
      default:
        return Icons.work;
    }
  }

  Color _getColorTipo(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'alta':
      case 'instalacion':
        return Colors.green;
      case 'reparación':
      case 'reparacion':
        return Colors.orange;
      case 'migración':
      case 'migracion':
        return Colors.purple;
      case 'modificación':
      case 'modificacion':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _formatearFecha(DateTime fecha) {
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = _getNombreMesCorto(fecha.month);
    final hora = fecha.hour.toString().padLeft(2, '0');
    final minuto = fecha.minute.toString().padLeft(2, '0');
    return '$dia $mes $hora:$minuto';
  }

  String _getNombreMes(int mes) {
    const meses = [
      '',
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre'
    ];
    return meses[mes];
  }

  String _getNombreMesCorto(int mes) {
    const meses = [
      '',
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic'
    ];
    return meses[mes];
  }
}














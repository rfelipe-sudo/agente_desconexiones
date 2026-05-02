import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'configuracion_screen.dart';

class BodegaScreen extends StatefulWidget {
  const BodegaScreen({super.key});

  @override
  State<BodegaScreen> createState() => _BodegaScreenState();
}

class _BodegaScreenState extends State<BodegaScreen> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _equiposPendientes = [];
  bool _cargando = true;
  int _totalPendientes = 0;
  String? _rolUsuario;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      _rolUsuario = prefs.getString('rol_usuario') ?? 'tecnico';

      if (_rolUsuario != 'bodeguero') {
        if (mounted) {
          setState(() {
            _equiposPendientes = [];
            _totalPendientes = 0;
            _cargando = false;
          });
        }
        return;
      }

      print('🔍 [Bodega] Consultando equipos en revisión...');
      
      final response = await supabase
          .from('equipos_reversa')
          .select()
          .eq('estado', 'en_revision')
          .order('fecha_entrega', ascending: true);

      print('🔍 [Bodega] Respuesta recibida: ${response.runtimeType}');
      print('🔍 [Bodega] Cantidad de equipos: ${(response as List).length}');
      
      if ((response as List).isNotEmpty) {
        print('🔍 [Bodega] Primer equipo: ${response.first}');
      } else {
        print('⚠️ [Bodega] No hay equipos en estado "en_revision"');
      }

      if (mounted) {
        final lista = List<Map<String, dynamic>>.from(response as List);
        setState(() {
          _equiposPendientes = lista;
          _totalPendientes = lista.length;
          _cargando = false;
        });
        
        print('✅ [Bodega] Estado actualizado: $_totalPendientes equipos');
      }
    } catch (e, stackTrace) {
      print('❌ [Bodega] Error al cargar datos: $e');
      print('❌ [Bodega] StackTrace: $stackTrace');
      
      if (mounted) {
        setState(() => _cargando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar datos: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _recibirOK(Map<String, dynamic> equipo) async {
    final serie = equipo['serial']?.toString() ?? 'equipo';
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Recepción'),
        content: Text('¿Recibir equipo $serie correctamente?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmado != true) return;

    try {
      final serial = equipo['serial'];
      if (serial == null) {
        throw Exception('Serial de equipo no encontrado');
      }

      await supabase
          .from('equipos_reversa')
          .update({
            'estado': 'recepcionado_ok',
            'fecha_recepcion': DateTime.now().toIso8601String(),
            'recibido_por': 'Bodeguero',
          })
          .eq('serial', serial);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Equipo recibido correctamente'),
            backgroundColor: Colors.green,
          ),
        );
        _cargarDatos();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error al recibir: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _rechazarEquipo(Map<String, dynamic> equipo) async {
    final motivoController = TextEditingController();
    String? motivoSeleccionado;

    final resultado = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Rechazar Equipo'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Selecciona un motivo o ingresa uno personalizado:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),
                // Opciones rápidas
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildMotivoChip(
                      'Serie no coincide',
                      motivoSeleccionado,
                      (value) => setDialogState(() {
                        motivoSeleccionado = value;
                        motivoController.text = value;
                      }),
                    ),
                    _buildMotivoChip(
                      'Equipo dañado',
                      motivoSeleccionado,
                      (value) => setDialogState(() {
                        motivoSeleccionado = value;
                        motivoController.text = value;
                      }),
                    ),
                    _buildMotivoChip(
                      'Falta equipo',
                      motivoSeleccionado,
                      (value) => setDialogState(() {
                        motivoSeleccionado = value;
                        motivoController.text = value;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: motivoController,
                  decoration: const InputDecoration(
                    labelText: 'Motivo de rechazo',
                    hintText: 'Ingresa el motivo...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  onChanged: (value) {
                    setDialogState(() {
                      motivoSeleccionado = null;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                final motivo = motivoController.text.trim();
                if (motivo.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Debes ingresar un motivo'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                Navigator.pop(context, {'motivo': motivo});
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Rechazar'),
            ),
          ],
        ),
      ),
    );

    if (resultado == null || resultado['motivo'] == null) return;

    try {
      final serial = equipo['serial'];
      if (serial == null) {
        throw Exception('Serial de equipo no encontrado');
      }

      await supabase
          .from('equipos_reversa')
          .update({
            'estado': 'rechazado',
            'fecha_recepcion': DateTime.now().toIso8601String(),
            'motivo_rechazo': resultado['motivo'],
          })
          .eq('serial', serial);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Equipo rechazado'),
            backgroundColor: Colors.orange,
          ),
        );
        _cargarDatos();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error al rechazar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildMotivoChip(String texto, String? seleccionado, Function(String) onTap) {
    final isSelected = seleccionado == texto;
    return InkWell(
      onTap: () => onTap(texto),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.red.withOpacity(0.2) : Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.red : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(
          texto,
          style: TextStyle(
            color: isSelected ? Colors.red : Colors.black87,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Future<void> _marcarEnRevision(Map<String, dynamic> equipo) async {
    final serie = equipo['serial']?.toString() ?? 'equipo';
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Marcar en Revisión'),
        content: Text('¿Marcar equipo $serie en revisión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black87,
            ),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmado != true) return;

    try {
      final serial = equipo['serial'];
      if (serial == null) {
        throw Exception('Serial de equipo no encontrado');
      }

      await supabase
          .from('equipos_reversa')
          .update({
            'estado': 'en_revision',
          })
          .eq('serial', serial);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⏳ Equipo marcado en revisión'),
            backgroundColor: Colors.amber,
          ),
        );
        _cargarDatos();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error al marcar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatearFecha(String? fecha) {
    if (fecha == null || fecha.isEmpty) return 'Sin fecha';
    try {
      final date = DateTime.parse(fecha);
      return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return fecha;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recepción Bodega'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ConfiguracionScreen()),
              );
              _cargarDatos();
            },
            tooltip: 'Configuración',
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _rolUsuario != 'bodeguero'
              ? _buildSoloBodegueros()
              : RefreshIndicator(
                  onRefresh: _cargarDatos,
                  color: Colors.indigo,
                  child: Column(
                    children: [
                      // Resumen
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.indigo.withOpacity(0.1),
                          border: Border(
                            bottom: BorderSide(
                              color: Colors.indigo.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.indigo.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.warehouse,
                                color: Colors.indigo,
                                size: 32,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _totalPendientes.toString(),
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _totalPendientes == 1
                                  ? 'Equipo pendiente de recibir'
                                  : 'Equipos pendientes de recibir',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Lista de equipos
                      Expanded(
                        child: _equiposPendientes.isEmpty
                            ? _buildSinDatos()
                            : ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: _equiposPendientes.length,
                                itemBuilder: (context, index) {
                                  final equipo = _equiposPendientes[index];
                                  return _buildEquipoCard(equipo);
                                },
                              ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSoloBodegueros() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.indigo.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warehouse,
                size: 64,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Solo para Bodegueros',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Esta pantalla es solo para bodegueros',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ConfiguracionScreen(),
                  ),
                );
                _cargarDatos();
              },
              icon: const Icon(Icons.settings),
              label: const Text('Ir a Configuración'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSinDatos() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No hay equipos pendientes de recepción',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Todos los equipos entregados han sido recibidos',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEquipoCard(Map<String, dynamic> equipo) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Serie (texto grande, monospace, negrita)
            Text(
              equipo['serial']?.toString() ?? 'Sin serie',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 8),
            // Tipo equipo
            Text(
              equipo['tipo_equipo']?.toString() ?? 'Sin tipo',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            // Información
            _buildInfoRow(
              Icons.person,
              'Técnico',
              equipo['tecnico_nombre']?.toString() ?? 'Sin técnico',
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              Icons.calendar_today,
              'Fecha Entrega',
              _formatearFecha(equipo['fecha_entrega']?.toString()),
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              Icons.work_outline,
              'Orden de Trabajo',
              equipo['ot']?.toString() ?? 'N/A',
            ),
            const SizedBox(height: 16),
            // Botones de acción
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _recibirOK(equipo),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('✓ OK'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _rechazarEquipo(equipo),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('✗ Rechazar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _marcarEnRevision(equipo),
                    icon: const Icon(Icons.hourglass_empty, size: 18),
                    label: const Text('⏳ Revisión'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}






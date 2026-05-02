import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'configuracion_screen.dart';
import '../services/reversa_service.dart';

class ReversaScreen extends StatefulWidget {
  const ReversaScreen({super.key});

  @override
  State<ReversaScreen> createState() => _ReversaScreenState();
}

class _ReversaScreenState extends State<ReversaScreen> {
  final supabase = Supabase.instance.client;
  final ReversaService _reversaService = ReversaService();

  List<Map<String, dynamic>> _desinstalaciones = [];
  bool _cargando = true;
  int _totalEquipos = 0;
  int _pendientes = 0;
  int _entregados = 0;
  int _enRevision = 0;
  int _rechazados = 0;
  int _recibidos = 0;
  String? _rutTecnico;
  String? _rolUsuario;
  String _filtroActual = 'todos'; // 'todos', 'pendiente_entrega', 'entregado', 'rechazado', 'en_revision', 'recepcionado_ok'
  int _mesOffset = 0; // 0 = mes actual, -1 = mes anterior, etc.
  final PageController _pageController = PageController(initialPage: 100);

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    print('🔄 [ReversaScreen] Cargando equipos...');
    setState(() => _cargando = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      _rutTecnico = prefs.getString('rut_tecnico');
      _rolUsuario = prefs.getString('rol_usuario') ?? 'tecnico';

      print('🔄 [ReversaScreen] RUT: $_rutTecnico');
      print('🔄 [ReversaScreen] Rol: $_rolUsuario');

      if (_rolUsuario != 'tecnico') {
        print('⚠️ [ReversaScreen] Usuario no es técnico, saliendo');
        if (mounted) {
          setState(() {
            _desinstalaciones = [];
            _totalEquipos = 0;
            _pendientes = 0;
            _entregados = 0;
            _cargando = false;
          });
        }
        return;
      }

      if (_rutTecnico == null || _rutTecnico!.isEmpty) {
        print('⚠️ [ReversaScreen] RUT no configurado');
        if (mounted) {
          setState(() {
            _desinstalaciones = [];
            _totalEquipos = 0;
            _pendientes = 0;
            _entregados = 0;
            _cargando = false;
          });
        }
        return;
      }

      // Calcular mes seleccionado
      final now = DateTime.now();
      final mesSeleccionado = DateTime(now.year, now.month + _mesOffset, 1);

      print('🔄 [ReversaScreen] Mes seleccionado: ${mesSeleccionado.month}/${mesSeleccionado.year}');

      final rut = _rutTecnico!; // Ya validado arriba que no es null

      // Obtener equipos usando el servicio
      print('🔄 [ReversaScreen] Llamando a obtenerEquiposReversa...');
      final lista = await _reversaService.obtenerEquiposReversa(
        rut,
        mes: mesSeleccionado.month,
        anno: mesSeleccionado.year,
      );

      print('🔄 [ReversaScreen] Equipos obtenidos: ${lista.length}');

      // Obtener resumen usando el servicio
      print('🔄 [ReversaScreen] Llamando a obtenerResumenReversaMes...');
      final resumen = await _reversaService.obtenerResumenReversaMes(
        rut,
        mes: mesSeleccionado.month,
        anno: mesSeleccionado.year,
      );

      print('🔄 [ReversaScreen] Resumen: $resumen');

      if (mounted) {
        setState(() {
          _desinstalaciones = lista;
          _totalEquipos = resumen['totalEquipos'] ?? 0;
          _pendientes = resumen['pendientes'] ?? 0;
          _entregados = resumen['entregados'] ?? 0;
          _enRevision = resumen['enRevision'] ?? 0;
          _rechazados = resumen['rechazados'] ?? 0;
          _recibidos = resumen['recibidos'] ?? 0;
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cargando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar datos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _reintentarEntrega(Map<String, dynamic> equipo) async {
    final serie = equipo['serial']?.toString() ?? 'equipo';
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reintentar Entrega'),
        content: Text('¿Volver a entregar el equipo $serie?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
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

      print('🔍 [Reversa] Reintentando entrega - Serial: $serial');

      // Actualizar usando el serial del equipo
      // Cambiar a 'en_revision' para que caiga al portal de bodega
      await supabase
          .from('equipos_reversa')
          .update({
            'estado': 'en_revision',
            'fecha_entrega': DateTime.now().toIso8601String(),
            'motivo_rechazo': null,
          })
          .eq('serial', serial);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Equipo enviado nuevamente a bodega'),
            backgroundColor: Colors.green,
          ),
        );
        _cargarDatos();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _entregarEquipo(Map<String, dynamic> equipo) async {
    final serie = equipo['serial']?.toString() ?? 'equipo';
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Entrega'),
        content: Text('¿Confirmas entrega del equipo $serie?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
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

      print('🔍 [Reversa] Serial: $serial');
      print('🔍 [Reversa] Estado actual: ${equipo['estado']}');
      print('🔍 [Reversa] equipo completo: $equipo');
      print('📤 [Reversa] Actualizando a estado "en_revision"...');

      // Actualizar usando el serial del equipo
      // Cambiar a 'en_revision' para que caiga al portal de bodega
      final response = await supabase
          .from('equipos_reversa')
          .update({
            'estado': 'en_revision',
            'fecha_entrega': DateTime.now().toIso8601String(),
          })
          .eq('serial', serial)
          .select();
      
      print('✅ [Reversa] Actualización exitosa: $response');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Equipo enviado a revisión de bodega'),
            backgroundColor: Colors.green,
          ),
        );
        // Refrescar lista
        _cargarDatos();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error al entregar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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

  String _formatearFecha(String? fecha) {
    if (fecha == null || fecha.isEmpty) return 'Sin fecha';
    try {
      final date = DateTime.parse(fecha);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return fecha;
    }
  }

  Color _getColorEstado(String? estado) {
    switch (estado) {
      case 'pendiente_entrega':
      case 'pendiente': // Compatibilidad con modelo EquipoReversa
        return Colors.orange;
      case 'entregado':
        return Colors.blue;
      case 'recepcionado_ok':
        return Colors.green;
      case 'rechazado':
        return Colors.red;
      case 'en_revision':
        return Colors.amber;
      default:
        return Colors.orange;
    }
  }

  String _getLabelEstado(String? estado) {
    switch (estado) {
      case 'pendiente_entrega':
      case 'pendiente': // Compatibilidad con modelo EquipoReversa
        return 'Pendiente';
      case 'entregado':
        return 'Entregado';
      case 'recepcionado_ok':
        return 'Recibido OK';
      case 'rechazado':
        return 'Rechazado';
      case 'en_revision':
        return 'En Revisión';
      default:
        return 'Pendiente';
    }
  }

  /// Getter para obtener equipos filtrados según el filtro actual
  List<Map<String, dynamic>> get _equiposFiltrados {
    if (_filtroActual == 'todos') {
      return _desinstalaciones.where((e) => e['estado'] != 'recepcionado_ok').toList();
    }
    return _desinstalaciones.where((e) => e['estado'] == _filtroActual).toList();
  }

  DateTime get _mesSeleccionado {
    final now = DateTime.now();
    return DateTime(now.year, now.month + _mesOffset, 1);
  }

  Color get _colorPrincipal {
    if (_mesOffset == 0) return Colors.deepOrange;
    if (_mesOffset < 0) return Colors.blue;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    final nombreMes = _getNombreMes(_mesSeleccionado.month);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Desinstalaciones'),
        backgroundColor: Colors.deepOrange,
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
          : _rolUsuario != 'tecnico'
              ? _buildSoloTecnicos()
              : _rutTecnico == null || _rutTecnico!.isEmpty
                  ? _buildSinRutConfigurado()
                  : PageView.builder(
                      controller: _pageController,
                      itemCount: 200, // 100 es el centro (mes actual), permite navegación completa
                      onPageChanged: (page) {
                        final newOffset = page - 100;
                        setState(() {
                          _mesOffset = newOffset;
                        });
                        _cargarDatos();
                      },
                      itemBuilder: (context, index) {
                        return RefreshIndicator(
                          onRefresh: _cargarDatos,
                          color: _colorPrincipal,
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: Column(
                              children: [
                                // Selector de mes
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  color: _colorPrincipal.withOpacity(0.1),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.chevron_left),
                                        onPressed: () {
                                          _pageController.previousPage(
                                            duration: const Duration(milliseconds: 300),
                                            curve: Curves.easeInOut,
                                          );
                                        },
                                      ),
                                      Text(
                                        '$nombreMes ${_mesSeleccionado.year}',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: _colorPrincipal,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.chevron_right,
                                          color: Colors.grey,
                                        ),
                                        onPressed: () {
                                          _pageController.nextPage(
                                            duration: const Duration(milliseconds: 300),
                                            curve: Curves.easeInOut,
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),

                                // Resumen con filtros clickeables
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.deepOrange.withOpacity(0.1),
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Colors.deepOrange.withOpacity(0.2),
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    child: Row(
                                      children: [
                                        _buildFiltroClickeable('todos', 'Todos', _totalEquipos - _recibidos, Colors.deepOrange),
                                        const SizedBox(width: 16),
                                        _buildFiltroClickeable('pendiente_entrega', 'Pendientes', _pendientes, Colors.orange),
                                        const SizedBox(width: 16),
                                        _buildFiltroClickeable('entregado', 'Entregados', _entregados, Colors.blue),
                                        const SizedBox(width: 16),
                                        _buildFiltroClickeable('en_revision', 'Revisión', _enRevision, Colors.amber),
                                        const SizedBox(width: 16),
                                        _buildFiltroClickeable('rechazado', 'Rechazados', _rechazados, Colors.red),
                                        const SizedBox(width: 16),
                                        _buildFiltroClickeable('recepcionado_ok', 'Historial', _recibidos, Colors.green),
                                      ],
                                    ),
                                  ),
                                ),

                                // Lista de equipos filtrados
                                ...(_equiposFiltrados.isEmpty
                                    ? [
                                        Padding(
                                          padding: const EdgeInsets.all(32),
                                          child: _buildSinDatos(),
                                        ),
                                      ]
                                    : _equiposFiltrados.map((equipo) => Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          child: _buildEquipoCard(equipo),
                                        )).toList()),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }

  Widget _buildSoloTecnicos() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.deepOrange.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.engineering,
                size: 64,
                color: Colors.deepOrange,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Solo para Técnicos',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Esta pantalla es solo para técnicos',
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
                backgroundColor: Colors.deepOrange,
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

  Widget _buildSinRutConfigurado() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.deepOrange.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.settings_outlined,
                size: 64,
                color: Colors.deepOrange,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'RUT no configurado',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Configura tu RUT en Configuración para ver tus desinstalaciones',
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
                backgroundColor: Colors.deepOrange,
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
            Icons.inventory_2_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No tienes desinstalaciones este mes',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Las desinstalaciones del mes aparecerán aquí cuando se registren',
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

  Widget _buildResumenItem(String label, String valor, Color color) {
    return Column(
      children: [
        Text(
          valor,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildFiltroClickeable(String filtro, String label, int cantidad, Color color) {
    final estaActivo = _filtroActual == filtro;
    return InkWell(
      onTap: () => setState(() => _filtroActual = filtro),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: estaActivo ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: estaActivo
              ? Border(
                  bottom: BorderSide(
                    color: color,
                    width: 3,
                  ),
                )
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              cantidad.toString(),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: estaActivo ? color : color.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: estaActivo ? color : Colors.grey[600],
                fontWeight: estaActivo ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEquipoCard(Map<String, dynamic> equipo) {
    final estado = equipo['estado']?.toString() ?? 'pendiente_entrega';
    final colorEstado = _getColorEstado(estado);
    final labelEstado = _getLabelEstado(estado);
    // Permitir entregar si está pendiente_entrega o pendiente (compatibilidad)
    final puedeEntregar = estado == 'pendiente_entrega' || estado == 'pendiente';
    
    print('🔍 [Reversa] Equipo ${equipo['serial']}: estado="$estado", puedeEntregar=$puedeEntregar');

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
            // Header con serie y chip de estado
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        equipo['serial']?.toString() ?? 'Sin serie',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        equipo['tipo_equipo']?.toString() ?? 'Sin tipo',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
                Chip(
                  label: Text(
                    labelEstado,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  backgroundColor: colorEstado,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            // Información adicional
            _buildInfoRow(
              Icons.work_outline,
              'Orden de Trabajo',
              equipo['ot']?.toString() ?? 'N/A',
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              Icons.calendar_today,
              'Fecha de Desinstalación',
              _formatearFecha(equipo['fecha_desinstalacion']?.toString()),
            ),
            if (equipo['fecha_proceso'] != null) ...[
              const SizedBox(height: 8),
              _buildInfoRow(
                Icons.access_time,
                'Fecha de Proceso',
                _formatearFecha(equipo['fecha_proceso']?.toString()),
              ),
            ],
            if (equipo['fecha_entrega'] != null) ...[
              const SizedBox(height: 8),
              _buildInfoRow(
                Icons.check_circle,
                'Fecha de Entrega',
                _formatearFecha(equipo['fecha_entrega']?.toString()),
              ),
            ],
            // Información adicional para equipos recibidos
            if (estado == 'recepcionado_ok') ...[
              if (equipo['fecha_recepcion'] != null) ...[
                const SizedBox(height: 8),
                _buildInfoRow(
                  Icons.inventory,
                  'Fecha de Recepción',
                  _formatearFecha(equipo['fecha_recepcion']?.toString()),
                ),
              ],
              if (equipo['recibido_por'] != null) ...[
                const SizedBox(height: 8),
                _buildInfoRow(
                  Icons.person,
                  'Recibido por',
                  equipo['recibido_por']?.toString() ?? 'N/A',
                ),
              ],
            ],
            // Botones de acción (no mostrar para equipos recibidos)
            if (estado != 'recepcionado_ok') ...[
              // Mostrar motivo de rechazo y botón de reintentar si está rechazado
              if (estado == 'rechazado') ...[
                // Mostrar motivo de rechazo si existe
                if (equipo['motivo_rechazo'] != null && equipo['motivo_rechazo'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Motivo: ${equipo['motivo_rechazo']}',
                      style: TextStyle(color: Colors.red[300], fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _reintentarEntrega(equipo),
                    icon: const Icon(Icons.refresh),
                    label: const Text('REINTENTAR ENTREGA'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
              // Botón entregar solo si está pendiente
              if (puedeEntregar) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _entregarEquipo(equipo),
                    icon: const Icon(Icons.send),
                    label: const Text('ENTREGAR'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ],
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

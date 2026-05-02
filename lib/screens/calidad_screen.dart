import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/produccion_service.dart';
import '../models/calidad_tecnico.dart';

class CalidadScreen extends StatefulWidget {
  const CalidadScreen({super.key});

  @override
  State<CalidadScreen> createState() => _CalidadScreenState();
}

class _CalidadScreenState extends State<CalidadScreen> {
  final ProduccionService _service = ProduccionService();
  Map<String, dynamic>? _calidadData;
  List<DetalleReiterado> _detalleReiterados = [];
  bool _cargando = true;
  String? _tecnicoRut;
  int _periodoOffset = 0; // 0 = período actual, -1 = anterior, etc.
  final PageController _pageController = PageController(initialPage: 100);

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String get _periodoSeleccionado {
    final now = DateTime.now();
    // Mes de pago = mes calendario actual (misma regla que Producción “cerrado” en Tu Mes).
    String periodoBase = _service.getPeriodoMesPagoProduccionCerrado();

    // Aplicar offset para navegar entre períodos
    if (_periodoOffset != 0) {
      final partes = periodoBase.split('-');
      if (partes.length == 2) {
        final anno = int.tryParse(partes[0]) ?? now.year;
        final mes = int.tryParse(partes[1]) ?? now.month;
        final fecha = DateTime(anno, mes + _periodoOffset, 1);
        return _service.getPeriodoDesdeMesAnno(fecha.month, fecha.year);
      }
    }
    
    return periodoBase;
  }

  Color get _colorPrincipal {
    return _periodoOffset == 0 ? Colors.amber[700]! : Colors.blue[700]!;
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);

    final prefs = await SharedPreferences.getInstance();
    _tecnicoRut = prefs.getString('rut_tecnico');

    if (_tecnicoRut != null) {
      final displayPeriodo = _periodoSeleccionado;

      // Cada período consulta su propio bloque en calidad_api_crea:
      // "2026-03" → periodo="03-2026" (trabajo feb), "2026-04" → "04-2026" (trabajo mar)
      _calidadData = await _service.obtenerCalidadPorPeriodo(
        _tecnicoRut!,
        displayPeriodo,
      );

      // Cargar detalle desde calidad_crea.
      // Estrategia:
      // 1. Traer TODOS los registros del técnico (sin filtro de período para evitar
      //    problemas de formato de campos).
      // 2. Filtrar en cliente usando los números de orden de calidad_api_crea,
      //    comparando contra orden_original Y orden_reiterada (no sabemos cuál coincide).
      // 3. Si sigue vacío (ej. BONO ABR sin datos aún en calidad_crea),
      //    buscar en produccion_crea usando los mismos números de orden.
      _detalleReiterados = [];
      if (_calidadData != null) {
        final ordenes = (_calidadData!['ordenes_reiteradas'] as List<dynamic>?)
                ?.map((o) => o.toString())
                .toList() ??
            [];

        if (ordenes.isNotEmpty) {
          // Paso 1: traer todos los registros de calidad_crea del técnico
          final todosCalidad = await _service.obtenerDetalleReiterados(_tecnicoRut!);
          print('📋 [Debug] calidad_crea total registros del técnico: ${todosCalidad.length}');
          print('📋 [Debug] Órdenes de calidad_api_crea: $ordenes');

          // Paso 2: filtrar en cliente comparando ambos campos de orden
          final encontrados = todosCalidad.where((d) {
            return ordenes.contains(d.ordenOriginal) ||
                ordenes.contains(d.ordenReiterada);
          }).toList();
          print('📋 [Debug] Coincidencias en calidad_crea: ${encontrados.length}');

          // Paso 3: órdenes que no aparecieron en calidad_crea → buscar en produccion_crea
          final ordenesYaEncontradas = <String>{
            for (final d in encontrados) ...[d.ordenOriginal, d.ordenReiterada],
          };
          final ordenesFaltantes = ordenes
              .where((o) => o.isNotEmpty && !ordenesYaEncontradas.contains(o))
              .toList();

          List<DetalleReiterado> desdeProduccion = [];
          if (ordenesFaltantes.isNotEmpty) {
            print('📋 [Debug] ${ordenesFaltantes.length} órdenes sin detalle → produccion_crea');
            desdeProduccion = await _service.obtenerDetalleDesdeProduccion(
              _tecnicoRut!,
              ordenesFaltantes,
            );
            print('📋 [Debug] Desde produccion_crea: ${desdeProduccion.length}');
          }

          _detalleReiterados = [...encontrados, ...desdeProduccion];
          print('✅ [Calidad] Total detalle: ${_detalleReiterados.length} / ${ordenes.length}');
        }
      }

      print('✅ [Calidad] Período: $displayPeriodo | Reiterados: ${_calidadData?['total_reiterados'] ?? 0} | Detalle: ${_detalleReiterados.length}');
    }

    setState(() => _cargando = false);
  }

  String _getNombreMesDesdePeriodo(String periodo) {
    try {
      final partes = periodo.split('-');
      if (partes.length == 2) {
        final mes = int.tryParse(partes[1]) ?? 0;
        // El período YA representa el mes del bono
        // Período 2025-11 → BONO NOV
        return _getNombreMes(mes);
      }
    } catch (e) {
      // Ignorar errores
    }
    return '';
  }

  String _getNombreMes(int mes) {
    const meses = ['', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
                   'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
    return meses[mes];
  }

  Color _getColorCalidad(double porcentaje) {
    if (porcentaje <= 4.0) return Colors.green;      // Excelente (≤ 4%)
    if (porcentaje <= 5.7) return Colors.orange;     // Regular (4.1% - 5.7%)
    return Colors.red;                                // Necesita mejorar (> 5.8%)
  }

  @override
  Widget build(BuildContext context) {
    final nombreMes = _getNombreMesDesdePeriodo(_periodoSeleccionado);
    final porcentaje = (_calidadData?['porcentaje_reiteracion'] as num?)?.toDouble() ?? 0.0;
    final totalReiterados = (_calidadData?['total_reiterados'] as num?)?.toInt() ?? 0;
    final totalCompletadas = (_calidadData?['total_completadas'] as num?)?.toInt() ?? 0;
    final promedioDias = (_calidadData?['promedio_dias'] as num?)?.toDouble() ?? 0.0;
    
    final colorCalidad = _getColorCalidad(porcentaje);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Calidad - $nombreMes',
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: _colorPrincipal,
        foregroundColor: Colors.white,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : PageView.builder(
              controller: _pageController,
              itemCount: 200, // 100 es el centro (período actual), permite navegación completa
              onPageChanged: (page) {
                final newOffset = page - 100; // 100 es el centro
                setState(() {
                  _periodoOffset = newOffset;
                });
                _cargarDatos();
              },
              itemBuilder: (context, index) {
                return RefreshIndicator(
              onRefresh: _cargarDatos,
                  color: _colorPrincipal,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                        // Header con resumen del período
                    Card(
                      elevation: 4,
                          color: colorCalidad,
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.all(20),
                            childrenPadding: const EdgeInsets.only(bottom: 16),
                            title: Column(
                          children: [
                                // Indicador de período con flechas
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                    IconButton(
                                      icon: const Icon(Icons.chevron_left, color: Colors.white),
                                      onPressed: () {
                                        _pageController.previousPage(
                                          duration: const Duration(milliseconds: 300),
                                          curve: Curves.easeInOut,
                                        );
                                      },
                                    ),
                                    Flexible(
                                      child: Text(
                                        '$nombreMes ${_periodoSeleccionado.split('-')[0]}',
                                        style: const TextStyle(color: Colors.white70, fontSize: 16),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.chevron_right,
                                        color: Colors.white,
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
                                const SizedBox(height: 8),
                                // Porcentaje de reiteración
                                Text(
                                  porcentaje > 0 
                                      ? '${porcentaje.toStringAsFixed(1)}%'
                                      : '0.0%',
                                  style: const TextStyle(
                                    fontSize: 48,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const Text(
                                  'Reiteración',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white70,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                // Fila de indicadores secundarios
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _buildMiniStat('Reiterados', '$totalReiterados'),
                                    _buildMiniStat('Completadas', '$totalCompletadas'),
                                    if (promedioDias > 0)
                                      _buildMiniStat('Promedio', '${promedioDias.toStringAsFixed(1)}d'),
                                  ],
                                ),
                              ],
                            ),
                            children: [
                              // Lista de reiterados dentro del ExpansionTile
                              if (_detalleReiterados.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    children: [
                                      const Icon(Icons.check_circle, size: 48, color: Colors.white70),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'No hay reiterados en este período',
                                        style: TextStyle(color: Colors.white70),
                                    textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                )
                              else
                                ..._detalleReiterados.map((detalle) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    child: Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.2),
                                          width: 1,
                                        ),
                                      ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                          // Fecha de instalación
                                          Row(
                                            children: [
                                              const Icon(Icons.calendar_today, size: 16, color: Colors.white70),
                                              const SizedBox(width: 8),
                                        Text(
                                                'Fecha de instalación: ${detalle.fechaOriginal}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          // Orden y fecha de reparación
                                        Row(
                                          children: [
                                              const Icon(Icons.refresh, size: 16, color: Colors.white70),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'Orden: ${detalle.ordenReiterada} - Fecha: ${detalle.fechaReiterada}',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          // Causa
                                          if (detalle.causa.isNotEmpty) ...[
                                            const SizedBox(height: 12),
                                            Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Icon(Icons.info_outline, size: 16, color: Colors.orange),
                                                const SizedBox(width: 8),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                      const Text(
                                                        'Causa:',
                                                        style: TextStyle(
                                                          color: Colors.white70,
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                  Text(
                                                        detalle.causa,
                                                        style: const TextStyle(
                                                          color: Colors.orange,
                                                          fontSize: 14,
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                      ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                          ],
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ],
                      ),
                    ),
                  ],
                ),
              ),
                );
              },
            ),
    );
  }

  Widget _buildMiniStat(String label, String valor) {
    return Column(
      children: [
        Text(
          valor,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildTipoChip(String label, int valor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Text(
        '$label: $valor',
        style: const TextStyle(
          color: Colors.blue,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildDetalleItem(String label, String valor, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.white70),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                valor,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

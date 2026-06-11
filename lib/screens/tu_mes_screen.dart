import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/produccion_service.dart';
import '../services/reversa_service.dart';
import '../constants/app_constants.dart';
import '../widgets/creaciones_loading.dart';
import '../widgets/flota_card.dart';
import 'calidad_screen.dart';
import 'calidad_detalle_screen.dart';
import 'produccion_screen.dart';
import 'consumo_screen.dart';
import 'reversa_screen.dart';
import 'configuracion_screen.dart';

class TuMesScreen extends StatefulWidget {
  const TuMesScreen({super.key});

  @override
  State<TuMesScreen> createState() => _TuMesScreenState();
}

class _TuMesScreenState extends State<TuMesScreen> {
  final ProduccionService _produccionService = ProduccionService();
  // final KrpConsumoService _consumoService = KrpConsumoService(); // PAUSADO

  int _equiposPendientes = 0;
  int _equiposPendientesReversa = 0;
  double _promedioRGU = 0.0;
  
  // Calidad - períodos
  Map<String, dynamic>? _calidadPagado;    // Bono pagado (mes anterior al cerrado)
  Map<String, dynamic>? _calidadCerrado;   // Periodo cerrado (a pago)
  Map<String, dynamic>? _calidadActual;
  Map<String, dynamic>? _calidadAnterior;
  String _periodoPagado  = '';
  String _periodoCerrado = '';
  String _periodoActual  = '';
  String _periodoAnterior = '';

  // Producción - períodos
  Map<String, dynamic>? _produccionPagado;     // Mes - 2 (bono pagado)
  Map<String, dynamic>? _produccionCerrado;    // Mes - 1 (cerrado)
  Map<String, dynamic>? _produccionActual;     // Mes 0 (en curso)
  
  // Consumo - períodos
  Map<String, dynamic>? _consumoCerrado;   // Mes anterior cerrado
  Map<String, dynamic>? _consumoActual;    // Mes actual en curso
  
  // Reversa - períodos
  Map<String, dynamic>? _reversaCerrado;   // Mes anterior cerrado
  Map<String, dynamic>? _reversaActual;    // Mes actual en curso
  
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);

    // Cargar equipos pendientes de reversa
    try {
      final prefs = await SharedPreferences.getInstance();
      final rut = prefs.getString('rut_tecnico');
      if (rut != null) {
        final pendientes = await Supabase.instance.client
            .from('desinstalaciones_crea')
            .select('id')
            .eq('rut_tecnico', rut)
            .inFilter('estado', ['pendiente_entrega', 'rechazado', 'en_revision']);
        _equiposPendientes = pendientes.length;
      } else {
        _equiposPendientes = 0;
      }
    } catch (e) {
      print('⚠️ [TuMes] Error cargando equipos pendientes: $e');
      _equiposPendientes = 0;
    }

    // Cargar equipos pendientes para el card de Reversa
    await _cargarEquiposPendientes();

    // Cargar promedio RGU del mes actual
    await _cargarPromedioRGU();

    // Cargar porcentaje de reiteración (calidad)
    await _cargarReiteracionCalidad();

    // Cargar estadísticas de consumo
    await _cargarEstadisticasConsumo();

    setState(() => _cargando = false);
  }

  Future<void> _cargarPromedioRGU() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rutTecnico = prefs.getString('rut_tecnico');
      
      if (rutTecnico != null) {
        final now = DateTime.now();
        
        // Producción en card: Bono pagado + Bono cerrado + Bono en curso.
        // Ej. hoy en mayo: Bono abr (med mar) | Bono may (med abr) | Bono jun (med may).
        final mesMedPagado  = DateTime(now.year, now.month - 2, 1);
        final mesMedCerrado = DateTime(now.year, now.month - 1, 1);
        final mesMedActual  = DateTime(now.year, now.month,     1);

        final resultados = await Future.wait([
          _produccionService.obtenerResumenMesRGU(
            rutTecnico, mes: mesMedPagado.month,  anno: mesMedPagado.year),
          _produccionService.obtenerResumenMesRGU(
            rutTecnico, mes: mesMedCerrado.month, anno: mesMedCerrado.year),
          _produccionService.obtenerResumenMesRGU(
            rutTecnico, mes: mesMedActual.month,  anno: mesMedActual.year),
        ]);

        setState(() {
          _produccionPagado  = resultados[0];
          _produccionCerrado = resultados[1];
          _produccionActual  = resultados[2];
          _promedioRGU = (resultados[2]['promedioRGU'] as num?)?.toDouble() ?? 0.0;
        });
      } else {
        setState(() {
          _produccionPagado  = null;
          _produccionCerrado = null;
          _produccionActual  = null;
          _promedioRGU = 0.0;
        });
      }
    } catch (e) {
      print('⚠️ [TuMes] Error cargando promedio RGU: $e');
      setState(() {
        _produccionPagado  = null;
        _produccionCerrado = null;
        _produccionActual  = null;
        _promedioRGU = 0.0;
      });
    }
  }

  Future<void> _cargarEquiposPendientes() async {
    final prefs = await SharedPreferences.getInstance();
    final rutTecnico = prefs.getString('rut_tecnico');
    if (rutTecnico == null) {
      setState(() {
        _equiposPendientesReversa = 0;
        _reversaCerrado = null;
        _reversaActual = null;
      });
      return;
    }

    try {
      // Usar el mismo servicio que reversa_screen.dart
      final reversaService = ReversaService();
      final now = DateTime.now();
      
      // Mes anterior cerrado
      final mesCerrado = now.month - 1 < 1 ? 12 : now.month - 1;
      final annoCerrado = now.month - 1 < 1 ? now.year - 1 : now.year;
      
      // Mes actual en curso
      final mesActual = now.month;
      final annoActual = now.year;
      
      final resumenCerrado = await reversaService.obtenerResumenReversaMes(
        rutTecnico,
        mes: mesCerrado,
        anno: annoCerrado,
      );
      
      final resumenActual = await reversaService.obtenerResumenReversaMes(
        rutTecnico,
        mes: mesActual,
        anno: annoActual,
      );

      // Calcular equipos pendientes del mes actual
      final totalEquipos = (resumenActual['totalEquipos'] ?? 0) as int;
      final recibidos = (resumenActual['recibidos'] ?? 0) as int;
      final equiposPendientes = totalEquipos - recibidos;

      print('📦 [TuMes] Equipos pendientes reversa: $equiposPendientes (Total:$totalEquipos, Recibidos:$recibidos)');

      setState(() {
        _reversaCerrado = resumenCerrado;
        _reversaActual = resumenActual;
        _equiposPendientesReversa = equiposPendientes;
      });
    } catch (e) {
      print('⚠️ [TuMes] Error cargando equipos pendientes reversa: $e');
      setState(() {
        _reversaCerrado = null;
        _reversaActual = null;
        _equiposPendientesReversa = 0;
      });
    }
  }

  Future<void> _cargarReiteracionCalidad() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rutTecnico = prefs.getString('rut_tecnico');
      
      if (rutTecnico != null) {
        final calidadPeriodos = await _produccionService.obtenerCalidadPeriodos(rutTecnico);
        
        setState(() {
          _calidadPagado   = calidadPeriodos['pagado']   as Map<String, dynamic>?;
          _calidadCerrado  = calidadPeriodos['cerrado']  as Map<String, dynamic>?;
          _calidadActual   = calidadPeriodos['actual']   as Map<String, dynamic>?;
          _calidadAnterior = calidadPeriodos['anterior'] as Map<String, dynamic>?;
          _periodoPagado   = calidadPeriodos['periodo_pagado']   as String? ?? '';
          _periodoCerrado  = calidadPeriodos['periodo_cerrado']  as String? ?? '';
          _periodoActual   = calidadPeriodos['periodo_actual']   as String? ?? '';
          _periodoAnterior = calidadPeriodos['periodo_anterior'] as String? ?? '';
        });
      } else {
        setState(() {
          _calidadPagado   = null;
          _calidadCerrado  = null;
          _calidadActual   = null;
          _calidadAnterior = null;
          _periodoPagado   = '';
          _periodoCerrado  = '';
          _periodoActual   = '';
          _periodoAnterior = '';
        });
      }
    } catch (e) {
      print('⚠️ [TuMes] Error cargando calidad: $e');
      setState(() {
        _calidadPagado   = null;
        _calidadCerrado  = null;
        _calidadActual   = null;
        _calidadAnterior = null;
        _periodoPagado   = '';
        _periodoCerrado  = '';
        _periodoActual   = '';
        _periodoAnterior = '';
      });
    }
  }

  Future<void> _cargarEstadisticasConsumo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rutTecnico = prefs.getString('rut_tecnico');
      
      if (rutTecnico != null) {
        final now = DateTime.now();
        
        // Mes anterior cerrado
        final mesCerrado = now.month - 1 < 1 ? 12 : now.month - 1;
        final annoCerrado = now.month - 1 < 1 ? now.year - 1 : now.year;
        
        // Mes actual en curso
        final mesActual = now.month;
        final annoActual = now.year;
        
        // CONSUMO PAUSADO - valores por defecto
        final estadisticasCerrado = {'totalPendientes': 0, 'detalles': {}};
        final estadisticasActual = {'totalPendientes': 0, 'detalles': {}};
        
        // final estadisticasCerrado = await _consumoService.obtenerEstadisticasMes(
        //   rutTecnico: rutTecnico,
        //   mes: mesCerrado,
        //   anno: annoCerrado,
        // );
        // 
        // final estadisticasActual = await _consumoService.obtenerEstadisticasMes(
        //   rutTecnico: rutTecnico,
        //   mes: mesActual,
        //   anno: annoActual,
        // );
        
        setState(() {
          _consumoCerrado = estadisticasCerrado;
          _consumoActual = estadisticasActual;
        });
      } else {
        setState(() {
          _consumoCerrado = null;
          _consumoActual = null;
        });
      }
    } catch (e) {
      print('⚠️ [TuMes] Error cargando consumo: $e');
      setState(() {
        _consumoCerrado = null;
        _consumoActual = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final nombreMes = _getNombreMes(now.month);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tu Mes'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ConfiguracionScreen(),
              ),
            ),
            tooltip: 'Configuración',
          ),
        ],
      ),
      body: _cargando
          ? const CreacionesLoading(
              mensaje: 'Cargando tu resumen del mes...',
            )
          : RefreshIndicator(
              onRefresh: _cargarDatos,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Título del mes
                    Text(
                      '$nombreMes ${now.year}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (AppConstants.modulosHerramientasProximamente)
                      _buildFlotaProximamenteCard()
                    else
                      const FlotaCard(),

                    const SizedBox(height: 12),

                    // Card Calidad
                    _buildCardCalidadCompleto(),

                    const SizedBox(height: 12),

                    // Card Producción completo con dos períodos
                    _buildCardProduccionCompleto(),

                    const SizedBox(height: 12),

                    // Card Consumo completo con dos períodos
                    _buildCardConsumoCompleto(),

                    const SizedBox(height: 12),

                    // Card Reversa completo con dos períodos
                    _buildCardReversaCompleto(),
                  ],
                ),
              ),
            ),
    );
  }

  /// Flota desactivada temporalmente (misma bandera que herramientas en home).
  Widget _buildFlotaProximamenteCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.local_shipping, color: Colors.grey[600], size: 26),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Flota',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Próximamente',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF8FA8C8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Widget para mostrar el card de calidad completo con tres períodos
  Widget _buildCardCalidadCompleto() {
    final now = DateTime.now();

    if (_calidadPagado == null && _calidadCerrado == null && _calidadActual == null) {
      return Card(
        elevation: 2,
        child: InkWell(
                      onTap: () => Navigator.push(
                        context,
            MaterialPageRoute(builder: (_) => const CalidadDetalleScreen()),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star, color: Colors.amber),
                  const SizedBox(width: 8),
                  const Text(
                    'Calidad - Sin datos',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    
    // ── Bono Pagado (mes -2 medición, mes -1 pago) ──────────────────────────
    final porcentajePagado  = (_calidadPagado?['porcentaje_reiteracion']  as num?)?.toDouble() ?? 0.0;
    final reiteradosPagado  = (_calidadPagado?['total_reiterados']  as num?)?.toInt() ?? 0;
    final completadasPagado = (_calidadPagado?['total_completadas'] as num?)?.toInt() ?? 0;
    final pPagadoDt = DateTime(now.year, now.month - 1, 1);
    final nombreMesPagado = _getNombreMes(pPagadoDt.month);
    final colorPagado = _getColorCalidad(porcentajePagado);

    // ── Bono Cerrado (mes -1 medición, mes actual pago) ──────────────────────
    final porcentajeCerrado  = (_calidadCerrado?['porcentaje_reiteracion']  as num?)?.toDouble() ?? 0.0;
    final reiteradosCerrado  = (_calidadCerrado?['total_reiterados']  as num?)?.toInt() ?? 0;
    final completadasCerrado = (_calidadCerrado?['total_completadas'] as num?)?.toInt() ?? 0;
    final periodoCerrado = _calidadCerrado?['periodo']?.toString() ?? '';
    String nombreMesCerrado = '';
    int mesGarantiaCerrado = now.month - 1;
    int annoGarantiaCerrado = now.year;
    if (periodoCerrado.isNotEmpty) {
      final partes = periodoCerrado.split('-');
      if (partes.length == 2) {
        final mes = int.parse(partes[1]);
        annoGarantiaCerrado = int.parse(partes[0]);
        nombreMesCerrado = _getNombreMes(mes);
        mesGarantiaCerrado = mes;
      }
    }
    final colorCerrado = _getColorCalidad(porcentajeCerrado);

    // ── Bono en Curso (mes actual medición, mes +1 pago) ─────────────────────
    final porcentajeActual  = (_calidadActual?['porcentaje_reiteracion']  as num?)?.toDouble() ?? 0.0;
    final reiteradosActual  = (_calidadActual?['total_reiterados']  as num?)?.toInt() ?? 0;
    final completadasActual = (_calidadActual?['total_completadas'] as num?)?.toInt() ?? 0;
    final periodoActual = _calidadActual?['periodo']?.toString() ?? '';
    String nombreMesActual = '';
    int mesGarantiaActual = now.month;
    int annoGarantiaActual = now.year;
    if (periodoActual.isNotEmpty) {
      final partes = periodoActual.split('-');
      if (partes.length == 2) {
        final mes = int.parse(partes[1]);
        annoGarantiaActual = int.parse(partes[0]);
        nombreMesActual = _getNombreMes(mes);
        mesGarantiaActual = mes;
      }
    }
    final colorActual = _getColorCalidad(porcentajeActual);
    int mesCierre = now.month; int annoCierre = now.year;
    if (periodoActual.isNotEmpty) {
      final partes = periodoActual.split('-');
      if (partes.length == 2) { mesCierre = int.parse(partes[1]); annoCierre = int.parse(partes[0]); }
    }
    final fechaCierre = DateTime(annoCierre, mesCierre + 1, 0);
    final diasRestantes = fechaCierre.difference(now).inDays;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header centrado
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star, color: Colors.amber),
                  const SizedBox(width: 8),
                  const Text(
                    'Calidad',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Tres columnas
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── COL 1: BONO PAGADO ──────────────────────────────────
                  Expanded(
                    child: InkWell(
                      onTap: () => _mostrarDetalleCalidad(context, _calidadPagado, _periodoPagado),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey[900],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Icon(Icons.check_circle_outline, size: 12, color: Colors.white54),
                              const SizedBox(width: 3),
                              Expanded(child: Text(
                                'BONO ${nombreMesPagado.toUpperCase()}',
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              )),
                            ]),
                            const SizedBox(height: 2),
                            Text(
                              _getRangoTrabajoBono(pPagadoDt.month, pPagadoDt.year),
                              style: const TextStyle(fontSize: 8, color: Colors.white54),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${porcentajePagado.toStringAsFixed(1)}%',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorPagado),
                            ),
                            Text('$reiteradosPagado / $completadasPagado',
                                style: const TextStyle(fontSize: 10, color: Colors.white54)),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey[700],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('Pagado', style: TextStyle(fontSize: 8, color: Colors.white70)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // ── COL 2: BONO CERRADO ─────────────────────────────────
                  Expanded(
                    child: InkWell(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CalidadDetalleScreen())),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey[850],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Icon(Icons.lock, size: 12, color: Colors.white),
                              const SizedBox(width: 3),
                              Expanded(child: Text(
                                'BONO ${nombreMesCerrado.toUpperCase()}',
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              )),
                            ]),
                            const SizedBox(height: 2),
                            Text(
                              _getRangoTrabajoBono(mesGarantiaCerrado, annoGarantiaCerrado),
                              style: const TextStyle(fontSize: 8, color: Colors.white70),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${porcentajeCerrado.toStringAsFixed(1)}%',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorCerrado),
                            ),
                            Text('$reiteradosCerrado / $completadasCerrado',
                                style: const TextStyle(fontSize: 10, color: Colors.white70)),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(4)),
                              child: const Text('Cerrado', style: TextStyle(fontSize: 8, color: Colors.white70)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // ── COL 3: BONO EN CURSO ────────────────────────────────
                  Expanded(
                    child: InkWell(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CalidadDetalleScreen())),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.15),
                          border: Border.all(color: Colors.green, width: 1.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Icon(Icons.hourglass_empty, size: 12, color: Colors.white),
                              const SizedBox(width: 3),
                              Expanded(child: Text(
                                'BONO ${nombreMesActual.toUpperCase()}',
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              )),
                            ]),
                            const SizedBox(height: 2),
                            Text(
                              _getRangoTrabajoBono(mesGarantiaActual, annoGarantiaActual),
                              style: const TextStyle(fontSize: 8, color: Colors.white70),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${porcentajeActual.toStringAsFixed(1)}%',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorActual),
                            ),
                            Text('$reiteradosActual / $completadasActual',
                                style: const TextStyle(fontSize: 10, color: Colors.white70)),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(4)),
                              child: Text('Cierra en $diasRestantes d',
                                  style: const TextStyle(fontSize: 8, color: Colors.white)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
              ),
            ),
    );
  }
  
  Color _getColorCalidad(double porcentaje) {
    if (porcentaje <= 3.0) {
      return Colors.green;
    } else if (porcentaje <= 6.0) {
      return Colors.lightGreen;
    } else if (porcentaje <= 10.0) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }

  Widget _buildMenuCard({
    required IconData icon,
    required Color color,
    required String titulo,
    required String valor,
    required String subtitulo,
    Color? subtituloColor,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    Text(
                      valor,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    Text(
                      subtitulo,
                      style: TextStyle(
                        fontSize: 12,
                        color: subtituloColor ?? Colors.grey[500],
                        fontWeight: subtituloColor != null ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCardReversa({
    required IconData icon,
    required Color color,
    required String titulo,
    required int equiposPendientes,
    required VoidCallback onTap,
  }) {
    final tienePendientes = equiposPendientes > 0;
    final colorValor = tienePendientes ? Colors.orange : Colors.green;
    
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    Text(
                      equiposPendientes.toString(),
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: colorValor,
                      ),
                    ),
                    Text(
                      tienePendientes ? 'equipos pendientes' : 'Sin pendientes',
                      style: TextStyle(
                        fontSize: 14,
                        color: colorValor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  String _getNombreMes(int mes) {
    const meses = ['', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
                   'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
    return meses[mes];
  }

  String _getNombreBonoPeriodo() {
    final ahora = DateTime.now();
    final mesActual = ahora.month;
    // El bono actual es del mes siguiente al de garantía
    final nombreBono = _getNombreBonoMes(mesActual + 1, ahora.year);
    return nombreBono;
  }

  String _getNombreBonoPago() {
    // El bono a pago es el del mes en curso (medición: mes anterior, 1 al último día)
    final ahora = DateTime.now();
    final mesActual = ahora.month;
    final nombreBono = _getNombreBonoMes(mesActual, ahora.year);
    return nombreBono;
  }


  Color _getColorPosicionCalidad(int posicion) {
    if (posicion == 0) return Colors.grey;
    if (posicion == 1) return Colors.amber[700]!;  // Oro
    if (posicion == 2) return Colors.grey[400]!;   // Plata
    if (posicion == 3) return Colors.orange[700]!; // Bronce
    if (posicion <= 10) return Colors.green[700]!; // Top 10
    if (posicion <= 20) return Colors.blue[700]!;  // Top 20
    return Colors.grey[600]!;
  }

  IconData _getIconoPosicion(int posicion) {
    if (posicion <= 3) return Icons.emoji_events; // Trofeo
    if (posicion <= 10) return Icons.star;        // Estrella
    return Icons.person;                           // Persona
  }

  String _getNombreMesCorto(String periodo) {
    try {
      final partes = periodo.split('-');
      if (partes.length == 2) {
        final mes = int.tryParse(partes[1]) ?? 0;
        const meses = ['', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
        if (mes >= 1 && mes <= 12) {
          return meses[mes];
        }
      }
    } catch (e) {
      // Ignorar errores
    }
    return '';
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

  Widget _buildMenuCardCalidad({
    required IconData icon,
    required Map<String, dynamic>? calidadActual,
    required Map<String, dynamic>? calidadAnterior,
    required String periodoActual,
    required String periodoAnterior,
  }) {
    // Calcular porcentajes y datos
    final porcentajeActual = (calidadActual?['porcentaje_reiteracion'] as num?)?.toDouble() ?? 0.0;
    final totalReiteradosActual = (calidadActual?['total_reiterados'] as num?)?.toInt() ?? 0;
    final totalCompletadasActual = (calidadActual?['total_completadas'] as num?)?.toInt() ?? 0;
    
    final porcentajeAnterior = (calidadAnterior?['porcentaje_reiteracion'] as num?)?.toDouble() ?? 0.0;
    final totalReiteradosAnterior = (calidadAnterior?['total_reiterados'] as num?)?.toInt() ?? 0;
    final totalCompletadasAnterior = (calidadAnterior?['total_completadas'] as num?)?.toInt() ?? 0;
    
    // Calcular períodos de trabajo y garantía
    final ahora = DateTime.now();
    final mesActualNum = ahora.month;
    final annoActual = ahora.year;
    
    // BONO ANTERIOR: mes anterior al actual (ej. hoy ABR → BONO MARZO, trabajo feb 1-28)
    // Período de pago cerrado = mes anterior; garantía venció último día del mes de pago.
    final mesBonoAnterior = mesActualNum - 1 < 1 ? 12 : mesActualNum - 1;
    final annoBonoAnterior = mesActualNum - 1 < 1 ? annoActual - 1 : annoActual;
    final nombreBonoAnterior = _getNombreBonoMes(mesBonoAnterior, annoBonoAnterior);
    final periodoTrabajoAnterior = _getPeriodoTrabajo(mesBonoAnterior, annoBonoAnterior);
    final mesGarantiaAnterior = _getMesAbrev(mesBonoAnterior);
    final diaFinGarantiaAnterior =
        DateTime(annoBonoAnterior, mesBonoAnterior + 1, 0).day;
    final fechaCierreAnterior = DateTime(annoBonoAnterior, mesBonoAnterior + 1, 0);
    final cerradoAnterior = ahora.isAfter(fechaCierreAnterior);
    final diasRestantesAnterior = cerradoAnterior ? 0 : fechaCierreAnterior.difference(ahora).inDays;

    // BONO ACTUAL: mes en curso (ej. hoy ABR → BONO ABRIL, trabajo mar 1-31)
    // Garantía vence el último día del mes de pago.
    final nombreBonoActual = _getNombreBonoMes(mesActualNum, annoActual);
    final periodoTrabajoActual = _getPeriodoTrabajo(mesActualNum, annoActual);
    final mesGarantiaActual = _getMesAbrev(mesActualNum);
    final diaFinGarantiaActual = DateTime(annoActual, mesActualNum + 1, 0).day;
    final fechaCierreActual = DateTime(annoActual, mesActualNum + 1, 0);
    final cerradoActual = ahora.isAfter(fechaCierreActual);
    final diasRestantesActual = cerradoActual ? 0 : fechaCierreActual.difference(ahora).inDays;
    
    final colorActual = _getColorCalidad(porcentajeActual);
    final colorAnterior = _getColorCalidad(porcentajeAnterior);
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header centrado
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.star, color: Colors.amber, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Calidad',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Dos bonos lado a lado (uniformes)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                // BONO ANTERIOR (cerrado)
                Expanded(
                  child: _buildBonoCard(
                    titulo: cerradoAnterior ? '🔒 $nombreBonoAnterior' : '⏳ $nombreBonoAnterior',
                    subtitulo: cerradoAnterior ? '(cerrado)' : '(midiendo)',
                    periodoTrabajo: periodoTrabajoAnterior,
                    mesGarantia: mesGarantiaAnterior,
                    diaFinGarantia: diaFinGarantiaAnterior,
                    porcentaje: porcentajeAnterior,
                    reiterados: totalReiteradosAnterior,
                    completadas: totalCompletadasAnterior,
                    color: colorAnterior,
                    diasRestantes: cerradoAnterior ? null : diasRestantesAnterior,
                    onTap: () => _mostrarDetalleCalidad(context, calidadAnterior, periodoAnterior),
                  ),
                ),
                const SizedBox(width: 10),
                
                // BONO ACTUAL (midiendo)
                Expanded(
                  child: _buildBonoCard(
                    titulo: '⏳ $nombreBonoActual',
                    subtitulo: '(midiendo)',
                    periodoTrabajo: periodoTrabajoActual,
                    mesGarantia: mesGarantiaActual,
                    diaFinGarantia: diaFinGarantiaActual,
                    porcentaje: porcentajeActual,
                    reiterados: totalReiteradosActual,
                    completadas: totalCompletadasActual,
                    color: colorActual,
                    diasRestantes: diasRestantesActual,
                    onTap: () => _mostrarDetalleCalidad(context, calidadActual, periodoActual),
                  ),
                ),
              ],
            ),
          ),
          ],
        ),
      ),
    );
  }

  Widget _buildBonoCard({
    required String titulo,
    required String subtitulo,
    required String periodoTrabajo,
    required String mesGarantia,
    required int diaFinGarantia,
    required double porcentaje,
    required int reiterados,
    required int completadas,
    required Color color,
    required int? diasRestantes,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Título con emoji
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            Text(
              subtitulo,
              style: TextStyle(
                fontSize: 9,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            
            // Período de trabajo
            Text(
              periodoTrabajo,
              style: TextStyle(
                fontSize: 9,
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            
            // Último día garantía (último día del mes de pago)
            Text(
              'Última garantía\n$diaFinGarantia de $mesGarantia',
              style: TextStyle(
                fontSize: 8,
                color: Colors.grey[600],
                height: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            
            // Porcentaje y números
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                children: [
                  Text(
                    '${porcentaje.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$reiterados / $completadas',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            
            // Días restantes (solo si está activo)
            if (diasRestantes != null) ...[
              const SizedBox(height: 8),
              Text(
                'Cierra en $diasRestantes días',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Retorna el rango de trabajo para un BONO dado el mes/año de pago.
  /// BONO MARZO (mes=3, anno=2026) → "01/feb - 28/feb"
  String _getRangoTrabajoBono(int mesPago, int annoPago) {
    final mesTrabajo = DateTime(annoPago, mesPago - 1, 1);
    final ultimoDia = DateTime(mesTrabajo.year, mesTrabajo.month + 1, 0).day;
    final abrev = _getMesAbrev(mesTrabajo.month);
    return '01/$abrev - $ultimoDia/$abrev';
  }

  String _getNombreBonoMes(int mes, int anno) {
    // Ajustar si el mes es > 12 o < 1
    int mesAjustado = mes;
    if (mes > 12) mesAjustado = mes - 12;
    if (mes < 1) mesAjustado = 12 + mes;
    
    const meses = ['', 'ENE', 'FEB', 'MAR', 'ABR', 
                   'MAY', 'JUN', 'JUL', 'AGO',
                   'SEP', 'OCT', 'NOV', 'DIC'];
    return mesAjustado >= 1 && mesAjustado <= 12 ? 'BONO ${meses[mesAjustado]}' : 'BONO';
  }

  String _getPeriodoTrabajo(int mes, int anno) {
    // El trabajo se mide del 1 al último día del mes anterior al pago.
    // Ejemplo: BONO MARZO (mes=3, anno=2026) → trabajo 01/feb - 28/feb
    final mesTrabajo = DateTime(anno, mes - 1, 1);
    final ultimoDia = DateTime(mesTrabajo.year, mesTrabajo.month + 1, 0).day;
    final mesAbrev = _getMesAbrev(mesTrabajo.month);
    return '01/$mesAbrev - $ultimoDia/$mesAbrev';
  }

  String _getMesAbrev(int mes) {
    // Ajustar si el mes es > 12 o < 1
    int mesAjustado = mes;
    if (mes > 12) mesAjustado = mes - 12;
    if (mes < 1) mesAjustado = 12 + mes;
    
    const meses = ['', 'ene', 'feb', 'mar', 'abr', 'may', 'jun', 
                   'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    return mesAjustado >= 1 && mesAjustado <= 12 ? meses[mesAjustado] : '';
  }

  /// Widget para mostrar el card de producción completo con DOS períodos
  Widget _buildCardProduccionCompleto() {
    final now = DateTime.now();

    // ── Bono Pagado: medición mes -2, pago mes -1 ──────────────────────────
    final mesMedPag = DateTime(now.year, now.month - 2, 1);
    final mesPagPag = DateTime(now.year, now.month - 1, 1);
    final nombreBonoPagado          = _getNombreMes(mesPagPag.month);
    final nombreMesMedicionPagado   = _getNombreMes(mesMedPag.month);
    final diasMesMedicionPagado     = DateTime(mesMedPag.year, mesMedPag.month + 1, 0).day;
    final promedioRGUPagado         = (_produccionPagado?['promedioRGU'] as num?)?.toDouble() ?? 0.0;
    final totalRGUPagado            = (_produccionPagado?['totalRGU']    as num?)?.toInt()    ?? 0;

    // ── Bono Cerrado: medición mes -1, pago mes actual ─────────────────────
    final mesMedCer = DateTime(now.year, now.month - 1, 1);
    final mesPagCer = DateTime(now.year, now.month,     1);
    final nombreBonoCerrado         = _getNombreMes(mesPagCer.month);
    final nombreMesMedicionCerrado  = _getNombreMes(mesMedCer.month);
    final diasMesMedicionCerrado    = DateTime(mesMedCer.year, mesMedCer.month + 1, 0).day;
    final promedioRGUCerrado        = (_produccionCerrado?['promedioRGU'] as num?)?.toDouble() ?? 0.0;
    final totalRGUCerrado           = (_produccionCerrado?['totalRGU']    as num?)?.toInt()    ?? 0;

    // ── Bono en Curso: medición mes actual, pago mes +1 ───────────────────
    final mesMedAct = DateTime(now.year, now.month,     1);
    final mesPagAct = DateTime(now.year, now.month + 1, 1);
    final nombreBonoActual          = _getNombreMes(mesPagAct.month);
    final nombreMesMedicionActual   = _getNombreMes(mesMedAct.month);
    final diasMesMedicionActual     = DateTime(mesMedAct.year, mesMedAct.month + 1, 0).day;
    final diasRestantes             = diasMesMedicionActual - now.day;
    final promedioRGUActual         = (_produccionActual?['promedioRGU'] as num?)?.toDouble() ?? 0.0;
    final totalRGUActual            = (_produccionActual?['totalRGU']    as num?)?.toInt()    ?? 0;

    Color _colorRGU(double rgu) {
      if (rgu < 3) return Colors.red[700]!;
      if (rgu < 4.5) return Colors.orange[700]!;
      return Colors.green[700]!;
    }

    return Card(
      elevation: 2,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProduccionScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.trending_up, color: Colors.green[700]),
                    const SizedBox(width: 8),
                    const Text('Producción', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Tres columnas
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── COL 1: BONO PAGADO ────────────────────────────────
                    Expanded(
                      child: InkWell(
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => ProduccionScreen(mesInicial: mesMedPag))),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blueGrey[900],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                const Icon(Icons.check_circle_outline, size: 12, color: Colors.white54),
                                const SizedBox(width: 3),
                                Expanded(child: Text(
                                  'BONO ${nombreBonoPagado.toUpperCase()}',
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                  overflow: TextOverflow.ellipsis,
                                )),
                              ]),
                              const SizedBox(height: 3),
                              Text('01/$nombreMesMedicionPagado',
                                  style: const TextStyle(fontSize: 8, color: Colors.white38)),
                              Text('$diasMesMedicionPagado/$nombreMesMedicionPagado',
                                  style: const TextStyle(fontSize: 8, color: Colors.white38)),
                              const SizedBox(height: 6),
                              Text('RGU Prom: ${promedioRGUPagado.toStringAsFixed(1)}',
                                  style: const TextStyle(fontSize: 11, color: Colors.white)),
                              Text('RGU Total: $totalRGUPagado',
                                  style: TextStyle(fontSize: 10, color: Colors.green[300])),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                    color: Colors.blueGrey[700], borderRadius: BorderRadius.circular(4)),
                                child: const Text('Pagado', style: TextStyle(fontSize: 8, color: Colors.white70)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // ── COL 2: BONO CERRADO ───────────────────────────────
                    Expanded(
                      child: InkWell(
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => ProduccionScreen(mesInicial: mesMedCer))),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey[850],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                const Icon(Icons.lock, size: 12, color: Colors.white),
                                const SizedBox(width: 3),
                                Expanded(child: Text(
                                  'BONO ${nombreBonoCerrado.toUpperCase()}',
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                  overflow: TextOverflow.ellipsis,
                                )),
                              ]),
                              const SizedBox(height: 3),
                              Text('01/$nombreMesMedicionCerrado',
                                  style: TextStyle(fontSize: 8, color: Colors.grey[400])),
                              Text('$diasMesMedicionCerrado/$nombreMesMedicionCerrado',
                                  style: TextStyle(fontSize: 8, color: Colors.grey[400])),
                              const SizedBox(height: 6),
                              Text('RGU Prom: ${promedioRGUCerrado.toStringAsFixed(1)}',
                                  style: const TextStyle(fontSize: 11, color: Colors.white)),
                              Text('RGU Total: $totalRGUCerrado',
                                  style: TextStyle(fontSize: 10, color: Colors.green[300])),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                    color: Colors.grey[700], borderRadius: BorderRadius.circular(4)),
                                child: const Text('Cerrado', style: TextStyle(fontSize: 8, color: Colors.white70)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // ── COL 3: BONO EN CURSO ──────────────────────────────
                    Expanded(
                      child: InkWell(
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => ProduccionScreen(mesInicial: mesMedAct))),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _colorRGU(promedioRGUActual),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                const Icon(Icons.hourglass_empty, size: 12, color: Colors.white),
                                const SizedBox(width: 3),
                                Expanded(child: Text(
                                  'BONO ${nombreBonoActual.toUpperCase()}',
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                  overflow: TextOverflow.ellipsis,
                                )),
                              ]),
                              const SizedBox(height: 3),
                              Text('01/$nombreMesMedicionActual',
                                  style: const TextStyle(fontSize: 8, color: Colors.white70)),
                              Text('$diasMesMedicionActual/$nombreMesMedicionActual',
                                  style: const TextStyle(fontSize: 8, color: Colors.white70)),
                              const SizedBox(height: 6),
                              Text('RGU Prom: ${promedioRGUActual.toStringAsFixed(1)}',
                                  style: const TextStyle(fontSize: 11, color: Colors.white)),
                              Text('RGU Total: $totalRGUActual',
                                  style: const TextStyle(fontSize: 10, color: Colors.white)),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                    color: Colors.black45, borderRadius: BorderRadius.circular(4)),
                                child: Text('Cierra en $diasRestantes d',
                                    style: const TextStyle(fontSize: 8, color: Colors.white)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _mostrarDetalleCalidad(
    BuildContext context,
    Map<String, dynamic>? calidadData,
    String periodo,
  ) async {
    if (calidadData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay datos de calidad para este período')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final rutTecnico = prefs.getString('rut_tecnico');
    
    if (rutTecnico == null) return;

    // Cargar ranking de calidad
    final rankingCalidad = await _produccionService.obtenerPosicionCalidad(rutTecnico, periodo);
    
    // Cargar detalle de reiterados
    final detalleReiterados = await _produccionService.obtenerDetalleReiteradosPorPeriodo(
      rutTecnico,
      periodo,
    );

    final totalReiterados = (calidadData['total_reiterados'] as num?)?.toInt() ?? 0;
    final totalCompletadas = (calidadData['total_completadas'] as num?)?.toInt() ?? 0;
    final porcentaje = (calidadData['porcentaje_reiteracion'] as num?)?.toDouble() ?? 0.0;
    final promedioDias = (calidadData['promedio_dias'] as num?)?.toDouble() ?? 0.0;
    final nombreMes = _getNombreMesDesdePeriodo(periodo);
    
    final posicion = rankingCalidad['posicion'] ?? 0;
    final totalTecnicos = rankingCalidad['totalTecnicos'] ?? 0;

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _getColorCalidad(porcentaje).withOpacity(0.2),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.star, color: _getColorCalidad(porcentaje)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Reiterados - $nombreMes',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // Resumen y Ranking
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Ranking
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _getColorPosicionCalidad(posicion).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _getColorPosicionCalidad(posicion).withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _getIconoPosicion(posicion),
                            color: _getColorPosicionCalidad(posicion),
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Posición #$posicion de $totalTecnicos',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _getColorPosicionCalidad(posicion),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Estadísticas
                    Text(
                      '$totalReiterados reiterados de $totalCompletadas completadas (${porcentaje.toStringAsFixed(1)}%)',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (promedioDias > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Promedio: ${promedioDias.toStringAsFixed(1)} días',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
              Divider(height: 1, color: Colors.grey[700]),
              // Lista de reiterados
              Expanded(
                child: detalleReiterados.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No hay reiterados en este período',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: detalleReiterados.length,
                        itemBuilder: (context, index) {
                          final detalle = detalleReiterados[index];
                          final fechaOriginal = _produccionService.formatearFecha(
                            detalle['fecha_original']?.toString(),
                          );
                          final fechaReiterada = _produccionService.formatearFecha(
                            detalle['fecha_reiterada']?.toString(),
                          );
                          final ordenOriginal = detalle['orden_original']?.toString() ?? '';
                          final tipoActividad = detalle['tipo_actividad']?.toString() ?? '';
                          final causa = detalle['descripcion_reiterado']?.toString() ?? detalle['causa']?.toString() ?? '';
                          final codigoCierre = detalle['codigo_cierre_reiterado']?.toString() ?? '';
                          final cliente = detalle['cliente']?.toString() ?? '';
                          final diasReiterado = (detalle['dias_reiterado'] as num?)?.toInt() ?? 0;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey[700],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[600]!),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Fecha y tipo
                                Row(
                                  children: [
                                    const Icon(Icons.calendar_today, size: 16, color: Colors.white70),
                                    const SizedBox(width: 8),
                                    Text(
                                      fechaOriginal,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withOpacity(0.3),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        tipoActividad,
                                        style: const TextStyle(
                                          color: Colors.blue,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                // Orden en verde
                                Row(
                                  children: [
                                    const Icon(Icons.work_outline, size: 16, color: Colors.green),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Orden: ',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.white70,
                                      ),
                                    ),
                                    Text(
                                      ordenOriginal,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                                // Cliente
                                if (cliente.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.person, size: 16, color: Colors.white70),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          cliente,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                // Causa
                                if (causa.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.info_outline, size: 16, color: Colors.orange),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Causa: $causa',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Colors.orange,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                // Código de cierre
                                if (codigoCierre.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.build, size: 16, color: Colors.green),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Código: $codigoCierre',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Colors.green,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                // Días de reiteración
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.refresh, size: 16, color: Colors.orange),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Reiteró en $diasReiterado días ($fechaReiterada)',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.orange,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Widget para mostrar el card de Consumo completo con dos períodos
  Widget _buildCardConsumoCompleto() {
    final now = DateTime.now();
    
    // Período cerrado (mes anterior)
    final mesCerrado = now.month - 1 < 1 ? 12 : now.month - 1;
    final annoCerrado = now.month - 1 < 1 ? now.year - 1 : now.year;
    final nombreMesCerrado = _getNombreMes(mesCerrado);
    
    final totalCerrado = (_consumoCerrado?['total'] as int?) ?? 0;
    
    // Período actual (mes actual)
    final mesActual = now.month;
    final annoActual = now.year;
    final nombreMesActual = _getNombreMes(mesActual);
    final diasRestantes = DateTime(annoActual, mesActual + 1, 0).day - now.day;
    
    final totalActual = (_consumoActual?['total'] as int?) ?? 0;
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header centrado
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  const Text(
                    'Consumo Órdenes',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Dos columnas para los períodos
            IntrinsicHeight(
              child: Row(
                children: [
                  // IZQUIERDA: Período CERRADO
                  Expanded(
                    child: InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ConsumoScreen()),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[850],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Título
                            Row(
                              children: [
                                const Icon(Icons.lock, size: 14, color: Colors.white),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'PENDIENTES ${nombreMesCerrado.toUpperCase()}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Total
                            Text(
                              'Total: $totalCerrado',
                              style: const TextStyle(fontSize: 12, color: Colors.white),
                            ),
                            const SizedBox(height: 8),
                            // Estado
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey[700],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Periodo cerrado',
                                style: TextStyle(fontSize: 9, color: Colors.white70),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // DERECHA: Período ACTUAL
                  Expanded(
                    child: InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ConsumoScreen()),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          border: Border.all(color: Colors.green, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Título
                            Row(
                              children: [
                                const Icon(Icons.hourglass_empty, size: 14, color: Colors.white),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'PENDIENTES ${nombreMesActual.toUpperCase()}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Total
                            Text(
                              'Total: $totalActual',
                              style: const TextStyle(fontSize: 12, color: Colors.white),
                            ),
                            const SizedBox(height: 8),
                            // Estado
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Cierra en $diasRestantes días',
                                style: const TextStyle(fontSize: 9, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Widget para mostrar el card de Reversa completo con dos períodos
  Widget _buildCardReversaCompleto() {
    final now = DateTime.now();
    
    // Período cerrado (mes anterior)
    final mesCerrado = now.month - 1 < 1 ? 12 : now.month - 1;
    final annoCerrado = now.month - 1 < 1 ? now.year - 1 : now.year;
    final nombreMesCerrado = _getNombreMes(mesCerrado);
    
    final totalCerrado = (_reversaCerrado?['totalEquipos'] as int?) ?? 0;
    final pendientesCerrado = (_reversaCerrado?['pendientes'] as int?) ?? 0;
    final entregadosCerrado = (_reversaCerrado?['entregados'] as int?) ?? 0;
    
    // Período actual (mes actual)
    final mesActual = now.month;
    final annoActual = now.year;
    final nombreMesActual = _getNombreMes(mesActual);
    final diasRestantes = DateTime(annoActual, mesActual + 1, 0).day - now.day;
    
    final totalActual = (_reversaActual?['totalEquipos'] as int?) ?? 0;
    final pendientesActual = (_reversaActual?['pendientes'] as int?) ?? 0;
    final entregadosActual = (_reversaActual?['entregados'] as int?) ?? 0;
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header centrado
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inventory_2, color: Colors.deepOrange),
                  const SizedBox(width: 8),
                  const Text(
                    'Reversa',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Dos columnas para los períodos
            IntrinsicHeight(
              child: Row(
                children: [
                  // IZQUIERDA: Período CERRADO
                  Expanded(
                    child: InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ReversaScreen()),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[850],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Título
                            Row(
                              children: [
                                const Icon(Icons.lock, size: 14, color: Colors.white),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'PENDIENTES ${nombreMesCerrado.toUpperCase()}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Total
                            Text(
                              'Total: $totalCerrado',
                              style: const TextStyle(fontSize: 12, color: Colors.white),
                            ),
                            Text(
                              'Entregados: $entregadosCerrado',
                              style: TextStyle(fontSize: 11, color: Colors.green[300]),
                            ),
                            const SizedBox(height: 8),
                            // Estado
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey[700],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Periodo cerrado',
                                style: TextStyle(fontSize: 9, color: Colors.white70),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // DERECHA: Período ACTUAL
                  Expanded(
                    child: InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ReversaScreen()),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          border: Border.all(color: Colors.green, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Título
                            Row(
                              children: [
                                const Icon(Icons.hourglass_empty, size: 14, color: Colors.white),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'PENDIENTES ${nombreMesActual.toUpperCase()}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Total
                            Text(
                              'Total: $totalActual',
                              style: const TextStyle(fontSize: 12, color: Colors.white),
                            ),
                            Text(
                              'Pendientes: $pendientesActual',
                              style: TextStyle(
                                fontSize: 11,
                                color: pendientesActual > 0 ? Colors.red[300] : Colors.green[300],
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Estado
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Cierra en $diasRestantes días',
                                style: const TextStyle(fontSize: 9, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}








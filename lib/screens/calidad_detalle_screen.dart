import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/produccion_service.dart';
import '../widgets/creaciones_loading.dart';

class CalidadDetalleScreen extends StatefulWidget {
  const CalidadDetalleScreen({super.key});

  @override
  State<CalidadDetalleScreen> createState() => _CalidadDetalleScreenState();
}

class _CalidadDetalleScreenState extends State<CalidadDetalleScreen> {
  final ProduccionService _service = ProduccionService();
  
  bool _cargando = true;
  String? _tecnicoRut;
  Map<String, dynamic>? _calidadCerrado;
  Map<String, dynamic>? _calidadEnCurso;
  List<Map<String, dynamic>> _detalleCerrado = [];
  List<Map<String, dynamic>> _detalleEnCurso = [];
  /// Datos para el gráfico: `periodo`, `porcentaje`, `label`.
  List<Map<String, dynamic>> _graficoTresMeses = [];
  
  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }
  
  Future<void> _cargarDatos() async {
    final prefs = await SharedPreferences.getInstance();
    _tecnicoRut = prefs.getString('rut_tecnico');
    
    if (_tecnicoRut == null) {
      setState(() => _cargando = false);
      return;
    }
    
    try {
      // Misma regla que Tu Mes / Producción (no getPeriodoCerrado/Actual antiguos).
      final periodoCerrado = _service.getPeriodoMesPagoProduccionCerrado();
      final periodoEnCurso = _service.getPeriodoMesPagoProduccionEnCurso();

      print('📊 [CalidadDetalle] Períodos (alineados Tu Mes):');
      print('   - Cerrado: $periodoCerrado');
      print('   - En curso: $periodoEnCurso');

      _graficoTresMeses = [];
      for (final row in _service.getPeriodosGraficoCalidadMenosUnoCerradoEnCurso()) {
        final p = row['periodo'] ?? '';
        if (p.isEmpty) continue;
        final data = await _service.obtenerCalidadPorPeriodo(_tecnicoRut!, p);
        final pct = (data?['porcentaje_reiteracion'] as num?)?.toDouble() ?? 0.0;
        _graficoTresMeses.add({
          'periodo': p,
          'porcentaje': pct,
          'label': row['label'] ?? '',
        });
      }

      if (periodoCerrado.isNotEmpty) {
        _calidadCerrado = await _service.obtenerCalidadPorPeriodo(_tecnicoRut!, periodoCerrado);
        _detalleCerrado = await _construirDetalle(_calidadCerrado);
        print('📋 [Cerrado] ${_detalleCerrado.length} detalles cargados');
      }

      if (periodoEnCurso.isNotEmpty) {
        _calidadEnCurso = await _service.obtenerCalidadPorPeriodo(_tecnicoRut!, periodoEnCurso);
        _detalleEnCurso = await _construirDetalle(_calidadEnCurso);
        print('📋 [En curso] ${_detalleEnCurso.length} detalles cargados');
      }
    } catch (e) {
      print('❌ Error cargando datos de calidad: $e');
    }
    
    setState(() => _cargando = false);
  }

  /// Construye la lista de detalle usando calidad_api_crea como fuente principal
  /// (tiene orden_original = reiterada_por_ot y causa = tipo_de_actividad).
  /// Enriquece con produccion_crea para datos de cliente/dirección cuando disponible.
  Future<List<Map<String, dynamic>>> _construirDetalle(
    Map<String, dynamic>? calidadData,
  ) async {
    if (calidadData == null) return [];

    final apiRecords = (calidadData['detalle_calidad_api'] as List<dynamic>?) ?? [];
    if (apiRecords.isEmpty) return [];

    // Mapa base desde calidad_api_crea
    final detalle = apiRecords.map((r) {
      final ordenReit = r['orden_de_trabajo']?.toString() ?? '';
      final ordenOrig = r['reiterada_por_ot']?.toString() ?? '';
      final fechaOrig = r['reiterada_por_fecha']?.toString() ?? '';
      final fechaReit = r['fecha']?.toString() ?? '';
      // Causa: tipo de actividad de la orden original → muestra qué trabajo falló
      final causa = r['reiterada_por_tipo_actividad']?.toString().isNotEmpty == true
          ? r['reiterada_por_tipo_actividad'].toString()
          : r['tipo_de_actividad']?.toString() ?? '';
      final tipoProd = r['tipo_red_producto']?.toString() ?? '';

      return <String, dynamic>{
        'orden_reiterada': ordenReit,
        'orden_original': ordenOrig,
        'fecha_original': fechaOrig,
        'fecha_reiterada': fechaReit,
        'descripcion_reiterado': causa,
        'tipo_red_producto': tipoProd,
        'cliente': '',
        'direccion': '',
        'dias_reiterado': 0,
      };
    }).toList();

    // Enriquecer con produccion_crea: cliente, dirección, días entre fechas
    try {
      final ordenes = detalle
          .map((d) => d['orden_reiterada']?.toString() ?? '')
          .where((o) => o.isNotEmpty)
          .toList();
      if (ordenes.isNotEmpty) {
        final prodResp = await _service.obtenerDetalleDesdeProduccion(
          _tecnicoRut!,
          ordenes,
        );
        final prodMap = <String, dynamic>{};
        for (final p in prodResp) {
          prodMap[p.ordenOriginal] = p;
          prodMap[p.ordenReiterada] = p;
        }
        for (final d in detalle) {
          final key = d['orden_reiterada']?.toString() ?? '';
          final prod = prodMap[key];
          if (prod != null) {
            d['cliente'] = prod.cliente;
            d['direccion'] = prod.direccion;
            // Calcular días entre fecha_original y fecha_reiterada
            try {
              final f1 = DateTime.tryParse(d['fecha_original'].toString());
              final f2 = DateTime.tryParse(d['fecha_reiterada'].toString());
              if (f1 != null && f2 != null) {
                d['dias_reiterado'] = f2.difference(f1).inDays;
              }
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      print('⚠️ [Detalle] No se pudo enriquecer desde produccion_crea: $e');
    }

    return detalle;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text('Calidad', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.amber[700],
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: _cargando
          ? const CreacionesLoading(
              mensaje: 'Cargando datos de calidad...',
            )
          : RefreshIndicator(
              onRefresh: _cargarDatos,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_graficoTresMeses.isNotEmpty) ...[
                    _buildGraficoUltimosTresMeses(),
                    const SizedBox(height: 16),
                  ],
                  if (_calidadCerrado != null)
                    _buildBonoExpansion(
                      calidadData: _calidadCerrado!,
                      detalleReiterados: _detalleCerrado,
                      esCerrado: true,
                    ),
                  const SizedBox(height: 16),
                  if (_calidadEnCurso != null)
                    _buildBonoExpansion(
                      calidadData: _calidadEnCurso!,
                      detalleReiterados: _detalleEnCurso,
                      esCerrado: false,
                    ),
                  const SizedBox(height: 16),
                  _buildRankingExpansion(),
                ],
              ),
            ),
    );
  }
  
  Widget _buildGraficoUltimosTresMeses() {
    final items = _graficoTresMeses;
    if (items.isEmpty) return const SizedBox.shrink();

    final valores = items.map((e) => (e['porcentaje'] as num?)?.toDouble() ?? 0.0).toList();
    final maxVal = math.max(1.0, valores.reduce(math.max) * 1.15);

    return Card(
      color: Colors.grey[850],
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bar_chart, color: Colors.amber[400], size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Reiteración % por mes de pago',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 160,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: items.map((e) {
                  final pct = (e['porcentaje'] as num?)?.toDouble() ?? 0.0;
                  final label = e['label']?.toString() ?? '';
                  final h = (pct / maxVal * 120).clamp(4.0, 120.0);
                  final col = _getColorCalidad(pct);
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            '${pct.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: col,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            height: h,
                            decoration: BoxDecoration(
                              color: col.withOpacity(0.85),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            label,
                            style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBonoExpansion({
    required Map<String, dynamic> calidadData,
    required List<Map<String, dynamic>> detalleReiterados,
    required bool esCerrado,
  }) {
    final porcentaje = (calidadData['porcentaje_reiteracion'] as num?)?.toDouble() ?? 0.0;
    final periodo = calidadData['periodo']?.toString() ?? '';

    // Usar detalleReiterados como fuente de verdad cuando la vista devuelve 0
    final totalReiteradosVista = (calidadData['total_reiterados'] as num?)?.toInt() ?? 0;
    final totalReiterados = totalReiteradosVista > 0
        ? totalReiteradosVista
        : detalleReiterados.length;

    // Calcular promedio de días desde el detalle si la vista devuelve 0
    final promedioDiasVista = (calidadData['promedio_dias'] as num?)?.toDouble() ?? 0.0;
    final promedioDias = promedioDiasVista > 0
        ? promedioDiasVista
        : (detalleReiterados.isNotEmpty
            ? detalleReiterados
                .map((d) => (d['dias_reiterado'] as num?)?.toDouble() ?? 0.0)
                .reduce((a, b) => a + b) /
              detalleReiterados.length
            : 0.0);

    // Deducir totalCompletadas desde el porcentaje si la vista devuelve 0
    final totalCompletadasVista = (calidadData['total_completadas'] as num?)?.toInt() ?? 0;
    final totalCompletadas = totalCompletadasVista > 0
        ? totalCompletadasVista
        : (porcentaje > 0 && totalReiterados > 0
            ? (totalReiterados / porcentaje * 100).round()
            : 0);
    
    final nombreBono = _getNombreBonoDesde(periodo);
    final infoPeriodo = _getInfoPeriodo(periodo);
    final color = _getColorCalidad(porcentaje);
    
    return Card(
      color: Colors.grey[850],
      elevation: 2,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.all(20),
        childrenPadding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
        leading: Icon(
          esCerrado ? Icons.lock : Icons.hourglass_empty,
          color: esCerrado ? Colors.grey : Colors.amber,
          size: 28,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'BONO $nombreBono',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              infoPeriodo['periodo_texto'] ?? '',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[400],
              ),
            ),
            Text(
              infoPeriodo['fin_garantia_texto'] ?? '',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[500],
              ),
            ),
            Text(
              esCerrado ? 'En medición' : 'Midiendo',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: esCerrado ? Colors.amber[200] : Colors.amber,
              ),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${porcentaje.toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              '$totalReiterados / $totalCompletadas',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[400],
              ),
            ),
          ],
        ),
        children: [
          // Porcentaje y promedio
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    Text(
                      '${porcentaje.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    Text(
                      'Porcentaje',
                      style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                    ),
                  ],
                ),
                Container(
                  height: 30,
                  width: 1,
                  color: Colors.grey[700],
                ),
                Column(
                  children: [
                    Text(
                      promedioDias.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Días promedio',
                      style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Lista de reiterados
          if (detalleReiterados.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '¡Sin reiterados! 🎉',
                  style: TextStyle(color: Colors.grey[400]),
                ),
              ),
            )
          else
            ...detalleReiterados.map((detalle) => _buildDetalleReiterado(detalle)),
        ],
      ),
    );
  }
  
  Widget _buildDetalleReiterado(Map<String, dynamic> detalle) {
    final ordenOriginal   = detalle['orden_original']?.toString() ?? '';
    final fechaOriginal   = detalle['fecha_original']?.toString() ?? '';
    final ordenReiterada  = detalle['orden_reiterada']?.toString() ?? '';
    final fechaReiterada  = detalle['fecha_reiterada']?.toString() ?? '';
    final diasReiterado   = (detalle['dias_reiterado'] as num?)?.toInt() ?? 0;
    final causa           = detalle['descripcion_reiterado']?.toString().isNotEmpty == true
        ? detalle['descripcion_reiterado'].toString()
        : detalle['causa']?.toString() ?? '';
    final tipoProd        = detalle['tipo_red_producto']?.toString() ?? '';
    final cliente         = detalle['cliente']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Orden BASE / instalación original (verde) ────────────────
          Row(
            children: [
              const Icon(Icons.check_circle_outline, size: 14, color: Colors.green),
              const SizedBox(width: 4),
              Text(
                'Instalación base',
                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  ordenReiterada.isNotEmpty ? ordenReiterada : '—',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatearFecha(fechaReiterada),
                style: TextStyle(fontSize: 12, color: Colors.grey[400]),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // ── Orden REITERADA (naranja) ────────────────────────────────
          Row(
            children: [
              const Icon(Icons.repeat, size: 14, color: Colors.orange),
              const SizedBox(width: 4),
              Text(
                'Reiterada',
                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  ordenOriginal.isNotEmpty ? ordenOriginal : '—',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatearFecha(fechaOriginal),
                style: TextStyle(fontSize: 12, color: Colors.grey[400]),
              ),
              const Spacer(),
              if (diasReiterado > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$diasReiterado días',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ),
            ],
          ),

          // ── Causa / Tipo actividad ───────────────────────────────────
          if (causa.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.info_outline, size: 13, color: Colors.amber),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    causa,
                    style: TextStyle(fontSize: 11, color: Colors.amber[200]),
                  ),
                ),
              ],
            ),
          ],

          // ── Tipo red/producto ────────────────────────────────────────
          if (tipoProd.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '📡 $tipoProd',
              style: TextStyle(fontSize: 11, color: Colors.grey[400]),
            ),
          ],

          // ── Cliente ──────────────────────────────────────────────────
          if (cliente.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '👤 $cliente',
              style: TextStyle(fontSize: 11, color: Colors.grey[400]),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildRankingExpansion() {
    return Card(
      color: Colors.grey[850],
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.emoji_events_outlined, color: Colors.grey[500], size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ranking de calidad',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Próximamente',
                    style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  String _getNombreBonoDesde(String periodo) {
    if (periodo.isEmpty) return '';
    try {
      final partes = periodo.split('-');
      if (partes.length == 2) {
        final anno = int.parse(partes[0]);
        final mes = int.parse(partes[1]);
        const meses = ['', 'ENE', 'FEB', 'MAR', 'ABR', 'MAY', 'JUN', 
                       'JUL', 'AGO', 'SEP', 'OCT', 'NOV', 'DIC'];
        // El período YA representa el mes del bono
        // El período 2025-11 → BONO NOV
        return meses[mes];
      }
    } catch (e) {
      print('⚠️ Error obteniendo nombre de bono: $e');
    }
    return '';
  }
  
  /// [periodo] YYYY-MM = mes de **pago** del bono (igual que Tu Mes).
  /// Medición = mes anterior; rango natural 1 → último día del mes de medición.
  /// Garantía = último día del mes de pago.
  Map<String, dynamic> _getInfoPeriodo(String periodo) {
    if (periodo.isEmpty) return {};

    try {
      final partes = periodo.split('-');
      if (partes.length == 2) {
        final annoPago = int.parse(partes[0]);
        final mesPago = int.parse(partes[1]);

        const mesesLargos = [
          '',
          'enero',
          'febrero',
          'marzo',
          'abril',
          'mayo',
          'junio',
          'julio',
          'agosto',
          'septiembre',
          'octubre',
          'noviembre',
          'diciembre',
        ];

        DateTime inicioMedicion;
        if (mesPago == 1) {
          inicioMedicion = DateTime(annoPago - 1, 12, 1);
        } else {
          inicioMedicion = DateTime(annoPago, mesPago - 1, 1);
        }
        final ultimoDiaMedicion =
            DateTime(inicioMedicion.year, inicioMedicion.month + 1, 0).day;
        final mm = inicioMedicion.month;

        final ultimoDiaPago = DateTime(annoPago, mesPago + 1, 0).day;

        final periodoTexto =
            '1 de ${mesesLargos[mm]} al $ultimoDiaMedicion de ${mesesLargos[mm]}';
        final finGarantiaTexto =
            'Fin de garantías el $ultimoDiaPago de ${mesesLargos[mesPago]}';

        return {
          'periodo_texto': periodoTexto,
          'fin_garantia_texto': finGarantiaTexto,
          'fin_garantia': DateTime(annoPago, mesPago, ultimoDiaPago, 23, 59, 59),
        };
      }
    } catch (e) {
      print('⚠️ Error calculando info de período: $e');
    }

    return {
      'periodo_texto': '',
      'fin_garantia_texto': '',
      'fin_garantia': null,
    };
  }
  
  String _formatearFecha(String fecha) {
    if (fecha.isEmpty) return '';
    try {
      final partes = fecha.split('-');
      if (partes.length == 3) {
        return '${partes[2]}/${partes[1]}';
      }
    } catch (e) {
      // Ignore
    }
    return fecha;
  }
  
  Color _getColorCalidad(double porcentaje) {
    if (porcentaje <= 4.0) return Colors.green;
    if (porcentaje <= 5.7) return Colors.orange;
    return Colors.red;
  }
  
}


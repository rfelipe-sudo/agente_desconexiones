// ============================================================================
// PANTALLA: MI EQUIPO — Rediseño completo
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/mi_equipo_data_service.dart';
import '../../screens/tecnico_ots_dia_screen.dart';

class MiEquipoScreen extends StatefulWidget {
  const MiEquipoScreen({Key? key}) : super(key: key);

  @override
  State<MiEquipoScreen> createState() => _MiEquipoScreenState();
}

class _MiEquipoScreenState extends State<MiEquipoScreen> {
  final _dataService = MiEquipoDataService();

  static const _colorFondo = Color(0xFF0D1117);
  static const _colorCard = Color(0xFF161B22);
  static const _colorBorde = Color(0xFF30363D);
  static const _colorVerde = Color(0xFF00F080);
  static const _colorAmarillo = Color(0xFFFFCC00);
  static const _colorRojo = Color(0xFFFF2255);
  static const _colorCyan = Color(0xFF00D4FF);

  String? _rutSupervisor;
  List<String> _rutsEquipo = [];
  List<String> _codigosTecnicos = [];
  bool _loading = true;
  DateTime _mesSeleccionado = DateTime.now();

  // Tacómetros
  double _pctMetaDia = 0;
  double _rguHoy = 0;
  double _metaDia = 0;
  double _pctMetaMes = 0;
  double _rguMes = 0;
  double _metaMes = 0;

  // Métricas mes
  int _ordenesMes = 0;
  double _rguPromedioMes = 0;
  double _reiteracionMes = 0;
  int _reiteradosMes = 0;
  int _totalCalidadMes = 0;
  double _quiebreMes = 0;
  int _quiebreCountMes = 0;
  int _totalQuiebreMes = 0;

  // Métricas día (solo cuando mes actual)
  int _activosHoy = 0;
  int _pendientesIniciar = 0;
  int _extensionesHoy = 0;
  List<Map<String, dynamic>> _px0Hoy = [];
  int _quiebreHoy = 0;

  // Mes anterior
  Map<String, dynamic> _mesAnterior = {};
  bool _comparacionExpandida = false;

  // Lista técnicos
  List<Map<String, dynamic>> _tecnicosConRgu = [];
  Map<String, String> _nombresTecnicos = {};
  bool _listaTecnicosExpandida = true;

  bool get _esMesActual =>
      _mesSeleccionado.month == DateTime.now().month &&
      _mesSeleccionado.year == DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  Future<void> _cargarTodo() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      _rutSupervisor = prefs.getString('rut_supervisor') ??
          prefs.getString('rut_tecnico') ??
          prefs.getString('user_rut') ?? '';

      if (_rutSupervisor == null || _rutSupervisor!.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      _rutsEquipo = await _dataService.obtenerRutsEquipo(_rutSupervisor!);
      _codigosTecnicos =
          await _dataService.obtenerCodigosTecnicosEquipo(_rutSupervisor!);

      final nTec = _rutsEquipo.length;
      final diasHab =
          MiEquipoDataService.diasHabilesTranscurridos(_mesSeleccionado);
      _metaMes = nTec * 4.0 * diasHab;

      // Carga en paralelo
      final results = await Future.wait([
        _dataService.obtenerProduccionMes(_rutsEquipo, _mesSeleccionado),
        _dataService.obtenerCalidadMes(_rutsEquipo, _mesSeleccionado),
        _dataService.obtenerQuiebreMes(_rutsEquipo, _mesSeleccionado),
        _esMesActual
            ? _dataService.obtenerProduccionHoy(_rutsEquipo)
            : Future.value(<String, dynamic>{
                'activos': 0,
                'tec_activos': 0,
                'pendientes_iniciar': 0,
                'px0': <Map<String, dynamic>>[],
                'quiebre': 0,
                'rgu_hoy': 0.0,
              }),
        _dataService.obtenerExtensionesHoy(_codigosTecnicos),
        _dataService.obtenerDatosMesAnterior(_rutsEquipo, _mesSeleccionado),
        _esMesActual
            ? _dataService.obtenerTecnicosConRguHoy(_rutsEquipo)
            : Future.value(<Map<String, dynamic>>[]),
        _dataService.obtenerNombresTecnicos(_rutsEquipo),
      ]);

      final prodMes = results[0] as Map<String, dynamic>;
      final calidad = results[1] as Map<String, dynamic>;
      final quiebre = results[2] as Map<String, dynamic>;
      final prodHoy = results[3] as Map<String, dynamic>;
      final extensiones = results[4] as int;
      _mesAnterior = results[5] as Map<String, dynamic>;
      _tecnicosConRgu = results[6] as List<Map<String, dynamic>>;
      _nombresTecnicos = results[7] as Map<String, String>;

      _ordenesMes = prodMes['total_completadas'] as int;
      _rguMes = (prodMes['total_rgu'] as num).toDouble();
      _rguPromedioMes = nTec > 0 ? _rguMes / nTec : 0;
      _pctMetaMes = _metaMes > 0 ? (_rguMes / _metaMes).clamp(0.0, 1.0) : 0;

      _reiteradosMes = calidad['reiterados'] as int;
      _totalCalidadMes = calidad['total'] as int;
      _reiteracionMes = (calidad['porcentaje'] as num).toDouble();

      _quiebreCountMes = quiebre['quiebre'] as int;
      _totalQuiebreMes = quiebre['total'] as int;
      _quiebreMes = (quiebre['porcentaje'] as num).toDouble();

      _activosHoy = prodHoy['activos'] as int;
      _pendientesIniciar = prodHoy['pendientes_iniciar'] as int;
      _px0Hoy = List<Map<String, dynamic>>.from(prodHoy['px0'] as List);
      _quiebreHoy = prodHoy['quiebre'] as int;
      _rguHoy = (prodHoy['rgu_hoy'] as num?)?.toDouble() ?? 0;
      final tecActivos = prodHoy['tec_activos'] as int? ?? 0;
      _metaDia = tecActivos > 0 ? tecActivos * 4.0 : nTec * 4.0;
      _pctMetaDia = _metaDia > 0 ? (_rguHoy / _metaDia).clamp(0.0, 1.0) : 0;

      _extensionesHoy = extensiones;

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatoMes(DateTime m) {
    const meses = [
      'ENE', 'FEB', 'MAR', 'ABR', 'MAY', 'JUN',
      'JUL', 'AGO', 'SEP', 'OCT', 'NOV', 'DIC',
    ];
    return '${meses[m.month - 1]} ${m.year.toString().substring(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'MI EQUIPO',
          style: TextStyle(
            color: Colors.white,
            letterSpacing: 3,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              Navigator.of(context).pushNamedAndRemoveUntil('/home', (r) => false);
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _cargarTodo,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _loading
          ? _buildShimmer()
          : RefreshIndicator(
              onRefresh: _cargarTodo,
              color: _colorCyan,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSelectorMes(),
                    const SizedBox(height: 20),
                    _buildTacometros(),
                    const SizedBox(height: 24),
                    _buildMetricasMes(),
                    const SizedBox(height: 24),
                    _buildMetricasDia(),
                    const SizedBox(height: 24),
                    _buildComparacionMesAnterior(),
                    const SizedBox(height: 24),
                    _buildListaTecnicos(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildShimmer() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(
              4,
              (_) => Container(
                margin: const EdgeInsets.only(right: 8),
                width: 70,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: List.generate(
              4,
              (_) => Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorMes() {
    final meses = MiEquipoDataService.mesesDisponibles();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: meses.map((m) {
          final activo = m.month == _mesSeleccionado.month &&
              m.year == _mesSeleccionado.year;
          return GestureDetector(
            onTap: () {
              setState(() {
                _mesSeleccionado = m;
                _cargarTodo();
              });
            },
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: activo ? _colorCyan : _colorCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: activo ? _colorCyan : _colorBorde,
                ),
              ),
              child: Text(
                _formatoMes(m),
                style: TextStyle(
                  color: activo ? Colors.black : Colors.white54,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTacometros() {
    return Row(
      children: [
        Expanded(
          child: _buildGauge(
            titulo: 'META DÍA',
            pct: _pctMetaDia,
            valorStr: _rguHoy.toStringAsFixed(0),
            metaStr: ' / ${_metaDia.toStringAsFixed(0)} RGU',
            subtituloStr: _esMesActual
                ? '${_activosHoy} téc activos × 4.0'
                : '—',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildGauge(
            titulo: 'META MES',
            pct: _pctMetaMes,
            valorStr: _rguMes.toStringAsFixed(0),
            metaStr: ' / ${_metaMes.toStringAsFixed(0)}',
            subtituloStr:
                '${_rutsEquipo.length} téc × ${MiEquipoDataService.diasHabilesTranscurridos(_mesSeleccionado)} días × 4.0',
          ),
        ),
      ],
    );
  }

  Widget _buildGauge({
    required String titulo,
    required double pct,
    required String valorStr,
    required String metaStr,
    required String subtituloStr,
  }) {
    final col = pct >= 0.85
        ? _colorVerde
        : pct >= 0.60
            ? _colorCyan
            : pct >= 0.40
                ? _colorAmarillo
                : _colorRojo;
    return Container(
      decoration: BoxDecoration(
        color: _colorCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _colorBorde),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            titulo,
            style: TextStyle(
              color: Colors.white.withOpacity(0.45),
              fontSize: 10,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 130,
            child: CustomPaint(
              painter: GaugePainter(pct: pct, valueColor: col),
              size: Size.infinite,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                valorStr,
                style: GoogleFonts.rajdhani(
                  color: col,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                metaStr,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.38),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${(pct * 100).toStringAsFixed(0)}%',
            style: GoogleFonts.rajdhani(
              color: col,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtituloStr,
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 9,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricasMes() {
    final colorRgu = _rguPromedioMes >= 4
        ? _colorVerde
        : _rguPromedioMes >= 2.8
            ? _colorAmarillo
            : _colorRojo;
    final colorReiteracion = _reiteracionMes <= 5
        ? _colorVerde
        : _reiteracionMes <= 8
            ? _colorAmarillo
            : _colorRojo;
    final colorQuiebre = _quiebreMes <= 10
        ? _colorVerde
        : _quiebreMes <= 20
            ? _colorAmarillo
            : _colorRojo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'MÉTRICAS DEL MES',
          style: TextStyle(
            color: Colors.white.withOpacity(0.45),
            fontSize: 10,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.4,
          children: [
            _metricCard(
              'ÓRDENES MES',
              '$_ordenesMes',
              'Prom: ${_rutsEquipo.isEmpty ? 0 : (_ordenesMes / _rutsEquipo.length).toStringAsFixed(0)}/téc.',
              _colorCyan,
            ),
            _metricCard(
              'RGU MES',
              _rguPromedioMes.toStringAsFixed(1),
              'Prom: ${_rguPromedioMes.toStringAsFixed(1)}/téc.',
              colorRgu,
            ),
            _metricCard(
              '% REITERACIÓN',
              '${_reiteracionMes.toStringAsFixed(1)}%',
              '$_reiteradosMes / $_totalCalidadMes órdenes',
              colorReiteracion,
            ),
            _metricCard(
              '% QUIEBRE',
              '${_quiebreMes.toStringAsFixed(1)}%',
              '$_quiebreCountMes / $_totalQuiebreMes',
              colorQuiebre,
            ),
          ],
        ),
      ],
    );
  }

  Widget _metricCard(String label, String value, String subtitle, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _colorCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _colorBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.45),
              fontSize: 10,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.rajdhani(
              color: color,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.38),
              fontSize: 10,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricasDia() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'MÉTRICAS DEL DÍA',
          style: TextStyle(
            color: Colors.white.withOpacity(0.45),
            fontSize: 10,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _chipMetrica(
                'ACTIVOS',
                _esMesActual ? '$_activosHoy/${_rutsEquipo.length}' : '—',
              ),
              const SizedBox(width: 8),
              _chipMetrica(
                'PEND. INICIAR',
                _esMesActual ? '$_pendientesIniciar' : '—',
              ),
              const SizedBox(width: 8),
              _chipMetrica(
                'TIEMPOS EXT.',
                _esMesActual ? '$_extensionesHoy' : '—',
              ),
              const SizedBox(width: 8),
              _chipMetrica(
                'PX0 HOY',
                _esMesActual ? '${_px0Hoy.length}' : '—',
                color: _px0Hoy.isNotEmpty ? _colorRojo : null,
                onTap: _px0Hoy.isNotEmpty ? _mostrarPx0Modal : null,
              ),
              const SizedBox(width: 8),
              _chipMetrica(
                'QUIEBRE HOY',
                _esMesActual ? '$_quiebreHoy' : '—',
                color: _quiebreHoy > 0 ? _colorRojo : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chipMetrica(String label, String value,
      {Color? color, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _colorCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: (color ?? _colorBorde).withOpacity(0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.45),
                fontSize: 10,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              style: GoogleFonts.rajdhani(
                color: color ?? Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarPx0Modal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _colorCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'PX0 HOY (${_px0Hoy.length})',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ..._px0Hoy.map((p) {
              final tieneTrabajo = p['tiene_trabajo_cargado'] == true;
              return ListTile(
                leading: Icon(
                  tieneTrabajo ? Icons.check_circle : Icons.cancel,
                  color: tieneTrabajo ? _colorVerde : _colorRojo,
                  size: 24,
                ),
                title: Text(
                  _nombresTecnicos[p['rut_tecnico']] ??
                      ((p['tecnico'] as String? ?? '').trim().isNotEmpty
                          ? (p['tecnico'] as String)
                          : (p['rut_tecnico'] ?? 'Técnico')),
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  '${p['orden_trabajo']} · ${p['estado']}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildComparacionMesAnterior() {
    final rguAnt = (_mesAnterior['rgu_promedio'] as num?)?.toDouble() ?? 0;
    final reiterAnt = (_mesAnterior['reiteracion'] as num?)?.toDouble() ?? 0;
    final quiebreAnt = (_mesAnterior['quiebre'] as num?)?.toDouble() ?? 0;
    final ordAnt = (_mesAnterior['ordenes_promedio'] as num?)?.toDouble() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () =>
              setState(() => _comparacionExpandida = !_comparacionExpandida),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _colorCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _colorBorde),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'COMPARACIÓN MES ANTERIOR',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.45),
                    fontSize: 10,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(
                  _comparacionExpandida ? Icons.expand_less : Icons.expand_more,
                  color: Colors.white54,
                ),
              ],
            ),
          ),
        ),
        if (_comparacionExpandida) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _colorCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _colorBorde),
            ),
            child: Column(
              children: [
                _buildComparacionFila(
                  'RGU prom/téc',
                  rguAnt.toStringAsFixed(1),
                  _rguPromedioMes.toStringAsFixed(1),
                  _rguPromedioMes > rguAnt,
                ),
                _buildComparacionFila(
                  '% Reiteración',
                  '${reiterAnt.toStringAsFixed(1)}%',
                  '${_reiteracionMes.toStringAsFixed(1)}%',
                  _reiteracionMes < reiterAnt,
                ),
                _buildComparacionFila(
                  '% Quiebre',
                  '${quiebreAnt.toStringAsFixed(1)}%',
                  '${_quiebreMes.toStringAsFixed(1)}%',
                  _quiebreMes < quiebreAnt,
                ),
                _buildComparacionFila(
                  'Órdenes prom',
                  ordAnt.toStringAsFixed(0),
                  _rutsEquipo.isEmpty
                      ? '0'
                      : (_ordenesMes / _rutsEquipo.length).toStringAsFixed(0),
                  _rutsEquipo.isEmpty
                      ? false
                      : (_ordenesMes / _rutsEquipo.length) > ordAnt,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildComparacionFila(
      String label, String valorAnt, String valorActual, bool mejoro) {
    final colorFlecha = mejoro
        ? _colorVerde
        : (valorAnt == valorActual ? Colors.grey : _colorRojo);
    final icono = mejoro
        ? Icons.arrow_upward
        : (valorAnt == valorActual ? Icons.remove : Icons.arrow_downward);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 13,
            ),
          ),
          Row(
            children: [
              Text(
                valorAnt,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.38),
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              Icon(icono, color: colorFlecha, size: 16),
              const SizedBox(width: 8),
              Text(
                valorActual,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildListaTecnicos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () =>
              setState(() => _listaTecnicosExpandida = !_listaTecnicosExpandida),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _colorCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _colorBorde),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'TÉCNICOS (${_tecnicosConRgu.length})',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.45),
                    fontSize: 10,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(
                  _listaTecnicosExpandida
                      ? Icons.expand_less
                      : Icons.expand_more,
                  color: Colors.white54,
                ),
              ],
            ),
          ),
        ),
        if (_listaTecnicosExpandida) ...[
          const SizedBox(height: 8),
          ..._tecnicosConRgu.map((t) => _buildTecnicoItem(t)),
        ],
      ],
    );
  }

  Widget _buildTecnicoItem(Map<String, dynamic> t) {
    final activo = t['activo'] == true;
    final rguDia = (t['rgu_dia'] as num?)?.toDouble() ?? 0;
    final completadas = t['completadas'] as int? ?? 0;
    final total = t['total'] as int? ?? 1;
    final progreso = (rguDia / 4.0).clamp(0.0, 1.0);

    final rut = t['rut'] as String? ?? '';
    final nombre = _nombresTecnicos[rut] ??
        ((t['nombre'] as String? ?? '').trim().isNotEmpty
            ? (t['nombre'] as String)
            : (rut.isNotEmpty ? rut : 'Técnico'));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: rut.isEmpty
            ? null
            : () {
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => TecnicoOtsDiaScreen(
                      rutTecnico: rut,
                      nombreTecnico: nombre,
                    ),
                  ),
                );
              },
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _colorCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _colorBorde),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: activo ? _colorVerde : _colorRojo,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'RGU: ${rguDia.toStringAsFixed(1)}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '$completadas / $total',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.45),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progreso,
                        minHeight: 4,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          progreso >= 1 ? _colorVerde : _colorCyan,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// GaugePainter — Tacómetro preciso
// ─────────────────────────────────────────────────────────────

class GaugePainter extends CustomPainter {
  final double pct;
  final Color valueColor;

  GaugePainter({required this.pct, required this.valueColor});

  static const _labelStyle = TextStyle(
    color: Color(0xFF253A52),
    fontSize: 9,
    fontFamily: 'monospace',
  );

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.72;
    final radius = size.width * 0.42;
    const sw = 14.0;
    const startAngle = math.pi;
    const sweepAngle = math.pi;

    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);

    // 1. Arco de fondo
    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF1E2A35);
    canvas.drawArc(rect, startAngle, sweepAngle, false, bgPaint);

    // 2. Arco de valor con gradiente
    if (pct > 0.01) {
      final gradient = SweepGradient(
        center: Alignment.center,
        startAngle: math.pi,
        endAngle: 2 * math.pi,
        colors: const [
          Color(0xFFFF2255),
          Color(0xFFFF6D00),
          Color(0xFFFFCC00),
          Color(0xFF00F080),
        ],
        stops: const [0.0, 0.3, 0.6, 1.0],
      );
      final gradientPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw
        ..strokeCap = StrokeCap.round
        ..shader = gradient.createShader(rect);
      canvas.drawArc(
        rect,
        startAngle,
        sweepAngle * pct.clamp(0.0, 1.0),
        false,
        gradientPaint,
      );
    }

    // 3. Marcas de escala
    for (final mark in [0.0, 0.25, 0.5, 0.75, 1.0]) {
      final angle = math.pi + math.pi * mark;
      final inner = Offset(
        cx + (radius - sw - 3) * math.cos(angle),
        cy + (radius - sw - 3) * math.sin(angle),
      );
      final outer = Offset(
        cx + (radius + 4) * math.cos(angle),
        cy + (radius + 4) * math.sin(angle),
      );
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..color = const Color(0xFF253A52)
          ..strokeWidth = (mark == 0 || mark == 0.5 || mark == 1.0) ? 1.5 : 1.0,
      );
    }

    // 4. Aguja
    final needleAngle = math.pi + math.pi * pct.clamp(0.0, 1.0);
    final needleTip = Offset(
      cx + (radius - sw / 2 - 3) * math.cos(needleAngle),
      cy + (radius - sw / 2 - 3) * math.sin(needleAngle),
    );
    canvas.drawLine(
      Offset(cx, cy),
      needleTip,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    // 5. Hub central
    canvas.drawCircle(Offset(cx, cy), 8, Paint()..color = Colors.white);
    canvas.drawCircle(
      Offset(cx, cy),
      12,
      Paint()
        ..color = Colors.white.withOpacity(0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // 6. Labels
    final tp0 = TextPainter(
      text: TextSpan(text: '0', style: _labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final tp100 = TextPainter(
      text: TextSpan(text: '100%', style: _labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final tp50 = TextPainter(
      text: TextSpan(text: '50%', style: _labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final left = Offset(cx - radius - sw / 2 - 4, cy - tp0.height / 2);
    final right =
        Offset(cx + radius + sw / 2 - tp100.width + 2, cy - tp100.height / 2);
    final top = Offset(cx - tp50.width / 2, cy - radius - sw / 2 - 16);
    tp0.paint(canvas, left);
    tp100.paint(canvas, right);
    tp50.paint(canvas, top);
  }

  @override
  bool shouldRepaint(GaugePainter old) => old.pct != pct;
}

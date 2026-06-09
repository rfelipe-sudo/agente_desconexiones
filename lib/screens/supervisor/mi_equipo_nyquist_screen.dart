import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/nyquist_panel_coord_service.dart';
import '../../widgets/mi_equipo_gauge_painter.dart';
import '../tecnico_ots_dia_screen.dart';

/// Mi Equipo — datos en vivo desde Nyquist `datos_panel_coord`.
class MiEquipoNyquistScreen extends StatefulWidget {
  const MiEquipoNyquistScreen({super.key});

  @override
  State<MiEquipoNyquistScreen> createState() => _MiEquipoNyquistScreenState();
}

class _MiEquipoNyquistScreenState extends State<MiEquipoNyquistScreen> {
  final _service = NyquistPanelCoordService();

  static const _colorFondo = Color(0xFF0D1117);
  static const _colorCard = Color(0xFF161B22);
  static const _colorBorde = Color(0xFF30363D);
  static const _colorVerde = Color(0xFF00F080);
  static const _colorAmarillo = Color(0xFFFFCC00);
  static const _colorRojo = Color(0xFFFF2255);
  static const _colorCyan = Color(0xFF00D4FF);

  bool _loading = true;
  String? _error;
  NyquistEquipoSupervisor? _equipo;
  bool _listaExpandida = true;
  final _busquedaCtrl = TextEditingController();
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  String _normBusqueda(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[.\-\s]'), '');

  bool _coincideBusqueda(Map<String, dynamic> t) {
    final q = _busqueda.trim();
    if (q.isEmpty) return true;
    final nq = _normBusqueda(q);
    final nombre = _normBusqueda(NyquistPanelCoordService.nombreTecnico(t));
    final rut = _normBusqueda(NyquistPanelCoordService.rutTecnico(t));
    return nombre.contains(nq) || rut.contains(nq);
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final rut = prefs.getString('rut_supervisor') ??
          prefs.getString('rut_tecnico') ??
          prefs.getString('user_rut') ??
          '';
      if (rut.isEmpty) {
        throw Exception('Sin RUT de supervisor en sesión');
      }
      final data = await _service.obtenerEquipoSupervisor(rut);
      if (!mounted) return;
      setState(() {
        _equipo = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Color _colorPct(double pct) {
    if (pct >= 0.85) return _colorVerde;
    if (pct >= 0.60) return _colorCyan;
    if (pct >= 0.40) return _colorAmarillo;
    return _colorRojo;
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
              Navigator.of(context)
                  .pushNamedAndRemoveUntil('/home', (r) => false);
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _cargar,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _colorCyan),
            )
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _cargar,
                  color: _colorCyan,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildEncabezado(),
                        const SizedBox(height: 16),
                        _buildPeriodos(),
                        const SizedBox(height: 20),
                        _buildTacometros(),
                        const SizedBox(height: 24),
                        _buildMetricasMes(),
                        const SizedBox(height: 24),
                        _buildMetricasDia(),
                        const SizedBox(height: 24),
                        _buildListaTecnicos(),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            'Fuente: Nyquist panel coordinación',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.25),
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: _colorRojo, size: 48),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _cargar,
              style: FilledButton.styleFrom(backgroundColor: _colorCyan),
              child: const Text('Reintentar', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEncabezado() {
    final e = _equipo!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _colorCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _colorBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            e.nombreSesion,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${e.equipo ?? '—'} · ${e.nTecnicos} técnicos',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
          ),
          if (e.mapeadoDesdeRafael) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _colorAmarillo.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _colorAmarillo.withOpacity(0.35)),
              ),
              child: const Text(
                'Datos Nyquist vía equipo Rafael (temporal)',
                style: TextStyle(color: _colorAmarillo, fontSize: 10),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPeriodos() {
    final e = _equipo!;
    return Row(
      children: [
        _periodoChip('MES ACTUAL', e.periodoActual),
        const SizedBox(width: 8),
        _periodoChip('MES PAGO', e.periodoPago),
      ],
    );
  }

  Widget _periodoChip(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _colorCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _colorBorde),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 9,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTacometros() {
    final e = _equipo!;
    return Row(
      children: [
        Expanded(
          child: _gauge(
            titulo: 'META DÍA',
            pct: e.pctMetaDia,
            valor: e.rguDia.toStringAsFixed(0),
            meta: e.metaDia.toStringAsFixed(0),
            subtitulo: '${e.operativos} operativos × 4.0',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _gauge(
            titulo: 'META MES',
            pct: e.pctMetaMes,
            valor: e.rguMesActual.toStringAsFixed(0),
            meta: e.metaMes.toStringAsFixed(0),
            subtitulo:
                '${e.nTecPlantel} téc × ${NyquistPanelCoordService.diasHabilesMesActual()} días × 4.0',
          ),
        ),
      ],
    );
  }

  Widget _gauge({
    required String titulo,
    required double pct,
    required String valor,
    required String meta,
    required String subtitulo,
  }) {
    final col = _colorPct(pct);
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
              painter: MiEquipoGaugePainter(pct: pct, valueColor: col),
              size: Size.infinite,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                valor,
                style: GoogleFonts.rajdhani(
                  color: col,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                ' / $meta',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.38),
                  fontSize: 16,
                ),
              ),
            ],
          ),
          Text(
            '${(pct * 100).toStringAsFixed(0)}%',
            style: GoogleFonts.rajdhani(
              color: col,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            subtitulo,
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 9,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricasMes() {
    final e = _equipo!;
    final rguPromMes = e.rguPromDiaMesPorTecnico;
    final colorRgu = rguPromMes >= 4
        ? _colorVerde
        : rguPromMes >= 2.8
            ? _colorAmarillo
            : _colorRojo;
    final colorReitActual = e.pctReitActual <= 5
        ? _colorVerde
        : e.pctReitActual <= 8
            ? _colorAmarillo
            : _colorRojo;
    final colorReitPago = e.pctReitPago <= 5
        ? _colorVerde
        : e.pctReitPago <= 8
            ? _colorAmarillo
            : _colorRojo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('MÉTRICAS DEL MES'),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.28,
          children: [
            _metricCard(
              'OTs MES ACTUAL',
              '${e.otsMesActual}',
              'Mes pago: ${e.otsMesPago} OTs',
              _colorCyan,
            ),
            _metricCard(
              'RGU PROM/DÍA TÉC',
              rguPromMes.toStringAsFixed(2),
              '${e.tecnicosConPromMes} téc · total mes ${e.rguMesActual.toStringAsFixed(0)} RGU',
              colorRgu,
            ),
            _metricCard(
              '% REIT. MES ACTUAL',
              '${e.pctReitActual.toStringAsFixed(2)}%',
              '${e.reitActual} reit. · ${e.periodoActual}',
              colorReitActual,
            ),
            _metricCard(
              '% REIT. MES PAGO',
              '${e.pctReitPago.toStringAsFixed(2)}%',
              '${e.reitPago} reit. · ${e.periodoPago}',
              colorReitPago,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricasDia() {
    final e = _equipo!;
    final px0 = e.px0Hoy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('MÉTRICAS DEL DÍA'),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _chip('OPERATIVOS', '${e.operativos}/${e.nTecPlantel}'),
              const SizedBox(width: 8),
              _chip(
                'RGU PROM/DÍA',
                e.rguPromDiaHoyPorTecnico.toStringAsFixed(2),
                color: e.rguPromDiaHoyPorTecnico >= 4
                    ? _colorVerde
                    : e.rguPromDiaHoyPorTecnico >= 2.8
                        ? _colorAmarillo
                        : _colorRojo,
              ),
              const SizedBox(width: 8),
              _chip('AUSENTES', '${e.ausentes}'),
              const SizedBox(width: 8),
              _chip('COMPLETADAS', '${e.compDia}'),
              const SizedBox(width: 8),
              _chip('EN CURSO', '${e.cursoDia}'),
              const SizedBox(width: 8),
              _chip(
                'PX0 HOY',
                '${px0.length}',
                color: px0.isNotEmpty ? _colorRojo : null,
                onTap: px0.isNotEmpty ? () => _mostrarPx0(px0) : null,
              ),
              const SizedBox(width: 8),
              _chip('SIN CIERRE', '${e.sinCierreDia}'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildListaTecnicos() {
    final e = _equipo!;
    final total = e.tecnicos.length;
    final lista = [...e.tecnicos]
      ..sort((a, b) {
        final pa = NyquistPanelCoordService.esPx0Hoy(a);
        final pb = NyquistPanelCoordService.esPx0Hoy(b);
        if (pa != pb) return pa ? -1 : 1;
        return NyquistPanelCoordService.nombreTecnico(a)
            .compareTo(NyquistPanelCoordService.nombreTecnico(b));
      });
    final filtrada = lista.where(_coincideBusqueda).toList();
    final tituloLista = _busqueda.trim().isEmpty
        ? 'TÉCNICOS ($total)'
        : 'TÉCNICOS (${filtrada.length}/$total)';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _listaExpandida = !_listaExpandida),
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
                _sectionTitle(tituloLista),
                Icon(
                  _listaExpandida ? Icons.expand_less : Icons.expand_more,
                  color: Colors.white54,
                ),
              ],
            ),
          ),
        ),
        if (_listaExpandida) ...[
          const SizedBox(height: 8),
          _buildBuscadorTecnicos(),
          const SizedBox(height: 8),
          if (filtrada.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _colorCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _colorBorde),
              ),
              child: Text(
                'Sin resultados para "$_busqueda"',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.45),
                  fontSize: 13,
                ),
              ),
            )
          else
            ...filtrada.map(_tecnicoTile),
        ],
      ],
    );
  }

  Widget _buildBuscadorTecnicos() {
    return Container(
      decoration: BoxDecoration(
        color: _colorCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _colorBorde),
      ),
      child: TextField(
        controller: _busquedaCtrl,
        onChanged: (v) => setState(() => _busqueda = v),
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Buscar por nombre o RUT',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
          prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.45)),
          suffixIcon: _busqueda.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close, color: Colors.white.withOpacity(0.45)),
                  onPressed: () {
                    _busquedaCtrl.clear();
                    setState(() => _busqueda = '');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          isDense: true,
        ),
      ),
    );
  }

  Widget _tecnicoTile(Map<String, dynamic> t) {
    final rut = NyquistPanelCoordService.rutTecnico(t);
    final nombre = NyquistPanelCoordService.nombreTecnico(t);
    final rgu = NyquistPanelCoordService.asDouble(t['rgu_dia']);
    final rguPromMes = NyquistPanelCoordService.asDouble(t['rgu_prom_dia']);
    final completadas = NyquistPanelCoordService.entero(t['completadas']);
    final enEjec = NyquistPanelCoordService.entero(t['en_ejecucion']);
    final px0 = NyquistPanelCoordService.esPx0Hoy(t);
    final operativo = t['operativo'] == true && t['ausente'] != true;
    final condicion = t['condicion']?.toString() ?? '';
    final progreso = (rgu / 4.0).clamp(0.0, 1.0);

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
            border: Border.all(
              color: px0 ? _colorRojo.withOpacity(0.55) : _colorBorde,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: px0
                      ? _colorRojo
                      : operativo
                          ? _colorVerde
                          : Colors.grey,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            nombre.isEmpty ? rut : nombre,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (px0)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _colorRojo.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'PX0',
                              style: TextStyle(
                                color: _colorRojo,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$condicion · $completadas comp · $enEjec en curso',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.45),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          'Hoy: ${rgu.toStringAsFixed(1)}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.75),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Prom/día: ${rguPromMes.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
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
                          px0
                              ? _colorRojo
                              : progreso >= 1
                                  ? _colorVerde
                                  : _colorCyan,
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

  void _mostrarPx0(List<Map<String, dynamic>> px0) {
    showModalBottomSheet<void>(
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'PX0 HOY — SIN CIERRE (${px0.length})',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Técnicos con actividad hoy pero sin OT completada ni RGU.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.45),
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: px0.length,
                itemBuilder: (_, i) {
                  final t = px0[i];
                  final nombre = NyquistPanelCoordService.nombreTecnico(t);
                  final rut = NyquistPanelCoordService.rutTecnico(t);
                  final enEj = NyquistPanelCoordService.entero(t['en_ejecucion']);
                  return ListTile(
                    leading: const Icon(Icons.warning_amber_rounded,
                        color: _colorRojo),
                    title: Text(
                      nombre.isEmpty ? rut : nombre,
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      '$enEj en ejecución · RGU ${NyquistPanelCoordService.asDouble(t['rgu_dia']).toStringAsFixed(1)}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: TextStyle(
          color: Colors.white.withOpacity(0.45),
          fontSize: 10,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w600,
        ),
      );

  Widget _metricCard(
    String label,
    String value,
    String subtitle,
    Color color,
  ) {
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
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.38),
              fontSize: 10,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _chip(
    String label,
    String value, {
    Color? color,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _colorCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: (color ?? _colorBorde).withOpacity(0.5)),
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
}

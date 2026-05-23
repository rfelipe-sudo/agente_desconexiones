import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/models/ford_ruta.dart';
import 'package:agente_desconexiones/screens/ford_rutas_screen.dart';
import 'package:agente_desconexiones/services/ford_api_service.dart';
import 'package:agente_desconexiones/widgets/combustible_format.dart';
import 'package:agente_desconexiones/widgets/sol_comb_tecnico_widget.dart';

// Fecha de inicio del historial — no se muestra nada anterior a esta fecha.
const _kInicio = '2026-05-18';

String _kInicioLabel() {
  final d = DateTime.parse(_kInicio);
  const mm = ['', 'ene', 'feb', 'mar', 'abr', 'may', 'jun',
               'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  return '${d.day} ${mm[d.month]}';
}

// ── Modelo de semana ──────────────────────────────────────────────────────────

class _SemanaResumen {
  final int weekNum;
  final int year;
  final DateTime primerDia;
  final DateTime ultimoDia;
  final double kmTotal;
  final double litrosTotal;
  final double costoTotal;
  final int diasTrabajados;

  const _SemanaResumen({
    required this.weekNum,
    required this.year,
    required this.primerDia,
    required this.ultimoDia,
    required this.kmTotal,
    required this.litrosTotal,
    required this.costoTotal,
    required this.diasTrabajados,
  });

  _SemanaResumen agregar(DateTime dia, double km, double lit, double cost) =>
      _SemanaResumen(
        weekNum: weekNum,
        year: year,
        primerDia: dia.isBefore(primerDia) ? dia : primerDia,
        ultimoDia: dia.isAfter(ultimoDia)  ? dia : ultimoDia,
        kmTotal: kmTotal + km,
        litrosTotal: litrosTotal + lit,
        costoTotal: costoTotal + cost,
        diasTrabajados: diasTrabajados + 1,
      );

  /// "2026-05" — mes del último día, para navegación FordRutasScreen.
  String get mesStr {
    final d = ultimoDia;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}';
  }
}

// ── Widget principal ──────────────────────────────────────────────────────────

class EstanqueScreen extends StatefulWidget {
  final String rut;
  final String nombreTecnico;
  final double precioLitroRef;
  final double initialSaldoPesos;
  final double initialSaldoLitros;
  final String? initialPatente;

  const EstanqueScreen({
    super.key,
    required this.rut,
    required this.nombreTecnico,
    required this.precioLitroRef,
    required this.initialSaldoPesos,
    required this.initialSaldoLitros,
    this.initialPatente,
  });

  @override
  State<EstanqueScreen> createState() => _EstanqueScreenState();
}

class _EstanqueScreenState extends State<EstanqueScreen> {
  static const Color _surface = Color(0xFF0D1B2A);
  static const Color _bg      = Color(0xFF0A1628);
  static const Color _accent  = Color(0xFF00D9FF);
  static const Color _border  = Color(0xFF1E3A5F);
  static const Color _textDim = Color(0xFF8FA8C8);
  static const Color _orange  = Color(0xFFF59E0B);
  static const Color _green   = Color(0xFF22C55E);
  static const double _rendKmL = 12.0;

  // Saldo virtual = cargas desde _kInicio - consumos desde _kInicio
  double  _vSaldoPesos    = 0.0;
  double  _vSaldoLitros   = 0.0;
  double  _totalCargPesos = 0.0;
  double  _totalConsPesos = 0.0;
  late String? _patente;

  List<_SemanaResumen> _semanas       = [];
  bool                 _semanasLoad   = true;

  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  @override
  void initState() {
    super.initState();
    _patente = widget.initialPatente;
    _suscribirRealtime();
    _cargarSemanas();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ── Realtime ──

  void _suscribirRealtime() {
    _sub = Supabase.instance.client
        .from('monedero_combustible')
        .stream(primaryKey: ['rut_tecnico'])
        .eq('rut_tecnico', widget.rut)
        .listen((data) {
      if (data.isEmpty || !mounted) return;
      // Solo actualiza patente; el saldo se calcula desde _kInicio
      setState(() => _patente = data.first['patente']?.toString());
    });
  }

  // ── Carga de semanas + saldo virtual ──

  Future<void> _cargarSemanas() async {
    if (mounted) setState(() => _semanasLoad = true);
    try {
      final inicio = DateTime.parse(_kInicio);

      // Fetch en paralelo: rutas Ford + cargas desde _kInicio
      final results = await Future.wait<dynamic>([
        FordApiService().getRutasDelTecnico(widget.rut),
        Supabase.instance.client
            .from('cargas_combustible')
            .select('litros, monto')
            .eq('rut_conductor', widget.rut)
            .gte('fecha', _kInicio),
      ]);

      final fordRutas = results[0] as List<FordDiaRuta>;
      final cargaRows = results[1] as List;

      // Saldo virtual: Σ cargas (pesos/litros)
      double totalCargLit = 0, totalCargPesos = 0;
      for (final r in cargaRows) {
        totalCargLit   += CombustibleFormat.toDouble(r['litros']);
        totalCargPesos += CombustibleFormat.toDouble(r['monto']);
      }

      // Agrupar rutas por semana ISO, filtrando desde _kInicio.
      // Litros y costo se calculan desde km (igual que FordRutasScreen).
      double totalConsumoLit = 0;
      final Map<String, _SemanaResumen> mapa = {};
      for (final dia in fordRutas) {
        final fecha = dia.fecha;
        if (fecha == null || fecha.isBefore(inicio)) continue;

        final wn  = _isoWeek(fecha);
        final yr  = _isoWeekYear(fecha, wn);
        final key = '$yr-${wn.toString().padLeft(2, '0')}';

        final km   = dia.kmTotal;
        final lit  = km / _rendKmL;
        final cost = lit * widget.precioLitroRef;
        totalConsumoLit += lit;

        mapa[key] = mapa.containsKey(key)
            ? mapa[key]!.agregar(fecha, km, lit, cost)
            : _SemanaResumen(
                weekNum: wn, year: yr,
                primerDia: fecha, ultimoDia: fecha,
                kmTotal: km, litrosTotal: lit, costoTotal: cost,
                diasTrabajados: 1,
              );
      }

      final lista = mapa.values.toList()
        ..sort((a, b) {
          final cy = b.year.compareTo(a.year);
          return cy != 0 ? cy : b.weekNum.compareTo(a.weekNum);
        });

      final totalConsumoPesos = totalConsumoLit * widget.precioLitroRef;
      final vLitros = (totalCargLit  - totalConsumoLit).clamp(0.0, double.infinity);
      final vPesos  = (totalCargPesos - totalConsumoPesos).clamp(0.0, double.infinity);

      // Sincroniza el saldo calculado en monedero_combustible para que el
      // trigger trg_saldo_bajo pueda disparar la solicitud operacional.
      unawaited(Supabase.instance.client
          .from('monedero_combustible')
          .update({
            'saldo_litros':           double.parse(vLitros.toStringAsFixed(2)),
            'saldo_pesos':            vPesos.round(),
            'total_consumido':        double.parse(totalConsumoLit.toStringAsFixed(2)),
            'total_consumido_pesos':  totalConsumoPesos.round(),
          })
          .eq('rut_tecnico', widget.rut)
          .then((_) {}, onError: (_) {}));

      if (mounted) {
        setState(() {
          _semanas        = lista;
          _semanasLoad    = false;
          _vSaldoLitros   = vLitros;
          _vSaldoPesos    = vPesos;
          _totalCargPesos = totalCargPesos;
          _totalConsPesos = totalConsumoPesos;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _semanasLoad = false);
    }
  }

  // ── ISO week helpers ──

  /// ISO 8601 week number (1–53).
  int _isoWeek(DateTime d) {
    final doy = d.difference(DateTime(d.year, 1, 1)).inDays + 1;
    return ((doy - d.weekday + 10) ~/ 7);
  }

  /// ISO week-year (handles Jan/Dec edge cases).
  int _isoWeekYear(DateTime d, int wn) {
    if (wn >= 52 && d.month == 1)  return d.year - 1;
    if (wn == 1  && d.month == 12) return d.year + 1;
    return d.year;
  }

  // ── Formatters ──

  Color _colorSaldo(double p) {
    if (p <= 0) return Colors.grey;
    if (p > 15000) return _green;
    if (p > 7000)  return _orange;
    return const Color(0xFFEF4444);
  }

  String _fmtPesos(double v) {
    if (v <= 0) return '\$0';
    final s = v.round().toString();
    final buf = StringBuffer();
    int cnt = 0;
    for (int k = s.length - 1; k >= 0; k--) {
      if (cnt > 0 && cnt % 3 == 0) buf.write('.');
      buf.write(s[k]);
      cnt++;
    }
    return '\$${buf.toString().split('').reversed.join()}';
  }

  Widget _resumenCol(String label, String valor, Color color) => Expanded(
    child: Column(children: [
      Text(label,
          style: TextStyle(color: _textDim, fontSize: 10)),
      const SizedBox(height: 2),
      Text(valor,
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 13)),
    ]),
  );

  Widget _dividerV() => Container(
    width: 1, height: 32, color: _border,
  );

  String _labelRango(_SemanaResumen s) {
    const ms = ['', 'ene', 'feb', 'mar', 'abr', 'may', 'jun',
                 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    final ini = s.primerDia;
    final fin = s.ultimoDia;
    return ini.month == fin.month
        ? '${ini.day}–${fin.day} ${ms[ini.month]}'
        : '${ini.day} ${ms[ini.month]} – ${fin.day} ${ms[fin.month]}';
  }

  // ── Solicitud de mantención ──

  Future<void> _solicitarMantencion() async {
    final motivoCtrl = TextEditingController();
    final kmCtrl     = TextEditingController();
    final formKey    = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: const Row(children: [
          Icon(Icons.build_rounded, color: Color(0xFF8B5CF6), size: 20),
          SizedBox(width: 8),
          Text('Solicitar mantención',
              style: TextStyle(color: Colors.white, fontSize: 16)),
        ]),
        content: Form(
          key: formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: motivoCtrl,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Motivo de solicitud *',
                labelStyle: const TextStyle(color: Color(0xFF8FA8C8)),
                hintText: 'Describe el problema o la mantención requerida',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12),
                filled: true,
                fillColor: _bg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF1E3A5F))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF1E3A5F))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF8B5CF6))),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Ingresa el motivo' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: kmCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Kilometraje actual *',
                labelStyle: const TextStyle(color: Color(0xFF8FA8C8)),
                hintText: 'Ej: 85000',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12),
                suffixText: 'km',
                suffixStyle: const TextStyle(color: Color(0xFF8FA8C8)),
                filled: true,
                fillColor: _bg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF1E3A5F))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF1E3A5F))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF8B5CF6))),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Ingresa el kilometraje';
                if (int.tryParse(v.trim()) == null) return 'Solo números';
                return null;
              },
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar',
                style: TextStyle(color: Color(0xFF8FA8C8))),
          ),
          ElevatedButton.icon(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('Enviar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );

    if (ok != true) {
      motivoCtrl.dispose();
      kmCtrl.dispose();
      return;
    }

    try {
      await Supabase.instance.client.from('sol_mantencion').insert({
        'rut_tecnico':    widget.rut,
        'nombre_tecnico': widget.nombreTecnico,
        'patente':        _patente ?? '',
        'tipo':           'correctiva',
        'descripcion':    motivoCtrl.text.trim(),
        'kilometraje':    int.parse(kmCtrl.text.trim()),
        'estado':         'pendiente',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Solicitud enviada a Flota'),
            backgroundColor: Color(0xFF8B5CF6),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    motivoCtrl.dispose();
    kmCtrl.dispose();
  }

  // ── Navegación ──

  void _mostrarHistorialCarga() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _HistorialCargaSheet(
        rutTecnico:        widget.rut,
        saldoActualLitros: _vSaldoLitros,
        saldoActualPesos:  _vSaldoPesos,
        precioLitroRef:    widget.precioLitroRef,
      ),
    );
  }

  void _abrirSemana(_SemanaResumen s) {
    Navigator.push<void>(context, MaterialPageRoute<void>(
      builder: (_) => FordRutasScreen(
        rutTecnico:    widget.rut,
        nombreTecnico: widget.nombreTecnico,
        mes:           s.mesStr,
        precioLitro:   widget.precioLitroRef,
      ),
    ));
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final sinSaldo     = _vSaldoPesos <= 0;
    final colorSaldo   = _colorSaldo(_vSaldoPesos);
    final patenteLabel = (_patente?.isNotEmpty ?? false)
        ? _patente!.toUpperCase()
        : null;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          const Icon(Icons.local_gas_station, color: _accent, size: 18),
          const SizedBox(width: 8),
          Text(
            patenteLabel != null ? 'ESTANQUE $patenteLabel' : 'ESTANQUE',
            style: const TextStyle(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ]),
      ),
      body: RefreshIndicator(
        color: _accent,
        onRefresh: _cargarSemanas,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [

            // ── Saldo disponible (tappeable) ──────────────────────────
            Material(
              color: _surface,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: _mostrarHistorialCarga,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _border)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(children: [
                      const Text('Saldo disponible',
                          style: TextStyle(color: _textDim, fontSize: 12)),
                      const Spacer(),
                      const Icon(Icons.history, color: _textDim, size: 14),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                      CombustibleFormat.formatMoney(_vSaldoPesos),
                      style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: colorSaldo),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      sinSaldo
                          ? 'Sin saldo cargado'
                          : '${_vSaldoLitros.toStringAsFixed(1)} L disponibles',
                      style: TextStyle(
                          fontSize: 13,
                          color: sinSaldo ? Colors.grey[500] : Colors.white70),
                    ),
                    if (!sinSaldo) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: _green.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: _green.withValues(alpha: 0.3))),
                        child: Text(
                          '~${(_vSaldoPesos / widget.precioLitroRef * _rendKmL).toStringAsFixed(0)} km estimados',
                          style: const TextStyle(
                              fontSize: 11,
                              color: _green,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                    if (!_semanasLoad) ...[
                      const SizedBox(height: 14),
                      const Divider(height: 1, color: Color(0xFF1E3A5F)),
                      const SizedBox(height: 10),
                      Row(children: [
                        _resumenCol('Cargado',   _fmtPesos(_totalCargPesos), _green),
                        _dividerV(),
                        _resumenCol('Consumido', _fmtPesos(_totalConsPesos), _orange),
                        _dividerV(),
                        _resumenCol('Saldo',     _fmtPesos(_vSaldoPesos),    colorSaldo),
                      ]),
                    ],
                  ]),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Recorrido por semana ──────────────────────────────────
            Row(children: [
              const Icon(Icons.route, size: 14, color: _accent),
              const SizedBox(width: 6),
              const Text('Recorrido operativo',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
              const Spacer(),
              Text('desde ${_kInicioLabel()}',
                  style: TextStyle(color: _textDim, fontSize: 11)),
            ]),
            const SizedBox(height: 10),

            if (_semanasLoad)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: CircularProgressIndicator(
                      color: _accent, strokeWidth: 2),
                ),
              )
            else if (_semanas.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Sin recorridos registrados desde el ${_kInicioLabel()}.',
                  style: TextStyle(color: _textDim, fontSize: 13),
                ),
              )
            else
              ..._semanas.map(_buildSemanaCard),

            const SizedBox(height: 24),

            // ── Solicitud de combustible adicional ────────────────────
            Row(children: [
              const Icon(Icons.local_gas_station, size: 14, color: Color(0xFFF59E0B)),
              const SizedBox(width: 6),
              const Text('Combustible adicional',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
            ]),
            const SizedBox(height: 10),
            SolCombTecnicoWidget(
              rut:          widget.rut,
              nombre:       widget.nombreTecnico,
              saldoLitros:  _vSaldoLitros,
              saldoPesos:   _vSaldoPesos,
            ),

            const SizedBox(height: 24),

            // ── Solicitud de mantención ───────────────────────────────
            Row(children: [
              const Icon(Icons.build_rounded, size: 14, color: Color(0xFF8B5CF6)),
              const SizedBox(width: 6),
              const Text('Mantención',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
            ]),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _solicitarMantencion,
                icon: const Icon(Icons.build_rounded, size: 18),
                label: const Text('Solicitar mantención'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF8B5CF6),
                  side: const BorderSide(color: Color(0xFF8B5CF6)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSemanaCard(_SemanaResumen s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: _accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => _abrirSemana(s),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _border)),
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Text('Semana ${s.weekNum}',
                        style: const TextStyle(
                            color: _accent,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                    const SizedBox(width: 8),
                    Text(_labelRango(s),
                        style:
                            const TextStyle(color: _textDim, fontSize: 11)),
                  ]),
                  const SizedBox(height: 5),
                  Text(
                    '${s.kmTotal.toStringAsFixed(1)} km  ·  '
                    '${s.litrosTotal.toStringAsFixed(1)} L  ·  '
                    '${_fmtPesos(s.costoTotal)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${s.diasTrabajados} día${s.diasTrabajados == 1 ? '' : 's'} trabajado${s.diasTrabajados == 1 ? '' : 's'}',
                    style:
                        const TextStyle(color: _textDim, fontSize: 11),
                  ),
                ]),
              ),
              const Icon(Icons.chevron_right, color: _textDim, size: 20),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Evento del ledger ─────────────────────────────────────────────────────────

class _Evento {
  final DateTime fecha;
  final String   hora;
  final bool     esCarga;
  final double   litros;
  final double   pesos;
  const _Evento({
    required this.fecha,
    required this.hora,
    required this.esCarga,
    required this.litros,
    required this.pesos,
  });
}

// ── Sheet historial de cargas y consumo ───────────────────────────────────────

class _HistorialCargaSheet extends StatefulWidget {
  final String rutTecnico;
  final double saldoActualLitros;
  final double saldoActualPesos;
  final double precioLitroRef;

  const _HistorialCargaSheet({
    required this.rutTecnico,
    required this.saldoActualLitros,
    required this.saldoActualPesos,
    required this.precioLitroRef,
  });

  @override
  State<_HistorialCargaSheet> createState() => _HistorialCargaSheetState();
}

class _HistorialCargaSheetState extends State<_HistorialCargaSheet> {
  static const Color _accent  = Color(0xFF00D9FF);
  static const Color _border  = Color(0xFF1E3A5F);
  static const Color _textDim = Color(0xFF8FA8C8);
  static const Color _green   = Color(0xFF22C55E);
  static const Color _orange  = Color(0xFFF59E0B);
  static const Color _red     = Color(0xFFEF4444);
  static const Color _surface = Color(0xFF0D1B2A);

  List<_Evento>? _eventos;
  bool    _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final results = await Future.wait([
        // Cargas reales en surtidor desde _kInicio
        Supabase.instance.client
            .from('cargas_combustible')
            .select('fecha, hora, litros, monto')
            .eq('rut_conductor', widget.rutTecnico)
            .gte('fecha', _kInicio)
            .order('fecha', ascending: true),
        // Descuentos por tramo (monedero)
        Supabase.instance.client
            .from('monedero_movimientos')
            .select('fecha_ref, litros')
            .eq('rut_tecnico', widget.rutTecnico)
            .eq('tipo', 'descuento')
            .gte('fecha_ref', _kInicio)
            .order('fecha_ref', ascending: true),
      ]);

      final cargasRows  = results[0] as List;
      final consumoRows = results[1] as List;

      // Carga → un evento por fila
      final cargas = cargasRows.map((r) => _Evento(
        fecha:   DateTime.parse(r['fecha'].toString()),
        hora:    r['hora']?.toString() ?? '',
        esCarga: true,
        litros:  CombustibleFormat.toDouble(r['litros']),
        pesos:   CombustibleFormat.toDouble(r['monto']),
      )).toList();

      // Consumo → agregar por día
      final Map<String, double> porDia = {};
      for (final r in consumoRows) {
        final key = r['fecha_ref'].toString().substring(0, 10);
        porDia[key] = (porDia[key] ?? 0) +
                      CombustibleFormat.toDouble(r['litros']);
      }
      final consumos = porDia.entries.map((e) => _Evento(
        fecha:   DateTime.parse(e.key),
        hora:    '',
        esCarga: false,
        litros:  e.value,
        pesos:   e.value * widget.precioLitroRef,
      )).toList();

      // Mezclar y ordenar (más reciente primero en la vista)
      final todos = [...cargas, ...consumos]
        ..sort((a, b) {
          final c = b.fecha.compareTo(a.fecha); // desc
          if (c != 0) return c;
          return a.esCarga ? -1 : 1; // carga antes que consumo mismo día
        });

      if (mounted) setState(() { _eventos = todos; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _fmt(double v) {
    if (v <= 0) return '\$0';
    final s = v.round().toString();
    final buf = StringBuffer();
    int c = 0;
    for (int k = s.length - 1; k >= 0; k--) {
      if (c > 0 && c % 3 == 0) buf.write('.');
      buf.write(s[k]);
      c++;
    }
    return '\$${buf.toString().split('').reversed.join()}';
  }

  String _fmtFecha(DateTime d) {
    const dd = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    const mm = ['', 'ene', 'feb', 'mar', 'abr', 'may', 'jun',
                'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    return '${dd[d.weekday - 1]} ${d.day} ${mm[d.month]}';
  }

  Color _colorSaldo(double p) {
    if (p <= 0) return Colors.grey;
    if (p > 15000) return _green;
    if (p > 7000)  return _orange;
    return _red;
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: _border,
                borderRadius: BorderRadius.circular(2)),
          ),
        ),
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          child: Row(children: [
            const Icon(Icons.local_gas_station, color: _accent, size: 15),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Cargas y consumo · desde ${_kInicioLabel()}',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(
                '${widget.saldoActualLitros.toStringAsFixed(1)} L',
                style: TextStyle(
                    color: _colorSaldo(widget.saldoActualPesos),
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
              Text(
                _fmt(widget.saldoActualPesos),
                style: TextStyle(
                    color: _colorSaldo(widget.saldoActualPesos),
                    fontSize: 12),
              ),
            ]),
          ]),
        ),
        const Divider(height: 1, color: _border),
        // Body
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(color: _accent, strokeWidth: 2),
          )
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Error: $_error',
                style: const TextStyle(color: _red, fontSize: 13)),
          )
        else
          _buildLedger(),
      ]),
    );
  }

  Widget _buildLedger() {
    final eventos = _eventos ?? [];

    if (eventos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Sin movimientos desde el ${_kInicioLabel()}.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _textDim, fontSize: 13)),
      );
    }

    // Totales para el footer
    final totalCargadoLit  = eventos.where((e) => e.esCarga) .fold(0.0, (s, e) => s + e.litros);
    final totalCargadoPesos = eventos.where((e) => e.esCarga).fold(0.0, (s, e) => s + e.pesos);
    final totalConsumoLit  = eventos.where((e) => !e.esCarga).fold(0.0, (s, e) => s + e.litros);
    final totalConsumoPesos = totalConsumoLit * widget.precioLitroRef;

    return Flexible(
      child: Column(children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            itemCount: eventos.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (_, i) => eventos[i].esCarga
                ? _buildFilaCarga(eventos[i])
                : _buildFilaConsumo(eventos[i]),
          ),
        ),
        // Footer totales
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFF1E3A5F))),
          ),
          child: Column(children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total cargado',
                    style: TextStyle(color: _textDim, fontSize: 12)),
                Text(
                  '+${totalCargadoLit.toStringAsFixed(1)} L  ·  +${_fmt(totalCargadoPesos)}',
                  style: const TextStyle(
                      color: _green, fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total consumido',
                    style: TextStyle(color: _textDim, fontSize: 12)),
                Text(
                  '-${totalConsumoLit.toStringAsFixed(1)} L  ·  -${_fmt(totalConsumoPesos)}',
                  style: const TextStyle(
                      color: _orange, fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0xFF1E3A5F)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Saldo actual',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                Text(
                  '${widget.saldoActualLitros.toStringAsFixed(1)} L  ·  ${_fmt(widget.saldoActualPesos)}',
                  style: TextStyle(
                      color: _colorSaldo(widget.saldoActualPesos),
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                ),
              ],
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildFilaCarga(_Evento e) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
        color: _green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _green.withValues(alpha: 0.3))),
    child: Row(children: [
      const Icon(Icons.battery_charging_full, color: _green, size: 15),
      const SizedBox(width: 8),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_fmtFecha(e.fecha),
              style: const TextStyle(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
          if (e.hora.isNotEmpty)
            Text('Carga · ${e.hora}',
                style: const TextStyle(color: _textDim, fontSize: 10)),
        ]),
      ),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('+${e.litros.toStringAsFixed(2)} L',
            style: const TextStyle(
                color: _green, fontWeight: FontWeight.bold, fontSize: 13)),
        Text('+${_fmt(e.pesos)}',
            style: const TextStyle(color: _green, fontSize: 11)),
      ]),
    ]),
  );

  Widget _buildFilaConsumo(_Evento e) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border)),
    child: Row(children: [
      const Icon(Icons.directions_car_outlined, color: _textDim, size: 15),
      const SizedBox(width: 8),
      Expanded(
        child: Text(_fmtFecha(e.fecha),
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
      ),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('-${e.litros.toStringAsFixed(2)} L',
            style: const TextStyle(
                color: _orange, fontWeight: FontWeight.w600, fontSize: 12)),
        Text('-${_fmt(e.pesos)}',
            style: const TextStyle(color: _textDim, fontSize: 10)),
      ]),
    ]),
  );
}

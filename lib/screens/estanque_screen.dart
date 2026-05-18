import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/models/ford_ruta.dart';
import 'package:agente_desconexiones/screens/combustible_screen.dart';
import 'package:agente_desconexiones/screens/ford_rutas_screen.dart';
import 'package:agente_desconexiones/services/ford_api_service.dart';
import 'package:agente_desconexiones/widgets/combustible_format.dart';

class EstanqueScreen extends StatefulWidget {
  final String rut;
  final String nombreTecnico;
  final double precioLitroRef;
  // Pre-loaded values from FlotaCard for instant first render
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
  static const Color _surface  = Color(0xFF0D1B2A);
  static const Color _bg       = Color(0xFF0A1628);
  static const Color _accent   = Color(0xFF00D9FF);
  static const Color _border   = Color(0xFF1E3A5F);
  static const Color _textDim  = Color(0xFF8FA8C8);
  static const Color _orange   = Color(0xFFF59E0B);
  static const Color _green    = Color(0xFF22C55E);
  static const double _rendimientoKmL = 12.0;

  late double _saldoPesos;
  late double _saldoLitros;
  late String? _patente;

  Map<DateTime, List<FordDiaRuta>> _semanas = {};
  bool    _fordLoading  = true;
  bool    _fordSinDatos = false;
  String? _fordError;

  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  @override
  void initState() {
    super.initState();
    _saldoPesos  = widget.initialSaldoPesos;
    _saldoLitros = widget.initialSaldoLitros;
    _patente     = widget.initialPatente;
    _suscribirRealtime();
    _cargarFord();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _suscribirRealtime() {
    _sub = Supabase.instance.client
        .from('monedero_combustible')
        .stream(primaryKey: ['rut_tecnico'])
        .eq('rut_tecnico', widget.rut)
        .listen((data) {
      if (data.isEmpty || !mounted) return;
      final row = data.first;
      setState(() {
        _saldoPesos  = CombustibleFormat.toDouble(row['saldo_pesos']);
        _saldoLitros = CombustibleFormat.toDouble(row['saldo_litros']);
        _patente     = row['patente']?.toString();
      });
    });
  }

  Future<void> _cargarFord() async {
    if (mounted) setState(() { _fordLoading = true; _fordError = null; });
    try {
      final semanas = await FordApiService()
          .getRutasPorSemana(widget.rut, maxSemanas: 2);
      if (mounted) {
        setState(() {
          _semanas      = semanas;
          _fordLoading  = false;
          _fordSinDatos = semanas.isEmpty;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _fordLoading  = false;
          _fordSinDatos = true;
          _fordError    = e.toString();
        });
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────

  double _kmSemana(List<FordDiaRuta> dias) =>
      dias.fold(0.0, (s, d) => s + d.kmTotal);
  double _litrosSemana(List<FordDiaRuta> dias) =>
      _kmSemana(dias) / _rendimientoKmL;
  double _costoSemana(List<FordDiaRuta> dias) =>
      _litrosSemana(dias) * widget.precioLitroRef;

  double get _totalLitros =>
      _semanas.values.fold(0.0, (s, d) => s + _litrosSemana(d));
  double get _totalCosto => _totalLitros * widget.precioLitroRef;

  Color _colorSaldo(double p) {
    if (p <= 0) return Colors.grey;
    if (p > 15000) return _green;
    if (p > 7000) return _orange;
    return const Color(0xFFEF4444);
  }

  String _labelSemana(DateTime ws) {
    const ms = ['', 'ene', 'feb', 'mar', 'abr', 'may', 'jun',
                 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    final end = ws.add(const Duration(days: 5));
    return ws.month == end.month
        ? '${ws.day}–${end.day} ${ms[ws.month]}'
        : '${ws.day} ${ms[ws.month]} – ${end.day} ${ms[end.month]}';
  }

  String _formatPesos(double v) {
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

  void _abrirRecorridos() {
    Navigator.push<void>(context, MaterialPageRoute<void>(
      builder: (_) => FordRutasScreen(
        rutTecnico: widget.rut,
        nombreTecnico: widget.nombreTecnico,
        mes: _semanas.keys.isNotEmpty
            ? _semanas.keys
                .reduce((a, b) => a.isAfter(b) ? a : b)
                .toIso8601String()
                .substring(0, 7)
            : '',
        precioLitro: widget.precioLitroRef,
      ),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sinSaldo     = _saldoPesos <= 0;
    final colorSaldo   = _colorSaldo(_saldoPesos);
    final patenteLabel = (_patente != null && _patente!.isNotEmpty)
        ? _patente!.toUpperCase()
        : null;
    final titulo = patenteLabel != null ? 'ESTANQUE $patenteLabel' : 'ESTANQUE';

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
          Text(titulo,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
        ]),
        actions: const [],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Balance ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text('Saldo disponible',
                  style: const TextStyle(color: _textDim, fontSize: 12)),
              const SizedBox(height: 8),
              Text(
                CombustibleFormat.formatMoney(_saldoPesos),
                style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: colorSaldo),
              ),
              const SizedBox(height: 4),
              Text(
                sinSaldo
                    ? 'Sin saldo cargado'
                    : '${_saldoLitros.toStringAsFixed(1)} L disponibles',
                style: TextStyle(
                    fontSize: 13,
                    color:
                        sinSaldo ? Colors.grey[500] : Colors.white70),
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
                    '~${(_saldoPesos / widget.precioLitroRef * _rendimientoKmL).toStringAsFixed(0)} km estimados',
                    style: const TextStyle(
                        fontSize: 11,
                        color: _green,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ]),
          ),

          const SizedBox(height: 14),

          // ── Consumo operativo ──
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border)),
            child: _fordLoading
                ? const SizedBox(
                    height: 64,
                    child: Center(
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _accent)),
                    ))
                : _fordSinDatos
                    ? _buildFordSinDatos()
                    : _buildConsumoSemanal(),
          ),

          // ── Ver recorridos ──
          if (!_fordSinDatos) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _fordLoading ? null : _abrirRecorridos,
              icon: const Icon(Icons.map_outlined, size: 16),
              label: const Text('Ver recorridos por semana',
                  style: TextStyle(fontSize: 13)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _accent,
                side: const BorderSide(color: _border),
                padding: const EdgeInsets.symmetric(vertical: 12),
                minimumSize: const Size(double.infinity, 0),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Consumo widgets ───────────────────────────────────────────

  Widget _buildFordSinDatos() {
    final tieneError = _fordError != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(
            tieneError ? Icons.error_outline : Icons.route,
            size: 14,
            color: tieneError ? const Color(0xFFEF4444) : _textDim,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              tieneError ? 'Error al cargar rutas' : 'Sin rutas registradas',
              style: TextStyle(
                color: tieneError ? const Color(0xFFEF4444) : _textDim,
                fontSize: 12,
              ),
            ),
          ),
        ]),
        if (tieneError) ...[
          const SizedBox(height: 6),
          Text(
            _fordError!,
            style: const TextStyle(color: Color(0xFF8FA8C8), fontSize: 10),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _cargarFord,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: _border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.refresh, size: 12, color: _accent),
              SizedBox(width: 4),
              Text('Reintentar', style: TextStyle(color: _accent, fontSize: 11)),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildConsumoSemanal() {
    final weeks = _semanas.entries.toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        Icon(Icons.local_gas_station, size: 13, color: _accent),
        SizedBox(width: 4),
        Text('CONSUMO OPERATIVO',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
      ]),
      const SizedBox(height: 10),
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < weeks.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _buildSemanaCol(
                  semanaNum: i + 1,
                  weekStart: weeks[i].key,
                  dias: weeks[i].value,
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 10),
      const Divider(height: 1, color: _border),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text('${_totalLitros.toStringAsFixed(1)} L consumidos',
                style: const TextStyle(
                    color: _orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
            Text('Equivalente a ${_formatPesos(_totalCosto)}',
                style:
                    const TextStyle(color: _textDim, fontSize: 11)),
          ]),
        ),
        if (_saldoPesos > 0)
          _buildBarraConsumo(
              (_totalCosto / _saldoPesos).clamp(0.0, 1.0)),
      ]),
    ]);
  }

  Widget _buildSemanaCol({
    required int semanaNum,
    required DateTime weekStart,
    required List<FordDiaRuta> dias,
  }) {
    final km     = _kmSemana(dias);
    final litros = _litrosSemana(dias);
    final costo  = _costoSemana(dias);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: _accent.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _border)),
      child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Semana $semanaNum',
            style: const TextStyle(
                color: _accent,
                fontWeight: FontWeight.bold,
                fontSize: 11)),
        Text(_labelSemana(weekStart),
            style: const TextStyle(color: _textDim, fontSize: 9)),
        const SizedBox(height: 8),
        Text('${km.toStringAsFixed(1)} km',
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13)),
        const SizedBox(height: 2),
        Text('${litros.toStringAsFixed(1)} L',
            style:
                const TextStyle(color: _orange, fontSize: 12)),
        const SizedBox(height: 2),
        Text(_formatPesos(costo),
            style:
                const TextStyle(color: _textDim, fontSize: 11)),
        const SizedBox(height: 4),
        Text('${dias.length} días trabajados',
            style: const TextStyle(color: _textDim, fontSize: 9)),
      ]),
    );
  }

  Widget _buildBarraConsumo(double pct) {
    final color = pct > 0.8
        ? const Color(0xFFEF4444)
        : pct > 0.5
            ? _orange
            : _green;
    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text('${(pct * 100).toStringAsFixed(0)}% del estanque',
          style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.bold)),
      const SizedBox(height: 3),
      SizedBox(
        width: 80,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
              value: pct,
              backgroundColor: _border,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6),
        ),
      ),
    ]);
  }
}

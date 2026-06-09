import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/models/ford_ruta.dart';
import 'package:agente_desconexiones/screens/estanque_screen.dart';
import 'package:agente_desconexiones/services/supervisor_rutas_service.dart';
import 'package:agente_desconexiones/widgets/combustible_format.dart';

const _kInicioFlotaSup = '2026-05-18';

/// Card Flota para supervisores (misma lógica que técnico, rutas desde GPS).
class FlotaSupervisorCard extends StatefulWidget {
  const FlotaSupervisorCard({super.key});

  @override
  State<FlotaSupervisorCard> createState() => _FlotaSupervisorCardState();
}

class _FlotaSupervisorCardState extends State<FlotaSupervisorCard> {
  static const Color _green = Color(0xFF22C55E);
  static const Color _orange = Color(0xFFF59E0B);
  static const double _rendimientoKmL = 12.0;

  double _saldoPesos = 0;
  double _saldoLitros = 0;
  String? _patente;
  bool _loading = true;
  String? _rut;
  String? _nombreSupervisor;
  double _precioLitroRef = 1500;

  StreamSubscription<List<Map<String, dynamic>>>? _monederoSub;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  @override
  void dispose() {
    _monederoSub?.cancel();
    super.dispose();
  }

  Future<void> _cargarTodo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rut = prefs.getString('rut_supervisor') ??
          prefs.getString('rut_tecnico') ??
          prefs.getString('user_rut');
      _nombreSupervisor =
          prefs.getString('nombre_supervisor') ??
              prefs.getString('user_nombre') ??
              'Supervisor';

      if (rut == null || rut.isEmpty) {
        if (mounted) {
          setState(() {
            _rut = null;
            _loading = false;
          });
        }
        return;
      }

      await _cargarParametroPrecio();
      await _cargarMonedero(rut);

      if (mounted) {
        setState(() {
          _rut = rut;
          _loading = false;
        });
      }

      _suscribirRealtime(rut);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cargarParametroPrecio() async {
    try {
      final row = await Supabase.instance.client
          .from('parametros_combustible')
          .select()
          .limit(1)
          .maybeSingle();
      if (row != null) {
        final p = CombustibleFormat.toDouble(
            row['precio_litro'] ?? row['precio_litro_referencia']);
        if (p > 0) _precioLitroRef = p;
      }
    } catch (_) {}
  }

  Future<void> _cargarMonedero(String rut) async {
    try {
      final row = await Supabase.instance.client
          .from('monedero_combustible')
          .select('patente')
          .eq('rut_tecnico', rut)
          .maybeSingle();
      if (row != null) _patente = row['patente']?.toString();

      final inicio = DateTime.parse(_kInicioFlotaSup);
      final results = await Future.wait<dynamic>([
        Supabase.instance.client
            .from('cargas_combustible')
            .select('litros, monto')
            .eq('rut_conductor', rut)
            .gte('fecha', _kInicioFlotaSup),
        SupervisorRutasService().getRutasDelSupervisor(rut),
      ]);

      final cargaRows = results[0] as List;
      final rutas = results[1] as List<FordDiaRuta>;

      double cargLit = 0, cargPesos = 0;
      for (final r in cargaRows) {
        cargLit += CombustibleFormat.toDouble(r['litros']);
        cargPesos += CombustibleFormat.toDouble(r['monto']);
      }

      double conLit = 0;
      for (final dia in rutas) {
        final f = dia.fecha;
        if (f == null || f.isBefore(inicio)) continue;
        conLit += dia.kmTotal / _rendimientoKmL;
      }
      final conPesos = conLit * _precioLitroRef;

      _saldoLitros = (cargLit - conLit).clamp(0.0, double.infinity);
      _saldoPesos = (cargPesos - conPesos).clamp(0.0, double.infinity);
    } catch (_) {}
  }

  void _suscribirRealtime(String rut) {
    _monederoSub?.cancel();
    _monederoSub = Supabase.instance.client
        .from('monedero_combustible')
        .stream(primaryKey: ['rut_tecnico'])
        .eq('rut_tecnico', rut)
        .listen((data) {
      if (data.isEmpty || !mounted) return;
      setState(() => _patente = data.first['patente']?.toString());
    });
  }

  Color _colorSaldo(double p) {
    if (p <= 0) return Colors.grey;
    if (p > 15000) return _green;
    if (p > 7000) return _orange;
    return const Color(0xFFEF4444);
  }

  void _abrirEstanque() {
    if (_rut == null) return;
    Navigator.push<void>(context, MaterialPageRoute<void>(
      builder: (_) => EstanqueScreen(
        rut: _rut!,
        nombreTecnico: _nombreSupervisor ?? 'Supervisor',
        precioLitroRef: _precioLitroRef,
        initialSaldoPesos: _saldoPesos,
        initialSaldoLitros: _saldoLitros,
        initialPatente: _patente,
        esSupervisor: true,
      ),
    ));
  }

  void _mostrarTagSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A2535),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lock_rounded,
                size: 56, color: Colors.white.withValues(alpha: 0.85)),
            const SizedBox(height: 16),
            const Text('TAG en camino — disponible muy pronto',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Entendido')),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorSaldo = _colorSaldo(_saldoPesos);
    final sinSaldo = _saldoPesos <= 0;
    final patenteLabel =
        (_patente != null && _patente!.isNotEmpty) ? _patente!.toUpperCase() : null;

    return Card(
      elevation: 2,
      color: const Color(0xFF0D1B2A),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.directions_car, color: Colors.green[700], size: 22),
                const SizedBox(width: 8),
                Text('Flota',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[400])),
              ]),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              )
            else if (_rut == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('Sin sesión de supervisor.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[500], fontSize: 13)),
              )
            else
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _abrirEstanque,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: const Color(0xFF252525),
                              borderRadius: BorderRadius.circular(8)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                const Icon(Icons.local_gas_station,
                                    size: 14, color: Color(0xFF00D9FF)),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    patenteLabel != null
                                        ? 'ESTANQUE $patenteLabel'
                                        : 'ESTANQUE',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ]),
                              const SizedBox(height: 8),
                              Text(
                                CombustibleFormat.formatMoney(_saldoPesos),
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: colorSaldo),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                sinSaldo
                                    ? 'Sin saldo cargado'
                                    : '${_saldoLitros.toStringAsFixed(1)} L disponibles',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: sinSaldo
                                        ? Colors.grey[500]
                                        : Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: _mostrarTagSheet,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: const Color(0xFF252525),
                              borderRadius: BorderRadius.circular(8)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(children: [
                                Icon(Icons.lock, size: 14, color: Colors.white),
                                SizedBox(width: 4),
                                Text('TAG',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white)),
                              ]),
                              const SizedBox(height: 8),
                              Text('Próximo',
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[500])),
                              const SizedBox(height: 4),
                              Text('Disponible pronto',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey[600])),
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

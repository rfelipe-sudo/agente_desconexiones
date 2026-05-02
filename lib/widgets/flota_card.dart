import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/constants/app_colors.dart';
import 'package:agente_desconexiones/screens/combustible_screen.dart';
import 'package:agente_desconexiones/widgets/combustible_format.dart';

/// Card "Flota" en Tu Mes — misma estructura visual que Calidad / Producción.
class FlotaCard extends StatefulWidget {
  const FlotaCard({super.key});

  @override
  State<FlotaCard> createState() => _FlotaCardState();
}

class _FlotaCardState extends State<FlotaCard> {
  static const Color _subCardCerrada = Color(0xFF252525);

  double _saldoPesos = 0;
  double _saldoLitros = 0;
  bool _loading = true;
  String? _rut;
  double _precioLitroRef = 1500;

  StreamSubscription<List<Map<String, dynamic>>>? _monederoSub;

  @override
  void initState() {
    super.initState();
    _cargarMonedero();
  }

  @override
  void dispose() {
    _monederoSub?.cancel();
    super.dispose();
  }

  double _kmOperacionales(double pesos) {
    if (pesos <= 0) return 0;
    final p = _precioLitroRef > 0 ? _precioLitroRef : 1500;
    return pesos / p * 13;
  }

  Future<void> _cargarParametroPrecio() async {
    try {
      final param = await Supabase.instance.client
          .from('parametros_combustible')
          .select()
          .limit(1)
          .maybeSingle();
      if (param != null) {
        final p = CombustibleFormat.toDouble(
          param['precio_litro'] ?? param['precio_litro_referencia'],
        );
        if (p > 0) _precioLitroRef = p;
      }
    } catch (e) {
      print('[Combustible] FlotaCard parametros: $e');
    }
  }

  void _suscribirRealtime(String rut) {
    _monederoSub?.cancel();
    print('[Combustible] FlotaCard Realtime monedero_combustible rut=$rut');
    _monederoSub = Supabase.instance.client
        .from('monedero_combustible')
        .stream(primaryKey: ['rut_tecnico'])
        .eq('rut_tecnico', rut)
        .listen((data) {
      if (data.isEmpty || !mounted) return;
      final row = data.first;
      setState(() {
        _saldoPesos = CombustibleFormat.toDouble(row['saldo_pesos']);
        _saldoLitros = CombustibleFormat.toDouble(row['saldo_litros']);
      });
    });
  }

  Future<void> _cargarMonedero() async {
    print('[Combustible] FlotaCard._cargarMonedero inicio');
    try {
      final prefs = await SharedPreferences.getInstance();
      final rut = prefs.getString('rut_tecnico');
      if (rut == null || rut.isEmpty) {
        print('[Combustible] FlotaCard sin RUT');
        if (mounted) {
          setState(() {
            _rut = null;
            _loading = false;
            _saldoPesos = 0;
            _saldoLitros = 0;
          });
        }
        return;
      }

      await _cargarParametroPrecio();

      Map<String, dynamic>? mon;
      try {
        mon = await Supabase.instance.client
            .from('monedero_combustible')
            .select('saldo_pesos, saldo_litros')
            .eq('rut_tecnico', rut)
            .maybeSingle();
        print('[Combustible] FlotaCard monedero inicial: $mon');
      } catch (e, st) {
        print('[Combustible] FlotaCard monedero: $e\n$st');
      }

      if (!mounted) return;
      setState(() {
        _rut = rut;
        if (mon != null) {
          _saldoPesos = CombustibleFormat.toDouble(mon['saldo_pesos']);
          _saldoLitros = CombustibleFormat.toDouble(mon['saldo_litros']);
        } else {
          _saldoPesos = 0;
          _saldoLitros = 0;
        }
        _loading = false;
      });

      _suscribirRealtime(rut);
    } catch (e, st) {
      print('[Combustible] FlotaCard ERROR: $e\n$st');
      if (mounted) {
        setState(() {
          _loading = false;
          _saldoPesos = 0;
          _saldoLitros = 0;
        });
      }
    }
  }

  Color _colorSemaforoPesos(double pesos) {
    if (pesos <= 0) return Colors.grey;
    if (pesos > 15000) return const Color(0xFF22C55E);
    if (pesos > 7000) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  void _mostrarTagSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_rounded,
                size: 56,
                color: Colors.white.withValues(alpha: 0.85),
              ),
              const SizedBox(height: 16),
              const Text(
                'TAG en camino — disponible muy pronto',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'La gestión de peajes TAG estará disponible muy pronto.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Entendido'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pesos = _saldoPesos;
    final litros = _saldoLitros;
    final sinSaldo = pesos <= 0;
    final colorValor = _colorSemaforoPesos(pesos);
    final kmOp = _kmOperacionales(pesos);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.directions_car, color: Colors.green[700], size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Flota',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[400],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (_rut == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Sin RUT de técnico. Completa tu registro.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[500], fontSize: 13),
                ),
              )
            else
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          print('[Combustible] FlotaCard → CombustibleScreen');
                          Navigator.push<void>(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => const CombustibleScreen(),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _subCardCerrada,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.local_gas_station,
                                    size: 14,
                                    color: Colors.white.withValues(alpha: 0.9),
                                  ),
                                  const SizedBox(width: 4),
                                  const Expanded(
                                    child: Text(
                                      'COMBUSTIBLE',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                CombustibleFormat.formatMoney(pesos),
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: colorValor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                sinSaldo
                                    ? 'Sin saldo cargado'
                                    : '${litros.toStringAsFixed(1)} L disponibles',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: sinSaldo
                                      ? Colors.grey[500]
                                      : Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey[800],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  sinSaldo
                                      ? '—'
                                      : '${kmOp.toStringAsFixed(0)} km operacionales',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: sinSaldo
                                        ? Colors.grey[600]
                                        : const Color(0xFF22C55E),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () => _mostrarTagSheet(context),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _subCardCerrada,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.lock, size: 14, color: Colors.white),
                                  const SizedBox(width: 4),
                                  const Expanded(
                                    child: Text(
                                      'TAG',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Próximo',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[500],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Disponible pronto',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey[700],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Próximamente',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.grey[400],
                                  ),
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

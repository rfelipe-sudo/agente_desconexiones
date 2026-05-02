import 'package:flutter/material.dart';

import 'package:agente_desconexiones/widgets/combustible_format.dart';

/// Monedero operativo: saldo en pesos (semáforo), barra 0–$30.000, km restantes.
class MonederoCard extends StatelessWidget {
  const MonederoCard({
    super.key,
    required this.data,
    this.kmRestantesOverride,
  });

  /// `out_saldo_pesos`, `out_saldo_litros`, `out_precio_litro`; opcional `out_km_restantes` del RPC.
  final Map<String, dynamic> data;

  /// Si viene del RPC, usar; si no, saldo_pesos/1500*13.
  final double? kmRestantesOverride;

  static const double _maxPesosBarra = 30000;

  Color _colorPesos(double pesos) {
    if (pesos <= 0) return Colors.grey;
    if (pesos > 15000) return const Color(0xFF22C55E);
    if (pesos > 7000) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  double _kmRestantes(double pesos, double? rpcKm) {
    if (rpcKm != null && rpcKm > 0) return rpcKm;
    if (pesos <= 0) return 0;
    return pesos / 1500 * 13;
  }

  @override
  Widget build(BuildContext context) {
    final pesos = CombustibleFormat.toDouble(data['out_saldo_pesos']);
    final litros = CombustibleFormat.toDouble(data['out_saldo_litros']);
    var precioLitro = CombustibleFormat.toDouble(data['out_precio_litro']);
    if (precioLitro <= 0) precioLitro = 1500;

    final rpcKm = data['out_km_restantes'] != null
        ? CombustibleFormat.toDouble(data['out_km_restantes'])
        : null;
    final kmRest =
        kmRestantesOverride ?? _kmRestantes(pesos, rpcKm);

    final colorVal = _colorPesos(pesos);
    final fracBarra = (pesos / _maxPesosBarra).clamp(0.0, 1.0);
    final pct = (fracBarra * 100).round();

    final pesosFmt = CombustibleFormat.formatMoney(pesos);
    final precioTxt = CombustibleFormat.formatMoney(precioLitro);

    final sinSaldo = pesos <= 0 && litros <= 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🛢️', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(
                'Monedero Operativo',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[300],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              pesosFmt,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: sinSaldo ? Colors.grey : colorVal,
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (sinSaldo)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Sin saldo cargado — el coordinador de flota cargará tu combustible operativo',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                  height: 1.35,
                ),
              ),
            )
          else
            Center(
              child: Text(
                '${litros.toStringAsFixed(1)} L disponibles',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
              ),
            ),
          if (!sinSaldo) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: fracBarra,
                minHeight: 10,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                color: colorVal,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  r'$0',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                Text(
                  '$pct%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorVal,
                  ),
                ),
                Text(
                  CombustibleFormat.formatMoney(_maxPesosBarra),
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '📍 ${kmRest.toStringAsFixed(0)} km operacionales restantes',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF22C55E),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '⛽ $precioTxt/L · 13 km/L',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[500],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

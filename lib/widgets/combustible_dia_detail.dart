import 'package:flutter/material.dart';

import 'package:agente_desconexiones/widgets/combustible_format.dart';

/// Detalle de un día: tramos operativos, trayecto personal y totalizador.
class CombustibleDiaDetail extends StatelessWidget {
  const CombustibleDiaDetail({
    super.key,
    required this.fechaLabel,
    required this.diaRow,
    required this.tramos,
    this.rpcRow,
    this.kmTrayectoFijo = 40,
    this.precioLitro = 1500,
    this.rendimientoKm = 13,
    this.keySeccionOperativo,
    this.keySeccionTrayecto,
  });

  final String fechaLabel;
  final Map<String, dynamic>? diaRow;
  final List<Map<String, dynamic>> tramos;
  final Map<String, dynamic>? rpcRow;
  final double kmTrayectoFijo;
  final double precioLitro;
  final double rendimientoKm;
  final Key? keySeccionOperativo;
  final Key? keySeccionTrayecto;

  static double _pickDouble(Map<String, dynamic>? m, List<String> keys) {
    if (m == null) return 0;
    for (final k in keys) {
      if (m.containsKey(k)) {
        return CombustibleFormat.toDouble(m[k]);
      }
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final kmOp = _pickDouble(diaRow, ['km_entre_ots', 'km_operativo']);
    final litrosOp = _pickDouble(diaRow, ['litros_operativo']);
    final costoOp = _pickDouble(diaRow, ['costo_operativo']);

    final legs = TrayectoDiaLegs.fromRpcYDia(
      rpc: rpcRow,
      diaRow: diaRow,
      kmTrayectoFijo: kmTrayectoFijo,
      precioLitro: precioLitro,
      rendimientoKm: rendimientoKm,
    );

    final kmTotal = _pickDouble(diaRow, ['km_total', 'km_totales']) != 0
        ? _pickDouble(diaRow, ['km_total', 'km_totales'])
        : kmOp + legs.kmTotal;
    final litrosTotal = _pickDouble(diaRow, ['litros_total', 'litros_totales']) != 0
        ? _pickDouble(diaRow, ['litros_total', 'litros_totales'])
        : litrosOp + legs.litrosTotal;
    final costoTotalDia = costoOp + legs.costoTotal;

    final tieneTramos = tramos.isNotEmpty;
    final muestraTotalOp = tieneTramos || kmOp > 0 || litrosOp > 0 || costoOp > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fechaLabel,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Column(
            key: keySeccionOperativo,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _seccionTitulo('🛣️ Uso Operativo'),
              const SizedBox(height: 8),
              if (!tieneTramos)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Sin movimientos registrados para este día',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.55),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                )
              else
                ...tramos.map(_filaTramo),
              if (muestraTotalOp) ...[
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'Total:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${CombustibleFormat.formatKm(kmOp > 0 ? kmOp : _sumTramosKm(tramos))} km | '
                          '${CombustibleFormat.formatLitros(litrosOp > 0 ? litrosOp : _sumTramosLitros(tramos))} L | '
                          '${CombustibleFormat.formatMoney(costoOp > 0 ? costoOp : _sumTramosCosto(tramos))}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          Container(height: 1, color: Colors.white.withOpacity(0.12)),
          const SizedBox(height: 18),
          Container(
            key: keySeccionTrayecto,
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _seccionTitulo('🏠 Trayecto personal (tú pagas)'),
                const SizedBox(height: 10),
                _filaTrayectoLeg(
                  icon: Icons.wb_sunny_outlined,
                  titulo: 'Casa → 1ª visita (AM)',
                  subtitulo: 'Se registra al iniciar el primer trabajo de la mañana',
                  km: legs.kmIda,
                  lit: legs.litrosIda,
                  costo: legs.costoIda,
                ),
                const SizedBox(height: 12),
                _filaTrayectoLeg(
                  icon: Icons.nightlight_round,
                  titulo: 'Última visita → Casa',
                  subtitulo: 'Se registra al cerrar la última OT del día',
                  km: legs.kmVuelta,
                  lit: legs.litrosVuelta,
                  costo: legs.costoVuelta,
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'Total trayecto:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${CombustibleFormat.formatKm(legs.kmTotal)} km | '
                          '${CombustibleFormat.formatLitros(legs.litrosTotal)} L | '
                          '${CombustibleFormat.formatMoney(legs.costoTotal)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Distancia estimada. Se actualizará con tu domicilio registrado.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.45),
                    fontStyle: FontStyle.italic,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _totalizadorDia(
            kmTotal: kmTotal,
            litrosTotal: litrosTotal,
            costoOp: costoOp,
            costoTray: legs.costoTotal,
            costoTotalDia: costoTotalDia,
          ),
        ],
      ),
    );
  }

  Widget _seccionTitulo(String t) => Text(
        t,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.white.withOpacity(0.9),
        ),
      );

  Widget _filaTrayectoLeg({
    required IconData icon,
    required String titulo,
    required String subtitulo,
    required double km,
    required double lit,
    required double costo,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, color: Colors.teal.shade300, size: 22),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitulo,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withOpacity(0.45),
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${CombustibleFormat.formatKm(km)} km | '
                '${CombustibleFormat.formatLitros(lit)} L | '
                '${CombustibleFormat.formatMoney(costo)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.teal.shade200,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static double _sumTramosKm(List<Map<String, dynamic>> t) =>
      t.fold<double>(0, (a, m) => a + CombustibleFormat.toDouble(m['km_tramo']));
  static double _sumTramosLitros(List<Map<String, dynamic>> t) =>
      t.fold<double>(0, (a, m) => a + CombustibleFormat.toDouble(m['litros_tramo']));
  static double _sumTramosCosto(List<Map<String, dynamic>> t) =>
      t.fold<double>(0, (a, m) => a + CombustibleFormat.toDouble(m['costo_tramo']));

  Widget _filaTramo(Map<String, dynamic> m) {
    final desde = m['orden_desde']?.toString() ?? '—';
    final hasta = m['orden_hasta']?.toString() ?? '—';
    final hora = m['hora_fin_hasta']?.toString() ?? '';
    final km = CombustibleFormat.toDouble(m['km_tramo']);
    final lit = CombustibleFormat.toDouble(m['litros_tramo']);
    final costo = CombustibleFormat.toDouble(m['costo_tramo']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.swap_horiz_rounded,
              size: 22,
              color: Colors.blue.shade300,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'OT $desde  →  OT $hasta',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  hora.isNotEmpty
                      ? '$hora  ·  ${CombustibleFormat.formatKm(km)} km  ·  '
                          '${CombustibleFormat.formatLitros(lit)} L  ·  '
                          '${CombustibleFormat.formatMoney(costo)}'
                      : '${CombustibleFormat.formatKm(km)} km  ·  '
                          '${CombustibleFormat.formatLitros(lit)} L  ·  '
                          '${CombustibleFormat.formatMoney(costo)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalizadorDia({
    required double kmTotal,
    required double litrosTotal,
    required double costoOp,
    required double costoTray,
    required double costoTotalDia,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A3E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumen del día',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          _filaResumen('Km totales:', '${CombustibleFormat.formatKm(kmTotal)} km'),
          _filaResumen('Litros totales:', '${CombustibleFormat.formatLitros(litrosTotal)} L'),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Divider(color: Colors.white.withOpacity(0.15), height: 1),
          ),
          _filaResumen('Operativo (empresa):', CombustibleFormat.formatMoney(costoOp)),
          _filaResumen('Trayecto (tuyo):', CombustibleFormat.formatMoney(costoTray)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Divider(color: Colors.white.withOpacity(0.15), height: 1),
          ),
          _filaResumen(
            'Total día:',
            CombustibleFormat.formatMoney(costoTotalDia),
            destacado: true,
          ),
        ],
      ),
    );
  }

  Widget _filaResumen(String k, String v, {bool destacado = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              k,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withOpacity(destacado ? 0.95 : 0.7),
                fontWeight: destacado ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          Text(
            v,
            style: TextStyle(
              fontSize: 13,
              fontWeight: destacado ? FontWeight.bold : FontWeight.w600,
              color: destacado ? Colors.white : Colors.white.withOpacity(0.9),
            ),
          ),
        ],
      ),
    );
  }
}

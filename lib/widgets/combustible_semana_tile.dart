import 'package:flutter/material.dart';

import 'package:agente_desconexiones/screens/combustible_dia_detalle_screen.dart';
import 'package:agente_desconexiones/widgets/combustible_format.dart';

/// Semana del mes con totales; al expandir, filas de días → [CombustibleDiaDetalleScreen].
class CombustibleSemanaTile extends StatelessWidget {
  const CombustibleSemanaTile({
    super.key,
    required this.rutTecnico,
    required this.semanaIndex,
    required this.anno,
    required this.mes,
    required this.diaInicio,
    required this.diaFin,
    required this.diasOrdenados,
  });

  final String rutTecnico;
  final int semanaIndex;
  final int anno;
  final int mes;
  final int diaInicio;
  final int diaFin;
  final List<Map<String, dynamic>> diasOrdenados;

  static double _pickSum(
    Iterable<Map<String, dynamic>> rows,
    List<String> keys,
  ) {
    var s = 0.0;
    for (final r in rows) {
      for (final k in keys) {
        if (r.containsKey(k)) {
          s += CombustibleFormat.toDouble(r[k]);
          break;
        }
      }
    }
    return s;
  }

  String _fechaKey(Map<String, dynamic> row) {
    final f = row['fecha'];
    if (f == null) return '';
    if (f is DateTime) {
      final d = f;
      return '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
    }
    return f.toString().split('T').first;
  }

  static const _mesesCorto = [
    '',
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
  ];

  String _labelFilaDia(String ymd) {
    try {
      final d = DateTime.parse(ymd);
      const dias = [
        'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo',
      ];
      return '${dias[d.weekday - 1]} ${d.day} ${_mesesCorto[d.month]}';
    } catch (_) {
      return ymd;
    }
  }

  @override
  Widget build(BuildContext context) {
    final header = 'Semana $semanaIndex · $diaInicio al $diaFin ${_mesesCorto[mes]}';

    final kmSem = _pickSum(diasOrdenados, ['km_entre_ots', 'km_operativo']);
    final costoOpSem =
        _pickSum(diasOrdenados, ['costo_operativo']);
    final costoTraySem = _pickSum(diasOrdenados, [
      'costo_trayecto',
      'pesos_trayecto',
      'pesos_trayecto_dia',
    ]);

    final diasSorted = [...diasOrdenados]..sort((a, b) {
        final ka = _fechaKey(a);
        final kb = _fechaKey(b);
        return ka.compareTo(kb);
      });

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(14),
        child: Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.transparent,
            splashColor: Colors.white.withValues(alpha: 0.06),
          ),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            childrenPadding:
                const EdgeInsets.only(left: 8, right: 8, bottom: 12),
            collapsedShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            title: Text(
              header,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.white,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  children: [
                    TextSpan(
                      text: '${CombustibleFormat.formatKm(kmSem)} km ',
                      style: const TextStyle(
                        color: Color(0xFF22C55E),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const TextSpan(text: 'op · '),
                    TextSpan(
                      text: CombustibleFormat.formatMoney(costoOpSem),
                      style: const TextStyle(
                        color: Color(0xFF22C55E),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const TextSpan(text: ' op · '),
                    TextSpan(
                      text: CombustibleFormat.formatMoney(costoTraySem),
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const TextSpan(
                      text: ' trayecto',
                      style: TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            iconColor: Colors.white70,
            collapsedIconColor: Colors.white70,
            children: diasSorted.map((row) {
              final key = _fechaKey(row);
              final visitas = CombustibleFormat.intVisitasDia(row);
              final kmDia = CombustibleFormat.toDouble(
                row['km_operativo'] ?? row['km_entre_ots'],
              );
              final costoOp = CombustibleFormat.toDouble(
                row['costo_operativo'],
              );
              final costoTray = CombustibleFormat.toDouble(
                row['costo_trayecto'] ??
                    row['pesos_trayecto'] ??
                    row['pesos_trayecto_dia'],
              );

              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: const Color(0xFF252525),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      print('[Combustible] navega DiaDetalle $key');
                      Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => CombustibleDiaDetalleScreen(
                            rutTecnico: rutTecnico,
                            fechaYmd: key,
                          ),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              _labelFilaDia(key),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '$visitas visitas · ${CombustibleFormat.formatKm(kmDia)} km',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.end,
                                ),
                                const SizedBox(height: 4),
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: CombustibleFormat.formatMoney(
                                          costoOp,
                                        ),
                                        style: const TextStyle(
                                          color: Color(0xFF22C55E),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const TextSpan(
                                        text: ' op · ',
                                        style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12,
                                        ),
                                      ),
                                      TextSpan(
                                        text: CombustibleFormat.formatMoney(
                                          costoTray,
                                        ),
                                        style: const TextStyle(
                                          color: Color(0xFF9CA3AF),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const TextSpan(
                                        text: ' trayecto',
                                        style: TextStyle(
                                          color: Color(0xFF9CA3AF),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  textAlign: TextAlign.end,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

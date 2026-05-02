import 'package:flutter/material.dart';

import 'package:agente_desconexiones/screens/ot_detalle_screen.dart';
import 'package:agente_desconexiones/services/produccion_service.dart';

/// Lista de OTs completadas del día para un técnico (vista supervisor).
class TecnicoOtsDiaScreen extends StatefulWidget {
  const TecnicoOtsDiaScreen({
    super.key,
    required this.rutTecnico,
    required this.nombreTecnico,
    this.fechaTrabajo,
  });

  final String rutTecnico;
  final String nombreTecnico;
  /// Si es null, se usa la fecha de hoy en formato DD/MM/YY.
  final String? fechaTrabajo;

  @override
  State<TecnicoOtsDiaScreen> createState() => _TecnicoOtsDiaScreenState();
}

class _TecnicoOtsDiaScreenState extends State<TecnicoOtsDiaScreen> {
  final _svc = ProduccionService();
  List<Map<String, dynamic>> _ots = [];
  bool _cargando = true;
  late String _fecha;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _fecha = widget.fechaTrabajo ??
        '${n.day.toString().padLeft(2, '0')}/${n.month.toString().padLeft(2, '0')}/${n.year.toString().substring(2)}';
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final list = await _svc.listarOrdenesCompletadasDia(
      rutTecnico: widget.rutTecnico,
      fechaTrabajo: _fecha,
    );
    list.sort((a, b) => (a['hora_inicio'] ?? '')
        .toString()
        .compareTo((b['hora_inicio'] ?? '').toString()));
    if (mounted) {
      setState(() {
        _ots = list;
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1B2A),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.nombreTecnico,
              overflow: TextOverflow.ellipsis,
            ),
            Text('OTs $_fecha', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
          : _ots.isEmpty
              ? const Center(
                  child: Text(
                    'Sin órdenes completadas este día',
                    style: TextStyle(color: Color(0xFF8FA8C8)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _ots.length,
                  itemBuilder: (context, i) {
                    final orden = _ots[i];
                    final ant = i > 0 ? _ots[i - 1] : null;
                    final ot = orden['orden_trabajo']?.toString() ?? '';
                    return Card(
                      color: const Color(0xFF161B22),
                      child: ListTile(
                        title: Text(
                          'OT $ot',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          '${orden['hora_inicio'] ?? ''} · ${orden['tipo_orden'] ?? ''}',
                          style: const TextStyle(color: Colors.white54),
                        ),
                        trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => OtDetalleScreen(
                                ordenActual: orden,
                                ordenAnterior: ant,
                                rutTecnico: widget.rutTecnico,
                                fechaTrabajo:
                                    orden['fecha_trabajo']?.toString() ?? _fecha,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }
}

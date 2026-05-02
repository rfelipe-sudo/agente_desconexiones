import 'package:flutter/material.dart';
import '../services/tag_service.dart';
import '../services/portico_detector_service.dart';
import '../models/paso_tag.dart';

class DetalleTagScreen extends StatefulWidget {
  const DetalleTagScreen({super.key});

  @override
  State<DetalleTagScreen> createState() => _DetalleTagScreenState();
}

class _DetalleTagScreenState extends State<DetalleTagScreen> {
  final TagService _tagService = TagService();
  List<PasoTag> _pasos = [];
  bool _cargando = true;
  int _totalMes = 0;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);

    _pasos = await _tagService.getPasosDelMes();
    _totalMes = await _tagService.getTotalMesActual();

    setState(() => _cargando = false);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final nombreMes = _getNombreMes(now.month);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle TAG'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargarDatos,
              child: Column(
                children: [
                  // Header con total
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    color: Colors.indigo,
                    child: Column(
                      children: [
                        Text(
                          '$nombreMes ${now.year}',
                          style: const TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '\$${_formatearNumero(_totalMes)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${_pasos.length} pórticos',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),

                  // Lista de pasos
                  Expanded(
                    child: _pasos.isEmpty
                        ? const Center(child: Text('Sin pasos registrados'))
                        : ListView.builder(
                            itemCount: _pasos.length,
                            itemBuilder: (context, index) {
                              final paso = _pasos[index];
                              final mostrarFecha = index == 0 ||
                                  _esDiferente(_pasos[index - 1].fechaPaso, paso.fechaPaso);

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (mostrarFecha)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                                      child: Text(
                                        _formatearFecha(paso.fechaPaso),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ),
                                  Card(
                                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: _getColorTarifa(paso.tipoTarifa),
                                        radius: 20,
                                        child: Text(
                                          paso.tipoTarifa.toUpperCase(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      title: Text(
                                        paso.porticoNombre,
                                        style: const TextStyle(fontWeight: FontWeight.w500),
                                      ),
                                      subtitle: Text(
                                        '${paso.autopista} • ${_formatearHora(paso.fechaPaso)}',
                                      ),
                                      trailing: Text(
                                        '\$${_formatearNumero(paso.tarifaCobrada)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Colors.indigo,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final detector = PorticoDetectorService();
          final info = await detector.diagnostico();
          if (!mounted) return;
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Diagnóstico TAG'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: info.entries.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${e.key}: ',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Expanded(
                          child: Text(
                            e.value.toString(),
                            style: const TextStyle(color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  )).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cerrar'),
                ),
              ],
            ),
          );
        },
        child: const Icon(Icons.bug_report),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
    );
  }

  bool _esDiferente(DateTime a, DateTime b) {
    return a.day != b.day || a.month != b.month || a.year != b.year;
  }

  Color _getColorTarifa(String tipo) {
    switch (tipo) {
      case 'ts':
        return Colors.red;
      case 'tbp':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  String _formatearNumero(int numero) {
    return numero.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
  }

  String _formatearHora(DateTime fecha) {
    return '${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
  }

  String _formatearFecha(DateTime fecha) {
    const dias = ['', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    const meses = ['', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
    return '${dias[fecha.weekday]} ${fecha.day} ${meses[fecha.month]}';
  }

  String _getNombreMes(int mes) {
    const meses = ['', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
                   'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
    return meses[mes];
  }
}









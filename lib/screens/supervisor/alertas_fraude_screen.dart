import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/alerta_fraude.dart';
import '../../services/alertas_fraude_service.dart';

class AlertasFraudeScreen extends StatefulWidget {
  const AlertasFraudeScreen({super.key});

  @override
  State<AlertasFraudeScreen> createState() => _AlertasFraudeScreenState();
}

class _AlertasFraudeScreenState extends State<AlertasFraudeScreen> {
  final _service = AlertasFraudeService();
  List<AlertaFraude> _alertas = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarAlertas();
  }

  Future<void> _cargarAlertas() async {
    setState(() => _cargando = true);
    final alertas = await _service.obtenerAlertasPendientes();
    setState(() {
      _alertas = alertas;
      _cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🚨 Alertas de Fraude'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargarAlertas,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _alertas.isEmpty
              ? _buildSinAlertas()
              : _buildListaAlertas(),
    );
  }

  Widget _buildSinAlertas() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, size: 80, color: Colors.green.shade300),
          const SizedBox(height: 16),
          Text(
            'Sin alertas pendientes',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildListaAlertas() {
    return RefreshIndicator(
      onRefresh: _cargarAlertas,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _alertas.length,
        itemBuilder: (ctx, i) => _buildAlertaCard(_alertas[i]),
      ),
    );
  }

  Widget _buildAlertaCard(AlertaFraude alerta) {
    final tiempoTranscurrido = DateTime.now().difference(alerta.timestamp);
    String tiempoTexto;
    if (tiempoTranscurrido.inMinutes < 60) {
      tiempoTexto = 'Hace ${tiempoTranscurrido.inMinutes} min';
    } else {
      tiempoTexto = 'Hace ${tiempoTranscurrido.inHours} hrs';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red.shade300, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header rojo
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade700,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning, color: Colors.white),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'INTENTO SIN MORADORES',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  tiempoTexto,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),

          // Contenido
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Técnico y OT
                Row(
                  children: [
                    Icon(Icons.person, size: 20, color: Colors.grey.shade700),
                    const SizedBox(width: 8),
                    Text(
                      alerta.nombreTecnico,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.assignment, size: 20, color: Colors.grey.shade700),
                    const SizedBox(width: 8),
                    Text('OT: ${alerta.ot}'),
                  ],
                ),

                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),

                // Datos detectados
                const Text(
                  'Datos detectados:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildChip('👟 ${alerta.pasosRealizados} pasos', Colors.orange),
                    const SizedBox(width: 8),
                    _buildChip(
                        '📍 ${alerta.distanciaRecorrida.toStringAsFixed(1)}m',
                        Colors.orange),
                  ],
                ),

                const SizedBox(height: 12),

                // Razones de fallo
                const Text(
                  'Razones del bloqueo:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...alerta.razonesFallo.map((razon) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.close, color: Colors.red, size: 16),
                          const SizedBox(width: 4),
                          Expanded(
                              child: Text(razon,
                                  style: const TextStyle(fontSize: 13))),
                        ],
                      ),
                    )),

                // Botón de ubicación si hay GPS
                if (alerta.latitud != null && alerta.longitud != null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _abrirMapa(alerta.latitud!, alerta.longitud!),
                    icon: const Icon(Icons.map),
                    label: const Text('Ver ubicación'),
                  ),
                ],

                const SizedBox(height: 16),

                // Botones de acción
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _confirmarFraude(alerta),
                        icon: const Icon(Icons.report),
                        label: const Text('Confirmar Fraude'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _descartarAlerta(alerta),
                        icon: const Icon(Icons.check),
                        label: const Text('Descartar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  void _abrirMapa(double lat, double lng) async {
    final url = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _confirmarFraude(AlertaFraude alerta) async {
    final comentario = await _mostrarDialogoComentario('Confirmar Fraude');
    if (comentario == null) return;

    final exito =
        await _service.marcarRevisada(alerta.id, 'confirmado', comentario);
    if (exito && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Fraude confirmado'),
            backgroundColor: Colors.red),
      );
      _cargarAlertas();
    }
  }

  Future<void> _descartarAlerta(AlertaFraude alerta) async {
    final comentario = await _mostrarDialogoComentario('Descartar Alerta');
    if (comentario == null) return;

    final exito =
        await _service.marcarRevisada(alerta.id, 'descartado', comentario);
    if (exito && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Alerta descartada'),
            backgroundColor: Colors.green),
      );
      _cargarAlertas();
    }
  }

  Future<String?> _mostrarDialogoComentario(String titulo) async {
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Agregar comentario (opcional)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }
}





















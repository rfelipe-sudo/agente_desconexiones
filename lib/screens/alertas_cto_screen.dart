import 'package:flutter/material.dart';
import '../models/alerta_cto.dart';
import '../services/alertas_cto_service.dart';
import '../widgets/alerta_cto_card.dart';

class AlertasCTOScreen extends StatefulWidget {
  const AlertasCTOScreen({super.key});

  @override
  State<AlertasCTOScreen> createState() => _AlertasCTOScreenState();
}

class _AlertasCTOScreenState extends State<AlertasCTOScreen> {
  final AlertasCTOService _alertasService = AlertasCTOService();
  List<AlertaCTO> _alertas = [];
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    _cargarAlertas();

    // Escuchar alertas en tiempo real
    _alertasService.onAlertasRecibidas = (alertas) {
      if (mounted) {
        setState(() {
          _alertas = alertas;
        });
      }
    };
  }

  Future<void> _cargarAlertas() async {
    setState(() => _cargando = true);

    final alertas = await _alertasService.consultarAlertas();

    if (mounted) {
      setState(() {
        _alertas = alertas;
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alertas CTO'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargarAlertas,
            tooltip: 'Refrescar estado vecinos',
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _alertas.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle, size: 64, color: Colors.green),
                      const SizedBox(height: 16),
                      const Text(
                        'Sin alertas de desconexión',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _cargarAlertas,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refrescar'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargarAlertas,
                  child: ListView.builder(
                    itemCount: _alertas.length,
                    itemBuilder: (context, index) {
                      return AlertaCTOCard(
                        alerta: _alertas[index],
                        onRefrescar: _cargarAlertas,
                      );
                    },
                  ),
                ),
    );
  }
}





















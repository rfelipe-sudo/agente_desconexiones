import 'package:flutter/material.dart';

import 'package:agente_desconexiones/services/app_version_service.dart';
import 'package:agente_desconexiones/utils/session_manager.dart';

/// Ajustes que no modifican la identidad del técnico (RUT fijo en el dispositivo).
class ConfiguracionScreen extends StatefulWidget {
  const ConfiguracionScreen({super.key});

  @override
  State<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends State<ConfiguracionScreen> {
  bool _cargando = true;
  String _nombre = '';
  String _rut = '';
  String _tipo = '';
  String _iniciales = '?';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final nombre = await SessionManager.getNombreTecnico();
    final rut = await SessionManager.getRutTecnico();
    final tipo = await SessionManager.getTipoPersonal();
    final ini = await SessionManager.getIniciales();
    if (mounted) {
      setState(() {
        _nombre = nombre;
        _rut = rut;
        _tipo = tipo;
        _iniciales = ini;
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Tu RUT y nombre están asociados a este dispositivo. '
                            'No se pueden cambiar desde la app. Si necesitas '
                            'corregir el registro, contacta a tu coordinador.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Dispositivo registrado como',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: Colors.indigo,
                                child: Text(
                                  _iniciales,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _nombre.isNotEmpty ? _nombre : '—',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _rut.isNotEmpty ? _rut : '—',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    if (_tipo.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Tipo: $_tipo',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Colors.black45,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.system_update, color: Colors.indigo),
                      title: const Text('Versión CREABOX'),
                      subtitle: Text(AppVersionService.versionLabel),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

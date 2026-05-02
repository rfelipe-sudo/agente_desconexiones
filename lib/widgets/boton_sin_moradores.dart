import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:agente_desconexiones/services/deteccion_caminata_service.dart';
import 'package:agente_desconexiones/models/trabajo_activo.dart';
import 'package:agente_desconexiones/providers/auth_provider.dart';
import 'package:agente_desconexiones/services/supabase_service.dart';

class BotonSinMoradores extends StatefulWidget {
  final String ot;
  final Function(bool aprobado, Map<String, dynamic> data)? onResultado;

  const BotonSinMoradores({
    super.key,
    required this.ot,
    this.onResultado,
  });

  @override
  State<BotonSinMoradores> createState() => _BotonSinMoradoresState();
}

class _BotonSinMoradoresState extends State<BotonSinMoradores> {
  final _deteccionService = DeteccionCaminataService();
  final _supabaseService = SupabaseService();
  bool _validando = false;
  StreamSubscription? _validacionSubscription;

  @override
  void initState() {
    super.initState();

    // Escuchar resultado de validación
    _validacionSubscription = _deteccionService.onValidacionResultado.listen((data) {
      if (data == null) return;

      if (mounted) {
        setState(() => _validando = false);

        if (data['aprobado'] == true) {
          // ✅ Aprobado - mostrar confirmación
          _mostrarDialogoAprobado(data);
        } else {
          // ❌ Rechazado - mostrar razones y alertar supervisor
          _mostrarDialogoRechazado(data);
        }

        widget.onResultado?.call(data['aprobado'] as bool, data);
      }
    });
  }

  @override
  void dispose() {
    _validacionSubscription?.cancel();
    super.dispose();
  }

  void _validar() {
    setState(() => _validando = true);
    _deteccionService.validarSinMoradores();
  }

  void _mostrarDialogoAprobado(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 32),
            SizedBox(width: 8),
            Text('Validación Aprobada'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Se verificó que caminaste a la ubicación del cliente.'),
            const SizedBox(height: 16),
            _buildInfoRow('Pasos realizados', '${data['pasos_realizados']}'),
            _buildInfoRow(
              'Distancia recorrida',
              '${(data['distancia_recorrida'] as num?)?.toStringAsFixed(1) ?? '0'} m',
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              Navigator.pop(ctx);
              // Proceder con Sin Moradores
            },
            child: const Text('Confirmar Sin Moradores'),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoRechazado(Map<String, dynamic> data) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red, size: 32),
            SizedBox(width: 8),
            Text('Validación Fallida'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'No se detectó que te hayas bajado del vehículo.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text('Razones:', style: TextStyle(fontWeight: FontWeight.bold)),
            ...((data['razones_fallo'] as List?) ?? []).map(
              (razon) => Padding(
                padding: const EdgeInsets.only(left: 8, top: 4),
                child: Row(
                  children: [
                    const Icon(Icons.close, color: Colors.red, size: 16),
                    const SizedBox(width: 4),
                    Expanded(child: Text(razon.toString())),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.supervisor_account, color: Colors.red),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Se notificará a tu supervisor sobre este intento.',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );

    // Enviar alerta a supervisor
    _enviarAlertaSupervisor(data);
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Future<void> _enviarAlertaSupervisor(Map<String, dynamic> data) async {
    try {
      // Obtener ubicación actual
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
      } catch (e) {
        debugPrint('⚠️ No se pudo obtener GPS: $e');
      }

      // Obtener datos del técnico desde el trabajo activo o AuthProvider
      final trabajo = data['trabajo'] as TrabajoActivo?;
      String tecnicoId = trabajo?.tecnicoId ?? 'TEC-UNKNOWN';
      String nombreTecnico = trabajo?.nombreTecnico ?? 'Técnico';

      // Si no hay datos en el trabajo, intentar obtenerlos del AuthProvider
      if (tecnicoId == 'TEC-UNKNOWN' || nombreTecnico == 'Técnico') {
        try {
          final authProvider =
              Provider.of<AuthProvider>(context, listen: false);
          final usuario = authProvider.usuario;
          if (usuario != null) {
            tecnicoId = usuario.id;
            nombreTecnico = usuario.nombre;
          }
        } catch (e) {
          debugPrint(
              '⚠️ No se pudo obtener datos del técnico desde AuthProvider: $e');
        }
      }

      // Enviar alerta a Supabase
      final exito = await _supabaseService.enviarAlertaFraude(
        ot: widget.ot,
        tecnicoId: tecnicoId,
        nombreTecnico: nombreTecnico,
        pasosRealizados: data['pasos_realizados'] ?? 0,
        distanciaRecorrida:
            (data['distancia_recorrida'] as num?)?.toDouble() ?? 0,
        razonesFallo: List<String>.from(data['razones_fallo'] ?? []),
        latitud: position?.latitude,
        longitud: position?.longitude,
      );

      if (exito) {
        debugPrint('🚨 Alerta de fraude enviada a Supabase');
      } else {
        debugPrint('❌ Error enviando alerta a Supabase');
      }
    } catch (e) {
      debugPrint('❌ Error enviando alerta: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: _validando ? null : _validar,
      icon: _validando
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.door_front_door),
      label: Text(_validando ? 'Validando...' : 'Sin Moradores'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.orange,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    );
  }
}


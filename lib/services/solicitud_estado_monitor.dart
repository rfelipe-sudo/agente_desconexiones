import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Escucha cambios de estado en [solicitudes_material] para una solicitud.
class SolicitudEstadoMonitor {
  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  void start({
    required String solicitudId,
    required void Function(String estado) onEstado,
  }) {
    stop();
    _sub = Supabase.instance.client
        .from('solicitudes_material')
        .stream(primaryKey: ['id'])
        .eq('id', solicitudId)
        .listen((rows) {
      if (rows.isEmpty) return;
      final estado = rows.first['estado'] as String?;
      if (estado != null && estado.isNotEmpty) onEstado(estado);
    });
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }
}

/// Diálogos y cierre de navegación compartidos en el flujo de material.
class MaterialTransaccionUi {
  static Future<void> mostrarCancelada(
    BuildContext context, {
    String? detalle,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1B2A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF1E3A5F)),
        ),
        title: const Row(children: [
          Icon(Icons.cancel_outlined, color: Color(0xFFEF4444), size: 22),
          SizedBox(width: 8),
          Text(
            'Transacción cancelada',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ]),
        content: Text(
          detalle ??
              'La solicitud de material fue cancelada. '
              'Puedes iniciar una nueva cuando lo necesites.',
          style: const TextStyle(color: Color(0xFF8FA8C8), fontSize: 13),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  static Future<void> mostrarCompletada(
    BuildContext context, {
    String? detalle,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF112240),
        title: const Row(children: [
          Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 24),
          SizedBox(width: 8),
          Text(
            'Traspaso confirmado',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ]),
        content: Text(
          detalle ??
              'El material fue registrado en bodega. '
              'Recibirás una notificación cuando sea aprobado.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Entendido',
              style: TextStyle(color: Color(0xFF00D4AA)),
            ),
          ),
        ],
      ),
    );
  }

  /// Cierra guía, PIN, entrega en camino, etc. y vuelve al home del stack.
  static void cerrarFlujoEntregador(BuildContext context) {
    Navigator.of(context).popUntil((r) => r.isFirst);
  }
}

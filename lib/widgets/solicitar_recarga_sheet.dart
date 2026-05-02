import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/widgets/combustible_format.dart';

/// Bottom sheet "Combustible adicional" → RPC `solicitar_combustible`.
/// Devuelve `true` si `out_ok`.
Future<bool?> showSolicitarCombustibleAdicionalSheet({
  required BuildContext context,
  required String rutTecnico,
  required double saldoPesos,
  required double kmRestantes,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1E1E2E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _SolicitarCombustibleBody(
      rutTecnico: rutTecnico,
      saldoPesos: saldoPesos,
      kmRestantes: kmRestantes,
    ),
  );
}

class _SolicitarCombustibleBody extends StatefulWidget {
  const _SolicitarCombustibleBody({
    required this.rutTecnico,
    required this.saldoPesos,
    required this.kmRestantes,
  });

  final String rutTecnico;
  final double saldoPesos;
  final double kmRestantes;

  @override
  State<_SolicitarCombustibleBody> createState() =>
      _SolicitarCombustibleBodyState();
}

class _SolicitarCombustibleBodyState extends State<_SolicitarCombustibleBody> {
  final TextEditingController _notaController = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _notaController.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    print('[Combustible] solicitar_combustible enviar');
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _enviando = true);
    try {
      final sol = await Supabase.instance.client.rpc(
        'solicitar_combustible',
        params: {
          'p_rut': widget.rutTecnico,
          'p_nota': _notaController.text.trim(),
        },
      );

      if (!mounted) return;

      final row = (sol is List && sol.isNotEmpty)
          ? sol[0] as Map<String, dynamic>
          : (sol is Map<String, dynamic> ? sol : null);

      final ok = CombustibleFormat.toBool(row?['out_ok']);
      final mensaje = row?['out_mensaje']?.toString() ?? '';

      Navigator.pop(context, ok);

      if (ok) {
        // La pantalla padre muestra el banner persistente con el texto completo.
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              mensaje.isNotEmpty ? mensaje : 'No se pudo enviar la solicitud',
            ),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context, false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _enviando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final saldoTxt = CombustibleFormat.formatMoney(widget.saldoPesos);
    final kmTxt = widget.kmRestantes.toStringAsFixed(1);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Combustible adicional',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Saldo operativo: $saldoTxt · $kmTxt km disponibles',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notaController,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Ej: Necesito combustible para viaje especial',
                labelText: 'Nota para el coordinador (opcional)',
                labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF3B82F6)),
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _enviando ? null : _enviar,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: const Color(0xFF3B82F6),
                disabledBackgroundColor: Colors.grey.shade800,
              ),
              child: _enviando
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Enviar solicitud'),
            ),
          ],
        ),
      ),
    );
  }
}

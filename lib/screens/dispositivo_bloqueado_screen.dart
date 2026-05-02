import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/providers/auth_provider.dart';
import 'package:agente_desconexiones/utils/device_helper.dart';
import 'package:agente_desconexiones/widgets/creabox_wordmark.dart';

/// Pantalla cuando el dispositivo no está autorizado o está pendiente.
class DispositivoBloqueadoScreen extends StatefulWidget {
  const DispositivoBloqueadoScreen({
    super.key,
    required this.estado,
    required this.mensaje,
  });

  final String estado;
  final String mensaje;

  @override
  State<DispositivoBloqueadoScreen> createState() =>
      _DispositivoBloqueadoScreenState();
}

class _DispositivoBloqueadoScreenState extends State<DispositivoBloqueadoScreen> {
  bool _reintentando = false;
  late String _mensaje;

  @override
  void initState() {
    super.initState();
    _mensaje = widget.mensaje;
  }

  Future<void> _reintentar() async {
    setState(() => _reintentando = true);
    try {
      final deviceId = await obtenerIdDispositivo();
      final supabase = Supabase.instance.client;

      final existe = await supabase
          .from('dispositivos_autorizados')
          .select('habilitado, motivo_bloqueo')
          .eq('imei', deviceId)
          .maybeSingle();

      if (!mounted) return;

      if (existe != null && existe['habilitado'] == true) {
        await context.read<AuthProvider>().reintentar();
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/home');
        return;
      }

      setState(() {
        _mensaje = existe?['motivo_bloqueo']?.toString() ??
            'Aún pendiente de autorización. Contacta a tu coordinador.';
        _reintentando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _reintentando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendiente = widget.estado == 'pendiente';
    final colorIcono = pendiente ? const Color(0xFFEAB308) : const Color(0xFFEF4444);

    return PopScope(
      canPop: false,
      child: Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const SizedBox(height: 48),
              const CreaboxWordmark(fontSize: 42, letterSpacing: 4),
              const SizedBox(height: 48),
              Icon(
                pendiente ? Icons.hourglass_top_rounded : Icons.lock_rounded,
                size: 88,
                color: colorIcono,
              ),
              const SizedBox(height: 28),
              Text(
                pendiente
                    ? 'Dispositivo pendiente de autorización'
                    : 'Dispositivo no autorizado',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _mensaje.isNotEmpty
                    ? _mensaje
                    : (pendiente
                        ? 'Tu equipo aún no ha sido habilitado en CREABOX.'
                        : 'Este dispositivo no puede acceder a la aplicación.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 15,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Contacta a tu coordinador para que autorice\n'
                'este dispositivo en el sistema CREABOX',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _reintentando ? null : _reintentar,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF38BDF8),
                    side: const BorderSide(color: Color(0xFF38BDF8)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _reintentando
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Reintentar verificación'),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

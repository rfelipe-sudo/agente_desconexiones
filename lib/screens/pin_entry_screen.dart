import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/models/solicitud_material.dart';
import 'package:agente_desconexiones/services/fcm_service.dart';
import 'package:agente_desconexiones/services/material_solicitud_service.dart';
import 'package:agente_desconexiones/services/solicitud_estado_monitor.dart';

/// Pantalla que muestra B (entregador) para ingresar el PIN de 6 dígitos
/// que el solicitante (A) recibió en su pantalla.
class PinEntryScreen extends StatefulWidget {
  final SolicitudMaterial solicitud;

  const PinEntryScreen({super.key, required this.solicitud});

  @override
  State<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends State<PinEntryScreen> {
  static const Color _bg      = Color(0xFF0A1628);
  static const Color _card    = Color(0xFF112240);
  static const Color _accent  = Color(0xFF00D4AA);
  static const Color _danger  = Color(0xFFE53935);

  final _db = Supabase.instance.client;

  String _pin         = '';
  bool   _cargando    = false;
  String? _error;
  bool   _exito       = false;
  bool   _sinIntentos = false;
  bool   _pinVerificado = false;
  String? _avisoRenovacion;

  final SolicitudEstadoMonitor _estadoMonitor = SolicitudEstadoMonitor();
  bool _transaccionCerrada = false;

  @override
  void initState() {
    super.initState();
    _renovarPinSiExpirado();
    _estadoMonitor.start(
      solicitudId: widget.solicitud.id,
      onEstado: (estado) {
        if (!mounted || _transaccionCerrada || _exito) return;
        if (estado == 'cancelada') {
          _transaccionCerrada = true;
          _estadoMonitor.stop();
          unawaited(_cerrarPorCancelacionRemota());
        } else if (estado == 'completada' && !_exito) {
          _transaccionCerrada = true;
          _estadoMonitor.stop();
          unawaited(_cerrarPorCompletadaRemota());
        }
      },
    );
  }

  Future<void> _cerrarPorCancelacionRemota() async {
    if (!mounted) return;
    await MaterialTransaccionUi.mostrarCancelada(context);
    if (!mounted) return;
    MaterialTransaccionUi.cerrarFlujoEntregador(context);
  }

  Future<void> _cerrarPorCompletadaRemota() async {
    if (!mounted) return;
    await MaterialTransaccionUi.mostrarCompletada(context);
    if (!mounted) return;
    MaterialTransaccionUi.cerrarFlujoEntregador(context);
  }

  @override
  void dispose() {
    _estadoMonitor.stop();
    super.dispose();
  }

  Future<void> _renovarPinSiExpirado() async {
    try {
      final row = await _db
          .from('solicitudes_material')
          .select('pin_codigo, pin_expira_en')
          .eq('id', widget.solicitud.id)
          .maybeSingle();
      if (row == null) return;

      final pin = row['pin_codigo'] as String?;
      final expiraRaw = row['pin_expira_en'] as String?;
      if (pin == null || pin.isEmpty) return;

      final expirado = expiraRaw != null &&
          DateTime.parse(expiraRaw).isBefore(DateTime.now());
      if (!expirado) return;

      await _db.functions.invoke('generar-pin', body: {
        'solicitud_id': widget.solicitud.id,
      });
      await FcmService.limpiarPinMostrado(widget.solicitud.id);
      if (mounted) {
        setState(() {
          _avisoRenovacion =
              'El PIN anterior expiró. Se generó uno nuevo — pídeselo al solicitante.';
        });
      }
    } catch (_) {}
  }

  Future<void> _regenerarPinTrasExpiracion() async {
    setState(() { _cargando = true; _error = null; });
    try {
      await _db.functions.invoke('generar-pin', body: {
        'solicitud_id': widget.solicitud.id,
      });
      await FcmService.limpiarPinMostrado(widget.solicitud.id);
      if (mounted) {
        setState(() {
          _cargando = false;
          _pin = '';
          _avisoRenovacion =
              'PIN renovado. Pide al solicitante el código nuevo en su pantalla.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = 'No se pudo renovar el PIN. Intenta nuevamente.';
        });
      }
    }
  }

  void _presionar(String digito) {
    if (_pin.length >= 6 || _cargando || _exito || _sinIntentos) return;
    setState(() {
      _pin  += digito;
      _error = null;
    });
    if (_pin.length == 6) _verificar();
  }

  void _borrar() {
    if (_pin.isEmpty || _cargando || _exito || _sinIntentos) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _verificar() async {
    if (_pinVerificado) return;
    setState(() { _cargando = true; _error = null; });

    debugPrint('[PIN] verificar solicitud=${widget.solicitud.id} pin=$_pin');

    try {
      final result = await _confirmarEnServidor();
      debugPrint('[PIN] resultado servidor: $result');

      final ok = result['ok'] == true;

      if (ok) {
        _pinVerificado = true;
        await FcmService.instance.detenerPinMonitor();
        setState(() {
          _cargando = false;
          _exito    = true;
        });
      } else {
        final motivo   = result['error'] as String? ?? 'error';
        final intentos = result['intentos_restantes'] as int?;

        if (motivo == 'expirado') {
          await _regenerarPinTrasExpiracion();
          return;
        }

        final agotados = motivo == 'sin_intentos' ||
            motivo == 'cancelada' ||
            (intentos != null && intentos <= 0);
        if (agotados) {
          unawaited(MaterialSolicitudService().notificarCancelacion(
            solicitudId:  widget.solicitud.id,
            tipoMaterial: widget.solicitud.tipoMaterial,
          ));
        }
        setState(() {
          _cargando    = false;
          _pin         = '';
          _sinIntentos = agotados;
          _error       = agotados ? null : _mensajeError(motivo, intentos);
        });
      }
    } catch (e) {
      debugPrint('[PIN] error verificar: $e');
      final msg = e.toString();
      final corto = msg.contains('pin_intentos')
          ? 'Error interno al confirmar. Intenta de nuevo en unos segundos.'
          : (msg.length > 120 ? '${msg.substring(0, 120)}…' : msg);
      setState(() {
        _cargando = false;
        _pin      = '';
        _error    = 'No se pudo confirmar: $corto';
      });
    }
  }

  Future<Map<String, dynamic>> _confirmarEnServidor() async {
    try {
      final res = await _db.functions.invoke('confirmar-pin', body: {
        'solicitud_id': widget.solicitud.id,
        'pin':          _pin,
      });
      final data = res.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
    } catch (e) {
      debugPrint('[PIN] edge confirmar-pin falló: $e');
    }

    return await _db.rpc('confirmar_traspaso_pin', params: {
      'p_solicitud_id': widget.solicitud.id,
      'p_pin':          _pin,
    }) as Map<String, dynamic>;
  }

  String _mensajeError(String motivo, int? intentos) {
    switch (motivo) {
      case 'expirado':
        return 'El PIN expiró. Se generó uno nuevo — pídeselo al solicitante.';
      case 'pin_ya_usado':
        return 'PIN ya utilizado. Si no ves confirmación, contacta a soporte.';
      case 'cancelada':
        return 'La solicitud fue cancelada.';
      case 'sin_intentos':
        return 'Sin intentos restantes. Contacta a tu supervisor.';
      case 'incorrecto':
        if (intentos != null && intentos > 0) {
          return 'PIN incorrecto. Quedan $intentos intento${intentos == 1 ? '' : 's'}.';
        }
        return 'PIN incorrecto. Sin intentos restantes.';
      default:
        return 'Error inesperado ($motivo).';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _exito,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _exito) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Debes confirmar el PIN para cerrar el traspaso. '
              'Si sales, usa el banner naranja para volver.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      },
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _card,
          title: const Text('Confirmar traspaso',
              style: TextStyle(color: Colors.white, fontSize: 16)),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: _sinIntentos
            ? _buildSinIntentos()
            : _exito
                ? _buildExito()
                : _buildForm(),
      ),
    );
  }

  Widget _buildExito() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline, color: _accent, size: 80),
            const SizedBox(height: 24),
            const Text('¡Traspaso enviado a bodega!',
                style: TextStyle(color: Colors.white, fontSize: 22,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            const Text(
              'Pendiente de aprobación por bodega.\nRecibirás una notificación cuando sea aprobado.',
              style: TextStyle(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: _bg,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 40, vertical: 14)),
              onPressed: () => Navigator.of(context).popUntil(
                  (r) => r.isFirst),
              child: const Text('Volver al inicio',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSinIntentos() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cancel_outlined, color: _danger, size: 80),
            const SizedBox(height: 24),
            const Text(
              'El traspaso no pudo completarse.',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Se agotaron los intentos de PIN. La solicitud será cancelada y deberás iniciar el proceso desde el principio.',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _danger,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 40, vertical: 14)),
              onPressed: _cancelarYVolver,
              child: const Text('Cancelar solicitud y volver al inicio',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cancelarYVolver() async {
    final rutEnt = widget.solicitud.rutEntregador;
    if (rutEnt == null || rutEnt.isEmpty) return;
    try {
      await MaterialSolicitudService().cancelarSolicitud(
        solicitudId:   widget.solicitud.id,
        rutCancelador: rutEnt,
      );
    } catch (_) {}
    _transaccionCerrada = true;
    _estadoMonitor.stop();
    if (mounted) {
      await MaterialTransaccionUi.mostrarCancelada(
        context,
        detalle: 'Cancelaste la solicitud. El solicitante fue notificado.',
      );
      if (!mounted) return;
      MaterialTransaccionUi.cerrarFlujoEntregador(context);
    }
  }

  Widget _buildForm() {
    return Column(
      children: [
        Container(
          color: _card,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.lock_outline, color: _accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pide al solicitante el PIN de 6 dígitos que ve en su pantalla (no el de una notificación antigua).',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13),
                ),
              ),
            ],
          ),
        ),

        if (_avisoRenovacion != null) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _accent.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.refresh, color: _accent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _avisoRenovacion!,
                      style: const TextStyle(color: _accent, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 40),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (i) {
            final filled = i < _pin.length;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? _accent : Colors.transparent,
                border: Border.all(
                    color: filled ? _accent
                        : Colors.white.withValues(alpha: 0.4),
                    width: 2),
              ),
            );
          }),
        ),

        if (_error != null) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(_error!,
                style: const TextStyle(color: _danger, fontSize: 13),
                textAlign: TextAlign.center),
          ),
        ],

        const Spacer(),

        if (_cargando)
          const Padding(
            padding: EdgeInsets.only(bottom: 60),
            child: CircularProgressIndicator(color: _accent),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              children: [
                for (final fila in [
                  ['1', '2', '3'],
                  ['4', '5', '6'],
                  ['7', '8', '9'],
                  ['', '0', '⌫'],
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: fila.map((d) {
                        if (d.isEmpty) return const SizedBox(width: 80);
                        final esBorrar = d == '⌫';
                        return _Tecla(
                          label: d,
                          onTap: esBorrar ? _borrar : () => _presionar(d),
                          color: esBorrar
                              ? Colors.white.withValues(alpha: 0.1)
                              : _card,
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Tecla extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _Tecla({
    required this.label,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        height: 64,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.1)),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/config/constants.dart';
import 'package:agente_desconexiones/models/solicitud_material.dart';

/// Pantalla que muestra B (entregador) para ingresar el PIN de 6 dígitos
/// que el solicitante (A) recibió por notificación.
/// Al validar el PIN llama a Kepler POST /traspaso/api/solicitar.
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
  String? _folio;
  bool   _sinIntentos = false;

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
    setState(() { _cargando = true; _error = null; });

    try {
      final result = await _db.rpc('verificar_pin', params: {
        'p_solicitud_id': widget.solicitud.id,
        'p_pin':          _pin,
      }) as Map<String, dynamic>;

      if (result['ok'] == true) {
        await _llamarKepler();
      } else {
        final motivo   = result['error'] as String? ?? 'error';
        final intentos = result['intentos_restantes'] as int?;
        final agotados = motivo == 'sin_intentos' ||
            (intentos != null && intentos <= 0);
        setState(() {
          _cargando    = false;
          _pin         = '';
          _sinIntentos = agotados;
          _error       = agotados ? null : _mensajeError(motivo, intentos);
        });
      }
    } catch (e) {
      setState(() {
        _cargando = false;
        _pin      = '';
        _error    = 'Error de conexión. Intenta nuevamente.';
      });
    }
  }

  String _mensajeError(String motivo, int? intentos) {
    switch (motivo) {
      case 'expirado':    return 'El PIN expiró. Solicita uno nuevo.';
      case 'sin_intentos': return 'Sin intentos restantes. Contacta a tu supervisor.';
      case 'incorrecto':
        if (intentos != null && intentos > 0) {
          return 'PIN incorrecto. Quedan $intentos intento${intentos == 1 ? '' : 's'}.';
        }
        return 'PIN incorrecto. Sin intentos restantes.';
      default: return 'Error inesperado ($motivo).';
    }
  }

  // PIN correcto → crea registro en bodega + notifica por email.
  // Kepler se llama cuando bodega aprueba (edge function aprobar-traspaso).
  Future<void> _llamarKepler() async {
    final sol = widget.solicitud;
    try {
      // Si las series no llegaron propagadas, leerlas directamente de
      // solicitudes_material (guía las guarda al firmar el entregador).
      List<String> series = sol.series;
      if (series.isEmpty && sol.esSeriado) {
        final row = await _db
            .from('solicitudes_material')
            .select('series')
            .eq('id', sol.id)
            .single();
        series = ((row as Map)['series'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
      }

      // Crear registro de trazabilidad en bodega
      await _db.from('traspasos_bodega').insert({
        'solicitud_material_id': sol.id,
        'rut_tecnico_b':         sol.rutEntregador ?? '',
        'nombre_tecnico_b':      sol.nombreEntregador ?? '',
        'rut_tecnico_a':         sol.rutSolicitante,
        'nombre_tecnico_a':      sol.nombreSolicitante,
        'tipo_material':         sol.tipoMaterial,
        'cantidad':              sol.cantidad,
        'series':                series,
        'id_material':           sol.idMaterial,
        'estado':                'pendiente',
      });

      // Notificar a bodegueros por FCM (fire-and-forget)
      unawaited(_db.functions.invoke('notificar-bodega-traspaso'));

      setState(() {
        _cargando = false;
        _exito    = true;
        _folio    = null; // folio llega cuando bodega apruebe
      });
    } catch (e) {
      setState(() {
        _cargando = false;
        _error    = 'Error al registrar en bodega. Intenta nuevamente.';
        _pin      = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            Text(
              _folio != null
                  ? 'Folio Kepler: $_folio'
                  : 'Pendiente de aprobación por bodega.\nRecibirás una notificación cuando sea aprobado.',
              style: TextStyle(
                  color: _folio != null ? _accent : Colors.white70,
                  fontSize: 14),
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
    try {
      await _db
          .from('solicitudes_material')
          .update({'estado': 'cancelada'})
          .eq('id', widget.solicitud.id);
    } catch (_) {}
    if (mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  Widget _buildForm() {
    return Column(
      children: [
        // Instrucción
        Container(
          color: _card,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.lock_outline, color: _accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pide al solicitante el PIN de 6 dígitos que recibió en su notificación.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 40),

        // Puntos del PIN
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

        // Error
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

        // Teclado numérico
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

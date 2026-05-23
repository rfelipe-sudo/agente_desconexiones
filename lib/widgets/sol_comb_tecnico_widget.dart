import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/services/sol_combustible_service.dart';
import 'package:agente_desconexiones/widgets/combustible_format.dart';

/// Widget que muestra el estado de la solicitud adicional activa del técnico
/// y permite crear una nueva si no hay ninguna en curso.
class SolCombTecnicoWidget extends StatefulWidget {
  const SolCombTecnicoWidget({
    super.key,
    required this.rut,
    required this.nombre,
    required this.saldoLitros,
    required this.saldoPesos,
  });

  final String rut;
  final String nombre;
  final double saldoLitros;
  final double saldoPesos;

  @override
  State<SolCombTecnicoWidget> createState() => _SolCombTecnicoWidgetState();
}

class _SolCombTecnicoWidgetState extends State<SolCombTecnicoWidget> {
  static const _surface = Color(0xFF1A2535);
  static const _border  = Color(0xFF1E3A5F);
  static const _accent  = Color(0xFF00D9FF);
  static const _green   = Color(0xFF22C55E);
  static const _orange  = Color(0xFFF59E0B);
  static const _red     = Color(0xFFEF4444);
  static const _textDim = Color(0xFF8FA8C8);

  final _svc = SolCombustibleService();

  Map<String, dynamic>? _solicitud;
  bool _cargando    = true;
  bool _enviando    = false;

  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final sol = await _svc.solicitudActivaTecnico(widget.rut);
      if (mounted) {
        setState(() {
          _solicitud = sol;
          _cargando  = false;
        });
        if (sol != null) {
          _suscribir(sol['id'].toString());
        }
      }
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _suscribir(String solicitudId) {
    _sub?.cancel();
    _sub = Supabase.instance.client
        .from('sol_comb_adicional')
        .stream(primaryKey: ['id'])
        .eq('id', int.tryParse(solicitudId) ?? 0)
        .listen((rows) {
      if (!mounted || rows.isEmpty) return;
      setState(() => _solicitud = rows.first);
    });
  }

  Future<void> _solicitar() async {
    setState(() => _enviando = true);
    try {
      final sol = await _svc.crearSolicitudAdicional(
        rutTecnico:    widget.rut,
        nombreTecnico: widget.nombre,
        saldoLitros:   widget.saldoLitros,
        saldoPesos:    widget.saldoPesos,
      );
      if (mounted) {
        setState(() => _solicitud = sol);
        _suscribir(sol['id'].toString());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Solicitud enviada a tu supervisor')),
        );
      }
    } on StateError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
        await _cargar();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const SizedBox(
        height: 60,
        child: Center(
          child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: _solicitud == null
          ? _buildBoton()
          : _buildTracker(_solicitud!),
    );
  }

  // ── Sin solicitud activa: mostrar botón ───────────────────────────────────

  Widget _buildBoton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.local_gas_station, size: 16, color: _accent),
            SizedBox(width: 6),
            Text('Combustible adicional',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Solicita una carga extra cuando tu saldo no sea suficiente para el turno.',
          style: TextStyle(color: _textDim, fontSize: 12),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _enviando ? null : _solicitar,
            icon: _enviando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_rounded, size: 16),
            label:
                Text(_enviando ? 'Enviando...' : 'Solicitar carga extra'),
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  // ── Con solicitud activa: mostrar tracker ─────────────────────────────────

  Widget _buildTracker(Map<String, dynamic> sol) {
    final estado  = sol['estado'] as String? ?? '';
    final rechazada = estado == 'rechazado_supervisor' ||
        estado == 'rechazado_jefe_ops';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.local_gas_station, size: 16, color: _accent),
            const SizedBox(width: 6),
            const Text('Solicitud combustible adicional',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
            const Spacer(),
            if (sol['monto_aprobado'] != null)
              Text(
                CombustibleFormat.formatMoney(
                    (sol['monto_aprobado'] as num).toDouble()),
                style: const TextStyle(
                    color: _green,
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // Pasos del flujo
        _buildPaso(
          label: 'Supervisor',
          completado: estado != 'pendiente_supervisor',
          activo:     estado == 'pendiente_supervisor',
          rechazado:  estado == 'rechazado_supervisor',
        ),
        _buildPaso(
          label: 'Jefe de Operaciones',
          completado: _estadoGte(estado, 'pendiente_flota') && !rechazada,
          activo:     estado == 'aprobado_supervisor',
          rechazado:  estado == 'rechazado_jefe_ops',
        ),
        _buildPaso(
          label: 'Flota (carga realizada)',
          completado: estado == 'completada',
          activo:     estado == 'pendiente_flota',
          rechazado:  false,
        ),

        // Motivo rechazo
        if (sol['motivo_rechazo_supervisor'] != null ||
            sol['motivo_rechazo_jefe_ops'] != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _red.withValues(alpha: 0.25)),
            ),
            child: Text(
              'Rechazada: ${sol['motivo_rechazo_supervisor'] ?? sol['motivo_rechazo_jefe_ops']}',
              style: const TextStyle(color: Color(0xFFFF8080), fontSize: 12),
            ),
          ),
        ],

        // Si fue rechazada, mostrar botón para nueva solicitud
        if (rechazada) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _enviando ? null : () async {
                setState(() { _solicitud = null; _sub?.cancel(); });
              },
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Nueva solicitud'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _accent,
                side: const BorderSide(color: _accent),
              ),
            ),
          ),
        ],

        if (estado == 'completada') ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _green.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: _green, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Carga completada por Flota',
                  style: const TextStyle(color: _green, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() { _solicitud = null; _sub?.cancel(); }),
            child: const Text('Cerrar', style: TextStyle(color: _textDim)),
          ),
        ],
      ],
    );
  }

  Widget _buildPaso({
    required String label,
    required bool completado,
    required bool activo,
    required bool rechazado,
  }) {
    final Color color;
    final IconData icono;
    final String estado;

    if (rechazado) {
      color = _red;
      icono = Icons.cancel_outlined;
      estado = 'Rechazado';
    } else if (completado) {
      color = _green;
      icono = Icons.check_circle;
      estado = 'Aprobado';
    } else if (activo) {
      color = _orange;
      icono = Icons.pending_outlined;
      estado = 'En proceso';
    } else {
      color = Colors.white24;
      icono = Icons.radio_button_unchecked;
      estado = 'Pendiente';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icono, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: completado || activo || rechazado
                        ? Colors.white
                        : Colors.white38,
                    fontSize: 13)),
          ),
          Text(estado,
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static const _ordenEstados = [
    'pendiente_supervisor',
    'aprobado_supervisor',
    'pendiente_flota',
    'completada',
  ];

  bool _estadoGte(String estado, String referencia) {
    final idxEstado = _ordenEstados.indexOf(estado);
    final idxRef    = _ordenEstados.indexOf(referencia);
    if (idxEstado < 0 || idxRef < 0) return false;
    return idxEstado >= idxRef;
  }
}

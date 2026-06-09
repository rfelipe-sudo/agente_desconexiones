import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/services/sol_combustible_service.dart';
import 'package:agente_desconexiones/widgets/combustible_format.dart';

/// Solicitud de combustible adicional del supervisor → jefe de operaciones.
class SolCombSupervisorWidget extends StatefulWidget {
  const SolCombSupervisorWidget({
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
  State<SolCombSupervisorWidget> createState() => _SolCombSupervisorWidgetState();
}

class _SolCombSupervisorWidgetState extends State<SolCombSupervisorWidget> {
  static const _surface = Color(0xFF1A2535);
  static const _border = Color(0xFF1E3A5F);
  static const _accent = Color(0xFF00D9FF);
  static const _green = Color(0xFF22C55E);
  static const _orange = Color(0xFFF59E0B);
  static const _red = Color(0xFFEF4444);
  static const _textDim = Color(0xFF8FA8C8);

  final _svc = SolCombustibleService();

  Map<String, dynamic>? _solicitud;
  bool _cargando = true;
  bool _enviando = false;

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
      final sol = await _svc.solicitudActivaSupervisor(widget.rut);
      if (mounted) {
        setState(() {
          _solicitud = sol;
          _cargando = false;
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
    final id = int.tryParse(solicitudId) ?? 0;
    _sub = Supabase.instance.client
        .from('sol_comb_adicional')
        .stream(primaryKey: ['id'])
        .eq('id', id)
        .listen((rows) {
      if (!mounted || rows.isEmpty) return;
      setState(() => _solicitud = rows.first);
    });
  }

  Future<void> _solicitar() async {
    setState(() => _enviando = true);
    try {
      final sol = await _svc.crearSolicitudAdicionalSupervisor(
        rutSupervisor: widget.rut,
        nombreSupervisor: widget.nombre,
        saldoLitros: widget.saldoLitros,
        saldoPesos: widget.saldoPesos,
      );
      if (mounted) {
        setState(() => _solicitud = sol);
        _suscribir(sol['id'].toString());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Solicitud enviada al jefe de operaciones'),
          ),
        );
      }
    } on StateError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  String _estadoLabel(String estado) => switch (estado) {
        'pendiente_jefe_ops' => 'Pendiente jefe de operaciones',
        'aprobado_supervisor' => 'Aprobada por supervisor',
        'pendiente_flota' => 'Autorizada — en flota',
        'completada' => 'Completada',
        'rechazado_jefe_ops' => 'Rechazada por jefe de operaciones',
        'rechazado_supervisor' => 'Rechazada',
        _ => estado,
      };

  Color _estadoColor(String estado) => switch (estado) {
        'pendiente_jefe_ops' || 'aprobado_supervisor' => _orange,
        'pendiente_flota' => _accent,
        'completada' => _green,
        'rechazado_jefe_ops' || 'rechazado_supervisor' => _red,
        _ => _textDim,
      };

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
        ),
      );
    }

    if (_solicitud == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '¿Necesitas combustible adicional?',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'La solicitud va directo al jefe de operaciones.',
              style: TextStyle(color: _textDim, fontSize: 12),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _enviando ? null : _solicitar,
              icon: _enviando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.local_gas_station, size: 18),
              label: Text(_enviando ? 'Enviando…' : 'Solicitar carga extra'),
              style: FilledButton.styleFrom(
                backgroundColor: _orange,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      );
    }

    final estado = _solicitud!['estado']?.toString() ?? '';
    final monto = CombustibleFormat.toDouble(
      _solicitud!['monto_aprobado'] ?? _solicitud!['monto_sugerido'],
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _estadoColor(estado).withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_gas_station, color: _estadoColor(estado), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _estadoLabel(estado),
                  style: TextStyle(
                    color: _estadoColor(estado),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Monto sugerido: ${CombustibleFormat.formatMoney(monto)}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

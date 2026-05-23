import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/services/sol_combustible_service.dart';

class FlotaExtraScreen extends StatefulWidget {
  const FlotaExtraScreen({super.key});

  @override
  State<FlotaExtraScreen> createState() => _FlotaExtraScreenState();
}

class _FlotaExtraScreenState extends State<FlotaExtraScreen>
    with SingleTickerProviderStateMixin {
  static const _bg      = Color(0xFF0A0F1E);
  static const _surface = Color(0xFF0D1B2A);
  static const _textDim = Color(0xFF8FA8C8);
  static const _cyan    = Color(0xFF00D9FF);

  late final TabController _tabs;
  final _svc = SolCombustibleService();

  String _rut = '';
  List<Map<String, dynamic>> _pendientes = [];
  List<Map<String, dynamic>> _historico  = [];
  bool _loadingH = true;
  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (_tabs.index == 1 && _loadingH) _cargarHistorico();
    });
    _init();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _rut = prefs.getString('rut_tecnico') ?? prefs.getString('user_rut') ?? '';
    _suscribir();
  }

  void _suscribir() {
    _sub = Supabase.instance.client
        .from('sol_comb_adicional')
        .stream(primaryKey: ['id'])
        .eq('estado', 'pendiente_flota')
        .listen((rows) {
      if (!mounted) return;
      setState(() => _pendientes =
          rows.where((r) => r['estado'] == 'pendiente_flota').toList());
    });
  }

  Future<void> _cargarHistorico() async {
    setState(() => _loadingH = true);
    try {
      final rows = await Supabase.instance.client
          .from('sol_comb_adicional')
          .select()
          .inFilter('estado', ['completada', 'rechazado_jefe_ops'])
          .order('created_at', ascending: false)
          .limit(50);
      if (mounted) setState(() => _historico = (rows as List).cast());
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingH = false);
    }
  }

  Future<void> _confirmarCarga(Map<String, dynamic> sol) async {
    final monto = sol['monto_aprobado'] as int? ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('Confirmar carga',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Técnico: ${sol['nombre_solicitante'] ?? '-'}',
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _cyan.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _cyan.withValues(alpha: 0.4)),
              ),
              child: Column(children: [
                const Text('Monto aprobado',
                    style: TextStyle(color: _textDim, fontSize: 12)),
                const SizedBox(height: 4),
                Text('\$${monto.toString()}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold)),
              ]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: _textDim)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _cyan),
            child: const Text('Confirmar carga',
                style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _svc.completarAdicional(
        solicitudId: sol['id'] as String,
        rutFlota: _rut,
      );
      setState(() => _pendientes.removeWhere((r) => r['id'] == sol['id']));
      _loadingH = true;
      _cargarHistorico();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        title: const Text('Solicitud Extra',
            style: TextStyle(
                color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: _cyan,
          labelColor: _cyan,
          unselectedLabelColor: _textDim,
          tabs: [
            Tab(text: 'Pendientes (${_pendientes.length})'),
            const Tab(text: 'Histórico'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_buildPendientes(), _buildHistorico()],
      ),
    );
  }

  Widget _buildPendientes() {
    if (_pendientes.isEmpty) {
      return const Center(
        child: Text('Sin solicitudes pendientes',
            style: TextStyle(color: _textDim)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _pendientes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _CardExtra(
        sol: _pendientes[i],
        onConfirmar: () => _confirmarCarga(_pendientes[i]),
      ),
    );
  }

  Widget _buildHistorico() {
    if (_loadingH) {
      return const Center(child: CircularProgressIndicator(color: _cyan));
    }
    if (_historico.isEmpty) {
      return const Center(
        child: Text('Sin registros', style: TextStyle(color: _textDim)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _historico.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _CardExtra(sol: _historico[i]),
    );
  }
}

// ─────────────────────────────────────────────────────────────

class _CardExtra extends StatelessWidget {
  const _CardExtra({required this.sol, this.onConfirmar});

  final Map<String, dynamic> sol;
  final VoidCallback? onConfirmar;

  static const _surface = Color(0xFF0D1B2A);
  static const _cyan    = Color(0xFF00D9FF);

  String _fmt(dynamic val) {
    if (val == null) return '-';
    try {
      final dt = DateTime.parse(val as String).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return val.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado    = sol['estado'] as String? ?? '';
    final monto     = sol['monto_aprobado'] as int?;
    final sugerido  = sol['monto_sugerido'] as int?;

    Color borderColor;
    switch (estado) {
      case 'completada':
        borderColor = Colors.green.withValues(alpha: 0.4);
        break;
      case 'rechazado_jefe_ops':
        borderColor = Colors.red.withValues(alpha: 0.4);
        break;
      default:
        borderColor = _cyan.withValues(alpha: 0.5);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.local_gas_station_rounded,
                color: _cyan, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(sol['nombre_solicitante'] as String? ?? '-',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
            ),
            _Chip(estado: estado),
          ]),
          const SizedBox(height: 10),
          if (sugerido != null) _InfoRow('Monto sugerido', '\$$sugerido'),
          if (monto != null) _InfoRow('Monto aprobado', '\$$monto'),
          _InfoRow('Solicitada', _fmt(sol['created_at'])),
          if (estado == 'completada')
            _InfoRow('Completada', _fmt(sol['completada_flota_at'])),
          if (estado == 'rechazado_jefe_ops') ...[
            _InfoRow('Rechazada', _fmt(sol['updated_at'])),
            if (sol['motivo_rechazo_jefe_ops'] != null)
              _InfoRow('Motivo', sol['motivo_rechazo_jefe_ops'] as String),
          ],
          if (onConfirmar != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onConfirmar,
                icon: const Icon(Icons.local_gas_station_rounded, size: 18),
                label: const Text('Confirmar carga'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _cyan,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Text('$label: ',
            style: const TextStyle(color: Color(0xFF8FA8C8), fontSize: 12)),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.estado});
  final String estado;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (estado) {
      'pendiente_flota'    => (const Color(0xFF00D9FF), 'Pendiente'),
      'completada'         => (Colors.green, 'Completada'),
      'rechazado_jefe_ops' => (Colors.red, 'Rechazada'),
      _                    => (Colors.grey, estado),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

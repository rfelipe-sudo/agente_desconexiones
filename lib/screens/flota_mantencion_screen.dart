import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/services/sol_combustible_service.dart';

class FlotaMantencionScreen extends StatefulWidget {
  const FlotaMantencionScreen({super.key});

  @override
  State<FlotaMantencionScreen> createState() => _FlotaMantencionScreenState();
}

class _FlotaMantencionScreenState extends State<FlotaMantencionScreen>
    with SingleTickerProviderStateMixin {
  static const _bg      = Color(0xFF0A0F1E);
  static const _surface = Color(0xFF0D1B2A);
  static const _textDim = Color(0xFF8FA8C8);
  static const _purple  = Color(0xFF8B5CF6);

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
        .from('sol_mantencion')
        .stream(primaryKey: ['id'])
        .eq('estado', 'pendiente')
        .listen((rows) {
      if (!mounted) return;
      setState(() => _pendientes =
          rows.where((r) => r['estado'] == 'pendiente').toList());
    });
  }

  Future<void> _cargarHistorico() async {
    setState(() => _loadingH = true);
    try {
      final rows = await Supabase.instance.client
          .from('sol_mantencion')
          .select()
          .eq('estado', 'completada')
          .order('completada_at', ascending: false)
          .limit(50);
      if (mounted) setState(() => _historico = (rows as List).cast());
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingH = false);
    }
  }

  Future<void> _completar(Map<String, dynamic> sol) async {
    final notasCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('Marcar completada',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${sol['nombre_tecnico'] ?? '-'} — ${sol['patente'] ?? '-'}',
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 4),
            Text('Tipo: ${sol['tipo'] ?? '-'}',
                style: const TextStyle(color: _textDim, fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: notasCtrl,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Notas (opcional)',
                hintStyle: const TextStyle(color: _textDim),
                filled: true,
                fillColor: const Color(0xFF0A0F1E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                      color: _purple.withValues(alpha: 0.4)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                      color: _purple.withValues(alpha: 0.4)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _purple),
                ),
              ),
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
            style: ElevatedButton.styleFrom(backgroundColor: _purple),
            child: const Text('Confirmar',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _svc.completarMantencion(
        solicitudId: sol['id'] as int,
        rutFlota: _rut,
        notas: notasCtrl.text.trim().isEmpty ? null : notasCtrl.text.trim(),
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
    notasCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        title: const Text('Solicitud de Mantención',
            style: TextStyle(
                color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: _purple,
          labelColor: _purple,
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
      itemBuilder: (_, i) => _CardMantencion(
        sol: _pendientes[i],
        onCompletar: () => _completar(_pendientes[i]),
      ),
    );
  }

  Widget _buildHistorico() {
    if (_loadingH) {
      return const Center(child: CircularProgressIndicator(color: _purple));
    }
    if (_historico.isEmpty) {
      return const Center(
        child: Text('Sin registros completados',
            style: TextStyle(color: _textDim)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _historico.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _CardMantencion(sol: _historico[i]),
    );
  }
}

// ─────────────────────────────────────────────────────────────

class _CardMantencion extends StatelessWidget {
  const _CardMantencion({required this.sol, this.onCompletar});

  final Map<String, dynamic> sol;
  final VoidCallback? onCompletar;

  static const _surface = Color(0xFF0D1B2A);
  static const _purple  = Color(0xFF8B5CF6);

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
    final estado     = sol['estado'] as String? ?? '';
    final completada = estado == 'completada';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: completada
              ? Colors.green.withValues(alpha: 0.4)
              : _purple.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.build_rounded,
                color: completada ? Colors.green : _purple, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(sol['nombre_tecnico'] as String? ?? '-',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
            ),
            _Chip(estado: estado),
          ]),
          const SizedBox(height: 10),
          _InfoRow('Patente', sol['patente'] as String? ?? '-'),
          _InfoRow('Tipo', sol['tipo'] as String? ?? '-'),
          if (sol['kilometraje'] != null)
            _InfoRow('Kilometraje', '${sol['kilometraje']} km'),
          if (sol['descripcion'] != null)
            _InfoRow('Descripción', sol['descripcion'] as String),
          _InfoRow('Solicitada', _fmt(sol['created_at'])),
          if (completada) ...[
            _InfoRow('Completada', _fmt(sol['completada_at'])),
            _InfoRow('Por', sol['completada_por'] as String? ?? '-'),
            if (sol['notas_flota'] != null)
              _InfoRow('Notas', sol['notas_flota'] as String),
          ],
          if (onCompletar != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onCompletar,
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Marcar completada'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _purple,
                  foregroundColor: Colors.white,
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ',
              style: const TextStyle(color: Color(0xFF8FA8C8), fontSize: 12)),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.estado});
  final String estado;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (estado) {
      'pendiente'  => (const Color(0xFF8B5CF6), 'Pendiente'),
      'completada' => (Colors.green, 'Completada'),
      _            => (Colors.grey, estado),
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

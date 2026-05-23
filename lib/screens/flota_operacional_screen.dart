import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/services/sol_combustible_service.dart';

class FlotaOperacionalScreen extends StatefulWidget {
  const FlotaOperacionalScreen({super.key});

  @override
  State<FlotaOperacionalScreen> createState() => _FlotaOperacionalScreenState();
}

class _FlotaOperacionalScreenState extends State<FlotaOperacionalScreen>
    with SingleTickerProviderStateMixin {
  static const _bg      = Color(0xFF0A0F1E);
  static const _surface = Color(0xFF0D1B2A);
  static const _textDim = Color(0xFF8FA8C8);
  static const _orange  = Color(0xFFF59E0B);

  late final TabController _tabs;
  final _svc = SolCombustibleService();

  String _rut = '';
  List<Map<String, dynamic>> _pendientes = [];
  List<Map<String, dynamic>> _historico  = [];
  final Map<int, int?> _montosSugeridos  = {};
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
        .from('sol_comb_operacional')
        .stream(primaryKey: ['id'])
        .eq('estado', 'pendiente')
        .listen((rows) {
      if (!mounted) return;
      final pending = rows.where((r) => r['estado'] == 'pendiente').toList();
      setState(() => _pendientes = pending);
      _calcularMontosSugeridos(pending);
    });
  }

  void _calcularMontosSugeridos(List<Map<String, dynamic>> rows) {
    for (final sol in rows) {
      final id  = sol['id'] as int;
      final rut = sol['rut_tecnico'] as String? ?? '';
      if (_montosSugeridos.containsKey(id) || rut.isEmpty) continue;
      _montosSugeridos[id] = null; // marca como "calculando"
      _svc.calcularMontoSugerido(rut: rut).then((monto) {
        if (!mounted) return;
        setState(() => _montosSugeridos[id] = monto);
      }).catchError((_) {});
    }
  }

  Future<void> _cargarHistorico() async {
    setState(() => _loadingH = true);
    try {
      final rows = await Supabase.instance.client
          .from('sol_comb_operacional')
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
    final id    = sol['id'] as int;
    final monto = _montosSugeridos[id];

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('Confirmar carga', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${sol['nombre_tecnico'] ?? '-'}  •  ${sol['patente'] ?? '-'}',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _orange.withValues(alpha: 0.4)),
              ),
              child: Column(children: [
                const Text('Monto recomendado',
                    style: TextStyle(color: _textDim, fontSize: 12)),
                const SizedBox(height: 4),
                monto != null
                    ? Text('\$$monto',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold))
                    : const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _orange)),
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
            style: ElevatedButton.styleFrom(backgroundColor: _orange),
            child: const Text('Confirmar',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _svc.completarOperacional(
        solicitudId: sol['id'] as int,
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
        title: const Text('Solicitud Operacional',
            style: TextStyle(
                color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: _orange,
          labelColor: _orange,
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
        child: Text('Sin alertas pendientes', style: TextStyle(color: _textDim)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _pendientes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final id = _pendientes[i]['id'] as int;
        return _CardOperacional(
          sol: _pendientes[i],
          montoSugerido: _montosSugeridos[id],
          onCompletar: () => _completar(_pendientes[i]),
        );
      },
    );
  }

  Widget _buildHistorico() {
    if (_loadingH) {
      return const Center(child: CircularProgressIndicator(color: _orange));
    }
    if (_historico.isEmpty) {
      return const Center(
        child: Text('Sin registros completados', style: TextStyle(color: _textDim)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _historico.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _CardOperacional(sol: _historico[i]),
    );
  }
}

// ─────────────────────────────────────────────────────────────

class _CardOperacional extends StatelessWidget {
  const _CardOperacional({required this.sol, this.montoSugerido, this.onCompletar});

  final Map<String, dynamic> sol;
  final int? montoSugerido;
  final VoidCallback? onCompletar;

  static const _surface = Color(0xFF0D1B2A);
  static const _textDim = Color(0xFF8FA8C8);
  static const _orange  = Color(0xFFF59E0B);

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
    final estado  = sol['estado'] as String? ?? '';
    final litros  = (sol['saldo_litros'] as num?)?.toStringAsFixed(1) ?? '-';
    final pesos   = sol['saldo_pesos'];
    final completada = estado == 'completada';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: completada
              ? Colors.green.withValues(alpha: 0.4)
              : _orange.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.warning_amber_rounded,
                color: completada ? Colors.green : _orange, size: 20),
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
          _InfoRow('Saldo litros', '$litros L'),
          if (pesos != null) _InfoRow('Saldo pesos', '\$$pesos'),
          if (onCompletar != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _orange.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Monto recomendado',
                      style: TextStyle(color: _textDim, fontSize: 12)),
                  montoSugerido != null
                      ? Text('\$$montoSugerido',
                          style: const TextStyle(
                              color: _orange,
                              fontSize: 15,
                              fontWeight: FontWeight.bold))
                      : const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _orange)),
                ],
              ),
            ),
            const SizedBox(height: 4),
          ],
          _InfoRow('Creada', _fmt(sol['created_at'])),
          if (completada) ...[
            _InfoRow('Completada', _fmt(sol['completada_at'])),
            _InfoRow('Por', sol['completada_por'] as String? ?? '-'),
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
                  backgroundColor: _orange,
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
      'pendiente'  => (const Color(0xFFF59E0B), 'Pendiente'),
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

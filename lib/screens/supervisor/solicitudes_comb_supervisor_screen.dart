import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/services/sol_combustible_service.dart';
import 'package:agente_desconexiones/widgets/combustible_format.dart';

class SolicitudesCombSupervisorScreen extends StatefulWidget {
  const SolicitudesCombSupervisorScreen({super.key});

  @override
  State<SolicitudesCombSupervisorScreen> createState() =>
      _SolicitudesCombSupervisorScreenState();
}

class _SolicitudesCombSupervisorScreenState
    extends State<SolicitudesCombSupervisorScreen> {
  static const _bg      = Color(0xFF0A0F1E);
  static const _surface = Color(0xFF0D1B2A);
  static const _border  = Color(0xFF1E3A5F);
  static const _accent  = Color(0xFF00D9FF);
  static const _green   = Color(0xFF22C55E);
  static const _orange  = Color(0xFFF59E0B);
  static const _red     = Color(0xFFEF4444);
  static const _textDim = Color(0xFF8FA8C8);

  final _svc = SolCombustibleService();

  List<Map<String, dynamic>> _pendientes = [];
  List<Map<String, dynamic>> _historial  = [];
  bool    _cargando = true;
  String? _rutSupervisor;

  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _rutSupervisor = prefs.getString('rut_tecnico') ??
        prefs.getString('user_rut') ?? '';
    await _cargar();
    _suscribir();
  }

  Future<void> _cargar() async {
    try {
      final results = await Future.wait<dynamic>([
        _svc.listarParaSupervisor(),
        Supabase.instance.client
            .from('sol_comb_adicional')
            .select()
            .neq('estado', 'pendiente_supervisor')
            .order('created_at', ascending: false)
            .limit(20),
      ]);
      if (mounted) {
        setState(() {
          _pendientes = results[0] as List<Map<String, dynamic>>;
          _historial  = (results[1] as List).cast();
          _cargando   = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _suscribir() {
    _sub = Supabase.instance.client
        .from('sol_comb_adicional')
        .stream(primaryKey: ['id'])
        .eq('estado', 'pendiente_supervisor')
        .listen((rows) {
      if (!mounted) return;
      setState(() => _pendientes = rows.cast());
    });
  }

  // ── Acciones ─────────────────────────────────────────────────────────────

  Future<void> _aprobar(Map<String, dynamic> sol) async {
    final montoSugerido = (sol['monto_sugerido'] as num?)?.toInt() ?? 15000;
    final ctrl = TextEditingController(text: '$montoSugerido');

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('Aprobar solicitud',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Técnico: ${sol['nombre_solicitante'] ?? sol['rut_solicitante']}',
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 4),
            Text(
              'Saldo actual: ${CombustibleFormat.formatMoney(sol['saldo_pesos_actual'] ?? 0)}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 16),
            const Text('Monto a aprobar (\$)',
                style: TextStyle(color: _textDim, fontSize: 12)),
            const SizedBox(height: 6),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF1A2C3D),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _accent)),
                prefixText: '\$ ',
                prefixStyle: const TextStyle(color: _textDim),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Sugerido: ${CombustibleFormat.formatMoney(montoSugerido)} (promedio 7d × 1.15)',
              style: const TextStyle(color: _textDim, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: _textDim)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _green),
            child: const Text('Aprobar'),
          ),
        ],
      ),
    );

    if (confirmado != true || !mounted) return;

    final monto = int.tryParse(ctrl.text.replaceAll(RegExp(r'[^\d]'), ''));
    if (monto == null || monto <= 0) return;

    try {
      await _svc.aprobarSupervisor(
        solicitudId:    sol['id'].toString(),
        rutSupervisor:  _rutSupervisor ?? '',
        montoAprobado:  monto,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Solicitud aprobada y enviada a Jefe de Operaciones')),
        );
        await _cargar();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _rechazar(Map<String, dynamic> sol) async {
    final ctrl = TextEditingController();

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('Rechazar solicitud',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Técnico: ${sol['nombre_solicitante'] ?? sol['rut_solicitante']}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            const Text('Motivo del rechazo',
                style: TextStyle(color: _textDim, fontSize: 12)),
            const SizedBox(height: 6),
            TextField(
              controller: ctrl,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF1A2C3D),
                hintText: 'Ingresa el motivo...',
                hintStyle: const TextStyle(color: Colors.white30),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _red)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: _textDim)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _red),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );

    if (confirmado != true || !mounted) return;
    if (ctrl.text.trim().isEmpty) return;

    try {
      await _svc.rechazarSupervisor(
        solicitudId:   sol['id'].toString(),
        rutSupervisor: _rutSupervisor ?? '',
        motivo:        ctrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Solicitud rechazada — se notificó al técnico')),
        );
        await _cargar();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _surface,
          elevation: 0,
          title: const Text('Solicitudes Combustible',
              style: TextStyle(color: Colors.white, fontSize: 17)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white70),
            onPressed: () => Navigator.pop(context),
          ),
          bottom: TabBar(
            labelColor: _accent,
            unselectedLabelColor: _textDim,
            indicatorColor: _accent,
            tabs: [
              Tab(text: 'Pendientes (${_pendientes.length})'),
              Tab(text: 'Historial (${_historial.length})'),
            ],
          ),
        ),
        body: _cargando
            ? const Center(child: CircularProgressIndicator(color: _accent))
            : TabBarView(
                children: [
                  _buildPendientes(),
                  _buildHistorial(),
                ],
              ),
      ),
    );
  }

  Widget _buildPendientes() {
    if (_pendientes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline,
                size: 56, color: _green.withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            const Text('Sin solicitudes pendientes',
                style: TextStyle(color: Colors.white54, fontSize: 15)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _pendientes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _buildCard(_pendientes[i], pendiente: true),
      ),
    );
  }

  Widget _buildHistorial() {
    if (_historial.isEmpty) {
      return const Center(
        child: Text('Sin historial', style: TextStyle(color: Colors.white38)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _historial.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _buildCard(_historial[i], pendiente: false),
    );
  }

  Widget _buildCard(Map<String, dynamic> sol, {required bool pendiente}) {
    final estado     = sol['estado'] as String? ?? '';
    final nombre     = sol['nombre_solicitante'] as String? ?? sol['rut_solicitante'] ?? '—';
    final saldoPesos = (sol['saldo_pesos_actual'] as num?)?.toDouble() ?? 0;
    final sugerido   = (sol['monto_sugerido']   as num?)?.toDouble() ?? 0;
    final aprobado   = (sol['monto_aprobado']   as num?)?.toDouble();
    final createdAt  = DateTime.tryParse(sol['created_at'] as String? ?? '');
    final hace       = createdAt != null
        ? _tiempoDesde(createdAt)
        : '—';

    final estadoColor = _estadoColor(estado);
    final estadoLabel = _estadoLabel(estado);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: pendiente ? _accent.withValues(alpha: 0.3) : _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Text(nombre,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: estadoColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: estadoColor.withValues(alpha: 0.4)),
                ),
                child: Text(estadoLabel,
                    style: TextStyle(
                        color: estadoColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Datos
          _dataRow('Saldo actual',   CombustibleFormat.formatMoney(saldoPesos)),
          _dataRow('Monto sugerido', CombustibleFormat.formatMoney(sugerido),
              color: _orange),
          if (aprobado != null)
            _dataRow('Monto aprobado', CombustibleFormat.formatMoney(aprobado),
                color: _green),
          _dataRow('Hace', hace),

          if (sol['motivo_rechazo_supervisor'] != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _red.withValues(alpha: 0.25)),
              ),
              child: Text(
                'Motivo rechazo: ${sol['motivo_rechazo_supervisor']}',
                style: const TextStyle(color: Color(0xFFFF8080), fontSize: 12),
              ),
            ),
          ],

          // Acciones (solo pendientes)
          if (pendiente) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _rechazar(sol),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Rechazar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _red,
                      side: const BorderSide(color: _red),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _aprobar(sol),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Aprobar'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _green,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _dataRow(String label, String valor, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          children: [
            Text('$label: ',
                style: const TextStyle(color: _textDim, fontSize: 12)),
            Text(valor,
                style: TextStyle(
                    color: color ?? Colors.white70,
                    fontSize: 12,
                    fontWeight:
                        color != null ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      );

  String _tiempoDesde(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    if (d.inHours < 24) return '${d.inHours} h';
    return DateFormat('dd/MM HH:mm').format(dt);
  }

  Color _estadoColor(String estado) => switch (estado) {
        'pendiente_supervisor'  => _orange,
        'aprobado_supervisor'   => const Color(0xFF60A5FA),
        'rechazado_supervisor'  => _red,
        'pendiente_flota'       => _orange,
        'completada'            => _green,
        'rechazado_jefe_ops'    => _red,
        _                       => Colors.grey,
      };

  String _estadoLabel(String estado) => switch (estado) {
        'pendiente_supervisor'  => 'Pendiente',
        'aprobado_supervisor'   => 'En Jefe Ops',
        'rechazado_supervisor'  => 'Rechazada',
        'pendiente_flota'       => 'En Flota',
        'completada'            => 'Completada',
        'rechazado_jefe_ops'    => 'Rechazada',
        _                       => estado,
      };
}

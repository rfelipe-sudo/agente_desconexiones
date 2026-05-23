import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/services/fcm_service.dart';
import 'package:agente_desconexiones/services/sol_combustible_service.dart';
import 'package:agente_desconexiones/widgets/combustible_format.dart';

/// Pantalla del Jefe de Operaciones (Bastián Cáceres).
/// Muestra solicitudes aprobadas por supervisor que esperan su revisión.
class JefeOpsSolicitudesScreen extends StatefulWidget {
  const JefeOpsSolicitudesScreen({super.key});

  @override
  State<JefeOpsSolicitudesScreen> createState() =>
      _JefeOpsSolicitudesScreenState();
}

class _JefeOpsSolicitudesScreenState extends State<JefeOpsSolicitudesScreen> {
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
  String? _rutJefeOps;

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
    _rutJefeOps = prefs.getString('rut_tecnico') ??
        prefs.getString('user_rut') ?? '';

    // Guardar FCM token en roles_flota para notificaciones
    try {
      final token = await FcmService.instance.getToken();
      if (token != null && token.isNotEmpty && _rutJefeOps != null) {
        await _svc.guardarTokenFlota(rut: _rutJefeOps!, token: token);
      }
    } catch (_) {}

    await _cargar();
    _suscribir();
  }

  Future<void> _cargar() async {
    try {
      final results = await Future.wait<dynamic>([
        _svc.listarParaJefeOps(),
        Supabase.instance.client
            .from('sol_comb_adicional')
            .select()
            .inFilter('estado',
                ['pendiente_flota', 'completada', 'rechazado_jefe_ops'])
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
        .eq('estado', 'aprobado_supervisor')
        .listen((rows) {
      if (!mounted) return;
      setState(() => _pendientes = rows.cast());
    });
  }

  // ── Acciones ─────────────────────────────────────────────────────────────

  Future<void> _aprobar(Map<String, dynamic> sol) async {
    final montoAprobado = (sol['monto_aprobado'] as num?)?.toInt() ??
        (sol['monto_sugerido'] as num?)?.toInt() ?? 15000;
    final ctrl = TextEditingController(text: '$montoAprobado');

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('Aprobar y enviar a Flota',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Técnico: ${sol['nombre_solicitante'] ?? sol['rut_solicitante']}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            const Text('Monto a autorizar (\$)',
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
            child: const Text('Autorizar'),
          ),
        ],
      ),
    );

    if (confirmado != true || !mounted) return;

    final monto = int.tryParse(ctrl.text.replaceAll(RegExp(r'[^\d]'), ''));
    if (monto == null || monto <= 0) return;

    try {
      await _svc.aprobarJefeOps(
        solicitudId:   sol['id'].toString(),
        rutJefeOps:    _rutJefeOps ?? '',
        montoAprobado: monto,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Solicitud enviada a Flota')),
        );
        await _cargar();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
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
      await _svc.rechazarJefeOps(
        solicitudId: sol['id'].toString(),
        rutJefeOps:  _rutJefeOps ?? '',
        motivo:      ctrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Solicitud rechazada')),
        );
        await _cargar();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
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
          title: const Text('Jefe de Operaciones — Combustible',
              style: TextStyle(color: Colors.white, fontSize: 16)),
          leading: Navigator.canPop(context)
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                )
              : null,
          bottom: TabBar(
            labelColor: _accent,
            unselectedLabelColor: _textDim,
            indicatorColor: _accent,
            tabs: [
              Tab(text: 'Por autorizar (${_pendientes.length})'),
              const Tab(text: 'Historial'),
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
            const Text('Sin solicitudes por autorizar',
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
    final nombre     = sol['nombre_solicitante'] as String?
                        ?? sol['rut_solicitante'] ?? '—';
    final saldoPesos = (sol['saldo_pesos_actual'] as num?)?.toDouble() ?? 0;
    final aprobado   = (sol['monto_aprobado'] as num?)?.toDouble();
    final sugerido   = (sol['monto_sugerido'] as num?)?.toDouble() ?? 0;
    final createdAt  = DateTime.tryParse(sol['created_at'] as String? ?? '');
    final hace       = createdAt != null ? _tiempoDesde(createdAt) : '—';

    final estadoColor = _estadoColor(estado);
    final estadoLabel = _estadoLabel(estado);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: pendiente ? _orange.withValues(alpha: 0.4) : _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          _row('Saldo actual', CombustibleFormat.formatMoney(saldoPesos)),
          _row('Sugerido', CombustibleFormat.formatMoney(sugerido),
              color: _textDim),
          if (aprobado != null)
            _row('Monto aprobado', CombustibleFormat.formatMoney(aprobado),
                color: _green),
          _row('Hace', hace),

          if (sol['motivo_rechazo_jefe_ops'] != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _red.withValues(alpha: 0.25)),
              ),
              child: Text(
                'Motivo: ${sol['motivo_rechazo_jefe_ops']}',
                style: const TextStyle(color: Color(0xFFFF8080), fontSize: 12),
              ),
            ),
          ],

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
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Autorizar'),
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

  Widget _row(String label, String valor, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          children: [
            Text('$label: ',
                style: const TextStyle(color: _textDim, fontSize: 12)),
            Text(valor,
                style: TextStyle(
                    color: color ?? Colors.white70,
                    fontSize: 12,
                    fontWeight: color == _green
                        ? FontWeight.bold
                        : FontWeight.normal)),
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
        'aprobado_supervisor'  => _orange,
        'pendiente_flota'      => const Color(0xFF60A5FA),
        'completada'           => _green,
        'rechazado_jefe_ops'   => _red,
        _                      => Colors.grey,
      };

  String _estadoLabel(String estado) => switch (estado) {
        'aprobado_supervisor' => 'Pendiente',
        'pendiente_flota'     => 'En Flota',
        'completada'          => 'Completada',
        'rechazado_jefe_ops'  => 'Rechazada',
        _                     => estado,
      };
}

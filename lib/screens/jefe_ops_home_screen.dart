import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/screens/jefe_ops_solicitudes_screen.dart';
import 'package:agente_desconexiones/screens/supervisor/supervisor_reversa_screen.dart';
import 'package:agente_desconexiones/services/fcm_service.dart';
import 'package:agente_desconexiones/services/sol_combustible_service.dart';

class JefeOpsHomeScreen extends StatefulWidget {
  const JefeOpsHomeScreen({super.key});

  @override
  State<JefeOpsHomeScreen> createState() => _JefeOpsHomeScreenState();
}

class _JefeOpsHomeScreenState extends State<JefeOpsHomeScreen> {
  static const _bg      = Color(0xFF0A0F1E);
  static const _surface = Color(0xFF0D1B2A);
  static const _accent  = Color(0xFF00D9FF);
  static const _orange  = Color(0xFFF59E0B);
  static const _textDim = Color(0xFF8FA8C8);

  String _nombre = '';
  int    _pendientes = 0;
  int    _reversaPendientes = 0;

  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  StreamSubscription<List<Map<String, dynamic>>>? _subReversa;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _subReversa?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final rut   = prefs.getString('rut_tecnico') ?? prefs.getString('user_rut') ?? '';
    final nombre = prefs.getString('nombre_tecnico') ?? prefs.getString('user_nombre') ?? 'Jefe de Operaciones';
    if (mounted) setState(() => _nombre = nombre);

    // Guardar FCM token en roles_flota
    try {
      final token = await FcmService.instance.getToken();
      if (token != null && token.isNotEmpty && rut.isNotEmpty) {
        await SolCombustibleService().guardarTokenFlota(rut: rut, token: token);
      }
    } catch (_) {}

    _suscribir();
  }

  void _suscribir() {
    _sub = Supabase.instance.client
        .from('sol_comb_adicional')
        .stream(primaryKey: ['id'])
        .eq('estado', 'aprobado_supervisor')
        .listen((rows) {
      if (!mounted) return;
      setState(() => _pendientes = rows.length);
    });

    _subReversa = Supabase.instance.client
        .from('equipos_reversa')
        .stream(primaryKey: ['id'])
        .eq('estado', 'pendiente_supervision')
        .listen((rows) {
      if (!mounted) return;
      setState(() => _reversaPendientes =
          rows.where((r) => r['estado'] == 'pendiente_supervision').length);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Jefe de Operaciones',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600)),
            if (_nombre.isNotEmpty)
              Text(_nombre,
                  style: const TextStyle(color: _textDim, fontSize: 12)),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Panel de gestión',
                style: TextStyle(
                    color: _textDim,
                    fontSize: 13,
                    letterSpacing: 0.5)),
            const SizedBox(height: 16),
            _buildCard(
              icono: Icons.local_gas_station_rounded,
              titulo: 'Solicitudes de Combustible',
              subtitulo: _pendientes > 0
                  ? '$_pendientes pendiente${_pendientes > 1 ? 's' : ''} de autorización'
                  : 'Sin solicitudes pendientes',
              badge: _pendientes,
              colores: const [Color(0xFFF59E0B), Color(0xFFD97706)],
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                    builder: (_) => const JefeOpsSolicitudesScreen()),
              ),
            ),
            const SizedBox(height: 16),
            _buildCard(
              icono: Icons.swap_horiz_rounded,
              titulo: 'Reversa de Equipos',
              subtitulo: _reversaPendientes > 0
                  ? '$_reversaPendientes equipo${_reversaPendientes > 1 ? 's' : ''} pendiente${_reversaPendientes > 1 ? 's' : ''} de revisión'
                  : 'Sin entregas pendientes',
              badge: _reversaPendientes,
              colores: const [Color(0xFFFF6B35), Color(0xFFE55A2B)],
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                    builder: (_) => const SupervisorReversaScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({
    required IconData icono,
    required String titulo,
    required String subtitulo,
    required List<Color> colores,
    required VoidCallback onTap,
    int badge = 0,
  }) {
    final card = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: colores,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: colores.first.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icono, size: 28, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitulo,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.white70, size: 24),
            ],
          ),
        ),
      ),
    );

    if (badge <= 0) return card;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        Positioned(
          top: -6,
          right: -6,
          child: Container(
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              badge > 9 ? '9+' : '$badge',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _orange,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/models/traspaso_bodega.dart';
import 'package:agente_desconexiones/screens/bodega/bodega_stock_screen.dart';
import 'package:agente_desconexiones/screens/bodega/bodega_traspasos_screen.dart';

class BodegaScreen extends StatefulWidget {
  const BodegaScreen({super.key});

  @override
  State<BodegaScreen> createState() => _BodegaScreenState();
}

class _BodegaScreenState extends State<BodegaScreen> {
  static const _bg      = Color(0xFF0A0F1E);
  static const _surface = Color(0xFF0D1B2A);
  static const _border  = Color(0xFF1E3A5F);
  static const _accent  = Color(0xFF00D9FF);
  static const _orange  = Color(0xFFF59E0B);
  static const _textDim = Color(0xFF8FA8C8);

  final _db = Supabase.instance.client;

  String _nombre = '';
  String _rut    = '';

  int _pendientesCount = 0;
  StreamSubscription<List<Map<String, dynamic>>>? _subTraspasos;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
    _suscribirPendientes();
  }

  @override
  void dispose() {
    _subTraspasos?.cancel();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    final prefs = await SharedPreferences.getInstance();
    final rut   = prefs.getString('rut_tecnico') ??
                  prefs.getString('user_rut') ?? '';
    final row   = await _db
        .from('nomina_bodega')
        .select('nombre')
        .eq('rut', rut)
        .maybeSingle();
    if (mounted) {
      setState(() {
        _rut    = rut;
        _nombre = row?['nombre'] as String? ?? rut;
      });
    }
  }

  void _suscribirPendientes() {
    _subTraspasos = _db
        .from('traspasos_bodega')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .listen((rows) {
      if (!mounted) return;
      final pendientes = rows
          .where((r) => (r['estado'] as String?) == 'pendiente')
          .length;
      setState(() => _pendientesCount = pendientes);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        automaticallyImplyLeading: false,
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.warehouse_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_nombre.isNotEmpty ? _nombre : 'Bodega',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                Text('Panel de Bodega · $_rut',
                    style: const TextStyle(
                        color: _textDim, fontSize: 12),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ]),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 12),
            // ── Card Stock ──────────────────────────────────────
            _BodegaCard(
              icon: Icons.inventory_2_rounded,
              titulo: 'Stock en Terreno',
              descripcion: 'Ver material por técnico y buscar por tipo',
              gradiente: const LinearGradient(
                colors: [Color(0xFF0077B6), Color(0xFF00D9FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              sombra: _accent,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const BodegaStockScreen())),
            ),
            const SizedBox(height: 20),
            // ── Card Traspasos ──────────────────────────────────
            _BodegaCard(
              icon: Icons.swap_horiz_rounded,
              titulo: 'Solicitudes de Traspaso',
              descripcion: _pendientesCount > 0
                  ? '$_pendientesCount solicitud${_pendientesCount == 1 ? '' : 'es'} pendiente${_pendientesCount == 1 ? '' : 's'} de aprobación'
                  : 'Aprobar transferencias entre técnicos',
              gradiente: const LinearGradient(
                colors: [Color(0xFFD97706), Color(0xFFF59E0B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              sombra: _orange,
              badge: _pendientesCount,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const BodegaTraspassosScreen())),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Card reutilizable ───────────────────────────────────────────

class _BodegaCard extends StatelessWidget {
  final IconData icon;
  final String   titulo;
  final String   descripcion;
  final Gradient gradiente;
  final Color    sombra;
  final int      badge;
  final VoidCallback onTap;

  const _BodegaCard({
    required this.icon,
    required this.titulo,
    required this.descripcion,
    required this.gradiente,
    required this.sombra,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            gradient: gradiente,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: sombra.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Row(children: [
              Stack(clipBehavior: Clip.none, children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 32),
                ),
                if (badge > 0)
                  Positioned(
                    top: -4, right: -4,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$badge',
                        style: TextStyle(
                          color: sombra,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(descripcion,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.7), size: 28),
            ]),
          ),
        ),
      ),
    );
  }
}

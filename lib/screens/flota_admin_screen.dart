import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/screens/flota_operacional_screen.dart';
import 'package:agente_desconexiones/screens/flota_extra_screen.dart';
import 'package:agente_desconexiones/screens/flota_mantencion_screen.dart';
import 'package:agente_desconexiones/services/fcm_service.dart';
import 'package:agente_desconexiones/services/sol_combustible_service.dart';

/// Home de Abraham Guzmán (Flota) — 3 cards de gestión.
class FlotaAdminScreen extends StatefulWidget {
  const FlotaAdminScreen({super.key});

  @override
  State<FlotaAdminScreen> createState() => _FlotaAdminScreenState();
}

class _FlotaAdminScreenState extends State<FlotaAdminScreen> {
  static const _bg      = Color(0xFF0A0F1E);
  static const _surface = Color(0xFF0D1B2A);
  static const _textDim = Color(0xFF8FA8C8);

  String _nombre = '';
  int    _operacionalCount = 0;
  int    _extraCount       = 0;
  int    _mantencionCount  = 0;

  // Conteos previos e inicialización para detectar nuevas entradas con sonido
  int  _operacionalPrev = 0;
  int  _extraPrev       = 0;
  int  _mantencionPrev  = 0;
  bool _opInit   = false;
  bool _exInit   = false;
  bool _mantInit = false;

  StreamSubscription<List<Map<String, dynamic>>>? _subOp;
  StreamSubscription<List<Map<String, dynamic>>>? _subEx;
  StreamSubscription<List<Map<String, dynamic>>>? _subMant;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _subOp?.cancel();
    _subEx?.cancel();
    _subMant?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final rut   = prefs.getString('rut_tecnico') ?? prefs.getString('user_rut') ?? '';
    final nombre = prefs.getString('nombre_tecnico') ?? prefs.getString('user_nombre') ?? 'Flota';
    if (mounted) setState(() => _nombre = nombre);

    // Guardar FCM token en roles_flota para notificaciones
    try {
      final token = await FcmService.instance.getToken();
      if (token != null && token.isNotEmpty && rut.isNotEmpty) {
        await SolCombustibleService().guardarTokenFlota(rut: rut, token: token);
      }
    } catch (_) {}

    _suscribir();
  }

  void _suscribir() {
    _subOp = Supabase.instance.client
        .from('sol_comb_operacional')
        .stream(primaryKey: ['id'])
        .eq('estado', 'pendiente')
        .listen((rows) {
      if (!mounted) return;
      final n = rows.length;
      if (!_opInit) {
        _opInit = true;
        _operacionalPrev = n;
      } else if (n > _operacionalPrev) {
        FcmService.playAlerta();
      }
      _operacionalPrev = n;
      setState(() => _operacionalCount = n);
    });

    _subEx = Supabase.instance.client
        .from('sol_comb_adicional')
        .stream(primaryKey: ['id'])
        .eq('estado', 'pendiente_flota')
        .listen((rows) {
      if (!mounted) return;
      final n = rows.length;
      if (!_exInit) {
        _exInit = true;
        _extraPrev = n;
      } else if (n > _extraPrev) {
        FcmService.playAlerta();
      }
      _extraPrev = n;
      setState(() => _extraCount = n);
    });

    _subMant = Supabase.instance.client
        .from('sol_mantencion')
        .stream(primaryKey: ['id'])
        .eq('estado', 'pendiente')
        .listen((rows) {
      if (!mounted) return;
      final n = rows.length;
      if (!_mantInit) {
        _mantInit = true;
        _mantencionPrev = n;
      } else if (n > _mantencionPrev) {
        FcmService.playAlerta();
      }
      _mantencionPrev = n;
      setState(() => _mantencionCount = n);
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
            const Text('Panel Flota',
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
            const Text('Gestión de solicitudes',
                style: TextStyle(
                    color: _textDim, fontSize: 13, letterSpacing: 0.5)),
            const SizedBox(height: 16),
            _buildCard(
              icono: Icons.warning_amber_rounded,
              titulo: 'Solicitud Operacional',
              subtitulo: _operacionalCount > 0
                  ? '$_operacionalCount alerta${_operacionalCount > 1 ? 's' : ''} de saldo bajo'
                  : 'Sin alertas pendientes',
              badge: _operacionalCount,
              colores: const [Color(0xFFF59E0B), Color(0xFFD97706)],
              onTap: () => _ir(const FlotaOperacionalScreen()),
            ),
            const SizedBox(height: 14),
            _buildCard(
              icono: Icons.local_gas_station_rounded,
              titulo: 'Solicitud Extra',
              subtitulo: _extraCount > 0
                  ? '$_extraCount solicitud${_extraCount > 1 ? 'es' : ''} autorizada${_extraCount > 1 ? 's' : ''}'
                  : 'Sin solicitudes pendientes',
              badge: _extraCount,
              colores: const [Color(0xFF00D9FF), Color(0xFF0099CC)],
              onTap: () => _ir(const FlotaExtraScreen()),
            ),
            const SizedBox(height: 14),
            _buildCard(
              icono: Icons.build_rounded,
              titulo: 'Solicitud de Mantención',
              subtitulo: _mantencionCount > 0
                  ? '$_mantencionCount solicitud${_mantencionCount > 1 ? 'es' : ''} pendiente${_mantencionCount > 1 ? 's' : ''}'
                  : 'Sin solicitudes pendientes',
              badge: _mantencionCount,
              colores: const [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
              onTap: () => _ir(const FlotaMantencionScreen()),
            ),
          ],
        ),
      ),
    );
  }

  void _ir(Widget screen) {
    Navigator.push<void>(
        context, MaterialPageRoute(builder: (_) => screen));
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
                color: colores.first.withValues(alpha: 0.30),
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
                  color: Colors.white.withValues(alpha: 0.18),
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
                            color: Colors.white.withValues(alpha: 0.82),
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
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              badge > 9 ? '9+' : '$badge',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: colores.first,
                  fontSize: 12,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}

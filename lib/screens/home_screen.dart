import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart'; // TEMP: debug FCM — quitar junto con _mostrarTokenFcm
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:agente_desconexiones/constants/app_constants.dart';
import 'package:agente_desconexiones/constants/app_colors.dart';
import 'package:agente_desconexiones/models/alerta.dart';
import 'package:agente_desconexiones/models/usuario.dart';
import 'package:agente_desconexiones/providers/auth_provider.dart';
import 'package:agente_desconexiones/providers/alertas_provider.dart';
import 'package:agente_desconexiones/screens/alerta_detail_screen.dart';
import 'package:agente_desconexiones/utils/session_manager.dart';
import 'package:agente_desconexiones/widgets/alerta_card.dart';
import 'package:agente_desconexiones/services/alarm_audio_service.dart';
import 'package:agente_desconexiones/services/alertas_cto_service.dart';
import 'package:agente_desconexiones/services/auth_service.dart';
import 'package:agente_desconexiones/services/fcm_service.dart'; // TEMP: debug FCM
import 'package:agente_desconexiones/screens/tu_mes_screen.dart';
import 'package:agente_desconexiones/screens/supervisor/mi_equipo_screen.dart';
import 'package:agente_desconexiones/services/ayuda_service.dart';
import 'package:agente_desconexiones/screens/bodega/bodega_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  late TabController _tabController;
  bool _puedeVerEquipo = false;
  bool _esIto = false;
  bool _esBodega = false;
  bool _checkingBodega = true;
  String _rutSesion = '';
  String _tipoSesion = '';
  List<Map<String, dynamic>> _historialDia = [];
  final _ayudaService = AyudaService();

  // ── Solicitudes de material (badge + notificación background) ──
  StreamSubscription<List<Map<String, dynamic>>>? _subSolicitudesMat;
  int _solicitudesMaterialCount = 0;
  final Set<String> _solicitudesNotificadasHome = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    // Registrar observer para detectar cuando la app se cierra
    WidgetsBinding.instance.addObserver(this);
    
    // Activar wakelock para mantener pantalla encendida
    WakelockPlus.enable();
    
    // Verificar si puede ver equipo
    _checkPuedeVerEquipo();
    _checkEsIto();
    _checkEsBodega();
    _refrescarEtiquetasSesion();
    
    // Inicializar alertas (sin syncUsuarioDesdePrefs aquí: ya aplicó initialize/splash;
    // evita notifyListeners extra y parpadeos con AppWrapper).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _refrescarEtiquetasSesion();
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final alertas = context.read<AlertasProvider>();
      if (auth.usuario != null) {
        alertas.initialize(auth.usuario!);
        // Monitor global: suena cuando llega solicitud de material aunque
        // el usuario no tenga SolicitudMaterialScreen abierta.
        unawaited(FcmService.instance.initSolicitudMonitor());

        if (AppConstants.monitoreoFraudeYAlertasCtoActivo) {
          final alertasCTOService = AlertasCTOService();
          alertasCTOService.onAlertaAgregar = (alerta) {
            alertas.agregarAlertaDesdeServicio(alerta);
          };
          alertasCTOService.onVerificarEstadoAlerta = (alertaId) {
            try {
              return alertas.obtenerEstadoAlerta(alertaId);
            } catch (e) {
              return 'cerrada';
            }
          };
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // ═══════════════════════════════════════════════════════════
    // DETENER ALARMAS CUANDO LA APP SE CIERRA O VA A BACKGROUND
    // ═══════════════════════════════════════════════════════════
    if (state == AppLifecycleState.paused || 
        state == AppLifecycleState.inactive || 
        state == AppLifecycleState.detached) {
      print('🔇 [HomeScreen] App en background/detenida - Deteniendo alarmas...');
      _detenerAlarmas();
    }
    if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _refrescarEtiquetasSesion();
      });
    }
  }

  Future<void> _detenerAlarmas() async {
    try {
      final alarmAudio = AlarmAudioService();
      if (alarmAudio.estaReproduciendo) {
        await alarmAudio.detenerAlarma();
        print('✅ [HomeScreen] Alarma detenida');
      }
    } catch (e) {
      print('⚠️ [HomeScreen] Error deteniendo alarma: $e');
    }
  }

  @override
  void dispose() {
    // Desregistrar observer
    WidgetsBinding.instance.removeObserver(this);
    
    // Detener alarmas antes de cerrar
    _detenerAlarmas();

    // Desactivar wakelock al salir
    WakelockPlus.disable();
    _tabController.dispose();
    _subSolicitudesMat?.cancel();
    super.dispose();
  }

  void _navigateToAlerta(Alerta alerta) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlertaDetailScreen(alerta: alerta),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingBodega) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A1628),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00D9FF))),
      );
    }

    if (_esBodega) return const BodegaScreen();

    final auth = context.watch<AuthProvider>();
    final usuario = auth.usuario;

    if (usuario == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A1628),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF00D9FF)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      appBar: _buildAppBar(usuario),
      body: Column(
        children: [
          // Botones principales
          _buildActionButtons(usuario),

          // Historial del día (solo supervisores)
          if (usuario.esSupervisor) _buildHistorialDiaSupervisor(),

          // Tabs: Pendientes e Historial
          _buildTabBar(),

          // Lista de alertas
          Expanded(
            child: _buildAlertasList(),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(Usuario usuario) {
    return AppBar(
      backgroundColor: const Color(0xFF0D1B2A),
      elevation: 0,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AppColors.creaGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              usuario.esTecnico ? Icons.engineering : Icons.supervisor_account,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  usuario.nombre,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                Text(
                  [
                    usuario.rol.displayName,
                    if (_rutSesion.isNotEmpty) _rutSesion,
                    if (_tipoSesion.isNotEmpty) _tipoSesion,
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8FA8C8),
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        // TEMP: debug FCM — quitar este IconButton, _mostrarTokenFcm y los
        // imports marcados `TEMP:` cuando ya no haga falta capturar el token.
        IconButton(
          icon: const Icon(Icons.bug_report, color: Color(0xFF00D9FF)),
          tooltip: 'Mostrar FCM token',
          onPressed: _mostrarTokenFcm,
        ),
        // Botón Tu Mes
        IconButton(
          icon: const Icon(Icons.calendar_month),
          tooltip: 'Tu Mes',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const TuMesScreen(),
              ),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () async {
            final alertas = context.read<AlertasProvider>();
            final auth = context.read<AuthProvider>();
            if (auth.usuario != null) {
              alertas.cargarAlertas(auth.usuario!);
              if (auth.usuario!.esSupervisor) {
                await _cargarHistorialDia();
              }
            }
          },
        ),
      ],
    );
  }

  // TEMP: debug FCM — borrar este método junto con el IconButton del AppBar.
  Future<void> _mostrarTokenFcm() async {
    final token = await FcmService.instance.getToken();
    if (!mounted) return;
    final t = token ?? '';
    if (t.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: t));
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1B2A),
        title: const Text('FCM Token', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: SelectableText(
            t.isEmpty ? '(token vacío — Firebase aún no entregó token)' : t,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              if (t.isNotEmpty) {
                await Clipboard.setData(ClipboardData(text: t));
              }
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Copiar', style: TextStyle(color: Color(0xFF00D9FF))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar', style: TextStyle(color: Color(0xFF8FA8C8))),
          ),
        ],
      ),
    );
    if (mounted && t.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('FCM token copiado al portapapeles')),
      );
    }
  }

  Widget _buildActionButtons(Usuario usuario) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.5,
        children: [
          _buildActionButton(
            icon: Icons.router,
            label: 'Asistente\nde CTO',
            color: const Color(0xFF00D9FF),
            gradient: const LinearGradient(
              colors: [Color(0xFF00D9FF), Color(0xFF0099CC)],
            ),
            onTap: () {
              Navigator.of(context).pushNamed('/asistente-cto');
            },
          ),
          _buildActionButton(
            icon: Icons.mic,
            label: 'Asistente\nCREA',
            color: const Color(0xFFAB47BC),
            gradient: const LinearGradient(
              colors: [Color(0xFFAB47BC), Color(0xFF7B1FA2)],
            ),
            onTap: () {
              Navigator.of(context).pushNamed('/asistente-crea-terreno');
            },
          ),
          _buildActionButton(
            icon: Icons.wifi_find,
            label: 'WiFi &\nMapas',
            color: const Color(0xFFFF6B35),
            gradient: const LinearGradient(
              colors: [Color(0xFFFF6B35), Color(0xFFE65100)],
            ),
            onTap: () {
              Navigator.of(context).pushNamed('/wifi-mapas');
            },
          ),
          _buildActionButton(
            icon: Icons.support_agent,
            label: 'Ayuda en\nTerreno',
            color: const Color(0xFF4CAF50),
            gradient: const LinearGradient(
              colors: [Color(0xFF4CAF50), Color(0xFF2E7D32)],
            ),
            onTap: () {
              Navigator.of(context).pushNamed('/ayuda-terreno');
            },
          ),
          // Medición de velocidad: activa siempre (el flag de
          // "próximamente" se ignora para esta tarjeta).
          _buildActionButton(
            icon: Icons.speed,
            label: 'Medición\nde Velocidad',
            color: const Color(0xFF00D4AA),
            gradient: const LinearGradient(
              colors: [Color(0xFF00D4AA), Color(0xFF0A84FF)],
            ),
            onTap: () {
              Navigator.of(context).pushNamed('/speed-meter');
            },
          ),
          _buildActionButton(
            icon: Icons.assignment_outlined,
            label: 'Mis\nActividades',
            color: const Color(0xFF0A84FF),
            gradient: const LinearGradient(
              colors: [Color(0xFF0A84FF), Color(0xFF00D4AA)],
            ),
            onTap: () {
              Navigator.of(context).pushNamed('/mis-actividades');
            },
          ),
          _buildActionButton(
            icon: Icons.health_and_safety_outlined,
            label: 'AST',
            color: const Color(0xFF7C3AED),
            gradient: const LinearGradient(
              colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
            ),
            onTap: () {
              Navigator.of(context).pushNamed('/ast');
            },
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              _buildActionButton(
                icon: Icons.inventory_2_outlined,
                label: 'Solicitud\nde Material',
                color: const Color(0xFF10B981),
                gradient: const LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                ),
                onTap: () {
                  Navigator.of(context).pushNamed('/solicitud-material');
                },
              ),
              if (_solicitudesMaterialCount > 0)
                Positioned(
                  top: -6,
                  right: -6,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Color(0xFFEF4444),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$_solicitudesMaterialCount',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
          // Botón Mi Equipo solo para supervisores/ITOs
          if (_puedeVerEquipo)
            _buildActionButton(
              icon: Icons.groups,
              label: 'Mi Equipo',
              color: const Color(0xFFFFA500),
              gradient: const LinearGradient(
                colors: [Color(0xFFFFA500), Color(0xFFFF8C00)],
              ),
              onTap: () {
                Navigator.of(context).pushNamed('/supervisor-equipo');
              },
            ),
          if (_esIto)
            _buildActionButton(
              icon: Icons.manage_accounts_rounded,
              label: 'Panel\nSupervisor',
              color: const Color(0xFF7B61FF),
              gradient: const LinearGradient(
                colors: [Color(0xFF7B61FF), Color(0xFF5C3FCC)],
              ),
              onTap: () {
                Navigator.of(context).pushNamed('/asistente-supervisor');
              },
            ),
          if (_esBodega)
            _buildActionButton(
              icon: Icons.warehouse_rounded,
              label: 'Panel\nBodega',
              color: const Color(0xFFF59E0B),
              gradient: const LinearGradient(
                colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
              ),
              onTap: () {
                Navigator.of(context).pushNamed('/bodega');
              },
            ),
          if (usuario.esSupervisor) ...[
            _buildActionButton(
              icon: Icons.supervisor_account_rounded,
              label: 'Asistente\nSupervisor',
              color: const Color(0xFF00ACC1),
              gradient: const LinearGradient(
                colors: [Color(0xFF00ACC1), Color(0xFF00838F)],
              ),
              onTap: () {
                Navigator.of(context).pushNamed('/asistente-supervisor');
              },
            ),
            _buildActionButton(
              icon: Icons.sos,
              label: 'Solicitudes\nayuda',
              color: const Color(0xFFE53935),
              gradient: const LinearGradient(
                colors: [Color(0xFFE53935), Color(0xFFC62828)],
              ),
              onTap: () {
                Navigator.of(context)
                    .pushNamed('/solicitudes-ayuda')
                    .then((_) => _cargarHistorialDia());
              },
            ),
            _buildActionButton(
              icon: Icons.directions_run,
              label: 'Mi\nactividad',
              color: const Color(0xFF5C6BC0),
              gradient: const LinearGradient(
                colors: [Color(0xFF5C6BC0), Color(0xFF3949AB)],
              ),
              onTap: () {
                Navigator.of(context).pushNamed('/mi-actividad');
              },
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.1);
  }

  Future<void> _refrescarEtiquetasSesion() async {
    if (mounted) {
      try {
        await context.read<AuthProvider>().syncUsuarioDesdePrefs();
      } catch (_) {}
    }
    final rut = await SessionManager.getRutTecnico();
    final tipo = await SessionManager.getTipoPersonal();
    if (mounted) {
      setState(() {
        _rutSesion = rut;
        _tipoSesion = tipo;
      });
    }
    debugPrint('🏠 [HOME] _refrescarEtiquetasSesion rut=$rut');
    if (rut.isNotEmpty) {
      _suscribirSolicitudesMaterial(rut);
      unawaited(FcmService.instance.initSolicitudMonitor());
      unawaited(FcmService.instance.initTraspasoMonitor(rut));
    } else {
      debugPrint('🏠 [HOME] ⚠️  rut vacío — monitores no iniciados');
    }
    // Cargar historial del día si es supervisor
    final usuario = mounted ? context.read<AuthProvider>().usuario : null;
    if (usuario != null && usuario.esSupervisor) {
      await _cargarHistorialDia();
    }
  }

  /// Obtiene el RUT del supervisor usando las mismas claves que SolicitudesAyudaScreen.
  Future<String> _obtenerRutSupervisor() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('rut_supervisor') ??
        prefs.getString('rut_tecnico') ??
        prefs.getString('user_rut') ??
        '';
  }

  void _suscribirSolicitudesMaterial(String rutPropio) {
    if (_esBodega) return; // bodega no recibe notificaciones de solicitudes
    _subSolicitudesMat?.cancel();
    _subSolicitudesMat = Supabase.instance.client
        .from('solicitudes_material')
        .stream(primaryKey: ['id'])
        .eq('estado', 'pendiente')
        .listen((rows) {
      if (!mounted || _esBodega) return;
      final ajenas = rows
          .where((r) => (r['rut_solicitante'] as String?) != rutPropio)
          .toList();
      final count = ajenas.length;

      for (final r in ajenas) {
        final id = r['id'] as String? ?? '';
        if (!_solicitudesNotificadasHome.contains(id)) {
          _solicitudesNotificadasHome.add(id);
          unawaited(FcmService.playAlerta());
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: const Color(0xFF22C55E),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 10),
            margin: const EdgeInsets.all(12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Row(children: [
              const Icon(Icons.inventory_2_outlined, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('¡Solicitud de material!',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                    Text(
                      '${r['nombre_solicitante'] ?? 'Técnico'} · ${r['tipo_material'] ?? ''}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ]),
            action: SnackBarAction(
              label: 'Ver',
              textColor: Colors.white,
              onPressed: () =>
                  Navigator.of(context).pushNamed('/solicitud-material'),
            ),
          ));
          break;
        }
      }

      if (mounted) setState(() => _solicitudesMaterialCount = count);
    });
  }

  Future<void> _cargarHistorialDia() async {
    try {
      final rut = await _obtenerRutSupervisor();
      if (rut.isEmpty) return;
      final lista = await _ayudaService.obtenerHistorialAtencionDia(rut);
      if (mounted) setState(() => _historialDia = lista);
    } catch (_) {}
  }

  Widget _buildHistorialDiaSupervisor() {
    if (_historialDia.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_outline_rounded,
                  color: Color(0xFF00D9FF), size: 15),
              const SizedBox(width: 6),
              const Text(
                'ACTIVIDADES COMPLETADAS DEL DÍA',
                style: TextStyle(
                  color: Color(0xFF00D9FF),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Text(
                '${_historialDia.length}',
                style: const TextStyle(
                  color: Color(0xFF00D9FF),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._historialDia.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 6,
                      height: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0xFF30D158),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ayuda a ${item['nombre_tecnico']}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${item['hora_desde']} – ${item['hora_hasta']}',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Future<void> _checkPuedeVerEquipo() async {
    await SessionManager.init();
    final puede = await _authService.puedeVerEquipo();
    if (mounted) {
      setState(() {
        _puedeVerEquipo = puede;
      });
    }
  }

  Future<void> _checkEsIto() async {
    await SessionManager.init();
    final rol = await SessionManager.getRol();
    if (mounted) {
      setState(() {
        _esIto = rol == 'ito';
      });
    }
  }

  Future<void> _checkEsBodega() async {
    final prefs = await SharedPreferences.getInstance();
    final rut   = prefs.getString('rut_tecnico') ??
                  prefs.getString('user_rut') ??
                  prefs.getString('rut') ?? '';
    if (rut.isEmpty) {
      if (mounted) setState(() => _checkingBodega = false);
      return;
    }
    try {
      final row = await Supabase.instance.client
          .from('nomina_bodega')
          .select('rut')
          .eq('rut', rut)
          .maybeSingle();
      if (mounted) {
        setState(() { _esBodega = row != null; _checkingBodega = false; });
        if (_esBodega) {
          // Bodega no debe recibir solicitudes de material
          _subSolicitudesMat?.cancel();
          _subSolicitudesMat = null;
        }
      }
    } catch (_) {
      if (mounted) setState(() => _checkingBodega = false);
    }
  }

  Widget _buildProximamenteActionButton({
    required IconData icon,
    required String label,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Próximamente'),
              duration: Duration(seconds: 2),
              backgroundColor: Color(0xFF1E3A5F),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.grey[800]!, Colors.grey[900]!],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF3D4F5F)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white38, size: 28),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Próximamente',
                style: TextStyle(
                  color: Color(0xFF8FA8C8),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().scale(begin: const Offset(0.95, 0.95));
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 32,
                color: Colors.white,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().scale(begin: const Offset(0.95, 0.95));
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E3A5F)),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: AppColors.creaGradient,
          borderRadius: BorderRadius.circular(10),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.white,
        unselectedLabelColor: const Color(0xFF8FA8C8),
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(text: 'Alertas Pendientes'),
          Tab(text: 'Historial de DX'),
        ],
      ),
    );
  }

  Widget _buildAlertasList() {
    return Consumer<AlertasProvider>(
      builder: (context, alertasProvider, _) {
        if (alertasProvider.isLoading) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF00D9FF)),
          );
        }
        
        return TabBarView(
          controller: _tabController,
          children: [
            // Tab 1: Pendientes (todas las alertas que NO están resueltas)
            _buildListaAlertas(
              [
                ...alertasProvider.alertasPorEstado(EstadoAlerta.pendiente),
                ...alertasProvider.alertasPorEstado(EstadoAlerta.enAtencion),
                ...alertasProvider.alertasPorEstado(EstadoAlerta.postergada),
                ...alertasProvider.alertasPorEstado(EstadoAlerta.enRevisionCalidad),
                ...alertasProvider.alertasPorEstado(EstadoAlerta.escalada),
              ],
              emptyMessage: 'No hay alertas pendientes',
            ),
            
            // Tab 2: Historial (SOLO alertas resueltas: regularizada o cerrada)
            _buildListaAlertas(
              [
                ...alertasProvider.alertasPorEstado(EstadoAlerta.regularizada),
                ...alertasProvider.alertasPorEstado(EstadoAlerta.cerrada),
              ],
              emptyMessage: 'No hay historial de alertas',
            ),
          ],
        );
      },
    );
  }

  Widget _buildListaAlertas(List<Alerta> alertas, {required String emptyMessage}) {
    if (alertas.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: const Color(0xFF5C7A99),
            ),
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              style: const TextStyle(
                color: Color(0xFF8FA8C8),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: () async {
        final auth = context.read<AuthProvider>();
        final alertasProvider = context.read<AlertasProvider>();
        if (auth.usuario != null) {
          await alertasProvider.cargarAlertas(auth.usuario!);
        }
      },
      color: const Color(0xFF00D9FF),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: alertas.length,
        itemBuilder: (context, index) {
          final alerta = alertas[index];
          return AlertaCard(
            alerta: alerta,
            onTap: () => _navigateToAlerta(alerta),
          ).animate(delay: (index * 100).ms).fadeIn().slideX(begin: 0.1);
        },
      ),
    );
  }
}

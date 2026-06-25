import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'package:agente_desconexiones/utils/rol_helper.dart';
import 'package:agente_desconexiones/utils/session_manager.dart';
import 'package:agente_desconexiones/widgets/alerta_card.dart';
import 'package:agente_desconexiones/services/alarm_audio_service.dart';
import 'package:agente_desconexiones/services/alertas_cto_service.dart';
import 'package:agente_desconexiones/services/auth_service.dart';
import 'package:agente_desconexiones/services/fcm_service.dart';
import 'package:agente_desconexiones/services/app_tecnico_open_service.dart';
import 'package:agente_desconexiones/services/material_alerta_estado.dart';
import 'package:agente_desconexiones/screens/wifi_mapas_screen.dart';
import 'package:agente_desconexiones/screens/wifi_cobertura_screen.dart';
import 'package:agente_desconexiones/screens/tu_mes_screen.dart';
import 'package:agente_desconexiones/screens/supervisor/mi_equipo_screen.dart';
import 'package:agente_desconexiones/services/ayuda_service.dart';
import 'package:agente_desconexiones/services/supabase_service.dart';
import 'package:agente_desconexiones/services/ubicacion_service.dart';
import 'package:agente_desconexiones/models/solicitud_ayuda.dart';
import 'package:agente_desconexiones/screens/admin/monitor_screen.dart';
import 'package:agente_desconexiones/screens/bodega/bodega_screen.dart';
import 'package:agente_desconexiones/screens/flota_admin_screen.dart';
import 'package:agente_desconexiones/screens/jefe_ops_home_screen.dart';
import 'package:agente_desconexiones/services/comunicado_service.dart';
import 'package:agente_desconexiones/services/logistica_service.dart';
import 'package:agente_desconexiones/widgets/perfil_tecnico_sheet.dart';
import 'package:agente_desconexiones/providers/alerta_provider.dart';
import 'package:agente_desconexiones/utils/navegacion_con_cortina.dart';
import 'package:agente_desconexiones/screens/asistente_cto_screen.dart';
import 'package:agente_desconexiones/screens/asistente_crea_terreno_screen.dart';
import 'package:agente_desconexiones/screens/ayuda_terreno_screen.dart';
import 'package:agente_desconexiones/screens/ast_login_screen.dart';
import 'package:agente_desconexiones/screens/solicitud_material_screen.dart';
import 'package:agente_desconexiones/screens/mis_actividades_screen.dart';
import 'package:agente_desconexiones/screens/supervisor/mi_equipo_nyquist_screen.dart';
import 'package:agente_desconexiones/screens/supervisor/asistente_supervisor_screen.dart';
import 'package:agente_desconexiones/screens/ito/informe_auditoria_calidad_screen.dart';
import 'package:agente_desconexiones/screens/supervisor/solicitudes_ayuda_screen.dart';
import 'package:agente_desconexiones/screens/supervisor/mi_actividad_screen.dart';
import 'package:agente_desconexiones/services/mis_actividades_state.dart';

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
  bool _esItoCalidad = false;
  bool _esBodega = false;
  bool _checkingBodega = true;
  // '' | 'jefe_operaciones' | 'flota'
  String _rolFlota = '';
  String _rutSesion = '';
  String _tipoSesion = '';
  bool _esAdmin = false;
  List<Map<String, dynamic>> _historialDia = [];
  final _ayudaService = AyudaService();

  // ── Solicitudes de material (badge + notificación background) ──
  StreamSubscription<List<Map<String, dynamic>>>? _subSolicitudesMat;
  int _solicitudesMaterialCount = 0;
  final Set<String> _solicitudesNotificadasHome = {};
  bool _matHomeInit = false;

  // ── Ayuda en terreno (badge de pendientes para supervisor) ──
  int _ayudaPendienteCount = 0;

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
    _checkRolFlota();
    _checkEsAdmin();
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
        unawaited(FcmService.instance.processPendingNavigation());
        unawaited(FcmService.instance.processPendingPin());
        unawaited(ComunicadoService.instance.processPendingComunicado(context));
        // Badge de ayuda pendiente para supervisor: carga inicial + listener en tiempo real
        if (!auth.usuario!.esTecnico) {
          unawaited(_cargarAyudaPendiente());
          _ayudaService.addListener(_onAyudaServiceChanged);
        }

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
        await _cargarAyudaPendiente();
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
    _ayudaService.removeListener(_onAyudaServiceChanged);
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
    if (_rolFlota == 'flota') return const FlotaAdminScreen();
    if (_rolFlota == 'jefe_operaciones') return const JefeOpsHomeScreen();

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
          InkWell(
            onTap: () => PerfilTecnicoSheet.mostrar(
              context,
              usuario: usuario,
              rut: _rutSesion,
              tipo: _tipoSesion,
            ),
            borderRadius: BorderRadius.circular(10),
            child: Container(
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
        // Botón Tu Mes
        IconButton(
          icon: const Icon(Icons.calendar_month),
          tooltip: 'Tu Mes',
          onPressed: () => _pushConCortina(
            color: const Color(0xFF6366F1),
            titulo: 'Tu Mes',
            screen: const TuMesScreen(),
          ),
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

  Future<void> _pushConCortina({
    required Color color,
    required String titulo,
    String? subtitulo,
    required Widget screen,
    Future<void> Function()? hastaListo,
  }) {
    return NavegacionConCortina.push<void>(
      context,
      accentColor: color,
      titulo: titulo,
      subtitulo: subtitulo,
      destination: screen,
      hastaListo: hastaListo,
    );
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
          // ── Fila 1 ──────────────────────────────────────────────
          _buildActionButton(
            icon: Icons.router,
            label: 'Asistente\nde CTO',
            color: const Color(0xFF00D9FF),
            gradient: const LinearGradient(
              colors: [Color(0xFF00D9FF), Color(0xFF0099CC)],
            ),
            onTap: () => _pushConCortina(
              color: const Color(0xFF00D9FF),
              titulo: 'Asistente de CTO',
              screen: const AsistenteCtoScreen(),
            ),
          ),
          _buildActionButton(
            icon: Icons.mic,
            label: 'Asistente\nCREA',
            color: const Color(0xFFAB47BC),
            gradient: const LinearGradient(
              colors: [Color(0xFFAB47BC), Color(0xFF7B1FA2)],
            ),
            onTap: () => _pushConCortina(
              color: const Color(0xFFAB47BC),
              titulo: 'Asistente CREA',
              screen: const AsistenteCreaTerrenoScreen(),
            ),
          ),
          // ── Fila 2 ──────────────────────────────────────────────
          _buildActionButton(
            icon: Icons.support_agent,
            label: 'Ayuda en\nTerreno',
            color: const Color(0xFF4CAF50),
            gradient: const LinearGradient(
              colors: [Color(0xFF4CAF50), Color(0xFF2E7D32)],
            ),
            onTap: () => _pushConCortina(
              color: const Color(0xFF4CAF50),
              titulo: 'Ayuda en Terreno',
              screen: const AyudaTerrenoScreen(),
            ),
          ),
          _buildActionButton(
            icon: Icons.health_and_safety_outlined,
            label: 'AST',
            color: const Color(0xFF7C3AED),
            gradient: const LinearGradient(
              colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
            ),
            onTap: () => _pushConCortina(
              color: const Color(0xFF7C3AED),
              titulo: 'AST',
              screen: const AstLoginScreen(),
            ),
          ),
          // ── Fila 3 ──────────────────────────────────────────────
          Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: _buildActionButton(
                  icon: Icons.inventory_2_outlined,
                  label: 'Solicitud\nde Material',
                  color: const Color(0xFF10B981),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF10B981), Color(0xFF059669)],
                  ),
                  onTap: () async {
                    final db = Supabase.instance.client;
                    try {
                      final rows = await db
                          .from('solicitudes_material')
                          .select('id')
                          .eq('estado', 'pendiente');
                      for (final r in (rows as List)) {
                        final id = r['id'] as String? ?? '';
                        if (id.isNotEmpty) _solicitudesNotificadasHome.add(id);
                      }
                    } catch (_) {}
                    if (mounted) setState(() => _solicitudesMaterialCount = 0);
                    if (mounted) {
                      _pushConCortina(
                        color: const Color(0xFF10B981),
                        titulo: 'Solicitud de Material',
                        screen: const SolicitudMaterialScreen(),
                      );
                    }
                  },
                ),
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
          _buildActionButton(
            icon: Icons.wifi_find,
            label: 'WiFi &\nMapas',
            color: const Color(0xFF00D9FF),
            gradient: const LinearGradient(
              colors: [Color(0xFF00D9FF), Color(0xFF0099CC)],
            ),
            onTap: () => _pushConCortina(
              color: const Color(0xFF00D9FF),
              titulo: 'WiFi & Mapas',
              subtitulo: 'Cargando herramientas…',
              screen: const WifiCoberturaScreen(),
            ),
          ),
          // ── Fila 4 ──────────────────────────────────────────────
          Consumer<AlertaProvider>(
            builder: (context, alertaProvider, _) {
              final bloqueada = alertaProvider.misActividadesBloqueada;
              return _buildActionButton(
                icon: bloqueada
                    ? Icons.lock_outline_rounded
                    : Icons.assignment_outlined,
                label: 'Mis\nActividades',
                color: bloqueada
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF3B82F6),
                gradient: bloqueada
                    ? const LinearGradient(
                        colors: [Color(0xFFEF4444), Color(0xFFB91C1C)],
                      )
                    : const LinearGradient(
                        colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                      ),
                onTap: () => _pushConCortina(
                  color: bloqueada
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF3B82F6),
                  titulo: 'Mis Actividades',
                  subtitulo: 'Iniciando sesión en TOA…',
                  screen: const MisActividadesScreen(),
                  hastaListo: MisActividadesState.instance.esperarCortinaHome,
                ),
              );
            },
          ),
          _buildActionButton(
            icon: Icons.phone_android,
            label: 'App\nTécnico',
            color: const Color(0xFFE30613),
            gradient: const LinearGradient(
              colors: [Color(0xFFE30613), Color(0xFFB8050F)],
            ),
            onTap: () =>
                AppTecnicoOpenService.instance.openFromHome(context),
          ),
          // ── Condicionales ────────────────────────────────────────
          if (_puedeVerEquipo)
            _buildActionButton(
              icon: Icons.groups,
              label: 'Mi Equipo',
              color: const Color(0xFFFFA500),
              gradient: const LinearGradient(
                colors: [Color(0xFFFFA500), Color(0xFFFF8C00)],
              ),
              onTap: () => _pushConCortina(
                color: const Color(0xFFFFA500),
                titulo: 'Mi Equipo',
                screen: const MiEquipoNyquistScreen(),
              ),
            ),
          if (_esIto)
            _buildActionButton(
              icon: Icons.manage_accounts_rounded,
              label: 'Panel\nSupervisor',
              color: const Color(0xFF7B61FF),
              gradient: const LinearGradient(
                colors: [Color(0xFF7B61FF), Color(0xFF5C3FCC)],
              ),
              onTap: () => _pushConCortina(
                color: const Color(0xFF7B61FF),
                titulo: 'Panel Supervisor',
                screen: const AsistenteSupervisorScreen(),
              ),
            ),
          if (_esItoCalidad)
            _buildActionButton(
              icon: Icons.fact_check_rounded,
              label: 'Informe\nAuditoría',
              color: const Color(0xFFEC4899),
              gradient: const LinearGradient(
                colors: [Color(0xFFEC4899), Color(0xFFBE185D)],
              ),
              onTap: () => _pushConCortina(
                color: const Color(0xFFEC4899),
                titulo: 'Informe Auditoría',
                screen: const InformeAuditoriaCalidadScreen(),
              ),
            ),
          if (_esBodega)
            _buildActionButton(
              icon: Icons.warehouse_rounded,
              label: 'Panel\nBodega',
              color: const Color(0xFFF59E0B),
              gradient: const LinearGradient(
                colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
              ),
              onTap: () => _pushConCortina(
                color: const Color(0xFFF59E0B),
                titulo: 'Panel Bodega',
                screen: const BodegaScreen(),
              ),
            ),
          if (usuario.esSupervisor) ...[
            _buildActionButton(
              icon: Icons.supervisor_account_rounded,
              label: 'Asistente\nSupervisor',
              color: const Color(0xFF00ACC1),
              gradient: const LinearGradient(
                colors: [Color(0xFF00ACC1), Color(0xFF00838F)],
              ),
              onTap: () => _pushConCortina(
                color: const Color(0xFF00ACC1),
                titulo: 'Asistente Supervisor',
                screen: const AsistenteSupervisorScreen(),
              ),
            ),
            Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: _buildActionButton(
                    icon: Icons.sos,
                    label: 'Solicitudes\nayuda',
                    color: const Color(0xFFE53935),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE53935), Color(0xFFC62828)],
                    ),
                    onTap: () {
                      setState(() => _ayudaPendienteCount = 0);
                      _pushConCortina(
                        color: const Color(0xFFE53935),
                        titulo: 'Solicitudes de ayuda',
                        screen: const SolicitudesAyudaScreen(),
                      ).then((_) => _cargarAyudaPendiente());
                    },
                  ),
                ),
                if (_ayudaPendienteCount > 0)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$_ayudaPendienteCount',
                        style: const TextStyle(
                          color: Color(0xFFE53935),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            _buildActionButton(
              icon: Icons.directions_run,
              label: 'Mi\nactividad',
              color: const Color(0xFF5C6BC0),
              gradient: const LinearGradient(
                colors: [Color(0xFF5C6BC0), Color(0xFF3949AB)],
              ),
              onTap: () => _pushConCortina(
                color: const Color(0xFF5C6BC0),
                titulo: 'Mi actividad',
                screen: const MiActividadScreen(),
              ),
            ),
          ],
          if (_esAdmin)
            _buildActionButton(
              icon: Icons.monitor_heart_rounded,
              label: 'Monitor\nSistema',
              color: const Color(0xFFFF6B35),
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6B35), Color(0xFFE55A2B)],
              ),
              onTap: () => _pushConCortina(
                color: const Color(0xFFFF6B35),
                titulo: 'Monitor Sistema',
                screen: MonitorScreen(rutAdmin: _rutSesion),
              ),
            ),
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
      unawaited(_actualizarUbicacionTecnico(rut));
    } else {
      debugPrint('🏠 [HOME] ⚠️  rut vacío — monitores no iniciados');
    }
    // Cargar historial del día si es supervisor
    final usuario = mounted ? context.read<AuthProvider>().usuario : null;
    if (usuario != null && usuario.esSupervisor) {
      await _cargarHistorialDia();
    }
  }

  /// Publica GPS en Supabase (ubicaciones_activas + respaldo tecnicos_ubicacion).
  Future<void> _actualizarUbicacionTecnico(String rut) async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final prefs  = await SharedPreferences.getInstance();
      final nombre = prefs.getString('nombre_tecnico') ?? '';
      await Future.wait([
        UbicacionService.publicarUbicacion(
          rutTecnico: rut,
          lat: pos.latitude,
          lng: pos.longitude,
          gpsActivo: true,
        ),
        SupabaseService().actualizarUbicacion(
          tecnicoId: rut,
          nombre: nombre,
          latitud: pos.latitude,
          longitud: pos.longitude,
        ),
      ]);
      debugPrint('🏠 [HOME] ubicación actualizada: $rut (${pos.latitude}, ${pos.longitude})');
    } catch (e) {
      debugPrint('🏠 [HOME] error actualizando ubicación: $e');
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
    if (_esBodega) return;
    final usuario = context.read<AuthProvider>().usuario;
    if (usuario != null && usuario.esSupervisor) return;
    if (_rolFlota.isNotEmpty) return;
    _subSolicitudesMat?.cancel();
    unawaited(_configurarStreamMaterial(rutPropio));
  }

  Future<void> _configurarStreamMaterial(String rutPropio) async {
    _matHomeInit = false;
    _solicitudesNotificadasHome
      ..clear()
      ..addAll(await MaterialAlertaEstado.load());

    _subSolicitudesMat = Supabase.instance.client
        .from('solicitudes_material_destinatarios')
        .stream(primaryKey: ['id'])
        .eq('rut_tecnico', rutPropio)
        .listen((rows) async {
      if (!mounted) return;
      final ajenas = rows
          .where((r) => (r['estado'] as String?) == 'pendiente')
          .toList();

      // Primera carga: marcar existentes sin alertar (evita falso positivo al abrir app)
      if (!_matHomeInit) {
        if (rows.isEmpty) return;
        for (final r in rows) {
          final sId = r['solicitud_id'] as String? ?? '';
          if (sId.isNotEmpty) _solicitudesNotificadasHome.add(sId);
        }
        await MaterialAlertaEstado.markAllSeen(_solicitudesNotificadasHome);
        _matHomeInit = true;
        if (mounted) {
          setState(() => _solicitudesMaterialCount = ajenas.length);
        }
        return;
      }

      for (final r in ajenas) {
        final sId = r['solicitud_id'] as String? ?? '';
        if (sId.isEmpty || _solicitudesNotificadasHome.contains(sId)) continue;
        _solicitudesNotificadasHome.add(sId);
        await MaterialAlertaEstado.markSeen(sId);
        unawaited(FcmService.playAlerta());
        if (!mounted) return;
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
                  const Text(
                    'Alguien cercano necesita material',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ]),
          action: SnackBarAction(
            label: 'Ver',
            textColor: Colors.white,
            onPressed: () => _pushConCortina(
              color: const Color(0xFF10B981),
              titulo: 'Solicitud de Material',
              screen: const SolicitudMaterialScreen(),
            ),
          ),
        ));
        break;
      }

      final nuevas = ajenas.where((r) {
        final sId = r['solicitud_id'] as String? ?? '';
        return sId.isNotEmpty && !_solicitudesNotificadasHome.contains(sId);
      }).length;
      if (mounted) setState(() => _solicitudesMaterialCount = nuevas);
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
    var rol = (await SessionManager.getRol()).toLowerCase();

    final prefs = await SharedPreferences.getInstance();
    final rut = prefs.getString('rut_tecnico') ??
        prefs.getString('user_rut') ??
        '';
    if (rut.isNotEmpty) {
      try {
        String? cargo;
        final plantel = await Supabase.instance.client
            .from('plantel_tecnicos')
            .select('cargo')
            .eq('rut', rut)
            .maybeSingle();
        cargo = plantel?['cargo']?.toString();

        String? rolEquipo;
        final eq = await Supabase.instance.client
            .from('equipos_crea')
            .select('rol')
            .eq('rut_tecnico', rut)
            .maybeSingle();
        rolEquipo = eq?['rol']?.toString();

        rol = RolHelper.normalizar(rolEquipo ?? rol, cargo: cargo);
        if (rol != prefs.getString('user_rol')) {
          await prefs.setString('user_rol', rol);
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _esIto = rol == 'ito';
        _esItoCalidad = rol == 'ito_calidad' || rol == 'jefe_calidad';
      });
    }
  }

  void _onAyudaServiceChanged() {
    if (!mounted) return;
    final count = _ayudaService.solicitudesSupervisor
        .where((s) => s.estado == EstadoSolicitud.pendiente)
        .length;
    if (count != _ayudaPendienteCount) {
      setState(() => _ayudaPendienteCount = count);
    }
  }

  Future<void> _cargarAyudaPendiente() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rut = prefs.getString('rut_supervisor') ??
                  prefs.getString('rut_tecnico') ??
                  prefs.getString('user_rut') ?? '';
      if (rut.isEmpty) return;

      final hoy = DateTime.now().subtract(const Duration(hours: 24));
      final rows = await Supabase.instance.client
          .from('ayuda_terreno_crea')
          .select('ticket_id, estado')
          .eq('rut_supervisor', rut)
          .neq('tipo', 'movimiento_material')
          .eq('estado', 'pendiente')
          .gte('created_at', hoy.toIso8601String());

      if (mounted) {
        setState(() => _ayudaPendienteCount = (rows as List).length);
      }
    } catch (_) {}
  }

  // Resuelve bodega Y roles_flota antes de liberar el render.
  // Cada consulta tiene su propio try/catch para que un fallo individual
  // no deje a _rolFlota en '' por error.
  Future<void> _checkEsBodega() async {
    final prefs = await SharedPreferences.getInstance();
    final rut   = prefs.getString('rut_tecnico') ??
                  prefs.getString('user_rut') ??
                  prefs.getString('rut') ?? '';
    if (rut.isEmpty) {
      if (mounted) setState(() => _checkingBodega = false);
      return;
    }

    bool   esBodega = false;
    String rolFlota = '';

    try {
      final canon = LogisticaService.canonicalRut(rut);
      final variantes = {
        rut,
        canon,
        canon.replaceAll('-', ''),
      }.where((s) => s.isNotEmpty).toList();
      final row = await Supabase.instance.client
          .from('nomina_bodega')
          .select('rut')
          .inFilter('rut', variantes)
          .limit(1)
          .maybeSingle();
      esBodega = row != null;
      if (esBodega) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_rol', 'bodeguero');
        await prefs.setString('rol_usuario', 'bodeguero');
      }
    } catch (_) {}

    try {
      final row = await Supabase.instance.client
          .from('roles_flota')
          .select('rol')
          .eq('rut', rut)
          .eq('activo', true)
          .maybeSingle();
      rolFlota = row?['rol'] as String? ?? '';
    } catch (_) {}

    if (mounted) {
      setState(() {
        _esBodega       = esBodega;
        _rolFlota       = rolFlota;
        _checkingBodega = false;
      });
      if (_esBodega) {
        _subSolicitudesMat?.cancel();
        _subSolicitudesMat = null;
        unawaited(FcmService.instance.syncFcmTokenDispositivo());
        unawaited(FcmService.instance.initBodegaGuiaMonitor());
        unawaited(FcmService.instance.initBodegaTraspasoMonitor());
      }
    }
  }

  // Mantenido vacío: la lógica se resuelve en _checkEsBodega.
  Future<void> _checkRolFlota() async {}

  Future<void> _checkEsAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    final rut = prefs.getString('rut_tecnico') ??
                prefs.getString('user_rut') ??
                prefs.getString('rut') ?? '';
    if (rut.isEmpty) return;
    try {
      final row = await Supabase.instance.client
          .from('administradores')
          .select('rut')
          .eq('rut', rut)
          .maybeSingle();
      if (mounted) setState(() => _esAdmin = row != null);
    } catch (_) {}
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
            SnackBar(
              content: const Row(children: [
                Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text('Próximamente',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ]),
              duration: const Duration(seconds: 2),
              backgroundColor: const Color(0xFF1E3A5F),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF080E1A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF1A2A3F)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white24, size: 32),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white30,
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
              Icon(icon, size: 32, color: Colors.white),
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

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/solicitud_ayuda.dart';
import '../../services/ayuda_service.dart';
import '../../services/fcm_service.dart';
import '../../services/nyquist_service.dart';
import 'dart:async';

import 'package:agente_desconexiones/models/solicitud_material.dart';
import 'auditoria_prl_screen.dart';
import 'mi_equipo_screen.dart';
import 'solicitudes_ayuda_screen.dart';
import 'solicitudes_material_supervisor_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Modelo de puerto para la tabla completa (igual que en asistente_cto_screen)
// ─────────────────────────────────────────────────────────────────────────────

class _PuertoSup {
  final int     numero;
  final double? rxAnterior;
  final double? rxActual;
  final bool    activo;

  const _PuertoSup({
    required this.numero,
    required this.rxAnterior,
    required this.rxActual,
    required this.activo,
  });

  double? get diferencia {
    if (rxActual == null || rxAnterior == null) return null;
    return rxActual! - rxAnterior!;
  }

  bool get esAlerta {
    if (!activo || rxAnterior == null) return false;
    if (rxActual == null || rxActual == 0.0) return true;
    return rxActual! - rxAnterior! < -3.0;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Modelo local para las actividades del día
// ─────────────────────────────────────────────────────────────────────────────

class _Actividad {
  final String nombre;
  final IconData icono;
  const _Actividad(this.nombre, this.icono);
}

// ─────────────────────────────────────────────────────────────────────────────
// Vistas internas
// ─────────────────────────────────────────────────────────────────────────────

enum _Vista { inicio, ctoBuscar, ctoResultado, actividades }

// ─────────────────────────────────────────────────────────────────────────────
// Pantalla principal
// ─────────────────────────────────────────────────────────────────────────────

class AsistenteSupervisorScreen extends StatefulWidget {
  const AsistenteSupervisorScreen({super.key, this.esRaiz = false});

  /// true cuando se usa como pantalla raíz (login supervisor) — oculta back.
  final bool esRaiz;

  @override
  State<AsistenteSupervisorScreen> createState() =>
      _AsistenteSupervisorScreenState();
}

class _AsistenteSupervisorScreenState
    extends State<AsistenteSupervisorScreen> {
  // ── Colores ────────────────────────────────────────────────────────────────
  static const _colorFondo   = Color(0xFF0A0F1E);
  static const _colorCard    = Color(0xFF0D1B2A);
  static const _colorCyan    = Color(0xFF00E5FF);
  static const _colorVerde   = Color(0xFF30D158);
  static const _colorNaranja = Color(0xFFFF9500);
  static const _colorRojo    = Color(0xFFFF3B30);
  static const _colorAzul    = Color(0xFF1E88E5);
  static const _colorPrl     = Color(0xFFFF6B35);

  // ── Colores para la tabla de puertos (mismo criterio que asistente_cto_screen)
  static const _portSurface = Color(0xFF1A2C3D);
  static const _portCyan    = Color(0xFF00BCD4);
  static const _portRed     = Color(0xFFE53935);

  // ── Vista activa ───────────────────────────────────────────────────────────
  _Vista _vista = _Vista.inicio;

  // ── Nombre del supervisor ──────────────────────────────────────────────────
  String _nombre = '';

  // ── AyudaService: badge de solicitudes pendientes ─────────────────────────
  final _ayudaService = AyudaService();
  String _rutSupervisor = '';

  // ── Material: badge de solicitudes vencidas (>5 min sin atender) ──────────
  int _materialVencidas = 0;
  StreamSubscription<List<Map<String, dynamic>>>? _subMaterial;
  Timer? _clockMaterial;

  // ── CTO ────────────────────────────────────────────────────────────────────
  final _otController = TextEditingController();
  bool       _ctoLoading  = false;
  String?    _ctoError;
  String?    _ctoAccessId;
  EstadoCTO? _ctoEstado;
  String?    _ctoOtBuscada;

  // ── Actividades del día ────────────────────────────────────────────────────
  static const List<_Actividad> _actividadesConfig = [
    _Actividad('Verificación de asistencia', Icons.how_to_reg_rounded),
    _Actividad('Reunión de equipo',          Icons.groups_rounded),
    _Actividad('Movimiento de materiales',   Icons.local_shipping_rounded),
    _Actividad('Colación',                   Icons.restaurant_rounded),
    _Actividad('Desvinculación',             Icons.person_remove_rounded),
    _Actividad('Reunión con jefatura',       Icons.business_center_rounded),
    _Actividad('Mesa de calidad',            Icons.verified_rounded),
  ];

  final Map<String, String>  _actEstado     = {};
  final Map<String, String?> _actHoraInicio = {};
  final Map<String, String?> _actHoraFin    = {};

  // ── Ciclo de vida ──────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _cargarActividades();
    _cargarNombre();
    _ayudaService.addListener(_onAyudaChanged);
    _iniciarMonitoreoAyuda();
    _iniciarMonitoreoMaterial();
  }

  @override
  void dispose() {
    _ayudaService.removeListener(_onAyudaChanged);
    _otController.dispose();
    _subMaterial?.cancel();
    _clockMaterial?.cancel();
    super.dispose();
  }

  void _onAyudaChanged() {
    if (mounted) setState(() {});
  }

  void _iniciarMonitoreoMaterial() {
    _subMaterial = Supabase.instance.client
        .from('solicitudes_material')
        .stream(primaryKey: ['id'])
        .eq('estado', 'pendiente')
        .listen((rows) {
      if (!mounted) return;
      final ahora = DateTime.now();
      final vencidas = rows
          .map((r) => SolicitudMaterial.fromMap(r as Map<String, dynamic>))
          .where((s) => ahora.difference(s.createdAt).inMinutes >= 5)
          .length;
      setState(() => _materialVencidas = vencidas);
    });
    // Refresca el conteo cada 30 s (el timer hace que el badge aparezca
    // aunque no llegue un nuevo evento de Supabase)
    _clockMaterial = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _iniciarMonitoreoAyuda() async {
    final prefs = await SharedPreferences.getInstance();
    final rut = prefs.getString('rut_tecnico') ??
        prefs.getString('user_rut') ??
        prefs.getString('rut') ?? '';
    if (rut.isEmpty) return;
    if (mounted) setState(() => _rutSupervisor = rut);
    await _ayudaService.iniciarMonitoreoGlobalSupervisor(rut);
    // Guardar FCM token en supervisores_crea para notificaciones en background
    _guardarTokenFcm(rut);
  }

  Future<void> _guardarTokenFcm(String rut) async {
    try {
      final token = await FcmService.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _ayudaService.guardarTokenFcmSupervisor(rut, token);
      }
    } catch (_) {}
  }

  int get _solicitudesPendientes => _ayudaService.solicitudesSupervisor
      .where((s) => s.estado == EstadoSolicitud.pendiente)
      .length;

  // ── Nombre ─────────────────────────────────────────────────────────────────

  Future<void> _cargarNombre() async {
    final prefs = await SharedPreferences.getInstance();
    final n = prefs.getString('user_nombre') ??
        prefs.getString('nombre_tecnico') ?? '';
    if (mounted) setState(() => _nombre = n);
  }

  // ── Actividades ────────────────────────────────────────────────────────────

  Future<void> _cargarActividades() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final hoy           = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final fechaGuardada = prefs.getString('sup_act_fecha') ?? '';

    if (fechaGuardada != hoy) {
      for (final a in _actividadesConfig) {
        _actEstado[a.nombre]     = 'pendiente';
        _actHoraInicio[a.nombre] = null;
        _actHoraFin[a.nombre]    = null;
      }
      await _persistirActividades(prefs, hoy);
    } else {
      for (final a in _actividadesConfig) {
        _actEstado[a.nombre]     = prefs.getString('sup_act_est_${a.nombre}') ?? 'pendiente';
        _actHoraInicio[a.nombre] = prefs.getString('sup_act_ini_${a.nombre}');
        _actHoraFin[a.nombre]    = prefs.getString('sup_act_fin_${a.nombre}');
      }
    }

    if (mounted) setState(() {});
  }

  Future<void> _persistirActividades(SharedPreferences prefs, String fecha) async {
    await prefs.setString('sup_act_fecha', fecha);
    for (final a in _actividadesConfig) {
      await prefs.setString('sup_act_est_${a.nombre}', _actEstado[a.nombre] ?? 'pendiente');
      final ini = _actHoraInicio[a.nombre];
      final fin = _actHoraFin[a.nombre];
      if (ini != null) await prefs.setString('sup_act_ini_${a.nombre}', ini);
      else await prefs.remove('sup_act_ini_${a.nombre}');
      if (fin != null) await prefs.setString('sup_act_fin_${a.nombre}', fin);
      else await prefs.remove('sup_act_fin_${a.nombre}');
    }
  }

  Future<void> _guardarActividades() async {
    final prefs = await SharedPreferences.getInstance();
    final hoy   = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await _persistirActividades(prefs, hoy);
  }

  void _iniciarActividad(String nombre) {
    final ahora = DateFormat('HH:mm').format(DateTime.now());
    setState(() {
      _actEstado[nombre]     = 'iniciada';
      _actHoraInicio[nombre] = ahora;
    });
    _guardarActividades();
  }

  void _completarActividad(String nombre) {
    final ahora = DateFormat('HH:mm').format(DateTime.now());
    setState(() {
      _actEstado[nombre] = 'completada';
      _actHoraFin[nombre] = ahora;
    });
    _guardarActividades();
  }

  // ── CTO: consulta manual por OT ────────────────────────────────────────────

  Future<void> _consultarCTO() async {
    final ot = _otController.text.trim();
    if (ot.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _ctoLoading  = true;
      _ctoError    = null;
      _ctoEstado   = null;
      _ctoAccessId = null;
    });

    try {
      final row = await Supabase.instance.client
          .from('tabla_access_id')
          .select('access_id, orden_trabajo')
          .eq('orden_trabajo', ot)
          .order('fecha_trabajo', ascending: false)
          .limit(1)
          .maybeSingle();

      if (row == null || (row['access_id']?.toString() ?? '').isEmpty) {
        if (!mounted) return;
        setState(() {
          _ctoLoading = false;
          _ctoError   = 'OT $ot no encontrada en tabla_access_id.';
        });
        return;
      }

      const vno        = '02';
      final accessRaw  = row['access_id'].toString().trim();
      final accessFull = accessRaw.startsWith('$vno-') ? accessRaw : '$vno-$accessRaw';

      final estado = await NyquistService().consultarEstado(accessFull);

      if (!mounted) return;
      setState(() {
        _ctoAccessId  = accessFull;
        _ctoEstado    = estado;
        _ctoOtBuscada = ot;
        _ctoLoading   = false;
        _vista        = _Vista.ctoResultado;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ctoLoading = false;
        _ctoError   = e.toString().replaceAll('Exception:', '').trim();
      });
    }
  }

  // ── AppBar ──────────────────────────────────────────────────────────────────

  Widget? _buildLeading() {
    if (_vista != _Vista.inicio) {
      return IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: Colors.white70),
        onPressed: () => setState(() {
          _vista = _vista == _Vista.ctoResultado
              ? _Vista.ctoBuscar
              : _Vista.inicio;
        }),
      );
    }
    if (!widget.esRaiz) {
      return IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: Colors.white70),
        onPressed: () => Navigator.pop(context),
      );
    }
    return null;
  }

  Widget _buildTitle() {
    final titulo = switch (_vista) {
      _Vista.inicio      => 'Panel Supervisor',
      _Vista.ctoBuscar   => 'Asistente CTO',
      _Vista.ctoResultado => 'Asistente CTO',
      _Vista.actividades => 'Actividades del Día',
    };
    final subtitulo = _vista == _Vista.ctoResultado && _ctoOtBuscada != null
        ? 'OT $_ctoOtBuscada'
        : _vista == _Vista.inicio && _nombre.isNotEmpty
            ? _nombre
            : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          titulo,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 17,
          ),
        ),
        if (subtitulo != null)
          Text(
            subtitulo,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
      ],
    );
  }

  // ── Build principal ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        backgroundColor: _colorCard,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: _buildLeading(),
        title: _buildTitle(),
        actions: _vista == _Vista.ctoResultado
            ? [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: _colorCyan),
                  onPressed: _ctoLoading ? null : _consultarCTO,
                  tooltip: 'Refrescar',
                ),
              ]
            : null,
      ),
      body: switch (_vista) {
        _Vista.inicio       => _buildInicio(),
        _Vista.ctoBuscar    => _buildCtoBuscar(),
        _Vista.ctoResultado => _buildCtoResultado(),
        _Vista.actividades  => _buildActividadesView(),
      },
    );
  }

  // ── Dashboard: grid de cards ────────────────────────────────────────────────

  Widget _buildInicio() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.5,
        children: [
          _buildCard(
            icono: Icons.cable_rounded,
            titulo: 'Asistente\nCTO',
            colores: [_colorCyan, const Color(0xFF0099CC)],
            onTap: () => setState(() {
              _vista       = _Vista.ctoBuscar;
              _ctoEstado   = null;
              _ctoError    = null;
              _ctoOtBuscada = null;
              _ctoAccessId  = null;
            }),
          ),
          _buildCard(
            icono: Icons.sos_rounded,
            titulo: 'Solicitudes\nde Ayuda',
            colores: [_colorRojo, const Color(0xFFCC0000)],
            badge: _solicitudesPendientes,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SolicitudesAyudaScreen()),
            ),
          ),
          _buildCard(
            icono: Icons.checklist_rounded,
            titulo: 'Actividades\ndel Día',
            colores: [_colorVerde, const Color(0xFF1A7A35)],
            onTap: () => setState(() => _vista = _Vista.actividades),
          ),
          _buildCard(
            icono: Icons.security_rounded,
            titulo: 'Auditoría\nPRL',
            colores: [_colorPrl, const Color(0xFFE84E0F)],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AuditoriaPrlScreen()),
            ),
          ),
          _buildCard(
            icono: Icons.groups_3_rounded,
            titulo: 'Mi Equipo',
            colores: [_colorAzul, const Color(0xFF1565C0)],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MiEquipoScreen()),
            ),
          ),
          _buildCard(
            icono: Icons.inventory_2_rounded,
            titulo: 'Solicitudes\nde Material',
            colores: [const Color(0xFF10B981), const Color(0xFF059669)],
            badge: _materialVencidas,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const SolicitudesMaterialSupervisorScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required IconData icono,
    required String titulo,
    required List<Color> colores,
    required VoidCallback onTap,
    int badge = 0,
  }) {
    final card = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colores),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: colores.first.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icono, size: 32, color: Colors.white),
              const SizedBox(height: 8),
              Text(
                titulo,
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
    );

    if (badge <= 0) return card;

    return Stack(
      children: [
        card,
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
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
                color: colores.first,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Vista CTO: búsqueda ─────────────────────────────────────────────────────

  Widget _buildCtoBuscar() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _colorCyan.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _colorCyan.withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.cable_rounded,
                  color: _colorCyan, size: 40),
            ),
            const SizedBox(height: 20),
            Text(
              'Ingresa el número de OT',
              style: GoogleFonts.poppins(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _otController,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _consultarCTO(),
              decoration: InputDecoration(
                hintText: 'Número de OT...',
                hintStyle: const TextStyle(color: Colors.white30),
                prefixIcon: const Icon(Icons.search,
                    color: Colors.white30, size: 22),
                filled: true,
                fillColor: const Color(0xFF0A1628),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      BorderSide(color: _colorCyan.withValues(alpha: 0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      BorderSide(color: _colorCyan.withValues(alpha: 0.2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: _colorCyan, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    vertical: 16, horizontal: 16),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _ctoLoading ? null : _consultarCTO,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _colorCyan,
                  foregroundColor: const Color(0xFF071829),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _ctoLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Color(0xFF071829)),
                      )
                    : const Text(
                        'Consultar',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
              ),
            ),
            if (_ctoError != null) ...[
              const SizedBox(height: 12),
              _errorBanner(_ctoError!),
            ],
          ],
        ),
      ),
    );
  }

  // ── Vista CTO: resultado ────────────────────────────────────────────────────

  Widget _buildCtoResultado() {
    final estado = _ctoEstado;
    if (estado == null) {
      return const Center(
          child: CircularProgressIndicator(color: _colorCyan));
    }

    final todosOk = estado.puertosNok == 0 && estado.puertosOk > 0;
    final resumenColor = todosOk ? _colorVerde : _colorRojo;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Resumen
          _card(
            color: const Color(0xFF071829),
            borderColor: _colorCyan.withValues(alpha: 0.35),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'OT $_ctoOtBuscada',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _ctoAccessId ?? '',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: resumenColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: resumenColor.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        todosOk
                            ? Icons.check_circle_rounded
                            : Icons.warning_rounded,
                        color: resumenColor,
                        size: 30,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${estado.puertosOk} OK',
                        style: TextStyle(
                            color: resumenColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                      if (estado.puertosNok > 0)
                        Text(
                          '${estado.puertosNok} NOK',
                          style: const TextStyle(
                              color: _colorRojo,
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Tabla de puertos — idéntica a la vista del técnico
          _buildTablaPuertosSup(_buildPuertosSup(estado)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => setState(() {
                _vista     = _Vista.ctoBuscar;
                _ctoEstado = null;
                _ctoError  = null;
              }),
              icon: const Icon(Icons.search_rounded),
              label: const Text('Nueva consulta'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _colorCyan,
                foregroundColor: const Color(0xFF071829),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }


  // ── Tabla de puertos completa (igual que asistente_cto_screen) ────────────

  List<_PuertoSup> _buildPuertosSup(EstadoCTO estado) {
    final byNum = <int, PuertoCTO>{};
    for (final p in estado.puertos) {
      byNum[p.numero] = p;
    }
    final maxPuertos = byNum.keys.isEmpty
        ? 8
        : byNum.keys.fold(0, (a, b) => a > b ? a : b);
    return List.generate(maxPuertos, (i) {
      final num = i + 1;
      final n   = byNum[num];
      return _PuertoSup(
        numero:     num,
        rxAnterior: n?.rxBefore,
        rxActual:   n?.rxActual,
        activo:     n != null && n.activo,
      );
    });
  }

  Widget _buildTablaPuertosSup(List<_PuertoSup> puertos) {
    return Container(
      decoration: BoxDecoration(
        color:         _portSurface,
        borderRadius:  BorderRadius.circular(14),
        border:        Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(children: [
        // Encabezado
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          decoration: const BoxDecoration(
            color: Color(0xFF0D2137),
            borderRadius: BorderRadius.only(
              topLeft:  Radius.circular(14),
              topRight: Radius.circular(14),
            ),
          ),
          child: Row(children: [
            _thCellSup('Pto',        flex: 2),
            _thCellSup('RX\nAnter.', flex: 3),
            _thCellSup('RX\nActual', flex: 3),
            _thCellSup('Δ',          flex: 2),
            _thCellSup('Status',     flex: 3),
          ]),
        ),
        ...puertos.asMap().entries.map((e) =>
            _buildFilaPuertoSup(e.value, isLast: e.key == puertos.length - 1)),
      ]),
    );
  }

  Widget _thCellSup(String txt, {required int flex}) => Expanded(
        flex: flex,
        child: Text(
          txt,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w600),
        ),
      );

  Widget _buildFilaPuertoSup(_PuertoSup p, {required bool isLast}) {
    final esAlerta = p.esAlerta;
    final inactivo = !p.activo;
    final diff     = p.diferencia;

    final txtAnt  = p.rxAnterior != null ? p.rxAnterior!.toStringAsFixed(2) : '—';
    final txtAct  = p.rxActual   != null ? p.rxActual!.toStringAsFixed(2)   : '—';
    final txtDiff = diff != null
        ? (diff > 0 ? '+${diff.toStringAsFixed(2)}' : diff.toStringAsFixed(2))
        : '—';

    final Color diffColor;
    if (diff == null) {
      diffColor = Colors.white30;
    } else if (diff < -3.0) {
      diffColor = _portRed;
    } else if (diff.abs() <= 1.5) {
      diffColor = const Color(0xFF22C55E);
    } else {
      diffColor = const Color(0xFFFBBF24);
    }

    return Container(
      decoration: BoxDecoration(
        color: esAlerta ? _portRed.withValues(alpha: 0.10) : Colors.transparent,
        border: Border(
          bottom: isLast
              ? BorderSide.none
              : BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
        borderRadius: isLast
            ? const BorderRadius.only(
                bottomLeft:  Radius.circular(14),
                bottomRight: Radius.circular(14))
            : null,
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      child: Row(children: [
        // Badge circular del puerto
        Expanded(
          flex: 2,
          child: Center(
            child: Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: esAlerta
                    ? _portRed
                    : inactivo
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0xFF173656),
                border: Border.all(
                  color: esAlerta
                      ? _portRed
                      : inactivo
                          ? Colors.white.withValues(alpha: 0.12)
                          : _portCyan.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                '${p.numero}',
                style: TextStyle(
                  color:      inactivo ? Colors.white38 : Colors.white,
                  fontSize:   13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        // RX anterior
        Expanded(
          flex: 3,
          child: Text(
            txtAnt,
            textAlign: TextAlign.center,
            style: TextStyle(
              color:      p.rxAnterior == null ? Colors.white30 : Colors.white70,
              fontSize:   13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // RX actual
        Expanded(
          flex: 3,
          child: Text(
            txtAct,
            textAlign: TextAlign.center,
            style: TextStyle(
              color:      p.rxActual == null ? Colors.white30 : Colors.white,
              fontSize:   13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        // Delta
        Expanded(
          flex: 2,
          child: Text(
            txtDiff,
            textAlign: TextAlign.center,
            style: TextStyle(
              color:      diffColor,
              fontSize:   12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        // Status pill
        Expanded(
          flex: 3,
          child: Center(child: _pillSup(esAlerta, inactivo)),
        ),
      ]),
    );
  }

  Widget _pillSup(bool esAlerta, bool inactivo) {
    if (inactivo) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color:        Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border:       Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: const Text(
          '— libre —',
          style: TextStyle(
              color: Colors.white38, fontSize: 10,
              fontWeight: FontWeight.w700, letterSpacing: 0.4),
        ),
      );
    }
    if (esAlerta) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color:        _portRed.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
          border:       Border.all(color: _portRed.withValues(alpha: 0.55)),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.warning_amber_rounded, color: _portRed, size: 12),
          SizedBox(width: 4),
          Text('Alerta',
              style: TextStyle(
                  color: _portRed, fontSize: 10,
                  fontWeight: FontWeight.w800, letterSpacing: 0.4)),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color:        const Color(0xFF22C55E).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border:       Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.5)),
      ),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_circle_outline, color: Color(0xFF22C55E), size: 12),
        SizedBox(width: 4),
        Text('OK',
            style: TextStyle(
                color: Color(0xFF22C55E), fontSize: 10,
                fontWeight: FontWeight.w800, letterSpacing: 0.4)),
      ]),
    );
  }

  // ── Vista Actividades ───────────────────────────────────────────────────────

  Widget _buildActividadesView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          ...List.generate(
            _actividadesConfig.length,
            (i) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildFilaActividad(_actividadesConfig[i]),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildFilaActividad(_Actividad act) {
    final estado   = _actEstado[act.nombre] ?? 'pendiente';
    final horaIni  = _actHoraInicio[act.nombre];
    final horaFin  = _actHoraFin[act.nombre];
    final esComplet = estado == 'completada';
    final esInicia  = estado == 'iniciada';

    Color borderC;
    Color bgC;
    if (esComplet) {
      borderC = _colorVerde.withValues(alpha: 0.3);
      bgC     = _colorVerde.withValues(alpha: 0.07);
    } else if (esInicia) {
      borderC = _colorNaranja.withValues(alpha: 0.3);
      bgC     = _colorNaranja.withValues(alpha: 0.07);
    } else {
      borderC = Colors.white12;
      bgC     = Colors.white.withValues(alpha: 0.04);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgC,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderC),
      ),
      child: Row(
        children: [
          Icon(
            act.icono,
            size: 20,
            color: esComplet
                ? _colorVerde
                : esInicia
                    ? _colorNaranja
                    : Colors.white38,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  act.nombre,
                  style: TextStyle(
                    color: esComplet ? _colorVerde : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    decoration:
                        esComplet ? TextDecoration.lineThrough : null,
                    decorationColor: _colorVerde,
                  ),
                ),
                if (horaIni != null)
                  Text(
                    esComplet && horaFin != null
                        ? '$horaIni → $horaFin'
                        : 'Iniciada: $horaIni',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11),
                  ),
              ],
            ),
          ),
          if (esComplet)
            const Icon(Icons.check_circle_rounded,
                color: _colorVerde, size: 22)
          else if (esInicia)
            _btnActividad(
              label: 'Completar',
              color: _colorVerde,
              onTap: () => _completarActividad(act.nombre),
              filled: true,
            )
          else
            _btnActividad(
              label: 'Iniciar',
              color: _colorNaranja,
              onTap: () => _iniciarActividad(act.nombre),
            ),
        ],
      ),
    );
  }

  Widget _btnActividad({
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: filled ? color : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: filled
              ? null
              : Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: filled ? Colors.black87 : color,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ── Widgets helpers ─────────────────────────────────────────────────────────

  Widget _card({
    required Widget child,
    required Color color,
    Color? borderColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor ?? Colors.white12),
      ),
      child: child,
    );
  }

  Widget _cardHeader({
    required IconData icono,
    required String titulo,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icono, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          titulo,
          style: GoogleFonts.poppins(
              color: color, fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ],
    );
  }

  Widget _errorBanner(String mensaje) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _colorRojo.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _colorRojo.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: _colorRojo, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              mensaje,
              style: const TextStyle(color: _colorRojo, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

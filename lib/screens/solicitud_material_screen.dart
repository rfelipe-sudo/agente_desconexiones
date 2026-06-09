import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:url_launcher/url_launcher.dart';

import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'package:agente_desconexiones/config/tips_calidad_material.dart';
import 'package:agente_desconexiones/constants/map_styles.dart';
import 'package:agente_desconexiones/models/solicitud_material.dart';
import 'package:agente_desconexiones/screens/entrega_en_camino_screen.dart';
import 'package:agente_desconexiones/screens/pin_entry_screen.dart';
import 'package:agente_desconexiones/services/fcm_service.dart';
import 'package:agente_desconexiones/services/guia_pdf_service.dart';
import 'package:agente_desconexiones/services/material_alerta_estado.dart';
import 'package:agente_desconexiones/services/combustible_material_ruta_service.dart';
import 'package:agente_desconexiones/services/material_solicitud_service.dart';
import 'package:agente_desconexiones/services/logistica_service.dart';
import 'package:agente_desconexiones/services/solicitud_estado_monitor.dart';
import 'package:agente_desconexiones/services/supabase_service.dart';
import 'package:agente_desconexiones/utils/session_manager.dart';
import 'package:agente_desconexiones/screens/supervisor/tecnico_stock_screen.dart';
import 'package:agente_desconexiones/screens/tecnicos_cercanos_mapa_screen.dart';

enum _FaseEsperaMaterial {
  revisandoStock,
  buscandoTecnicos,
  enviandoSolicitud,
  completado,
}

class SolicitudMaterialScreen extends StatefulWidget {
  const SolicitudMaterialScreen({super.key});

  @override
  State<SolicitudMaterialScreen> createState() =>
      _SolicitudMaterialScreenState();
}

class _SolicitudMaterialScreenState extends State<SolicitudMaterialScreen>
    with WidgetsBindingObserver {
  static const Color _bg      = Color(0xFF0A1628);
  static const Color _surface = Color(0xFF0D1B2A);
  static const Color _accent  = Color(0xFF00D9FF);
  static const Color _border  = Color(0xFF1E3A5F);
  static const Color _textDim = Color(0xFF8FA8C8);
  static const Color _green   = Color(0xFF22C55E);
  static const Color _orange  = Color(0xFFF59E0B);
  static const Color _red     = Color(0xFFEF4444);

  // ── Identidad ────────────────────────────────────────────────
  String? _rut;
  String? _nombre;
  Position? _posicion;

  bool   _initListo     = false;
  String? _bloqueoAcceso;

  // ── Formulario ───────────────────────────────────────────────
  MaterialItem? _materialSeleccionado;
  int _cantidad = 1;
  final List<({MaterialItem material, int cantidad})> _adicionales = [];

  // ── Estado solicitud propia ──────────────────────────────────
  SolicitudMaterial? _miSolicitud;
  SolicitudMaterial? _pinPendienteEntregador;
  bool _enviando = false;

  // ── Solicitudes cercanas (rol entregador) ────────────────────
  List<SolicitudMaterial> _cercanas = [];

  // ── Mapa ─────────────────────────────────────────────────────
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  BitmapDescriptor? _iconoYo;
  BitmapDescriptor? _iconoTecnico;

  // ── Realtime ─────────────────────────────────────────────────
  StreamSubscription<List<Map<String, dynamic>>>? _subPropia;
  StreamSubscription<List<Map<String, dynamic>>>? _subDestinatarios;

  // IDs de solicitudes ya notificadas — alias del set global en FcmService
  static Set<String> get _notificadas => FcmService.solicitudesNotificadas;

  // Evita sonar en la carga inicial del stream (solo en cambios reales)
  bool _streamInicializado = false;

  // IDs aceptadas por este técnico (evita mostrar "atendida por otro" para propias)
  final Set<String> _aceptadasPorMi = {};

  // ── Tips de calidad (overlay envío solicitud) ────────────────
  Timer? _tipCalidadTimer;
  int _tipCalidadIdx = 0;
  final math.Random _tipRng = math.Random();

  // ── Barra de progreso al enviar solicitud ────────────────────
  static const _estadosGuiaHistorial = ['firmada', 'confirmada_bodega', 'emitida'];

  /// Más reciente primero: created_at, luego fecha+hora.
  static int _cmpGuiaReciente(Map<String, dynamic> a, Map<String, dynamic> b) {
    final ca = a['created_at'] as String?;
    final cb = b['created_at'] as String?;
    if (ca != null && cb != null) return cb.compareTo(ca);
    final fa = '${a['fecha'] ?? ''}T${a['hora'] ?? '00:00:00'}';
    final fb = '${b['fecha'] ?? ''}T${b['hora'] ?? '00:00:00'}';
    return fb.compareTo(fa);
  }

  static List<Map<String, dynamic>> _ordenarGuiasRecientes(
    List<Map<String, dynamic>> guias,
  ) {
    final copia = List<Map<String, dynamic>>.from(guias);
    copia.sort(_cmpGuiaReciente);
    return copia;
  }

  _FaseEsperaMaterial _faseEspera = _FaseEsperaMaterial.revisandoStock;
  bool _overlayProgresoVisible = false;

  // ── Timer de 10 minutos ──────────────────────────────────────
  Timer? _timer10min;

  // ── Timer GPS emisor (posición propia mientras espera) ───────
  Timer? _timerGpsAceptada;

  // ── Polling activo para la posición del entregador (cada 5 s) ─
  Timer? _pollingEntregador;

  // ── Guías del mes (para el historial) ────────────────────────
  List<Map<String, dynamic>> _guiasEntregadas = []; // yo fui entregador
  List<Map<String, dynamic>> _guiasRecibidas  = []; // yo fui solicitante

  // Evita mostrar el banner de modalidad más de una vez por solicitud
  bool _bannerModalidadMostrado = false;
  bool _llegadaMostrada         = false;
  bool _cargandoSaldo           = false;
  String? _aceptandoId;
  bool _marcandoLlegada         = false;
  bool _transaccionCerrada      = false;
  // Evita procesar eventos realtime obsoletos si llegan en ráfaga.
  int _cercanasGen = 0;

  /// Evita repetir el snack de PIN pendiente al reentrar a la pantalla.
  static final Set<String> _pinSnackMostrados = {};

  final _db      = Supabase.instance.client;
  final _service = MaterialSolicitudService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _crearIconos();
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refrescarSesion());
    }
  }

  Future<void> _refrescarSesion() async {
    final id = await SessionManager.identidadSesionMaterial();
    if (!mounted || id.rut.isEmpty) return;
    if (id.rut != _rut || id.nombre != _nombre) {
      debugPrint(
          '🔁 [SolicitudMat] sesión actualizada: ${id.rut} → ${id.nombre}');
      setState(() {
        _rut = id.rut;
        _nombre = id.nombre;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(FcmService.stopAlerta());
    _subPropia?.cancel();
    _subDestinatarios?.cancel();
    _timer10min?.cancel();
    _timerGpsAceptada?.cancel();
    _pollingEntregador?.cancel();
    _tipCalidadTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  bool _pinEntregadorVigente(Map<String, dynamic> row) {
    final pin = row['pin_codigo'] as String?;
    if (pin == null || pin.isEmpty) return false;
    final expiraRaw = row['pin_expira_en'] as String?;
    if (expiraRaw == null) return true;
    try {
      return DateTime.parse(expiraRaw).isAfter(DateTime.now());
    } catch (_) {
      return true;
    }
  }

  Future<void> _cargarPinPendienteEntregador({bool mostrarSnack = true}) async {
    if (_rut == null) return;
    try {
      final rows = await _db
          .from('solicitudes_material')
          .select()
          .eq('rut_entregador', _rut!)
          .eq('estado', 'firmada')
          .not('pin_codigo', 'is', null)
          .order('created_at', ascending: false)
          .limit(3);
      if (!mounted) return;
      Map<String, dynamic>? rowPendiente;
      for (final row in rows as List) {
        final m = row as Map<String, dynamic>;
        if (_pinEntregadorVigente(m)) {
          rowPendiente = m;
          break;
        }
      }
      if (rowPendiente == null) {
        setState(() => _pinPendienteEntregador = null);
        return;
      }
      final sol = SolicitudMaterial.fromMap(rowPendiente);
      final mismoId = _pinPendienteEntregador?.id == sol.id;
      debugPrint('🟠 [SolicitudMat] PIN pendiente entregador → ${sol.id}');
      setState(() => _pinPendienteEntregador = sol);
      if (!mostrarSnack || mismoId || _pinSnackMostrados.contains(sol.id)) {
        return;
      }
      _pinSnackMostrados.add(sol.id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _pinPendienteEntregador?.id != sol.id) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: _orange,
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'Ingresar PIN',
              textColor: Colors.white,
              onPressed: _abrirPinPendienteEntregador,
            ),
            content: Text(
              'Tienes un traspaso sin confirmar (${sol.tipoMaterial}). '
              'Pide el PIN a ${sol.nombreSolicitante}.',
            ),
          ),
        );
      });
    } catch (e) {
      debugPrint('🔴 [SolicitudMat] error PIN pendiente: $e');
    }
  }

  void _abrirPinPendienteEntregador() {
    final sol = _pinPendienteEntregador;
    if (sol == null) return;
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PinEntryScreen(solicitud: sol),
      ),
    ).then((_) {
      _pinSnackMostrados.remove(sol.id);
      return _cargarPinPendienteEntregador(mostrarSnack: false);
    });
  }

  Widget _bannerPinPendienteEntregador() {
    final sol = _pinPendienteEntregador;
    if (sol == null) return const SizedBox.shrink();
    return Material(
      color: _orange,
      child: InkWell(
        onTap: _abrirPinPendienteEntregador,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            const Icon(Icons.pin_outlined, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Traspaso pendiente: ingresa el PIN de ${sol.nombreSolicitante}',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white),
          ]),
        ),
      ),
    );
  }

  // ── Iconos canvas para marcadores ────────────────────────────

  Future<void> _crearIconos() async {
    _iconoYo      = await _circleMarker(const Color(0xFF00D9FF), 72);
    _iconoTecnico = await _circleMarker(const Color(0xFF22C55E), 64);
    if (mounted) setState(() {});
  }

  Future<BitmapDescriptor> _circleMarker(Color color, double size) async {
    final recorder = ui.PictureRecorder();
    final canvas   = Canvas(recorder);

    final shadow = Paint()
      ..color      = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(Offset(size / 2, size / 2 + 2), size / 2 - 4, shadow);

    final fill = Paint()
      ..shader = ui.Gradient.radial(
        Offset(size / 2, size / 2), size / 2 - 6,
        [color, color.withValues(alpha: 0.75)],
      );
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2 - 6, fill);
    canvas.drawCircle(
      Offset(size / 2, size / 2), size / 2 - 6,
      Paint()
        ..color       = Colors.white
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(Offset(size / 2, size / 2), size * 0.1,
        Paint()..color = Colors.white);

    final picture = recorder.endRecording();
    final image   = await picture.toImage(size.toInt(), size.toInt());
    final bytes   = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  String get _tituloFaseEspera => switch (_faseEspera) {
        _FaseEsperaMaterial.revisandoStock => 'Revisando stock',
        _FaseEsperaMaterial.buscandoTecnicos => 'Buscando técnicos',
        _FaseEsperaMaterial.enviandoSolicitud => 'Esperando que acepten',
        _FaseEsperaMaterial.completado => '¡Listo!',
      };

  String get _textoFaseEspera => _faseEspera == _FaseEsperaMaterial.completado
      ? _tituloFaseEspera
      : '$_tituloFaseEspera…';

  void _detenerProgresoEnvio() {
    _overlayProgresoVisible = false;
    _tipCalidadTimer?.cancel();
    _tipCalidadTimer = null;
  }

  void _iniciarProgresoEnvio() {
    _faseEspera = _FaseEsperaMaterial.revisandoStock;
    _overlayProgresoVisible = true;
    if (mounted) setState(() {});
    _syncTipsCalidad();
  }

  void _avanzarFaseEspera(_FaseEsperaMaterial fase) {
    if (!mounted) return;
    setState(() => _faseEspera = fase);
  }

  Future<void> _completarProgresoEnvio() async {
    if (!mounted) return;
    setState(() {
      _faseEspera = _FaseEsperaMaterial.completado;
      _enviando = false;
    });
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _overlayProgresoVisible = false);
    _tipCalidadTimer?.cancel();
    _tipCalidadTimer = null;
  }

  void _syncTipsCalidad() {
    if (!_overlayProgresoVisible) {
      _tipCalidadTimer?.cancel();
      _tipCalidadTimer = null;
      return;
    }

    _tipCalidadTimer ??= Timer.periodic(const Duration(seconds: 9), (_) {
      if (!mounted || !_overlayProgresoVisible) return;
      var next = _tipRng.nextInt(kTipsCalidadMaterial.length);
      while (next == _tipCalidadIdx && kTipsCalidadMaterial.length > 1) {
        next = _tipRng.nextInt(kTipsCalidadMaterial.length);
      }
      setState(() => _tipCalidadIdx = next);
    });

    if (_tipCalidadIdx == 0 && kTipsCalidadMaterial.isNotEmpty) {
      _tipCalidadIdx = _tipRng.nextInt(kTipsCalidadMaterial.length);
    }
  }

  Widget _buildBarraFasesEspera() {
    const fases = _FaseEsperaMaterial.values;
    const etiquetas = ['Stock', 'Técnicos', 'Espera', 'OK'];
    final activa = _faseEspera.index;
    final terminado = _faseEspera == _FaseEsperaMaterial.completado;

    return Column(
      children: [
        Row(
          children: List.generate(fases.length * 2 - 1, (i) {
            if (i.isOdd) {
              final paso = i ~/ 2;
              final avanzado = terminado || paso < activa;
              return Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  height: 3,
                  color: avanzado
                      ? _green
                      : Colors.white.withValues(alpha: 0.15),
                ),
              );
            }
            final paso = i ~/ 2;
            final hecho = terminado || paso < activa;
            final actual = !terminado && paso == activa;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hecho
                    ? _green
                    : actual
                        ? _accent
                        : Colors.white.withValues(alpha: 0.12),
                border: Border.all(
                  color: actual ? _accent : Colors.transparent,
                  width: 2,
                ),
              ),
              child: hecho
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : actual
                      ? const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black87,
                          ),
                        )
                      : null,
            );
          }),
        ),
        const SizedBox(height: 6),
        Row(
          children: List.generate(fases.length, (paso) {
            final activo = terminado || paso <= activa;
            return Expanded(
              child: Text(
                etiquetas[paso],
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: activo ? Colors.white : _textDim,
                  fontWeight: activo ? FontWeight.bold : FontWeight.normal,
                  fontSize: 9,
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        Text(
          _textoFaseEspera,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: terminado ? _green : Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 16,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildCapaBuscandoTecnico({double bottomReserva = 0}) {
    final tip = kTipsCalidadMaterial.isNotEmpty
        ? kTipsCalidadMaterial[_tipCalidadIdx]
        : '';
    return Positioned.fill(
      bottom: bottomReserva,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.45),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 8),
                _buildBarraFasesEspera(),
                Expanded(
                  child: Center(
                    child: tip.isEmpty
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFC62828),
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(14),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.2),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: const Text(
                                      'A TENER EN CUENTA..',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 17,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 22,
                                      vertical: 20,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _green,
                                      borderRadius: const BorderRadius.vertical(
                                        bottom: Radius.circular(14),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: _green.withValues(alpha: 0.35),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: AnimatedSwitcher(
                                      duration:
                                          const Duration(milliseconds: 450),
                                      child: Text(
                                        tip,
                                        key: ValueKey<int>(_tipCalidadIdx),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                          height: 1.45,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Init ─────────────────────────────────────────────────────

  Future<void> _init() async {
    await FcmService.cancelMaterialNotificacion();
    _notificadas.addAll(await MaterialAlertaEstado.load());
    final id = await SessionManager.identidadSesionMaterial();
    _rut = id.rut.isEmpty ? null : id.rut;
    _nombre = id.nombre.isEmpty ? null : id.nombre;
    _posicion = await _obtenerPosicion();

    debugPrint(
        '🔵 [SolicitudMat] init → rut=$_rut nombre=$_nombre '
        'pos=${_posicion?.latitude},${_posicion?.longitude}');

    if (_rut == null) {
      debugPrint('🔴 [SolicitudMat] sin RUT, abortando init');
      if (mounted) setState(() => _initListo = true);
      return;
    }

    final bloqueo =
        await LogisticaService().mensajeBloqueoSolicitudMaterial(_rut!);
    if (bloqueo != null) {
      debugPrint('🔴 [SolicitudMat] acceso bloqueado: $bloqueo');
      if (mounted) {
        setState(() {
          _bloqueoAcceso = bloqueo;
          _initListo     = true;
        });
      }
      return;
    }

    if (_nombre == null || _nombre!.isEmpty) {
      try {
        _nombre = await LogisticaService().nombreDesdeNomina(_rut!);
      } catch (e) {
        debugPrint('🔴 [SolicitudMat] nombre nómina: $e');
        if (mounted) {
          setState(() {
            _bloqueoAcceso = e is StateError
                ? e.message
                : 'No se pudo validar tu RUT en nómina.';
            _initListo = true;
          });
        }
        return;
      }
    }

    // Registrar ubicación para que notificarDestinatarios() encuentre este técnico.
    if (_posicion != null) {
      unawaited(SupabaseService().actualizarUbicacion(
        tecnicoId: _rut!,
        nombre:    _nombre ?? '',
        latitud:   _posicion!.latitude,
        longitud:  _posicion!.longitude,
      ));
    }

    final rows = await _db
        .from('solicitudes_material')
        .select()
        .eq('rut_solicitante', _rut!)
        .inFilter('estado', ['pendiente', 'aceptada', 'en_guia', 'firmada'])
        .order('created_at', ascending: false)
        .limit(1);

    debugPrint('🔵 [SolicitudMat] solicitud propia activa: ${rows.length}');

    await _cargarPinPendienteEntregador();

    if (rows.isNotEmpty && mounted) {
      setState(() {
        _miSolicitud = SolicitudMaterial.fromMap(rows.first as Map<String, dynamic>);
        _overlayProgresoVisible = false;
      });
      _suscribirSolicitudPropia();
      // Activar monitor de PIN: A verá su PIN en un dialog global cuando B confirme.
      if (_rut != null && _miSolicitud != null) {
        unawaited(FcmService.instance.initPinMonitor(_rut!, _miSolicitud!.id));
      }
      if (_miSolicitud?.pinCodigo != null &&
          _miSolicitud!.pinCodigo!.isNotEmpty &&
          mounted) {
        unawaited(FcmService.showPinDialogIfNeeded(
          context,
          _miSolicitud!.pinCodigo!,
          solicitudId: _miSolicitud!.id,
        ));
      }
      unawaited(FcmService.instance.processPendingPin(context));
    }

    _suscribirCercanas();
    _cargarGuiasMes();
    if (mounted) {
      setState(() => _initListo = true);
      _syncTipsCalidad();
      // Reanima la cámara cuando el mapa esté listo con la posición correcta
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _actualizarMarkers();
      });
    }
  }

  Future<void> _verMiSaldo() async {
    await _refrescarSesion();
    if (_rut == null || _cargandoSaldo) return;
    setState(() => _cargandoSaldo = true);
    try {
      final stock = await LogisticaService().fetchStockTecnico(
        _rut!,
        nombreDisplay: _nombre,
      );
      if (!mounted) return;
      if (stock == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se encontró tu saldo en logística.\n'
              'Verifica que tu RUT esté en nómina.',
            ),
          ),
        );
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TecnicoStockScreen(tecnico: stock),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al cargar saldo. Revisa conexión e intenta de nuevo.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _cargandoSaldo = false);
    }
  }

  Future<void> _cargarGuiasMes() async {
    if (_rut == null) return;
    final now   = DateTime.now();
    final inicio = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final fin    = DateTime(now.year, now.month + 1, 0)
        .toIso8601String()
        .substring(0, 10);
    // Seleccionamos solo metadatos; las firmas (base64 grandes) se cargan al abrir el PDF
    const cols = 'id, solicitud_id, fecha, hora, created_at, lugar, '
        'detalle_material, cantidad, series, estado, '
        'nombre_solicitante, rut_solicitante, nombre_entregador, rut_entregador';
    try {
      final results = await Future.wait([
        _db
            .from('solicitudes_bodega')
            .select(cols)
            .eq('rut_entregador', _rut!)
            .inFilter('estado', _estadosGuiaHistorial)
            .gte('fecha', inicio)
            .lte('fecha', fin)
            .order('created_at', ascending: false),
        _db
            .from('solicitudes_bodega')
            .select(cols)
            .eq('rut_solicitante', _rut!)
            .inFilter('estado', _estadosGuiaHistorial)
            .gte('fecha', inicio)
            .lte('fecha', fin)
            .order('created_at', ascending: false),
      ]);
      if (!mounted) return;
      final logistica = LogisticaService();
      Future<Map<String, dynamic>> enriquecer(Map<String, dynamic> g) async {
        final rutEnt = g['rut_entregador'] as String? ?? '';
        final rutSol = g['rut_solicitante'] as String? ?? '';
        return {
          ...g,
          'nombre_entregador': await logistica.nombrePorRut(
            rutEnt,
            fallback: g['nombre_entregador'] as String?,
          ),
          'nombre_solicitante': await logistica.nombrePorRut(
            rutSol,
            fallback: g['nombre_solicitante'] as String?,
          ),
        };
      }

      final entregadas = await Future.wait(
        (results[0] as List)
            .cast<Map<String, dynamic>>()
            .map(enriquecer),
      );
      final recibidas = await Future.wait(
        (results[1] as List)
            .cast<Map<String, dynamic>>()
            .map(enriquecer),
      );

      if (!mounted) return;
      setState(() {
        _guiasEntregadas = _ordenarGuiasRecientes(entregadas);
        _guiasRecibidas  = _ordenarGuiasRecientes(recibidas);
      });
    } catch (_) {}
  }

  Future<Position?> _obtenerPosicion() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return null;
      final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high));
      return pos;
    } catch (_) {
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }

  void _limpiarRecursosSeguimiento() {
    _timerGpsAceptada?.cancel();
    _timerGpsAceptada = null;
    _pollingEntregador?.cancel();
    _pollingEntregador = null;
    _timer10min?.cancel();
    _tipCalidadTimer?.cancel();
    _tipCalidadTimer = null;
    _mapController?.dispose();
    _mapController = null;
    _markers.clear();
  }

  Future<void> _finalizarCancelada({
    String? mensaje,
    bool cancelacionLocal = false,
  }) async {
    if (_transaccionCerrada || !mounted) return;
    _transaccionCerrada = true;
    _limpiarRecursosSeguimiento();
    _subPropia?.cancel();
    _bannerModalidadMostrado = false;
    _llegadaMostrada         = false;
    unawaited(FcmService.instance.detenerPinMonitor());
    unawaited(FcmService.cancelMaterialNotificacion());
    setState(() => _miSolicitud = null);
    if (!mounted) return;
    await MaterialTransaccionUi.mostrarCancelada(
      context,
      detalle: mensaje ??
          (cancelacionLocal
              ? 'Cancelaste la solicitud. El entregador fue notificado.'
              : 'La solicitud de material fue cancelada.'),
    );
  }

  Future<void> _finalizarCompletada() async {
    if (_transaccionCerrada || !mounted) return;
    _transaccionCerrada = true;
    _limpiarRecursosSeguimiento();
    _subPropia?.cancel();
    _bannerModalidadMostrado = false;
    _llegadaMostrada         = false;
    unawaited(FcmService.instance.detenerPinMonitor());
    setState(() => _miSolicitud = null);
    _cargarGuiasMes();
    if (!mounted) return;
    await MaterialTransaccionUi.mostrarCompletada(context);
  }

  void _procesarEstadoSolicitud(SolicitudMaterial updated) {
    if (updated.id != _miSolicitud?.id) return;

    if (updated.estado == 'cancelada') {
      _detenerProgresoEnvio();
      unawaited(_finalizarCancelada());
      return;
    }
    if (updated.estado == 'completada') {
      _detenerProgresoEnvio();
      unawaited(_finalizarCompletada());
      return;
    }

    if (updated.estado == 'aceptada' && _overlayProgresoVisible) {
      unawaited(_alAceptarSolicitud(updated));
      return;
    }

    _aplicarEstadoSolicitud(updated);
  }

  Future<void> _alAceptarSolicitud(SolicitudMaterial updated) async {
    await _completarProgresoEnvio();
    if (!mounted) return;
    _aplicarEstadoSolicitud(updated);
  }

  void _aplicarEstadoSolicitud(SolicitudMaterial updated) {
    setState(() => _miSolicitud = updated);
    _syncTipsCalidad();

    if (updated.estado != 'pendiente') {
      _timer10min?.cancel();
      _tipCalidadTimer?.cancel();
      _tipCalidadTimer = null;
    }

    if (updated.estado == 'aceptada') {
      if (updated.modalidad != null && !_bannerModalidadMostrado) {
        _bannerModalidadMostrado = true;
        _mostrarBannerModalidad(
            updated.modalidad!, updated.nombreEntregador ?? 'Tu colega');
      }

      _obtenerPosicion().then((pos) {
        if (pos != null && mounted) setState(() => _posicion = pos);
      });
      _timerGpsAceptada ??= Timer.periodic(const Duration(seconds: 30), (_) async {
        final pos = await _obtenerPosicion();
        if (pos != null && mounted) setState(() => _posicion = pos);
      });
      _pollingEntregador ??= Timer.periodic(const Duration(seconds: 5), (_) async {
        if (!mounted || _miSolicitud == null) return;
        try {
          final row = await _db
              .from('solicitudes_material')
              .select()
              .eq('id', _miSolicitud!.id)
              .single();
          if (!mounted) return;
          final fresh =
              SolicitudMaterial.fromMap(row as Map<String, dynamic>);
          if (fresh.estado != 'aceptada') {
            _pollingEntregador?.cancel();
            _pollingEntregador = null;
            _procesarEstadoSolicitud(fresh);
            return;
          }
          setState(() => _miSolicitud = fresh);
          _actualizarMarkers();
        } catch (_) {}
      });
      _actualizarMarkers();
    }

    if (updated.estado == 'en_guia') {
      _limpiarRecursosSeguimiento();
      if (!_llegadaMostrada) {
        _llegadaMostrada = true;
        _mostrarLlegadaEntregador(updated);
      }
    }

    if (updated.estado == 'firmada') {
      _limpiarRecursosSeguimiento();
      if (updated.pinCodigo != null && updated.pinCodigo!.isNotEmpty) {
        unawaited(FcmService.showPinDialogIfNeeded(
          context,
          updated.pinCodigo!,
          solicitudId: updated.id,
        ));
      }
    }
  }

  void _suscribirSolicitudPropia() {
    if (_miSolicitud == null) return;
    _subPropia?.cancel();
    _transaccionCerrada = false;
    final solicitudIdEsperado = _miSolicitud!.id;
    _subPropia = _db
        .from('solicitudes_material')
        .stream(primaryKey: ['id'])
        .eq('id', solicitudIdEsperado)
        .listen((rows) {
      if (rows.isEmpty || !mounted) return;
      final updated =
          SolicitudMaterial.fromMap(rows.first as Map<String, dynamic>);
      if (updated.id != solicitudIdEsperado) return;
      _procesarEstadoSolicitud(updated);
    });
  }

  static const _soundChannel = MethodChannel(
    'com.creacionestecnologicas.agente_desconexiones/sound',
  );

  Future<void> _tocarAlertaUnica() async {
    debugPrint('🔔 [Sonido] _tocarAlertaUnica INICIO');
    HapticFeedback.heavyImpact();
    debugPrint('🔔 [Sonido] haptic enviado, llamando canal nativo...');
    try {
      await _soundChannel.invokeMethod<void>('playAlerta');
      debugPrint('🔔 [Sonido] playAlerta OK — MediaPlayer arrancado');
    } catch (e) {
      debugPrint('🔔 [Sonido] ERROR en playAlerta: $e');
    }
  }

  Future<void> _cancelarNotificacionMaterial() async {
    await FcmService.cancelMaterialNotificacion();
  }

  void _mostrarBannerSolicitud(SolicitudMaterial sol) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 10),
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        content: Row(children: [
          const Icon(Icons.notification_important,
              color: Colors.white, size: 20),
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
                  '${sol.nombreSolicitante} · ${sol.tipoMaterial} ×${sol.cantidad}',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  void _mostrarBannerModalidad(String modalidad, String nombreEntregador) {
    if (!mounted) return;
    final esYtll   = modalidad == 'yo_te_lo_llevo';
    final color    = esYtll ? _green : _orange;
    final icono    = esYtll ? Icons.directions_walk : Icons.person_pin_circle_outlined;
    final mensaje  = esYtll
        ? '$nombreEntregador te lo lleva — quédate donde estás'
        : 'Ve a buscar el material a donde está $nombreEntregador';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(children: [
          Icon(icono, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(mensaje,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
          ),
        ]),
      ),
    );
  }

  void _mostrarAtendida(SolicitudMaterial sol) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _orange,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(children: [
          const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'La solicitud de ${sol.tipoMaterial} ya fue atendida',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ]),
      ),
    );
  }

  void _suscribirCercanas() {
    if (_rut == null) return;
    debugPrint('🔵 [SolicitudMat] suscribirCercanas → escuchando destinatarios de $_rut');
    _subDestinatarios?.cancel();
    // Suscribirse SOLO a las filas donde este técnico fue seleccionado como
    // destinatario válido (el servidor ya aplicó filtro de rol + 5 km + stock).
    _subDestinatarios = _db
        .from('solicitudes_material_destinatarios')
        .stream(primaryKey: ['id'])
        .eq('rut_tecnico', _rut!)
        .listen((destRows) async {
      final gen = ++_cercanasGen;
      final pendientesRows = destRows
          .where((r) => r['estado'] == 'pendiente')
          .toList();
      debugPrint('🟢 [SolicitudMat] stream destinatarios → ${pendientesRows.length} pendientes (${destRows.length} total)');
      if (!mounted) return;

      // Solo las filas con estado 'pendiente' dan acceso a la solicitud
      final pendientesIds = pendientesRows
          .map((r) => r['solicitud_id'] as String)
          .toList();

      if (pendientesIds.isEmpty) {
        if (_cercanas.isNotEmpty && _streamInicializado) {
          ScaffoldMessenger.of(context).clearSnackBars();
          unawaited(_cancelarNotificacionMaterial());
        }
        _streamInicializado = true;
        setState(() => _cercanas = []);
        _actualizarMarkers();
        return;
      }

      // Obtener datos completos de esas solicitudes (solo las aún pendientes)
      final solicRows = await _db
          .from('solicitudes_material')
          .select()
          .inFilter('id', pendientesIds)
          .eq('estado', 'pendiente');

      if (gen != _cercanasGen || !mounted) return;

      final filtradas = (solicRows as List)
          .map((r) => SolicitudMaterial.fromMap(r as Map<String, dynamic>))
          .where((s) => s.rutSolicitante != _rut)
          .toList();

      debugPrint('🟢 [SolicitudMat] solicitudes visibles (rol + 5km validados): ${filtradas.length}');

      // Primera carga: mostrar lista sin alertar (solicitudes ya existían)
      if (!_streamInicializado) {
        for (final sol in filtradas) {
          _notificadas.add(sol.id);
        }
        await MaterialAlertaEstado.markAllSeen(filtradas.map((s) => s.id));
        _streamInicializado = true;
        setState(() => _cercanas = filtradas);
        _actualizarMarkers();
        return;
      }

      // Solo alertar solicitudes realmente nuevas tras la carga inicial
      for (final sol in filtradas) {
        debugPrint('🟡 [SolicitudMat] evaluando sol id=${sol.id} notificada=${_notificadas.contains(sol.id)}');
        if (!_notificadas.contains(sol.id)) {
          _notificadas.add(sol.id);
          await MaterialAlertaEstado.markSeen(sol.id);
          debugPrint('🟡 [SolicitudMat] NUEVA solicitud → alerta');
          await _tocarAlertaUnica();
          _mostrarBannerSolicitud(sol);
          break;
        }
      }

      // Detectar solicitudes que desaparecieron (aceptadas por otro o canceladas)
      final nuevosIds = filtradas.map((s) => s.id).toSet();
      for (final sol in _cercanas) {
        if (!nuevosIds.contains(sol.id) && _notificadas.contains(sol.id)) {
          unawaited(_cancelarNotificacionMaterial());
          if (!_aceptadasPorMi.contains(sol.id)) {
            final opened = await MaterialAlertaEstado.wasOpened(sol.id);
            if (gen != _cercanasGen || !mounted) return;
            await MaterialAlertaEstado.clearOpened(sol.id);
            await MaterialAlertaEstado.unmarkSeen(sol.id);
            _notificadas.remove(sol.id);
            if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
            if (opened && mounted) {
              _mostrarAtendida(sol);
            }
          }
        }
      }

      if (gen != _cercanasGen || !mounted) return;

      if (filtradas.isEmpty) {
        ScaffoldMessenger.of(context).clearSnackBars();
        unawaited(_cancelarNotificacionMaterial());
      }

      setState(() => _cercanas = filtradas);
      _actualizarMarkers();
    });
  }

  void _actualizarMarkers() {
    final markers = <Marker>{};

    // Mi posición
    final pos = _posicion;
    if (pos != null) {
      markers.add(Marker(
        markerId: const MarkerId('yo'),
        position: LatLng(pos.latitude, pos.longitude),
        icon: _iconoYo ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'Mi posición'),
      ));
    }

    // Entregador en camino (estado aceptada)
    final sol = _miSolicitud;
    if (sol != null &&
        sol.estado == 'aceptada' &&
        sol.latEntregador != null &&
        sol.lngEntregador != null) {
      markers.add(Marker(
        markerId: const MarkerId('entregador'),
        position: LatLng(sol.latEntregador!, sol.lngEntregador!),
        icon: _iconoTecnico ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(
          title: sol.nombreEntregador ?? 'Técnico en camino',
          snippet: 'Entregando ${sol.tipoMaterial}',
        ),
      ));
    }

    // Técnicos con solicitudes cercanas
    for (final s in _cercanas) {
      if (s.latSolicitante == null || s.lngSolicitante == null) continue;
      final dist = pos != null
          ? _distanciaKm(pos.latitude, pos.longitude,
                  s.latSolicitante!, s.lngSolicitante!)
              .toStringAsFixed(1)
          : '';
      markers.add(Marker(
        markerId: MarkerId(s.id),
        position: LatLng(s.latSolicitante!, s.lngSolicitante!),
        icon: _iconoTecnico ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(
          title: s.nombreSolicitante,
          snippet: '${s.tipoMaterial} ×${s.cantidad}  ${dist.isNotEmpty ? "$dist km" : ""}',
        ),
      ));
    }

    if (mounted) setState(() => _markers
      ..clear()
      ..addAll(markers));

    // Mover cámara
    final solAct = _miSolicitud;
    if (solAct != null &&
        solAct.estado == 'aceptada' &&
        solAct.latEntregador != null &&
        solAct.lngEntregador != null) {
      final destLat = solAct.latEntregador!;
      final destLng = solAct.lngEntregador!;
      if (pos != null) {
        final midLat = (pos.latitude + destLat) / 2;
        final midLng = (pos.longitude + destLng) / 2;
        _mapController?.animateCamera(
            CameraUpdate.newLatLng(LatLng(midLat, midLng)));
      } else {
        _mapController?.animateCamera(
            CameraUpdate.newLatLng(LatLng(destLat, destLng)));
      }
    } else if (solAct != null && solAct.estado == 'pendiente' && pos != null) {
      // Siempre centrar en la posición real del usuario cuando está buscando
      _mapController?.animateCamera(
          CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)));
    }
  }

  double _distanciaKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _rad(double deg) => deg * math.pi / 180;

  // ── Enviar solicitud ─────────────────────────────────────────

  Future<void> _enviarSolicitud() async {
    await _refrescarSesion();
    if (_materialSeleccionado == null || _rut == null) return;

    setState(() => _enviando = true);
    _iniciarProgresoEnvio();
    _syncTipsCalidad();

    // Refrescar GPS en paralelo — no bloquear la transición al mapa.
    unawaited(_obtenerPosicion().then((p) {
      if (p != null && mounted) setState(() => _posicion = p);
    }));

    debugPrint('🔵 [SolicitudMat] enviando solicitud: ${_materialSeleccionado!.nombre} ×$_cantidad');
    try {
      final nombreSol = await LogisticaService().nombrePorRut(
        _rut!,
        fallback: _nombre,
      );
      final row = await _db.from('solicitudes_material').insert({
        'rut_solicitante':       _rut,
        'nombre_solicitante':    nombreSol,
        'lat_solicitante':       _posicion?.latitude,
        'lng_solicitante':       _posicion?.longitude,
        'tipo_material':         _materialSeleccionado!.nombre,
        'es_seriado':            _materialSeleccionado!.esSeriado,
        'cantidad':              _cantidad,
        'series':                [],
        'estado':                'pendiente',
        'materiales_adicionales': _adicionales.map((a) => {
          'tipo':       a.material.nombre,
          'cantidad':   a.cantidad,
          'es_seriado': a.material.esSeriado,
        }).toList(),
      }).select().single();

      final sol = SolicitudMaterial.fromMap(row as Map<String, dynamic>);
      debugPrint('🟢 [SolicitudMat] solicitud creada id=${sol.id}');
      _avanzarFaseEspera(_FaseEsperaMaterial.buscandoTecnicos);
      setState(() {
        _miSolicitud = sol;
        _adicionales.clear();
      });
      _suscribirSolicitudPropia();
      if (_rut != null) unawaited(FcmService.instance.initPinMonitor(_rut!, sol.id));

      // Alerta de stock al bodeguero si material seriado y supera umbrales
      if (sol.esSeriado) {
        unawaited(_service.verificarAlertaStock(
          solicitudId:       sol.id,
          rutSolicitante:    _rut!,
          nombreSolicitante: nombreSol,
          tipoMaterial:      sol.tipoMaterial,
        ));
      }

      debugPrint('🔵 [SolicitudMat] notificarDestinatarios (5 km)…');
      final resultadoRadio = await _service.notificarDestinatarios(
        solicitudId:       sol.id,
        tipoMaterial:      sol.tipoMaterial,
        latSolicitante:    sol.latSolicitante,
        lngSolicitante:    sol.lngSolicitante,
        rutSolicitante:    _rut!,
        nombreSolicitante: nombreSol,
        soloRadio5Km:      true,
      );

      if (!mounted) return;

      if (resultadoRadio.sinDestinatarios && resultadoRadio.keplerDisponible) {
        final ampliar = await _ofrecerAmpliarBusquedaMaterial(sol);
        if (!mounted) return;
        if (ampliar) {
          debugPrint('🔵 [SolicitudMat] notificarDestinatarios (plantel)…');
          final resultadoPlantel = await _service.notificarDestinatarios(
            solicitudId:       sol.id,
            tipoMaterial:      sol.tipoMaterial,
            latSolicitante:    sol.latSolicitante,
            lngSolicitante:    sol.lngSolicitante,
            rutSolicitante:    _rut!,
            nombreSolicitante: nombreSol,
            soloRadio5Km:      false,
          );
          if (!mounted) return;
          if (resultadoPlantel.cantidad > 0) {
            await _mostrarMapaPlantelConStock(sol);
            if (mounted) {
              _snack(
                'Solicitud enviada a ${resultadoPlantel.cantidad} '
                'técnico${resultadoPlantel.cantidad == 1 ? '' : 's'} del plantel',
              );
            }
          } else {
            _snack('No hay técnicos con stock disponible en el plantel');
          }
        }
      }

      _avanzarFaseEspera(_FaseEsperaMaterial.enviandoSolicitud);

      // Aviso local a los 10 min (el servidor también escala al supervisor vía cron).
      _timer10min?.cancel();
      _timer10min = Timer(const Duration(minutes: 10), () {
        _mostrarAlertaSinRespuesta(sol);
      });

      // Actualizar mapa en try/catch — un error de mapa no debe bloquear la solicitud
      try {
        _actualizarMarkers();
      } catch (e) {
        debugPrint('⚠️ [SolicitudMat] error actualizando mapa (ignorado): $e');
      }
    } catch (e) {
      debugPrint('🔴 [SolicitudMat] error al enviar: $e');
      _detenerProgresoEnvio();
      setState(() => _enviando = false);
      _syncTipsCalidad();
      _snack(e is StateError ? e.message : 'Error al enviar: $e');
    }
  }

  Future<bool> _ofrecerAmpliarBusquedaMaterial(SolicitudMaterial sol) async {
    final ampliar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _border),
        ),
        title: Row(children: [
          Icon(Icons.search_off_rounded, color: _orange, size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Sin técnicos cercanos',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ]),
        content: const Text(
          'NO ENCONTRAMOS TÉCNICOS CON STOCK DISPONIBLE EN 5 KILÓMETROS '
          'A LA REDONDA.\n\n¿AMPLIAR LA BÚSQUEDA?',
          style: TextStyle(color: Colors.white70, height: 1.45, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No, esperar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.black,
            ),
            child: const Text(
              'Ampliar búsqueda',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    return ampliar == true;
  }

  Future<void> _mostrarMapaPlantelConStock(SolicitudMaterial sol) async {
    var pos = _posicion;
    if (pos == null &&
        sol.latSolicitante != null &&
        sol.lngSolicitante != null) {
      pos = Position(
        latitude: sol.latSolicitante!,
        longitude: sol.lngSolicitante!,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
    }
    pos ??= await _obtenerPosicion();
    if (pos == null || !mounted) return;

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => TecnicosCercanosMapaScreen(
          tipoMaterial: sol.tipoMaterial,
          posicionSolicitante: pos!,
          rutSolicitante: _rut ?? sol.rutSolicitante,
          radioKm: null,
        ),
      ),
    );
  }

  Future<void> _mostrarAlertaSinRespuesta(SolicitudMaterial sol) async {
    if (!mounted || _miSolicitud?.estado != 'pendiente') return;

    // Respaldo cliente (idempotente con alerta_supervisor_sin_respuesta_at en BD).
    unawaited(_service.notificarSupervisorSinRespuesta(
      solicitudId:    sol.id,
      rutSolicitante: sol.rutSolicitante,
      tipoMaterial:   sol.tipoMaterial,
    ));

    final pendientes =
        await _service.destinatariosPendientes(sol.id);
    if (!mounted) return;

    if (pendientes.isEmpty) {
      _snack(
          'Sin respuesta en 10 min — tu supervisor fue notificado');
      return;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: _border)),
        title: Row(children: [
          Icon(Icons.timer_off_outlined, color: _orange, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Sin respuesta (10 min)',
                style:
                    TextStyle(color: Colors.white, fontSize: 15)),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Técnicos notificados que aún no responden:',
                style:
                    TextStyle(color: _textDim, fontSize: 12)),
            const SizedBox(height: 10),
            ...pendientes.map((d) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          color: _orange,
                          shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        d['nombre_tecnico'] as String? ?? '',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${d['stock_disponible']} u.',
                        style: TextStyle(
                            color: _green, fontSize: 11),
                      ),
                    ),
                  ]),
                )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido',
                style: TextStyle(color: _accent)),
          ),
        ],
      ),
    );
  }

  // ── Aceptar solicitud (rol entregador) ───────────────────────

  Future<void> _aceptarSolicitud(SolicitudMaterial sol) async {
    if (_rut == null || _aceptandoId != null) return;

    final modalidad = await _elegirModalidadEntrega(sol);
    if (modalidad == null) return;
    if (!mounted) return;

    setState(() => _aceptandoId = sol.id);
    try {
      final updated = await _completarAceptacion(sol, modalidad);
      if (!mounted) return;

      _aceptadasPorMi.add(sol.id);
      unawaited(FcmService.cancelMaterialNotificacion());
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();

      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => EntregaEnCaminoScreen(
            solicitud:       updated,
            rutPropio:       _rut!,
            nombrePropio:    _nombre ?? '',
            posicionInicial: _posicion,
          ),
        ),
      );
    } catch (e) {
      _aceptadasPorMi.remove(sol.id);
      final msg = e is StateError
          ? e.message
          : 'Error al aceptar: $e';
      _snack(msg);
    } finally {
      if (mounted) setState(() => _aceptandoId = null);
    }
  }

  Future<SolicitudMaterial> _completarAceptacion(
    SolicitudMaterial sol,
    String modalidad,
  ) async {
    final lat = _posicion?.latitude;
    final lng = _posicion?.longitude;

    // GPS en background — no bloquear la navegación al mapa.
    unawaited(_obtenerPosicion().then((p) async {
      if (p == null) return;
      _posicion = p;
      try {
        await _db.from('solicitudes_material').update({
          'lat_entregador': p.latitude,
          'lng_entregador': p.longitude,
        }).eq('id', sol.id);
      } catch (_) {}
    }));

    await _refrescarSesion();
    await _service.aceptar(
      solicitudId:  sol.id,
      rutAceptador: _rut!,
      lat:          lat,
      lng:          lng,
      modalidad:    modalidad,
      nombreAceptadorSesion: _nombre,
    );

    // id_material Kepler en background (puede tardar varios segundos).
    if (!sol.esSeriado) {
      unawaited(() async {
        try {
          final idMat = await _service.resolverIdMaterial(
            rutEntregador: _rut!,
            tipoMaterial:  sol.tipoMaterial,
            esSeriado:     false,
            cantidad:      sol.cantidad,
          );
          if (idMat != null) {
            await _db.from('solicitudes_material').update({
              'id_material': idMat,
            }).eq('id', sol.id);
          }
        } catch (_) {}
      }());
    }

    return sol.copyWith(
      estado:           'aceptada',
      modalidad:        modalidad,
      rutEntregador:    _rut,
      nombreEntregador: _nombre,
      latEntregador:    lat,
      lngEntregador:    lng,
    );
  }

  /// ven_por_el: el solicitante inicia el viaje — GPS = partida del tramo.
  Future<void> _iniciarViajeMaterial() async {
    if (_miSolicitud == null || _rut == null) return;
    final sol = _miSolicitud!;
    if (sol.modalidad != 'ven_por_el' || sol.estado != 'aceptada') return;
    if (sol.partidaAt != null) return;

    setState(() => _marcandoLlegada = true);
    try {
      var pos = _posicion ?? await _obtenerPosicion();
      if (pos == null) {
        if (mounted) {
          _snack('Activa el GPS para registrar tu punto de partida');
        }
        return;
      }
      final ok = await CombustibleMaterialRutaService.instance
          .registrarPartidaSolicitud(
        solicitudId: sol.id,
        rutViajero: _rut!,
        lat: pos.latitude,
        lng: pos.longitude,
      );
      if (!ok) {
        if (mounted) _snack('No se pudo registrar la partida');
        return;
      }
      if (mounted) {
        setState(() {
          _miSolicitud = sol.copyWith(
            latPartida: pos.latitude,
            lngPartida: pos.longitude,
            partidaAt: DateTime.now(),
          );
        });
        _snack('Viaje iniciado — tu ubicación es el punto de partida');
      }
    } catch (e) {
      if (mounted) _snack('Error al iniciar viaje: $e');
    } finally {
      if (mounted) setState(() => _marcandoLlegada = false);
    }
  }

  /// Solicitante con modalidad "ven a buscar": avisa llegada si falla la geocerca.
  Future<void> _marcarLlegadaSolicitante() async {
    if (_miSolicitud == null || _marcandoLlegada) return;
    final sol = _miSolicitud!;
    if (sol.modalidad != 'ven_por_el' || sol.estado != 'aceptada') return;

    setState(() => _marcandoLlegada = true);
    try {
      await _db
          .from('solicitudes_material')
          .update({'estado': 'en_guia'})
          .eq('id', sol.id);
    } catch (e) {
      if (mounted) _snack('Error al marcar llegada: $e');
    } finally {
      if (mounted) setState(() => _marcandoLlegada = false);
    }
  }

  /// Muestra el modal "¿Cómo entregas?" y devuelve la modalidad elegida,
  /// o null si el usuario cerró sin elegir.
  Future<String?> _elegirModalidadEntrega(SolicitudMaterial sol) {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _border),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.swap_horiz, color: _accent, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('¿Cómo entregas el material?',
                    style: TextStyle(color: Colors.white, fontSize: 15)),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              sol.materialesAdicionales.isEmpty
                  ? '${sol.tipoMaterial} ×${sol.cantidad} para ${sol.nombreSolicitante}'
                  : '${sol.tipoMaterial} y ${sol.materialesAdicionales.length} material${sol.materialesAdicionales.length == 1 ? '' : 'es'} más para ${sol.nombreSolicitante}',
              style: TextStyle(color: _textDim, fontSize: 12),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Opción 1: Yo te lo llevo
            InkWell(
              onTap: () => Navigator.pop(ctx, 'yo_te_lo_llevo'),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _green.withValues(alpha: 0.4)),
                ),
                child: Row(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: _green.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.directions_walk,
                        color: _green, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('YO TE LO LLEVO',
                            style: TextStyle(
                                color: _green,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        SizedBox(height: 2),
                        Text('Me desplazo hasta donde estás tú',
                            style: TextStyle(color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: _green, size: 20),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            // Opción 2: Ven por él
            InkWell(
              onTap: () => Navigator.pop(ctx, 'ven_por_el'),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _orange.withValues(alpha: 0.4)),
                ),
                child: Row(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: _orange.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_pin_circle_outlined,
                        color: _orange, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('VEN POR ÉL',
                            style: TextStyle(
                                color: _orange,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        SizedBox(height: 2),
                        Text('El material está acá, tú te desplazas',
                            style: TextStyle(color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: _orange, size: 20),
                ]),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar', style: TextStyle(color: _textDim)),
          ),
        ],
      ),
    );
  }

  void _mostrarLlegadaEntregador(SolicitudMaterial sol) {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    unawaited(FcmService.playMaterialLlegada());
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: _green.withValues(alpha: 0.5))),
        title: Row(children: [
          Icon(Icons.directions_walk, color: _green, size: 22),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('¡Tu colega ya llegó!',
                style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ]),
        content: Text(
          'Tu colega llegó con tus materiales. Acércate y firma la guía de entrega en su dispositivo.',
          style: TextStyle(color: _textDim, fontSize: 13),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12)),
            child: const Text('Entendido',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelar() async {
    if (_miSolicitud == null || _rut == null) return;
    final sol = _miSolicitud!;
    if (sol.estado == 'completada' || sol.estado == 'cancelada') {
      _snack('Esta solicitud ya no se puede cancelar.');
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('Cancelar solicitud',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          '¿Cancelar la solicitud de ${sol.tipoMaterial}?\n'
          'Se notificará al entregador.',
          style: const TextStyle(color: _textDim, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No', style: TextStyle(color: _textDim)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _red),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
    try {
      await _service.cancelarSolicitud(
        solicitudId:    sol.id,
        rutCancelador:  _rut!,
      );
      await _finalizarCancelada(cancelacionLocal: true);
    } catch (e) {
      _snack(e is StateError ? e.message : 'Error al cancelar: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  Widget _buildBloqueoAcceso(String mensaje) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Solicitud de Material',
            style: TextStyle(color: Colors.white, fontSize: 15)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.block_rounded,
                  color: _red.withValues(alpha: 0.9), size: 48),
              const SizedBox(height: 16),
              Text(
                mensaje,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.45),
                textAlign: TextAlign.center,
              ),
              if (_rut != null) ...[
                const SizedBox(height: 12),
                Text(
                  'RUT: $_rut',
                  style: const TextStyle(color: _textDim, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_initListo) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _surface,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Solicitud de Material',
              style: TextStyle(color: Colors.white, fontSize: 15)),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: _accent),
        ),
      );
    }

    if (_bloqueoAcceso != null) {
      return _buildBloqueoAcceso(_bloqueoAcceso!);
    }

    if (_aceptandoId != null) {
      return _buildTransicionMapa(
        titulo: 'Confirmando entrega…',
        subtitulo: 'Aceptando solicitud de material',
      );
    }

    // Transición al mapa mientras avanza la barra de progreso
    if (_overlayProgresoVisible && _miSolicitud == null && _cercanas.isEmpty) {
      return _buildTransicionMapa(buscandoTecnico: true);
    }

    // Prioridad: si espera que acepten su solicitud, mostrar mapa + overlay.
    if (_miSolicitud != null && _miSolicitud!.estado == 'pendiente') {
      return _buildMapaView();
    }

    if (_cercanas.isEmpty) {
      if (_miSolicitud != null && _miSolicitud!.estado == 'aceptada') {
        return _buildAceptadaView();
      }
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Solicitud de Material',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          if (_rut != null)
            TextButton.icon(
              onPressed: _cargandoSaldo ? null : _verMiSaldo,
              icon: _cargandoSaldo
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _accent,
                      ),
                    )
                  : const Icon(Icons.inventory_2_outlined,
                      color: _accent, size: 18),
              label: const Text('Mi saldo',
                  style: TextStyle(color: _accent, fontSize: 12)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_pinPendienteEntregador != null) ...[
            _bannerPinPendienteEntregador(),
            const SizedBox(height: 12),
          ],
          // ── Solicitudes cercanas (rol entregador) ──
          if (_cercanas.isNotEmpty) ...[
            _seccion('SOLICITUDES CERCANAS', Icons.people_alt_outlined, _accent),
            const SizedBox(height: 8),
            ..._cercanas.map(_buildSolicitudCercana),
            const SizedBox(height: 20),
          ],

          // ── Mi solicitud activa (aceptada / en_guia) ──
          if (_miSolicitud != null) ...[
            _seccion('MI SOLICITUD', Icons.inventory_2_outlined, _orange),
            const SizedBox(height: 8),
            _buildMiSolicitudCard(),
          ] else ...[
            // ── Formulario ──
            _seccion('NUEVA SOLICITUD', Icons.add_box_outlined, _accent),
            const SizedBox(height: 12),
            _buildFormulario(),
          ],

          // ── Mis guías del mes ──
          if (_guiasEntregadas.isNotEmpty || _guiasRecibidas.isNotEmpty) ...[
            const SizedBox(height: 28),
            _seccion('MIS GUÍAS DEL MES', Icons.receipt_long, _accent),
            const SizedBox(height: 12),

            if (_guiasEntregadas.isNotEmpty) ...[
              Row(children: [
                Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(
                      color: _green, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                const Text('Materiales entregados',
                    style: TextStyle(
                        color: _green,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
              ]),
              const SizedBox(height: 8),
              ..._guiasEntregadas.map(_buildGuiaCard),
              const SizedBox(height: 16),
            ],

            if (_guiasRecibidas.isNotEmpty) ...[
              Row(children: [
                Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(
                      color: _orange, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                const Text('Materiales recibidos',
                    style: TextStyle(
                        color: _orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
              ]),
              const SizedBox(height: 8),
              ..._guiasRecibidas.map(_buildGuiaCard),
            ],
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Abrir Google Maps ────────────────────────────────────────

  Future<void> _abrirEnMapas(double lat, double lng) async {
    final dest = '$lat,$lng';
    final pos = _posicion;
    final mapsUrl = Uri.parse(
      pos != null
          ? 'https://www.google.com/maps/dir/?api=1'
              '&origin=${pos.latitude},${pos.longitude}'
              '&destination=$dest'
              '&travelmode=driving'
          : 'https://www.google.com/maps/dir/?api=1'
              '&destination=$dest'
              '&travelmode=driving',
    );
    final geoUri = Uri.parse('geo:$dest?q=$dest');
    try {
      if (await canLaunchUrl(mapsUrl)) {
        await launchUrl(mapsUrl, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(geoUri)) {
        await launchUrl(geoUri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        _snack('No se pudo abrir el mapa. Instala Google Maps.');
      }
    } catch (_) {
      _snack('Error al abrir el mapa.');
    }
  }

  // ── Vista emisor: entregador aceptó (estado aceptada) ────────

  Widget _buildAceptadaView() {
    final sol = _miSolicitud!;
    final pos = _posicion;
    final esVenPorEl = sol.modalidad == 'ven_por_el';
    final viajeIniciado = sol.partidaAt != null;
    final puedeIniciarViaje =
        esVenPorEl && sol.estado == 'aceptada' && !viajeIniciado && !_marcandoLlegada;
    final puedeMarcarLlegada =
        esVenPorEl && sol.estado == 'aceptada' && viajeIniciado && !_marcandoLlegada;

    double? distM;
    if (pos != null &&
        sol.latEntregador != null &&
        sol.lngEntregador != null) {
      distM = _distanciaKm(pos.latitude, pos.longitude,
              sol.latEntregador!, sol.lngEntregador!) *
          1000;
    }

    final distLabel = distM == null
        ? null
        : distM < 1000
            ? '${distM.toInt()} m'
            : '${(distM / 1000).toStringAsFixed(1)} km';

    final etaLabel = distM == null
        ? null
        : distM < 100
            ? 'menos de 1 min'
            : '~${(distM / 500).ceil()} min';

    final camPos = sol.latEntregador != null
        ? LatLng(sol.latEntregador!, sol.lngEntregador!)
        : pos != null
            ? LatLng(pos.latitude, pos.longitude)
            : const LatLng(-33.45, -70.66);

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // ── Mapa full-screen ────────────────────────────────
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition:
                  CameraPosition(target: camPos, zoom: 14),
              markers: _markers,
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: false,
              mapType: MapType.normal,
              style: MapStyles.estiloMapaUberDark,
              onMapCreated: (ctrl) {
                _mapController = ctrl;
                Future.delayed(
                    const Duration(milliseconds: 300), _actualizarMarkers);
              },
            ),
          ),

          // ── Chip superior — Column para que el Stack tome la altura completa
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Row(children: [
                    GestureDetector(
                      onTap: () => Navigator.maybePop(context),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.18),
                                blurRadius: 8)
                          ],
                        ),
                        child: const Icon(Icons.arrow_back,
                            color: Colors.black87, size: 20),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _green.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                              color: _green.withValues(alpha: 0.3),
                              blurRadius: 8)
                        ],
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                          esVenPorEl
                              ? Icons.directions_car_outlined
                              : Icons.directions_walk,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          esVenPorEl
                              ? 'Ve a buscar · ${sol.nombreEntregador ?? "Técnico"}'
                              : 'En camino · ${sol.nombreEntregador ?? "Técnico"}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ]),
                    ),
                  ]),
                ),
              ],
            ),
          ),

          // ── Panel inferior ──────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _border),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, -4))
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nombre entregador
                    Row(children: [
                      Icon(Icons.directions_walk,
                          color: _green, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          sol.nombreEntregador ?? 'Técnico en camino',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 10),

                    if (sol.pinCodigo != null && sol.pinCodigo!.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00D4AA).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: const Color(0xFF00D4AA)
                                  .withValues(alpha: 0.45)),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'Tu PIN de confirmación',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              sol.pinCodigo!,
                              style: const TextStyle(
                                color: Color(0xFF00D4AA),
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 8,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Díselo al entregador para cerrar el traspaso',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 11),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Distancia + ETA grandes
                    if (distLabel != null)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            distLabel,
                            style: TextStyle(
                              color: _green,
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              height: 1,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('de distancia',
                                style: TextStyle(
                                    color: _textDim, fontSize: 12)),
                          ),
                        ],
                      )
                    else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _textDim),
                          ),
                          const SizedBox(width: 8),
                          Text('Calculando distancia…',
                              style: TextStyle(
                                  color: _textDim, fontSize: 12)),
                        ],
                      ),

                    if (etaLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '$etaLabel estimados',
                        style: TextStyle(color: _textDim, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],

                    const SizedBox(height: 8),
                    // Material
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: _orange.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6)),
                        child: Text(
                          '${sol.cantidad}× ${sol.tipoMaterial}',
                          style: const TextStyle(
                              color: _orange,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Estado de espera
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: _green.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: _green.withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        Icon(
                          esVenPorEl
                              ? Icons.store_outlined
                              : Icons.phone_android,
                          color: _green,
                          size: 16,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            esVenPorEl
                                ? 'Ve donde está ${sol.nombreEntregador ?? "tu colega"} y avisa cuando llegues'
                                : 'Cuando llegue tu colega, firma la guía en su dispositivo',
                            style: const TextStyle(
                                color: _green,
                                fontSize: 12,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ]),
                    ),
                    if (puedeIniciarViaje) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _marcandoLlegada
                              ? null
                              : _iniciarViajeMaterial,
                          icon: _marcandoLlegada
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Icon(Icons.directions_car_filled_outlined,
                                  size: 18),
                          label: Text(
                            _marcandoLlegada
                                ? 'Registrando partida…'
                                : 'Voy por el material',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                    if (puedeMarcarLlegada) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _marcandoLlegada
                              ? null
                              : _marcarLlegadaSolicitante,
                          icon: _marcandoLlegada
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Icon(Icons.place_outlined, size: 18),
                          label: Text(
                            _marcandoLlegada
                                ? 'Marcando llegada…'
                                : 'Ya llegué — avisar al entregador',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: _green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),

                    // Botón abrir en mapas
                    if (sol.latEntregador != null &&
                        sol.lngEntregador != null)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => _abrirEnMapas(
                              sol.latEntregador!, sol.lngEntregador!),
                          icon:
                              const Icon(Icons.map_outlined, size: 16),
                          label: const Text('Abrir en Google Maps',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                          style: FilledButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                                vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    // Cancelar
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _cancelar,
                        style: OutlinedButton.styleFrom(
                            foregroundColor: _red,
                            side: BorderSide(
                                color: _red.withValues(alpha: 0.5)),
                            padding: const EdgeInsets.symmetric(
                                vertical: 10)),
                        child: const Text('Cancelar solicitud'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Vista mapa (estado pendiente) ────────────────────────────

  /// Pantalla de carga con mapa mientras se procesa la solicitud o la aceptación.
  Widget _buildTransicionMapa({
    bool buscandoTecnico = false,
    String? titulo,
    String? subtitulo,
  }) {
    final pos = _posicion;
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: pos != null
                    ? LatLng(pos.latitude, pos.longitude)
                    : const LatLng(-33.45, -70.66),
                zoom: 14,
              ),
              myLocationEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: false,
              mapType: MapType.normal,
              style: MapStyles.estiloMapaUberDark,
            ),
          ),
          if (buscandoTecnico)
            _buildCapaBuscandoTecnico()
          else
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.35),
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 32),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 24),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _border),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: _accent,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          titulo ?? 'Cargando…',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if (subtitulo != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            subtitulo,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: _textDim, fontSize: 13),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Align(
                alignment: Alignment.topLeft,
                child: GestureDetector(
                  onTap: () {
                    if (_overlayProgresoVisible) return;
                    Navigator.maybePop(context);
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_back,
                        color: Colors.black87, size: 20),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapaView() {
    final sol = _miSolicitud!;
    final pos = _posicion;

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // ── Mapa full-screen ──────────────────────────────────
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: pos != null
                    ? LatLng(pos.latitude, pos.longitude)
                    : const LatLng(-33.45, -70.66),
                zoom: 14,
              ),
              markers:               _markers,
              myLocationEnabled:     false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled:   false,
              mapToolbarEnabled:     false,
              compassEnabled:        false,
              mapType:               MapType.normal,
              style:                 MapStyles.estiloMapaUberDark,
              onMapCreated: (ctrl) {
                _mapController = ctrl;
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (mounted) _actualizarMarkers();
                });
              },
            ),
          ),

          if (_overlayProgresoVisible)
            _buildCapaBuscandoTecnico(bottomReserva: 210),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Align(
                alignment: Alignment.topLeft,
                child: GestureDetector(
                  onTap: () => Navigator.maybePop(context),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 8)
                      ],
                    ),
                    child: const Icon(Icons.arrow_back,
                        color: Colors.black87, size: 20),
                  ),
                ),
              ),
            ),
          ),

          // ── Panel inferior ────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _border),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, -4))
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(sol.tipoMaterial,
                            style: const TextStyle(
                                color: _orange,
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                      ),
                      const SizedBox(width: 8),
                      Text('× ${sol.cantidad}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                      if (sol.esSeriado) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                              color: _accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4)),
                          child: const Text('SERIADO',
                              style:
                                  TextStyle(color: _accent, fontSize: 9)),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 4),
                    Text(
                      'Las series se registran en la guía de entrega',
                      style: TextStyle(
                          color: _textDim.withValues(alpha: 0.7), fontSize: 11),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _cancelar,
                        style: OutlinedButton.styleFrom(
                            foregroundColor: _red,
                            side: BorderSide(
                                color: _red.withValues(alpha: 0.5)),
                            padding:
                                const EdgeInsets.symmetric(vertical: 12)),
                        child: const Text('Cancelar solicitud'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Pulse de radar ────────────────────────────────────
          if (pos != null)
            Positioned(
              top: MediaQuery.of(context).size.height * 0.38,
              left: MediaQuery.of(context).size.width / 2 - 50,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: _accent.withValues(alpha: 0.4), width: 2),
                ),
              )
                  .animate(onPlay: (c) => c.repeat())
                  .scale(
                      begin: const Offset(1, 1),
                      end: const Offset(2.5, 2.5),
                      duration: 2000.ms,
                      curve: Curves.easeOut)
                  .fadeOut(duration: 1500.ms),
            ),
        ],
      ),
    );
  }

  // ── Encabezado de sección ────────────────────────────────────

  Widget _seccion(String titulo, IconData icon, Color color) => Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(titulo,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 0.8)),
        ],
      );

  // ── Card solicitud cercana (rol entregador) ──────────────────

  Widget _buildSolicitudCercana(SolicitudMaterial sol) {
    final dist = (_posicion != null &&
            sol.latSolicitante != null &&
            sol.lngSolicitante != null)
        ? _distanciaKm(_posicion!.latitude, _posicion!.longitude,
                sol.latSolicitante!, sol.lngSolicitante!)
            .toStringAsFixed(1)
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _orange.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: _orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6)),
            child: Text(sol.tipoMaterial,
                style: const TextStyle(
                    color: _orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          ),
          const SizedBox(width: 8),
          Text('× ${sol.cantidad}',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          if (sol.materialesAdicionales.isNotEmpty) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                  color: _textDim.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4)),
              child: Text('+${sol.materialesAdicionales.length} más',
                  style: const TextStyle(color: _textDim, fontSize: 9)),
            ),
          ],
          if (sol.esSeriado) ...[
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4)),
              child: const Text('SERIADO',
                  style: TextStyle(color: _accent, fontSize: 9)),
            ),
          ],
          const Spacer(),
          if (dist != null)
            Text('$dist km',
                style: const TextStyle(color: _textDim, fontSize: 11)),
        ]),
        const SizedBox(height: 6),
        Text(sol.nombreSolicitante,
            style: const TextStyle(color: _textDim, fontSize: 12)),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _aceptandoId != null ? null : () => _aceptarSolicitud(sol),
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Aceptar y entregar',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ),
      ]),
    );
  }

  // ── Card solicitud propia (aceptada / en_guia) ───────────────

  Widget _buildMiSolicitudCard() {
    final sol = _miSolicitud!;
    final (label, color, icon) = switch (sol.estado) {
      'aceptada' => (
          'Técnico en camino: ${sol.nombreEntregador}',
          _green,
          Icons.directions_walk
        ),
      'en_guia' => (
          'Listo para firmar guía',
          _accent,
          Icons.draw_outlined
        ),
      'firmada' => (
          'Confirma el traspaso con PIN',
          _orange,
          Icons.lock_outline
        ),
      _ => ('Estado: ${sol.estado}', _textDim, Icons.info_outline),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
          ),
        ]),
        const SizedBox(height: 12),
        _fila('Material', sol.tipoMaterial),
        _fila('Cantidad', '${sol.cantidad}'),
        ...sol.materialesAdicionales.map((m) =>
          _fila('+ ${m['tipo'] as String? ?? ''}', '${m['cantidad'] ?? 1}'),
        ),
        const SizedBox(height: 12),
        if (sol.estado == 'en_guia')
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _accent.withValues(alpha: 0.3)),
            ),
            child: const Row(children: [
              Icon(Icons.phone_android, color: _accent, size: 14),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Acércate y firma la guía en el dispositivo de tu colega',
                  style: TextStyle(color: _accent, fontSize: 12),
                ),
              ),
            ]),
          ),
        if (sol.estado == 'firmada' &&
            sol.pinCodigo != null &&
            sol.pinCodigo!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: _orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _orange.withValues(alpha: 0.35)),
            ),
            child: Column(children: [
              const Text('Tu PIN de confirmación',
                  style: TextStyle(color: _orange, fontSize: 11)),
              const SizedBox(height: 6),
              Text(
                sol.pinCodigo!,
                style: const TextStyle(
                  color: Color(0xFF00D4AA),
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Díselo al entregador para cerrar el traspaso',
                style: TextStyle(color: Colors.white54, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ]),
          ),
        ],
        if (sol.estado != 'completada' && sol.estado != 'cancelada') ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _cancelar,
              style: OutlinedButton.styleFrom(
                foregroundColor: _red,
                side: BorderSide(color: _red.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              child: const Text('Cancelar solicitud'),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _buildGuiaCard(Map<String, dynamic> guia) {
    final detalle      = guia['detalle_material'] as String? ?? 'Sin detalle';
    final fecha        = guia['fecha'] as String? ?? '';
    final horaRaw      = guia['hora'] as String? ?? '';
    final hora         = horaRaw.length >= 5 ? horaRaw.substring(0, 5) : horaRaw;
    final estadoGuia   = guia['estado'] as String? ?? '';
    final puedePdf     = _estadosGuiaHistorial.contains(estadoGuia);
    final esEntregador = guia['rut_entregador'] == _rut;
    final contraparte  = esEntregador
        ? (guia['nombre_solicitante'] as String? ?? 'Solicitante')
        : (guia['nombre_entregador']  as String? ?? 'Entregador');

    return InkWell(
      onTap: () => _abrirPdfGuia(guia),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border),
        ),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (esEntregador ? _green : _orange).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              esEntregador ? Icons.arrow_upward : Icons.arrow_downward,
              color: esEntregador ? _green : _orange,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(detalle,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
              const SizedBox(height: 2),
              Text(esEntregador ? 'Para: $contraparte' : 'De: $contraparte',
                  style: TextStyle(color: _textDim, fontSize: 11)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(fecha, style: TextStyle(color: _textDim, fontSize: 10)),
            Text(hora,  style: TextStyle(color: _textDim, fontSize: 10)),
            const SizedBox(height: 4),
            if (puedePdf)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.picture_as_pdf, color: _accent, size: 11),
                const SizedBox(width: 2),
                Text('Ver PDF', style: TextStyle(color: _accent, fontSize: 10)),
              ])
            else
              Text('Pendiente', style: TextStyle(color: _orange, fontSize: 10)),
          ]),
        ]),
      ),
    );
  }

  /// Toca una card: busca la guía completa (con firmas) y abre el PDF en la app.
  Future<void> _abrirPdfGuia(Map<String, dynamic> guiaMeta) async {
    final id      = guiaMeta['id'] as String?;
    final estadoGuia = guiaMeta['estado'] as String? ?? '';
    if (id == null) return;

    if (!_estadosGuiaHistorial.contains(estadoGuia)) {
      _snack('La guía aún no está disponible.');
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Generando PDF…'),
        duration: Duration(seconds: 30),
      ),
    );

    try {
      final row   = await _db.from('solicitudes_bodega').select().eq('id', id).single();
      final bytes = await GuiaPdfService.generar(
        guia: row as Map<String, dynamic>,
      );
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (ctx) => Scaffold(
            backgroundColor: _bg,
            appBar: AppBar(
              backgroundColor: _surface,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
              title: const Text('Guía de entrega',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.share_outlined, color: _accent),
                  tooltip: 'Compartir',
                  onPressed: () async {
                    final fecha =
                        (guiaMeta['fecha'] as String? ?? '').replaceAll('-', '');
                    await Printing.sharePdf(
                        bytes: bytes, filename: 'guia_$fecha.pdf');
                  },
                ),
              ],
            ),
            body: PdfPreview(
              build: (_) async => bytes,
              allowSharing: false,
              allowPrinting: false,
              canChangePageFormat: false,
              canChangeOrientation: false,
              initialPageFormat: PdfPageFormat.a4,
            ),
          ),
        ),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      _snack('Error al generar PDF: $e');
    }
  }

  Widget _fila(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Text('$label: ',
              style: const TextStyle(color: _textDim, fontSize: 12)),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ]),
      );

  // ── Formulario nueva solicitud ───────────────────────────────

  Widget _buildFormulario() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Material selector — altura máxima 45 % de pantalla con scroll interno
      Container(
        decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _border)),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.45,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: SingleChildScrollView(
            child: Column(
              children: [
                _grupoMaterial('No seriados',
                    kMateriales.where((m) => !m.esSeriado).toList()),
                const Divider(height: 1, color: Color(0xFF1E3A5F)),
                _grupoMaterial('Seriados',
                    kMateriales.where((m) => m.esSeriado).toList()),
              ],
            ),
          ),
        ),
      ),

      const SizedBox(height: 16),

      if (_materialSeleccionado != null) ...[
        // Cantidad
        const Text('Cantidad',
            style: TextStyle(color: _textDim, fontSize: 12)),
        const SizedBox(height: 6),
        Row(children: [
          _btnCantidad(Icons.remove, () {
            if (_cantidad > 1) setState(() => _cantidad--);
          }),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('$_cantidad',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20)),
          ),
          _btnCantidad(Icons.add, () => setState(() => _cantidad++)),
        ]),

        if (_materialSeleccionado!.esSeriado) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _accent.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, color: _accent, size: 14),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Las series se registran al generar la guía de entrega.',
                  style: TextStyle(color: _accent, fontSize: 11),
                ),
              ),
            ]),
          ),
        ],

        // ── Materiales adicionales ────────────────────────────────
        if (_adicionales.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('Materiales adicionales',
              style: TextStyle(color: _textDim, fontSize: 12)),
          const SizedBox(height: 6),
          ..._adicionales.asMap().entries.map((e) => Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _border),
            ),
            child: Row(children: [
              Icon(
                e.value.material.esSeriado ? Icons.qr_code : Icons.category_outlined,
                color: _accent, size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${e.value.material.nombre} × ${e.value.cantidad}',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _adicionales.removeAt(e.key)),
                child: const Icon(Icons.close, color: _textDim, size: 16),
              ),
            ]),
          )),
        ],
        if (_adicionales.length < 2) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _agregarMaterialAdicional,
            icon: const Icon(Icons.add_circle_outline, size: 16),
            label: const Text('Agregar otro material'),
            style: TextButton.styleFrom(
              foregroundColor: _accent,
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],

        const SizedBox(height: 12),

        // Botón ver técnicos en mapa
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _materialSeleccionado == null
                ? null
                : () async {
                    final pos = _posicion ?? await _obtenerPosicion();
                    if (pos == null || !mounted) return;
                    await Navigator.push<String>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TecnicosCercanosMapaScreen(
                          tipoMaterial:       _materialSeleccionado!.nombre,
                          posicionSolicitante: pos,
                          rutSolicitante:     _rut ?? '',
                        ),
                      ),
                    );
                  },
            icon: const Icon(Icons.map_outlined, size: 18),
            label: const Text('Ver técnicos cercanos en mapa'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _accent,
              side: const BorderSide(color: _accent),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Botón enviar
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _enviando ? null : _enviarSolicitud,
            icon: _enviando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send, size: 18),
            label: Text(_enviando ? 'Enviando...' : 'Enviar solicitud',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14)),
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ] else
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border)),
          child: const Row(children: [
            Icon(Icons.touch_app, color: _textDim, size: 18),
            SizedBox(width: 10),
            Text('Selecciona un material de la lista',
                style: TextStyle(color: _textDim, fontSize: 13)),
          ]),
        ),
    ]);
  }

  Widget _grupoMaterial(String titulo, List<MaterialItem> items) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Text(titulo.toUpperCase(),
            style: const TextStyle(
                color: _textDim,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8)),
      ),
      ...items.map((m) {
        final sel = _materialSeleccionado?.nombre == m.nombre;
        return InkWell(
          onTap: () => setState(() {
            _materialSeleccionado = m;
            _cantidad = 1;
          }),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: sel ? _accent.withValues(alpha: 0.1) : Colors.transparent,
              border: Border(
                  left: BorderSide(
                      color: sel ? _accent : Colors.transparent,
                      width: 3)),
            ),
            child: Row(children: [
              Icon(
                m.esSeriado
                    ? Icons.memory_outlined
                    : Icons.cable_outlined,
                color: sel ? _accent : _textDim,
                size: 16,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(m.nombre,
                    style: TextStyle(
                        color: sel ? Colors.white : _textDim,
                        fontSize: 13,
                        fontWeight:
                            sel ? FontWeight.bold : FontWeight.normal)),
              ),
              if (sel)
                const Icon(Icons.check_circle, color: _accent, size: 16),
            ]),
          ),
        );
      }),
    ]);
  }

  Future<void> _agregarMaterialAdicional() async {
    MaterialItem? sel;
    int cant = 1;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: _surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: _border),
          ),
          title: const Text('Agregar material',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          content: SizedBox(
            width: double.maxFinite,
            height: 340,
            child: Column(children: [
              Expanded(
                child: ListView(
                  children: kMateriales.map((m) {
                    final esSel = sel?.nombre == m.nombre;
                    return InkWell(
                      onTap: () => setS(() { sel = m; cant = 1; }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: esSel ? _accent.withValues(alpha: 0.1) : Colors.transparent,
                          border: Border(left: BorderSide(
                              color: esSel ? _accent : Colors.transparent, width: 3)),
                        ),
                        child: Row(children: [
                          Icon(m.esSeriado ? Icons.qr_code : Icons.category_outlined,
                              color: esSel ? _accent : _textDim, size: 15),
                          const SizedBox(width: 8),
                          Text(m.nombre,
                              style: TextStyle(
                                  color: esSel ? Colors.white : _textDim,
                                  fontSize: 13,
                                  fontWeight: esSel ? FontWeight.w600 : FontWeight.normal)),
                        ]),
                      ),
                    );
                  }).toList(),
                ),
              ),
              if (sel != null) ...[
                const Divider(height: 1, color: Color(0xFF1E3A5F)),
                const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _btnCantidad(Icons.remove, () { if (cant > 1) setS(() => cant--); }),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text('$cant',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                  ),
                  _btnCantidad(Icons.add, () => setS(() => cant++)),
                ]),
                const SizedBox(height: 4),
              ],
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: _textDim)),
            ),
            if (sel != null)
              FilledButton(
                onPressed: () {
                  setState(() => _adicionales.add((material: sel!, cantidad: cant)));
                  Navigator.pop(ctx);
                },
                style: FilledButton.styleFrom(
                    backgroundColor: _accent, foregroundColor: Colors.black),
                child: const Text('Agregar',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _btnCantidad(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _border)),
          child: Icon(icon, color: _accent, size: 20),
        ),
      );
}

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:url_launcher/url_launcher.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:agente_desconexiones/constants/map_styles.dart';
import 'package:agente_desconexiones/models/solicitud_material.dart';
import 'package:agente_desconexiones/screens/entrega_en_camino_screen.dart';
import 'package:agente_desconexiones/services/fcm_service.dart';
import 'package:agente_desconexiones/services/material_solicitud_service.dart';
import 'package:agente_desconexiones/services/supabase_service.dart';
import 'package:agente_desconexiones/screens/tecnicos_cercanos_mapa_screen.dart';

class SolicitudMaterialScreen extends StatefulWidget {
  const SolicitudMaterialScreen({super.key});

  @override
  State<SolicitudMaterialScreen> createState() =>
      _SolicitudMaterialScreenState();
}

class _SolicitudMaterialScreenState extends State<SolicitudMaterialScreen> {
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

  // ── Formulario ───────────────────────────────────────────────
  MaterialItem? _materialSeleccionado;
  int _cantidad = 1;
  final List<({MaterialItem material, int cantidad})> _adicionales = [];

  // ── Estado solicitud propia ──────────────────────────────────
  SolicitudMaterial? _miSolicitud;
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

  final _db      = Supabase.instance.client;
  final _service = MaterialSolicitudService();

  @override
  void initState() {
    super.initState();
    _crearIconos();
    _init();
  }

  @override
  void dispose() {
    _subPropia?.cancel();
    _subDestinatarios?.cancel();
    _timer10min?.cancel();
    _timerGpsAceptada?.cancel();
    _pollingEntregador?.cancel();
    _mapController?.dispose();
    super.dispose();
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

  // ── Init ─────────────────────────────────────────────────────

  Future<void> _init() async {
    _cancelarNotificacionMaterial(); // descarta notificación 42 del sistema al entrar
    final prefs = await SharedPreferences.getInstance();
    _rut    = prefs.getString('rut_tecnico');
    _nombre = prefs.getString('nombre_tecnico') ?? 'Técnico';
    _posicion = await _obtenerPosicion();

    debugPrint('🔵 [SolicitudMat] init → rut=$_rut pos=${_posicion?.latitude},${_posicion?.longitude}');

    if (_rut == null) {
      debugPrint('🔴 [SolicitudMat] sin RUT, abortando init');
      return;
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
        .inFilter('estado', ['pendiente', 'aceptada', 'en_guia'])
        .order('created_at', ascending: false)
        .limit(1);

    debugPrint('🔵 [SolicitudMat] solicitud propia activa: ${rows.length}');

    if (rows.isNotEmpty && mounted) {
      setState(() =>
          _miSolicitud = SolicitudMaterial.fromMap(rows.first as Map<String, dynamic>));
      _suscribirSolicitudPropia();
      // Activar monitor de PIN: A verá su PIN en un dialog global cuando B confirme.
      if (_rut != null && _miSolicitud != null) {
        unawaited(FcmService.instance.initPinMonitor(_rut!, _miSolicitud!.id));
      }
    }

    _suscribirCercanas();
    _cargarGuiasMes();
    if (mounted) {
      setState(() {});
      // Reanima la cámara cuando el mapa esté listo con la posición correcta
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _actualizarMarkers();
      });
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
    const cols = 'id, solicitud_id, fecha, hora, lugar, '
        'detalle_material, cantidad, series, estado, '
        'nombre_solicitante, rut_solicitante, nombre_entregador, rut_entregador';
    try {
      final results = await Future.wait([
        _db
            .from('solicitudes_bodega')
            .select(cols)
            .eq('rut_entregador', _rut!)
            .gte('fecha', inicio)
            .lte('fecha', fin)
            .order('fecha', ascending: false),
        _db
            .from('solicitudes_bodega')
            .select(cols)
            .eq('rut_solicitante', _rut!)
            .gte('fecha', inicio)
            .lte('fecha', fin)
            .order('fecha', ascending: false),
      ]);
      if (!mounted) return;
      setState(() {
        _guiasEntregadas =
            (results[0] as List).cast<Map<String, dynamic>>();
        _guiasRecibidas  =
            (results[1] as List).cast<Map<String, dynamic>>();
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

  void _suscribirSolicitudPropia() {
    if (_miSolicitud == null) return;
    _subPropia?.cancel();
    final solicitudIdEsperado = _miSolicitud!.id;
    _subPropia = _db
        .from('solicitudes_material')
        .stream(primaryKey: ['id'])
        .eq('id', solicitudIdEsperado)
        .listen((rows) {
      if (rows.isEmpty || !mounted) return;
      final updated =
          SolicitudMaterial.fromMap(rows.first as Map<String, dynamic>);
      // Ignorar si este evento pertenece a una suscripción anterior
      if (updated.id != _miSolicitud?.id) return;
      setState(() => _miSolicitud = updated);

      if (updated.estado == 'cancelada') {
        _timer10min?.cancel();
        _timerGpsAceptada?.cancel();
        _timerGpsAceptada = null;
        _pollingEntregador?.cancel();
        _pollingEntregador = null;
        _subPropia?.cancel();
        _bannerModalidadMostrado = false;
        _llegadaMostrada         = false;
        unawaited(FcmService.instance.detenerPinMonitor());
        setState(() => _miSolicitud = null);
        return;
      }

      if (updated.estado != 'pendiente') {
        _timer10min?.cancel();
      }
      if (updated.estado == 'aceptada') {
        // Banner de modalidad al solicitante (solo la primera vez)
        if (updated.modalidad != null && !_bannerModalidadMostrado) {
          _bannerModalidadMostrado = true;
          _mostrarBannerModalidad(updated.modalidad!, updated.nombreEntregador ?? 'Tu colega');
        }

        // GPS propio inmediato (para calcular distancia al entregador)
        _obtenerPosicion().then((pos) {
          if (pos != null && mounted) setState(() => _posicion = pos);
        });
        // Timer GPS propio cada 30 s (solo arranca una vez)
        _timerGpsAceptada ??= Timer.periodic(const Duration(seconds: 30), (_) async {
          final pos = await _obtenerPosicion();
          if (pos != null && mounted) setState(() => _posicion = pos);
        });
        // Polling posición del entregador cada 5 s (como ayuda_tracking_screen)
        _pollingEntregador ??= Timer.periodic(const Duration(seconds: 5), (_) async {
          if (!mounted || _miSolicitud == null) return;
          try {
            final row = await _db
                .from('solicitudes_material')
                .select()
                .eq('id', _miSolicitud!.id)
                .single();
            if (!mounted) return;
            final fresh = SolicitudMaterial.fromMap(row as Map<String, dynamic>);
            if (fresh.estado != 'aceptada') {
              _pollingEntregador?.cancel();
              _pollingEntregador = null;
              return;
            }
            setState(() => _miSolicitud = fresh);
            _actualizarMarkers();
          } catch (_) {}
        });
        _actualizarMarkers();
      }
      if (updated.estado == 'en_guia') {
        _timerGpsAceptada?.cancel();
        _timerGpsAceptada = null;
        _pollingEntregador?.cancel();
        _pollingEntregador = null;
        // Guard: el stream puede dispararse varias veces con estado 'en_guia'
        // (ej. cuando _firmarEntregador actualiza guia_id). Solo mostrar una vez.
        if (!_llegadaMostrada) {
          _llegadaMostrada = true;
          _mostrarLlegadaEntregador(updated);
        }
      }
      if (updated.estado == 'completada') {
        _timerGpsAceptada?.cancel();
        _timerGpsAceptada = null;
        _pollingEntregador?.cancel();
        _pollingEntregador = null;
        _subPropia?.cancel();
        _bannerModalidadMostrado = false;
        _llegadaMostrada         = false;
        unawaited(FcmService.instance.detenerPinMonitor());
        setState(() => _miSolicitud = null);
        _cargarGuiasMes();
      }
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
    try {
      await _soundChannel.invokeMethod<void>('stopAlerta');
    } catch (_) {}
    try {
      final flnp = FlutterLocalNotificationsPlugin();
      const initSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await flnp.initialize(initSettings);
      await flnp.cancel(42);
    } catch (_) {}
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
              'Solicitud de ${sol.tipoMaterial} fue atendida por otro técnico',
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
      debugPrint('🟢 [SolicitudMat] stream destinatarios → ${destRows.length} filas');
      if (!mounted) return;

      // Solo las filas con estado 'pendiente' dan acceso a la solicitud
      final pendientesIds = destRows
          .where((r) => r['estado'] == 'pendiente')
          .map((r) => r['solicitud_id'] as String)
          .toList();

      if (pendientesIds.isEmpty) {
        if (_cercanas.isNotEmpty && _streamInicializado) {
          ScaffoldMessenger.of(context).clearSnackBars();
          _cancelarNotificacionMaterial();
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

      final filtradas = (solicRows as List)
          .map((r) => SolicitudMaterial.fromMap(r as Map<String, dynamic>))
          .where((s) => s.rutSolicitante != _rut)
          .toList();

      debugPrint('🟢 [SolicitudMat] solicitudes visibles (rol + 5km validados): ${filtradas.length}');

      // Notificar por cada solicitud que no hayamos alertado antes
      for (final sol in filtradas) {
        debugPrint('🟡 [SolicitudMat] evaluando sol id=${sol.id} notificada=${_notificadas.contains(sol.id)}');
        if (!_notificadas.contains(sol.id)) {
          _notificadas.add(sol.id);
          final esReciente = DateTime.now().difference(sol.createdAt).inSeconds < 60;
          debugPrint('🟡 [SolicitudMat] NUEVA solicitud esReciente=$esReciente inicializado=$_streamInicializado');
          if (esReciente) _tocarAlertaUnica();
          _mostrarBannerSolicitud(sol);
          break; // Una alerta por ciclo
        }
      }

      // Detectar solicitudes que desaparecieron (aceptadas por otro o canceladas)
      final nuevosIds = filtradas.map((s) => s.id).toSet();
      for (final sol in _cercanas) {
        if (!nuevosIds.contains(sol.id) && _notificadas.contains(sol.id)) {
          _cancelarNotificacionMaterial();
          if (!_aceptadasPorMi.contains(sol.id)) {
            ScaffoldMessenger.of(context).clearSnackBars();
            _mostrarAtendida(sol);
          }
        }
      }

      if (filtradas.isEmpty) {
        ScaffoldMessenger.of(context).clearSnackBars();
        _cancelarNotificacionMaterial();
      }

      _streamInicializado = true;
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
    if (_materialSeleccionado == null || _rut == null) return;

    // GPS fresco antes de enviar
    _posicion = await _obtenerPosicion() ?? _posicion;
    debugPrint('🔵 [SolicitudMat] enviando solicitud: ${_materialSeleccionado!.nombre} ×$_cantidad pos=${_posicion?.latitude},${_posicion?.longitude}');
    setState(() => _enviando = true);
    try {
      final row = await _db.from('solicitudes_material').insert({
        'rut_solicitante':       _rut,
        'nombre_solicitante':    _nombre,
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
      setState(() {
        _miSolicitud = sol;
        _enviando    = false;
        _adicionales.clear();
      });
      _suscribirSolicitudPropia();
      if (_rut != null) unawaited(FcmService.instance.initPinMonitor(_rut!, sol.id));

      // Notificar técnicos cercanos con stock (background) — ANTES de operaciones de mapa
      debugPrint('🔵 [SolicitudMat] lanzando notificarDestinatarios en background...');
      _service.notificarDestinatarios(
        solicitudId:       sol.id,
        tipoMaterial:      sol.tipoMaterial,
        latSolicitante:    sol.latSolicitante,
        lngSolicitante:    sol.lngSolicitante,
        rutSolicitante:    _rut!,
        nombreSolicitante: _nombre ?? '',
      );

      // Alerta de stock al bodeguero si material seriado y supera umbrales
      if (sol.esSeriado) {
        unawaited(_service.verificarAlertaStock(
          solicitudId:       sol.id,
          rutSolicitante:    _rut!,
          nombreSolicitante: _nombre ?? '',
          tipoMaterial:      sol.tipoMaterial,
        ));
      }

      // Alerta de 10 minutos si nadie responde
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
      setState(() => _enviando = false);
      _snack('Error al enviar: $e');
    }
  }

  Future<void> _mostrarAlertaSinRespuesta(SolicitudMaterial sol) async {
    if (!mounted || _miSolicitud?.estado != 'pendiente') return;

    final pendientes =
        await _service.destinatariosPendientes(sol.id);
    if (!mounted) return;

    if (pendientes.isEmpty) {
      _snack('Nadie tiene stock cercano — sin respuesta en 10 min');
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
    if (_rut == null) return;

    // Pedir al entregador cómo va a entregar antes de aceptar
    final modalidad = await _elegirModalidadEntrega(sol);
    if (modalidad == null) return; // canceló el modal

    try {
      _posicion = await _obtenerPosicion() ?? _posicion;

      // Resolver id_material desde el stock logístico del entregador (B).
      // Solo aplica a no seriados; seriados resuelven la serie en la guía de entrega.
      int? idMaterial;
      if (!sol.esSeriado) {
        idMaterial = await _service.resolverIdMaterial(
          rutEntregador: _rut!,
          tipoMaterial:  sol.tipoMaterial,
          esSeriado:     false,
          cantidad:      sol.cantidad,
        );
        debugPrint('🔵 [Aceptar] id_material resuelto: $idMaterial para ${sol.tipoMaterial}');
      }

      await _service.aceptar(
        solicitudId:     sol.id,
        rutAceptador:    _rut!,
        nombreAceptador: _nombre ?? '',
        lat:             _posicion?.latitude,
        lng:             _posicion?.longitude,
        modalidad:       modalidad,
        idMaterial:      idMaterial,
      );

      final updated = SolicitudMaterial.fromMap(
        (await _db
                .from('solicitudes_material')
                .select()
                .eq('id', sol.id)
                .single())
            as Map<String, dynamic>,
      );
      if (mounted) {
        _aceptadasPorMi.add(sol.id);
        _cancelarNotificacionMaterial();
        ScaffoldMessenger.of(context).clearSnackBars();
        Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => EntregaEnCaminoScreen(
              solicitud:        updated,
              rutPropio:        _rut!,
              nombrePropio:     _nombre ?? '',
              posicionInicial:  _posicion,
            ),
          ),
        );
      }
    } catch (e) {
      _snack('Error al aceptar: $e');
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
    if (_miSolicitud == null) return;
    _timer10min?.cancel();
    if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
    final sol = _miSolicitud!;
    await _db
        .from('solicitudes_material')
        .update({'estado': 'cancelada'}).eq('id', sol.id);
    // Notificar a TODOS los destinatarios (pendientes o aceptados) para que
    // eliminen el banner de solicitud de sus bandejas de notificaciones.
    unawaited(_service.notificarCancelacion(
      solicitudId:  sol.id,
      tipoMaterial: sol.tipoMaterial,
    ));
    _subPropia?.cancel();
    unawaited(FcmService.instance.detenerPinMonitor());
    setState(() => _miSolicitud = null);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Si hay solicitudes cercanas pendientes de aceptar, mostrar siempre
    // la vista de lista para que sean visibles aunque el usuario tenga
    // su propia solicitud activa en mapa.
    if (_cercanas.isEmpty) {
      if (_miSolicitud != null && _miSolicitud!.estado == 'pendiente') {
        return _buildMapaView();
      }
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
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
                        const Icon(Icons.directions_walk,
                            color: Colors.white, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          'En camino · ${sol.nombreEntregador ?? "Técnico"}',
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

                    // Estado de espera — la guía se firma en el dispositivo del entregador
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
                        const Icon(Icons.phone_android,
                            color: _green, size: 16),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Cuando llegue tu colega, firma la guía en su dispositivo',
                            style: TextStyle(
                                color: _green,
                                fontSize: 12,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ]),
                    ),
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

          // ── Banner superior ───────────────────────────────────
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Row(
                    children: [
                      // Botón volver
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
                      // Chip de estado
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _orange.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                                color: _orange.withValues(alpha: 0.3),
                                blurRadius: 8)
                          ],
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const SizedBox(
                            width: 8,
                            height: 8,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text('Buscando…',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12)),
                        ]),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // Barra de búsqueda animada
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 13),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 10,
                            spreadRadius: 2)
                      ],
                    ),
                    child: Row(
                      children: [
                        // Icono en movimiento
                        const Icon(Icons.directions_walk,
                                color: Color(0xFF00D9FF), size: 22)
                            .animate(onPlay: (c) => c.repeat())
                            .shimmer(
                                duration: 1400.ms,
                                color: Colors.white.withValues(alpha: 0.7))
                            .then()
                            .shake(hz: 2, duration: 600.ms),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Revisando stock de materiales\nen móviles cercanos…',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                                height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
            onPressed: () => _aceptarSolicitud(sol),
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
      ]),
    );
  }

  Widget _buildGuiaCard(Map<String, dynamic> guia) {
    final detalle      = guia['detalle_material'] as String? ?? 'Sin detalle';
    final fecha        = guia['fecha'] as String? ?? '';
    final horaRaw      = guia['hora'] as String? ?? '';
    final hora         = horaRaw.length >= 5 ? horaRaw.substring(0, 5) : horaRaw;
    final firmada      = (guia['estado'] as String?) == 'firmada';
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
            if (firmada)
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
    final firmada = (guiaMeta['estado'] as String?) == 'firmada';
    if (id == null) return;

    if (!firmada) {
      _snack('La guía aún no está firmada por ambas partes.');
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
      final bytes = await _buildPdfGuia(row as Map<String, dynamic>);
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

  /// Construye el PDF a partir de la fila completa de `solicitudes_bodega`.
  Future<Uint8List> _buildPdfGuia(Map<String, dynamic> g) async {
    final firmaEb64 = g['firma_entregador']  as String?;
    final firmaSb64 = g['firma_solicitante'] as String?;
    final fecha     = g['fecha'] as String? ?? '';
    final horaRaw   = g['hora']  as String? ?? '';
    final hora      = horaRaw.length >= 5 ? horaRaw.substring(0, 5) : horaRaw;

    final imgE = (firmaEb64 != null && firmaEb64.isNotEmpty)
        ? pw.MemoryImage(base64Decode(firmaEb64))
        : null;
    final imgS = (firmaSb64 != null && firmaSb64.isNotEmpty)
        ? pw.MemoryImage(base64Decode(firmaSb64))
        : null;

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Text('GUÍA DE ENTREGA DE MATERIAL',
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text('CREABOX — Operaciones de fibra óptica',
                  style: pw.TextStyle(fontSize: 10, color: PdfColors.blueGrey600)),
            ),
            pw.SizedBox(height: 14),
            pw.Divider(),
            pw.SizedBox(height: 10),

            pw.Row(children: [
              pw.Text('Fecha: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
              pw.Text(fecha, style: const pw.TextStyle(fontSize: 10)),
              pw.SizedBox(width: 20),
              pw.Text('Hora: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
              pw.Text(hora, style: const pw.TextStyle(fontSize: 10)),
            ]),
            pw.SizedBox(height: 4),
            pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Lugar: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
              pw.Text(g['lugar'] as String? ?? 'Sin GPS', style: const pw.TextStyle(fontSize: 10)),
            ]),
            pw.SizedBox(height: 14),

            pw.Text('PARTES',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.blueGrey700)),
            pw.Divider(height: 8, thickness: 0.5),
            _pdfFila('Solicitante (recibe)', g['nombre_solicitante'] as String? ?? ''),
            _pdfFila('RUT solicitante',      g['rut_solicitante']   as String? ?? ''),
            _pdfFila('Entregador',           g['nombre_entregador'] as String? ?? ''),
            _pdfFila('RUT entregador',       g['rut_entregador']    as String? ?? ''),
            pw.SizedBox(height: 14),

            pw.Text('MATERIAL',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.blueGrey700)),
            pw.Divider(height: 8, thickness: 0.5),
            _pdfFila('Descripción', g['detalle_material'] as String? ?? ''),
            if ((g['series'] as List?)?.isNotEmpty == true)
              _pdfFila('Series', (g['series'] as List).join(', ')),
            pw.SizedBox(height: 20),

            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                    pw.Text('Firma del entregador',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.SizedBox(height: 2),
                    pw.Text(g['nombre_entregador'] as String? ?? '',
                        style: const pw.TextStyle(fontSize: 9)),
                    pw.SizedBox(height: 6),
                    pw.Container(
                      width: 180, height: 80,
                      decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.blueGrey300)),
                      child: imgE != null
                          ? pw.Image(imgE, fit: pw.BoxFit.contain)
                          : pw.SizedBox(),
                    ),
                  ]),
                ),
                pw.SizedBox(width: 20),
                pw.Expanded(
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                    pw.Text('Firma del solicitante',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.SizedBox(height: 2),
                    pw.Text(g['nombre_solicitante'] as String? ?? '',
                        style: const pw.TextStyle(fontSize: 9)),
                    pw.SizedBox(height: 6),
                    pw.Container(
                      width: 180, height: 80,
                      decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.blueGrey300)),
                      child: imgS != null
                          ? pw.Image(imgS, fit: pw.BoxFit.contain)
                          : pw.SizedBox(),
                    ),
                  ]),
                ),
              ],
            ),

            pw.Spacer(),
            pw.Divider(),
            pw.Text('CREABOX — Documento generado automáticamente',
                style: pw.TextStyle(fontSize: 8, color: PdfColors.blueGrey400)),
          ],
        ),
      ),
    );
    return doc.save();
  }

  pw.Widget _pdfFila(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(
            width: 130,
            child: pw.Text('$label:',
                style: pw.TextStyle(fontSize: 9, color: PdfColors.blueGrey600)),
          ),
          pw.Expanded(
            child: pw.Text(value,
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          ),
        ]),
      );

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

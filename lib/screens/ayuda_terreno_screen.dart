import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:agente_desconexiones/constants/map_styles.dart';
import 'package:agente_desconexiones/models/solicitud_ayuda.dart';
import 'package:agente_desconexiones/services/ayuda_service.dart';
import 'package:agente_desconexiones/services/fcm_service.dart';

// ═════════════════════════════════════════════════════════════
// Pantalla principal de Ayuda en Terreno
// ═════════════════════════════════════════════════════════════

class AyudaTerrenoScreen extends StatefulWidget {
  const AyudaTerrenoScreen({super.key});

  @override
  State<AyudaTerrenoScreen> createState() => _AyudaTerrenoScreenState();
}

class _AyudaTerrenoScreenState extends State<AyudaTerrenoScreen>
    with WidgetsBindingObserver {
  final _ayudaService = AyudaService();

  SolicitudAyuda? _solicitudActiva;
  bool _enviando = false;
  bool _restaurando = true;
  String? _rutUsuario;
  String? _nombreUsuario;

  // Mapa y tracking
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  Timer? _timerElapsed;
  Timer? _timerGps; // refresca GPS del supervisor cada 10s
  int _segundosEspera = 0;
  double? _distanciaActual;
  int? _etaMinutos;

  // Llegada del supervisor: true cuando el técnico presiona "Supervisor llegó"
  // (detección por proximidad 150m desactivada durante pruebas)
  bool _supervisorLlego = false;

  // Iconos personalizados para el mapa
  BitmapDescriptor? _iconoTecnico;
  BitmapDescriptor? _iconoSupervisor;

  // Diagnóstico de mapa
  String? _mapaError;

  // ─────────────────────────────────────────────────────────────
  // Ciclo de vida
  // ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _crearIconosMarcadores();
    _iniciar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timerElapsed?.cancel();
    _timerGps?.cancel();
    _mapController?.dispose();
    _ayudaService.cancelarSuscripcionTecnico();
    _ayudaService.removeListener(_onSolicitudActualizada);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _solicitudActiva != null) {
      _verificarEstadoTicket(_solicitudActiva!.ticketId);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Iconos canvas para el mapa (estilo agente)
  // ─────────────────────────────────────────────────────────────

  Future<void> _crearIconosMarcadores() async {
    try {
      _iconoTecnico = await _buildCircleMarker(
        color: const Color(0xFF2196F3),
        tamano: 80,
      );
      _iconoSupervisor = await _buildCircleMarker(
        color: const Color(0xFF4CAF50),
        tamano: 90,
      );
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<BitmapDescriptor> _buildCircleMarker({
    required Color color,
    required double tamano,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(tamano, tamano);

    // Sombra
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(
        Offset(size.width / 2, size.height / 2 + 2),
        size.width / 2 - 4,
        shadowPaint);

    // Círculo con gradiente
    final gradient = ui.Gradient.radial(
      Offset(size.width / 2, size.height / 2),
      size.width / 2 - 6,
      [color, color.withOpacity(0.8)],
    );
    canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        size.width / 2 - 6,
        Paint()
          ..shader = gradient
          ..style = PaintingStyle.fill);

    // Borde blanco
    canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        size.width / 2 - 6,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4);

    // Punto interior blanco
    canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        tamano * 0.12,
        Paint()..color = Colors.white);

    final picture = recorder.endRecording();
    final image =
        await picture.toImage(size.width.toInt(), size.height.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  // ─────────────────────────────────────────────────────────────
  // Inicialización y restauración de ticket
  // ─────────────────────────────────────────────────────────────

  Future<void> _iniciar() async {
    final prefs = await SharedPreferences.getInstance();
    _rutUsuario =
        prefs.getString('rut_tecnico') ?? prefs.getString('user_rut') ?? '';
    _nombreUsuario = prefs.getString('user_nombre') ?? '';

    final ticketGuardado = prefs.getString('ayuda_ticket_activo');
    if (ticketGuardado != null && ticketGuardado.isNotEmpty) {
      await _restaurarTicket(ticketGuardado);
    } else {
      if (mounted) setState(() => _restaurando = false);
    }
  }

  Future<void> _restaurarTicket(String ticketId) async {
    final solicitud = await _ayudaService.obtenerSolicitudPorTicket(ticketId);
    if (!mounted) return;

    if (solicitud == null) {
      await _ayudaService.limpiarTicketPersistido();
      setState(() => _restaurando = false);
      return;
    }

    // Solicitud cerrada (rechazada/cancelada) — informar y limpiar
    if (solicitud.estaResuelta) {
      await _ayudaService.limpiarTicketPersistido();
      setState(() {
        _solicitudActiva = solicitud;
        _restaurando = false;
      });
      Future.delayed(const Duration(milliseconds: 500),
          () => mounted ? _mostrarDialogoRespuesta() : null);
      return;
    }

    setState(() {
      _solicitudActiva = solicitud;
      _restaurando = false;
    });
    _suscribirARespuesta(solicitud.ticketId);
    _segundosEspera =
        DateTime.now().difference(solicitud.fechaCreacion).inSeconds;
    _iniciarTimerEspera();
    _iniciarTimerGps(solicitud.ticketId);
    _actualizarMarkers(solicitud);
  }

  Future<void> _verificarEstadoTicket(String ticketId) async {
    final solicitud = await _ayudaService.obtenerSolicitudPorTicket(ticketId);
    if (solicitud == null || !mounted) return;

    final estadoAnterior = _solicitudActiva?.estado;

    // Solicitud rechazada o cancelada → cerrar tracking
    if (solicitud.estaResuelta) {
      _timerGps?.cancel();
      setState(() => _solicitudActiva = solicitud);
      _mostrarDialogoRespuesta();
      await _ayudaService.limpiarTicketPersistido();
      return;
    }

    // Supervisor acaba de aceptar → mostrar banner pero mantener tracking activo
    if (solicitud.supervisorEnCamino &&
        estadoAnterior == EstadoSolicitud.pendiente) {
      setState(() => _solicitudActiva = solicitud);
      _actualizarMarkers(solicitud);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: const Color(0xFF34C759),
          duration: const Duration(seconds: 3),
          content: Row(children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${solicitud.supervisorNombre ?? "Supervisor"} está en camino 🚗',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ]),
        ));
      }
      return;
    }

    // Actualizar GPS del supervisor en el mapa
    if (solicitud.estaActiva) {
      setState(() => _solicitudActiva = solicitud);
      _actualizarMarkers(solicitud);
    }
  }

  // Polling cada 30s para refrescar GPS del supervisor en Supabase
  void _iniciarTimerGps(String ticketId) {
    _timerGps?.cancel();
    _timerGps = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!mounted) {
        _timerGps?.cancel();
        return;
      }
      await _verificarEstadoTicket(ticketId);
    });
  }

  // ─────────────────────────────────────────────────────────────
  // Flujo de solicitud
  // ─────────────────────────────────────────────────────────────

  Future<void> _solicitarAyuda(TipoAyuda tipo) async {
    final confirmar = await _mostrarDialogoConfirmacion(tipo);
    if (!confirmar || !mounted) return;

    setState(() => _enviando = true);

    // Mostrar diálogo de búsqueda
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: false, // Usar navegador local para poder cerrar de forma segura
      builder: (_) => const _BuscandoSupervisorDialog(),
    );

    Map<String, dynamic> resultado;
    try {
      resultado = await _ayudaService.solicitarAyuda(
        tipo: tipo,
        rutTecnico: _rutUsuario ?? '',
        nombreTecnico: _nombreUsuario ?? '',
      );
    } catch (e) {
      resultado = {'error': 'Error inesperado al enviar solicitud: $e'};
    }

    // Cerrar diálogo de búsqueda de forma segura
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
    if (mounted) setState(() => _enviando = false);

    if (resultado['error'] != null) {
      _mostrarSnackError(resultado['error'] as String);
      return;
    }

    final solicitud = resultado['solicitud'] as SolicitudAyuda;
    await _ayudaService.persistirTicketActivo(solicitud.ticketId);

    if (mounted) {
      setState(() => _solicitudActiva = solicitud);
      _suscribirARespuesta(solicitud.ticketId);
      _iniciarTimerEspera();
      _iniciarTimerGps(solicitud.ticketId);
      _actualizarMarkers(solicitud);
    }
  }

  void _suscribirARespuesta(String ticketId) {
    _ayudaService.suscribirRespuestaTecnico(
      ticketId: ticketId,
      onSonido: () {
        if (mounted) {
          HapticFeedback.heavyImpact();
          unawaited(FcmService.playAyuda());
          _mostrarDialogoRespuesta();
        }
      },
    );
    _ayudaService.addListener(_onSolicitudActualizada);
  }

  void _onSolicitudActualizada() {
    final nueva = _ayudaService.solicitudActual;
    if (nueva != null && mounted) {
      setState(() {
        _solicitudActiva = nueva;
      });
      _actualizarMarkers(nueva);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Timer, mapa y ruta
  // ─────────────────────────────────────────────────────────────

  void _iniciarTimerEspera() {
    _timerElapsed?.cancel();
    _timerElapsed = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _segundosEspera++);
    });
  }

  void _actualizarMarkers(SolicitudAyuda s) {
    _markers.clear();

    // Marcador del técnico
    _markers.add(Marker(
      markerId: const MarkerId('tecnico'),
      position: LatLng(s.latTecnico, s.lngTecnico),
      icon: _iconoTecnico ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      anchor: const Offset(0.5, 0.5),
      infoWindow: InfoWindow(
          title: '📍 Tu ubicación', snippet: s.tecnicoNombre ?? ''),
    ));

    // Marcador del supervisor si tiene GPS
    if (s.latSupervisor != null && s.lngSupervisor != null) {
      _markers.add(Marker(
        markerId: const MarkerId('supervisor'),
        position: LatLng(s.latSupervisor!, s.lngSupervisor!),
        icon: _iconoSupervisor ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        anchor: const Offset(0.5, 0.5),
        infoWindow: InfoWindow(
          title: '✅ ${s.supervisorNombre ?? "Supervisor"}',
          snippet: 'En camino hacia ti',
        ),
      ));

      // Mostrar spinner hasta tener datos reales de la API
      // (no usar Haversine para evitar mostrar el "doble" estimado)
      final dist = _calcDistanciaKm(
          s.latTecnico, s.lngTecnico, s.latSupervisor!, s.lngSupervisor!);
      setState(() {
        _distanciaActual = dist; // distancia lineal como referencia inicial
        _etaMinutos = null;      // null = mostrar spinner hasta que API responda
      });

      // Obtener ruta real desde API Directions (sobrescribe _distanciaActual y _etaMinutos)
      _obtenerRuta(
        LatLng(s.latTecnico, s.lngTecnico),
        LatLng(s.latSupervisor!, s.lngSupervisor!),
      );

      // Ajustar cámara para mostrar ambos
      _ajustarCamaraAmbos(s);

      // Detección automática por proximidad DESACTIVADA durante pruebas.
      // El técnico usa el botón "Supervisor llegó" para cerrar manualmente.
    } else {
      _distanciaActual = null;
      _etaMinutos = null;
      _polylines.clear();
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(s.latTecnico, s.lngTecnico), 14),
      );
    }

    if (mounted) setState(() {});
  }

  Future<void> _obtenerRuta(LatLng origen, LatLng destino) async {
    _polylines.removeWhere((p) => p.polylineId == const PolylineId('ruta'));

    try {
      const apiKey = 'AIzaSyBY14w076XgTfwyOPjLnE-ov1I1upnp5Ak';
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json?'
        'origin=${origen.latitude},${origen.longitude}&'
        'destination=${destino.latitude},${destino.longitude}&'
        'key=$apiKey&language=es&units=metric',
      );
      final response =
          await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'OK' &&
            (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];
          final points = _decodePolyline(
              route['overview_polyline']['points'] as String);
          final leg = (route['legs'] as List)[0];
          final durSec = leg['duration']['value'] as int;
          final distM = leg['distance']['value'] as int;
          if (mounted) {
            setState(() {
              _etaMinutos = (durSec / 60).round();
              _distanciaActual = distM / 1000;
            });
          }
          if (points.isNotEmpty && mounted) {
            _polylines.add(Polyline(
              polylineId: const PolylineId('ruta'),
              points: points,
              color: const Color(0xFF4CAF50),
              width: 6,
              patterns: [PatternItem.dash(50), PatternItem.gap(20)],
              geodesic: true,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
              jointType: JointType.round,
            ));
            if (mounted) setState(() {});
            return;
          }
        }
      }
    } catch (_) {}

    // Fallback: línea recta
    if (mounted) {
      _polylines.add(Polyline(
        polylineId: const PolylineId('ruta'),
        points: [origen, destino],
        color: const Color(0xFF4CAF50),
        width: 5,
        patterns: [PatternItem.dash(40), PatternItem.gap(15)],
        geodesic: true,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ));
      setState(() {});
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    int index = 0;
    int lat = 0, lng = 0;
    while (index < encoded.length) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  void _ajustarCamaraAmbos(SolicitudAyuda s) {
    if (s.latSupervisor == null) return;
    final sw = LatLng(
      math.min(s.latTecnico, s.latSupervisor!),
      math.min(s.lngTecnico, s.lngSupervisor!),
    );
    final ne = LatLng(
      math.max(s.latTecnico, s.latSupervisor!),
      math.max(s.lngTecnico, s.lngSupervisor!),
    );
    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: sw, northeast: ne),
        100,
      ),
    );
  }

  double _calcDistanciaKm(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  String _formatMinutos(int minutos) {
    if (minutos < 60) return '${minutos} min';
    final h = minutos ~/ 60;
    final m = minutos % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}min';
  }

  String _tiempoEsperaTexto() {
    if (_segundosEspera < 60) return '${_segundosEspera}s';
    final minutos = _segundosEspera ~/ 60;
    final segundos = _segundosEspera % 60;
    if (minutos < 60) return '${minutos}m ${segundos}s';
    return '${minutos ~/ 60}h ${minutos % 60}m';
  }

  // ─────────────────────────────────────────────────────────────
  // Diálogos
  // ─────────────────────────────────────────────────────────────

  Future<void> _mostrarDialogoRespuesta() async {
    final s = _solicitudActiva;
    if (s == null) return;

    const verde = Color(0xFF34C759);
    const rojo = Color(0xFFFF3B30);
    const naranja = Color(0xFFFF9500);
    const cyan = Color(0xFF00E5FF);

    final (color, icono, titulo, subtitulo) = switch (s.estado) {
      EstadoSolicitud.aceptada => (
          verde,
          Icons.check_circle,
          '¡Ayuda en camino!',
          s.supervisorNombre != null
              ? '${s.supervisorNombre} aceptó tu solicitud.'
              : 'Un supervisor aceptó tu solicitud.',
        ),
      EstadoSolicitud.rechazada => (
          rojo,
          Icons.cancel,
          'Solicitud rechazada',
          s.respuestaMensaje ?? 'El supervisor no puede atenderte ahora.',
        ),
      EstadoSolicitud.aceptadaConTiempo => (
          naranja,
          Icons.schedule,
          'Aceptada con demora',
          s.tiempoExtraMinutos != null
              ? '${s.supervisorNombre ?? "El supervisor"} llegará en ~${_formatMinutos(s.tiempoExtraMinutos!)} adicionales.'
              : '${s.supervisorNombre ?? "El supervisor"} aceptó con demora.',
        ),
      _ => (
          cyan,
          Icons.info,
          'Actualización recibida',
          'Estado de tu solicitud actualizado.',
        ),
    };

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icono, color: color, size: 48),
              ),
              const SizedBox(height: 20),
              Text(titulo,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: color,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text(subtitulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.black54, fontSize: 14, height: 1.4)),
              if (s.respuestaMensaje != null &&
                  s.estado != EstadoSolicitud.rechazada) ...[
                const SizedBox(height: 10),
                Text('"${s.respuestaMensaje}"',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.black38,
                        fontSize: 12,
                        fontStyle: FontStyle.italic)),
              ],
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                // Solo cerrar el tracking si la solicitud fue rechazada/cancelada.
                // Si fue aceptada, el técnico sigue viendo el mapa con el supervisor.
                if (s.estaResuelta) {
                  _cerrarSolicitudResuelta();
                }
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: Text(
                s.supervisorEnCamino ? 'Ver en mapa' : 'Entendido',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarDialogoSupervisorLlego() async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Column(
          children: [
            Icon(Icons.check_circle, color: Color(0xFF34C759), size: 56),
            SizedBox(height: 8),
            Text('¡Supervisor llegó!',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.black87,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          '${_solicitudActiva?.supervisorNombre ?? "El supervisor"} está en tu ubicación.\nYa puedes continuar.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54, height: 1.5),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _cerrarSolicitudResuelta();
              },
              icon: const Icon(Icons.thumb_up),
              label: const Text('Perfecto, gracias',
                  style: TextStyle(fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF34C759),
                foregroundColor: Colors.white,
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

  Future<bool> _mostrarDialogoConfirmacion(TipoAyuda tipo) async {
    return await showDialog<bool>(
          context: context,
            builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A2C3D),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _colorPorTipo(tipo).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_iconoPorTipo(tipo),
                      color: _colorPorTipo(tipo), size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(tipo.displayName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tipo.descripcion,
                    style:
                        const TextStyle(color: Colors.white70, height: 1.4)),
                const SizedBox(height: 16),
                _buildInfoRow(
                  Icons.location_on,
                  const Color(0xFF2196F3),
                  'Se usará tu GPS para encontrar al supervisor más cercano.',
                ),
                const SizedBox(height: 8),
                _buildInfoRow(
                  Icons.lock_clock,
                  const Color(0xFFFF9500),
                  'Podrás cancelar la solicitud en cualquier momento mientras esté activa.',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar',
                    style: TextStyle(color: Colors.white38)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                child: const Text('Enviar Solicitud',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ) ??
        false;
  }

  Widget _buildInfoRow(IconData icono, Color color, String texto) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icono, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texto,
                style: TextStyle(color: color, fontSize: 12, height: 1.3)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmarCancelar() async {
    final s = _solicitudActiva;
    final supervisorEnCamino = s != null && s.supervisorEnCamino;
    final nombreSup = s?.supervisorNombre;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancelar solicitud',
            style: TextStyle(color: Colors.black87, fontSize: 16)),
        content: Text(
          supervisorEnCamino
              ? '${nombreSup ?? "El supervisor"} ya fue notificado y puede estar en camino.\n\n'
                  '¿Confirmas que ya no necesitas ayuda? Se avisará al supervisor.'
              : '¿Ya resolviste el problema o no necesitas ayuda?\n'
                  'Esto cerrará la solicitud activa y avisará al supervisor.',
          style: const TextStyle(color: Colors.black54, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('No, esperar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white),
            child: const Text('Sí, cancelar',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmar != true || _solicitudActiva == null) return;

    final ok =
        await _ayudaService.cancelarSolicitud(_solicitudActiva!.ticketId);

    if (ok) {
      await _cerrarSolicitudResuelta();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Solicitud cancelada'),
          backgroundColor: Color(0xFF636366),
          duration: Duration(seconds: 2),
        ));
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Error al cancelar. Intenta de nuevo.'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _cerrarSolicitudResuelta() async {
    _timerGps?.cancel();
    _timerElapsed?.cancel();
    _ayudaService.cancelarSuscripcionTecnico();
    _ayudaService.removeListener(_onSolicitudActualizada);
    _ayudaService.limpiarSolicitudActual();
    await _ayudaService.limpiarTicketPersistido();
    if (mounted) {
      setState(() {
        _solicitudActiva = null;
        _distanciaActual = null;
        _etaMinutos = null;
        _supervisorLlego = false;
        _segundosEspera = 0;
      });
    }
  }

  void _mostrarSnackError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          const Icon(Icons.location_off, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(msg, style: const TextStyle(fontSize: 13))),
        ],
      ),
      backgroundColor: Colors.red,
      duration: const Duration(seconds: 5),
    ));
  }

  // ─────────────────────────────────────────────────────────────
  // Helpers de color/icono
  // ─────────────────────────────────────────────────────────────

  IconData _iconoPorTipo(TipoAyuda tipo) => switch (tipo) {
        TipoAyuda.zonaRoja => Icons.warning_amber_rounded,
        TipoAyuda.crucePeligroso => Icons.traffic,
        TipoAyuda.ducto => Icons.block,
        TipoAyuda.fusion => Icons.cable,
        TipoAyuda.altura => Icons.height,
      };

  Color _colorPorTipo(TipoAyuda tipo) => switch (tipo) {
        TipoAyuda.zonaRoja => const Color(0xFFFF3B30),
        TipoAyuda.crucePeligroso => const Color(0xFFFF9500),
        TipoAyuda.ducto => const Color(0xFFFFCC02),
        TipoAyuda.fusion => const Color(0xFF00C49A),
        TipoAyuda.altura => const Color(0xFF34C759),
      };

  // ─────────────────────────────────────────────────────────────
  // Build raíz
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hayEspera =
        _solicitudActiva != null && _solicitudActiva!.estaActiva;

    return PopScope(
      // Permite volver al home siempre.
      // El ticket persiste en SharedPreferences; al re-ingresar se restaura.
      // Bloquear nueva solicitud sin cancelar es responsabilidad del menu.
      canPop: true,
      onPopInvoked: (didPop) {
        if (didPop && hayEspera && !_supervisorLlego) {
          // Aviso informativo al salir con solicitud activa
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                '⚠️  Tu solicitud sigue activa. Vuelve a Ayuda en Terreno para cancelarla.'),
            backgroundColor: Color(0xFFFF9500),
            duration: Duration(seconds: 3),
          ));
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1B2A),
        appBar: hayEspera
            ? null
            : AppBar(
                backgroundColor: const Color(0xFF111F2F),
                elevation: 0,
                surfaceTintColor: Colors.transparent,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white70, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
                title: const Row(
                  children: [
                    Icon(Icons.support_agent,
                        color: Color(0xFF34C759), size: 22),
                    SizedBox(width: 10),
                    Text('Ayuda en Terreno',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_restaurando) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF34C759)),
            SizedBox(height: 16),
            Text('Verificando solicitudes activas...',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
      );
    }

    if (_solicitudActiva != null && _solicitudActiva!.estaActiva) {
      return _buildTrackingView();
    }

    return _buildMenuOpciones();
  }

  // ─────────────────────────────────────────────────────────────
  // Menú de selección (tema claro — estilo agente)
  // ─────────────────────────────────────────────────────────────

  Widget _buildMenuOpciones() {
    final opciones = [
      (TipoAyuda.zonaRoja, Icons.warning_amber_rounded),
      (TipoAyuda.crucePeligroso, Icons.traffic),
      (TipoAyuda.ducto, Icons.block),
      (TipoAyuda.fusion, Icons.cable),
      (TipoAyuda.altura, Icons.height),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Aviso informativo
        Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF00E5FF).withOpacity(0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: const Color(0xFF00E5FF).withOpacity(0.2)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline,
                  color: Color(0xFF00E5FF), size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Selecciona el tipo de ayuda que necesitas. Podrás cancelarla en cualquier momento mientras esté activa.',
                  style: TextStyle(
                      color: Color(0xFF00E5FF), fontSize: 13, height: 1.4),
                ),
              ),
            ],
          ),
        ).animate().fadeIn(duration: 300.ms),

        // Tarjetas de opciones
        ...opciones.asMap().entries.map((e) {
          final delay = (e.key * 80).ms;
          final tipo = e.value.$1;
          final icono = e.value.$2;
          final color = _colorPorTipo(tipo);
          return _buildOpcionCard(tipo, icono, color)
              .animate()
              .fadeIn(delay: delay + 100.ms)
              .slideX(begin: -0.08, delay: delay + 100.ms);
        }),
      ],
    );
  }

  Widget _buildOpcionCard(TipoAyuda tipo, IconData icono, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: _enviando ? null : () => _solicitarAyuda(tipo),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF111F2F),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icono, color: color, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tipo.displayName,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                      const SizedBox(height: 4),
                      Text(tipo.descripcion,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white54)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: color.withOpacity(0.6), size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Vista de tracking (mapa full-screen estilo Uber)
  // ─────────────────────────────────────────────────────────────

  Widget _buildTrackingView() {
    final s = _solicitudActiva!;
    final esPendiente = s.estado == EstadoSolicitud.pendiente;
    final fueAceptada = s.estado == EstadoSolicitud.aceptada ||
        s.estado == EstadoSolicitud.aceptadaConTiempo;
    final tieneSupGps = s.latSupervisor != null && s.lngSupervisor != null;

    return Stack(
      children: [
        // ── Mapa full-screen con tema Uber ────────────────────
        Positioned.fill(
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(s.latTecnico, s.lngTecnico),
              zoom: 14,
            ),
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            tiltGesturesEnabled: false,
            mapType: MapType.normal,
            style: MapStyles.estiloMapaUberDark,
            onMapCreated: (ctrl) {
              _mapController = ctrl;
              ctrl.setMapStyle(MapStyles.estiloMapaUberDark).catchError((e) {
                if (mounted) setState(() => _mapaError = e.toString());
              });
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted) _actualizarMarkers(s);
              });
            },
          ),
        ),

        // ── Error de mapa (diagnóstico) ────────────────────────
        if (_mapaError != null)
          Positioned(
            top: 80,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade900.withOpacity(0.92),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '⚠️ Map: $_mapaError',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),

        // ── Top bar: botón atrás + chip de estado ─────────────
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                child: Row(
                  children: [
                    // Botón volver (circular blanco)
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
                                color: Colors.black.withOpacity(0.18),
                                blurRadius: 8,
                                spreadRadius: 1)
                          ],
                        ),
                        child: const Icon(Icons.arrow_back,
                            color: Colors.black87, size: 20),
                      ),
                    ),
                    const Spacer(),
                    // Chip de estado
                    _buildChipEstado(esPendiente, fueAceptada, s.estado),
                  ],
                ),
              ),

              // ── Barra de búsqueda (info del supervisor) ───────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          spreadRadius: 2)
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                            color: Colors.black, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          tieneSupGps && s.supervisorNombre != null
                              ? 'Supervisor: ${s.supervisorNombre}'
                              : esPendiente
                                  ? 'Buscando supervisor cercano...'
                                  : 'Supervisor asignado, obteniendo ubicación...',
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: Colors.black87),
                        ),
                      ),
                      if (tieneSupGps)
                        const Icon(Icons.check_circle,
                            color: Color(0xFF34C759), size: 22),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Re-centrar ───────────────────────────────────────
        Positioned(
          right: 14,
          bottom: 260,
          child: GestureDetector(
            onTap: () => _actualizarMarkers(s),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 8,
                      spreadRadius: 1)
                ],
              ),
              child:
                  const Icon(Icons.my_location, color: Colors.black54, size: 20),
            ),
          ),
        ),

        // ── Tarjeta inferior ─────────────────────────────────
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildSupervisorCard(s, esPendiente).animate().slideY(
              begin: 0.15, duration: 400.ms, curve: Curves.easeOut),
        ),
      ],
    );
  }

  Widget _buildChipEstado(
      bool esPendiente, bool fueAceptada, EstadoSolicitud estado) {
    final (bg, icono, label) = esPendiente
        ? (
            const Color(0xFFFF9500),
            Icons.hourglass_top,
            'Esperando',
          )
        : fueAceptada
            ? (
                const Color(0xFF34C759),
                Icons.check_circle,
                _supervisorLlego ? '¡Llegó!' : 'Asignado',
              )
            : (
                const Color(0xFFFF3B30),
                Icons.cancel,
                'Rechazado',
              );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bg.withOpacity(0.9),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              spreadRadius: 1)
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, color: Colors.white, size: 15),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildSupervisorCard(SolicitudAyuda s, bool esPendiente) {
    final colorBadge = _supervisorLlego
        ? const Color(0xFF34C759)
        : esPendiente
            ? const Color(0xFFFF9500)
            : const Color(0xFF34C759);

    final tieneGps = s.latSupervisor != null && s.lngSupervisor != null;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, -5))
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Asa de arrastre
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4)),
            ),

            // Fila: avatar + nombre + tiempo espera
            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: colorBadge.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _supervisorLlego
                        ? Icons.check_circle
                        : esPendiente
                            ? Icons.support_agent
                            : Icons.directions_run,
                    color: colorBadge,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _supervisorLlego
                            ? '¡Supervisor llegó!'
                            : esPendiente
                                ? 'Buscando supervisor…'
                                : '¡Supervisor asignado!',
                        style: TextStyle(
                            color: _supervisorLlego
                                ? const Color(0xFF34C759)
                                : esPendiente
                                    ? Colors.grey.shade500
                                    : const Color(0xFF2196F3),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3),
                      ),
                      const SizedBox(height: 3),
                      // Nombre del supervisor — protagonista visual
                      Text(
                        s.supervisorNombre != null
                            ? s.supervisorNombre!
                            : esPendiente
                                ? 'Localizando…'
                                : 'En camino',
                        style: TextStyle(
                            color: s.supervisorNombre != null
                                ? Colors.black87
                                : Colors.black45,
                            fontSize: s.supervisorNombre != null ? 19 : 16,
                            fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                      if (s.tiempoExtraMinutos != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.schedule,
                                size: 13, color: Colors.orange.shade600),
                            const SizedBox(width: 4),
                            Text('Llegará en ~${_formatMinutos(s.tiempoExtraMinutos!)} extra',
                                style: TextStyle(
                                    color: Colors.orange.shade700,
                                    fontSize: 12)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Tiempo en espera
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Esperando',
                        style: TextStyle(
                            color: Colors.grey.shade400, fontSize: 10)),
                    Text(_tiempoEsperaTexto(),
                        style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),

            // Distancia y ETA
            const SizedBox(height: 16),
            Divider(color: Colors.grey.shade100, height: 1),
            const SizedBox(height: 16),

            if (tieneGps && _distanciaActual != null) ...[
              Row(
                children: [
                  Expanded(
                    child: _buildInfoItem(
                      icon: Icons.near_me,
                      value: '${_distanciaActual!.toStringAsFixed(1)} km',
                      label: 'Distancia',
                      color: colorBadge,
                    ),
                  ),
                  Container(
                      width: 1, height: 44, color: Colors.grey.shade100),
                  Expanded(
                    child: _buildInfoItem(
                      icon: Icons.access_time_filled,
                      value: _etaMinutos != null
                          ? _etaMinutos! < 60
                              ? '$_etaMinutos min'
                              : '${_etaMinutos! ~/ 60}h ${_etaMinutos! % 60}m'
                          : '—',
                      label: 'Tiempo estimado',
                      color: colorBadge,
                    ),
                  ),
                ],
              ),
              // Indicador de actualización cada 30s
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.sync, size: 11, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Text('Actualiza cada 30 seg',
                      style: TextStyle(
                          fontSize: 10, color: Colors.grey.shade400)),
                ],
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: colorBadge),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    esPendiente
                        ? 'Localizando supervisor más cercano…'
                        : 'Obteniendo ubicación del supervisor…',
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 12),
                  ),
                ],
              ),
            ],

            // Cancelar: disponible mientras la solicitud siga activa
            if (s.estaActiva) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _confirmarCancelar,
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Cancelar solicitud'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade200),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
            // Botón "Supervisor llegó" (cuando supervisor aceptó, para cerrar manualmente en pruebas)
            if (!esPendiente && !_supervisorLlego) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() => _supervisorLlego = true);
                    _mostrarDialogoSupervisorLlego();
                  },
                  icon: const Icon(Icons.check_circle, size: 18),
                  label: const Text('Supervisor llegó'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF34C759),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color.withOpacity(0.8), size: 22),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color)),
        const SizedBox(height: 3),
        Text(label,
            style:
                TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      ],
    );
  }

}

// ─────────────────────────────────────────────────────────────
// Diálogo de búsqueda de supervisor (animación GPS)
// ─────────────────────────────────────────────────────────────

class _BuscandoSupervisorDialog extends StatelessWidget {
  const _BuscandoSupervisorDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ícono GPS con anillo animado
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: const Color(0xFF4CAF50).withOpacity(0.3),
                        width: 2),
                  ),
                )
                    .animate(onPlay: (c) => c.repeat())
                    .scale(
                        begin: const Offset(1, 1),
                        end: const Offset(1.5, 1.5),
                        duration: 1500.ms,
                        curve: Curves.easeOut)
                    .then()
                    .fadeOut(duration: 500.ms),
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.my_location,
                      color: Color(0xFF4CAF50), size: 36),
                )
                    .animate(onPlay: (c) => c.repeat())
                    .shimmer(
                        duration: 1200.ms,
                        color: Colors.white.withOpacity(0.6)),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Buscando supervisor\no ITO más cercano',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87),
            ),
            const SizedBox(height: 16),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor:
                    AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

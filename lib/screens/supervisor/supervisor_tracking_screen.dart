import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:agente_desconexiones/constants/map_styles.dart';
import 'package:agente_desconexiones/models/solicitud_ayuda.dart';
import 'package:agente_desconexiones/services/ayuda_service.dart';

/// Pantalla de mapa en tiempo real para el supervisor cuando va hacia el técnico.
/// Muestra su propia posición (en movimiento) y la del técnico (fija).
class SupervisorTrackingScreen extends StatefulWidget {
  final SolicitudAyuda solicitud;
  final String ticketId;

  const SupervisorTrackingScreen({
    super.key,
    required this.solicitud,
    required this.ticketId,
  });

  @override
  State<SupervisorTrackingScreen> createState() =>
      _SupervisorTrackingScreenState();
}

class _SupervisorTrackingScreenState extends State<SupervisorTrackingScreen> {
  final _ayudaService = AyudaService();

  GoogleMapController? _mapController;
  StreamSubscription<Position>? _gpsStream;
  Timer? _rutaTimer;

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  Position? _miPosicion;
  double? _distanciaKm;
  int? _etaMinutos;
  bool _cargandoMapa = true;

  BitmapDescriptor? _iconoSupervisor;
  BitmapDescriptor? _iconoTecnico;

  static const _cyan = Color(0xFF00E5FF);
  static const _bg = Color(0xFF0D1B2A);
  static const _surface = Color(0xFF1A2C3D);

  @override
  void initState() {
    super.initState();
    debugPrint('🗺️ [MapDebug] initState — ticketId=${widget.ticketId}');
    debugPrint('🗺️ [MapDebug] Técnico lat=${widget.solicitud.latTecnico} lng=${widget.solicitud.lngTecnico}');
    _crearIconos();
    _iniciarGpsStream();
  }

  @override
  void dispose() {
    _gpsStream?.cancel();
    _rutaTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  // ── Iconos ──────────────────────────────────────────────────────────────────

  Future<void> _crearIconos() async {
    _iconoSupervisor = await _buildCircle(const Color(0xFF4CAF50), 90);
    _iconoTecnico = await _buildCircle(const Color(0xFF2196F3), 80);
    if (mounted) setState(() {});
  }

  Future<BitmapDescriptor> _buildCircle(Color color, double size) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final shadow = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(Offset(size / 2, size / 2 + 2), size / 2 - 4, shadow);
    final gradient = ui.Gradient.radial(
      Offset(size / 2, size / 2),
      size / 2 - 6,
      [color, color.withOpacity(0.8)],
    );
    canvas.drawCircle(
        Offset(size / 2, size / 2),
        size / 2 - 6,
        Paint()
          ..shader = gradient
          ..style = PaintingStyle.fill);
    canvas.drawCircle(
        Offset(size / 2, size / 2),
        size / 2 - 6,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4);
    canvas.drawCircle(
        Offset(size / 2, size / 2), size * 0.12, Paint()..color = Colors.white);
    final pic = recorder.endRecording();
    final img = await pic.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  // ── GPS Stream en tiempo real ─────────────────────────────────────────────

  void _iniciarGpsStream() {
    debugPrint('🗺️ [MapDebug] Iniciando GPS stream...');
    _testApiKey();

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );

    _gpsStream = Geolocator.getPositionStream(locationSettings: settings)
        .listen(
      (pos) {
        debugPrint('🗺️ [MapDebug] GPS fix → lat=${pos.latitude} lng=${pos.longitude} acc=${pos.accuracy.toStringAsFixed(0)}m');
        final eraPrimero = _miPosicion == null;
        _miPosicion = pos;
        if (mounted) setState(() => _cargandoMapa = false);
        if (eraPrimero) debugPrint('🗺️ [MapDebug] Primer fix GPS — GoogleMap debería renderizarse ahora');
        _ayudaService.actualizarGpsSolicitud(widget.ticketId, pos.latitude, pos.longitude);
        _actualizarMapa(pos);
      },
      onError: (e) => debugPrint('🗺️ [MapDebug] ❌ GPS stream error: $e'),
    );
  }

  Future<void> _testApiKey() async {
    const apiKey = 'AIzaSyBY14w076XgTfwyOPjLnE-ov1I1upnp5Ak';
    debugPrint('🗺️ [MapDebug] Probando API key: ${apiKey.substring(0, 12)}...');

    // Diagnóstico: Geocoding API (solo log, no bloquea el mapa)
    try {
      final urlGeo = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?address=Santiago&key=$apiKey',
      );
      final resGeo = await http.get(urlGeo).timeout(const Duration(seconds: 6));
      final dataGeo = jsonDecode(resGeo.body) as Map<String, dynamic>;
      final statusGeo = dataGeo['status'] as String? ?? 'UNKNOWN';
      debugPrint('🗺️ [MapDebug] Geocoding API status: $statusGeo'
          '${statusGeo != 'OK' ? ' — ${dataGeo['error_message'] ?? ''}' : ''}');
    } catch (e) {
      debugPrint('🗺️ [MapDebug] ❌ Geocoding error: $e');
    }

    // Diagnóstico: Static Maps API
    try {
      final urlStatic = Uri.parse(
        'https://maps.googleapis.com/maps/api/staticmap?center=-33.45,-70.67&zoom=13&size=64x64&key=$apiKey',
      );
      final resStatic = await http.get(urlStatic).timeout(const Duration(seconds: 8));
      debugPrint('🗺️ [MapDebug] Static Maps HTTP ${resStatic.statusCode} — '
          'content-type: ${resStatic.headers['content-type']}');
      if (resStatic.statusCode != 200) {
        final body = resStatic.body.length > 200 ? resStatic.body.substring(0, 200) : resStatic.body;
        debugPrint('🗺️ [MapDebug] Static Maps error body: $body');
      } else {
        debugPrint('🗺️ [MapDebug] ✅ Static Maps OK — clave válida para Maps');
      }
    } catch (e) {
      debugPrint('🗺️ [MapDebug] ❌ Static Maps error: $e');
    }
  }

  // ── Marcadores y ruta ─────────────────────────────────────────────────────

  void _actualizarMapa(Position miPos) {
    debugPrint('🗺️ [MapDebug] _actualizarMapa — controller=${_mapController != null ? "OK" : "NULL"} markers antes=${_markers.length}');
    _markers.clear();

    // Marcador del supervisor (yo)
    _markers.add(Marker(
      markerId: const MarkerId('supervisor'),
      position: LatLng(miPos.latitude, miPos.longitude),
      icon: _iconoSupervisor ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      anchor: const Offset(0.5, 0.5),
      infoWindow: const InfoWindow(title: '📍 Tú', snippet: 'Tu posición'),
    ));

    // Marcador del técnico (destino fijo)
    _markers.add(Marker(
      markerId: const MarkerId('tecnico'),
      position: LatLng(widget.solicitud.latTecnico, widget.solicitud.lngTecnico),
      icon: _iconoTecnico ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      anchor: const Offset(0.5, 0.5),
      infoWindow: InfoWindow(
        title: '🔧 ${widget.solicitud.tecnicoNombre}',
        snippet: 'Necesita ayuda aquí',
      ),
    ));

    debugPrint('🗺️ [MapDebug] Markers agregados: ${_markers.length}');
    if (mounted) setState(() {});

    // Ajustar cámara para mostrar ambos
    _ajustarCamara(miPos);

    // Recalcular ruta cada vez que el supervisor se mueve
    _obtenerRuta(
      LatLng(miPos.latitude, miPos.longitude),
      LatLng(widget.solicitud.latTecnico, widget.solicitud.lngTecnico),
    );
  }

  void _ajustarCamara(Position miPos) {
    if (_mapController == null) {
      debugPrint('🗺️ [MapDebug] ⚠️ _ajustarCamara: controller null, skip');
      return;
    }
    debugPrint('🗺️ [MapDebug] Ajustando cámara...');
    final tecnico = LatLng(
        widget.solicitud.latTecnico, widget.solicitud.lngTecnico);
    final yo = LatLng(miPos.latitude, miPos.longitude);
    final bounds = LatLngBounds(
      southwest: LatLng(
        [yo.latitude, tecnico.latitude].reduce((a, b) => a < b ? a : b) - 0.003,
        [yo.longitude, tecnico.longitude].reduce((a, b) => a < b ? a : b) - 0.003,
      ),
      northeast: LatLng(
        [yo.latitude, tecnico.latitude].reduce((a, b) => a > b ? a : b) + 0.003,
        [yo.longitude, tecnico.longitude].reduce((a, b) => a > b ? a : b) + 0.003,
      ),
    );
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  Future<void> _obtenerRuta(LatLng origen, LatLng destino) async {
    try {
      const apiKey = 'AIzaSyBY14w076XgTfwyOPjLnE-ov1I1upnp5Ak';
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json?'
        'origin=${origen.latitude},${origen.longitude}&'
        'destination=${destino.latitude},${destino.longitude}&'
        'key=$apiKey&language=es&units=metric',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 6));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['status'] == 'OK' && (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];
          final leg = (route['legs'] as List)[0];
          final durSec = leg['duration']['value'] as int;
          final distM = leg['distance']['value'] as int;
          final points =
              _decodePolyline(route['overview_polyline']['points'] as String);
          if (mounted) {
            _polylines
              ..removeWhere((p) => p.polylineId == const PolylineId('ruta'))
              ..add(Polyline(
                polylineId: const PolylineId('ruta'),
                points: points,
                color: _cyan,
                width: 5,
                patterns: [PatternItem.dash(40), PatternItem.gap(15)],
                startCap: Cap.roundCap,
                endCap: Cap.roundCap,
              ));
            setState(() {
              _etaMinutos = (durSec / 60).round();
              _distanciaKm = distM / 1000;
            });
          }
        }
      }
    } catch (_) {}
  }

  List<LatLng> _decodePolyline(String encoded) {
    final result = <LatLng>[];
    int index = 0;
    final len = encoded.length;
    int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result2 = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result2 |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = (result2 & 1) != 0 ? ~(result2 >> 1) : (result2 >> 1);
      lat += dlat;
      shift = 0;
      result2 = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result2 |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = (result2 & 1) != 0 ? ~(result2 >> 1) : (result2 >> 1);
      lng += dlng;
      result.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return result;
  }

  Widget _buildMapa() {
    if (_cargandoMapa) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00E5FF))),
              SizedBox(height: 16),
              Text('Obteniendo tu ubicación…',
                  style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    }
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: _miPosicion != null
            ? LatLng(_miPosicion!.latitude, _miPosicion!.longitude)
            : LatLng(widget.solicitud.latTecnico, widget.solicitud.lngTecnico),
        zoom: 15,
        tilt: 0.0,
        bearing: 0.0,
      ),
      onMapCreated: (ctrl) {
        debugPrint('🗺️ [MapDebug] ✅ onMapCreated disparado');
        _mapController = ctrl;
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && _miPosicion != null) {
            _actualizarMapa(_miPosicion!);
          }
        });
      },
      markers: _markers,
      polylines: _polylines,
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      rotateGesturesEnabled: true,
      tiltGesturesEnabled: false,
      zoomGesturesEnabled: true,
      scrollGesturesEnabled: true,
      mapType: MapType.normal,
      style: MapStyles.estiloMapaUberDark,
    );
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Mapa — mismo patrón que ayuda_tracking_screen (directo, sin Positioned.fill)
          _buildMapa(),


          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
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
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 8)
                        ],
                      ),
                      child: const Icon(Icons.arrow_back,
                          color: Colors.black87, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 8)
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.navigation_rounded,
                              color: Color(0xFF4CAF50), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Yendo hacia ${widget.solicitud.tecnicoNombre}',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom card con ETA y distancia
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: _surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.3), blurRadius: 20)
                ],
              ),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Técnico destino
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2196F3).withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.person,
                            color: Color(0xFF2196F3), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.solicitud.tecnicoNombre,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15),
                            ),
                            Text(
                              widget.solicitud.tipo.displayName,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      // ETA
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (_etaMinutos != null)
                            Text(
                              '$_etaMinutos min',
                              style: const TextStyle(
                                color: _cyan,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          else
                            const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _cyan,
                              ),
                            ),
                          if (_distanciaKm != null)
                            Text(
                              '${_distanciaKm!.toStringAsFixed(1)} km',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _abrirEnGoogleMaps,
                      icon: const Icon(Icons.map_outlined, size: 18),
                      label: const Text('Abrir en Google Maps'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _cyan,
                        side: BorderSide(color: _cyan.withOpacity(0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirEnGoogleMaps() async {
    final lat = widget.solicitud.latTecnico;
    final lng = widget.solicitud.lngTecnico;
    if (lat == null || lng == null) return;

    final pos = _miPosicion;
    final url = pos != null
        ? 'https://www.google.com/maps/dir/?api=1'
            '&origin=${pos.latitude},${pos.longitude}'
            '&destination=$lat,$lng'
            '&travelmode=driving'
        : 'https://www.google.com/maps/dir/?api=1'
            '&destination=$lat,$lng'
            '&travelmode=driving';

    final uri = Uri.parse(url);
    final geo = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(geo)) {
        await launchUrl(geo, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }
}

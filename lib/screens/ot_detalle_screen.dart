import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:agente_desconexiones/constants/map_styles.dart';
import 'package:agente_desconexiones/models/navixy_point.dart';
import 'package:agente_desconexiones/services/navixy_service.dart';
import 'package:agente_desconexiones/services/produccion_service.dart';

/// Detalle de OT: tramo de **llegada** (fin OT anterior → inicio esta OT) vía Navixy.
class OtDetalleScreen extends StatefulWidget {
  const OtDetalleScreen({
    super.key,
    required this.ordenActual,
    this.ordenAnterior,
    required this.rutTecnico,
    required this.fechaTrabajo,
  });

  final Map<String, dynamic> ordenActual;
  final Map<String, dynamic>? ordenAnterior;
  final String rutTecnico;
  final String fechaTrabajo;

  @override
  State<OtDetalleScreen> createState() => _OtDetalleScreenState();
}

class _OtDetalleScreenState extends State<OtDetalleScreen> {
  final _navixy = NavixyService.instance;
  final _produccion = ProduccionService();

  Map<String, dynamic>? _orden;
  int? _trackerId;

  bool _cargando = true;
  bool _cargandoTrack = false;
  List<NavixyPoint> _puntos = [];
  bool _fatalNavixy = false;

  String? _fromStr;
  String? _toStr;
  DateTime? _ventanaFrom;
  DateTime? _ventanaTo;

  GoogleMapController? _mapController;
  final Set<Polyline> _polylines = {};
  final Set<Marker> _markers = {};
  final Set<Circle> _circles = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final ot = widget.ordenActual['orden_trabajo']?.toString() ?? '';
      final fecha = widget.fechaTrabajo;
      final row = await _produccion.obtenerOrdenProduccionCrea(
        rutTecnico: widget.rutTecnico,
        ordenTrabajo: ot,
        fechaTrabajo: fecha,
      );
      _orden = row ?? Map<String, dynamic>.from(widget.ordenActual);
      if (mounted) setState(() => _cargando = false);

      _trackerId = await _navixy.getTrackerIdPorRut(widget.rutTecnico);
      if (_trackerId != null) {
        _calcularVentanaTramo();
        await _cargarTrack();
      } else if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _fatalNavixy = true;
        });
      }
    }
  }

  /// Tramo de llegada: desde fin OT anterior (o 1 h antes si es primera) hasta inicio de esta OT.
  void _calcularVentanaTramo() {
    final o = _orden ?? widget.ordenActual;
    final fecha = o['fecha_trabajo']?.toString() ?? widget.fechaTrabajo;
    final ant = widget.ordenAnterior;

    if (ant != null) {
      final fechaAnt = ant['fecha_trabajo']?.toString() ?? fecha;
      final hf = ant['hora_fin']?.toString().trim();
      final hiActual = o['hora_inicio']?.toString() ?? '08:00';
      if (hf != null && hf.isNotEmpty) {
        _fromStr = _navixy.buildDateTime(fechaAnt, _soloHhMm(hf));
      } else {
        _fromStr = _navixy.buildDateTime(
          fecha,
          NavixyService.horaMenosUnaHora(hiActual),
        );
      }
      _toStr = _navixy.buildDateTime(fecha, _soloHhMm(hiActual));
    } else {
      final hi = o['hora_inicio']?.toString() ?? '08:00';
      _fromStr = _navixy.buildDateTime(
        fecha,
        NavixyService.horaMenosUnaHora(hi),
      );
      _toStr = _navixy.buildDateTime(fecha, _soloHhMm(hi));
    }

    _ventanaFrom = _parseNavixyLocal(_fromStr!);
    _ventanaTo = _parseNavixyLocal(_toStr!);
    if (_ventanaFrom != null &&
        _ventanaTo != null &&
        !_ventanaTo!.isAfter(_ventanaFrom!)) {
      _ventanaTo = _ventanaFrom!.add(const Duration(minutes: 1));
    }
  }

  String _soloHhMm(String raw) {
    final p = raw.trim().split(':');
    if (p.isEmpty) return '00:00';
    final h = p[0].padLeft(2, '0');
    final m = p.length > 1 ? p[1].split(' ').first.padLeft(2, '0') : '00';
    return '$h:$m';
  }

  DateTime? _parseNavixyLocal(String s) {
    return DateTime.tryParse(s.replaceFirst(' ', 'T'));
  }

  Future<void> _cargarTrack() async {
    final tid = _trackerId;
    if (tid == null || _orden == null) return;

    setState(() {
      _cargandoTrack = true;
      _fatalNavixy = false;
    });

    final from = _fromStr;
    final to = _toStr;
    if (from == null || to == null) {
      if (mounted) {
        setState(() {
          _cargandoTrack = false;
          _puntos = [];
        });
        _armarMapa();
      }
      return;
    }

    final vf = _ventanaFrom;
    final vt = _ventanaTo;
    if (vf == null || vt == null || !vt.isAfter(vf)) {
      if (mounted) {
        setState(() {
          _cargandoTrack = false;
          _puntos = [];
        });
        _armarMapa();
      }
      return;
    }

    try {
      final res = await _navixy.getTrack(
        trackerId: tid,
        from: from,
        to: to,
      );
      if (!mounted) return;
      setState(() {
        _puntos = res.points;
        _fatalNavixy = res.fatalError;
        _cargandoTrack = false;
      });
      if (!_fatalNavixy) _armarMapa();
    } catch (e) {
      if (mounted) {
        setState(() {
          _puntos = [];
          _fatalNavixy = true;
          _cargandoTrack = false;
        });
      }
    }
  }

  /// coord_x = lng, coord_y = lat
  LatLng? _posicionOt() {
    final o = _orden;
    if (o == null) return null;
    final x = o['coord_x'];
    final y = o['coord_y'];
    final lng = (x is num) ? x.toDouble() : double.tryParse(x?.toString() ?? '');
    final lat = (y is num) ? y.toDouble() : double.tryParse(y?.toString() ?? '');
    if (lat == null || lng == null) return null;
    if (lat.abs() < 1e-6 && lng.abs() < 1e-6) return null;
    return LatLng(lat, lng);
  }

  void _armarMapa() {
    _polylines.clear();
    _markers.clear();
    _circles.clear();

    final ot = _posicionOt();

    if (_puntos.isNotEmpty) {
      final coords =
          _puntos.map((p) => LatLng(p.lat, p.lng)).toList(growable: false);
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('tramo'),
          points: coords,
          color: const Color(0xFF00E5FF),
          width: 4,
        ),
      );

      final inicio = coords.first;
      _circles.add(
        Circle(
          circleId: const CircleId('inicio'),
          center: inicio,
          radius: 28,
          fillColor: const Color(0xFF22C55E).withOpacity(0.35),
          strokeColor: const Color(0xFF22C55E),
          strokeWidth: 2,
        ),
      );
    }

    if (ot != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('ot'),
          position: ot,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: 'OT ${_orden!['orden_trabajo'] ?? ''}',
            snippet: _orden!['direccion']?.toString() ?? '',
          ),
        ),
      );
    }

    if (mounted) setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ajustarCamara();
    });
  }

  Future<void> _ajustarCamara() async {
    final c = _mapController;
    if (c == null) return;

    final ot = _posicionOt();
    final List<LatLng> bounds = [];

    if (_puntos.isNotEmpty) {
      for (final p in _puntos) {
        bounds.add(LatLng(p.lat, p.lng));
      }
    }
    if (ot != null) bounds.add(ot);

    if (bounds.isEmpty) return;

    double minLat = bounds.first.latitude;
    double maxLat = bounds.first.latitude;
    double minLng = bounds.first.longitude;
    double maxLng = bounds.first.longitude;
    for (final p in bounds) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }

    if ((maxLat - minLat).abs() < 1e-5 && (maxLng - minLng).abs() < 1e-5) {
      await c.animateCamera(
        CameraUpdate.newLatLngZoom(bounds.first, 15),
      );
      return;
    }

    await c.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        80,
      ),
    );
  }

  double get _kmTramo {
    if (_puntos.isEmpty) return 0;
    final a = _puntos.first.mileage;
    final b = _puntos.last.mileage;
    final d = b - a;
    return d > 0 ? d : 0;
  }

  int get _duracionMin {
    final a = _ventanaFrom;
    final b = _ventanaTo;
    if (a == null || b == null) return 0;
    return b.difference(a).inMinutes.abs();
  }

  double get _velMax {
    if (_puntos.isEmpty) return 0;
    return _puntos.map((p) => p.speed).reduce(math.max);
  }

  @override
  Widget build(BuildContext context) {
    final ot = _orden;
    final h = MediaQuery.sizeOf(context).height;
    final mapH = (h * 0.5).clamp(220.0, 520.0);

    final mostrarMapa =
        _trackerId != null && !_fatalNavixy && !_cargandoTrack;

    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      appBar: AppBar(
        title: Text(
          'OT ${ot?['orden_trabajo'] ?? widget.ordenActual['orden_trabajo'] ?? ''}',
        ),
        backgroundColor: const Color(0xFF0D1B2A),
      ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
            )
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_trackerId == null) _cardSinGpsRegistrado(),
                  if (_fatalNavixy) _cardErrorNavixy(),
                  if (_trackerId != null && !_fatalNavixy) ...[
                    if (_cargandoTrack)
                      SizedBox(
                        height: mapH,
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF00E5FF),
                          ),
                        ),
                      )
                    else if (mostrarMapa)
                      SizedBox(
                        height: mapH,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(12),
                          ),
                          child: GoogleMap(
                            initialCameraPosition: CameraPosition(
                              target: _posicionOt() ??
                                  const LatLng(-33.45, -70.65),
                              zoom: 14,
                            ),
                            onMapCreated: (ctrl) {
                              _mapController = ctrl;
                              ctrl.setMapStyle(MapStyles.estiloMapaUberDark);
                              _ajustarCamara();
                            },
                            polylines: _polylines,
                            markers: _markers,
                            circles: _circles,
                            myLocationButtonEnabled: false,
                            zoomControlsEnabled: false,
                            mapToolbarEnabled: false,
                          ),
                        ),
                      ),
                    if (_puntos.isEmpty && mostrarMapa)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Text(
                          'Sin datos GPS para este tramo',
                          style: const TextStyle(color: Color(0xFF8FA8C8)),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    if (!_cargandoTrack)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: _seccionTramoLlegada(),
                      ),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: _datosOtCard(ot),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _cardSinGpsRegistrado() {
    return Card(
      margin: const EdgeInsets.all(16),
      color: const Color(0xFF161B22),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.gps_off, color: Colors.amber.shade600, size: 40),
            const SizedBox(width: 16),
            const Expanded(
              child: Text(
                'Este técnico no tiene GPS registrado',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardErrorNavixy() {
    return Card(
      margin: const EdgeInsets.all(16),
      color: const Color(0xFF161B22),
      child: const Padding(
        padding: EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.cloud_off, color: Color(0xFF8FA8C8), size: 36),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                'No se pudo cargar el recorrido. Se muestran solo los datos de la orden.',
                style: TextStyle(color: Colors.white70, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _seccionTramoLlegada() {
    return Card(
      color: const Color(0xFF161B22),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TRAMO DE LLEGADA',
              style: TextStyle(
                color: Color(0xFF00E5FF),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _metricItem(
                    'Duración',
                    '$_duracionMin min',
                  ),
                ),
                Expanded(
                  child: _metricItem(
                    'Distancia',
                    '${_kmTramo.toStringAsFixed(1)} km',
                  ),
                ),
                Expanded(
                  child: _metricItem(
                    'Vel. máx',
                    '${_velMax.toStringAsFixed(0)} km/h',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 11),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget _datosOtCard(Map<String, dynamic>? o) {
    if (o == null) return const SizedBox.shrink();
    String t(String k) => o[k]?.toString() ?? '—';
    final cliente = t('cliente').trim().isNotEmpty
        ? t('cliente')
        : t('tecnico');

    return Card(
      color: const Color(0xFF161B22),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'DETALLE DE LA OT',
              style: TextStyle(
                color: Color(0xFF00E5FF),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 12),
            _filaDato('Tipo', t('tipo_orden')),
            _filaDato('Estado', t('estado')),
            _filaDato('Inicio', t('hora_inicio')),
            _filaDato('Fin', t('hora_fin')),
            _filaDato('Cliente', cliente),
            _filaDato('Dirección', t('direccion')),
            _filaDato('Duración (min)', t('duracion_min')),
            _filaDato('RGU total', t('rgu_total')),
            _filaDato('Fecha', t('fecha_trabajo')),
          ],
        ),
      ),
    );
  }

  Widget _filaDato(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              k,
              style: TextStyle(
                color: Colors.white.withOpacity(0.55),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

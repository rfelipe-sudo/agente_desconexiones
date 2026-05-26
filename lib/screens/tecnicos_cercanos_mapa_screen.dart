import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:agente_desconexiones/constants/map_styles.dart';
import 'package:agente_desconexiones/services/logistica_service.dart';
import 'package:agente_desconexiones/services/ubicacion_service.dart';

class TecnicosCercanosMapaScreen extends StatefulWidget {
  const TecnicosCercanosMapaScreen({
    super.key,
    required this.tipoMaterial,
    required this.posicionSolicitante,
    required this.rutSolicitante,
  });

  final String   tipoMaterial;
  final Position posicionSolicitante;
  final String   rutSolicitante;

  @override
  State<TecnicosCercanosMapaScreen> createState() =>
      _TecnicosCercanosMapaScreenState();
}

class _TecnicosCercanosMapaScreenState
    extends State<TecnicosCercanosMapaScreen> {
  static const _bg      = Color(0xFF0A0F1E);
  static const _surface = Color(0xFF0D1B2A);
  static const _accent  = Color(0xFF00D9FF);
  static const _textDim = Color(0xFF8FA8C8);
  static const _green   = Color(0xFF22C55E);

  GoogleMapController? _mapCtrl;
  final Set<Marker>    _markers   = {};
  final Set<Circle>    _circles   = {};

  bool _cargando = true;
  List<_TecnicoCercano> _tecnicos = [];

  BitmapDescriptor? _iconoYo;
  BitmapDescriptor? _iconoTecnico;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    await _crearIconos();
    await _cargarTecnicos();
  }

  Future<void> _crearIconos() async {
    _iconoYo      = await _circleMarker(_accent, 40);
    _iconoTecnico = await _circleMarker(_green,  40);
    if (mounted) setState(() {});
  }

  Future<BitmapDescriptor> _circleMarker(Color color, double size) async {
    final recorder = ui.PictureRecorder();
    final canvas   = Canvas(recorder);
    final paint    = Paint()..color = color;
    final shadow   = Paint()
      ..color    = color.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    final center = Offset(size / 2, size / 2);
    final radius = size / 2 - 4;

    canvas.drawCircle(center, radius + 6, shadow);
    canvas.drawCircle(center, radius, paint);
    canvas.drawCircle(
      center, radius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    final picture = recorder.endRecording();
    final image   = await picture.toImage(size.toInt(), size.toInt());
    final bytes   = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  Future<void> _cargarTecnicos() async {
    setState(() => _cargando = true);
    try {
      final lat = widget.posicionSolicitante.latitude;
      final lng = widget.posicionSolicitante.longitude;

      // Técnicos dentro de 5 km con GPS activo
      final cercanos = await UbicacionService.obtenerTecnicosCercanos(
        latSolicitante: lat,
        lngSolicitante: lng,
        radioKm:        5.0,
        excluirRut:     widget.rutSolicitante,
      );

      if (cercanos.isEmpty) {
        setState(() {
          _tecnicos = [];
          _cargando = false;
        });
        _actualizarMapa();
        return;
      }

      // Consultar stock KRP
      final stockList = await LogisticaService().fetchStock();
      final stockMap  = {for (final t in stockList) t.rut: t};

      final List<_TecnicoCercano> resultado = [];
      for (final c in cercanos) {
        final rut     = c['rut_tecnico'] as String? ?? '';
        final tecStock = stockMap[rut];
        final cantidad = tecStock?.stock[widget.tipoMaterial] ?? 0;
        if (cantidad <= 0) continue; // sin stock de este material

        resultado.add(_TecnicoCercano(
          rut:         rut,
          nombre:      tecStock?.nombre ?? rut,
          lat:         (c['lat'] as num).toDouble(),
          lng:         (c['lng'] as num).toDouble(),
          distanciaKm: (c['distancia_km'] as num).toDouble(),
          stockQty:    cantidad.toInt(),
          updatedAt:   DateTime.tryParse(c['updated_at'] as String? ?? '') ??
                       DateTime.now(),
        ));
      }

      setState(() {
        _tecnicos = resultado;
        _cargando = false;
      });
      _actualizarMapa();
    } catch (e) {
      setState(() => _cargando = false);
    }
  }

  void _actualizarMapa() {
    final lat = widget.posicionSolicitante.latitude;
    final lng = widget.posicionSolicitante.longitude;

    _markers.clear();
    _circles.clear();

    // Círculo de 5 km
    _circles.add(Circle(
      circleId: const CircleId('radio'),
      center:   LatLng(lat, lng),
      radius:   5000,
      fillColor: _accent.withValues(alpha: 0.06),
      strokeColor: _accent.withValues(alpha: 0.4),
      strokeWidth: 1,
    ));

    // Marcador propio
    _markers.add(Marker(
      markerId: const MarkerId('yo'),
      position: LatLng(lat, lng),
      icon:     _iconoYo ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      infoWindow: const InfoWindow(title: 'Tú'),
    ));

    // Marcadores técnicos
    for (final t in _tecnicos) {
      _markers.add(Marker(
        markerId: MarkerId(t.rut),
        position: LatLng(t.lat, t.lng),
        icon:     _iconoTecnico ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(
          title: t.nombre,
          snippet: '${t.stockQty} uds · ${t.distanciaKm.toStringAsFixed(1)} km',
        ),
        onTap: () => _mostrarDetalle(t),
      ));
    }

    if (mounted) setState(() {});
  }

  void _mostrarDetalle(_TecnicoCercano t) {
    final mins = DateTime.now().difference(t.updatedAt).inMinutes;
    showModalBottomSheet<void>(
      context:         context,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.person_pin_circle_rounded, color: _green, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(t.nombre,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ),
            ]),
            const SizedBox(height: 12),
            _Row('Material',  widget.tipoMaterial),
            _Row('Stock',     '${t.stockQty} unidades'),
            _Row('Distancia', '${t.distanciaKm.toStringAsFixed(2)} km'),
            _Row('Ubicación', 'hace $mins min'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context, t.rut); // devuelve el RUT elegido
                },
                child: const Text('Solicitar a este técnico',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lat = widget.posicionSolicitante.latitude;
    final lng = widget.posicionSolicitante.longitude;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Técnicos cercanos',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            Text(widget.tipoMaterial,
                style: const TextStyle(color: _textDim, fontSize: 12)),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _accent),
            onPressed: _cargarTecnicos,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(lat, lng),
              zoom:   14,
            ),
            onMapCreated: (ctrl) {
              _mapCtrl = ctrl;
              ctrl.setMapStyle(MapStyles.estiloMapaUberDark);
            },
            markers:         _markers,
            circles:         _circles,
            myLocationEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),
          // Panel inferior
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: _buildPanel(),
          ),
          // Loading overlay
          if (_cargando)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(
                    child: CircularProgressIndicator(color: _accent)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPanel() {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(top: BorderSide(color: _accent.withValues(alpha: 0.2))),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 4, height: 16,
              decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 8),
            Text(
              _cargando
                  ? 'Buscando...'
                  : _tecnicos.isEmpty
                      ? 'Sin técnicos con stock en 5 km'
                      : '${_tecnicos.length} técnico${_tecnicos.length > 1 ? 's' : ''} con stock disponible',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14),
            ),
          ]),
          if (_tecnicos.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount:       _tecnicos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _ChipTecnico(
                  tecnico: _tecnicos[i],
                  onTap:   () => _mostrarDetalle(_tecnicos[i]),
                ),
              ),
            ),
          ],
          if (_tecnicos.isEmpty && !_cargando) ...[
            const SizedBox(height: 8),
            const Text(
              'No hay técnicos cercanos con GPS activo y stock del material solicitado.',
              style: TextStyle(color: _textDim, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Chip técnico en la lista horizontal ──────────────────────────────────────

class _ChipTecnico extends StatelessWidget {
  const _ChipTecnico({required this.tecnico, required this.onTap});

  final _TecnicoCercano tecnico;
  final VoidCallback    onTap;

  static const _surface = Color(0xFF0A0F1E);
  static const _green   = Color(0xFF22C55E);
  static const _accent  = Color(0xFF00D9FF);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _green.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.person, color: _green, size: 14),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  tecnico.nombre.split(' ').first,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Text('${tecnico.stockQty} uds',
                style: const TextStyle(color: _green, fontSize: 11)),
            Text('${tecnico.distanciaKm.toStringAsFixed(1)} km',
                style: const TextStyle(color: _accent, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// ── Info row helper ───────────────────────────────────────────────────────────

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Text('$label: ',
            style: const TextStyle(
                color: Color(0xFF8FA8C8), fontSize: 13)),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ),
      ]),
    );
  }
}

// ── Modelo interno ────────────────────────────────────────────────────────────

class _TecnicoCercano {
  const _TecnicoCercano({
    required this.rut,
    required this.nombre,
    required this.lat,
    required this.lng,
    required this.distanciaKm,
    required this.stockQty,
    required this.updatedAt,
  });

  final String   rut;
  final String   nombre;
  final double   lat;
  final double   lng;
  final double   distanciaKm;
  final int      stockQty;
  final DateTime updatedAt;
}

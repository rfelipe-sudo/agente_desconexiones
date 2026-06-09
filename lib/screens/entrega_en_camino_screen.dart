import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:agente_desconexiones/constants/map_styles.dart';
import 'package:agente_desconexiones/models/solicitud_material.dart';
import 'package:agente_desconexiones/screens/guia_entrega_screen.dart';
import 'package:agente_desconexiones/services/material_solicitud_service.dart';
import 'package:agente_desconexiones/services/solicitud_estado_monitor.dart';

/// Pantalla del entregador mientras se desplaza hacia el solicitante.
/// Cuando la distancia baja de 200 m se abre automáticamente la guía.
class EntregaEnCaminoScreen extends StatefulWidget {
  final SolicitudMaterial solicitud;
  final String rutPropio;
  final String nombrePropio;
  final Position? posicionInicial;
  /// Aceptación en BD en paralelo — el mapa se muestra de inmediato.
  final Future<SolicitudMaterial>? prepararEntrega;

  const EntregaEnCaminoScreen({
    super.key,
    required this.solicitud,
    required this.rutPropio,
    required this.nombrePropio,
    this.posicionInicial,
    this.prepararEntrega,
  });

  @override
  State<EntregaEnCaminoScreen> createState() => _EntregaEnCaminoScreenState();
}

class _EntregaEnCaminoScreenState extends State<EntregaEnCaminoScreen> {
  static const Color _bg      = Color(0xFF0A1628);
  static const Color _surface = Color(0xFF0D1B2A);
  static const Color _accent  = Color(0xFF00D9FF);
  static const Color _border  = Color(0xFF1E3A5F);
  static const Color _textDim = Color(0xFF8FA8C8);
  static const Color _green   = Color(0xFF22C55E);
  static const Color _orange  = Color(0xFFF59E0B);
  static const Color _red     = Color(0xFFEF4444);

  Position? _posicion;
  double?   _distanciaMetros;
  bool      _navegando = false;
  late SolicitudMaterial _solicitud;
  bool _preparandoEntrega = false;
  String? _errorPreparacion;

  GoogleMapController? _mapController;
  final Set<Marker> _markers  = {};
  BitmapDescriptor? _iconoYo;
  BitmapDescriptor? _iconoSolicitante;

  Timer? _timerGps;
  final SolicitudEstadoMonitor _estadoMonitor = SolicitudEstadoMonitor();
  bool _transaccionCerrada = false;

  @override
  void initState() {
    super.initState();
    _solicitud = widget.solicitud;
    _posicion = widget.posicionInicial;
    _crearIconos();
    _iniciarSeguimiento();
    _suscribirCancelacion();
    _ejecutarPreparacionSiCorresponde();
  }

  void _ejecutarPreparacionSiCorresponde() {
    final futuro = widget.prepararEntrega;
    if (futuro == null) return;
    setState(() => _preparandoEntrega = true);
    futuro.then((actualizada) {
      if (!mounted) return;
      setState(() {
        _solicitud = actualizada;
        _preparandoEntrega = false;
      });
      _actualizarMarkers();
      _actualizarPosicion();
    }).catchError((Object e) {
      if (!mounted) return;
      setState(() {
        _preparandoEntrega = false;
        _errorPreparacion = e.toString();
      });
    });
  }

  @override
  void dispose() {
    _timerGps?.cancel();
    _estadoMonitor.stop();
    _mapController?.dispose();
    super.dispose();
  }

  void _suscribirCancelacion() {
    _estadoMonitor.start(
      solicitudId: _solicitud.id,
      onEstado: (estado) {
        if (!mounted || _transaccionCerrada) return;
        if (estado == 'completada') {
          _transaccionCerrada = true;
          _timerGps?.cancel();
          _estadoMonitor.stop();
          _mostrarCompletada();
          return;
        }
        if (estado == 'cancelada') {
          _transaccionCerrada = true;
          _timerGps?.cancel();
          _estadoMonitor.stop();
          _mostrarCancelacion();
          return;
        }
        // Modalidad "ven a buscar": el solicitante avisa llegada → abrir guía.
        if (estado == 'en_guia' &&
            _solicitud.modalidad == 'ven_por_el' &&
            !_navegando) {
          _navegando = true;
          _irAGuia(sinActualizarEstado: true);
        }
      },
    );
  }

  Future<void> _mostrarCompletada() async {
    if (!mounted) return;
    await MaterialTransaccionUi.mostrarCompletada(context);
    if (!mounted) return;
    MaterialTransaccionUi.cerrarFlujoEntregador(context);
  }

  void _mostrarCancelacion() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1B2A),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF1E3A5F))),
        title: const Row(children: [
          Icon(Icons.cancel_outlined, color: Color(0xFFEF4444), size: 22),
          SizedBox(width: 8),
          Text('Transacción cancelada',
              style: TextStyle(color: Colors.white, fontSize: 16)),
        ]),
        content: Text(
          'La solicitud de ${_solicitud.tipoMaterial} fue cancelada.',
          style: const TextStyle(color: Color(0xFF8FA8C8), fontSize: 13),
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              MaterialTransaccionUi.cerrarFlujoEntregador(context);
            },
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _crearIconos() async {
    _iconoYo          = await _circleMarker(const Color(0xFF00D9FF), 64);
    _iconoSolicitante = await _circleMarker(const Color(0xFFF59E0B), 72);
    if (mounted) {
      _actualizarMarkers();
    }
  }

  Future<BitmapDescriptor> _circleMarker(Color color, double size) async {
    final recorder = ui.PictureRecorder();
    final canvas   = Canvas(recorder);
    final shadow   = Paint()
      ..color      = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(Offset(size / 2, size / 2 + 2), size / 2 - 4, shadow);
    final fill = Paint()
      ..shader = ui.Gradient.radial(
        Offset(size / 2, size / 2), size / 2 - 6,
        [color, color.withValues(alpha: 0.75)],
      );
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2 - 6, fill);
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2 - 6,
        Paint()
          ..color       = Colors.white
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 3);
    canvas.drawCircle(
        Offset(size / 2, size / 2), size * 0.1, Paint()..color = Colors.white);
    final picture = recorder.endRecording();
    final image   = await picture.toImage(size.toInt(), size.toInt());
    final bytes   = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  void _iniciarSeguimiento() {
    _actualizarPosicion();
    _timerGps = Timer.periodic(const Duration(seconds: 10), (_) {
      _actualizarPosicion();
    });
  }

  Future<void> _actualizarPosicion() async {
    if (_preparandoEntrega) return;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high));
      if (!mounted) return;
      setState(() => _posicion = pos);

      // Publica posición para que el emisor vea distancia en tiempo real
      Supabase.instance.client
          .from('solicitudes_material')
          .update({
            'lat_entregador': pos.latitude,
            'lng_entregador': pos.longitude,
          })
          .eq('id', _solicitud.id)
          .then((_) {})
          .catchError((_) {});

      final sol = _solicitud;
      final esVenPorEl = sol.modalidad == 'ven_por_el';
      if (!esVenPorEl &&
          sol.latSolicitante != null &&
          sol.lngSolicitante != null) {
        final d = Geolocator.distanceBetween(pos.latitude, pos.longitude,
            sol.latSolicitante!, sol.lngSolicitante!);
        setState(() => _distanciaMetros = d);

        if (d < 200 && !_navegando) {
          unawaited(_abrirGuia());
        }
      } else if (esVenPorEl) {
        _actualizarMarkers();
      }
    } catch (_) {}
  }

  void _actualizarMarkers() {
    final markers = <Marker>{};
    final pos     = _posicion;
    final sol     = _solicitud;

    if (pos != null) {
      markers.add(Marker(
        markerId: const MarkerId('yo'),
        position: LatLng(pos.latitude, pos.longitude),
        icon: _iconoYo ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'Tú'),
      ));
    }

    if (sol.latSolicitante != null && sol.lngSolicitante != null) {
      markers.add(Marker(
        markerId: const MarkerId('solicitante'),
        position: LatLng(sol.latSolicitante!, sol.lngSolicitante!),
        icon: _iconoSolicitante ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(
          title: sol.nombreSolicitante,
          snippet: sol.tipoMaterial,
        ),
      ));
    }

    if (mounted) {
      setState(() {
        _markers
          ..clear()
          ..addAll(markers);
      });
    }

    // Centrar cámara
    if (pos != null && sol.latSolicitante != null && sol.lngSolicitante != null) {
      // Ambas posiciones: mostrar punto medio
      final midLat = (pos.latitude + sol.latSolicitante!) / 2;
      final midLng = (pos.longitude + sol.lngSolicitante!) / 2;
      _mapController?.animateCamera(
          CameraUpdate.newLatLng(LatLng(midLat, midLng)));
    } else if (sol.latSolicitante != null && sol.lngSolicitante != null) {
      // Sin GPS propio: al menos mostrar al solicitante
      _mapController?.animateCamera(
          CameraUpdate.newLatLng(
              LatLng(sol.latSolicitante!, sol.lngSolicitante!)));
    }
  }

  Future<void> _abrirGuia() async {
    if (_preparandoEntrega || !mounted) return;
    if (_navegando) return;
    _navegando = true;
    _irAGuia();
  }

  Future<void> _cancelarEntrega() async {
    if (_transaccionCerrada || !mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('Cancelar entrega',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          '¿Cancelar la entrega de ${_solicitud.tipoMaterial}?\n'
          'Se notificará al solicitante.',
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
    if (confirm != true || !mounted) return;
    try {
      await MaterialSolicitudService().cancelarSolicitud(
        solicitudId:   _solicitud.id,
        rutCancelador: widget.rutPropio,
      );
      _transaccionCerrada = true;
      _timerGps?.cancel();
      _estadoMonitor.stop();
      if (!mounted) return;
      await MaterialTransaccionUi.mostrarCancelada(context);
      if (!mounted) return;
      MaterialTransaccionUi.cerrarFlujoEntregador(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is StateError ? e.message : 'Error al cancelar: $e',
          ),
        ),
      );
    }
  }

  void _irAGuia({bool sinActualizarEstado = false}) {
    if (!mounted) return;
    if (!sinActualizarEstado) {
      unawaited(Supabase.instance.client
          .from('solicitudes_material')
          .update({'estado': 'en_guia'})
          .eq('id', _solicitud.id)
          .then((_) {})
          .catchError((_) {}));
    }
    Navigator.pushReplacement<void, void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => GuiaEntregaScreen(
          solicitud:    _solicitud,
          rutPropio:    widget.rutPropio,
          nombrePropio: widget.nombrePropio,
          posicion:     _posicion,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sol       = _solicitud;
    final esVenPorEl = sol.modalidad == 'ven_por_el';
    final distancia = _distanciaMetros;
    final distLabel = distancia == null
        ? 'Calculando...'
        : distancia < 1000
            ? '${distancia.toInt()} m'
            : '${(distancia / 1000).toStringAsFixed(1)} km';

    final distColor = distancia == null
        ? _textDim
        : distancia < 200
            ? _green
            : distancia < 1000
                ? _orange
                : _accent;

    final camPos = _posicion != null
        ? LatLng(_posicion!.latitude, _posicion!.longitude)
        : sol.latSolicitante != null
            ? LatLng(sol.latSolicitante!, sol.lngSolicitante!)
            : const LatLng(-33.45, -70.66);

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // ── Mapa full-screen ──────────────────────────────────
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: camPos, zoom: 14),
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
                Future.delayed(
                    const Duration(milliseconds: 300), _actualizarMarkers);
              },
            ),
          ),

          // ── Barra superior — Column para que el Stack tome la altura completa
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
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 10)
                      ],
                    ),
                    child: Row(children: [
                      const Icon(Icons.directions_walk,
                              color: Color(0xFF00D9FF), size: 20)
                          .animate(onPlay: (c) => c.repeat())
                          .shimmer(
                              duration: 1400.ms,
                              color: Colors.white.withValues(alpha: 0.7))
                          .then()
                          .shake(hz: 2, duration: 600.ms),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          esVenPorEl
                              ? 'Esperando a ${sol.nombreSolicitante}'
                              : 'En camino a ${sol.nombreSolicitante}',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ]),
                  ),
                ),
              ]),
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
                padding: const EdgeInsets.all(20),
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
                  children: [
                    if (esVenPorEl) ...[
                      Icon(Icons.store_outlined, color: _orange, size: 36),
                      const SizedBox(height: 8),
                      const Text(
                        'Modalidad: te lo vienen a buscar',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Quédate en tu ubicación. Se abrirá la guía cuando ${sol.nombreSolicitante} avise que llegó.',
                        style: TextStyle(color: _textDim, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ] else ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            distLabel,
                            style: TextStyle(
                              color: distColor,
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                              height: 1,
                            ),
                          ),
                          if (distancia != null) ...[
                            const SizedBox(width: 6),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                'de distancia',
                                style: TextStyle(
                                    color: _textDim, fontSize: 12),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (distancia != null && distancia >= 200) ...[
                        const SizedBox(height: 2),
                        Text(
                          '~${(distancia / 500).ceil()} min estimados',
                          style: TextStyle(color: _textDim, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      if (distancia != null && distancia < 200) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: _green.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: _green.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle,
                                  color: _green, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                _navegando
                                    ? '¡Llegaste! Abriendo guía...'
                                    : '¡Llegaste! Toca para abrir la guía',
                                style: const TextStyle(
                                    color: _green,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed:
                                _navegando ? null : () => _abrirGuia(),
                            icon: const Icon(Icons.draw_outlined, size: 16),
                            label: const Text('Abrir guía de entrega',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                            style: FilledButton.styleFrom(
                              backgroundColor: _green,
                              foregroundColor: Colors.black,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed:
                                _navegando ? null : () => _abrirGuia(),
                            icon: const Icon(Icons.draw_outlined, size: 16),
                            label: const Text('Ya llegué — abrir guía',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _accent,
                              side: BorderSide(
                                  color: _accent.withValues(alpha: 0.5)),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ],

                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${sol.cantidad}× ${sol.tipoMaterial}',
                        style: const TextStyle(
                            color: _orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Solicita: ${sol.nombreSolicitante}',
                      style: TextStyle(color: _textDim, fontSize: 12),
                    ),
                    if (esVenPorEl) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _navegando ? null : () => _abrirGuia(),
                          icon: const Icon(Icons.draw_outlined, size: 16),
                          label: const Text('Abrir guía manualmente',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _accent,
                            side: BorderSide(
                                color: _accent.withValues(alpha: 0.5)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _cancelarEntrega,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _red,
                          side: BorderSide(
                              color: _red.withValues(alpha: 0.5)),
                          padding:
                              const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: const Text('Cancelar entrega'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (_preparandoEntrega)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.45),
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
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: _accent,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Confirmando entrega…',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Preparando ${sol.tipoMaterial} para ${sol.nombreSolicitante}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: _textDim, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          if (_errorPreparacion != null)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.55),
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 32),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _red.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: Color(0xFFEF4444), size: 32),
                        const SizedBox(height: 12),
                        const Text(
                          'No se pudo confirmar la entrega',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorPreparacion!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: _textDim, fontSize: 12),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Volver'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

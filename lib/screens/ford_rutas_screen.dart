import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../models/ford_ruta.dart';
import '../services/ford_api_service.dart';

const _bg = Color(0xFF0A1628);
const _surface = Color(0xFF0D1B2A);
const _accent = Color(0xFF00D9FF);
const _border = Color(0xFF1E3A5F);
const _textDim = Color(0xFF8FA8C8);
const _green = Color(0xFF4CAF50);
const _orange = Color(0xFFF59E0B);

// Coordinates of the base warehouse (Avda Lo Espejo 1565, Lo Espejo)
// Verified via Nominatim/OSM geocoding
const _baseLatLng = LatLng(-33.5380, -70.6882);

class FordRutasScreen extends StatefulWidget {
  final String rutTecnico;
  final String nombreTecnico;
  final String mes;
  final double precioLitro;
  final double rendimientoKmL;

  const FordRutasScreen({
    super.key,
    required this.rutTecnico,
    required this.nombreTecnico,
    required this.mes,
    this.precioLitro = 1500.0,
    this.rendimientoKmL = 12.0,
  });

  @override
  State<FordRutasScreen> createState() => _FordRutasScreenState();
}

class _FordRutasScreenState extends State<FordRutasScreen> {
  final _svc = FordApiService();

  List<FordDiaRuta> _rutas = [];
  Map<DateTime, List<FordDiaRuta>> _semanas = {};
  bool _loading = true;
  String? _error;

  final _mapCtrl = Completer<GoogleMapController>();
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  // Drill-down selection: week → day → traslado
  DateTime? _semanaSeleccionada;
  FordDiaRuta? _diaSeleccionado;
  FordTraslado? _trasladoSeleccionado;

  // Cache of OSRM road geometry: key = cache key string → road points
  final Map<String, List<LatLng>> _routeCache = {};

  static const _hues = [
    BitmapDescriptor.hueAzure,
    BitmapDescriptor.hueGreen,
    BitmapDescriptor.hueOrange,
    BitmapDescriptor.hueRed,
    BitmapDescriptor.hueViolet,
    BitmapDescriptor.hueYellow,
  ];

  static const _lineColors = [
    _accent, _green, _orange,
    Color(0xFFEF4444), Color(0xFF9C27B0), Color(0xFFFFEB3B),
  ];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  // ── Data loading ─────────────────────────────────────────────

  Future<void> _cargar() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rutas = await _svc.getRutasDelTecnico(widget.rutTecnico);

      final grupos = <DateTime, List<FordDiaRuta>>{};
      for (final dia in rutas) {
        final ws = dia.semanaISO;
        if (ws == null) continue;
        grupos.putIfAbsent(ws, () => []).add(dia);
      }
      for (final dias in grupos.values) {
        dias.sort((a, b) => a.fecha!.compareTo(b.fecha!));
      }

      DateTime? defaultWeek;
      if (grupos.isNotEmpty) {
        final sortedWeeks = grupos.keys.toList()..sort();
        // Arrancar en la semana anterior a la más reciente (si existe)
        defaultWeek = sortedWeeks.length > 1
            ? sortedWeeks[sortedWeeks.length - 2]
            : sortedWeeks.last;
      }

      if (mounted) {
        setState(() {
          _rutas = rutas;
          _semanas = grupos;
          _semanaSeleccionada = defaultWeek;
          _diaSeleccionado = null;
          _trasladoSeleccionado = null;
          _loading = false;
        });
        _rebuildMap();
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  // ── Selection handlers ────────────────────────────────────────

  void _onTapDia(FordDiaRuta dia) {
    final isSame = _diaSeleccionado == dia && _trasladoSeleccionado == null;
    setState(() {
      _diaSeleccionado = isSame ? null : dia;
      _trasladoSeleccionado = null;
    });
    _rebuildMap();
  }

  void _onTapTraslado(FordDiaRuta dia, FordTraslado t) {
    final isSame = _trasladoSeleccionado == t;
    setState(() {
      _diaSeleccionado = dia;
      _trasladoSeleccionado = isSame ? null : t;
    });
    _rebuildMap();
  }

  // ── Map building ──────────────────────────────────────────────

  void _rebuildMap() {
    if (_trasladoSeleccionado != null && _diaSeleccionado != null) {
      _mapTraslado(_diaSeleccionado!, _trasladoSeleccionado!);
    } else if (_diaSeleccionado != null) {
      _mapDias([_diaSeleccionado!]);
    } else if (_semanaSeleccionada != null) {
      final entry = _semanas.entries
          .where((e) => _mismaSemana(e.key, _semanaSeleccionada))
          .firstOrNull;
      _mapDias(entry?.value ?? []);
    } else {
      _mapDias(_rutas);
    }
  }

  Future<void> _mapDias(List<FordDiaRuta> dias) async {
    final markers = <Marker>{};
    // polylineMap lets us replace individual lines as road geometry arrives
    final polylineMap = <String, Polyline>{};

    // Collect per-day coordinate lists
    final dayCoords = <int, List<LatLng>>{};

    for (final (dIdx, dia) in dias.indexed) {
      final hue = _hues[dIdx % _hues.length];
      final lineColor = _lineColors[dIdx % _lineColors.length];

      for (final (oIdx, ot) in dia.ots.indexed) {
        if (!ot.tieneCoords) continue;
        markers.add(Marker(
          markerId: MarkerId('ot_${dIdx}_$oIdx'),
          position: LatLng(ot.coordLat!, ot.coordLng!),
          infoWindow: InfoWindow(
            title: 'OT ${ot.orden}',
            snippet: [ot.direccion, ot.ciudad]
                .where((s) => s.isNotEmpty)
                .join(', '),
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        ));
      }

      final coords = dia.ots
          .where((o) => o.tieneCoords)
          .map((o) => LatLng(o.coordLat!, o.coordLng!))
          .toList();

      if (coords.length >= 2) {
        dayCoords[dIdx] = coords;
        // Straight line as immediate placeholder
        polylineMap['route_${dIdx}_${dia.fechaToa}'] = Polyline(
          polylineId: PolylineId('route_${dIdx}_${dia.fechaToa}'),
          points: coords,
          color: lineColor.withValues(alpha: 0.45),
          width: 2,
          patterns: [PatternItem.dash(8), PatternItem.gap(4)],
        );
      }
    }

    if (!mounted) return;
    setState(() { _markers = markers; _polylines = polylineMap.values.toSet(); });
    _centrarMapa();

    // Fetch real road geometry for each day sequentially
    for (final (dIdx, dia) in dias.indexed) {
      final coords = dayCoords[dIdx];
      if (coords == null) continue;

      final cacheKey = 'day_${dia.fechaToa}';
      final lineColor = _lineColors[dIdx % _lineColors.length];
      final polyKey  = 'route_${dIdx}_${dia.fechaToa}';

      List<LatLng> roadPoints;
      if (_routeCache.containsKey(cacheKey)) {
        roadPoints = _routeCache[cacheKey]!;
      } else {
        final fetched = await _fetchOsrmRoute(coords);
        if (!mounted) return;
        if (fetched == null) continue;
        _routeCache[cacheKey] = fetched;
        roadPoints = fetched;
      }

      polylineMap[polyKey] = Polyline(
        polylineId: PolylineId(polyKey),
        points: roadPoints,
        color: lineColor,
        width: 3,
      );
      if (mounted) setState(() => _polylines = polylineMap.values.toSet());
    }
  }

  Future<void> _mapTraslado(FordDiaRuta dia, FordTraslado t) async {
    final esBase = t.tipoLeg == 'bodega_ida' || t.tipoLeg == 'bodega_vuelta';
    final color = esBase ? _orange : _accent;

    LatLng? desdePos;
    LatLng? hastaPos;

    if (t.desde.esBodega) {
      desdePos = _baseLatLng;
    } else {
      final ot = dia.ots
          .where((o) => o.orden == t.desde.orden && o.tieneCoords)
          .firstOrNull;
      if (ot != null) desdePos = LatLng(ot.coordLat!, ot.coordLng!);
    }

    if (t.hasta.esBodega) {
      hastaPos = _baseLatLng;
    } else {
      final ot = dia.ots
          .where((o) => o.orden == t.hasta.orden && o.tieneCoords)
          .firstOrNull;
      if (ot != null) hastaPos = LatLng(ot.coordLat!, ot.coordLng!);
    }

    final markers = <Marker>{};

    if (desdePos != null) {
      markers.add(Marker(
        markerId: const MarkerId('desde'),
        position: desdePos,
        infoWindow: InfoWindow(title: t.desde.label, snippet: t.desde.direccionCorta),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ));
    }
    if (hastaPos != null) {
      markers.add(Marker(
        markerId: const MarkerId('hasta'),
        position: hastaPos,
        infoWindow: InfoWindow(title: t.hasta.label, snippet: t.hasta.direccionCorta),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ));
    }

    if (desdePos == null || hastaPos == null) {
      setState(() { _markers = markers; _polylines = {}; });
      _centrarMapa();
      return;
    }

    // Straight-line placeholder while OSRM loads
    setState(() {
      _markers = markers;
      _polylines = {
        Polyline(
          polylineId: const PolylineId('tramo'),
          points: [desdePos!, hastaPos!],
          color: color.withValues(alpha: 0.45),
          width: 2,
          patterns: [PatternItem.dash(8), PatternItem.gap(4)],
        ),
      };
    });
    _centrarMapa();

    // Fetch actual road geometry
    final cacheKey = 'traslado_${dia.fechaToa}_${t.tramo}';
    List<LatLng>? roadPoints = _routeCache[cacheKey];
    if (roadPoints == null) {
      roadPoints = await _fetchOsrmRoute([desdePos, hastaPos]);
      if (roadPoints != null) _routeCache[cacheKey] = roadPoints;
    }
    if (!mounted || roadPoints == null) return;
    setState(() {
      _polylines = {
        Polyline(
          polylineId: const PolylineId('tramo'),
          points: roadPoints!,
          color: color,
          width: 4,
        ),
      };
    });
  }

  // ── OSRM road routing ─────────────────────────────────────────

  static const _osrmBase =
      'https://router.project-osrm.org/route/v1/driving';

  Future<List<LatLng>?> _fetchOsrmRoute(List<LatLng> waypoints) async {
    if (waypoints.length < 2) return null;
    final coordStr = waypoints
        .map((p) =>
            '${p.longitude.toStringAsFixed(6)},${p.latitude.toStringAsFixed(6)}')
        .join(';');
    try {
      final uri = Uri.parse(
          '$_osrmBase/$coordStr?geometries=geojson&overview=full');
      final resp =
          await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok') return null;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;
      final geometry =
          (routes[0] as Map<String, dynamic>)['geometry']
              as Map<String, dynamic>;
      final coords = geometry['coordinates'] as List;
      return coords
          .map((c) => LatLng(
              (c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();
    } catch (_) {
      return null; // falls back to straight lines already on screen
    }
  }

  Future<void> _centrarMapa() async {
    if (_markers.isEmpty) return;
    final ctrl = await _mapCtrl.future;
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final m in _markers) {
      final lat = m.position.latitude;
      final lng = m.position.longitude;
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }
    ctrl.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat - 0.01, minLng - 0.01),
        northeast: LatLng(maxLat + 0.01, maxLng + 0.01),
      ),
      60,
    ));
  }

  // ── Helpers ───────────────────────────────────────────────────

  bool _mismaSemana(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _labelSemana(DateTime ws) {
    final fin = ws.add(const Duration(days: 5));
    const abr = ['', 'ene', 'feb', 'mar', 'abr', 'may', 'jun',
                  'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    final startStr = '${ws.day} ${abr[ws.month]}';
    final endStr = ws.month == fin.month
        ? '${fin.day}'
        : '${fin.day} ${abr[fin.month]}';
    return '$startStr – $endStr';
  }

  String _formatFecha(FordDiaRuta dia) {
    final f = dia.fecha;
    if (f == null) return dia.fechaToa;
    const ds = ['', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    const ms = ['', 'ene', 'feb', 'mar', 'abr', 'may', 'jun',
                 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    return '${ds[f.weekday]} ${f.day} ${ms[f.month]}';
  }

  String _formatPesos(double v) {
    final s = v.round().toString();
    final buf = StringBuffer();
    int cnt = 0;
    for (int k = s.length - 1; k >= 0; k--) {
      if (cnt > 0 && cnt % 3 == 0) buf.write('.');
      buf.write(s[k]);
      cnt++;
    }
    return buf.toString().split('').reversed.join();
  }

  String get _mapContextLabel {
    if (_trasladoSeleccionado != null) {
      return '${_trasladoSeleccionado!.desde.label} → ${_trasladoSeleccionado!.hasta.label}';
    }
    if (_diaSeleccionado != null) {
      return _formatFecha(_diaSeleccionado!);
    }
    if (_semanaSeleccionada != null) {
      return _labelSemana(_semanaSeleccionada!);
    }
    return 'Todo el historial';
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.nombreTecnico,
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: _accent),
            onPressed: () { _svc.limpiarCache(); _cargar(); },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : _error != null
              ? _buildError()
              : _rutas.isEmpty
                  ? _buildSinDatos()
                  : Column(children: [
                      _buildMapa(),
                      const Divider(color: _border, height: 1),
                      Expanded(child: _buildListaDias()),
                    ]),
    );
  }

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, color: _accent, size: 48),
            const SizedBox(height: 16),
            const Text('Error al cargar recorridos',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: _textDim, fontSize: 13)),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _cargar, child: const Text('Reintentar')),
          ]),
        ),
      );

  Widget _buildSinDatos() => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.route, color: _textDim, size: 56),
            SizedBox(height: 16),
            Text('Sin recorridos registrados',
                style: TextStyle(color: Colors.white, fontSize: 16)),
          ]),
        ),
      );

  // ── Semana chips (oldest → newest left to right) ──────────────

  // ── Map with context label ────────────────────────────────────

  Widget _buildMapa() {
    return Column(children: [
      // Context label strip
      Container(
        color: _surface,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        child: Row(children: [
          Icon(
            _trasladoSeleccionado != null
                ? Icons.directions
                : _diaSeleccionado != null
                    ? Icons.today
                    : Icons.calendar_view_week,
            color: _accent,
            size: 13,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _mapContextLabel,
              style: const TextStyle(color: _accent, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_diaSeleccionado != null || _trasladoSeleccionado != null)
            GestureDetector(
              onTap: () {
                if (_trasladoSeleccionado != null) {
                  _onTapTraslado(_diaSeleccionado!, _trasladoSeleccionado!);
                } else if (_diaSeleccionado != null) {
                  _onTapDia(_diaSeleccionado!);
                }
              },
              child: const Icon(Icons.close, color: _textDim, size: 14),
            ),
        ]),
      ),
      SizedBox(
        height: 280,
        child: _markers.isNotEmpty
            ? GoogleMap(
                mapType: MapType.normal,
                initialCameraPosition: const CameraPosition(
                    target: LatLng(-33.4569, -70.6483), zoom: 11),
                onMapCreated: (ctrl) {
                  _mapCtrl.complete(ctrl);
                  _centrarMapa();
                },
                markers: _markers,
                polylines: _polylines,
                myLocationEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
              )
            : Container(
                color: _surface,
                child: const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.location_off, color: _textDim, size: 36),
                    SizedBox(height: 8),
                    Text('Sin coordenadas en este período',
                        style: TextStyle(color: _textDim, fontSize: 13)),
                  ]),
                ),
              ),
      ),
    ]);
  }

  // ── List of days ──────────────────────────────────────────────

  Widget _buildListaDias() {
    // Siempre muestra todas las semanas, ordenadas de más reciente a más antigua.
    final todasSemanas = _semanas.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    final items = <_ListItem>[];
    for (final entry in todasSemanas) {
      items.add(_ListItem.header(entry.key, entry.value));
      for (final dia in entry.value) {
        items.add(_ListItem.day(dia));
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (ctx, idx) {
        final item = items[idx];
        return item.isHeader
            ? _buildSemanaHeader(item.weekStart!, item.dias!)
            : _buildDiaCard(item.dia!);
      },
    );
  }

  Widget _buildSemanaHeader(DateTime weekStart, List<FordDiaRuta> dias) {
    final km = dias.fold(0.0, (s, d) => s + d.kmTotal);
    final litros = km / widget.rendimientoKmL;
    final monto = litros * widget.precioLitro;
    final isSelected = _mismaSemana(_semanaSeleccionada, weekStart);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _semanaSeleccionada = weekStart;
            _diaSeleccionado = null;
            _trasladoSeleccionado = null;
          });
          _rebuildMap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? _accent.withValues(alpha: 0.15)
                : _accent.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? _accent
                  : _accent.withValues(alpha: 0.25),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            const Icon(Icons.calendar_view_week, color: _accent, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _labelSemana(weekStart),
                style: const TextStyle(
                    color: _accent, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(
                '${km.toStringAsFixed(1)} km · ${litros.toStringAsFixed(1)} L',
                style: const TextStyle(
                    color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              Text(
                '\$${_formatPesos(monto)} · ${dias.length} días',
                style: const TextStyle(color: _textDim, fontSize: 11),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _buildDiaCard(FordDiaRuta dia) {
    final km = dia.kmTotal;
    final litros = km / widget.rendimientoKmL;
    final monto = litros * widget.precioLitro;
    final isDiaSelected = _diaSeleccionado == dia && _trasladoSeleccionado == null;

    return GestureDetector(
      onTap: () => _onTapDia(dia),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, left: 6),
        decoration: BoxDecoration(
          color: isDiaSelected
              ? _accent.withValues(alpha: 0.06)
              : _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDiaSelected ? _accent : _border,
            width: isDiaSelected ? 1.5 : 1,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Day header (tap = filter map to this day)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                    color: isDiaSelected
                        ? _accent.withValues(alpha: 0.25)
                        : _accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(7)),
                child: Center(
                  child: Text(
                    dia.fecha?.day.toString() ?? '?',
                    style: const TextStyle(
                        color: _accent, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(_formatFecha(dia),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                  Text('${dia.ots.length} OTs · ${dia.traslados.length} tramos',
                      style: const TextStyle(color: _textDim, fontSize: 11)),
                ]),
              ),
              Icon(
                isDiaSelected ? Icons.map : Icons.map_outlined,
                color: isDiaSelected ? _accent : _textDim,
                size: 16,
              ),
            ]),
          ),

          // Traslados list
          if (dia.traslados.isNotEmpty) ...[
            const Divider(height: 1, color: _border),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Column(
                children: dia.traslados
                    .map((t) => _buildTraslado(dia, t))
                    .toList(),
              ),
            ),
          ],

          // Day summary
          const Divider(height: 1, color: _border),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(children: [
              _resumenItem(Icons.route, '${km.toStringAsFixed(1)} km',
                  'recorridos', _accent),
              _resumenItem(Icons.local_gas_station,
                  '${litros.toStringAsFixed(1)} L', 'consumidos', _orange),
              _resumenItem(Icons.payments_outlined,
                  '\$${_formatPesos(monto)}', 'costo día', _green),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _resumenItem(IconData icon, String val, String lbl, Color color) =>
      Expanded(
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(val,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 12)),
            Text(lbl, style: const TextStyle(color: _textDim, fontSize: 9)),
          ]),
        ]),
      );

  Widget _buildTraslado(FordDiaRuta dia, FordTraslado t) {
    final esBase = t.tipoLeg == 'bodega_ida' || t.tipoLeg == 'bodega_vuelta';
    final color = esBase ? _orange : _accent;
    final litros = t.kmOsrm / widget.rendimientoKmL;
    final isSelected = _trasladoSeleccionado == t;

    final kmStr = t.kmOsrm < 1
        ? '${(t.kmOsrm * 1000).toStringAsFixed(0)} m'
        : '${t.kmOsrm.toStringAsFixed(1)} km';
    final litStr = litros < 0.1 ? '< 0.1 L' : '${litros.toStringAsFixed(1)} L';

    return GestureDetector(
      onTap: () => _onTapTraslado(dia, t),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? color.withValues(alpha: 0.4) : Colors.transparent,
          ),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: '${t.desde.label} → ${t.hasta.label}',
                  style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white,
                      fontSize: 11,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500),
                ),
                TextSpan(
                  text: '  ·  $kmStr · $litStr',
                  style: const TextStyle(color: _textDim, fontSize: 10),
                ),
              ]),
            ),
          ),
          Icon(
            Icons.map_outlined,
            size: 12,
            color: isSelected ? color : _textDim.withValues(alpha: 0.5),
          ),
        ]),
      ),
    );
  }
}

class _ListItem {
  final bool isHeader;
  final DateTime? weekStart;
  final List<FordDiaRuta>? dias;
  final FordDiaRuta? dia;

  _ListItem.header(this.weekStart, this.dias)
      : isHeader = true,
        dia = null;

  _ListItem.day(this.dia)
      : isHeader = false,
        weekStart = null,
        dias = null;
}

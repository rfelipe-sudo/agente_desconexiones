import 'dart:math' as math;
import 'dart:ui';

import 'package:agente_desconexiones/services/coverage_calculator.dart';
import 'package:agente_desconexiones/services/ont_wifi_service.dart';

/// Plano de planta + simulación de cobertura sin recorrido del técnico.
class CoverageFloorPlan {
  CoverageFloorPlan({
    required this.tipoPropiedad,
    required this.tamano,
    required this.construccion,
    required this.vecinos5g,
    this.devices = const [],
    this.banda = '5 GHz',
  });

  final String tipoPropiedad;
  final String tamano;
  final String construccion;
  final int vecinos5g;
  final List<OntDevice> devices;
  final String banda;

  static const int gridCols = 48;
  static const int gridRows = 32;

  late final List<FloorRoom> rooms = _buildRooms();
  late final Offset ontCenter = _ontCenter();
  late final List<List<double>> rssiGrid = _simulateGrid();

  List<FloorRoom> _buildRooms() {
    final scale = switch (tamano) {
      'peq' => 0.85,
      'gra' => 1.15,
      _ => 1.0,
    };

    switch (tipoPropiedad) {
      case 'depto':
        return _deptoRooms(scale);
      case 'casa2':
        return _casa2Rooms(scale);
      case 'local':
        return _localRooms(scale);
      default:
        return _casa1Rooms(scale);
    }
  }

  List<FloorRoom> _casa1Rooms(double s) {
    return [
      FloorRoom(id: 'living', label: 'Living', rect: _r(0.04, 0.28, 0.42 * s, 0.44 * s), ontRoom: true),
      FloorRoom(id: 'cocina', label: 'Cocina', rect: _r(0.04, 0.04, 0.42 * s, 0.20 * s)),
      FloorRoom(id: 'dorm1', label: 'Dorm. 1', rect: _r(0.50, 0.04, 0.46 * s, 0.34 * s)),
      FloorRoom(id: 'dorm2', label: 'Dorm. 2', rect: _r(0.50, 0.42, 0.46 * s, 0.30 * s)),
      FloorRoom(id: 'bano', label: 'Baño', rect: _r(0.50, 0.76, 0.22 * s, 0.18 * s)),
      FloorRoom(id: 'pasillo', label: 'Pasillo', rect: _r(0.46, 0.34, 0.06, 0.44 * s)),
    ];
  }

  List<FloorRoom> _casa2Rooms(double s) {
    return [
      FloorRoom(id: 'living', label: 'Living P1', rect: _r(0.04, 0.30, 0.40 * s, 0.40 * s), ontRoom: true),
      FloorRoom(id: 'cocina', label: 'Cocina', rect: _r(0.04, 0.04, 0.40 * s, 0.22 * s)),
      FloorRoom(id: 'dorm1', label: 'Dorm. P1', rect: _r(0.48, 0.04, 0.48 * s, 0.30 * s)),
      FloorRoom(id: 'dorm2', label: 'Dorm. P2', rect: _r(0.48, 0.38, 0.48 * s, 0.28 * s)),
      FloorRoom(id: 'bano', label: 'Baño', rect: _r(0.48, 0.70, 0.24 * s, 0.22 * s)),
      FloorRoom(id: 'escalera', label: 'Escalera', rect: _r(0.04, 0.74, 0.18 * s, 0.20 * s)),
    ];
  }

  List<FloorRoom> _deptoRooms(double s) {
    return [
      FloorRoom(id: 'living', label: 'Living', rect: _r(0.06, 0.36, 0.52 * s, 0.38 * s), ontRoom: true),
      FloorRoom(id: 'cocina', label: 'Cocina', rect: _r(0.06, 0.06, 0.52 * s, 0.26 * s)),
      FloorRoom(id: 'dorm', label: 'Dormitorio', rect: _r(0.62, 0.06, 0.32 * s, 0.38 * s)),
      FloorRoom(id: 'bano', label: 'Baño', rect: _r(0.62, 0.48, 0.32 * s, 0.26 * s)),
    ];
  }

  List<FloorRoom> _localRooms(double s) {
    return [
      FloorRoom(id: 'frente', label: 'Frente', rect: _r(0.04, 0.04, 0.92 * s, 0.38 * s), ontRoom: true),
      FloorRoom(id: 'mostrador', label: 'Mostrador', rect: _r(0.04, 0.46, 0.44 * s, 0.46 * s)),
      FloorRoom(id: 'bodega', label: 'Bodega', rect: _r(0.52, 0.46, 0.44 * s, 0.46 * s)),
    ];
  }

  Rect _r(double x, double y, double w, double h) {
    return Rect.fromLTWH(x.clamp(0.0, 0.94), y.clamp(0.0, 0.94), w, h);
  }

  Offset _ontCenter() {
    final ontRoom = rooms.firstWhere((r) => r.ontRoom, orElse: () => rooms.first);
    return ontRoom.rect.center;
  }

  FloorRoom? roomAt(double nx, double ny) {
    for (final r in rooms) {
      if (r.rect.contains(Offset(nx, ny))) return r;
    }
    return null;
  }

  int _wallsBetween(FloorRoom from, FloorRoom to) {
    if (from.id == to.id) return 0;
    // Pasillo / escalera actúan como conector sin pared extra.
    const connectors = {'pasillo', 'escalera'};
    if (connectors.contains(from.id) || connectors.contains(to.id)) return 1;
    return 2;
  }

  double _wallPenalty() {
    return switch (construccion) {
      'Madera' => 6.0,
      'Hormigón' => 14.0,
      _ => 10.0,
    };
  }

  List<List<double>> _simulateGrid() {
    final n = CoverageCalculator.factorMaterial[construccion] ?? 2.4;
    final radios = CoverageCalculator.radiosEfectivos(banda, construccion, vecinos5g);
    final maxDist = radios[1] * 1.15;
    final ontRoom = rooms.firstWhere((r) => r.ontRoom, orElse: () => rooms.first);
    final refRssi = banda == '5 GHz' ? -38.0 : -35.0;
    final wallPen = _wallPenalty();
    final rfPen = (1 - CoverageCalculator.factorRuido(vecinos5g)) * 12;

    final grid = List.generate(
      gridRows,
      (_) => List<double>.filled(gridCols, -95.0),
    );

    for (var row = 0; row < gridRows; row++) {
      for (var col = 0; col < gridCols; col++) {
        final nx = (col + 0.5) / gridCols;
        final ny = (row + 0.5) / gridRows;
        final cell = Offset(nx, ny);
        final targetRoom = roomAt(nx, ny);
        if (targetRoom == null) continue;

        final distM = _distMeters(cell, ontCenter, maxDist);
        final walls = _wallsBetween(ontRoom, targetRoom);
        var rssi = refRssi -
            20 * math.log(distM.clamp(0.8, maxDist)) / math.ln10 * n -
            walls * wallPen -
            rfPen;
        if (banda == '5 GHz' && walls > 0) rssi -= 3;

        grid[row][col] = rssi.clamp(-92.0, -30.0);
      }
    }

    _blendDeviceAnchors(grid, n, maxDist);
    return grid;
  }

  double _distMeters(Offset a, Offset b, double maxDist) {
    final dx = (a.dx - b.dx) * 12;
    final dy = (a.dy - b.dy) * 8;
    return math.sqrt(dx * dx + dy * dy).clamp(0.5, maxDist);
  }

  void _blendDeviceAnchors(List<List<double>> grid, double n, double maxDist) {
    final wifi = devices.where((d) => !d.esCableado && d.rssiKnown).toList();
    if (wifi.isEmpty) return;

    final roomTargets = <String, List<OntDevice>>{};
    for (final d in wifi) {
      final dist = d.distanciaMetros(n).clamp(0.5, maxDist);
      FloorRoom? best;
      var bestErr = double.infinity;
      for (final room in rooms) {
        final err = ( _distMeters(room.rect.center, ontCenter, maxDist) - dist).abs();
        if (err < bestErr) {
          bestErr = err;
          best = room;
        }
      }
      if (best != null) {
        roomTargets.putIfAbsent(best.id, () => []).add(d);
      }
    }

    for (final entry in roomTargets.entries) {
      final room = rooms.firstWhere((r) => r.id == entry.key);
      final avg = entry.value.map((d) => d.rssi).reduce((a, b) => a + b) / entry.value.length;
      final cx = (room.rect.center.dx * gridCols).floor().clamp(0, gridCols - 1);
      final cy = (room.rect.center.dy * gridRows).floor().clamp(0, gridRows - 1);
      const radius = 4;
      for (var dy = -radius; dy <= radius; dy++) {
        for (var dx = -radius; dx <= radius; dx++) {
          final row = cy + dy;
          final col = cx + dx;
          if (row < 0 || row >= gridRows || col < 0 || col >= gridCols) continue;
          if (!room.rect.contains(Offset((col + 0.5) / gridCols, (row + 0.5) / gridRows))) {
            continue;
          }
          final w = math.exp(-(dx * dx + dy * dy) / (radius * radius * 0.45));
          grid[row][col] = grid[row][col] * (1 - w) + avg * w;
        }
      }
    }
  }

  static Color colorForRssi(double rssi) {
    if (rssi >= -60) return const Color(0xFF10B981);
    if (rssi >= -70) return const Color(0xFFF59E0B);
    if (rssi >= -75) return const Color(0xFFFF6B35);
    return const Color(0xFFEF4444);
  }

  String get subtitulo {
    final prop = switch (tipoPropiedad) {
      'casa2' => 'Casa 2 pisos',
      'depto' => 'Departamento',
      'local' => 'Local comercial',
      _ => 'Casa 1 piso',
    };
    final tam = switch (tamano) {
      'peq' => 'pequeño',
      'gra' => 'grande',
      _ => 'mediano',
    };
    return '$prop $tam · $construccion · estimado $banda (sin recorrido)';
  }
}

class FloorRoom {
  const FloorRoom({
    required this.id,
    required this.label,
    required this.rect,
    this.ontRoom = false,
  });

  final String id;
  final String label;
  final Rect rect;
  final bool ontRoom;
}

class FordOt {
  final String orden;
  final String direccion;
  final String ciudad;
  final String zona;
  final double? coordLat; // coord_y = latitude
  final double? coordLng; // coord_x = longitude
  final String estado;
  final String inicio;
  final String fin;
  final double inicioMin;
  final double finMin;

  FordOt({
    required this.orden,
    required this.direccion,
    required this.ciudad,
    required this.zona,
    this.coordLat,
    this.coordLng,
    required this.estado,
    required this.inicio,
    required this.fin,
    required this.inicioMin,
    required this.finMin,
  });

  bool get tieneCoords => coordLat != null && coordLng != null;

  factory FordOt.fromJson(Map<String, dynamic> j) => FordOt(
        orden: j['orden']?.toString() ?? '',
        direccion: j['direccion']?.toString() ?? '',
        ciudad: j['ciudad']?.toString() ?? '',
        zona: j['zona']?.toString() ?? '',
        coordLat: double.tryParse(j['coord_y']?.toString() ?? ''),
        coordLng: double.tryParse(j['coord_x']?.toString() ?? ''),
        estado: j['estado']?.toString() ?? '',
        inicio: j['inicio']?.toString() ?? '',
        fin: j['fin']?.toString() ?? '',
        inicioMin: (j['inicio_min'] as num?)?.toDouble() ?? 0,
        finMin: (j['fin_min'] as num?)?.toDouble() ?? 0,
      );
}

/// Extremo de un traslado (desde o hasta).
class FordPunto {
  final String orden;
  final String direccion;
  final String ciudad;
  final String zona;
  final String inicio;
  final String fin;
  final String estado;

  const FordPunto({
    required this.orden,
    required this.direccion,
    required this.ciudad,
    required this.zona,
    required this.inicio,
    required this.fin,
    required this.estado,
  });

  bool get esBodega => orden == 'Bodega';

  String get label =>
      esBodega ? 'Base (Lo Espejo)' : 'OT $orden';

  String get direccionCorta {
    if (esBodega) return 'Avda Lo Espejo 1565';
    if (direccion.isNotEmpty) return _titleCase(direccion);
    return orden;
  }

  static String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s
        .toLowerCase()
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  factory FordPunto.fromJson(Map<String, dynamic> j) => FordPunto(
        orden: j['orden']?.toString() ?? '',
        direccion: j['direccion']?.toString() ?? '',
        ciudad: j['ciudad']?.toString() ?? '',
        zona: j['zona']?.toString() ?? '',
        inicio: j['inicio']?.toString() ?? '',
        fin: j['fin']?.toString() ?? '',
        estado: j['estado']?.toString() ?? '',
      );
}

class FordTraslado {
  final String tipoLeg;
  final double kmOsrm;
  final double? duracionMin;
  final int tramo;
  final FordPunto desde;
  final FordPunto hasta;

  const FordTraslado({
    required this.tipoLeg,
    required this.kmOsrm,
    this.duracionMin,
    required this.tramo,
    required this.desde,
    required this.hasta,
  });

  factory FordTraslado.fromJson(Map<String, dynamic> j) => FordTraslado(
        tipoLeg: j['tipo_leg']?.toString() ?? '',
        kmOsrm: (j['km_osrm'] as num?)?.toDouble() ?? 0,
        duracionMin: (j['duracion_ruta_min'] as num?)?.toDouble(),
        tramo: (j['tramo'] as num?)?.toInt() ?? 0,
        desde: FordPunto.fromJson(j['desde'] as Map<String, dynamic>? ?? {}),
        hasta: FordPunto.fromJson(j['hasta'] as Map<String, dynamic>? ?? {}),
      );
}

class FordDiaRuta {
  final String rut;
  final String fechaToa; // "dd/mm/yy"
  final String mes;      // "yyyy-mm"
  final String? patente;
  final String? tecnico;
  final double kmTotal;
  final double kmBodegaIda;
  final double kmBodegaVuelta;
  final double kmEntreOt;
  final double tiempoProductivoMin;
  final double tiempoTrasladoMin;
  final List<FordOt> ots;
  final List<FordTraslado> traslados;

  const FordDiaRuta({
    required this.rut,
    required this.fechaToa,
    required this.mes,
    this.patente,
    this.tecnico,
    required this.kmTotal,
    required this.kmBodegaIda,
    required this.kmBodegaVuelta,
    required this.kmEntreOt,
    required this.tiempoProductivoMin,
    required this.tiempoTrasladoMin,
    required this.ots,
    required this.traslados,
  });

  DateTime? get fecha {
    try {
      final p = fechaToa.split('/');
      if (p.length != 3) return null;
      return DateTime(2000 + int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
    } catch (_) {
      return null;
    }
  }

  /// Monday of the ISO week containing this day.
  DateTime? get semanaISO {
    final f = fecha;
    if (f == null) return null;
    return DateTime(f.year, f.month, f.day - (f.weekday - 1));
  }

  factory FordDiaRuta.fromJson(Map<String, dynamic> j) {
    final p = j['payload'] as Map<String, dynamic>? ?? {};
    return FordDiaRuta(
      rut: j['rut']?.toString() ?? '',
      fechaToa: j['fecha_toa']?.toString() ?? '',
      mes: j['mes']?.toString() ?? '',
      patente: p['patente']?.toString(),
      tecnico: p['tecnico']?.toString(),
      kmTotal: (p['km_osrm_asignado'] as num?)?.toDouble() ?? 0,
      kmBodegaIda: (p['km_bodega_ida'] as num?)?.toDouble() ?? 0,
      kmBodegaVuelta: (p['km_bodega_vuelta'] as num?)?.toDouble() ?? 0,
      kmEntreOt: (p['km_entre_ot'] as num?)?.toDouble() ?? 0,
      tiempoProductivoMin: (p['tiempo_productivo_min'] as num?)?.toDouble() ?? 0,
      tiempoTrasladoMin: (p['tiempo_traslado_min'] as num?)?.toDouble() ?? 0,
      ots: (p['ots'] as List? ?? [])
          .map((o) => FordOt.fromJson(o as Map<String, dynamic>))
          .toList(),
      traslados: (p['traslados'] as List? ?? [])
          .map((t) => FordTraslado.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }
}

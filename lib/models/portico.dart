// ============================================================================
// MODELO: PÓRTICO TAG
// ============================================================================

class Portico {
  final String id;
  final String codigo;
  final String nombre;
  final String autopista;
  final String sentido;
  final double latitud;
  final double longitud;
  final int tarifaTbfp;
  final int tarifaTbp;
  final int tarifaTs;
  final bool activo;

  Portico({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.autopista,
    required this.sentido,
    required this.latitud,
    required this.longitud,
    required this.tarifaTbfp,
    required this.tarifaTbp,
    required this.tarifaTs,
    required this.activo,
  });

  factory Portico.fromJson(Map<String, dynamic> json) {
    return Portico(
      id: json['id']?.toString() ?? '',
      codigo: json['codigo']?.toString() ?? '',
      nombre: json['nombre']?.toString() ?? '',
      autopista: json['autopista']?.toString() ?? '',
      sentido: json['sentido']?.toString() ?? '',
      latitud: (json['latitud'] as num?)?.toDouble() ?? 0.0,
      longitud: (json['longitud'] as num?)?.toDouble() ?? 0.0,
      tarifaTbfp: (json['tarifa_tbfp'] as num?)?.toInt() ?? 0,
      tarifaTbp: (json['tarifa_tbp'] as num?)?.toInt() ?? 0,
      tarifaTs: (json['tarifa_ts'] as num?)?.toInt() ?? 0,
      activo: json['activo'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'codigo': codigo,
      'nombre': nombre,
      'autopista': autopista,
      'sentido': sentido,
      'latitud': latitud,
      'longitud': longitud,
      'tarifa_tbfp': tarifaTbfp,
      'tarifa_tbp': tarifaTbp,
      'tarifa_ts': tarifaTs,
      'activo': activo,
    };
  }
}














class PasoTag {
  final String id;
  final DateTime fechaPaso;
  final String porticoNombre;
  final String autopista;
  final String tipoTarifa;
  final int tarifaCobrada;

  PasoTag({
    required this.id,
    required this.fechaPaso,
    required this.porticoNombre,
    required this.autopista,
    required this.tipoTarifa,
    required this.tarifaCobrada,
  });

  factory PasoTag.fromJson(Map<String, dynamic> json) {
    return PasoTag(
      id: json['id']?.toString() ?? '',
      fechaPaso: DateTime.parse(json['fecha_paso'] ?? DateTime.now().toIso8601String()),
      porticoNombre: json['portico_nombre']?.toString() ?? '',
      autopista: json['autopista']?.toString() ?? '',
      tipoTarifa: json['tipo_tarifa']?.toString() ?? 'ts',
      tarifaCobrada: (json['tarifa_cobrada'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fecha_paso': fechaPaso.toIso8601String(),
      'portico_nombre': porticoNombre,
      'autopista': autopista,
      'tipo_tarifa': tipoTarifa,
      'tarifa_cobrada': tarifaCobrada,
    };
  }
}





















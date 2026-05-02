class AlertaFraude {
  final String id;
  final String tipo;
  final String ot;
  final String tecnicoId;
  final String nombreTecnico;
  final int pasosRealizados;
  final double distanciaRecorrida;
  final List<String> razonesFallo;
  final DateTime timestamp;
  final String estado; // "pendiente", "revisada", "descartada"
  final double? latitud;
  final double? longitud;

  AlertaFraude({
    required this.id,
    required this.tipo,
    required this.ot,
    required this.tecnicoId,
    required this.nombreTecnico,
    required this.pasosRealizados,
    required this.distanciaRecorrida,
    required this.razonesFallo,
    required this.timestamp,
    this.estado = "pendiente",
    this.latitud,
    this.longitud,
  });

  factory AlertaFraude.fromJson(Map<String, dynamic> json) {
    // Manejar timestamp desde Supabase (created_at) o timestamp directo
    DateTime timestamp;
    if (json['created_at'] != null) {
      timestamp = DateTime.parse(json['created_at']);
    } else if (json['timestamp'] != null) {
      timestamp = DateTime.parse(json['timestamp']);
    } else {
      timestamp = DateTime.now();
    }

    return AlertaFraude(
      id: json['id']?.toString() ?? '',
      tipo: json['tipo'] ?? 'intento_sin_moradores_fraudulento',
      ot: json['ot'] ?? '',
      tecnicoId: json['tecnico_id'] ?? '',
      nombreTecnico: json['nombre_tecnico'] ?? '',
      pasosRealizados: json['pasos_realizados'] ?? 0,
      distanciaRecorrida: (json['distancia_recorrida'] as num?)?.toDouble() ?? 0,
      razonesFallo: List<String>.from(json['razones_fallo'] ?? []),
      timestamp: timestamp,
      estado: json['estado'] ?? 'pendiente',
      latitud: (json['latitud'] as num?)?.toDouble(),
      longitud: (json['longitud'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'tipo': tipo,
        'ot': ot,
        'tecnico_id': tecnicoId,
        'nombre_tecnico': nombreTecnico,
        'pasos_realizados': pasosRealizados,
        'distancia_recorrida': distanciaRecorrida,
        'razones_fallo': razonesFallo,
        'timestamp': timestamp.toIso8601String(),
        'estado': estado,
        'latitud': latitud,
        'longitud': longitud,
      };

  AlertaFraude copyWith({
    String? id,
    String? tipo,
    String? ot,
    String? tecnicoId,
    String? nombreTecnico,
    int? pasosRealizados,
    double? distanciaRecorrida,
    List<String>? razonesFallo,
    DateTime? timestamp,
    String? estado,
    double? latitud,
    double? longitud,
  }) {
    return AlertaFraude(
      id: id ?? this.id,
      tipo: tipo ?? this.tipo,
      ot: ot ?? this.ot,
      tecnicoId: tecnicoId ?? this.tecnicoId,
      nombreTecnico: nombreTecnico ?? this.nombreTecnico,
      pasosRealizados: pasosRealizados ?? this.pasosRealizados,
      distanciaRecorrida: distanciaRecorrida ?? this.distanciaRecorrida,
      razonesFallo: razonesFallo ?? this.razonesFallo,
      timestamp: timestamp ?? this.timestamp,
      estado: estado ?? this.estado,
      latitud: latitud ?? this.latitud,
      longitud: longitud ?? this.longitud,
    );
  }
}


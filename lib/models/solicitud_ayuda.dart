/// Modelo para solicitud de ayuda en terreno
class SolicitudAyuda {
  final String ticketId;
  final TipoAyuda tipo;
  final String rutTecnico;
  final String tecnicoNombre;
  final double latTecnico;
  final double lngTecnico;
  final DateTime fechaCreacion;
  final EstadoSolicitud estado;
  final String? rutSupervisor;
  final String? supervisorNombre;
  final double? latSupervisor;
  final double? lngSupervisor;
  final double? distanciaKm;
  final int? tiempoExtraMinutos;
  final String? respuestaMensaje;

  SolicitudAyuda({
    required this.ticketId,
    required this.tipo,
    required this.rutTecnico,
    required this.tecnicoNombre,
    required this.latTecnico,
    required this.lngTecnico,
    required this.fechaCreacion,
    required this.estado,
    this.rutSupervisor,
    this.supervisorNombre,
    this.latSupervisor,
    this.lngSupervisor,
    this.distanciaKm,
    this.tiempoExtraMinutos,
    this.respuestaMensaje,
  });

  factory SolicitudAyuda.fromJson(Map<String, dynamic> json) {
    return SolicitudAyuda(
      ticketId: json['ticket_id'] as String? ?? '',
      tipo: TipoAyuda.values.firstWhere(
        (e) => e.value == json['tipo'],
        orElse: () => TipoAyuda.ducto,
      ),
      rutTecnico: json['rut_tecnico'] as String? ?? '',
      tecnicoNombre: json['nombre_tecnico'] as String? ?? '',
      latTecnico: (json['lat_tecnico'] as num?)?.toDouble() ?? 0.0,
      lngTecnico: (json['lng_tecnico'] as num?)?.toDouble() ?? 0.0,
      fechaCreacion: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      estado: EstadoSolicitud.values.firstWhere(
        (e) => e.value == json['estado'],
        orElse: () => EstadoSolicitud.pendiente,
      ),
      rutSupervisor: json['rut_supervisor'] as String?,
      supervisorNombre: json['nombre_supervisor'] as String?,
      latSupervisor: (json['lat_supervisor'] as num?)?.toDouble(),
      lngSupervisor: (json['lng_supervisor'] as num?)?.toDouble(),
      distanciaKm: (json['distancia_km'] as num?)?.toDouble(),
      tiempoExtraMinutos: json['tiempo_extra_minutos'] as int?,
      respuestaMensaje: json['respuesta_mensaje'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ticket_id': ticketId,
      'tipo': tipo.value,
      'rut_tecnico': rutTecnico,
      'nombre_tecnico': tecnicoNombre,
      'lat_tecnico': latTecnico,
      'lng_tecnico': lngTecnico,
      'estado': estado.value,
      'rut_supervisor': rutSupervisor,
      'nombre_supervisor': supervisorNombre,
      'lat_supervisor': latSupervisor,
      'lng_supervisor': lngSupervisor,
      'distancia_km': distanciaKm,
      'tiempo_extra_minutos': tiempoExtraMinutos,
      'respuesta_mensaje': respuestaMensaje,
    };
  }

  SolicitudAyuda copyWith({
    String? ticketId,
    TipoAyuda? tipo,
    String? rutTecnico,
    String? tecnicoNombre,
    double? latTecnico,
    double? lngTecnico,
    DateTime? fechaCreacion,
    EstadoSolicitud? estado,
    String? rutSupervisor,
    String? supervisorNombre,
    double? latSupervisor,
    double? lngSupervisor,
    double? distanciaKm,
    int? tiempoExtraMinutos,
    String? respuestaMensaje,
  }) {
    return SolicitudAyuda(
      ticketId: ticketId ?? this.ticketId,
      tipo: tipo ?? this.tipo,
      rutTecnico: rutTecnico ?? this.rutTecnico,
      tecnicoNombre: tecnicoNombre ?? this.tecnicoNombre,
      latTecnico: latTecnico ?? this.latTecnico,
      lngTecnico: lngTecnico ?? this.lngTecnico,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
      estado: estado ?? this.estado,
      rutSupervisor: rutSupervisor ?? this.rutSupervisor,
      supervisorNombre: supervisorNombre ?? this.supervisorNombre,
      latSupervisor: latSupervisor ?? this.latSupervisor,
      lngSupervisor: lngSupervisor ?? this.lngSupervisor,
      distanciaKm: distanciaKm ?? this.distanciaKm,
      tiempoExtraMinutos: tiempoExtraMinutos ?? this.tiempoExtraMinutos,
      respuestaMensaje: respuestaMensaje ?? this.respuestaMensaje,
    );
  }

  /// Cerrada definitivamente. El técnico vuelve al menú.
  bool get estaResuelta =>
      estado == EstadoSolicitud.rechazada ||
      estado == EstadoSolicitud.cancelada ||
      estado == EstadoSolicitud.completada;

  /// Supervisor asignado y en camino. El técnico debe seguir en la vista de tracking.
  bool get supervisorEnCamino =>
      estado == EstadoSolicitud.aceptada ||
      estado == EstadoSolicitud.aceptadaConTiempo;

  /// Solicitud activa (técnico esperando o supervisor en camino).
  bool get estaActiva =>
      estado == EstadoSolicitud.pendiente ||
      estado == EstadoSolicitud.aceptada ||
      estado == EstadoSolicitud.aceptadaConTiempo;
}


enum TipoAyuda {
  zonaRoja('zona_roja'),
  crucePeligroso('cruce_peligroso'),
  ducto('ducto'),
  fusion('fusion'),
  altura('altura');

  final String value;
  const TipoAyuda(this.value);

  String get displayName {
    switch (this) {
      case TipoAyuda.zonaRoja:
        return 'Zona Roja';
      case TipoAyuda.crucePeligroso:
        return 'Cruce Peligroso';
      case TipoAyuda.ducto:
        return 'Ducto Obstruido';
      case TipoAyuda.fusion:
        return 'Necesito Fusionar';
      case TipoAyuda.altura:
        return 'Trabajo en Altura';
    }
  }

  String get descripcion {
    switch (this) {
      case TipoAyuda.zonaRoja:
        return 'Requiero apoyo por seguridad en zona de riesgo';
      case TipoAyuda.crucePeligroso:
        return 'Cruce de calle o vía de alto tráfico peligroso';
      case TipoAyuda.ducto:
        return 'Ducto bloqueado u obstruido que impide el trabajo';
      case TipoAyuda.fusion:
        return 'Necesito un técnico con equipo de fusión de fibra';
      case TipoAyuda.altura:
        return 'Trabajo en poste o altura que requiere asistencia';
    }
  }
}

enum EstadoSolicitud {
  pendiente('pendiente'),
  aceptada('aceptada'),
  rechazada('rechazada'),
  aceptadaConTiempo('aceptada_con_tiempo'),
  cancelada('cancelada'),
  completada('completada');

  final String value;
  const EstadoSolicitud(this.value);

  String get displayName {
    switch (this) {
      case EstadoSolicitud.pendiente:
        return 'Pendiente';
      case EstadoSolicitud.aceptada:
        return 'Aceptada';
      case EstadoSolicitud.rechazada:
        return 'Rechazada';
      case EstadoSolicitud.aceptadaConTiempo:
        return 'Aceptada con demora';
      case EstadoSolicitud.cancelada:
        return 'Cancelada';
      case EstadoSolicitud.completada:
        return 'Completada';
    }
  }
}

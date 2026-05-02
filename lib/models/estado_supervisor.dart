/// Modelo para estado de actividad del supervisor
class EstadoSupervisor {
  final String rutSupervisor;
  final String? nombreSupervisor;
  final String actividad;
  final DateTime? actividadDesde;
  final String? ticketIdActivo;
  final String? rutTecnicoActivo;
  final String? nombreTecnicoActivo;
  final String? tipoAyudaActivo;
  final double? lat;
  final double? lng;
  final DateTime? ubicacionAt;
  final DateTime? updatedAt;

  EstadoSupervisor({
    required this.rutSupervisor,
    this.nombreSupervisor,
    required this.actividad,
    this.actividadDesde,
    this.ticketIdActivo,
    this.rutTecnicoActivo,
    this.nombreTecnicoActivo,
    this.tipoAyudaActivo,
    this.lat,
    this.lng,
    this.ubicacionAt,
    this.updatedAt,
  });

  factory EstadoSupervisor.fromJson(Map<String, dynamic> json) {
    return EstadoSupervisor(
      rutSupervisor: json['rut_supervisor'] as String? ?? '',
      nombreSupervisor: json['nombre_supervisor'] as String?,
      actividad: json['actividad'] as String? ?? 'sin_actividad',
      actividadDesde: json['actividad_desde'] != null
          ? DateTime.parse(json['actividad_desde'] as String)
          : null,
      ticketIdActivo: json['ticket_id_activo'] as String?,
      rutTecnicoActivo: json['rut_tecnico_activo'] as String?,
      nombreTecnicoActivo: json['nombre_tecnico_activo'] as String?,
      tipoAyudaActivo: json['tipo_ayuda_activo'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      ubicacionAt: json['ubicacion_at'] != null
          ? DateTime.parse(json['ubicacion_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  bool get estaActivo =>
      actividad != 'sin_actividad' && actividad.isNotEmpty;

  bool get esMovimientoMaterial =>
      tipoAyudaActivo == 'movimiento_material';
}

/// Actividades disponibles para el supervisor
/// Valores deben coincidir con CHECK de estado_supervisor.actividad
enum ActividadSupervisor {
  verificandoAsistencia('Verificando asistencia', 'verificando_asistencia'),
  reunionEquipo('Reunión de equipo', 'reunion_equipo'),
  movimientoMateriales('Movimiento de materiales', 'movimiento_material'),
  colacion('Colación', 'colacion'),
  desvinculacion('Desvinculación', 'desvinculacion'),
  reunionJefatura('Reunión con jefatura', 'reunion_jefatura');

  final String displayName;
  final String valorSupabase;
  const ActividadSupervisor(this.displayName, this.valorSupabase);
}

import 'dart:convert';

class CreavoxOrden {
  final String ordenDeTrabajo;
  final String nombreCompletoCliente;
  final String direccion;
  final String zonaDeTrabajo;
  final String tipoActividad;
  final double coordX;
  final double coordY;
  final String telefonoInternacional;
  final String? rutTecnico;
  final String? estado;
  final DateTime? fechaAsignacion;

  CreavoxOrden({
    required this.ordenDeTrabajo,
    required this.nombreCompletoCliente,
    required this.direccion,
    required this.zonaDeTrabajo,
    required this.tipoActividad,
    required this.coordX,
    required this.coordY,
    required this.telefonoInternacional,
    this.rutTecnico,
    this.estado,
    this.fechaAsignacion,
  });

  static double _parseCoord(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  Map<String, dynamic> toJson() => {
        'orden_de_trabajo': ordenDeTrabajo,
        'nombre_completo_cliente': nombreCompletoCliente,
        'direccion': direccion,
        'zona_de_trabajo': zonaDeTrabajo,
        'tipo_actividad': tipoActividad,
        'coord_x': coordX,
        'coord_y': coordY,
        'telefono_internacional': telefonoInternacional,
        'Rut_tecnico': rutTecnico,
        'estado': estado,
        'fecha_asignacion': fechaAsignacion?.toIso8601String(),
      };

  String toJsonString() => jsonEncode(toJson());

  factory CreavoxOrden.fromJsonString(String s) {
    final json = jsonDecode(s) as Map<String, dynamic>;
    return CreavoxOrden(
      ordenDeTrabajo: json['orden_de_trabajo'] as String? ?? '',
      nombreCompletoCliente: json['nombre_completo_cliente'] as String? ?? '',
      direccion: json['direccion'] as String? ?? '',
      zonaDeTrabajo: json['zona_de_trabajo'] as String? ?? '',
      tipoActividad: json['tipo_actividad'] as String? ?? '',
      coordX: _parseCoord(json['coord_x']),
      coordY: _parseCoord(json['coord_y']),
      telefonoInternacional: json['telefono_internacional'] as String? ?? '',
      rutTecnico: json['Rut_tecnico'] as String?,
      estado: json['estado'] as String?,
      fechaAsignacion: json['fecha_asignacion'] != null
          ? DateTime.tryParse(json['fecha_asignacion'])
          : null,
    );
  }

  bool get tieneCoordenadas => coordX != 0.0 && coordY != 0.0;
}

import 'dart:convert';

class CreavoxTecnico {
  final String rutTecnico;
  final String nombreTecnico;
  final String nombreSupervisor;
  final String rutSupervisor;
  final bool active;

  CreavoxTecnico({
    required this.rutTecnico,
    required this.nombreTecnico,
    required this.nombreSupervisor,
    required this.rutSupervisor,
    required this.active,
  });

  factory CreavoxTecnico.fromJson(Map<String, dynamic> json) {
    return CreavoxTecnico(
      rutTecnico: json['rut_tecnico']?.toString() ?? '',
      nombreTecnico: json['nombre_tecnico']?.toString() ?? '',
      nombreSupervisor: json['nombre_supervisor']?.toString() ?? '',
      rutSupervisor: json['rut_supervisor']?.toString() ?? '',
      active: json['active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'rut_tecnico': rutTecnico,
        'nombre_tecnico': nombreTecnico,
        'nombre_supervisor': nombreSupervisor,
        'rut_supervisor': rutSupervisor,
        'active': active,
      };

  String toJsonString() => jsonEncode(toJson());

  factory CreavoxTecnico.fromJsonString(String s) =>
      CreavoxTecnico.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

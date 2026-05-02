/// Modelo que representa un usuario de la aplicación
class Usuario {
  final String id;
  final String nombre;
  final String telefono;
  final String email;
  final RolUsuario rol;
  final String? fcmToken;
  final bool activo;
  final List<String>? zonasCto; // CTOs asignadas al técnico/supervisor
  final DateTime? ultimaConexion;

  Usuario({
    required this.id,
    required this.nombre,
    required this.telefono,
    required this.email,
    required this.rol,
    this.fcmToken,
    this.activo = true,
    this.zonasCto,
    this.ultimaConexion,
  });

  factory Usuario.fromJson(Map<String, dynamic> json) {
    return Usuario(
      id: json['id'] ?? '',
      nombre: json['nombre'] ?? '',
      telefono: json['telefono'] ?? '',
      email: json['email'] ?? '',
      rol: RolUsuario.fromString(json['rol'] ?? 'tecnico'),
      fcmToken: json['fcm_token'],
      activo: json['activo'] ?? true,
      zonasCto: json['zonas_cto'] != null 
          ? List<String>.from(json['zonas_cto']) 
          : null,
      ultimaConexion: json['ultima_conexion'] != null
          ? DateTime.parse(json['ultima_conexion'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'telefono': telefono,
      'email': email,
      'rol': rol.name,
      'fcm_token': fcmToken,
      'activo': activo,
      'zonas_cto': zonasCto,
      'ultima_conexion': ultimaConexion?.toIso8601String(),
    };
  }

  Usuario copyWith({
    String? id,
    String? nombre,
    String? telefono,
    String? email,
    RolUsuario? rol,
    String? fcmToken,
    bool? activo,
    List<String>? zonasCto,
    DateTime? ultimaConexion,
  }) {
    return Usuario(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      telefono: telefono ?? this.telefono,
      email: email ?? this.email,
      rol: rol ?? this.rol,
      fcmToken: fcmToken ?? this.fcmToken,
      activo: activo ?? this.activo,
      zonasCto: zonasCto ?? this.zonasCto,
      ultimaConexion: ultimaConexion ?? this.ultimaConexion,
    );
  }

  bool get esTecnico => rol == RolUsuario.tecnico;
  bool get esSupervisor => rol == RolUsuario.supervisor;
}

/// Roles de usuario en el sistema
enum RolUsuario {
  tecnico,
  supervisor;

  static RolUsuario fromString(String value) {
    switch (value.toLowerCase()) {
      case 'supervisor':
      case 'ito':
        return RolUsuario.supervisor;
      case 'tecnico':
      default:
        return RolUsuario.tecnico;
    }
  }

  String get displayName {
    switch (this) {
      case RolUsuario.tecnico:
        return 'Técnico';
      case RolUsuario.supervisor:
        return 'Supervisor';
    }
  }
}


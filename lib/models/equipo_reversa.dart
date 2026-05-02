class EquipoReversa {
  final String? id;
  final String tecnicoRut;
  final String tecnicoNombre;
  final String serial;
  final String tipoEquipo;
  final String ot;
  final String? cliente;
  final String? direccion;
  final DateTime? fechaDesinstalacion;
  final DateTime? fechaEntrega;
  final String estado;
  final String? bodegaRecibe;
  final String? notas;
  final String? descripcion;

  EquipoReversa({
    this.id,
    required this.tecnicoRut,
    required this.tecnicoNombre,
    required this.serial,
    required this.tipoEquipo,
    required this.ot,
    this.cliente,
    this.direccion,
    this.fechaDesinstalacion,
    this.fechaEntrega,
    required this.estado,
    this.bodegaRecibe,
    this.notas,
    this.descripcion,
  });

  factory EquipoReversa.fromJson(Map<String, dynamic> json) {
    print('🔍 [EquipoReversa] Parseando: $json');

    return EquipoReversa(
      id: json['id']?.toString(),
      tecnicoRut: json['tecnico_rut']?.toString() ?? '',
      tecnicoNombre: json['tecnico_nombre']?.toString() ?? '',
      serial: json['serial']?.toString() ?? '',
      tipoEquipo: json['tipo_equipo']?.toString() ?? '',
      ot: json['ot']?.toString() ?? '',
      cliente: json['cliente']?.toString(),
      direccion: json['direccion']?.toString(),
      fechaDesinstalacion: _parseDate(json['fecha_desinstalacion']),
      fechaEntrega: _parseDate(json['fecha_entrega']),
      estado: json['estado']?.toString() ?? 'pendiente',
      bodegaRecibe: json['bodega_recibe']?.toString(),
      notas: json['notas']?.toString(),
      descripcion: json['descripcion']?.toString(),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tecnico_rut': tecnicoRut,
      'tecnico_nombre': tecnicoNombre,
      'serial': serial,
      'tipo_equipo': tipoEquipo,
      'ot': ot,
      'cliente': cliente,
      'direccion': direccion,
      'fecha_desinstalacion': fechaDesinstalacion?.toIso8601String().split('T')[0],
      'fecha_entrega': fechaEntrega?.toIso8601String().split('T')[0],
      'estado': estado,
      'bodega_recibe': bodegaRecibe,
      'notas': notas,
      'descripcion': descripcion,
    };
  }
}

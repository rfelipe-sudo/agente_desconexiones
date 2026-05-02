/// Modelo para los niveles de cada puerto de la CTO
class NivelPuerto {
  final int puerto;
  final double? consulta1;  // Valor inicial (puede ser null si no hay medición)
  final double? consulta2;  // Valor final (puede ser null si no se ha medido)
  
  NivelPuerto({
    required this.puerto,
    this.consulta1,
    this.consulta2,
  });
  
  /// Diferencia entre consulta1 y consulta2
  double get diferencia {
    if (consulta1 == null && consulta2 == null) return 0;
    if (consulta1 == null) return consulta2 ?? 0;
    if (consulta2 == null) return (consulta1 ?? 0).abs();
    return ((consulta2 ?? 0) - (consulta1 ?? 0)).abs();
  }
  
  /// Indica si el puerto perdió señal
  bool get senalPerdida {
    if (consulta1 != null && consulta2 == null) return true;
    if (consulta1 != null && consulta2 != null && diferencia > 10) return true;
    return false;
  }
  
  /// Estado del puerto
  String get estadoTexto {
    if (senalPerdida) return 'Señal perdida';
    return 'OK';
  }
  
  factory NivelPuerto.fromJson(Map<String, dynamic> json) {
    return NivelPuerto(
      puerto: json['puerto'] ?? 0,
      consulta1: json['consulta1']?.toDouble(),
      consulta2: json['consulta2']?.toDouble(),
    );
  }
  
  Map<String, dynamic> toJson() => {
    'puerto': puerto,
    'consulta1': consulta1,
    'consulta2': consulta2,
  };
}

/// Modelo que representa una alerta de desconexión de fibra óptica
class Alerta {
  final String id;
  final String nombreTecnico;
  final String telefonoTecnico;
  final String numeroOt;
  final String accessId;
  final String nombreCto;
  final String numeroPelo;
  final double valorConsulta1;
  final double? valorConsulta2;  // Consulta después de revisión
  final TipoAlerta tipoAlerta;
  final DateTime fechaRecepcion;
  final EstadoAlerta estado;
  final DateTime? fechaAtendida;
  final DateTime? fechaPostergada;
  final DateTime? fechaEscalada;
  final String? motivoEscalamiento;
  final List<String>? fotosGeoreferenciadas;
  final String? notas;
  final String? comentarioResolucion;
  final String? empresa;
  final String? actividad;
  final Duration? tiempoEjecucion;
  final List<NivelPuerto>? nivelesPuertos;

  Alerta({
    required this.id,
    required this.nombreTecnico,
    required this.telefonoTecnico,
    required this.numeroOt,
    required this.accessId,
    required this.nombreCto,
    required this.numeroPelo,
    required this.valorConsulta1,
    this.valorConsulta2,
    required this.tipoAlerta,
    required this.fechaRecepcion,
    this.estado = EstadoAlerta.pendiente,
    this.fechaAtendida,
    this.fechaPostergada,
    this.fechaEscalada,
    this.motivoEscalamiento,
    this.fotosGeoreferenciadas,
    this.notas,
    this.comentarioResolucion,
    this.empresa,
    this.actividad,
    this.tiempoEjecucion,
    this.nivelesPuertos,
  });

  /// Crea una alerta desde el JSON del webhook de Kepler
  factory Alerta.fromWebhook(Map<String, dynamic> json) {
    // Parsear niveles de puertos si existen
    List<NivelPuerto>? niveles;
    if (json['niveles_puertos'] != null) {
      niveles = (json['niveles_puertos'] as List)
          .map((e) => NivelPuerto.fromJson(e))
          .toList();
    }
    
    // Parsear tiempo de ejecución si existe
    Duration? tiempoEjec;
    if (json['tiempo_ejecucion_minutos'] != null) {
      tiempoEjec = Duration(minutes: json['tiempo_ejecucion_minutos']);
    }
    
    return Alerta(
      id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      nombreTecnico: json['nombre_tecnico'] ?? '',
      telefonoTecnico: json['telefono_tecnico'] ?? '',
      numeroOt: json['numero_ot'] ?? '',
      accessId: json['access_id'] ?? '',
      nombreCto: json['nombre_cto'] ?? '',
      numeroPelo: json['numero_pelo'] ?? '',
      valorConsulta1: (json['valor_consulta1'] ?? 0).toDouble(),
      valorConsulta2: json['valor_consulta2']?.toDouble(),
      tipoAlerta: TipoAlerta.fromString(json['tipo_alerta'] ?? 'desconexion'),
      fechaRecepcion: json['fecha_recepcion'] != null
          ? DateTime.parse(json['fecha_recepcion'])
          : DateTime.now(),
      estado: EstadoAlerta.pendiente,
      empresa: json['empresa'] ?? 'CREA',
      actividad: json['actividad'],
      tiempoEjecucion: tiempoEjec,
      comentarioResolucion: json['comentario_resolucion'],
      nivelesPuertos: niveles,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre_tecnico': nombreTecnico,
      'telefono_tecnico': telefonoTecnico,
      'numero_ot': numeroOt,
      'access_id': accessId,
      'nombre_cto': nombreCto,
      'numero_pelo': numeroPelo,
      'valor_consulta1': valorConsulta1,
      'valor_consulta2': valorConsulta2,
      'tipo_alerta': tipoAlerta.name,
      'fecha_recepcion': fechaRecepcion.toIso8601String(),
      'estado': estado.name,
      'fecha_atendida': fechaAtendida?.toIso8601String(),
      'fecha_postergada': fechaPostergada?.toIso8601String(),
      'fecha_escalada': fechaEscalada?.toIso8601String(),
      'motivo_escalamiento': motivoEscalamiento,
      'fotos_georeferenciadas': fotosGeoreferenciadas,
      'notas': notas,
      'empresa': empresa,
      'actividad': actividad,
      'tiempo_ejecucion_minutos': tiempoEjecucion?.inMinutes,
      'comentario_resolucion': comentarioResolucion,
      'niveles_puertos': nivelesPuertos?.map((e) => e.toJson()).toList(),
    };
  }

  Alerta copyWith({
    String? id,
    String? nombreTecnico,
    String? telefonoTecnico,
    String? numeroOt,
    String? accessId,
    String? nombreCto,
    String? numeroPelo,
    double? valorConsulta1,
    double? valorConsulta2,
    TipoAlerta? tipoAlerta,
    DateTime? fechaRecepcion,
    EstadoAlerta? estado,
    DateTime? fechaAtendida,
    DateTime? fechaPostergada,
    DateTime? fechaEscalada,
    String? motivoEscalamiento,
    List<String>? fotosGeoreferenciadas,
    String? notas,
    String? comentarioResolucion,
    String? empresa,
    String? actividad,
    Duration? tiempoEjecucion,
    List<NivelPuerto>? nivelesPuertos,
  }) {
    return Alerta(
      id: id ?? this.id,
      nombreTecnico: nombreTecnico ?? this.nombreTecnico,
      telefonoTecnico: telefonoTecnico ?? this.telefonoTecnico,
      numeroOt: numeroOt ?? this.numeroOt,
      accessId: accessId ?? this.accessId,
      nombreCto: nombreCto ?? this.nombreCto,
      numeroPelo: numeroPelo ?? this.numeroPelo,
      valorConsulta1: valorConsulta1 ?? this.valorConsulta1,
      valorConsulta2: valorConsulta2 ?? this.valorConsulta2,
      tipoAlerta: tipoAlerta ?? this.tipoAlerta,
      fechaRecepcion: fechaRecepcion ?? this.fechaRecepcion,
      estado: estado ?? this.estado,
      fechaAtendida: fechaAtendida ?? this.fechaAtendida,
      fechaPostergada: fechaPostergada ?? this.fechaPostergada,
      fechaEscalada: fechaEscalada ?? this.fechaEscalada,
      motivoEscalamiento: motivoEscalamiento ?? this.motivoEscalamiento,
      fotosGeoreferenciadas: fotosGeoreferenciadas ?? this.fotosGeoreferenciadas,
      notas: notas ?? this.notas,
      comentarioResolucion: comentarioResolucion ?? this.comentarioResolucion,
      empresa: empresa ?? this.empresa,
      actividad: actividad ?? this.actividad,
      tiempoEjecucion: tiempoEjecucion ?? this.tiempoEjecucion,
      nivelesPuertos: nivelesPuertos ?? this.nivelesPuertos,
    );
  }

  /// Tiempo restante antes de escalar (3 minutos desde recepción)
  Duration get tiempoRestanteEscalamiento {
    final limite = fechaRecepcion.add(const Duration(minutes: 3));
    final ahora = DateTime.now();
    if (ahora.isAfter(limite)) return Duration.zero;
    return limite.difference(ahora);
  }

  /// Indica si la alerta debe escalarse por tiempo
  bool get debeEscalarse => tiempoRestanteEscalamiento == Duration.zero && estado == EstadoAlerta.pendiente;

  /// Tiempo transcurrido desde que se atendió
  Duration? get tiempoEnAtencion {
    if (fechaAtendida == null) return null;
    return DateTime.now().difference(fechaAtendida!);
  }

  /// Indica si han pasado 20 minutos desde atención (para preguntar estado)
  bool get debeConsultarProgreso {
    final tiempo = tiempoEnAtencion;
    if (tiempo == null) return false;
    return tiempo.inMinutes >= 20;
  }
}

/// Tipos de alerta soportados
enum TipoAlerta {
  desconexion,
  churn,
  ctoDanada,
  tercerosEnCto,
  otro;

  static TipoAlerta fromString(String value) {
    switch (value.toLowerCase()) {
      case 'desconexion':
        return TipoAlerta.desconexion;
      case 'churn':
        return TipoAlerta.churn;
      case 'cto_danada':
      case 'ctodanada':
        return TipoAlerta.ctoDanada;
      case 'terceros_en_cto':
      case 'terceros':
        return TipoAlerta.tercerosEnCto;
      default:
        return TipoAlerta.otro;
    }
  }

  String get displayName {
    switch (this) {
      case TipoAlerta.desconexion:
        return 'Desconexión';
      case TipoAlerta.churn:
        return 'Churn';
      case TipoAlerta.ctoDanada:
        return 'CTO Dañada';
      case TipoAlerta.tercerosEnCto:
        return 'Terceros en CTO';
      case TipoAlerta.otro:
        return 'Otro';
    }
  }

  /// Indica si requiere fotos georeferenciadas
  bool get requiereFotos => this == TipoAlerta.churn;

  /// Indica si debe transferirse al supervisor
  bool get requiereEscalamiento => 
      this == TipoAlerta.ctoDanada || this == TipoAlerta.tercerosEnCto;
}

/// Estados posibles de una alerta
enum EstadoAlerta {
  pendiente,
  postergada,
  enAtencion,
  enRevisionCalidad,
  regularizada,
  escalada,
  cerrada;

  String get displayName {
    switch (this) {
      case EstadoAlerta.pendiente:
        return 'Pendiente';
      case EstadoAlerta.postergada:
        return 'Postergada';
      case EstadoAlerta.enAtencion:
        return 'En Atención';
      case EstadoAlerta.enRevisionCalidad:
        return 'En Revisión de Calidad';
      case EstadoAlerta.regularizada:
        return 'Regularizada';
      case EstadoAlerta.escalada:
        return 'Escalada';
      case EstadoAlerta.cerrada:
        return 'Cerrada';
    }
  }
}


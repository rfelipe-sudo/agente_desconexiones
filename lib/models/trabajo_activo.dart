/// Modelo para trabajo activo con detección de caminata
class TrabajoActivo {
  final String ot;
  final String tecnicoId;
  final String nombreTecnico;
  final String direccion;
  final DateTime horaInicio;
  final double latInicial;
  final double lngInicial;
  int pasosInicial;
  int pasosActual;
  double distanciaMaxRecorrida;
  Duration tiempoCaminando;
  bool detectoCaminata;
  List<String> actividadesDetectadas;

  TrabajoActivo({
    required this.ot,
    required this.tecnicoId,
    required this.nombreTecnico,
    required this.direccion,
    required this.horaInicio,
    required this.latInicial,
    required this.lngInicial,
    this.pasosInicial = 0,
    this.pasosActual = 0,
    this.distanciaMaxRecorrida = 0,
    this.tiempoCaminando = const Duration(seconds: 0),
    this.detectoCaminata = false,
    this.actividadesDetectadas = const [],
  });

  int get pasosRealizados => pasosActual - pasosInicial;

  Map<String, dynamic> toJson() => {
    'ot': ot,
    'tecnico_id': tecnicoId,
    'nombre_tecnico': nombreTecnico,
    'direccion': direccion,
    'hora_inicio': horaInicio.toIso8601String(),
    'lat_inicial': latInicial,
    'lng_inicial': lngInicial,
    'pasos_inicial': pasosInicial,
    'pasos_actual': pasosActual,
    'distancia_max_recorrida': distanciaMaxRecorrida,
    'tiempo_caminando_segundos': tiempoCaminando.inSeconds,
    'detecto_caminata': detectoCaminata,
    'actividades_detectadas': actividadesDetectadas,
  };

  factory TrabajoActivo.fromJson(Map<String, dynamic> json) => TrabajoActivo(
    ot: json['ot'] as String,
    tecnicoId: json['tecnico_id'] as String,
    nombreTecnico: json['nombre_tecnico'] as String,
    direccion: json['direccion'] as String,
    horaInicio: DateTime.parse(json['hora_inicio'] as String),
    latInicial: (json['lat_inicial'] as num).toDouble(),
    lngInicial: (json['lng_inicial'] as num).toDouble(),
    pasosInicial: json['pasos_inicial'] as int? ?? 0,
    pasosActual: json['pasos_actual'] as int? ?? 0,
    distanciaMaxRecorrida: (json['distancia_max_recorrida'] as num?)?.toDouble() ?? 0,
    tiempoCaminando: Duration(seconds: json['tiempo_caminando_segundos'] as int? ?? 0),
    detectoCaminata: json['detecto_caminata'] as bool? ?? false,
    actividadesDetectadas: List<String>.from(json['actividades_detectadas'] as List? ?? []),
  );
}

/// Resultado de validación para "Sin Moradores"
class ValidacionSinMoradores {
  final bool aprobado;
  final bool cumplePasos;
  final bool cumpleDistancia;
  final bool cumpleCaminata;
  final int pasosRealizados;
  final double distanciaRecorrida;
  final String mensaje;
  final List<String> razonesFallo;

  ValidacionSinMoradores({
    required this.aprobado,
    required this.cumplePasos,
    required this.cumpleDistancia,
    required this.cumpleCaminata,
    required this.pasosRealizados,
    required this.distanciaRecorrida,
    required this.mensaje,
    this.razonesFallo = const [],
  });

  factory ValidacionSinMoradores.fromJson(Map<String, dynamic> json) {
    return ValidacionSinMoradores(
      aprobado: json['aprobado'] as bool? ?? false,
      cumplePasos: json['cumple_pasos'] as bool? ?? false,
      cumpleDistancia: json['cumple_distancia'] as bool? ?? false,
      cumpleCaminata: json['cumple_caminata'] as bool? ?? false,
      pasosRealizados: json['pasos_realizados'] as int? ?? 0,
      distanciaRecorrida: (json['distancia_recorrida'] as num?)?.toDouble() ?? 0,
      mensaje: json['mensaje'] as String? ?? '',
      razonesFallo: List<String>.from(json['razones_fallo'] as List? ?? []),
    );
  }
}


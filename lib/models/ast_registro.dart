class ASTRegistro {
  final String? id;
  final String ordenTrabajo;
  final String rutTecnico;
  final String nombreTecnico;
  final String cargo;
  final String actividad;
  final String empresa;
  final String lugarActividad;
  final List<String> tareasRealizar;
  final List<String> riesgosIdentificados;
  final List<String> medidasControl;
  final List<String> equiposProteccion;
  final List<String> dispositivosSeguridad;
  final List<String> herramientasUtilizar;
  final String estadoHerramientas;
  final String condicionesCriticas;
  final String condicionesClimaticas;
  final Map<String, dynamic>? fotoArea;
  final Map<String, dynamic>? firma;
  final String? urlFotoAreaTrabajo;
  final String observaciones;
  final String? urlFirmaTecnico;
  final double latitud;
  final double longitud;
  final DateTime fechaHora;

  const ASTRegistro({
    this.id,
    required this.ordenTrabajo,
    required this.rutTecnico,
    required this.nombreTecnico,
    required this.cargo,
    this.actividad = '',
    required this.empresa,
    required this.lugarActividad,
    required this.tareasRealizar,
    required this.riesgosIdentificados,
    required this.medidasControl,
    required this.equiposProteccion,
    required this.dispositivosSeguridad,
    required this.herramientasUtilizar,
    required this.estadoHerramientas,
    required this.condicionesCriticas,
    required this.condicionesClimaticas,
    this.fotoArea,
    this.firma,
    this.urlFotoAreaTrabajo,
    required this.observaciones,
    this.urlFirmaTecnico,
    required this.latitud,
    required this.longitud,
    required this.fechaHora,
  });

  static List<String> _csvToList(dynamic v) {
    if (v == null) return [];
    final s = v.toString().trim();
    if (s.isEmpty) return [];
    return s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  factory ASTRegistro.fromMap(Map<String, dynamic> m) {
    return ASTRegistro(
      id: m['id'] as String?,
      ordenTrabajo: m['orden_trabajo'] as String? ?? '',
      rutTecnico: m['rut_tecnico'] as String? ?? '',
      nombreTecnico: m['nombre_tecnico'] as String? ?? '',
      cargo: m['cargo'] as String? ?? '',
      actividad: m['actividad'] as String? ?? '',
      empresa: m['empresa'] as String? ?? '',
      lugarActividad: m['lugar_actividad'] as String? ?? '',
      tareasRealizar: _csvToList(m['tareas_realizar']),
      riesgosIdentificados: _csvToList(m['riesgos_identificados']),
      medidasControl: _csvToList(m['medidas_control']),
      equiposProteccion: _csvToList(m['equipos_proteccion']),
      dispositivosSeguridad: _csvToList(m['dispositivos_seguridad']),
      herramientasUtilizar: _csvToList(m['herramientas_utilizar']),
      estadoHerramientas: m['estado_herramientas'] as String? ?? '',
      condicionesCriticas: m['condiciones_criticas'] as String? ?? '',
      condicionesClimaticas: m['condiciones_climaticas'] as String? ?? '',
      fotoArea: m['foto_area'] as Map<String, dynamic>?,
      firma: m['firma'] as Map<String, dynamic>?,
      urlFotoAreaTrabajo: m['url_foto_area'] as String?,
      observaciones: m['observaciones'] as String? ?? '',
      urlFirmaTecnico: m['url_firma'] as String?,
      latitud: (m['latitud'] as num?)?.toDouble() ?? 0,
      longitud: (m['longitud'] as num?)?.toDouble() ?? 0,
      fechaHora: DateTime.tryParse(m['fecha_hora'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'orden_trabajo': ordenTrabajo,
    'rut_tecnico': rutTecnico,
    'nombre_tecnico': nombreTecnico,
    'cargo': cargo,
    'actividad': actividad,
    'empresa': empresa,
    'lugar_actividad': lugarActividad,
    'tareas_realizar': tareasRealizar.join(', '),
    'riesgos_identificados': riesgosIdentificados.join(', '),
    'medidas_control': medidasControl.join(', '),
    'equipos_proteccion': equiposProteccion.join(', '),
    'dispositivos_seguridad': dispositivosSeguridad.join(', '),
    'herramientas_utilizar': herramientasUtilizar.join(', '),
    'estado_herramientas': estadoHerramientas,
    'condiciones_criticas': condicionesCriticas,
    'condiciones_climaticas': condicionesClimaticas,
    if (fotoArea != null) 'foto_area': fotoArea,
    if (firma != null) 'firma': firma,
    if (urlFotoAreaTrabajo != null) 'url_foto_area': urlFotoAreaTrabajo,
    'observaciones': observaciones,
    if (urlFirmaTecnico != null) 'url_firma': urlFirmaTecnico,
    'latitud': latitud,
    'longitud': longitud,
    'fecha_hora': fechaHora.toUtc().toIso8601String(),
  };
}

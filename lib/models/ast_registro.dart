class ASTRegistro {
  final String ordenTrabajo;
  final String rutTecnico;
  final String nombreTecnico;
  final String cargo;
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
  final String urlFotoAreaTrabajo;
  final String observaciones;
  final String urlFirmaTecnico;
  final double latitud;
  final double longitud;
  final DateTime fechaHora;

  const ASTRegistro({
    required this.ordenTrabajo,
    required this.rutTecnico,
    required this.nombreTecnico,
    required this.cargo,
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
    required this.urlFotoAreaTrabajo,
    required this.observaciones,
    required this.urlFirmaTecnico,
    required this.latitud,
    required this.longitud,
    required this.fechaHora,
  });

  Map<String, dynamic> toJson() => {
    'orden_trabajo': ordenTrabajo,
    'rut_tecnico': rutTecnico,
    'nombre_tecnico': nombreTecnico,
    'cargo': cargo,
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
    'url_foto_area': urlFotoAreaTrabajo,
    'observaciones': observaciones,
    'url_firma': urlFirmaTecnico,
    'latitud': latitud,
    'longitud': longitud,
    'fecha_hora': fechaHora.toIso8601String(),
  };
}

class MetricaProduccion {
  final String? id;
  final String tecnicoRut;
  final String? tecnicoNombre;
  final DateTime fecha;
  
  // Tiempos (minutos)
  final int tiempoTrabajoMin;
  final int tiempoTrayectoMin;
  final int tiempoOcioMin;
  final int tiempoPromedioOrdenMin;
  
  // Distancias
  final double kmRecorridos;
  final double combustibleLitros;
  
  // Costos
  final int gastoTag;
  final int costoCombustible;
  final int costoTotal;
  
  // Productividad
  final int ordenesAsignadas;
  final int ordenesCompletadas;
  final int quiebres;
  final double porcentajeProductividad;
  final double porcentajeQuiebre;
  final double productividadVsQuiebre;
  
  // Desglose
  final int altasCompletadas;
  final int bajasCompletadas;
  final int reparacionesCompletadas;
  
  // Análisis
  final String? horaPico;
  final String? zonaMasEficiente;

  MetricaProduccion({
    this.id,
    required this.tecnicoRut,
    this.tecnicoNombre,
    required this.fecha,
    this.tiempoTrabajoMin = 0,
    this.tiempoTrayectoMin = 0,
    this.tiempoOcioMin = 0,
    this.tiempoPromedioOrdenMin = 0,
    this.kmRecorridos = 0,
    this.combustibleLitros = 0,
    this.gastoTag = 0,
    this.costoCombustible = 0,
    this.costoTotal = 0,
    this.ordenesAsignadas = 0,
    this.ordenesCompletadas = 0,
    this.quiebres = 0,
    this.porcentajeProductividad = 0,
    this.porcentajeQuiebre = 0,
    this.productividadVsQuiebre = 0,
    this.altasCompletadas = 0,
    this.bajasCompletadas = 0,
    this.reparacionesCompletadas = 0,
    this.horaPico,
    this.zonaMasEficiente,
  });

  factory MetricaProduccion.fromJson(Map<String, dynamic> json) {
    return MetricaProduccion(
      id: json['id'],
      tecnicoRut: json['tecnico_rut'] ?? '',
      tecnicoNombre: json['tecnico_nombre'],
      fecha: DateTime.parse(json['fecha']),
      tiempoTrabajoMin: json['tiempo_trabajo_min'] ?? 0,
      tiempoTrayectoMin: json['tiempo_trayecto_min'] ?? 0,
      tiempoOcioMin: json['tiempo_ocio_min'] ?? 0,
      tiempoPromedioOrdenMin: json['tiempo_promedio_orden_min'] ?? 0,
      kmRecorridos: (json['km_recorridos'] as num?)?.toDouble() ?? 0,
      combustibleLitros: (json['combustible_litros'] as num?)?.toDouble() ?? 0,
      gastoTag: json['gasto_tag'] ?? 0,
      costoCombustible: json['costo_combustible'] ?? 0,
      costoTotal: json['costo_total'] ?? 0,
      ordenesAsignadas: json['ordenes_asignadas'] ?? 0,
      ordenesCompletadas: json['ordenes_completadas'] ?? 0,
      quiebres: json['quiebres'] ?? 0,
      porcentajeProductividad: (json['porcentaje_productividad'] as num?)?.toDouble() ?? 0,
      porcentajeQuiebre: (json['porcentaje_quiebre'] as num?)?.toDouble() ?? 0,
      productividadVsQuiebre: (json['productividad_vs_quiebre'] as num?)?.toDouble() ?? 0,
      altasCompletadas: json['altas_completadas'] ?? 0,
      bajasCompletadas: json['bajas_completadas'] ?? 0,
      reparacionesCompletadas: json['reparaciones_completadas'] ?? 0,
      horaPico: json['hora_pico'],
      zonaMasEficiente: json['zona_mas_eficiente'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tecnico_rut': tecnicoRut,
      'tecnico_nombre': tecnicoNombre,
      'fecha': fecha.toIso8601String().split('T')[0],
      'tiempo_trabajo_min': tiempoTrabajoMin,
      'tiempo_trayecto_min': tiempoTrayectoMin,
      'tiempo_ocio_min': tiempoOcioMin,
      'tiempo_promedio_orden_min': tiempoPromedioOrdenMin,
      'km_recorridos': kmRecorridos,
      'combustible_litros': combustibleLitros,
      'gasto_tag': gastoTag,
      'costo_combustible': costoCombustible,
      'costo_total': costoTotal,
      'ordenes_asignadas': ordenesAsignadas,
      'ordenes_completadas': ordenesCompletadas,
      'quiebres': quiebres,
      'porcentaje_productividad': porcentajeProductividad,
      'porcentaje_quiebre': porcentajeQuiebre,
      'productividad_vs_quiebre': productividadVsQuiebre,
      'altas_completadas': altasCompletadas,
      'bajas_completadas': bajasCompletadas,
      'reparaciones_completadas': reparacionesCompletadas,
      'hora_pico': horaPico,
      'zona_mas_eficiente': zonaMasEficiente,
    };
  }
}















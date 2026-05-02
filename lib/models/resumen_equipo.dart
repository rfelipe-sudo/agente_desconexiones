// ============================================================================
// MODELO: RESUMEN DEL EQUIPO
// ============================================================================

class ResumenEquipo {
  final int totalTecnicos;
  final int tecnicosTrabajando;
  final int tecnicosEnRuta;
  final int tecnicosSinIniciar;
  final double promedioCalidad; // 0-100
  final double presupuestoCumplido; // 0-100
  final double presupuestoFaltante; // 0-100
  final int ordenesPendientesConsumo;
  final double produccionPromedioMes; // Actividades promedio por técnico

  ResumenEquipo({
    this.totalTecnicos = 0,
    this.tecnicosTrabajando = 0,
    this.tecnicosEnRuta = 0,
    this.tecnicosSinIniciar = 0,
    this.promedioCalidad = 0.0,
    this.presupuestoCumplido = 0.0,
    this.presupuestoFaltante = 0.0,
    this.ordenesPendientesConsumo = 0,
    this.produccionPromedioMes = 0.0,
  });

  factory ResumenEquipo.fromJson(Map<String, dynamic> json) {
    return ResumenEquipo(
      totalTecnicos: json['total_tecnicos'] ?? 0,
      tecnicosTrabajando: json['tecnicos_trabajando'] ?? 0,
      tecnicosEnRuta: json['tecnicos_en_ruta'] ?? 0,
      tecnicosSinIniciar: json['tecnicos_sin_iniciar'] ?? 0,
      promedioCalidad: (json['promedio_calidad'] ?? 0.0).toDouble(),
      presupuestoCumplido: (json['presupuesto_cumplido'] ?? 0.0).toDouble(),
      presupuestoFaltante: (json['presupuesto_faltante'] ?? 0.0).toDouble(),
      ordenesPendientesConsumo: json['ordenes_pendientes_consumo'] ?? 0,
      produccionPromedioMes: (json['produccion_promedio_mes'] ?? 0.0).toDouble(),
    );
  }
}














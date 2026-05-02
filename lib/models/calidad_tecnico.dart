import 'package:flutter/material.dart';

/// Modelo para representar los datos de calidad del técnico desde v_calidad_tecnicos
class CalidadTecnico {
  final String rutTecnico;
  final String tecnico;
  final int totalReiterados;
  final double promedioDias;
  final int minDias;
  final int maxDias;
  final int reiteradosAlta;
  final int reiteradosReparacion;
  final int reiteradosMigracion;

  CalidadTecnico({
    required this.rutTecnico,
    required this.tecnico,
    required this.totalReiterados,
    required this.promedioDias,
    required this.minDias,
    required this.maxDias,
    required this.reiteradosAlta,
    required this.reiteradosReparacion,
    required this.reiteradosMigracion,
  });

  factory CalidadTecnico.fromJson(Map<String, dynamic> json) {
    return CalidadTecnico(
      rutTecnico: json['rut_tecnico']?.toString() ?? '',
      tecnico: json['tecnico']?.toString() ?? '',
      totalReiterados: (json['total_reiterados'] as num?)?.toInt() ?? 0,
      promedioDias: (json['promedio_dias'] as num?)?.toDouble() ?? 0.0,
      minDias: (json['min_dias'] as num?)?.toInt() ?? 0,
      maxDias: (json['max_dias'] as num?)?.toInt() ?? 0,
      reiteradosAlta: (json['reiterados_alta'] as num?)?.toInt() ?? 0,
      reiteradosReparacion: (json['reiterados_reparacion'] as num?)?.toInt() ?? 0,
      reiteradosMigracion: (json['reiterados_migracion'] as num?)?.toInt() ?? 0,
    );
  }

  /// Obtener color según cantidad de reiterados
  Color getColor() {
    if (totalReiterados <= 5) return Colors.green;
    if (totalReiterados <= 15) return Colors.orange;
    if (totalReiterados <= 25) return Colors.deepOrange;
    return Colors.red;
  }

  /// Obtener nivel de calidad
  String getNivel() {
    if (totalReiterados <= 5) return 'Excelente';
    if (totalReiterados <= 15) return 'Bueno';
    if (totalReiterados <= 25) return 'Regular';
    return 'Necesita mejorar';
  }
}

/// Modelo para representar un detalle de reiterado desde calidad_crea
class DetalleReiterado {
  final String ordenOriginal;
  final String fechaOriginal;
  final String tipoActividad;
  final String ordenReiterada;
  final String fechaReiterada;
  final int diasReiterado;
  final String cliente;
  final String direccion;
  final String causa; // Causa o motivo de la reiteración
  final String codigoCierre; // Código de cierre

  DetalleReiterado({
    required this.ordenOriginal,
    required this.fechaOriginal,
    required this.tipoActividad,
    required this.ordenReiterada,
    required this.fechaReiterada,
    required this.diasReiterado,
    required this.cliente,
    required this.direccion,
    required this.causa,
    required this.codigoCierre,
  });

  factory DetalleReiterado.fromJson(Map<String, dynamic> json) {
    // Debug: imprimir los valores recibidos
    final codigoCierreRaw = json['codigo_cierre_reiterado'];
    final descripcionRaw = json['descripcion_reiterado'];
    
    if (codigoCierreRaw != null || descripcionRaw != null) {
      print('📋 [DetalleReiterado] codigo_cierre_reiterado: $codigoCierreRaw');
      print('📋 [DetalleReiterado] descripcion_reiterado: $descripcionRaw');
    }
    
    final codigoCierre = json['codigo_cierre_reiterado']?.toString().trim() ?? '';
    final causa = json['descripcion_reiterado']?.toString().trim() ?? '';
    
    return DetalleReiterado(
      ordenOriginal: json['orden_original']?.toString() ?? '',
      fechaOriginal: json['fecha_original']?.toString() ?? '',
      tipoActividad: json['tipo_actividad']?.toString() ?? '',
      ordenReiterada: json['orden_reiterada']?.toString() ?? '',
      fechaReiterada: json['fecha_reiterada']?.toString() ?? '',
      diasReiterado: (json['dias_reiterado'] as num?)?.toInt() ?? 0,
      cliente: json['cliente']?.toString() ?? '',
      direccion: json['direccion']?.toString() ?? '',
      causa: causa,
      codigoCierre: codigoCierre,
    );
  }
}


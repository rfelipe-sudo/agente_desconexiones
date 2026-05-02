// ============================================================================
// MODELO: TÉCNICO DEL EQUIPO
// ============================================================================

import 'package:flutter/material.dart';

class TecnicoEquipo {
  final String id;
  final String rut;
  final String nombre;
  final String estadoCodigo; // sin_iniciar, en_ruta, trabajando, pausado, finalizado
  final String estadoColor; // rojo, naranja, verde, amarillo, gris
  final int actividadesHoy;
  final int actividadesMes;
  final double calidad; // 0-100
  final int ranking;

  TecnicoEquipo({
    required this.id,
    required this.rut,
    required this.nombre,
    required this.estadoCodigo,
    required this.estadoColor,
    this.actividadesHoy = 0,
    this.actividadesMes = 0,
    this.calidad = 0.0,
    this.ranking = 0,
  });

  factory TecnicoEquipo.fromJson(Map<String, dynamic> json) {
    return TecnicoEquipo(
      id: json['id']?.toString() ?? '',
      rut: json['rut']?.toString() ?? '',
      nombre: json['nombre']?.toString() ?? '',
      estadoCodigo: json['estado_codigo']?.toString() ?? 'sin_iniciar',
      estadoColor: json['estado_color']?.toString() ?? 'rojo',
      actividadesHoy: json['actividades_hoy'] ?? 0,
      actividadesMes: json['actividades_mes'] ?? 0,
      calidad: (json['calidad'] ?? 0.0).toDouble(),
      ranking: json['ranking'] ?? 0,
    );
  }

  /// Color según estado
  Color get estadoColorFlutter {
    switch (estadoCodigo) {
      case 'trabajando':
        return const Color(0xFF00D4AA); // Verde
      case 'en_ruta':
        return const Color(0xFFFFA500); // Naranja
      case 'sin_iniciar':
        return const Color(0xFFFF6B6B); // Rojo
      case 'pausado':
        return Colors.amber;
      case 'finalizado':
        return Colors.grey;
      default:
        return const Color(0xFFFF6B6B);
    }
  }

  /// Tiene alerta si no ha cerrado actividades hoy
  bool get tieneAlerta => actividadesHoy == 0;

  /// Tiene ticket si ya cerró actividades hoy
  bool get tieneTicket => actividadesHoy > 0;
}

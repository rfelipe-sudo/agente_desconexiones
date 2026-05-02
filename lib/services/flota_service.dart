import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Servicio de Flota
/// Centraliza cálculos de TAG (peajes) y Combustible para la card FLOTA
class FlotaService {
  static final FlotaService _instance = FlotaService._internal();
  factory FlotaService() => _instance;
  FlotaService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  // ────────────────────────────────────────────────────────
  // Parámetros de combustible (fijos por ahora)
  // ────────────────────────────────────────────────────────
  /// Precio del litro de petróleo en CLP (no editable por el técnico)
  static const double precioPorLitro = 1500.0;

  /// Rendimiento del vehículo en km por litro
  static const double rendimientoKmLitro = 12.0;

  /// Velocidad promedio usada para estimar km desde tiempo_viaje_min
  static const double velocidadPromedioKmh = 40.0;

  /// Km de trayecto diario (casa ↔ trabajo, ida+vuelta)
  static const double kmTrayectoDiario = 20.0;

  /// Umbral de litros operacionales: si hay más → técnico aún tiene combustible
  static const double umbralCombustibleOperac = 6.0;

  // ────────────────────────────────────────────────────────
  // Método principal
  // ────────────────────────────────────────────────────────

  /// Obtiene todos los datos de flota (TAG + combustible) para un mes
  Future<Map<String, dynamic>> obtenerDatosFlota(
    String rutTecnico, {
    required int mes,
    required int anno,
  }) async {
    try {
      final results = await Future.wait([
        _obtenerDatosTag(rutTecnico, mes: mes, anno: anno),
        _calcularCombustible(rutTecnico, mes: mes, anno: anno),
      ]);

      return {
        'tag': results[0],
        'combustible': results[1],
        'precio_litro': precioPorLitro,
      };
    } catch (e) {
      print('❌ [FlotaService] Error obteniendo datos flota: $e');
      return _datosVacios();
    }
  }

  // ────────────────────────────────────────────────────────
  // TAG
  // ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _obtenerDatosTag(
    String rutTecnico, {
    required int mes,
    required int anno,
  }) async {
    try {
      final inicioMes = DateTime(anno, mes, 1);
      // Mes siguiente para el fin (DateTime maneja desbordamiento)
      final finMes = DateTime(anno, mes + 1, 0, 23, 59, 59);

      final response = await _supabase
          .from('pasos_tag')
          .select('tarifa_cobrada, tipo_tarifa, fecha_paso')
          .eq('rut_tecnico', rutTecnico)
          .gte('fecha_paso', inicioMes.toIso8601String())
          .lte('fecha_paso', finMes.toIso8601String());

      final pasos = response as List;
      final totalTag = pasos.fold<int>(
        0,
        (sum, p) => sum + ((p['tarifa_cobrada'] as num?)?.toInt() ?? 0),
      );

      print(
        '🛣️ [FlotaService] TAG $mes/$anno: ${pasos.length} pasos = \$$totalTag',
      );

      return {
        'total': totalTag,
        'pasos': pasos.length,
      };
    } catch (e) {
      print('⚠️ [FlotaService] Error TAG: $e');
      return {'total': 0, 'pasos': 0};
    }
  }

  // ────────────────────────────────────────────────────────
  // Combustible
  // ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _calcularCombustible(
    String rutTecnico, {
    required int mes,
    required int anno,
  }) async {
    try {
      final mesStr = mes.toString().padLeft(2, '0');

      // Obtener tiempo_viaje_min de órdenes completadas del mes
      final ordenes = await _supabase
          .from('produccion_crea')
          .select('tiempo_viaje_min, fecha_trabajo')
          .eq('rut_tecnico', rutTecnico)
          .eq('estado', 'Completado')
          .ilike('fecha_trabajo', '*/$mesStr/$anno');

      final lista = ordenes as List;

      // Sumar minutos de viaje operacional
      final totalMinViaje = lista.fold<double>(
        0.0,
        (sum, o) => sum + ((o['tiempo_viaje_min'] as num?)?.toDouble() ?? 0.0),
      );

      // Días únicos con producción (para calcular trayecto)
      final diasSet = <String>{};
      for (final o in lista) {
        final fecha = o['fecha_trabajo']?.toString() ?? '';
        if (fecha.isNotEmpty) diasSet.add(fecha);
      }
      final diasTrabajados = diasSet.length;

      // Cálculo km operacional: min_viaje → horas → km
      final kmOperac = (totalMinViaje / 60.0) * velocidadPromedioKmh;

      // Cálculo km trayecto: días × km diario
      final kmTrayecto = diasTrabajados * kmTrayectoDiario;

      // Litros
      final litrosOperac = kmOperac / rendimientoKmLitro;
      final litrosTrayecto = kmTrayecto / rendimientoKmLitro;

      // Costos en CLP
      final costoOperac = litrosOperac * precioPorLitro;
      final costoTrayecto = litrosTrayecto * precioPorLitro;

      print(
        '⛽ [FlotaService] Combustible $mes/$anno: '
        '${totalMinViaje.toStringAsFixed(0)}min viaje → '
        '${kmOperac.toStringAsFixed(1)}km operac / '
        '${kmTrayecto.toStringAsFixed(1)}km trayecto → '
        '${litrosOperac.toStringAsFixed(2)}L + ${litrosTrayecto.toStringAsFixed(2)}L',
      );

      return {
        'km_operac': kmOperac,
        'km_trayecto': kmTrayecto,
        'litros_operac': litrosOperac,
        'litros_trayecto': litrosTrayecto,
        'litros_total': litrosOperac + litrosTrayecto,
        'costo_operac': costoOperac,
        'costo_trayecto': costoTrayecto,
        'costo_total': costoOperac + costoTrayecto,
        'dias_trabajados': diasTrabajados,
        'minutos_viaje': totalMinViaje,
      };
    } catch (e) {
      print('⚠️ [FlotaService] Error combustible: $e');
      return _combustibleVacio();
    }
  }

  // ────────────────────────────────────────────────────────
  // Solicitud de combustible
  // ────────────────────────────────────────────────────────

  /// Envía una solicitud de combustible al dashboard de flota
  /// Guarda en la tabla `solicitudes_combustible`
  Future<bool> solicitarCombustible({
    required String rutTecnico,
    required String nombreTecnico,
    required double litrosOperac,
    required double litrosTrayecto,
    required double kmOperac,
    required double kmTrayecto,
    required String mes,
  }) async {
    try {
      await _supabase.from('solicitudes_combustible').insert({
        'rut_tecnico': rutTecnico,
        'nombre_tecnico': nombreTecnico,
        'litros_operac': litrosOperac,
        'litros_trayecto': litrosTrayecto,
        'litros_total': litrosOperac + litrosTrayecto,
        'km_operac': kmOperac,
        'km_trayecto': kmTrayecto,
        'estado': 'pendiente',
        'mes': mes,
        'created_at': DateTime.now().toIso8601String(),
      });
      print('✅ [FlotaService] Solicitud combustible enviada ($mes)');
      return true;
    } catch (e) {
      print('❌ [FlotaService] Error enviando solicitud: $e');
      return false;
    }
  }

  /// Verifica si ya existe una solicitud pendiente para este mes
  Future<bool> tieneSolicitudPendiente(String rutTecnico, String mes) async {
    try {
      final resp = await _supabase
          .from('solicitudes_combustible')
          .select('id')
          .eq('rut_tecnico', rutTecnico)
          .eq('mes', mes)
          .inFilter('estado', ['pendiente', 'aprobado']);

      return (resp as List).isNotEmpty;
    } catch (e) {
      print('⚠️ [FlotaService] Error verificando solicitud: $e');
      return false;
    }
  }

  // ────────────────────────────────────────────────────────
  // Helpers
  // ────────────────────────────────────────────────────────

  Map<String, dynamic> _datosVacios() => {
        'tag': {'total': 0, 'pasos': 0},
        'combustible': _combustibleVacio(),
        'precio_litro': precioPorLitro,
      };

  Map<String, dynamic> _combustibleVacio() => {
        'km_operac': 0.0,
        'km_trayecto': 0.0,
        'litros_operac': 0.0,
        'litros_trayecto': 0.0,
        'litros_total': 0.0,
        'costo_operac': 0.0,
        'costo_trayecto': 0.0,
        'costo_total': 0.0,
        'dias_trabajados': 0,
        'minutos_viaje': 0.0,
      };

  // ────────────────────────────────────────────────────────
  // Formateo (helpers estáticos para la UI)
  // ────────────────────────────────────────────────────────

  /// Formatea número con puntos de miles: 1500 → "1.500"
  static String formatearPesos(double valor) {
    final entero = valor.round();
    final str = entero.toString();
    final buffer = StringBuffer();
    int count = 0;
    for (int i = str.length - 1; i >= 0; i--) {
      if (count > 0 && count % 3 == 0) buffer.write('.');
      buffer.write(str[i]);
      count++;
    }
    return buffer.toString().split('').reversed.join();
  }

  /// Indica si hay suficiente combustible operacional (> umbral)
  static bool tieneCombustibleSuficiente(double litrosOperac) =>
      litrosOperac > umbralCombustibleOperac;
}

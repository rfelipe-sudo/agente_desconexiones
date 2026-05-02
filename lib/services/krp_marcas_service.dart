import 'package:supabase_flutter/supabase_flutter.dart';

/// Modelo para representar las marcas de asistencia del técnico
class MarcasTecnico {
  final int diasTrabajados;
  final int diasAusentes;
  final int diasFeriados;
  final int diasVacaciones;

  MarcasTecnico({
    required this.diasTrabajados,
    required this.diasAusentes,
    required this.diasFeriados,
    required this.diasVacaciones,
  });
}

/// Servicio para consultar las marcas de asistencia desde Supabase (GeoVictoria)
class KrpMarcasService {
  final _supabase = Supabase.instance.client;

  /// Obtener las marcas de asistencia del técnico desde Supabase
  /// [rutTecnico] RUT del técnico (sin puntos, con/sin guión)
  /// [mes] Mes a consultar (1-12)
  /// [anio] Año a consultar
  Future<MarcasTecnico> obtenerMarcas({
    required String rutTecnico,
    int? mes,
    int? anio,
  }) async {
    return _obtenerMarcasDesdeSupabase(rutTecnico, mes, anio);
  }

  /// Obtener marcas desde Supabase
  Future<MarcasTecnico> _obtenerMarcasDesdeSupabase(
    String rutTecnico,
    int? mes,
    int? anio,
  ) async {
    try {
      final ahora = DateTime.now();
      final mesActual = mes ?? ahora.month;
      final anioActual = anio ?? ahora.year;
      
      // Calcular rango de fechas del mes
      final primerDia = DateTime(anioActual, mesActual, 1);
      final ultimoDia = DateTime(anioActual, mesActual + 1, 0);
      
      final fechaInicio = primerDia.toIso8601String().split('T')[0];
      final fechaFin = ultimoDia.toIso8601String().split('T')[0];
      
      print('🔍 [Marcas] =============================================');
      print('🔍 [Marcas] Consultando marcas en Supabase');
      print('🔍 [Marcas] RUT original: $rutTecnico');
      print('🔍 [Marcas] Período: $fechaInicio al $fechaFin');
      print('🔍 [Marcas] Mes: $mesActual, Año: $anioActual');
      
      // Generar variaciones del RUT (con/sin guión, con/sin puntos)
      // La tabla tiene RUTs como números enteros (ej: 260128906)
      final rutSinFormato = rutTecnico.replaceAll('.', '').replaceAll('-', '');
      final rutConGuion = rutTecnico.contains('-') ? rutTecnico : '${rutTecnico.substring(0, rutTecnico.length - 1)}-${rutTecnico.substring(rutTecnico.length - 1)}';
      final rutComoNumero = int.tryParse(rutSinFormato);
      
      print('🔍 [Marcas] RUT sin formato: $rutSinFormato');
      print('🔍 [Marcas] RUT como número: $rutComoNumero');
      print('🔍 [Marcas] RUT con guión: $rutConGuion');
      
      // Consultar la tabla geo_marcas_diarias para el técnico específico
      // El campo 'rut' es VARCHAR, buscar como string sin formato primero
      List<dynamic> response = [];
      
      // Intentar primero con string sin formato (260128906)
      print('🔍 [Marcas] Buscando con RUT string: $rutSinFormato');
      response = await _supabase
          .from('geo_marcas_diarias')
          .select('fecha, permiso, total_marcas')
          .eq('rut', rutSinFormato)
          .gte('fecha', fechaInicio)
          .lte('fecha', fechaFin)
          .order('fecha', ascending: false);
      
      // Si no encuentra, intentar con el RUT con guión
      if (response.isEmpty && rutConGuion != rutTecnico) {
        print('🔍 [Marcas] Reintentando con RUT con guión: $rutConGuion');
        response = await _supabase
            .from('geo_marcas_diarias')
            .select('fecha, permiso, total_marcas')
            .eq('rut', rutConGuion)
            .gte('fecha', fechaInicio)
            .lte('fecha', fechaFin)
            .order('fecha', ascending: false);
      }
      
      // Si aún no encuentra, intentar con el RUT original
      if (response.isEmpty && rutTecnico != rutSinFormato) {
        print('🔍 [Marcas] Reintentando con RUT original: $rutTecnico');
        response = await _supabase
            .from('geo_marcas_diarias')
            .select('fecha, permiso, total_marcas')
            .eq('rut', rutTecnico)
            .gte('fecha', fechaInicio)
            .lte('fecha', fechaFin)
            .order('fecha', ascending: false);
      }
      
      print('📊 [Marcas] Respuesta Supabase: ${response.length} días encontrados');
      
      // Mostrar todos los días encontrados para debugging
      if (response.isNotEmpty) {
        print('📋 [Marcas] Días encontrados en GeoVictoria:');
        for (final marca in response) {
          final fecha = marca['fecha'];
          final permiso = marca['permiso'];
          final totalMarcas = marca['total_marcas'];
          print('   • $fecha: $permiso (${totalMarcas} marcas)');
        }
      }
      
      if (response.isEmpty) {
        print('⚠️ [Marcas] NO HAY DATOS - Haciendo diagnóstico...');
        
        // Test 1: Ver RUTs disponibles
        final rutsSample = await _supabase
            .from('geo_marcas_diarias')
            .select('rut')
            .limit(10);
        print('⚠️ [Marcas] Muestra de RUTs en tabla: ${rutsSample.map((r) => r['rut']).toList()}');
        
        // Test 2: Ver rango de fechas
        final fechasSample = await _supabase
            .from('geo_marcas_diarias')
            .select('fecha')
            .order('fecha', ascending: false)
            .limit(5);
        print('⚠️ [Marcas] Fechas más recientes en tabla: ${fechasSample.map((f) => f['fecha']).toList()}');
      }
      
      if (response.isEmpty) {
        print('⚠️ [Marcas] No hay datos en Supabase para este técnico en este mes');
        return MarcasTecnico(
          diasTrabajados: 0,
          diasAusentes: 0,
          diasFeriados: 0,
          diasVacaciones: 0,
        );
      }
      
      // Procesar los datos según la lógica de GeoVictoria
      int diasTrabajados = 0;
      int diasAusentes = 0;
      int diasFeriados = 0;
      int diasVacaciones = 0;
      
      for (final marca in response) {
        final fecha = marca['fecha']?.toString() ?? '';
        final permiso = (marca['permiso']?.toString() ?? 'Ninguno').trim();
        final totalMarcas = (marca['total_marcas'] as int?) ?? 0;
        
        print('   📅 $fecha | Permiso: "$permiso" | Marcas: $totalMarcas');
        
        // Lógica según la estructura de GeoVictoria:
        // - permiso = 'Ninguno' + total_marcas > 0 → trabajó
        // - permiso = 'Ninguno' + total_marcas = 0 → ausente
        // - permiso = 'Vacaciones' → en vacaciones
        // - permiso contiene 'Feriado' → feriado
        // - otros permisos se cuentan como ausentes justificados
        
        if (permiso == 'Ninguno') {
          if (totalMarcas > 0) {
            diasTrabajados++;
            print('      ✅ Contado como TRABAJADO');
          } else {
            diasAusentes++;
            print('      ❌ Contado como AUSENTE (sin marcas)');
          }
        } else if (permiso.toLowerCase().contains('vacaciones') || 
                   permiso.toLowerCase().contains('vacación')) {
          diasVacaciones++;
          print('      🏖️ Contado como VACACIONES');
        } else if (permiso.toLowerCase().contains('feriado')) {
          diasFeriados++;
          print('      🎉 Contado como FERIADO');
        } else {
          print('      ⚪ Otro permiso (no contado): "$permiso"');
        }
      }
      
      print('✅ [Marcas] Resumen para $rutTecnico:');
      print('   Trabajados: $diasTrabajados');
      print('   Ausentes: $diasAusentes');
      print('   Feriados: $diasFeriados');
      print('   Vacaciones: $diasVacaciones');
      
      return MarcasTecnico(
        diasTrabajados: diasTrabajados,
        diasAusentes: diasAusentes,
        diasFeriados: diasFeriados,
        diasVacaciones: diasVacaciones,
      );
    } catch (e, stackTrace) {
      print('❌ [Marcas] Error obteniendo marcas desde Supabase: $e');
      print('Stack trace: $stackTrace');
      
      // Retornar valores por defecto si falla
      return MarcasTecnico(
        diasTrabajados: 0,
        diasAusentes: 0,
        diasFeriados: 0,
        diasVacaciones: 0,
      );
    }
  }
}


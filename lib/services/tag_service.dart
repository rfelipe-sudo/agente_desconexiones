import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/paso_tag.dart';

class TagService {
  static final TagService _instance = TagService._internal();
  factory TagService() => _instance;
  TagService._internal();

  final SupabaseClient _client = Supabase.instance.client;

  /// Obtiene todos los pasos TAG del mes actual
  Future<List<PasoTag>> getPasosDelMes() async {
    try {
      final now = DateTime.now();
      final inicioMes = DateTime(now.year, now.month, 1);
      final finMes = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

      // Obtener RUT del técnico desde SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final rutTecnico = prefs.getString('rut_tecnico');

      if (rutTecnico == null || rutTecnico.isEmpty) {
        print('⚠️ [TagService] No hay RUT guardado');
        return [];
      }

      final response = await _client
          .from('pasos_tag')
          .select()
          .eq('rut_tecnico', rutTecnico)
          .gte('fecha_paso', inicioMes.toIso8601String())
          .lte('fecha_paso', finMes.toIso8601String())
          .order('fecha_paso', ascending: false);

      return (response as List)
          .map((json) => PasoTag.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('❌ [TagService] Error obteniendo pasos: $e');
      return [];
    }
  }

  /// Obtiene el total gastado en TAG del mes actual
  Future<int> getTotalMesActual() async {
    try {
      final pasos = await getPasosDelMes();
      return pasos.fold<int>(0, (int sum, paso) => sum + paso.tarifaCobrada);
    } catch (e) {
      print('❌ [TagService] Error calculando total: $e');
      return 0;
    }
  }

  /// Obtiene la cantidad de pasos del mes actual
  Future<int> getCantidadPasosMes() async {
    try {
      final pasos = await getPasosDelMes();
      return pasos.length;
    } catch (e) {
      print('❌ [TagService] Error contando pasos: $e');
      return 0;
    }
  }
}



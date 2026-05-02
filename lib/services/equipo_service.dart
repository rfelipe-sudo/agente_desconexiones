// ============================================================================
// SERVICIO DE EQUIPO - OBTENER DATOS DEL EQUIPO
// ============================================================================

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/tecnico_equipo.dart';
import '../models/resumen_equipo.dart';

class EquipoService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Obtener lista de técnicos del equipo
  Future<List<TecnicoEquipo>> getMiEquipo(String supervisorId) async {
    try {
      final response = await _client.rpc('get_mi_equipo', params: {
        'p_supervisor_id': supervisorId,
      });

      if (response == null) return [];

      final List<dynamic> lista = response is List ? response : [response];
      return lista.map((e) => TecnicoEquipo.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      print('❌ [EquipoService] Error en getMiEquipo: $e');
      return [];
    }
  }

  /// Obtener resumen del equipo
  Future<ResumenEquipo> getResumenEquipo(String supervisorId) async {
    try {
      final response = await _client.rpc('get_resumen_equipo', params: {
        'p_supervisor_id': supervisorId,
      });

      if (response == null) {
        return ResumenEquipo();
      }

      return ResumenEquipo.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      print('❌ [EquipoService] Error en getResumenEquipo: $e');
      return ResumenEquipo();
    }
  }
}














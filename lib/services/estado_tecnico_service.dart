// ============================================================================
// SERVICIO DE ESTADO TÉCNICO
// ============================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

class EstadoTecnicoService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Actualizar estado del técnico
  Future<bool> actualizarEstado(String usuarioId, String estadoCodigo) async {
    try {
      await _client.rpc('actualizar_estado_tecnico', params: {
        'p_usuario_id': usuarioId,
        'p_estado_codigo': estadoCodigo,
      });
      print('✅ [EstadoTecnico] Estado actualizado: $estadoCodigo');
      return true;
    } catch (e) {
      print('❌ [EstadoTecnico] Error actualizando estado: $e');
      return false;
    }
  }

  /// Registrar cierre de actividad
  Future<bool> registrarCierreActividad(String usuarioId) async {
    try {
      await _client.rpc('incrementar_actividad_cerrada', params: {
        'p_usuario_id': usuarioId,
      });
      print('✅ [EstadoTecnico] Actividad cerrada registrada');
      return true;
    } catch (e) {
      print('❌ [EstadoTecnico] Error registrando cierre: $e');
      return false;
    }
  }
}














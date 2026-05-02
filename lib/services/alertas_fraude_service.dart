import 'dart:async';
import '../models/alerta_fraude.dart';
import 'supabase_service.dart';

class AlertasFraudeService {
  final SupabaseService _supabaseService = SupabaseService();

  // Obtener alertas pendientes para supervisor
  Future<List<AlertaFraude>> obtenerAlertasPendientes() async {
    try {
      final data = await _supabaseService.obtenerAlertasPendientes();
      return data.map((json) => AlertaFraude.fromJson(json)).toList();
    } catch (e) {
      print('❌ Error obteniendo alertas: $e');
      return [];
    }
  }

  // Marcar alerta como revisada
  Future<bool> marcarRevisada(
    String alertaId,
    String accion,
    String? comentario,
  ) async {
    try {
      return await _supabaseService.revisarAlerta(alertaId, accion, comentario);
    } catch (e) {
      print('❌ Error marcando alerta: $e');
      return false;
    }
  }

  // Stream de nuevas alertas en tiempo real desde Supabase
  Stream<List<AlertaFraude>> streamAlertas() {
    return _supabaseService
        .streamAlertasFraude()
        .map((data) => data.map((json) => AlertaFraude.fromJson(json)).toList());
  }
}


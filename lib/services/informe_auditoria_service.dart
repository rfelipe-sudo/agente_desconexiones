import 'package:supabase_flutter/supabase_flutter.dart';

class InformeAuditoriaService {
  InformeAuditoriaService({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  Future<String> guardarInforme(Map<String, dynamic> payload) async {
    final row = await _db
        .from('informes_auditoria')
        .insert(payload)
        .select('id')
        .single();
    return (row as Map)['id'] as String;
  }

  Future<List<Map<String, dynamic>>> listarPorIto(String rutIto) async {
    final rows = await _db
        .from('informes_auditoria')
        .select(
          'id, created_at, nombre_tecnico_auditado, actividad, numero_cliente, estado',
        )
        .eq('rut_ito', rutIto)
        .order('created_at', ascending: false)
        .limit(50);
    return (rows as List).cast<Map<String, dynamic>>();
  }
}

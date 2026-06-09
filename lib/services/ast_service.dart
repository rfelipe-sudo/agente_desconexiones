import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ast_registro.dart';
import '../utils/image_compress_util.dart';

class AstService {
  final SupabaseClient _client = Supabase.instance.client;
  static const _table = 'ast_registros';

  /// Comprime y devuelve payload jsonb listo para Supabase.
  Future<Map<String, dynamic>?> comprimirImagen(
    File file, {
    String? label,
    int maxWidth = 1024,
    int quality = 65,
  }) =>
      ImageCompressUtil.fileToCompressedPayload(
        file.path,
        label: label,
        maxWidth: maxWidth,
        quality: quality,
      );

  Future<String> insertarAST(ASTRegistro registro) async {
    final row = await _client.from(_table).insert(registro.toJson()).select('id').single();
    return row['id'] as String;
  }

  Future<Map<String, dynamic>> obtenerPorId(String id) async {
    final row = await _client.from(_table).select().eq('id', id).single();
    return Map<String, dynamic>.from(row as Map);
  }

  Future<List<Map<String, dynamic>>> listarPorTecnico(
    String rut, {
    DateTime? desde,
  }) async {
    var q = _client
        .from(_table)
        .select(
          'id, orden_trabajo, lugar_actividad, condiciones_criticas, '
          'estado_herramientas, fecha_hora, nombre_tecnico',
        )
        .eq('rut_tecnico', rut);
    if (desde != null) {
      q = q.gte('fecha_hora', desde.toUtc().toIso8601String());
    }
    final data = await q.order('fecha_hora', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Última OT con AST guardado para el técnico (fallback sin orden activa).
  Future<String?> obtenerUltimaOrdenTrabajo(String rut) async {
    final row = await _client
        .from(_table)
        .select('orden_trabajo')
        .eq('rut_tecnico', rut)
        .order('fecha_hora', ascending: false)
        .limit(1)
        .maybeSingle();
    return row?['orden_trabajo'] as String?;
  }
}

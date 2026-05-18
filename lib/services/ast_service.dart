import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ast_registro.dart';

class AstService {
  final SupabaseClient _client = Supabase.instance.client;
  static const _bucket = 'ast-imagenes';
  static const _table  = 'ast_registros';

  Future<String> subirImagen(File file, String nombre) async {
    final bytes = await file.readAsBytes();
    await _client.storage.from(_bucket).uploadBinary(
      nombre,
      bytes,
      fileOptions: const FileOptions(upsert: true),
    );
    return _client.storage.from(_bucket).getPublicUrl(nombre);
  }

  Future<void> guardarAST(ASTRegistro registro) async {
    await _client.from(_table).insert(registro.toJson());
  }
}

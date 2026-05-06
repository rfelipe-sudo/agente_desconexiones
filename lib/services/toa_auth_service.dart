import 'package:supabase_flutter/supabase_flutter.dart';

/// Trae las credenciales de Oracle TOA / etadirect del técnico desde
/// Supabase (`credenciales_toa`). Solo lectura.
///
/// **Importante**: las credenciales **nunca** se loguean, ni se persisten
/// en SharedPreferences, ni se exponen en UI. Viven solo en memoria del
/// state que las pidió, el tiempo que la pantalla esté abierta.
class ToaAuthService {
  ToaAuthService();

  final SupabaseClient _supabase = Supabase.instance.client;

  /// Devuelve `{'usuario': ..., 'email': ..., 'pass': ...}` o `null` si no
  /// encuentra credenciales activas para ese RUT.
  ///
  /// - `usuario` (`usuario_toa`): se inyecta en el campo `#sso_username`
  ///   de etadirect (paso 2 del flujo SSO).
  /// - `email` (`email_sso`): se inyecta en el campo de email de
  ///   Microsoft Entra ID (paso 3, dominio `login.microsoftonline.com`).
  /// - `pass` (`pass_toa`): se inyecta en el campo de password de Entra
  ///   (paso 4).
  Future<Map<String, String>?> getCredenciales(String rut) async {
    final r = rut.trim();
    if (r.isEmpty) return null;

    try {
      final row = await _supabase
          .from('credenciales_toa')
          .select('usuario_toa, email_sso, pass_toa')
          .eq('rut', r)
          .eq('activo', true)
          .maybeSingle();

      if (row == null) return null;
      final usuario = row['usuario_toa']?.toString() ?? '';
      final email = row['email_sso']?.toString() ?? '';
      final pass = row['pass_toa']?.toString() ?? '';
      // Mínimo viable: usuario + pass. El email puede caer al usuario si la
      // columna no está poblada (algunos tenants aceptan el username como email).
      if (usuario.isEmpty || pass.isEmpty) return null;
      return {
        'usuario': usuario,
        'email': email.isEmpty ? usuario : email,
        'pass': pass,
      };
    } catch (_) {
      // No exponer detalles del error: podría arrastrar credenciales en log.
      return null;
    }
  }
}

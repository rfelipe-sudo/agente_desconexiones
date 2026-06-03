import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AlertaSistemaService {
  final _db = Supabase.instance.client;

  /// Inserta un registro de fallo en alertas_sistema y notifica a todos los admins por FCM.
  Future<void> registrarFallo({
    required String modulo,
    required String tipoError,
    required String mensaje,
    String? rutTecnico,
    String? nombreTecnico,
    String? solicitudId,
  }) async {
    try {
      await _db.from('alertas_sistema').insert({
        'modulo':          modulo,
        'tipo_error':      tipoError,
        'mensaje':         mensaje,
        if (rutTecnico    != null) 'rut_tecnico':    rutTecnico,
        if (nombreTecnico != null) 'nombre_tecnico': nombreTecnico,
        if (solicitudId   != null) 'solicitud_id':   solicitudId,
        'estado': 'nueva',
      });
      debugPrint('🔴 [AlertaSistema] $modulo/$tipoError registrado');
      await _notificarAdmins(modulo: modulo, mensaje: mensaje, nombreTecnico: nombreTecnico);
    } catch (e) {
      debugPrint('⚠️ [AlertaSistema] error al registrar fallo: $e');
    }
  }

  Future<void> _notificarAdmins({
    required String modulo,
    required String mensaje,
    String? nombreTecnico,
  }) async {
    try {
      final rows = await _db.from('administradores').select('fcm_token');
      final desc = nombreTecnico != null
          ? '[$modulo] Fallo para $nombreTecnico: $mensaje'
          : '[$modulo] $mensaje';

      for (final row in (rows as List)) {
        final token = row['fcm_token'] as String?;
        if (token == null || token.isEmpty) continue;
        try {
          await _db.functions.invoke('fcm-send', body: {
            'token':       token,
            'accion':      'alerta_sistema',
            'tipo':        'Alerta de sistema',
            'descripcion': desc,
          });
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('⚠️ [AlertaSistema] error al notificar admins: $e');
    }
  }

  /// Marca una alerta como revisada por el administrador que la revisó.
  Future<void> marcarRevisada({
    required String alertaId,
    required String rutAdmin,
  }) async {
    await _db.from('alertas_sistema').update({
      'estado':      'revisada',
      'revisada_en': DateTime.now().toIso8601String(),
      'revisada_por': rutAdmin,
    }).eq('id', alertaId);
  }

  /// Devuelve las últimas [limite] alertas ordenadas por timestamp DESC.
  Future<List<Map<String, dynamic>>> listarAlertas({
    String? filtroEstado,
    int limite = 100,
  }) async {
    if (filtroEstado != null) {
      final rows = await _db
          .from('alertas_sistema')
          .select()
          .eq('estado', filtroEstado)
          .order('timestamp', ascending: false)
          .limit(limite);
      return rows;
    }
    final rows = await _db
        .from('alertas_sistema')
        .select()
        .order('timestamp', ascending: false)
        .limit(limite);
    return rows;
  }

  /// Cuenta alertas nuevas (para badge).
  Future<int> contarNuevas() async {
    final res = await _db
        .from('alertas_sistema')
        .select()
        .eq('estado', 'nueva');
    return (res as List).length;
  }
}

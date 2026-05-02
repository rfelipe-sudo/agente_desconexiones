import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  // ═══════════════════════════════════════════════════════════
  // ALERTAS DE FRAUDE
  // ═══════════════════════════════════════════════════════════

  // Enviar alerta de fraude (desde app técnico)
  Future<bool> enviarAlertaFraude({
    required String ot,
    required String tecnicoId,
    required String nombreTecnico,
    required int pasosRealizados,
    required double distanciaRecorrida,
    required List<String> razonesFallo,
    double? latitud,
    double? longitud,
    String tipo = 'no_se_bajo',
  }) async {
    try {
      await _client.from('alertas_fraude').insert({
        'tipo': tipo,
        'ot': ot,
        'tecnico_id': tecnicoId,
        'nombre_tecnico': nombreTecnico,
        'pasos_realizados': pasosRealizados,
        'distancia_recorrida': distanciaRecorrida,
        'razones_fallo': razonesFallo,
        'latitud': latitud,
        'longitud': longitud,
        'estado': 'pendiente',
      });
      print('🚨 Alerta de fraude ($tipo) enviada a Supabase');
      return true;
    } catch (e) {
      print('❌ Error enviando alerta: $e');
      return false;
    }
  }

  // Obtener alertas pendientes (para app supervisor)
  Future<List<Map<String, dynamic>>> obtenerAlertasPendientes() async {
    try {
      final response = await _client
          .from('alertas_fraude')
          .select()
          .eq('estado', 'pendiente')
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo alertas: $e');
      return [];
    }
  }

  // Marcar alerta como revisada
  Future<bool> revisarAlerta(
      String alertaId, String accion, String? comentario) async {
    try {
      await _client.from('alertas_fraude').update({
        'estado': accion,
        'comentario_revision': comentario,
        'fecha_revision': DateTime.now().toIso8601String(),
      }).eq('id', alertaId);

      return true;
    } catch (e) {
      print('❌ Error revisando alerta: $e');
      return false;
    }
  }

  // Stream de alertas en tiempo real (para supervisor)
  Stream<List<Map<String, dynamic>>> streamAlertasFraude() {
    return _client
        .from('alertas_fraude')
        .stream(primaryKey: ['id'])
        .eq('estado', 'pendiente')
        .order('created_at', ascending: false);
  }

  // ═══════════════════════════════════════════════════════════
  // FOTOS CHURN
  // ═══════════════════════════════════════════════════════════

  // Subir foto de evidencia CHURN
  Future<String?> subirFotoChurn(File foto, String ot) async {
    try {
      final fileName = '${ot}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final path = '$ot/$fileName';

      await _client.storage.from('fotos-churn').upload(path, foto);

      final url = _client.storage.from('fotos-churn').getPublicUrl(path);

      print('📷 Foto subida: $url');
      return url;
    } catch (e) {
      print('❌ Error subiendo foto: $e');
      return null;
    }
  }

  // Registrar foto en base de datos
  Future<bool> registrarFotoChurn({
    required String ot,
    required String fotoUrl,
    String? tecnicoId,
    String? nombreTecnico,
  }) async {
    try {
      await _client.from('fotos_churn').insert({
        'ot': ot,
        'foto_url': fotoUrl,
        'tecnico_id': tecnicoId,
        'nombre_tecnico': nombreTecnico,
        'estado': 'pendiente',
      });
      return true;
    } catch (e) {
      print('❌ Error registrando foto: $e');
      return false;
    }
  }

  // Obtener fotos pendientes de validación (para calidad)
  Future<List<Map<String, dynamic>>> obtenerFotosPendientes() async {
    try {
      final response = await _client
          .from('fotos_churn')
          .select()
          .eq('estado', 'pendiente')
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo fotos: $e');
      return [];
    }
  }

  // Validar foto (para calidad)
  Future<bool> validarFoto(
      String fotoId, String estado, String? comentario) async {
    try {
      await _client.from('fotos_churn').update({
        'estado': estado,
        'comentario_calidad': comentario,
        'fecha_validacion': DateTime.now().toIso8601String(),
      }).eq('id', fotoId);

      return true;
    } catch (e) {
      print('❌ Error validando foto: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // UBICACIÓN TÉCNICOS (TIPO UBER)
  // ═══════════════════════════════════════════════════════════

  // Actualizar ubicación del técnico
  Future<bool> actualizarUbicacion({
    required String tecnicoId,
    required String nombre,
    required double latitud,
    required double longitud,
    String? telefono,
    String? estado,
    String? otActual,
  }) async {
    try {
      await _client.from('tecnicos_ubicacion').upsert({
        'tecnico_id': tecnicoId,
        'nombre': nombre,
        'telefono': telefono,
        'latitud': latitud,
        'longitud': longitud,
        'estado': estado ?? 'disponible',
        'ot_actual': otActual,
        'ultima_actualizacion': DateTime.now().toIso8601String(),
        'en_linea': true,
      }, onConflict: 'tecnico_id');

      return true;
    } catch (e) {
      print('❌ Error actualizando ubicación: $e');
      return false;
    }
  }

  // Marcar técnico como offline
  Future<bool> marcarOffline(String tecnicoId) async {
    try {
      await _client.from('tecnicos_ubicacion').update({
        'en_linea': false,
        'ultima_actualizacion': DateTime.now().toIso8601String(),
      }).eq('tecnico_id', tecnicoId);

      return true;
    } catch (e) {
      print('❌ Error marcando offline: $e');
      return false;
    }
  }

  // Obtener todos los técnicos en línea
  Future<List<Map<String, dynamic>>> obtenerTecnicosEnLinea() async {
    try {
      final response = await _client
          .from('tecnicos_ubicacion')
          .select()
          .eq('en_linea', true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo técnicos: $e');
      return [];
    }
  }

  // Stream de ubicaciones en tiempo real (para mapa tipo Uber)
  Stream<List<Map<String, dynamic>>> streamTecnicosUbicacion() {
    return _client
        .from('tecnicos_ubicacion')
        .stream(primaryKey: ['id'])
        .eq('en_linea', true);
  }

  // ─────────────────────────────────────────────────────────
  // REGISTRO DE TÉCNICOS (RUT ↔ Nombre)
  // ─────────────────────────────────────────────────────────

  Future<bool> registrarTecnico({
    required String rut,
    required String telefono,
    required String deviceId,
  }) async {
    try {
      await _client.from('tecnicos_registro').upsert({
        'rut': rut,
        'telefono': telefono,
        'device_id': deviceId,
        'activo': true,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'rut');
      print('✅ Técnico registrado: $rut');
      return true;
    } catch (e) {
      print('❌ Error registrando técnico: $e');
      return false;
    }
  }

  Future<bool> actualizarNombreTecnico({
    required String rut,
    required String nombre,
    required String nombreFull,
  }) async {
    try {
      await _client.from('tecnicos_registro').update({
        'nombre': nombre,
        'nombre_full': nombreFull,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('rut', rut);
      print('✅ Nombre actualizado para $rut: $nombre');
      return true;
    } catch (e) {
      print('❌ Error actualizando nombre: $e');
      return false;
    }
  }

  Future<String?> obtenerNombrePorRut(String rut) async {
    try {
      final response = await _client
          .from('tecnicos_registro')
          .select('nombre, nombre_full')
          .eq('rut', rut)
          .maybeSingle();

      if (response != null) {
        return response['nombre'] ?? response['nombre_full'];
      }
      return null;
    } catch (e) {
      print('❌ Error obteniendo nombre: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> obtenerTecnicoPorRut(String rut) async {
    try {
      final response = await _client
          .from('tecnicos_registro')
          .select()
          .eq('rut', rut)
          .maybeSingle();
      return response;
    } catch (e) {
      print('❌ Error obteniendo técnico: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────
  // ALERTAS CTO (guardar y gestionar)
  // ─────────────────────────────────────────────────────────

  Future<bool> guardarAlertaCTO({
    required String alertaId,
    required String ot,
    String? accessId,
    String? tecnico,
    String? tecnicoFull,
    String? actividad,
    List<Map<String, dynamic>>? puertosAfectados,
    List<Map<String, dynamic>>? nivelesInicial,
    List<Map<String, dynamic>>? nivelesFinal,
  }) async {
    try {
      await _client.from('alertas_cto').upsert({
        'alerta_id': alertaId,
        'ot': ot,
        'access_id': accessId,
        'tecnico': tecnico,
        'tecnico_full': tecnicoFull,
        'actividad': actividad,
        'puertos_afectados': puertosAfectados,
        'niveles_inicial': nivelesInicial,
        'niveles_final': nivelesFinal,
        'estado': 'pendiente',
        'fecha_alerta': DateTime.now().toIso8601String(),
      }, onConflict: 'alerta_id');
      print('✅ Alerta CTO guardada: $ot');
      return true;
    } catch (e) {
      print('❌ Error guardando alerta CTO: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> obtenerAlertasCTOPendientes() async {
    try {
      final response = await _client
          .from('alertas_cto')
          .select()
          .eq('estado', 'pendiente')
          .order('fecha_alerta', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo alertas CTO: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> obtenerAlertasCTOHistorial() async {
    try {
      final response = await _client
          .from('alertas_cto')
          .select()
          .eq('estado', 'solucionado')
          .order('fecha_solucion', ascending: false)
          .limit(50);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo historial CTO: $e');
      return [];
    }
  }

  Future<bool> marcarAlertaCTOSolucionada(String alertaId, {String? notas}) async {
    try {
      await _client.from('alertas_cto').update({
        'estado': 'solucionado',
        'fecha_solucion': DateTime.now().toIso8601String(),
        'notas': notas,
      }).eq('alerta_id', alertaId);
      print('✅ Alerta CTO marcada como solucionada: $alertaId');
      return true;
    } catch (e) {
      print('❌ Error marcando alerta solucionada: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> obtenerAlertaCTOPorOT(String ot) async {
    try {
      final response = await _client
          .from('alertas_cto')
          .select()
          .eq('ot', ot)
          .eq('estado', 'pendiente')
          .maybeSingle();
      return response;
    } catch (e) {
      print('❌ Error obteniendo alerta por OT: $e');
      return null;
    }
  }
}


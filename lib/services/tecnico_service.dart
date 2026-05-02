import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Modelo de datos del técnico
class TecnicoData {
  final String deviceId;
  final String telefono;
  final String nombre;
  final String rol;
  final DateTime createdAt;

  TecnicoData({
    required this.deviceId,
    required this.telefono,
    required this.nombre,
    this.rol = 'tecnico',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory TecnicoData.fromJson(Map<String, dynamic> json) {
    return TecnicoData(
      deviceId: json['device_id'] ?? '',
      telefono: json['telefono'] ?? '',
      nombre: json['nombre'] ?? '',
      rol: json['rol'] ?? 'tecnico',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'telefono': telefono,
    'nombre': nombre,
    'rol': rol,
    'created_at': createdAt.toIso8601String(),
  };

  bool get esTecnico => rol == 'tecnico';
  bool get esSupervisor => rol == 'supervisor';
}

/// Servicio para manejar el registro automático de técnicos
class TecnicoService {
  static const String _storageKey = 'tecnico_registrado';
  static final SupabaseClient _supabase = Supabase.instance.client;
  
  // Simular base de datos local (en producción sería el backend)
  static final Map<String, TecnicoData> _mockDatabase = {};

  /// Obtiene el Android ID del dispositivo
  static Future<String> getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    
    // El Android ID es único por dispositivo
    final androidId = androidInfo.id;
    print('📱 Android ID obtenido: $androidId');
    return androidId;
  }

  /// Verifica si el dispositivo ya está registrado
  /// Retorna los datos del técnico si existe, null si no
  static Future<TecnicoData?> verificarRegistro() async {
    try {
      final deviceId = await getDeviceId();
      
      // Primero verificar en storage local
      final prefs = await SharedPreferences.getInstance();
      final tecnicoJson = prefs.getString(_storageKey);
      
      if (tecnicoJson != null) {
        final tecnico = TecnicoData.fromJson(jsonDecode(tecnicoJson));
        if (tecnico.deviceId == deviceId) {
          print('✅ Técnico encontrado en storage local: ${tecnico.nombre}');
          return tecnico;
        }
      }
      
      // Simular llamada al backend: GET /tecnico/{device_id}
      // En producción: final response = await http.get('/tecnico/$deviceId');
      if (_mockDatabase.containsKey(deviceId)) {
        final tecnico = _mockDatabase[deviceId]!;
        // Guardar en storage local para próximas consultas
        await _guardarEnLocal(tecnico);
        print('✅ Técnico encontrado en servidor: ${tecnico.nombre}');
        return tecnico;
      }
      
      print('❌ Dispositivo no registrado: $deviceId');
      return null;
    } catch (e) {
      print('❌ Error verificando registro: $e');
      return null;
    }
  }

  /// Registra un nuevo técnico
  static Future<TecnicoData?> registrarTecnico({
    required String telefono,
    required String nombre,
    String rol = 'tecnico',
  }) async {
    try {
      final deviceId = await getDeviceId();
      
      final tecnico = TecnicoData(
        deviceId: deviceId,
        telefono: telefono,
        nombre: nombre,
        rol: rol,
      );
      
      // Simular llamada al backend: POST /tecnico
      // En producción: final response = await http.post('/tecnico', body: tecnico.toJson());
      _mockDatabase[deviceId] = tecnico;
      
      // Guardar en storage local
      await _guardarEnLocal(tecnico);
      
      print('✅ Técnico registrado: ${tecnico.nombre} (${tecnico.telefono})');
      return tecnico;
    } catch (e) {
      print('❌ Error registrando técnico: $e');
      return null;
    }
  }

  /// Guarda los datos del técnico en storage local
  static Future<void> _guardarEnLocal(TecnicoData tecnico) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(tecnico.toJson()));
  }

  /// Elimina el registro local (para pruebas/desarrollo)
  static Future<void> limpiarRegistro() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    print('🧹 Registro local limpiado');
  }

  /// Obtiene el device ID actual
  static Future<String> obtenerDeviceIdActual() async {
    return await getDeviceId();
  }

  /// Valida que el RUT exista en produccion_crea y obtiene el nombre del técnico
  /// Retorna un mapa con 'nombre' si existe, null si no
  static Future<Map<String, dynamic>?> validarRutEnProduccion(String rut) async {
    try {
      print('🔍 [ValidarRUT] ════════════════════════════════');
      print('🔍 [ValidarRUT] RUT ingresado: "$rut"');
      print('🔍 [ValidarRUT] Longitud: ${rut.length}');
      
      final response = await _supabase
          .from('produccion_crea')
          .select('rut_tecnico, tecnico')  // ✅ CORREGIDO: era 'nombre_tecnico'
          .eq('rut_tecnico', rut)
          .limit(1)
          .maybeSingle();

      print('🔍 [ValidarRUT] Respuesta: $response');
      print('🔍 [ValidarRUT] Response es null: ${response == null}');
      
      if (response != null) {
        print('🔍 [ValidarRUT] Keys en response: ${response.keys}');
        print('🔍 [ValidarRUT] tecnico: ${response['tecnico']}');  // ✅ CORREGIDO
      }

      if (response != null && response['tecnico'] != null) {  // ✅ CORREGIDO
        final nombre = response['tecnico'].toString();  // ✅ CORREGIDO
        print('✅ [ValidarRUT] RUT encontrado: $nombre');
        print('🔍 [ValidarRUT] ════════════════════════════════');
        return {
          'rut': rut,
          'nombre': nombre,
          'existe': true,
        };
      }

      print('❌ [ValidarRUT] RUT NO encontrado: $rut');
      print('🔍 [ValidarRUT] ════════════════════════════════');
      return null;
    } catch (e) {
      print('❌ [ValidarRUT] Error: $e');
      print('🔍 [ValidarRUT] ════════════════════════════════');
      return null;
    }
  }
}

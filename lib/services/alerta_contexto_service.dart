import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:agente_desconexiones/models/alerta.dart';

/// Estado de una alerta en el contexto de conversación
enum EstadoContextoAlerta {
  nueva,
  enProgreso,
  regularizada,
}

/// Modelo para el contexto de una alerta
class ContextoAlerta {
  final String numeroOt;
  final EstadoContextoAlerta estado;
  final int pelo;
  final String cto;
  final double consulta1;
  final DateTime ultimoContacto;

  ContextoAlerta({
    required this.numeroOt,
    required this.estado,
    required this.pelo,
    required this.cto,
    required this.consulta1,
    required this.ultimoContacto,
  });

  Map<String, dynamic> toJson() => {
        'numero_ot': numeroOt,
        'estado': estado.name,
        'pelo': pelo,
        'cto': cto,
        'consulta1': consulta1,
        'ultimo_contacto': ultimoContacto.toIso8601String(),
      };

  factory ContextoAlerta.fromJson(Map<String, dynamic> json) {
    return ContextoAlerta(
      numeroOt: json['numero_ot'] as String,
      estado: EstadoContextoAlerta.values.firstWhere(
        (e) => e.name == json['estado'],
        orElse: () => EstadoContextoAlerta.nueva,
      ),
      pelo: json['pelo'] as int,
      cto: json['cto'] as String,
      consulta1: (json['consulta1'] as num).toDouble(),
      ultimoContacto: DateTime.parse(json['ultimo_contacto'] as String),
    );
  }

  ContextoAlerta copyWith({
    String? numeroOt,
    EstadoContextoAlerta? estado,
    int? pelo,
    String? cto,
    double? consulta1,
    DateTime? ultimoContacto,
  }) {
    return ContextoAlerta(
      numeroOt: numeroOt ?? this.numeroOt,
      estado: estado ?? this.estado,
      pelo: pelo ?? this.pelo,
      cto: cto ?? this.cto,
      consulta1: consulta1 ?? this.consulta1,
      ultimoContacto: ultimoContacto ?? this.ultimoContacto,
    );
  }
}

/// Servicio para gestionar el contexto de conversaciones de alertas
class AlertaContextoService {
  static final AlertaContextoService _instance = AlertaContextoService._internal();
  factory AlertaContextoService() => _instance;
  AlertaContextoService._internal();

  // Usar keys individuales por OT: "alerta_estado_{ot}"
  String _getKeyForOt(String ot) => 'alerta_estado_$ot';
  
  // Cache en memoria para acceso rápido
  Map<String, ContextoAlerta> _contextos = {};

  /// Inicializa el servicio cargando los contextos guardados
  Future<void> initialize() async {
    try {
      print('📦 Inicializando AlertaContextoService...');
      final prefs = await SharedPreferences.getInstance();
      
      // Obtener todas las keys de forma segura
      Set<String> keys;
      try {
        keys = prefs.getKeys();
      } catch (e) {
        print('⚠️ Error obteniendo keys de SharedPreferences: $e');
        _contextos = {};
        return;
      }
      
      // Cargar todas las keys que empiezan con "alerta_estado_"
      _contextos.clear();
      int loadedCount = 0;
      
      for (final key in keys) {
        try {
          if (key.startsWith('alerta_estado_')) {
            final ot = key.replaceFirst('alerta_estado_', '');
            if (ot.isEmpty) continue;
            
            final jsonString = prefs.getString(key);
            if (jsonString != null && jsonString.isNotEmpty) {
              try {
                final data = jsonDecode(jsonString) as Map<String, dynamic>;
                _contextos[ot] = ContextoAlerta.fromJson(data);
                loadedCount++;
              } catch (e) {
                print('⚠️ Error parseando contexto para $ot: $e');
                // Continuar con la siguiente key
              }
            }
          }
        } catch (e) {
          print('⚠️ Error procesando key $key: $e');
          // Continuar con la siguiente key
        }
      }
      
      print('📦 Contextos de alertas cargados: $loadedCount');
    } catch (e, stackTrace) {
      print('❌ Error cargando contextos: $e');
      print('Stack trace: $stackTrace');
      _contextos = {};
    }
  }

  /// Obtiene el contexto de una alerta por su número de OT
  ContextoAlerta? obtenerContexto(String numeroOt) {
    return _contextos[numeroOt];
  }

  /// Obtiene el estado de una alerta
  EstadoContextoAlerta obtenerEstado(String numeroOt) {
    final contexto = _contextos[numeroOt];
    return contexto?.estado ?? EstadoContextoAlerta.nueva;
  }

  /// Crea o actualiza el contexto de una alerta
  Future<void> actualizarContexto(Alerta alerta, {EstadoContextoAlerta? nuevoEstado}) async {
    try {
      final peloNum = int.tryParse(alerta.numeroPelo.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      
      final contextoExistente = _contextos[alerta.numeroOt];
      final estado = nuevoEstado ?? 
          contextoExistente?.estado ?? 
          EstadoContextoAlerta.nueva;

      final contexto = ContextoAlerta(
        numeroOt: alerta.numeroOt,
        estado: estado,
        pelo: peloNum,
        cto: alerta.nombreCto,
        consulta1: alerta.valorConsulta1,
        ultimoContacto: DateTime.now(),
      );

      _contextos[alerta.numeroOt] = contexto;
      await _guardarContextoIndividual(alerta.numeroOt, contexto);
      
      print('💾 Contexto actualizado para ${alerta.numeroOt}: ${estado.name}');
    } catch (e) {
      print('❌ Error actualizando contexto: $e');
    }
  }

  /// Marca una alerta como nueva (primera vez que se abre)
  Future<void> marcarComoNueva(Alerta alerta) async {
    await actualizarContexto(alerta, nuevoEstado: EstadoContextoAlerta.nueva);
  }

  /// Marca una alerta como en progreso (conversación iniciada pero no regularizada)
  Future<void> marcarComoEnProgreso(Alerta alerta) async {
    await actualizarContexto(alerta, nuevoEstado: EstadoContextoAlerta.enProgreso);
  }

  /// Marca una alerta como regularizada
  Future<void> marcarComoRegularizada(Alerta alerta) async {
    await actualizarContexto(alerta, nuevoEstado: EstadoContextoAlerta.regularizada);
  }

  /// Calcula el primer mensaje según el estado de la alerta
  /// Esta función se usa para enviar el firstMessage a ElevenLabs
  /// TONO: Siempre positivo y motivador
  String calcularPrimerMensaje(Alerta alerta, String nombreTecnico) {
    final estado = obtenerEstado(alerta.numeroOt);
    
    // Extraer número del pelo (ej: "P-04" -> "4", "2" -> "2")
    final peloNum = alerta.numeroPelo.replaceAll(RegExp(r'[^0-9]'), '');
    final peloNumero = peloNum.isEmpty ? alerta.numeroPelo : peloNum;
    
    // Potencia anterior (consulta1) y actual (consulta2, si existe o 0 si no hay)
    // Formato simple: solo el número sin decimales ni unidad
    final potenciaAnterior = alerta.valorConsulta1.toInt().toString();
    final potenciaActual = alerta.valorConsulta2?.toInt().toString() ?? '0';

    if (estado == EstadoContextoAlerta.nueva) {
      return '¡Hola $nombreTecnico! Soy CREA, tu asistente. '
             'Tenemos una alerta en el pelo $peloNumero. '
             'La potencia inicial era $potenciaAnterior y ahora está en $potenciaActual. '
             'Sé que puedes resolverlo, avísame cuando lo revises y actualizamos juntos.';
    } else {
      return '¡Hola de nuevo $nombreTecnico! '
             'Veo que sigues con la alerta del pelo $peloNumero. '
             '¿Ya pudiste revisarlo? Estoy aquí para ayudarte.';
    }
  }

  /// Genera el mensaje inicial según el estado de la alerta
  /// [estadoForzado] permite usar un estado concreto sin depender de lo persistido
  /// Esta función mantiene compatibilidad con el código existente
  String generarMensajeInicial(Alerta alerta, {EstadoContextoAlerta? estadoForzado}) {
    final estado = estadoForzado ?? obtenerEstado(alerta.numeroOt);
    
    // Usar calcularPrimerMensaje si el estado coincide
    if (estadoForzado == null || estadoForzado == estado) {
      return calcularPrimerMensaje(alerta, alerta.nombreTecnico);
    }
    
    // Si hay un estado forzado diferente, usar la lógica anterior
    final peloNum = alerta.numeroPelo.replaceAll(RegExp(r'[^0-9]'), '');
    final peloNumero = peloNum.isEmpty ? alerta.numeroPelo : peloNum;
    final valorConsulta = alerta.valorConsulta1.toStringAsFixed(2);

    switch (estado) {
      case EstadoContextoAlerta.nueva:
        return 'Hola ${alerta.nombreTecnico}, soy CREA. Mira, en la instalación que estás trabajando se generó una alerta por desconexión en el pelo $peloNumero de la CTO ${alerta.nombreCto}. Antes tenía $valorConsulta dBm y ahora no tiene potencia. Avísame cuando revises para refrescar el estado de la CTO y que solucionemos la alerta.';
      
      case EstadoContextoAlerta.enProgreso:
        return 'Hola ${alerta.nombreTecnico}, soy CREA. Veo que vuelves por la alerta del pelo $peloNumero en la CTO ${alerta.nombreCto}. ¿Ya pudiste revisarlo para que actualice el estado?';
      
      case EstadoContextoAlerta.regularizada:
        return 'Hola ${alerta.nombreTecnico}, soy CREA. Esta alerta ya está regularizada. ¿Hay algo más en lo que pueda ayudarte?';
    }
  }

  /// Guarda un contexto individual en SharedPreferences usando key "alerta_estado_{ot}"
  Future<void> _guardarContextoIndividual(String ot, ContextoAlerta contexto) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getKeyForOt(ot);
      final jsonString = jsonEncode(contexto.toJson());
      await prefs.setString(key, jsonString);
      print('💾 Contexto guardado para $ot en key: $key');
    } catch (e) {
      print('❌ Error guardando contexto para $ot: $e');
    }
  }

  /// Limpia todos los contextos (útil para pruebas)
  Future<void> limpiarContextos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      // Eliminar todas las keys que empiezan con "alerta_estado_"
      for (final key in keys) {
        if (key.startsWith('alerta_estado_')) {
          await prefs.remove(key);
        }
      }
      
      _contextos.clear();
      print('🗑️ Contextos limpiados');
    } catch (e) {
      print('❌ Error limpiando contextos: $e');
    }
  }
  
  /// Limpia el contexto de una alerta específica
  Future<void> limpiarContexto(String ot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getKeyForOt(ot);
      await prefs.remove(key);
      _contextos.remove(ot);
      print('🗑️ Contexto limpiado para $ot');
    } catch (e) {
      print('❌ Error limpiando contexto para $ot: $e');
    }
  }
}



import 'dart:async';
import 'package:agente_desconexiones/models/alerta.dart';
import 'package:agente_desconexiones/services/mock_database_service.dart';
import 'package:agente_desconexiones/services/local_notification_service.dart';
import 'package:agente_desconexiones/services/deteccion_caminata_service.dart';

/// Servicio que simula el webhook de Kepler
/// En producción, este servicio recibirá las alertas desde el panel Kepler
class KeplerWebhookService {
  static final KeplerWebhookService _instance = KeplerWebhookService._internal();
  factory KeplerWebhookService() => _instance;
  KeplerWebhookService._internal();

  final MockDatabaseService _mockDb = MockDatabaseService();
  final LocalNotificationService _notificationService = LocalNotificationService();
  final DeteccionCaminataService _deteccionService = DeteccionCaminataService();
  
  // Stream para notificar nuevas alertas
  final StreamController<Alerta> _alertaStreamController = 
      StreamController<Alerta>.broadcast();
  
  Stream<Alerta> get alertasStream => _alertaStreamController.stream;

  /// Simula la recepción de un webhook desde Kepler
  /// En producción, este método será llamado por el servidor cuando detecte una desconexión
  Future<void> recibirWebhookAlerta(Map<String, dynamic> datosWebhook) async {
    print('📡 Webhook recibido desde Kepler: $datosWebhook');
    
    try {
      // Parsear alerta desde el webhook
      final alerta = Alerta.fromWebhook(datosWebhook);
      
      // La alerta se guardará automáticamente cuando se agregue a la lista en el provider
      
      // Emitir al stream
      _alertaStreamController.add(alerta);
      
      // Mostrar notificación con sonido de llamada
      await _notificationService.mostrarAlertaComoLlamada(alerta);
      
      print('✅ Alerta procesada: ${alerta.numeroOt}');
    } catch (e) {
      print('❌ Error procesando webhook: $e');
    }
  }

  /// Simula una alerta de desconexión desde Kepler (para pruebas)
  Future<void> simularAlertaDesdeKepler({
    String? nombreTecnico,
    String? telefonoTecnico,
    String? numeroOt,
    String? accessId,
    String? nombreCto,
    String? numeroPelo,
    double? valorConsulta1,
    TipoAlerta? tipoAlerta,
  }) async {
    // Generar datos de webhook simulados
    final datosWebhook = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'nombre_tecnico': nombreTecnico ?? 'Juan Pérez',
      'telefono_tecnico': telefonoTecnico ?? '+56 9 1234 5678',
      'numero_ot': numeroOt ?? 'OT-2024-${DateTime.now().millisecondsSinceEpoch}',
      'access_id': accessId ?? 'ACC-${DateTime.now().millisecondsSinceEpoch}',
      'nombre_cto': nombreCto ?? 'CTO-SANTIAGO-001',
      'numero_pelo': numeroPelo ?? '2', // Pelo 2 por defecto
      'valor_consulta1': valorConsulta1 ?? -21.20, // Valor correcto por defecto
      'tipo_alerta': tipoAlerta?.name ?? 'desconexion',
      'fecha_recepcion': DateTime.now().toIso8601String(),
      'empresa': 'CREA',
      'actividad': 'Desconexión',
    };
    
    await recibirWebhookAlerta(datosWebhook);
  }

  /// Procesar webhook cuando llega trabajo iniciado desde Kepler
  Future<void> procesarTrabajoIniciado(Map<String, dynamic> data) async {
    /*
    Formato esperado desde Kepler:
    {
      "tipo": "trabajo_iniciado" o "orden_iniciada",
      "ot": "1-3GEHGXBC",
      "tecnico_id": "TEC-001",
      "nombre_tecnico": "Juan Pérez",
      "direccion": "Av. Principal 123, Santiago",
      "timestamp": "2025-12-10T10:30:00Z"
    }
    */

    // Detectar si es una orden iniciada (activar monitoreo automático)
    if (data['tipo'] == 'trabajo_iniciado' || 
        data['tipo'] == 'orden_iniciada' ||
        data['actividad'] == 'Inicio' ||
        data['actividad'] == 'En Ruta') {
      print('📥 Orden iniciada - Activando monitoreo anti-fraude automático');

      await _deteccionService.iniciarTrabajo(
        ot: data['ot'] ?? data['numero_ot'] ?? '',
        tecnicoId: data['tecnico_id'] ?? '',
        nombreTecnico: data['nombre_tecnico'] ?? '',
        direccion: data['direccion'] ?? '',
      );
    } else if (data['tipo'] == 'trabajo_finalizado' || 
               data['tipo'] == 'orden_finalizada' ||
               data['actividad'] == 'Completado' ||
               data['actividad'] == 'Finalizado') {
      print('📥 Orden finalizada - Cancelando monitoreo');
      _deteccionService.finalizarTrabajo();
    }
  }
  
  /// Procesar webhook genérico de Kepler (puede ser alerta o orden)
  Future<void> procesarWebhookKepler(Map<String, dynamic> data) async {
    // Si es una orden iniciada, activar monitoreo
    if (data['tipo'] == 'orden_iniciada' || 
        data['actividad'] == 'Inicio' ||
        data['actividad'] == 'En Ruta') {
      await procesarTrabajoIniciado(data);
    }
    
    // Si es una orden finalizada, cancelar monitoreo
    if (data['tipo'] == 'orden_finalizada' || 
        data['actividad'] == 'Completado' ||
        data['actividad'] == 'Finalizado') {
      await procesarTrabajoIniciado(data);
    }
    
    // Si es una alerta de desconexión, procesarla normalmente
    if (data['tipo'] == 'desconexion' || data['tipo_alerta'] != null) {
      await recibirWebhookAlerta(data);
    }
  }

  /// Procesar webhook de alerta de fraude desde Kepler
  /// En producción, este método será llamado cuando se detecte un intento de fraude
  Future<void> procesarAlertaFraude(Map<String, dynamic> data) async {
    print('🚨 Webhook recibido: Alerta de fraude ${data['ot']}');

    try {
      // Mostrar notificación al supervisor
      await _notificationService.mostrarAlertaFraude(
        tecnico: data['nombre_tecnico'] ?? 'Técnico',
        ot: data['ot'] ?? 'OT-UNKNOWN',
      );

      print('✅ Notificación de fraude enviada al supervisor');
    } catch (e) {
      print('❌ Error procesando alerta de fraude: $e');
    }
  }

  void dispose() {
    _alertaStreamController.close();
  }
}


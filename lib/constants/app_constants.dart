/// Constantes de la aplicación
class AppConstants {
  AppConstants._();

  // Nombre de la app
  static const String appName = 'CREABOX';
  static const String companyName = 'Creaciones Tecnológicas';
  
  // Tiempos (en segundos)
  static const int tiempoEscalamientoSegundos = 180;  // 3 minutos para escalar
  static const int tiempoPostergacionSegundos = 300;   // 5 minutos de postergación
  static const int tiempoConsultaProgresoSegundos = 1200; // 20 minutos para preguntar
  static const int tiempoMaximoAtencionSegundos = 3600;   // 1 hora máximo
  
  // URLs de API
  static const String apiBaseUrl = 'https://api.kepler.creacionestecnologicas.com';
  static const String webhookEndpoint = '/webhook/alertas';
  static const String alertasEndpoint = '/api/alertas';
  static const String verificarEstadoEndpoint = '/api/verificar-estado';
  
  // API Key para Kepler
  static const String keplerApiKey = 'F2ZFFWfwpVKVmT9XaJiFYigZInFYoeEBZfDPTKjyu3IZJcTG1vIUb3ccu7rQUOGT';
  
  /// Headers para requests a Kepler con Authorization Bearer
  static Map<String, String> get keplerHeaders => {
    'Authorization': 'Bearer $keplerApiKey',
    'Content-Type': 'application/json',
  };
  
  // ElevenLabs
  static const String elevenLabsAgentId = 'CREA_AGENT_ID'; // Reemplazar con ID real
  static const String elevenLabsVoiceId = 'CREA_VOICE_ID'; // Reemplazar con ID real
  
  // Notificaciones
  static const String notificationChannelId = 'alertas_desconexion';
  static const String notificationChannelName = 'Alertas de Desconexión';
  static const String notificationChannelDesc = 'Notificaciones de alertas de fibra óptica';
  static const String alertSoundFileName = 'alerta_urgente'; // Sin extensión
  
  /// Mapa calor, medición velocidad, microscopio fibra y Flota en Tu Mes: UI "Próximamente".
  static const bool modulosHerramientasProximamente = false;

  /// Monitoreo fraude (background), alertas CTO, polling Kepler/detención; listeners a Supabase.
  static const bool monitoreoFraudeYAlertasCtoActivo = false;

  // Storage keys
  static const String storageKeyUsuario = 'usuario_actual';
  static const String storageKeyAlertas = 'alertas_pendientes';
  static const String storageKeyFcmToken = 'fcm_token';
  static const String storageKeyPrimerInicio = 'primer_inicio';
}

/// Mensajes predefinidos del agente CREA
class CreaMessages {
  CreaMessages._();
  
  static const String saludoInicial = 
    'Hola, soy CREA, tu asistente de desconexiones. '
    'Veo que tienes una alerta en la CTO {cto}, pelo {pelo}. '
    '¿Puedes confirmar que estás en camino?';
    
  static const String consultaProgreso = 
    'Han pasado 20 minutos desde que iniciaste la atención. '
    '¿Cómo va el trabajo? ¿Necesitas más tiempo?';
    
  static const String solicitudFotosChurn = 
    'Esta alerta corresponde a un churn. '
    'Por favor, toma fotos georeferenciadas del estado actual de la CTO.';
    
  static const String transferenciaSupervidor = 
    'Entiendo. Voy a transferir esta alerta al supervisor. '
    'Mantente en línea mientras realizo la transferencia.';
    
  static const String confirmacionRegularizacion = 
    'Excelente trabajo. He verificado en el panel y la CTO ya está regularizada. '
    '¿Hay algo más en lo que pueda ayudarte?';
    
  static const String despedida = 
    'Gracias por tu trabajo. La alerta ha sido cerrada exitosamente. '
    '¡Hasta pronto!';
}


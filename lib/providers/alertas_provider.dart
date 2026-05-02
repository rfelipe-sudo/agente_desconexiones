import 'package:flutter/foundation.dart';
import 'package:agente_desconexiones/models/alerta.dart';
import 'package:agente_desconexiones/models/usuario.dart';
import 'package:agente_desconexiones/services/kepler_webhook_service.dart';
import 'package:agente_desconexiones/services/local_notification_service.dart';

class AlertasProvider extends ChangeNotifier {
  final List<Alerta> _alertas = [];
  bool _isLoading = false;
  final KeplerWebhookService _webhookService = KeplerWebhookService();
  final LocalNotificationService _notificationService = LocalNotificationService();

  List<Alerta> get alertas => List.unmodifiable(_alertas);
  bool get isLoading => _isLoading;

  /// Inicializar el provider con el usuario
  Future<void> initialize(Usuario usuario) async {
    _isLoading = true;
    notifyListeners();

    // Escuchar webhooks de alertas
    _webhookService.alertasStream.listen((alerta) {
      _agregarAlerta(alerta);
    });

    _isLoading = false;
    notifyListeners();
  }

  /// Agregar una nueva alerta
  void _agregarAlerta(Alerta alerta) {
    // Verificar si ya existe
    if (_alertas.any((a) => a.id == alerta.id)) {
      return;
    }

    _alertas.insert(0, alerta);
    notifyListeners();
  }

  /// Agregar alerta desde servicio externo (ej: AlertasCTOService)
  void agregarAlertaDesdeServicio(Alerta alerta) {
    _agregarAlerta(alerta);
  }

  /// Obtener estado de una alerta por ID (para verificar si está solucionada)
  String? obtenerEstadoAlerta(String alertaId) {
    final alerta = _alertas.firstWhere(
      (a) => a.id == alertaId,
      orElse: () => throw Exception('Alerta no encontrada'),
    );
    return alerta.estado.name;
  }

  /// Obtener alertas por estado
  List<Alerta> alertasPorEstado(EstadoAlerta estado) {
    return _alertas.where((a) => a.estado == estado).toList();
  }

  /// Actualizar estado de una alerta
  void actualizarEstadoAlerta(String alertaId, EstadoAlerta nuevoEstado) {
    final index = _alertas.indexWhere((a) => a.id == alertaId);
    if (index != -1) {
      final alerta = _alertas[index];
      // Crear nueva instancia con el estado actualizado
      final alertaActualizada = Alerta(
        id: alerta.id,
        nombreTecnico: alerta.nombreTecnico,
        telefonoTecnico: alerta.telefonoTecnico,
        numeroOt: alerta.numeroOt,
        accessId: alerta.accessId,
        nombreCto: alerta.nombreCto,
        numeroPelo: alerta.numeroPelo,
        valorConsulta1: alerta.valorConsulta1,
        valorConsulta2: alerta.valorConsulta2,
        tipoAlerta: alerta.tipoAlerta,
        fechaRecepcion: alerta.fechaRecepcion,
        estado: nuevoEstado,
        fechaAtendida: nuevoEstado == EstadoAlerta.enAtencion 
            ? (alerta.fechaAtendida ?? DateTime.now())
            : alerta.fechaAtendida,
        fechaPostergada: nuevoEstado == EstadoAlerta.postergada
            ? (alerta.fechaPostergada ?? DateTime.now())
            : alerta.fechaPostergada,
        fechaEscalada: alerta.fechaEscalada,
        motivoEscalamiento: alerta.motivoEscalamiento,
        fotosGeoreferenciadas: alerta.fotosGeoreferenciadas,
        notas: alerta.notas,
        comentarioResolucion: alerta.comentarioResolucion,
        empresa: alerta.empresa,
        actividad: alerta.actividad,
        tiempoEjecucion: alerta.tiempoEjecucion,
        nivelesPuertos: alerta.nivelesPuertos,
      );
      _alertas[index] = alertaActualizada;
      notifyListeners();
    }
  }

  /// Marcar alerta como solucionada
  Future<bool> marcarComoSolucionada(Alerta alerta) async {
    actualizarEstadoAlerta(alerta.id, EstadoAlerta.regularizada);
    return true;
  }

  /// Atender una alerta
  Future<bool> atenderAlerta(Alerta alerta) async {
    actualizarEstadoAlerta(alerta.id, EstadoAlerta.enAtencion);
    await _notificationService.detenerAlarmaAlerta(alerta.id);
    return true;
  }

  /// Postergar una alerta
  Future<bool> postergarAlerta(Alerta alerta) async {
    actualizarEstadoAlerta(alerta.id, EstadoAlerta.postergada);
    await _notificationService.detenerAlarmaAlerta(alerta.id);
    return true;
  }

  /// Cargar alertas para un usuario
  Future<void> cargarAlertas(Usuario usuario) async {
    // Este método puede cargar alertas desde el backend si es necesario
    // Por ahora solo inicializa el stream
    _isLoading = true;
    notifyListeners();
    
    // El stream de webhooks ya está configurado en initialize
    _isLoading = false;
    notifyListeners();
  }

  /// Simular nueva alerta (para pruebas)
  Future<void> simularNuevaAlerta() async {
    // Simular una alerta de desconexión para pruebas
    await _webhookService.simularAlertaDesdeKepler(
      nombreTecnico: 'Juan Pérez',
      telefonoTecnico: '+56 9 1234 5678',
      numeroOt: 'OT-2024-${DateTime.now().millisecondsSinceEpoch}',
      nombreCto: 'CTO-SANTIAGO-001',
      numeroPelo: '2',
      valorConsulta1: -21.20,
      tipoAlerta: TipoAlerta.desconexion,
    );
  }

  /// Verificar si una alerta puede postergarse
  bool puedePostergarse(Alerta alerta) {
    // Una alerta puede postergarse si está en estado pendiente o en atención
    return alerta.estado == EstadoAlerta.pendiente || 
           alerta.estado == EstadoAlerta.enAtencion;
  }
}


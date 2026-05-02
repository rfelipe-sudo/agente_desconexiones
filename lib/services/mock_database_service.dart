import 'dart:math';
import 'package:agente_desconexiones/models/alerta.dart';

/// Servicio de base de datos ficticia para simular alertas
class MockDatabaseService {
  static final MockDatabaseService _instance = MockDatabaseService._internal();
  factory MockDatabaseService() => _instance;
  MockDatabaseService._internal();

  final Random _random = Random();
  
  // Base de datos en memoria
  final List<Alerta> _alertas = [];
  
  // Técnicos ficticios
  final List<Map<String, String>> _tecnicos = [
    {'nombre': 'Juan Pérez', 'telefono': '+56 9 1234 5678'},
    {'nombre': 'María González', 'telefono': '+56 9 8765 4321'},
    {'nombre': 'Carlos Rodríguez', 'telefono': '+56 9 5555 1234'},
    {'nombre': 'Ana Martínez', 'telefono': '+56 9 6666 7890'},
  ];
  
  // CTOs ficticias
  final List<String> _ctos = [
    'CTO-SANTIAGO-001',
    'CTO-PROVIDENCIA-002',
    'CTO-ÑUÑOA-003',
    'CTO-LAS-CONDES-004',
    'CTO-MAIPU-005',
    'CTO-SAN-BERNARDO-006',
  ];

  /// Genera una alerta aleatoria nueva
  Alerta generarAlertaAleatoria() {
    final tecnico = _tecnicos[_random.nextInt(_tecnicos.length)];
    final cto = _ctos[_random.nextInt(_ctos.length)];
    final pelo = _random.nextInt(16) + 1; // Pelo 1-16
    final tipos = TipoAlerta.values;
    final tipo = tipos[_random.nextInt(tipos.length)];
    
    // Generar OT única
    final otNum = _random.nextInt(9999) + 1000;
    final numeroOt = 'OT-2024-$otNum';
    
    // Generar Access ID
    final accessNum = _random.nextInt(99999);
    final accessId = 'ACC-$accessNum';
    
    // Valor de consulta (negativo para desconexión, positivo para pérdida total)
    final valorConsulta = tipo == TipoAlerta.desconexion
        ? -(_random.nextDouble() * 25 + 15) // -15 a -40
        : (_random.nextDouble() * 5 + 1); // 1 a 6
    
    final alerta = Alerta(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      nombreTecnico: tecnico['nombre']!,
      telefonoTecnico: tecnico['telefono']!,
      numeroOt: numeroOt,
      accessId: accessId,
      nombreCto: cto,
      numeroPelo: 'P-${pelo.toString().padLeft(2, '0')}',
      valorConsulta1: valorConsulta,
      tipoAlerta: tipo,
      fechaRecepcion: DateTime.now(),
      estado: EstadoAlerta.pendiente,
      empresa: 'CREA',
      actividad: 'Desconexión',
    );
    
    // Guardar en base de datos
    _alertas.add(alerta);
    
    return alerta;
  }

  /// Obtiene todas las alertas
  List<Alerta> obtenerTodasLasAlertas() {
    return List.from(_alertas);
  }

  /// Obtiene alertas pendientes de un técnico
  List<Alerta> obtenerAlertasPendientes(String telefonoTecnico) {
    return _alertas.where((a) => 
      a.telefonoTecnico == telefonoTecnico && 
      a.estado == EstadoAlerta.pendiente
    ).toList();
  }

  /// Obtiene alertas escaladas
  List<Alerta> obtenerAlertasEscaladas() {
    return _alertas.where((a) => a.estado == EstadoAlerta.escalada).toList();
  }

  /// Actualiza el estado de una alerta
  Future<bool> actualizarEstadoAlerta(String alertaId, EstadoAlerta nuevoEstado) async {
    final index = _alertas.indexWhere((a) => a.id == alertaId);
    if (index != -1) {
      _alertas[index] = _alertas[index].copyWith(estado: nuevoEstado);
      return true;
    }
    return false;
  }

  /// Limpia todas las alertas (para pruebas)
  void limpiarAlertas() {
    _alertas.clear();
  }

  /// Obtiene estadísticas
  Map<String, int> obtenerEstadisticas() {
    return {
      'total': _alertas.length,
      'pendientes': _alertas.where((a) => a.estado == EstadoAlerta.pendiente).length,
      'enAtencion': _alertas.where((a) => a.estado == EstadoAlerta.enAtencion).length,
      'escaladas': _alertas.where((a) => a.estado == EstadoAlerta.escalada).length,
      'cerradas': _alertas.where((a) => a.estado == EstadoAlerta.cerrada).length,
    };
  }
}



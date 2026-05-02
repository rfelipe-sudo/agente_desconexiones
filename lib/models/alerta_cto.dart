class AlertaCTO {
  final String ot;
  final String accessId;
  final String tecnico;
  final String tecnicoFull;
  final String actividad;
  final String fecha;
  final String inicio;
  final String ejecucion;
  final bool hasAlerts;
  final List<PuertoAlerta> puertosConAlerta;
  final List<NivelPuerto> nivelesInicial;
  final List<NivelPuerto> nivelesFinal;
  final String horarioConsultaInicial;
  final String horarioConsultaFinal;

  AlertaCTO({
    required this.ot,
    required this.accessId,
    required this.tecnico,
    required this.tecnicoFull,
    required this.actividad,
    required this.fecha,
    required this.inicio,
    required this.ejecucion,
    required this.hasAlerts,
    required this.puertosConAlerta,
    required this.nivelesInicial,
    required this.nivelesFinal,
    required this.horarioConsultaInicial,
    required this.horarioConsultaFinal,
  });

  factory AlertaCTO.fromJson(Map<String, dynamic> json) {
    final alertas = json['alertas'] ?? {};

    final ports = (alertas['ports'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final puertosConAlerta = ports
        .where((p) => p['has_alert'] == true)
        .map((p) => PuertoAlerta.fromJson(p))
        .toList();

    final nivelesInicial = (json['niveles_inicial'] as List?)
        ?.map((n) => NivelPuerto.fromJson(n as Map<String, dynamic>))
        .toList() ?? [];

    final nivelesFinal = (json['niveles_final'] as List?)
        ?.map((n) => NivelPuerto.fromJson(n as Map<String, dynamic>))
        .toList() ?? [];

    return AlertaCTO(
      ot: json['ot']?.toString() ?? '',
      accessId: json['access_id']?.toString() ?? '',
      tecnico: json['tecnico']?.toString() ?? '',
      tecnicoFull: json['tecnico_full']?.toString() ?? '',
      actividad: json['actividad']?.toString() ?? '',
      fecha: json['fecha']?.toString() ?? '',
      inicio: json['inicio']?.toString() ?? '',
      ejecucion: json['ejecucion']?.toString() ?? '',
      hasAlerts: alertas['has_alerts'] ?? false,
      puertosConAlerta: puertosConAlerta,
      nivelesInicial: nivelesInicial,
      nivelesFinal: nivelesFinal,
      horarioConsultaInicial: json['horario_consulta_inicial']?.toString() ?? '',
      horarioConsultaFinal: json['horario_consulta_final']?.toString() ?? '',
    );
  }
}

class PuertoAlerta {
  final int portNumber;
  final double inicial;
  final double finalValue;
  final double difference;
  final List<String> alertReasons;
  final bool isCurrent;

  PuertoAlerta({
    required this.portNumber,
    required this.inicial,
    required this.finalValue,
    required this.difference,
    required this.alertReasons,
    required this.isCurrent,
  });

  factory PuertoAlerta.fromJson(Map<String, dynamic> json) {
    return PuertoAlerta(
      portNumber: json['port_number'] ?? 0,
      inicial: (json['inicial'] as num?)?.toDouble() ?? 0.0,
      finalValue: (json['final'] as num?)?.toDouble() ?? 0.0,
      difference: (json['difference'] as num?)?.toDouble() ?? 0.0,
      alertReasons: List<String>.from(json['alert_reasons'] ?? []),
      isCurrent: json['is_current'] ?? false,
    );
  }
}

class NivelPuerto {
  final int portNumber;
  final String portId;
  final String rxActual;
  final String status;
  final bool isCurrent;

  NivelPuerto({
    required this.portNumber,
    required this.portId,
    required this.rxActual,
    required this.status,
    required this.isCurrent,
  });

  factory NivelPuerto.fromJson(Map<String, dynamic> json) {
    return NivelPuerto(
      portNumber: json['port_number'] ?? 0,
      portId: json['port_id']?.toString() ?? '',
      rxActual: json['rx_actual']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      isCurrent: json['is_current'] ?? false,
    );
  }
}





















/// Material del sistema KRP (bodega)
class MaterialKrp {
  final int id;
  final String uuid;
  final String sku;
  final String? skuExterno;
  final String nombre;
  final bool esSeriado;
  final int? consumoMaximoOt;
  final String createdAt;
  final String? nombreFamilia;  // ⭐ NUEVO CAMPO
  final String? rutTrabajador;
  final String? nombreTrabajador;
  final double? latitud;
  final double? longitud;
  final int? cantidadDisponible;
  
  MaterialKrp({
    required this.id,
    required this.uuid,
    required this.sku,
    this.skuExterno,
    required this.nombre,
    required this.esSeriado,
    this.consumoMaximoOt,
    required this.createdAt,
    this.nombreFamilia,  // ⭐ NUEVO
    this.rutTrabajador,
    this.nombreTrabajador,
    this.latitud,
    this.longitud,
    this.cantidadDisponible,
  });
  
  factory MaterialKrp.fromJson(Map<String, dynamic> json) {
    return MaterialKrp(
      id: json['id'],
      uuid: json['uuid'],
      sku: json['sku'],
      skuExterno: json['sku_externo'],
      nombre: json['nombre'],
      esSeriado: json['es_seriado'] ?? false,
      consumoMaximoOt: json['consumo_maximo_ot'],
      createdAt: json['created_at'],
      nombreFamilia: json['nombre_familia'],  // ⭐ NUEVO
      rutTrabajador: json['rut_trabajador'],
      nombreTrabajador: json['nombre_trabajador'],
      latitud: json['latitud']?.toDouble(),
      longitud: json['longitud']?.toDouble(),
      cantidadDisponible: json['cantidad_disponible'] ?? 0,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uuid': uuid,
      'sku': sku,
      'sku_externo': skuExterno,
      'nombre': nombre,
      'es_seriado': esSeriado,
      'consumo_maximo_ot': consumoMaximoOt,
      'created_at': createdAt,
      'nombre_familia': nombreFamilia,  // ⭐ NUEVO
      'rut_trabajador': rutTrabajador,
      'nombre_trabajador': nombreTrabajador,
      'latitud': latitud,
      'longitud': longitud,
      'cantidad_disponible': cantidadDisponible,
    };
  }
}

class TecnicoConMaterial {
  final String rut;
  final String nombre;
  final List<MaterialKrp> materiales;
  final double? latitud;
  final double? longitud;
  final double? distancia;
  
  TecnicoConMaterial({
    required this.rut,
    required this.nombre,
    required this.materiales,
    this.latitud,
    this.longitud,
    this.distancia,
  });
  
  TecnicoConMaterial copyWith({
    String? rut,
    String? nombre,
    List<MaterialKrp>? materiales,
    double? latitud,
    double? longitud,
    double? distancia,
  }) {
    return TecnicoConMaterial(
      rut: rut ?? this.rut,
      nombre: nombre ?? this.nombre,
      materiales: materiales ?? this.materiales,
      latitud: latitud ?? this.latitud,
      longitud: longitud ?? this.longitud,
      distancia: distancia ?? this.distancia,
    );
  }
}

class MaterialTransferencia {
  final String sku;
  final String nombre;
  final int cantidad;
  final String? modelo;
  final String? uuid;
  
  MaterialTransferencia({
    required this.sku,
    required this.nombre,
    required this.cantidad,
    this.modelo,
    this.uuid,
  });
  
  factory MaterialTransferencia.fromJson(Map<String, dynamic> json) {
    return MaterialTransferencia(
      sku: json['sku'],
      nombre: json['nombre'],
      cantidad: json['cantidad'],
      modelo: json['modelo'],
      uuid: json['uuid'],
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'sku': sku,
      'nombre': nombre,
      'cantidad': cantidad,
      'modelo': modelo,
      'uuid': uuid,
    };
  }
}

class TransferenciaMaterial {
  final int? id;
  final String codigoTransferencia;
  final String rutTecnicoOrigen;
  final String nombreTecnicoOrigen;
  final String rutTecnicoDestino;
  final String nombreTecnicoDestino;
  final MaterialTransferencia material;
  final String? serialTransferido;
  final double? latitudEncuentro;
  final double? longitudEncuentro;
  final String? firmaEntrega;
  final String? firmaRecepcion;
  final String? fotoTransferencia;
  final String estado;
  final String? estadoKrp;
  final String? estadoSap;
  final String urgencia;
  final double? distanciaKm;
  final int intentoNumero;
  final String? mensajeSolicitante;
  final String? notasBodeguero;
  final DateTime fechaSolicitud;
  final DateTime? fechaAceptacion;
  final DateTime? fechaFirma;
  final DateTime? fechaCompletado;
  final int? tiempoRespuestaMinutos;
  
  TransferenciaMaterial({
    this.id,
    required this.codigoTransferencia,
    required this.rutTecnicoOrigen,
    required this.nombreTecnicoOrigen,
    required this.rutTecnicoDestino,
    required this.nombreTecnicoDestino,
    required this.material,
    this.serialTransferido,
    this.latitudEncuentro,
    this.longitudEncuentro,
    this.firmaEntrega,
    this.firmaRecepcion,
    this.fotoTransferencia,
    required this.estado,
    this.estadoKrp,
    this.estadoSap,
    required this.urgencia,
    this.distanciaKm,
    this.intentoNumero = 1,
    this.mensajeSolicitante,
    this.notasBodeguero,
    required this.fechaSolicitud,
    this.fechaAceptacion,
    this.fechaFirma,
    this.fechaCompletado,
    this.tiempoRespuestaMinutos,
  });
  
  factory TransferenciaMaterial.fromJson(Map<String, dynamic> json) {
    return TransferenciaMaterial(
      id: json['id'],
      codigoTransferencia: json['codigo_transferencia'],
      rutTecnicoOrigen: json['rut_tecnico_origen'],
      nombreTecnicoOrigen: json['nombre_tecnico_origen'],
      rutTecnicoDestino: json['rut_tecnico_destino'],
      nombreTecnicoDestino: json['nombre_tecnico_destino'],
      material: MaterialTransferencia.fromJson(json['material']),
      serialTransferido: json['serial_transferido'],
      latitudEncuentro: json['latitud_encuentro']?.toDouble(),
      longitudEncuentro: json['longitud_encuentro']?.toDouble(),
      firmaEntrega: json['firma_entrega'],
      firmaRecepcion: json['firma_recepcion'],
      fotoTransferencia: json['foto_transferencia'],
      estado: json['estado'],
      estadoKrp: json['estado_krp'],
      estadoSap: json['estado_sap'],
      urgencia: json['urgencia'],
      distanciaKm: json['distancia_km']?.toDouble(),
      intentoNumero: json['intento_numero'] ?? 1,
      mensajeSolicitante: json['mensaje_solicitante'],
      notasBodeguero: json['notas_bodeguero'],
      fechaSolicitud: DateTime.parse(json['fecha_solicitud']),
      fechaAceptacion: json['fecha_aceptacion'] != null 
          ? DateTime.parse(json['fecha_aceptacion']) 
          : null,
      fechaFirma: json['fecha_firma'] != null 
          ? DateTime.parse(json['fecha_firma']) 
          : null,
      fechaCompletado: json['fecha_completado'] != null 
          ? DateTime.parse(json['fecha_completado']) 
          : null,
      tiempoRespuestaMinutos: json['tiempo_respuesta_minutos'],
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'codigo_transferencia': codigoTransferencia,
      'rut_tecnico_origen': rutTecnicoOrigen,
      'nombre_tecnico_origen': nombreTecnicoOrigen,
      'rut_tecnico_destino': rutTecnicoDestino,
      'nombre_tecnico_destino': nombreTecnicoDestino,
      'material': material.toJson(),
      'serial_transferido': serialTransferido,
      'latitud_encuentro': latitudEncuentro,
      'longitud_encuentro': longitudEncuentro,
      'firma_entrega': firmaEntrega,
      'firma_recepcion': firmaRecepcion,
      'foto_transferencia': fotoTransferencia,
      'estado': estado,
      'estado_krp': estadoKrp,
      'estado_sap': estadoSap,
      'urgencia': urgencia,
      'distancia_km': distanciaKm,
      'intento_numero': intentoNumero,
      'mensaje_solicitante': mensajeSolicitante,
      'notas_bodeguero': notasBodeguero,
      'fecha_solicitud': fechaSolicitud.toIso8601String(),
      'fecha_aceptacion': fechaAceptacion?.toIso8601String(),
      'fecha_firma': fechaFirma?.toIso8601String(),
      'fecha_completado': fechaCompletado?.toIso8601String(),
      'tiempo_respuesta_minutos': tiempoRespuestaMinutos,
    };
  }
}

class EstadoTransferencia {
  static const String solicitado = 'SOLICITADO';
  static const String aceptado = 'ACEPTADO';
  static const String rechazado = 'RECHAZADO';
  static const String firmado = 'FIRMADO';
  static const String completado = 'COMPLETADO';
  static const String cancelado = 'CANCELADO';
}

class UrgenciaTransferencia {
  static const String normal = 'NORMAL';
  static const String urgente = 'URGENTE';
}

/// ⭐ NUEVAS CONSTANTES DE FAMILIAS
class FamiliasKRP {
  // Todas las familias disponibles en KRP
  static const List<String> todas = [
    'Ferretería',
    'Movistar',
    'Equipamiento',
    'Herramientas',
    'Seriado',
    'Uniformes',
    'EPP',
    'No seriado',
    'Servicios',
    'FLOTA',
  ];
  
  // Familias de materiales para instalación (recomendadas para transferencias)
  static const List<String> instalacion = [
    'Ferretería',    // Cables, amarras, conectores, silicona
    'Seriado',       // ONTs, decos, routers
    'No seriado',    // Adaptadores, switches, cables
  ];
  
  // Familias que NO deberían transferirse entre técnicos
  static const List<String> excluir = [
    'Herramientas',  // Son patrimoniales
    'EPP',           // Son personales
    'Uniformes',     // Son personales
    'Servicios',     // No son materiales físicos
    'FLOTA',         // No son materiales físicos
  ];
  
  // Solo herramientas
  static const List<String> herramientas = [
    'Herramientas',
  ];
  
  // Solo EPP
  static const List<String> epp = [
    'EPP',
  ];
}

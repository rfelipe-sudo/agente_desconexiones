class MaterialItem {
  final String nombre;
  final bool esSeriado;
  const MaterialItem({required this.nombre, required this.esSeriado});
}

const kMateriales = [
  // ── No seriados ──────────────────────────────────────────────
  MaterialItem(nombre: 'Conector de campo',  esSeriado: false),
  MaterialItem(nombre: 'Jumper',             esSeriado: false),
  MaterialItem(nombre: 'Roseta',             esSeriado: false),
  MaterialItem(nombre: 'Amarras plásticas',  esSeriado: false),
  MaterialItem(nombre: 'Drop 100m',          esSeriado: false),
  MaterialItem(nombre: 'Drop 150m',          esSeriado: false),
  MaterialItem(nombre: 'Drop 200m',          esSeriado: false),
  MaterialItem(nombre: 'Drop 300m',          esSeriado: false),
  MaterialItem(nombre: 'Soportes drop',      esSeriado: false),
  MaterialItem(nombre: 'Ficha de abonado',   esSeriado: false),
  MaterialItem(nombre: 'Cáncamos',           esSeriado: false),
  MaterialItem(nombre: 'Grampa negra',       esSeriado: false),
  MaterialItem(nombre: 'Grampa blanca',      esSeriado: false),
  MaterialItem(nombre: 'Pasacable blanco',   esSeriado: false),
  MaterialItem(nombre: 'Pasacable negro',    esSeriado: false),
  MaterialItem(nombre: 'Cable UTP',          esSeriado: false),
  MaterialItem(nombre: 'Conector RJ45',      esSeriado: false),
  MaterialItem(nombre: 'Micro USB',          esSeriado: false),
  // ── Seriados ─────────────────────────────────────────────────
  MaterialItem(nombre: 'Decodificador',      esSeriado: true),
  MaterialItem(nombre: 'ONT ZTE',            esSeriado: true),
  MaterialItem(nombre: 'ONT Huawei',         esSeriado: true),
  MaterialItem(nombre: 'Extensor',           esSeriado: true),
];

class SolicitudMaterial {
  final String id;
  final DateTime createdAt;
  final String rutSolicitante;
  final String nombreSolicitante;
  final double? latSolicitante;
  final double? lngSolicitante;
  final String tipoMaterial;
  final bool esSeriado;
  final int cantidad;
  final List<String> series;
  final String estado;
  final String? rutEntregador;
  final String? nombreEntregador;
  final double? latEntregador;
  final double? lngEntregador;
  final String? guiaId;
  final String? modalidad; // 'yo_te_lo_llevo' | 'ven_por_el'
  final int?    idMaterial;   // ID interno Kepler — se guarda al aceptar
  final String? folioKepler;  // Folio devuelto por Kepler al confirmar PIN

  const SolicitudMaterial({
    required this.id,
    required this.createdAt,
    required this.rutSolicitante,
    required this.nombreSolicitante,
    this.latSolicitante,
    this.lngSolicitante,
    required this.tipoMaterial,
    required this.esSeriado,
    required this.cantidad,
    required this.series,
    required this.estado,
    this.rutEntregador,
    this.nombreEntregador,
    this.latEntregador,
    this.lngEntregador,
    this.guiaId,
    this.modalidad,
    this.idMaterial,
    this.folioKepler,
  });

  factory SolicitudMaterial.fromMap(Map<String, dynamic> m) =>
      SolicitudMaterial(
        id:               m['id'] as String,
        createdAt:        DateTime.parse(m['created_at'] as String),
        rutSolicitante:   m['rut_solicitante'] as String,
        nombreSolicitante: m['nombre_solicitante'] as String,
        latSolicitante:   (m['lat_solicitante'] as num?)?.toDouble(),
        lngSolicitante:   (m['lng_solicitante'] as num?)?.toDouble(),
        tipoMaterial:     m['tipo_material'] as String,
        esSeriado:        m['es_seriado'] as bool? ?? false,
        cantidad:         m['cantidad'] as int? ?? 1,
        series: (m['series'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        estado:           m['estado'] as String? ?? 'pendiente',
        rutEntregador:    m['rut_entregador'] as String?,
        nombreEntregador: m['nombre_entregador'] as String?,
        latEntregador:    (m['lat_entregador'] as num?)?.toDouble(),
        lngEntregador:    (m['lng_entregador'] as num?)?.toDouble(),
        guiaId:           m['guia_id'] as String?,
        modalidad:        m['modalidad'] as String?,
        idMaterial:       m['id_material'] as int?,
        folioKepler:      m['folio_kepler'] as String?,
      );

  SolicitudMaterial copyWith({
    String? estado,
    String? rutEntregador,
    String? nombreEntregador,
    double? latEntregador,
    double? lngEntregador,
    String? guiaId,
    String? modalidad,
    int?    idMaterial,
    String? folioKepler,
  }) =>
      SolicitudMaterial(
        id: id,
        createdAt: createdAt,
        rutSolicitante: rutSolicitante,
        nombreSolicitante: nombreSolicitante,
        latSolicitante: latSolicitante,
        lngSolicitante: lngSolicitante,
        tipoMaterial: tipoMaterial,
        esSeriado: esSeriado,
        cantidad: cantidad,
        series: series,
        estado: estado ?? this.estado,
        rutEntregador: rutEntregador ?? this.rutEntregador,
        nombreEntregador: nombreEntregador ?? this.nombreEntregador,
        latEntregador: latEntregador ?? this.latEntregador,
        lngEntregador: lngEntregador ?? this.lngEntregador,
        guiaId: guiaId ?? this.guiaId,
        modalidad: modalidad ?? this.modalidad,
        idMaterial: idMaterial ?? this.idMaterial,
        folioKepler: folioKepler ?? this.folioKepler,
      );
}

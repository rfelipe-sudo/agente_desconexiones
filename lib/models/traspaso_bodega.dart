class TraspassoBodega {
  final String id;
  final DateTime createdAt;
  final String? solicitudMaterialId;
  final String rutTecnicoB;
  final String nombreTecnicoB;
  final String rutTecnicoA;
  final String nombreTecnicoA;
  final String tipoMaterial;
  final int cantidad;
  final List<String> series;
  final int? idMaterial;
  final String estado; // 'pendiente' | 'aprobado'
  final String? aprobadoPor;
  final String? nombreAprobador;
  final DateTime? aprobadoEn;
  final String? folioKepler;

  const TraspassoBodega({
    required this.id,
    required this.createdAt,
    this.solicitudMaterialId,
    required this.rutTecnicoB,
    required this.nombreTecnicoB,
    required this.rutTecnicoA,
    required this.nombreTecnicoA,
    required this.tipoMaterial,
    required this.cantidad,
    required this.series,
    this.idMaterial,
    required this.estado,
    this.aprobadoPor,
    this.nombreAprobador,
    this.aprobadoEn,
    this.folioKepler,
  });

  bool get pendiente => estado == 'pendiente';

  TraspassoBodega copyWith({
    String? estado,
    String? nombreAprobador,
    String? aprobadoPor,
    DateTime? aprobadoEn,
    String? folioKepler,
  }) => TraspassoBodega(
    id:                  id,
    createdAt:           createdAt,
    solicitudMaterialId: solicitudMaterialId,
    rutTecnicoB:         rutTecnicoB,
    nombreTecnicoB:      nombreTecnicoB,
    rutTecnicoA:         rutTecnicoA,
    nombreTecnicoA:      nombreTecnicoA,
    tipoMaterial:        tipoMaterial,
    cantidad:            cantidad,
    series:              series,
    idMaterial:          idMaterial,
    estado:              estado         ?? this.estado,
    aprobadoPor:         aprobadoPor    ?? this.aprobadoPor,
    nombreAprobador:     nombreAprobador ?? this.nombreAprobador,
    aprobadoEn:          aprobadoEn     ?? this.aprobadoEn,
    folioKepler:         folioKepler    ?? this.folioKepler,
  );

  factory TraspassoBodega.fromMap(Map<String, dynamic> m) => TraspassoBodega(
        id:                   m['id'] as String,
        createdAt:            DateTime.parse(m['created_at'] as String),
        solicitudMaterialId:  m['solicitud_material_id'] as String?,
        rutTecnicoB:          m['rut_tecnico_b'] as String,
        nombreTecnicoB:       m['nombre_tecnico_b'] as String,
        rutTecnicoA:          m['rut_tecnico_a'] as String,
        nombreTecnicoA:       m['nombre_tecnico_a'] as String,
        tipoMaterial:         m['tipo_material'] as String,
        cantidad:             m['cantidad'] as int? ?? 1,
        series: (m['series'] as List?)?.map((e) => e.toString()).toList() ?? [],
        idMaterial:           m['id_material'] as int?,
        estado:               m['estado'] as String? ?? 'pendiente',
        aprobadoPor:          m['aprobado_por'] as String?,
        nombreAprobador:      m['nombre_aprobador'] as String?,
        aprobadoEn:           m['aprobado_en'] != null
            ? DateTime.parse(m['aprobado_en'] as String)
            : null,
        folioKepler:          m['folio_kepler'] as String?,
      );
}

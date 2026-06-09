import 'package:agente_desconexiones/utils/fecha_chile.dart';

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
  final bool pdfKeplerOk;
  final bool sapOk;
  final DateTime? sapConfirmadoEn;

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
    this.pdfKeplerOk = false,
    this.sapOk = false,
    this.sapConfirmadoEn,
  });

  bool get pendiente  => estado == 'pendiente';
  bool get krpOk      => !pendiente;
  bool get confirmado => !pendiente && pdfKeplerOk;

  TraspassoBodega copyWith({
    String? estado,
    String? nombreAprobador,
    String? aprobadoPor,
    DateTime? aprobadoEn,
    String? folioKepler,
    bool? pdfKeplerOk,
    bool? sapOk,
    DateTime? sapConfirmadoEn,
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
    estado:              estado           ?? this.estado,
    aprobadoPor:         aprobadoPor      ?? this.aprobadoPor,
    nombreAprobador:     nombreAprobador  ?? this.nombreAprobador,
    aprobadoEn:          aprobadoEn       ?? this.aprobadoEn,
    folioKepler:         folioKepler      ?? this.folioKepler,
    pdfKeplerOk:         pdfKeplerOk      ?? this.pdfKeplerOk,
    sapOk:               sapOk            ?? this.sapOk,
    sapConfirmadoEn:     sapConfirmadoEn  ?? this.sapConfirmadoEn,
  );

  factory TraspassoBodega.fromMap(Map<String, dynamic> m) => TraspassoBodega(
        id:                   m['id'] as String,
        createdAt:            FechaChile.parse(m['created_at'] as String),
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
            ? FechaChile.parse(m['aprobado_en'] as String)
            : null,
        folioKepler:          m['folio_kepler'] as String?,
        pdfKeplerOk:          m['pdf_kepler_ok']      as bool? ?? false,
        sapOk:                m['sap_ok']             as bool? ?? false,
        sapConfirmadoEn:      m['sap_confirmado_en'] != null
            ? FechaChile.parse(m['sap_confirmado_en'] as String)
            : null,
      );
}

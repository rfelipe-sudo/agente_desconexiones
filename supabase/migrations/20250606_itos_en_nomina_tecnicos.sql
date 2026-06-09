-- Los 4 ITO (equipos_crea) también en nomina_tecnicos para nombres, FCM y solicitud de material.
-- Fuente nombres: plantel_tecnicos / equipos_crea.

INSERT INTO public.nomina_tecnicos (
  rut, nombres, paterno, materno, estado_vigencia, tipo_personal, cc
) VALUES
  ('18907543-K', 'ERICK IVAN',      'SOTO',         'AREVALO',        'Vigente', 'ITO', 'VTR-Claro'),
  ('18534498-3', 'LUIS ALBERTO',    'AGUILAR',      'SANCHEZ CONCHA', 'Vigente', 'ITO', 'VTR-Claro'),
  ('26857054-3', 'MARCO LEONEL',    'LOZADA',       'PADILLA',        'Vigente', 'ITO', 'VTR-Claro'),
  ('25821869-8', 'ROBERT JONATHAN', 'CARRASQUERO',  'PRIETO',         'Vigente', 'ITO', 'VTR-Claro')
ON CONFLICT (rut) DO UPDATE SET
  nombres         = EXCLUDED.nombres,
  paterno         = EXCLUDED.paterno,
  materno         = EXCLUDED.materno,
  estado_vigencia = EXCLUDED.estado_vigencia,
  tipo_personal   = EXCLUDED.tipo_personal,
  cc              = EXCLUDED.cc,
  updated_at      = now();

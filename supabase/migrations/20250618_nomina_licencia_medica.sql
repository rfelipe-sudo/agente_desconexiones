-- Refuerza estado licencia_medica y comentario de columna (documentación).
COMMENT ON COLUMN public.nomina_tecnicos.estado_vigencia IS
  'vigente | licencia_medica | no_vigente';

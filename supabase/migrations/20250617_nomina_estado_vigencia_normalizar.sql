-- Normaliza estado_vigencia en nomina_tecnicos a valores canónicos:
--   vigente          → operativos en terreno
--   licencia_medica  → ausentes temporales (vuelven a vigente)
--   no_vigente       → bajas / desvinculados
-- Import Excel Maestro: solo vigente / vigentes / operativo / operativos.

UPDATE public.nomina_tecnicos
SET estado_vigencia = 'licencia_medica'
WHERE LOWER(TRIM(COALESCE(estado_vigencia, ''))) LIKE '%licencia%'
   OR LOWER(REPLACE(TRIM(COALESCE(estado_vigencia, '')), ' ', '_')) IN (
     'licencia_medica', 'licencia'
   );

UPDATE public.nomina_tecnicos
SET estado_vigencia = 'vigente'
WHERE LOWER(TRIM(COALESCE(estado_vigencia, ''))) IN (
  'vigente', 'vigentes', 'operativo', 'operativos'
);

UPDATE public.nomina_tecnicos
SET estado_vigencia = 'no_vigente'
WHERE LOWER(TRIM(COALESCE(estado_vigencia, ''))) NOT IN (
  'vigente', 'no_vigente', 'licencia_medica'
);

-- Técnicos con cargo LICENCIA MEDICA en plantel → licencia_medica (conserva supervisor)
UPDATE public.nomina_tecnicos nt
SET estado_vigencia = 'licencia_medica'
FROM public.plantel_tecnicos pt
WHERE nt.rut = pt.rut
  AND UPPER(TRIM(COALESCE(pt.cargo, ''))) LIKE '%LICENCIA%MEDICA%'
  AND nt.estado_vigencia = 'vigente';

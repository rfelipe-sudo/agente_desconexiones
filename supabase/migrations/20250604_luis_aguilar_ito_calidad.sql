-- Ampliar roles permitidos (quitar check rígido que bloqueaba ito_calidad)
ALTER TABLE public.equipos_crea
  DROP CONSTRAINT IF EXISTS equipos_crea_rol_check;

-- Luis Alberto Aguilar — ITO de Calidad (rol app: ito_calidad)
-- RUT: 18534498-3

UPDATE public.plantel_tecnicos
SET cargo = 'ITO de Calidad'
WHERE rut IN ('18534498-3', '185344983');

UPDATE public.equipos_crea
SET rol = 'ito_calidad',
    nombre = COALESCE(NULLIF(nombre, ''), 'LUIS ALBERTO AGUILAR SANCHEZ CONCHA')
WHERE rut_tecnico IN ('18534498-3', '185344983');

INSERT INTO public.equipos_crea (rut_tecnico, rol, nombre)
SELECT
  '18534498-3',
  'ito_calidad',
  'LUIS ALBERTO AGUILAR SANCHEZ CONCHA'
WHERE NOT EXISTS (
  SELECT 1 FROM public.equipos_crea
  WHERE rut_tecnico IN ('18534498-3', '185344983')
);

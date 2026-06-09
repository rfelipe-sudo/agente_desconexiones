-- Supervisores de Calidad CREABOX
-- Edinson Mellado Bravo  15538814-5 — supervisor directo de los ITOs de calidad
-- Rafael Martínez        26601622-0 — jefe / supervisor de calidad (visible en Equipos)

ALTER TABLE public.equipos_crea
  DROP CONSTRAINT IF EXISTS equipos_crea_rol_check;

-- ── Edinson Mellado ──
INSERT INTO public.equipos_crea (rut_tecnico, rol, nombre, equipo)
SELECT '15538814-5', 'supervisor_calidad', 'EDINSON MELLADO BRAVO', 5
WHERE NOT EXISTS (SELECT 1 FROM public.equipos_crea WHERE rut_tecnico = '15538814-5');

UPDATE public.equipos_crea
SET rol = 'supervisor_calidad',
    nombre = 'EDINSON MELLADO BRAVO',
    equipo = 5
WHERE rut_tecnico = '15538814-5';

INSERT INTO public.supervisores_crea (rut, nombre, cargo, activo)
SELECT '15538814-5', 'EDINSON MELLADO BRAVO', 'supervisor_calidad', true
WHERE NOT EXISTS (SELECT 1 FROM public.supervisores_crea WHERE rut = '15538814-5');

UPDATE public.supervisores_crea
SET nombre = 'EDINSON MELLADO BRAVO',
    cargo = 'supervisor_calidad',
    activo = true
WHERE rut = '15538814-5';

INSERT INTO public.plantel_tecnicos (rut, nombre_completo, supervisor, cargo, ito)
SELECT '15538814-5', 'EDINSON MELLADO BRAVO', NULL, 'Supervisor de Calidad', NULL
WHERE NOT EXISTS (SELECT 1 FROM public.plantel_tecnicos WHERE rut = '15538814-5');

UPDATE public.plantel_tecnicos
SET cargo = 'Supervisor de Calidad'
WHERE rut = '15538814-5';

-- ── Rafael Martínez (jefe de calidad + columna en Equipos) ──
UPDATE public.equipos_crea
SET rol = 'jefe_calidad',
    nombre = COALESCE(NULLIF(nombre, ''), 'RAFAEL ANGEL MARTINEZ CHACARE'),
    equipo = 5
WHERE rut_tecnico = '26601622-0';

INSERT INTO public.equipos_crea (rut_tecnico, rol, nombre, equipo)
SELECT '26601622-0', 'jefe_calidad', 'RAFAEL ANGEL MARTINEZ CHACARE', 5
WHERE NOT EXISTS (SELECT 1 FROM public.equipos_crea WHERE rut_tecnico = '26601622-0');

UPDATE public.supervisores_crea
SET nombre = 'RAFAEL ANGEL MARTINEZ CHACARE',
    cargo = 'jefe_calidad',
    activo = true
WHERE rut = '26601622-0';

INSERT INTO public.supervisores_crea (rut, nombre, cargo, activo)
SELECT '26601622-0', 'RAFAEL ANGEL MARTINEZ CHACARE', 'jefe_calidad', true
WHERE NOT EXISTS (SELECT 1 FROM public.supervisores_crea WHERE rut = '26601622-0');

UPDATE public.plantel_tecnicos
SET cargo = 'Jefe de Calidad'
WHERE rut = '26601622-0';

-- ── ITOs de calidad → supervisor Edinson ──
UPDATE public.equipos_crea
SET rol = 'ito_calidad',
    equipo = 5
WHERE rut_tecnico IN ('18534498-3', '25821869-8', '26857054-3', '18907543-K');

UPDATE public.plantel_tecnicos
SET cargo = 'ITO de Calidad',
    ito = 'SI',
    supervisor = 'EDINSON MELLADO BRAVO'
WHERE rut IN ('18534498-3', '25821869-8', '26857054-3', '18907543-K');

DELETE FROM public.supervisor_tecnicos_crea
WHERE rut_tecnico IN ('18534498-3', '25821869-8', '26857054-3', '18907543-K');

INSERT INTO public.supervisor_tecnicos_crea (rut_tecnico, rut_supervisor) VALUES
  ('18534498-3', '15538814-5'),
  ('25821869-8', '15538814-5'),
  ('26857054-3', '15538814-5'),
  ('18907543-K', '15538814-5');

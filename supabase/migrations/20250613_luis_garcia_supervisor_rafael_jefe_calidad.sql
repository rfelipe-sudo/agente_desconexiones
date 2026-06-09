-- Luis García Benitez (25626541-9) → supervisor equipo 2
-- Rafael Martínez (26601622-0) → jefe_calidad; reasignar vínculos operativos a Luis

ALTER TABLE public.equipos_crea
  DROP CONSTRAINT IF EXISTS equipos_crea_rol_check;

-- ── Luis: nuevo supervisor (hereda equipo 2 de Rafael) ──
INSERT INTO public.equipos_crea (rut_tecnico, rol, nombre, equipo)
SELECT '25626541-9', 'supervisor', 'LUIS GARCIA BENITEZ', 2
WHERE NOT EXISTS (
  SELECT 1 FROM public.equipos_crea WHERE rut_tecnico = '25626541-9'
);

UPDATE public.equipos_crea
SET rol = 'supervisor',
    nombre = 'LUIS GARCIA BENITEZ',
    equipo = 2
WHERE rut_tecnico = '25626541-9';

-- ── Rafael: deja de ser supervisor ──
UPDATE public.equipos_crea
SET rol = 'jefe_calidad',
    nombre = COALESCE(NULLIF(nombre, ''), 'RAFAEL ANGEL MARTINEZ CHACARE')
WHERE rut_tecnico = '26601622-0';

UPDATE public.plantel_tecnicos
SET cargo = 'Jefe de Calidad'
WHERE rut = '26601622-0';

-- ── Reasignar técnicos y solicitudes activas ──
UPDATE public.supervisor_tecnicos_crea
SET rut_supervisor = '25626541-9'
WHERE rut_supervisor = '26601622-0';

UPDATE public.sol_comb_adicional
SET rut_supervisor = '25626541-9'
WHERE rut_supervisor = '26601622-0';

UPDATE public.ayuda_terreno_crea
SET rut_supervisor = '25626541-9'
WHERE rut_supervisor = '26601622-0';

UPDATE public.plantel_tecnicos
SET supervisor = 'LUIS GARCIA BENITEZ'
WHERE supervisor ILIKE '%RAFAEL%MARTINEZ%'
   OR supervisor ILIKE '%MARTINEZ%RAFAEL%'
   OR supervisor ILIKE '%RAFAEL ANGEL MARTINEZ%';

UPDATE public.trabajadores_importados
SET supervisor = 'LUIS GARCIA BENITEZ'
WHERE supervisor ILIKE '%RAFAEL%MARTINEZ%'
   OR supervisor ILIKE '%MARTINEZ%RAFAEL%'
   OR supervisor ILIKE '%RAFAEL ANGEL MARTINEZ%';

-- ── supervisores_crea: Luis activo, Rafael fuera de pool supervisor ──
INSERT INTO public.supervisores_crea (rut, nombre, cargo, activo)
SELECT '25626541-9', 'LUIS GARCIA BENITEZ', 'supervisor', true
WHERE NOT EXISTS (
  SELECT 1 FROM public.supervisores_crea WHERE rut = '25626541-9'
);

UPDATE public.supervisores_crea
SET nombre = 'LUIS GARCIA BENITEZ',
    cargo = 'supervisor',
    activo = true
WHERE rut = '25626541-9';

UPDATE public.supervisores_crea
SET activo = false,
    cargo = 'jefe_calidad'
WHERE rut = '26601622-0';

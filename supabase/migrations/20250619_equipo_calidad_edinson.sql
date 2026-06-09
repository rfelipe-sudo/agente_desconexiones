-- Equipo Calidad CREABOX
-- Edinson Mellado Bravo → Supervisor de Calidad
-- ITOs de calidad (supervisor Edinson): Luis Aguilar, Robert Carrasquero, Marco Lozada, Erick Soto
--
-- Si Edinson no está en nomina/equipos/supervisores, agregar manualmente su RUT en supervisores_crea
-- y volver a ejecutar el bloque de asignación al final de este archivo.

ALTER TABLE public.equipos_crea
  DROP CONSTRAINT IF EXISTS equipos_crea_rol_check;

DO $migration$
DECLARE
  edinson_rut text := NULL;
  ito_rut text;
  ito_nombre text;
  ito_pairs text[][] := ARRAY[
    ARRAY['18534498-3', 'LUIS ALBERTO AGUILAR SANCHEZ CONCHA'],
    ARRAY['25821869-8', 'ROBERT JONATHAN CARRASQUERO PRIETO'],
    ARRAY['26857054-3', 'MARCO LEONEL LOZADA PADILLA'],
    ARRAY['18907543-K', 'ERICK IVAN SOTO AREVALO']
  ];
  pair text[];
BEGIN
  SELECT rut INTO edinson_rut
  FROM public.nomina_tecnicos
  WHERE UPPER(TRIM(paterno)) LIKE '%MELLADO%'
    AND UPPER(TRIM(nombres)) LIKE '%EDINSON%'
  LIMIT 1;

  IF edinson_rut IS NULL THEN
    SELECT rut_tecnico INTO edinson_rut
    FROM public.equipos_crea
    WHERE UPPER(nombre) LIKE '%EDINSON%MELLADO%'
    LIMIT 1;
  END IF;

  IF edinson_rut IS NULL THEN
    SELECT rut INTO edinson_rut
    FROM public.supervisores_crea
    WHERE UPPER(nombre) LIKE '%EDINSON%MELLADO%'
    LIMIT 1;
  END IF;

  IF edinson_rut IS NOT NULL THEN
    INSERT INTO public.equipos_crea (rut_tecnico, rol, nombre, equipo)
    SELECT edinson_rut, 'supervisor_calidad', 'EDINSON MELLADO BRAVO', 5
    WHERE NOT EXISTS (SELECT 1 FROM public.equipos_crea WHERE rut_tecnico = edinson_rut);

    UPDATE public.equipos_crea
    SET rol = 'supervisor_calidad',
        nombre = 'EDINSON MELLADO BRAVO',
        equipo = 5
    WHERE rut_tecnico = edinson_rut;

    INSERT INTO public.supervisores_crea (rut, nombre, cargo, activo)
    SELECT edinson_rut, 'EDINSON MELLADO BRAVO', 'supervisor_calidad', true
    WHERE NOT EXISTS (SELECT 1 FROM public.supervisores_crea WHERE rut = edinson_rut);

    UPDATE public.supervisores_crea
    SET nombre = 'EDINSON MELLADO BRAVO',
        cargo = 'supervisor_calidad',
        activo = true
    WHERE rut = edinson_rut;

    UPDATE public.plantel_tecnicos
    SET cargo = 'Supervisor de Calidad'
    WHERE rut = edinson_rut;
  END IF;

  FOREACH pair SLICE 1 IN ARRAY ito_pairs
  LOOP
    ito_rut := pair[1];
    ito_nombre := pair[2];

    UPDATE public.equipos_crea
    SET rol = 'ito_calidad',
        nombre = ito_nombre
    WHERE rut_tecnico = ito_rut;

    INSERT INTO public.equipos_crea (rut_tecnico, rol, nombre, equipo)
    SELECT ito_rut, 'ito_calidad', ito_nombre, 5
    WHERE NOT EXISTS (SELECT 1 FROM public.equipos_crea WHERE rut_tecnico = ito_rut);

    UPDATE public.nomina_tecnicos
    SET tipo_personal = 'ITO',
        estado_vigencia = 'vigente'
    WHERE rut = ito_rut;

    UPDATE public.plantel_tecnicos
    SET cargo = 'ITO de Calidad',
        ito = 'SI',
        supervisor = 'EDINSON MELLADO BRAVO'
    WHERE rut = ito_rut;

    IF edinson_rut IS NOT NULL THEN
      DELETE FROM public.supervisor_tecnicos_crea WHERE rut_tecnico = ito_rut;
      INSERT INTO public.supervisor_tecnicos_crea (rut_tecnico, rut_supervisor)
      VALUES (ito_rut, edinson_rut);
    END IF;
  END LOOP;
END
$migration$;

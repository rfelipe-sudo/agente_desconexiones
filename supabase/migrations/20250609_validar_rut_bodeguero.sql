-- Incluir bodegueros (nomina_bodega) en validación de RUT para registro CREABOX.

CREATE OR REPLACE FUNCTION public.validar_rut_tecnico(p_rut text)
RETURNS TABLE(existe boolean, nombre text, tipo_personal text, es_vigente boolean, rol text)
LANGUAGE plpgsql
AS $function$
DECLARE
  v_nombre  TEXT;
  v_tipo    TEXT;
  v_vigente BOOLEAN;
  v_rol     TEXT;
  v_rut_key TEXT;
BEGIN
  v_rut_key := UPPER(REPLACE(REPLACE(REPLACE(TRIM(p_rut), '.', ''), '-', ''), ' ', ''));

  -- 1. Supervisores / ITOs (equipos_crea)
  SELECT ec.nombre, ec.rol
  INTO v_nombre, v_rol
  FROM equipos_crea ec
  WHERE UPPER(REPLACE(REPLACE(REPLACE(TRIM(ec.rut_tecnico), '.', ''), '-', ''), ' ', '')) = v_rut_key
  LIMIT 1;

  IF FOUND THEN
    RETURN QUERY SELECT TRUE, v_nombre, v_rol, TRUE, v_rol;
    RETURN;
  END IF;

  -- 2. Bodegueros (nomina_bodega)
  SELECT nb.nombre
  INTO v_nombre
  FROM nomina_bodega nb
  WHERE UPPER(REPLACE(REPLACE(REPLACE(TRIM(nb.rut), '.', ''), '-', ''), ' ', '')) = v_rut_key
  LIMIT 1;

  IF FOUND THEN
    RETURN QUERY SELECT TRUE, v_nombre, 'BODEGA'::TEXT, TRUE, 'bodeguero'::TEXT;
    RETURN;
  END IF;

  -- 3. Técnicos de terreno (nomina_tecnicos)
  SELECT
    TRIM(nt.nombres || ' ' || nt.paterno || ' ' || COALESCE(nt.materno, '')),
    nt.tipo_personal,
    (LOWER(TRIM(nt.estado_vigencia)) = 'vigente')
  INTO v_nombre, v_tipo, v_vigente
  FROM nomina_tecnicos nt
  WHERE UPPER(REPLACE(REPLACE(REPLACE(TRIM(nt.rut), '.', ''), '-', ''), ' ', '')) = v_rut_key
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, NULL::TEXT, NULL::TEXT, FALSE, 'tecnico'::TEXT;
    RETURN;
  END IF;

  RETURN QUERY SELECT TRUE, v_nombre, v_tipo, v_vigente, 'tecnico'::TEXT;
END;
$function$;

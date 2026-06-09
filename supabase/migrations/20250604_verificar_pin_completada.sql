-- Corrige verificar_pin: marca completada al validar, no cancela en reintentos.

CREATE OR REPLACE FUNCTION public.verificar_pin(
  p_solicitud_id uuid,
  p_pin          text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v             record;
  v_restantes   integer;
BEGIN
  SELECT pin_codigo, pin_expira_en, pin_intentos, estado
  INTO v
  FROM public.solicitudes_material
  WHERE id = p_solicitud_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_encontrada');
  END IF;

  IF v.estado = 'completada' THEN
    RETURN jsonb_build_object('ok', true, 'ya_completada', true);
  END IF;

  IF v.estado = 'cancelada' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'cancelada');
  END IF;

  -- PIN ya consumido (validación previa exitosa).
  IF v.pin_codigo IS NULL OR trim(v.pin_codigo) = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pin_ya_usado');
  END IF;

  IF COALESCE(v.pin_intentos, 0) <= 0 THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'sin_intentos',
      'intentos_restantes', 0
    );
  END IF;

  IF v.pin_expira_en IS NOT NULL AND v.pin_expira_en < now() THEN
    RETURN jsonb_build_object('ok', false, 'error', 'expirado');
  END IF;

  IF trim(v.pin_codigo) <> trim(p_pin) THEN
    v_restantes := GREATEST(0, COALESCE(v.pin_intentos, 3) - 1);

    UPDATE public.solicitudes_material
    SET pin_intentos = v_restantes
    WHERE id = p_solicitud_id;

    IF v_restantes <= 0 THEN
      UPDATE public.solicitudes_material
      SET estado = 'cancelada'
      WHERE id = p_solicitud_id;

      RETURN jsonb_build_object(
        'ok', false,
        'error', 'sin_intentos',
        'intentos_restantes', 0
      );
    END IF;

    RETURN jsonb_build_object(
      'ok', false,
      'error', 'incorrecto',
      'intentos_restantes', v_restantes
    );
  END IF;

  -- PIN correcto → cerrar solicitud.
  UPDATE public.solicitudes_material
  SET pin_codigo    = NULL,
      pin_expira_en = NULL,
      pin_intentos  = 0,
      estado        = 'completada'
  WHERE id = p_solicitud_id;

  RETURN jsonb_build_object('ok', true);
END;
$$;

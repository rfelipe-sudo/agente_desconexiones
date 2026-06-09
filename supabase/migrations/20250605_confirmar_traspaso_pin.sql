-- Confirma traspaso con PIN en una sola transacción (verificar + traspaso + completada).

CREATE OR REPLACE FUNCTION public.confirmar_traspaso_pin(
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
  v_traspaso_id uuid;
BEGIN
  SELECT *
  INTO v
  FROM public.solicitudes_material
  WHERE id = p_solicitud_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_encontrada');
  END IF;

  IF v.estado = 'completada' THEN
    SELECT id INTO v_traspaso_id
    FROM public.traspasos_bodega
    WHERE solicitud_material_id = p_solicitud_id
    LIMIT 1;

    RETURN jsonb_build_object(
      'ok', true,
      'ya_completada', true,
      'traspaso_id', v_traspaso_id
    );
  END IF;

  IF v.estado = 'cancelada' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'cancelada');
  END IF;

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

  -- PIN correcto: crear traspaso si no existe.
  SELECT id INTO v_traspaso_id
  FROM public.traspasos_bodega
  WHERE solicitud_material_id = p_solicitud_id
  LIMIT 1;

  IF v_traspaso_id IS NULL THEN
    INSERT INTO public.traspasos_bodega (
      solicitud_material_id,
      rut_tecnico_b,
      nombre_tecnico_b,
      rut_tecnico_a,
      nombre_tecnico_a,
      tipo_material,
      cantidad,
      series,
      id_material,
      estado
    ) VALUES (
      p_solicitud_id,
      COALESCE(v.rut_entregador, ''),
      COALESCE(v.nombre_entregador, ''),
      v.rut_solicitante,
      v.nombre_solicitante,
      v.tipo_material,
      COALESCE(v.cantidad, 1),
      COALESCE(v.series, '{}'::text[]),
      v.id_material,
      'pendiente'
    )
    RETURNING id INTO v_traspaso_id;
  END IF;

  UPDATE public.solicitudes_material
  SET pin_codigo    = NULL,
      pin_expira_en = NULL,
      pin_intentos  = 0,
      estado        = 'completada'
  WHERE id = p_solicitud_id;

  RETURN jsonb_build_object(
    'ok', true,
    'traspaso_id', v_traspaso_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.confirmar_traspaso_pin(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirmar_traspaso_pin(uuid, text) TO service_role;

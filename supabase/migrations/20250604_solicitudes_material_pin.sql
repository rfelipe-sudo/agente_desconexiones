-- Columnas PIN en solicitudes_material + RPC verificar_pin
-- Requerido por edge function generar-pin y pantalla PinEntryScreen.

ALTER TABLE public.solicitudes_material
  ADD COLUMN IF NOT EXISTS pin_codigo    text,
  ADD COLUMN IF NOT EXISTS pin_expira_en timestamptz,
  ADD COLUMN IF NOT EXISTS pin_intentos  integer NOT NULL DEFAULT 3;

COMMENT ON COLUMN public.solicitudes_material.pin_codigo IS
  'PIN de 6 dígitos generado al firmar la guía (edge generar-pin).';
COMMENT ON COLUMN public.solicitudes_material.pin_expira_en IS
  'Vencimiento del PIN (típicamente 3 minutos).';
COMMENT ON COLUMN public.solicitudes_material.pin_intentos IS
  'Intentos restantes para ingresar el PIN (inicia en 3).';

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
  SELECT pin_codigo, pin_expira_en, pin_intentos
  INTO v
  FROM public.solicitudes_material
  WHERE id = p_solicitud_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_encontrada');
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

  IF v.pin_codigo IS NULL OR trim(v.pin_codigo) <> trim(p_pin) THEN
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

  -- PIN correcto: invalidar PIN usado.
  UPDATE public.solicitudes_material
  SET pin_codigo = NULL,
      pin_expira_en = NULL,
      pin_intentos = 0
  WHERE id = p_solicitud_id;

  RETURN jsonb_build_object('ok', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.verificar_pin(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.verificar_pin(uuid, text) TO service_role;

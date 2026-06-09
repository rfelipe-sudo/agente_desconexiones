-- Marca cuándo se notificó al supervisor por solicitud de material sin respuesta (10 min).
ALTER TABLE public.solicitudes_material
  ADD COLUMN IF NOT EXISTS alerta_supervisor_sin_respuesta_at timestamptz;

COMMENT ON COLUMN public.solicitudes_material.alerta_supervisor_sin_respuesta_at IS
  'Timestamp del FCM al supervisor cuando la solicitud lleva 10 min en pendiente sin aceptar.';

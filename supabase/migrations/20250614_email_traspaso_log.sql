-- Registro de envíos de correo de traspasos + lista configurable de destinatarios.

CREATE TABLE IF NOT EXISTS public.email_envios_traspaso (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  traspaso_id   uuid REFERENCES public.traspasos_bodega(id) ON DELETE SET NULL,
  modo          text NOT NULL DEFAULT 'aprobacion',
  destinatario  text NOT NULL,
  ok            boolean NOT NULL DEFAULT false,
  resend_id     text,
  resend_error  text,
  from_address  text,
  subject       text,
  creado_en     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_email_envios_traspaso_traspaso
  ON public.email_envios_traspaso (traspaso_id, creado_en DESC);

CREATE INDEX IF NOT EXISTS idx_email_envios_traspaso_creado
  ON public.email_envios_traspaso (creado_en DESC);

ALTER TABLE public.email_envios_traspaso ENABLE ROW LEVEL SECURITY;

-- Destinatarios de correo al aprobar traspaso (JSON array de emails).
INSERT INTO public.configuracion_app (clave, valor)
VALUES (
  'emails_bodega_traspaso',
  '["rfelipe@sbip.cl","marcelo.gonzalez@sbip.cl","sergio.silva@sbip.cl","bastian.caceres@sbip.cl","gabriel.uribe@sbip.cl"]'
)
ON CONFLICT (clave) DO NOTHING;

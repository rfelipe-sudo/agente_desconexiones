-- Token de un solo uso para confirmar SAP desde el correo de bodega.
ALTER TABLE public.traspasos_bodega
  ADD COLUMN IF NOT EXISTS sap_confirm_token uuid;

ALTER TABLE public.traspasos_bodega
  ADD COLUMN IF NOT EXISTS sap_confirmado_por text;

ALTER TABLE public.traspasos_bodega
  ADD COLUMN IF NOT EXISTS nombre_sap_confirmador text;

CREATE INDEX IF NOT EXISTS idx_traspasos_sap_confirm_token
  ON public.traspasos_bodega (sap_confirm_token)
  WHERE sap_confirm_token IS NOT NULL;

-- Correo del jefe de bodega (notificación cuando SAP queda OK).
INSERT INTO public.configuracion_app (clave, valor)
VALUES ('email_jefe_bodega', 'sergio.silva@sbip.cl')
ON CONFLICT (clave) DO NOTHING;

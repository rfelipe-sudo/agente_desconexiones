-- Roles destinatarios para comunicados (tecnico, ito, supervisor, bodeguero, flota, administrativo, todos)
ALTER TABLE public.comunicados_creabox
  ADD COLUMN IF NOT EXISTS roles_destino text[] NOT NULL DEFAULT '{}';

-- Ampliar tipos: por_roles además de masivo/personalizado
ALTER TABLE public.comunicados_creabox
  DROP CONSTRAINT IF EXISTS comunicados_creabox_tipo_check;

ALTER TABLE public.comunicados_creabox
  ADD CONSTRAINT comunicados_creabox_tipo_check
  CHECK (tipo IN ('masivo', 'personalizado', 'por_roles'));

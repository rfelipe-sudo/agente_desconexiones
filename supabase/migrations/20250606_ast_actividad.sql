-- Actividad de la OT (Instalación, Reparación, etc.) para el PDF AST.
ALTER TABLE public.ast_registros
  ADD COLUMN IF NOT EXISTS actividad text;

COMMENT ON COLUMN public.ast_registros.actividad IS
  'Tipo de actividad de la orden (ej. Instalación), usado en PDF AST.';

-- AST: fotos y firma comprimidas en jsonb (base64 JPEG) + índices

ALTER TABLE public.ast_registros
  ADD COLUMN IF NOT EXISTS foto_area jsonb,
  ADD COLUMN IF NOT EXISTS firma jsonb;

COMMENT ON COLUMN public.ast_registros.foto_area IS
  'Foto área de trabajo comprimida: {mime, ancho, alto, bytes_originales, bytes_comprimidos, data_base64}';
COMMENT ON COLUMN public.ast_registros.firma IS
  'Firma técnico comprimida (mismo formato que foto_area)';

-- URLs legacy opcionales (registros antiguos en storage)
ALTER TABLE public.ast_registros
  ALTER COLUMN url_foto_area DROP NOT NULL,
  ALTER COLUMN url_firma DROP NOT NULL;

CREATE INDEX IF NOT EXISTS idx_ast_registros_rut_fecha
  ON public.ast_registros (rut_tecnico, fecha_hora DESC);

CREATE INDEX IF NOT EXISTS idx_ast_registros_orden
  ON public.ast_registros (orden_trabajo);

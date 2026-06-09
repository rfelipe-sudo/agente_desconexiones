-- Comunicados masivos/personalizados con confirmación de lectura y firma
CREATE TABLE IF NOT EXISTS public.comunicados_creabox (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  titulo text NOT NULL,
  mensaje text NOT NULL,
  tipo text NOT NULL DEFAULT 'masivo'
    CHECK (tipo IN ('masivo', 'personalizado')),
  rut_destino text,
  ruts_destino text[] DEFAULT '{}',
  creado_por text,
  activo boolean NOT NULL DEFAULT true
);

CREATE INDEX IF NOT EXISTS idx_comunicados_creabox_created
  ON public.comunicados_creabox (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_comunicados_creabox_activo
  ON public.comunicados_creabox (activo) WHERE activo = true;

CREATE TABLE IF NOT EXISTS public.comunicados_lecturas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  comunicado_id uuid NOT NULL REFERENCES public.comunicados_creabox(id) ON DELETE CASCADE,
  rut_tecnico text NOT NULL,
  nombre_tecnico text,
  estado text NOT NULL DEFAULT 'pendiente'
    CHECK (estado IN ('pendiente', 'leido')),
  leido_at timestamptz,
  firma_base64 text,
  firma_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (comunicado_id, rut_tecnico)
);

CREATE INDEX IF NOT EXISTS idx_comunicados_lecturas_comunicado
  ON public.comunicados_lecturas (comunicado_id);
CREATE INDEX IF NOT EXISTS idx_comunicados_lecturas_rut
  ON public.comunicados_lecturas (rut_tecnico);

ALTER TABLE public.comunicados_creabox ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.comunicados_lecturas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS comunicados_creabox_insert ON public.comunicados_creabox;
CREATE POLICY comunicados_creabox_insert ON public.comunicados_creabox
  FOR INSERT TO anon, authenticated WITH CHECK (true);

DROP POLICY IF EXISTS comunicados_creabox_select ON public.comunicados_creabox;
CREATE POLICY comunicados_creabox_select ON public.comunicados_creabox
  FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS comunicados_creabox_update ON public.comunicados_creabox;
CREATE POLICY comunicados_creabox_update ON public.comunicados_creabox
  FOR UPDATE TO anon, authenticated USING (true);

DROP POLICY IF EXISTS comunicados_lecturas_insert ON public.comunicados_lecturas;
CREATE POLICY comunicados_lecturas_insert ON public.comunicados_lecturas
  FOR INSERT TO anon, authenticated WITH CHECK (true);

DROP POLICY IF EXISTS comunicados_lecturas_select ON public.comunicados_lecturas;
CREATE POLICY comunicados_lecturas_select ON public.comunicados_lecturas
  FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS comunicados_lecturas_update ON public.comunicados_lecturas;
CREATE POLICY comunicados_lecturas_update ON public.comunicados_lecturas
  FOR UPDATE TO anon, authenticated USING (true);

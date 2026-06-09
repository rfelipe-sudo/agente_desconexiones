-- Informes Mesa de Calidad / Norma Técnica (ITO Calidad)
CREATE TABLE IF NOT EXISTS public.informes_auditoria (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  estado text NOT NULL DEFAULT 'finalizado'
    CHECK (estado IN ('borrador', 'finalizado')),

  rut_ito text NOT NULL,
  nombre_ito text,
  rut_tecnico_auditado text,
  nombre_tecnico_auditado text,

  empresa text DEFAULT 'CREACIONES TECNOLOGICAS',
  operacion text,
  antecedentes_tipo text,
  fecha_citacion date,
  fecha_toa date,
  involucrados text,
  numero_cliente text,
  actividad text,
  peticion text,

  motivo text,
  causa text,
  antecedentes_detalle text,
  irregularidades jsonb NOT NULL DEFAULT '[]'::jsonb,
  calificacion_incumplimiento text,

  fotos_registro jsonb NOT NULL DEFAULT '[]'::jsonb,
  regularizacion_texto text,
  fotos_regularizacion jsonb NOT NULL DEFAULT '[]'::jsonb,

  resumen_mesa jsonb NOT NULL DEFAULT '[]'::jsonb,

  sancion_amonestacion_verbal boolean NOT NULL DEFAULT false,
  sancion_amonestacion_escrita boolean NOT NULL DEFAULT false,
  sancion_reinduccion_formacion boolean NOT NULL DEFAULT false,
  sancion_pernoctacion_vehiculo boolean NOT NULL DEFAULT false,
  sancion_programacion_formacion boolean NOT NULL DEFAULT false,

  nombre_supervisor_atc text,
  firma_tecnico text,
  firma_supervisor_atc text,
  firma_auditor_calidad text
);

CREATE INDEX IF NOT EXISTS idx_informes_auditoria_rut_ito
  ON public.informes_auditoria (rut_ito);
CREATE INDEX IF NOT EXISTS idx_informes_auditoria_rut_tecnico
  ON public.informes_auditoria (rut_tecnico_auditado);
CREATE INDEX IF NOT EXISTS idx_informes_auditoria_created
  ON public.informes_auditoria (created_at DESC);

ALTER TABLE public.informes_auditoria ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS informes_auditoria_insert ON public.informes_auditoria;
CREATE POLICY informes_auditoria_insert ON public.informes_auditoria
  FOR INSERT TO anon, authenticated WITH CHECK (true);

DROP POLICY IF EXISTS informes_auditoria_select ON public.informes_auditoria;
CREATE POLICY informes_auditoria_select ON public.informes_auditoria
  FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS informes_auditoria_update ON public.informes_auditoria;
CREATE POLICY informes_auditoria_update ON public.informes_auditoria
  FOR UPDATE TO anon, authenticated USING (true);

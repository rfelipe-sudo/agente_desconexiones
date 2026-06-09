-- GPS de partida en solicitudes de material (ven_por_el / yo_te_lo_llevo)
ALTER TABLE solicitudes_material
  ADD COLUMN IF NOT EXISTS lat_partida double precision,
  ADD COLUMN IF NOT EXISTS lng_partida double precision,
  ADD COLUMN IF NOT EXISTS partida_at timestamptz;

-- Último punto de fin de viaje → partida del siguiente (por técnico)
CREATE TABLE IF NOT EXISTS combustible_ruta_estado (
  rut_tecnico   text PRIMARY KEY,
  lat           double precision NOT NULL,
  lng           double precision NOT NULL,
  orden_trabajo text,
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- Km calculados por GPS en entregas de material
ALTER TABLE combustible_materiales
  ADD COLUMN IF NOT EXISTS km_ida double precision,
  ADD COLUMN IF NOT EXISTS km_vuelta double precision,
  ADD COLUMN IF NOT EXISTS incluye_vuelta boolean DEFAULT false;

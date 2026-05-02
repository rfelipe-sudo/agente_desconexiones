-- ═══════════════════════════════════════════════════════════════════════════
-- TABLA configuracion_app
-- Almacena credenciales y parámetros de APIs externas (Nyquist, etc.)
-- Se debe ejecutar una sola vez en Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Crear tabla
CREATE TABLE IF NOT EXISTS configuracion_app (
  id          BIGSERIAL PRIMARY KEY,
  clave       TEXT NOT NULL UNIQUE,
  valor       TEXT NOT NULL,
  descripcion TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Índice para búsqueda por clave
CREATE INDEX IF NOT EXISTS idx_configuracion_app_clave ON configuracion_app(clave);

-- 3. Trigger para actualizar updated_at automáticamente
CREATE OR REPLACE FUNCTION update_configuracion_app_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_update_configuracion_app ON configuracion_app;
CREATE TRIGGER trg_update_configuracion_app
  BEFORE UPDATE ON configuracion_app
  FOR EACH ROW EXECUTE FUNCTION update_configuracion_app_updated_at();

-- 4. Row Level Security: solo usuarios autenticados pueden leer
ALTER TABLE configuracion_app ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Autenticados pueden leer configuracion" ON configuracion_app;
CREATE POLICY "Autenticados pueden leer configuracion"
  ON configuracion_app FOR SELECT
  USING (auth.role() = 'authenticated');

-- Solo el service_role puede insertar/actualizar (nunca desde la app)
DROP POLICY IF EXISTS "Solo service_role puede modificar configuracion" ON configuracion_app;
CREATE POLICY "Solo service_role puede modificar configuracion"
  ON configuracion_app FOR ALL
  USING (auth.role() = 'service_role');

-- 5. Insertar credenciales Nyquist
-- IMPORTANTE: Cambiar estos valores si las credenciales cambian
INSERT INTO configuracion_app (clave, valor, descripcion) VALUES
  ('nyquist_url',      'https://nyquisttraza.sbip.cl/onfide/estado-vecino', 'URL base de la API Nyquist para consultar estado de CTO'),
  ('nyquist_usuario',  '0npVpRUG7MegtpmfdDuJ3A',                           'Usuario para autenticación básica en Nyquist'),
  ('nyquist_password', 'Ddw3u241Y0MN_x7ezZixKIJtk1ZRHpG6Zz2tCYrhXVg',    'Contraseña para autenticación básica en Nyquist'),
  ('nyquist_vno_id',   '02',                                                'VNO ID de Creaciones Tecnológicas en Nyquist (prefijo del access_id)')
ON CONFLICT (clave) DO UPDATE
  SET valor = EXCLUDED.valor,
      descripcion = EXCLUDED.descripcion,
      updated_at = NOW();

-- 6. Verificar inserción
SELECT clave, descripcion, LEFT(valor, 10) || '...' AS valor_parcial
FROM configuracion_app
WHERE clave LIKE 'nyquist%'
ORDER BY clave;

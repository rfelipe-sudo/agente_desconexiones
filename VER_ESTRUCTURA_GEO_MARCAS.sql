-- ═══════════════════════════════════════════════════════════════════
-- 🔍 DIAGNÓSTICO: Estructura de geo_marcas_diarias
-- ═══════════════════════════════════════════════════════════════════

-- 1️⃣ Ver todas las columnas de la tabla
SELECT 
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_name = 'geo_marcas_diarias'
ORDER BY ordinal_position;

-- 2️⃣ Ver algunos registros de ejemplo
SELECT *
FROM geo_marcas_diarias
LIMIT 10;

-- 3️⃣ Ver registros de diciembre 2025
SELECT *
FROM geo_marcas_diarias
WHERE fecha >= '2025-12-01'
  AND fecha <= '2025-12-31'
ORDER BY fecha
LIMIT 20;





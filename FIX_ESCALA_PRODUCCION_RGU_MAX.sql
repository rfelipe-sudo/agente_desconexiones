-- ═══════════════════════════════════════════════════════════════════
-- 🔧 CORREGIR ESCALA DE PRODUCCIÓN: Ampliar rgu_max
-- ═══════════════════════════════════════════════════════════════════

-- 1️⃣ Ver el tipo de dato actual
SELECT 
    column_name,
    data_type,
    numeric_precision,
    numeric_scale
FROM information_schema.columns
WHERE table_name = 'escala_produccion'
  AND column_name IN ('rgu_min', 'rgu_max');

-- 2️⃣ Cambiar el tipo de dato de rgu_max para que acepte 999.99
ALTER TABLE escala_produccion
ALTER COLUMN rgu_max TYPE NUMERIC(5,2);

-- 3️⃣ También cambiar rgu_min por consistencia
ALTER TABLE escala_produccion
ALTER COLUMN rgu_min TYPE NUMERIC(5,2);

-- 4️⃣ Ahora sí actualizar el último tramo
UPDATE escala_produccion
SET rgu_max = 999.99
WHERE id = 11;

-- 5️⃣ Verificar que quedó bien
SELECT 
    id,
    rgu_min,
    rgu_max,
    liquido_aprox
FROM escala_produccion
ORDER BY rgu_min;





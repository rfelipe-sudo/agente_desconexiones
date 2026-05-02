-- ═══════════════════════════════════════════════════════════════════
-- 🔍 DIAGNÓSTICO: ¿Por qué sigue devolviendo 27?
-- ═══════════════════════════════════════════════════════════════════

-- 1️⃣ Verificar si existen feriados en geo_marcas_diarias para diciembre 2025
SELECT 
    '1️⃣ Feriados en Diciembre 2025' AS test,
    fecha,
    es_feriado,
    EXTRACT(DOW FROM fecha) AS dia_semana
FROM geo_marcas_diarias
WHERE fecha >= '2025-12-01'
  AND fecha <= '2025-12-31'
  AND es_feriado = true
ORDER BY fecha;

-- 2️⃣ Contar feriados que caen en L-S
SELECT 
    '2️⃣ Feriados laborales (L-S) en Diciembre' AS test,
    COUNT(*) AS total_feriados
FROM geo_marcas_diarias
WHERE fecha >= '2025-12-01'
  AND fecha <= '2025-12-31'
  AND es_feriado = true
  AND EXTRACT(DOW FROM fecha) BETWEEN 1 AND 6;

-- 3️⃣ Ver tipo de dato de la columna fecha
SELECT 
    '3️⃣ Tipo de dato de fecha' AS test,
    column_name,
    data_type
FROM information_schema.columns
WHERE table_name = 'geo_marcas_diarias'
  AND column_name = 'fecha';

-- 4️⃣ Ver todas las columnas de geo_marcas_diarias para diciembre
SELECT 
    '4️⃣ Datos de diciembre 2025' AS test,
    fecha,
    es_feriado,
    EXTRACT(DOW FROM fecha) AS dia_semana
FROM geo_marcas_diarias
WHERE fecha >= '2025-12-01'
  AND fecha <= '2025-12-31'
ORDER BY fecha
LIMIT 10;


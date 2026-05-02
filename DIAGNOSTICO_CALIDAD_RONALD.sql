-- ═══════════════════════════════════════════════════════════════════
-- 🔍 DIAGNÓSTICO: Porcentaje de calidad de Ronald Sierra Peña
-- ═══════════════════════════════════════════════════════════════════
-- La vista muestra 6.98% pero el cálculo manual da 7.5%
-- RUT: 25861660-K
-- Período calidad: 21/11/2025 - 20/12/2025
-- ═══════════════════════════════════════════════════════════════════

-- PASO 1: Cálculo manual directo desde calidad_crea
SELECT 
    '1. Cálculo manual desde calidad_crea' AS paso,
    COUNT(DISTINCT orden_original) AS total_ordenes,
    COUNT(DISTINCT CASE WHEN orden_reiterada IS NOT NULL THEN orden_original END) AS ordenes_reiteradas,
    COUNT(CASE WHEN orden_reiterada IS NOT NULL THEN 1 END) AS total_reiterados,
    ROUND(
        (COUNT(DISTINCT CASE WHEN orden_reiterada IS NOT NULL THEN orden_original END)::NUMERIC / 
         NULLIF(COUNT(DISTINCT orden_original), 0) * 100), 
        2
    ) AS porcentaje_por_ordenes_reiteradas,
    ROUND(
        (COUNT(CASE WHEN orden_reiterada IS NOT NULL THEN 1 END)::NUMERIC / 
         NULLIF(COUNT(DISTINCT orden_original), 0) * 100), 
        2
    ) AS porcentaje_por_total_reiterados
FROM calidad_crea
WHERE rut_tecnico_original = '25861660-K'
  AND fecha_original >= '2025-11-21'
  AND fecha_original <= '2025-12-20';

-- PASO 2: Ver las órdenes reiteradas
SELECT 
    '2. Detalle de órdenes reiteradas' AS paso,
    orden_original,
    fecha_original,
    orden_reiterada,
    fecha_reiterada,
    descripcion_reiterado
FROM calidad_crea
WHERE rut_tecnico_original = '25861660-K'
  AND fecha_original >= '2025-11-21'
  AND fecha_original <= '2025-12-20'
  AND orden_reiterada IS NOT NULL
ORDER BY fecha_original;

-- PASO 3: Contar órdenes únicas ejecutadas en el período
SELECT 
    '3. Órdenes ejecutadas en período' AS paso,
    COUNT(DISTINCT orden_trabajo) AS ordenes_ejecutadas,
    MIN(fecha_trabajo) AS primera_fecha,
    MAX(fecha_trabajo) AS ultima_fecha
FROM produccion_crea
WHERE rut_tecnico = '25861660-K'
  AND fecha_trabajo LIKE '%/11/2025'
     OR fecha_trabajo LIKE '%/12/2025'
  AND estado = 'Completado';

-- PASO 4: Ver lo que dice v_calidad_tecnicos
SELECT 
    '4. Vista v_calidad_tecnicos' AS paso,
    rut_tecnico,
    tecnico,
    periodo,
    total_trabajos,
    total_reiterados,
    porcentaje_reiteracion,
    ordenes_reiteradas,
    ordenes_totales
FROM v_calidad_tecnicos
WHERE rut_tecnico = '25861660-K'
  AND periodo = '21/11/2025-20/12/2025';

-- PASO 5: Verificar si hay múltiples reiteraciones de la misma orden
WITH reiteraciones AS (
    SELECT 
        orden_original,
        COUNT(*) AS veces_reiterada
    FROM calidad_crea
    WHERE rut_tecnico_original = '25861660-K'
      AND fecha_original >= '2025-11-21'
      AND fecha_original <= '2025-12-20'
      AND orden_reiterada IS NOT NULL
    GROUP BY orden_original
)
SELECT 
    '5. Órdenes con múltiples reiteraciones' AS paso,
    orden_original,
    veces_reiterada
FROM reiteraciones
WHERE veces_reiterada > 1;

-- PASO 6: Contar todas las combinaciones únicas
SELECT 
    '6. Combinaciones únicas en calidad_crea' AS paso,
    COUNT(*) AS total_registros,
    COUNT(DISTINCT orden_original) AS ordenes_distintas,
    COUNT(DISTINCT CASE WHEN orden_reiterada IS NOT NULL THEN orden_original END) AS ordenes_con_reiteracion,
    COUNT(DISTINCT orden_reiterada) AS reiteraciones_distintas
FROM calidad_crea
WHERE rut_tecnico_original = '25861660-K'
  AND fecha_original >= '2025-11-21'
  AND fecha_original <= '2025-12-20';

-- ═══════════════════════════════════════════════════════════════════
-- ✅ ANÁLISIS ESPERADO
-- ═══════════════════════════════════════════════════════════════════
/*
Si el técnico tiene:
- 40 órdenes ejecutadas
- 3 órdenes reiteradas
- Porcentaje: 3/40 × 100 = 7.5%

Pero la vista muestra 6.98%, posibles causas:

1. OPCIÓN A: Está contando 43 órdenes en lugar de 40
   - 3/43 × 100 = 6.98% ✅
   - Puede estar sumando las órdenes originales + reiteradas

2. OPCIÓN B: Está usando un período diferente
   - Puede estar usando fechas del mes actual en lugar del período de calidad

3. OPCIÓN C: Está contando trabajos duplicados
   - La vista puede estar contando mal los trabajos totales

La corrección dependerá de cuál sea la causa.
*/




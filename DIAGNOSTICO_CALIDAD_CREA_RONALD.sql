-- ═══════════════════════════════════════════════════════════════════
-- 🔍 DIAGNÓSTICO PROFUNDO: Tabla calidad_crea para Ronald Sierra
-- ═══════════════════════════════════════════════════════════════════

-- 1. Ver TODOS los registros de calidad para Ronald
SELECT 
    '📋 Registros completos en calidad_crea' AS diagnostico,
    *
FROM calidad_crea
WHERE rut_tecnico_original = '25861660-K'
  AND fecha_original >= '2025-11-21'
  AND fecha_original <= '2025-12-20'
ORDER BY fecha_original;

-- 2. Ver específicamente las columnas clave
SELECT 
    '🔑 Columnas clave' AS diagnostico,
    orden_original,
    fecha_original,
    orden_reiterada,
    fecha_reiterada,
    dias_reiterado,
    CASE 
        WHEN orden_reiterada IS NULL THEN '⚠️ NULL'
        WHEN orden_reiterada = '' THEN '⚠️ VACÍO'
        ELSE '✅ TIENE VALOR'
    END AS estado_orden_reiterada
FROM calidad_crea
WHERE rut_tecnico_original = '25861660-K'
  AND fecha_original >= '2025-11-21'
  AND fecha_original <= '2025-12-20'
ORDER BY fecha_original;

-- 3. Verificar si alguna de estas órdenes reiteradas está en produccion_crea
SELECT 
    '🔗 ¿Las reiteraciones están en produccion_crea?' AS diagnostico,
    cc.orden_original,
    cc.orden_reiterada,
    CASE 
        WHEN pc.orden_trabajo IS NOT NULL THEN '✅ SÍ está en produccion_crea'
        ELSE '❌ NO está en produccion_crea'
    END AS encontrada
FROM calidad_crea cc
LEFT JOIN produccion_crea pc ON pc.orden_trabajo = cc.orden_reiterada
WHERE cc.rut_tecnico_original = '25861660-K'
  AND cc.fecha_original >= '2025-11-21'
  AND cc.fecha_original <= '2025-12-20'
ORDER BY cc.fecha_original;

-- 4. Buscar las 3 reiteraciones por fecha
SELECT 
    '📅 Órdenes por fecha (buscando las 3 reiteradas)' AS diagnostico,
    cc.fecha_original,
    cc.fecha_reiterada,
    cc.orden_original AS orden_original_calidad,
    pc1.orden_trabajo AS orden_en_produccion_fecha_original,
    pc2.orden_trabajo AS orden_en_produccion_fecha_reiterada
FROM calidad_crea cc
LEFT JOIN produccion_crea pc1 
    ON pc1.rut_tecnico = '25861660-K' 
    AND pc1.fecha_trabajo = TO_CHAR(cc.fecha_original, 'DD/MM/YYYY')
LEFT JOIN produccion_crea pc2 
    ON pc2.rut_tecnico = '25861660-K' 
    AND pc2.fecha_trabajo = TO_CHAR(cc.fecha_reiterada, 'DD/MM/YYYY')
WHERE cc.rut_tecnico_original = '25861660-K'
  AND cc.fecha_original >= '2025-11-21'
  AND cc.fecha_original <= '2025-12-20'
ORDER BY cc.fecha_original;

-- 5. Contar órdenes DISTINTAS por fecha de Ronald
SELECT 
    '📊 Órdenes distintas de Ronald por día' AS diagnostico,
    fecha_trabajo,
    COUNT(DISTINCT orden_trabajo) AS ordenes_distintas,
    STRING_AGG(DISTINCT orden_trabajo, ', ') AS ordenes
FROM produccion_crea
WHERE rut_tecnico = '25861660-K'
  AND estado = 'Completado'
  AND (
      (fecha_trabajo LIKE '%/11/2025' AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) >= 21)
      OR
      (fecha_trabajo LIKE '%/12/2025' AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) <= 20)
  )
GROUP BY fecha_trabajo
ORDER BY TO_DATE(fecha_trabajo, 'DD/MM/YYYY');

-- 6. Ver estructura de la tabla calidad_crea
SELECT 
    '📋 Estructura de calidad_crea' AS info,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_name = 'calidad_crea'
ORDER BY ordinal_position;




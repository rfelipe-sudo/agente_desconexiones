-- ═══════════════════════════════════════════════════════════════════
-- 🔍 VERIFICAR: ¿Por qué Ronald tiene 43 trabajos en lugar de 40?
-- ═══════════════════════════════════════════════════════════════════

-- 1. Ver TODAS las órdenes de Ronald en el período de calidad
SELECT 
    '📋 TODAS las órdenes (43 registros)' AS diagnostico,
    orden_trabajo,
    fecha_trabajo,
    estado,
    COUNT(*) OVER (PARTITION BY orden_trabajo) AS veces_que_aparece
FROM produccion_crea
WHERE rut_tecnico = '25861660-K'
  AND estado = 'Completado'
  AND (
      (fecha_trabajo LIKE '%/11/2025' AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) >= 21)
      OR
      (fecha_trabajo LIKE '%/12/2025' AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) <= 20)
  )
ORDER BY fecha_trabajo, orden_trabajo;

-- 2. ¿Hay órdenes DUPLICADAS?
SELECT 
    '🔍 Órdenes que aparecen MÁS DE UNA VEZ' AS diagnostico,
    orden_trabajo,
    COUNT(*) AS cantidad_veces,
    STRING_AGG(fecha_trabajo, ', ') AS fechas
FROM produccion_crea
WHERE rut_tecnico = '25861660-K'
  AND estado = 'Completado'
  AND (
      (fecha_trabajo LIKE '%/11/2025' AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) >= 21)
      OR
      (fecha_trabajo LIKE '%/12/2025' AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) <= 20)
  )
GROUP BY orden_trabajo
HAVING COUNT(*) > 1
ORDER BY COUNT(*) DESC;

-- 3. Contar ÓRDENES DISTINTAS (únicas)
SELECT 
    '📊 Resumen: Registros vs Órdenes Únicas' AS diagnostico,
    COUNT(*) AS total_registros,
    COUNT(DISTINCT orden_trabajo) AS ordenes_unicas,
    COUNT(*) - COUNT(DISTINCT orden_trabajo) AS registros_duplicados
FROM produccion_crea
WHERE rut_tecnico = '25861660-K'
  AND estado = 'Completado'
  AND (
      (fecha_trabajo LIKE '%/11/2025' AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) >= 21)
      OR
      (fecha_trabajo LIKE '%/12/2025' AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) <= 20)
  );

-- 4. ¿Cuáles de esas órdenes son REITERACIONES?
SELECT 
    '🔍 ¿Cuáles órdenes son REITERACIONES de otra orden?' AS diagnostico,
    pc.orden_trabajo,
    pc.fecha_trabajo,
    cc.orden_original AS es_reiteracion_de,
    cc.fecha_original
FROM produccion_crea pc
LEFT JOIN calidad_crea cc ON cc.orden_reiterada = pc.orden_trabajo
WHERE pc.rut_tecnico = '25861660-K'
  AND pc.estado = 'Completado'
  AND (
      (pc.fecha_trabajo LIKE '%/11/2025' AND CAST(SPLIT_PART(pc.fecha_trabajo, '/', 1) AS INTEGER) >= 21)
      OR
      (pc.fecha_trabajo LIKE '%/12/2025' AND CAST(SPLIT_PART(pc.fecha_trabajo, '/', 1) AS INTEGER) <= 20)
  )
ORDER BY pc.fecha_trabajo;

-- 5. CONTAR: ¿Cuántas son ORIGINALES y cuántas son REITERACIONES?
SELECT 
    '📊 Resumen: Originales vs Reiteraciones' AS diagnostico,
    COUNT(*) AS total_ordenes,
    COUNT(*) FILTER (WHERE cc.orden_reiterada IS NULL) AS ordenes_originales,
    COUNT(*) FILTER (WHERE cc.orden_reiterada IS NOT NULL) AS ordenes_que_son_reiteraciones
FROM produccion_crea pc
LEFT JOIN calidad_crea cc ON cc.orden_reiterada = pc.orden_trabajo
WHERE pc.rut_tecnico = '25861660-K'
  AND pc.estado = 'Completado'
  AND (
      (pc.fecha_trabajo LIKE '%/11/2025' AND CAST(SPLIT_PART(pc.fecha_trabajo, '/', 1) AS INTEGER) >= 21)
      OR
      (pc.fecha_trabajo LIKE '%/12/2025' AND CAST(SPLIT_PART(pc.fecha_trabajo, '/', 1) AS INTEGER) <= 20)
  );

-- ═══════════════════════════════════════════════════════════════════
-- RESPUESTAS ESPERADAS:
-- ═══════════════════════════════════════════════════════════════════
/*
CASO 1: Si hay DUPLICADOS
- Resultado 2 mostrará órdenes repetidas
- Resultado 3 mostrará: 43 registros, 40 únicas, 3 duplicados
- Solución: Usar COUNT(DISTINCT orden_trabajo) en la vista

CASO 2: Si 3 órdenes son REITERACIONES
- Resultado 4 mostrará 3 órdenes con valor en "es_reiteracion_de"
- Resultado 5 mostrará: 43 total, 40 originales, 3 reiteraciones
- Solución: Ya está implementada con NOT EXISTS en la vista

CASO 3: Si NO hay ni duplicados ni reiteraciones
- 43 es el número correcto
- El problema es que esperabas 40 pero en realidad son 43
*/




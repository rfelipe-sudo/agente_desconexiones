-- ═══════════════════════════════════════════════════════════════════
-- 🔍 VERIFICAR: Órdenes de Ronald en cada período
-- ═══════════════════════════════════════════════════════════════════

-- 1. Órdenes en período de PRODUCCIÓN (1-31 Diciembre 2025)
SELECT 
    '📊 PRODUCCIÓN: 1-31 Diciembre 2025' AS periodo,
    COUNT(*) AS total_ordenes,
    STRING_AGG(DISTINCT fecha_trabajo, ', ' ORDER BY fecha_trabajo) AS fechas_distintas
FROM produccion_crea
WHERE rut_tecnico = '25861660-K'
  AND estado = 'Completado'
  AND fecha_trabajo LIKE '%/12/2025'
  AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) BETWEEN 1 AND 31;

-- 2. Órdenes en período de CALIDAD (21 Nov - 20 Dic 2025)
SELECT 
    '📊 CALIDAD: 21 Nov - 20 Dic 2025' AS periodo,
    COUNT(*) AS total_ordenes,
    STRING_AGG(DISTINCT fecha_trabajo, ', ' ORDER BY fecha_trabajo) AS fechas_distintas
FROM produccion_crea
WHERE rut_tecnico = '25861660-K'
  AND estado = 'Completado'
  AND (
      (fecha_trabajo LIKE '%/11/2025' AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) >= 21)
      OR
      (fecha_trabajo LIKE '%/12/2025' AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) <= 20)
  );

-- 3. Órdenes SOLO en CALIDAD pero NO en PRODUCCIÓN (21-30 Nov)
SELECT 
    '📊 SOLO en CALIDAD (21-30 Nov)' AS periodo,
    COUNT(*) AS total_ordenes,
    STRING_AGG(fecha_trabajo, ', ' ORDER BY fecha_trabajo) AS fechas
FROM produccion_crea
WHERE rut_tecnico = '25861660-K'
  AND estado = 'Completado'
  AND fecha_trabajo LIKE '%/11/2025'
  AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) >= 21;

-- 4. Órdenes SOLO en PRODUCCIÓN pero NO en CALIDAD (21-31 Dic)
SELECT 
    '📊 SOLO en PRODUCCIÓN (21-31 Dic)' AS periodo,
    COUNT(*) AS total_ordenes,
    STRING_AGG(fecha_trabajo, ', ' ORDER BY fecha_trabajo) AS fechas
FROM produccion_crea
WHERE rut_tecnico = '25861660-K'
  AND estado = 'Completado'
  AND fecha_trabajo LIKE '%/12/2025'
  AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) >= 21;

-- 5. Órdenes en AMBOS períodos (1-20 Dic)
SELECT 
    '📊 En AMBOS períodos (1-20 Dic)' AS periodo,
    COUNT(*) AS total_ordenes,
    STRING_AGG(fecha_trabajo, ', ' ORDER BY fecha_trabajo) AS fechas
FROM produccion_crea
WHERE rut_tecnico = '25861660-K'
  AND estado = 'Completado'
  AND fecha_trabajo LIKE '%/12/2025'
  AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) BETWEEN 1 AND 20;

-- 6. RESUMEN: Verificar la lógica
SELECT 
    '📊 RESUMEN' AS diagnostico,
    (SELECT COUNT(*) FROM produccion_crea 
     WHERE rut_tecnico = '25861660-K' AND estado = 'Completado'
     AND fecha_trabajo LIKE '%/12/2025'
     AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) BETWEEN 1 AND 31) AS produccion_1_31_dic,
    
    (SELECT COUNT(*) FROM produccion_crea 
     WHERE rut_tecnico = '25861660-K' AND estado = 'Completado'
     AND (
         (fecha_trabajo LIKE '%/11/2025' AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) >= 21)
         OR
         (fecha_trabajo LIKE '%/12/2025' AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) <= 20)
     )) AS calidad_21nov_20dic,
    
    (SELECT COUNT(DISTINCT orden_original)
     FROM calidad_crea
     WHERE rut_tecnico_original = '25861660-K'
       AND fecha_original >= '2025-11-21'
       AND fecha_original <= '2025-12-20'
       AND dias_reiterado <= 30) AS reiterados_calidad,
    
    -- Dashboard (INCORRECTO): reiterados de calidad / órdenes de producción
    ROUND(
        (SELECT COUNT(DISTINCT orden_original)::NUMERIC FROM calidad_crea
         WHERE rut_tecnico_original = '25861660-K'
           AND fecha_original >= '2025-11-21' AND fecha_original <= '2025-12-20'
           AND dias_reiterado <= 30) 
        / 
        (SELECT COUNT(*)::NUMERIC FROM produccion_crea 
         WHERE rut_tecnico = '25861660-K' AND estado = 'Completado'
         AND fecha_trabajo LIKE '%/12/2025'
         AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) BETWEEN 1 AND 31) 
        * 100, 2
    ) AS porc_dashboard_incorrecto,
    
    -- SQL Vista (CORRECTO): reiterados de calidad / órdenes de calidad
    ROUND(
        (SELECT COUNT(DISTINCT orden_original)::NUMERIC FROM calidad_crea
         WHERE rut_tecnico_original = '25861660-K'
           AND fecha_original >= '2025-11-21' AND fecha_original <= '2025-12-20'
           AND dias_reiterado <= 30) 
        / 
        (SELECT COUNT(*)::NUMERIC FROM produccion_crea 
         WHERE rut_tecnico = '25861660-K' AND estado = 'Completado'
         AND (
             (fecha_trabajo LIKE '%/11/2025' AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) >= 21)
             OR
             (fecha_trabajo LIKE '%/12/2025' AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) <= 20)
         )) 
        * 100, 2
    ) AS porc_sql_correcto;

-- ═══════════════════════════════════════════════════════════════════
-- EXPLICACIÓN
-- ═══════════════════════════════════════════════════════════════════
/*
VERIFICACIÓN:
- Producción (1-31 dic): Debería ser 40 órdenes
- Calidad (21 nov - 20 dic): Debería ser 43 órdenes
- Reiterados (21 nov - 20 dic): 3 órdenes

DIFERENCIA:
- Del 21-30 Nov: X órdenes (en calidad, NO en producción)
- Del 21-31 Dic: Y órdenes (en producción, NO en calidad)
- Del 1-20 Dic: Z órdenes (en AMBOS períodos)

CÁLCULOS:
- Dashboard (INCORRECTO): 3 / 40 = 7.5%
  (reiterados del período de calidad / órdenes del período de producción)
  
- SQL Vista (CORRECTO): 3 / 43 = 6.98%
  (reiterados del período de calidad / órdenes del período de calidad)

CONCLUSIÓN:
Si el resultado 6 muestra:
- produccion_1_31_dic = 40
- calidad_21nov_20dic = 43
- porc_dashboard_incorrecto = 7.50
- porc_sql_correcto = 6.98

Entonces el dashboard está mezclando períodos y necesita corrección.
*/




-- ═══════════════════════════════════════════════════════════════════
-- 🔍 DEBUG: ¿Por qué sale 6% en lugar de 7%?
-- ═══════════════════════════════════════════════════════════════════

-- 1. Ver el cálculo paso a paso
SELECT 
    '🔍 Cálculo paso a paso' AS debug,
    rut_tecnico,
    periodo,
    ordenes_reiteradas,
    total_trabajos,
    -- Cálculo crudo (sin redondear)
    (ordenes_reiteradas::NUMERIC / total_trabajos::NUMERIC) * 100 AS porcentaje_crudo,
    -- Con 2 decimales
    ROUND((ordenes_reiteradas::NUMERIC / total_trabajos::NUMERIC) * 100, 2) AS con_2_decimales,
    -- Con 0 decimales (redondeo actual)
    ROUND((ordenes_reiteradas::NUMERIC / total_trabajos::NUMERIC) * 100, 0) AS con_0_decimales,
    -- Con CEILING (siempre hacia arriba)
    CEILING((ordenes_reiteradas::NUMERIC / total_trabajos::NUMERIC) * 100) AS ceiling_hacia_arriba,
    -- Porcentaje que está guardado
    porcentaje_reiteracion AS porcentaje_en_vista
FROM v_calidad_tecnicos
WHERE rut_tecnico = '25861660-K'
  AND periodo = '2026-01';

-- 2. Verificar cuántas órdenes y reiterados hay
SELECT 
    '📊 Datos base' AS debug,
    (SELECT COUNT(*) FROM produccion_crea 
     WHERE rut_tecnico = '25861660-K' AND estado = 'Completado'
     AND (
         (fecha_trabajo LIKE '%/11/2025' AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) >= 21)
         OR
         (fecha_trabajo LIKE '%/12/2025' AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) <= 20)
     )) AS ordenes_periodo_calidad,
    
    (SELECT COUNT(DISTINCT orden_original) FROM calidad_crea
     WHERE rut_tecnico_original = '25861660-K'
       AND fecha_original >= '2025-11-21'
       AND fecha_original <= '2025-12-20'
       AND dias_reiterado <= 30) AS reiterados_periodo_calidad,
    
    -- Cálculo manual
    ROUND(
        (SELECT COUNT(DISTINCT orden_original)::NUMERIC FROM calidad_crea
         WHERE rut_tecnico_original = '25861660-K'
           AND fecha_original >= '2025-11-21'
           AND fecha_original <= '2025-12-20'
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
    ) AS porcentaje_manual_2_decimales,
    
    ROUND(
        (SELECT COUNT(DISTINCT orden_original)::NUMERIC FROM calidad_crea
         WHERE rut_tecnico_original = '25861660-K'
           AND fecha_original >= '2025-11-21'
           AND fecha_original <= '2025-12-20'
           AND dias_reiterado <= 30)
        /
        (SELECT COUNT(*)::NUMERIC FROM produccion_crea 
         WHERE rut_tecnico = '25861660-K' AND estado = 'Completado'
         AND (
             (fecha_trabajo LIKE '%/11/2025' AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) >= 21)
             OR
             (fecha_trabajo LIKE '%/12/2025' AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) <= 20)
         ))
        * 100, 0
    ) AS porcentaje_manual_0_decimales;

-- 3. Ver qué está en pagos_tecnicos
SELECT 
    '💰 Tabla pagos_tecnicos' AS debug,
    porcentaje_reiteracion,
    bono_calidad_bruto,
    bono_calidad_liquido
FROM pagos_tecnicos
WHERE rut_tecnico = '25861660-K'
  AND periodo = '2026-01';

-- ═══════════════════════════════════════════════════════════════════
-- EXPLICACIÓN
-- ═══════════════════════════════════════════════════════════════════
/*
Si el resultado 2 muestra:
- ordenes_periodo_calidad: 43
- reiterados_periodo_calidad: 3
- porcentaje_manual_2_decimales: 6.98
- porcentaje_manual_0_decimales: 7

Entonces el problema está en la función calcular_bonos_prorrateo_simple()
que está obteniendo un valor diferente.

Si muestra un número diferente de órdenes o reiterados,
entonces hay un problema en la vista v_calidad_tecnicos.
*/




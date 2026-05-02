-- ═══════════════════════════════════════════════════════════════════
-- 🔍 VERIFICAR Y RECALCULAR PASO A PASO
-- ═══════════════════════════════════════════════════════════════════
-- Este script verifica si la vista se actualizó y recalcula los bonos
-- ═══════════════════════════════════════════════════════════════════

-- ═════════════════════════════════════════════════════════════════
-- PASO 1: VERIFICAR SI LA VISTA ESTÁ ACTUALIZADA
-- ═════════════════════════════════════════════════════════════════

-- 1.1: Ver definición de la vista
SELECT 
    '🔍 PASO 1.1: Verificar definición de vista' AS paso;

-- Ver si la vista tiene la columna 'ordenes_reiteradas'
SELECT 
    column_name,
    data_type
FROM information_schema.columns
WHERE table_name = 'v_calidad_tecnicos'
  AND column_name IN ('ordenes_reiteradas', 'total_trabajos', 'ordenes_totales')
ORDER BY ordinal_position;

-- Si NO aparece 'ordenes_reiteradas', la vista NO se actualizó ❌

-- 1.2: Ver datos actuales de Ronald
SELECT 
    '🔍 PASO 1.2: Datos actuales de Ronald en v_calidad_tecnicos' AS paso,
    *
FROM v_calidad_tecnicos
WHERE rut_tecnico = '25861660-K'
  AND periodo = '2026-01';

-- ═════════════════════════════════════════════════════════════════
-- PASO 2: CÁLCULO MANUAL (para comparar)
-- ═════════════════════════════════════════════════════════════════

SELECT 
    '📊 PASO 2: Cálculo manual directo' AS paso;

-- Contar órdenes ORIGINALES (sin contar reiteradas)
WITH ordenes_originales AS (
    SELECT COUNT(DISTINCT pc.orden_trabajo) AS total
    FROM produccion_crea pc
    WHERE pc.rut_tecnico = '25861660-K'
      AND pc.estado = 'Completado'
      AND (
          (pc.fecha_trabajo LIKE '%/11/2025' AND CAST(SPLIT_PART(pc.fecha_trabajo, '/', 1) AS INTEGER) >= 21)
          OR
          (pc.fecha_trabajo LIKE '%/12/2025' AND CAST(SPLIT_PART(pc.fecha_trabajo, '/', 1) AS INTEGER) <= 20)
      )
      -- Excluir las que son reiteraciones
      AND NOT EXISTS (
          SELECT 1 FROM calidad_crea cc 
          WHERE cc.orden_reiterada = pc.orden_trabajo
      )
),
ordenes_con_reiteracion AS (
    SELECT COUNT(DISTINCT cc.orden_original) AS total
    FROM calidad_crea cc
    WHERE cc.rut_tecnico_original = '25861660-K'
      AND cc.fecha_original >= '2025-11-21'
      AND cc.fecha_original <= '2025-12-20'
      AND cc.dias_reiterado <= 30
      AND cc.orden_reiterada IS NOT NULL
)
SELECT 
    oo.total AS ordenes_originales_esperado_40,
    ocr.total AS ordenes_reiteradas_esperado_3,
    ROUND(ocr.total::NUMERIC / NULLIF(oo.total, 0) * 100, 2) AS porcentaje_esperado_7_5
FROM ordenes_originales oo
CROSS JOIN ordenes_con_reiteracion ocr;

-- ═════════════════════════════════════════════════════════════════
-- PASO 3: SI LA VISTA NO ESTÁ ACTUALIZADA, ACTUALIZARLA AHORA
-- ═════════════════════════════════════════════════════════════════

-- Eliminar vista actual
DROP VIEW IF EXISTS v_calidad_tecnicos CASCADE;

-- Crear vista CORREGIDA
CREATE OR REPLACE VIEW v_calidad_tecnicos AS
WITH produccion_periodo AS (
    SELECT 
        pc.rut_tecnico,
        CASE 
            WHEN EXTRACT(DAY FROM TO_DATE(pc.fecha_trabajo, 'DD/MM/YYYY')) <= 20 
            THEN DATE_TRUNC('month', TO_DATE(pc.fecha_trabajo, 'DD/MM/YYYY')) + INTERVAL '1 month'
            ELSE DATE_TRUNC('month', TO_DATE(pc.fecha_trabajo, 'DD/MM/YYYY')) + INTERVAL '2 months'
        END AS mes_medicion,
        COUNT(*) AS total_completadas
    FROM produccion_crea pc
    WHERE pc.estado = 'Completado'
      AND NOT EXISTS (
          SELECT 1 FROM calidad_crea cc 
          WHERE cc.orden_reiterada = pc.orden_trabajo
      )
    GROUP BY 
        pc.rut_tecnico,
        CASE 
            WHEN EXTRACT(DAY FROM TO_DATE(pc.fecha_trabajo, 'DD/MM/YYYY')) <= 20 
            THEN DATE_TRUNC('month', TO_DATE(pc.fecha_trabajo, 'DD/MM/YYYY')) + INTERVAL '1 month'
            ELSE DATE_TRUNC('month', TO_DATE(pc.fecha_trabajo, 'DD/MM/YYYY')) + INTERVAL '2 months'
        END
),
reiterados_periodo AS (
    SELECT 
        c.rut_tecnico_original,
        MIN(c.tecnico_original) AS tecnico_original,
        CASE 
            WHEN EXTRACT(DAY FROM c.fecha_original) <= 20 
            THEN DATE_TRUNC('month', c.fecha_original) + INTERVAL '1 month'
            ELSE DATE_TRUNC('month', c.fecha_original) + INTERVAL '2 months'
        END AS mes_medicion,
        SUM(CASE WHEN c.dias_reiterado <= 30 THEN 1 ELSE 0 END) AS total_reiterados,
        SUM(CASE WHEN c.dias_reiterado > 30 THEN 1 ELSE 0 END) AS reiterados_fuera_garantia,
        COUNT(*) AS reiterados_totales,
        COUNT(DISTINCT CASE WHEN c.dias_reiterado <= 30 THEN c.orden_original END) AS ordenes_reiteradas,
        ROUND(AVG(CASE WHEN c.dias_reiterado <= 30 THEN c.dias_reiterado ELSE NULL END), 1) AS promedio_dias,
        MIN(CASE WHEN c.dias_reiterado <= 30 THEN c.dias_reiterado ELSE NULL END) AS min_dias,
        MAX(CASE WHEN c.dias_reiterado <= 30 THEN c.dias_reiterado ELSE NULL END) AS max_dias,
        SUM(CASE WHEN c.dias_reiterado <= 30 AND c.tipo_actividad ILIKE '%alta%' THEN 1 ELSE 0 END) AS reiterados_alta,
        SUM(CASE WHEN c.dias_reiterado <= 30 AND c.tipo_actividad ILIKE '%migraci%' THEN 1 ELSE 0 END) AS reiterados_migracion,
        SUM(CASE WHEN c.dias_reiterado <= 30 AND (c.tipo_actividad ILIKE '%reparaci%' OR c.tipo_actividad ILIKE '%averia%') THEN 1 ELSE 0 END) AS reiterados_reparacion
    FROM calidad_crea c
    WHERE c.fecha_reiterada IS NOT NULL
    GROUP BY 
        c.rut_tecnico_original,
        CASE 
            WHEN EXTRACT(DAY FROM c.fecha_original) <= 20 
            THEN DATE_TRUNC('month', c.fecha_original) + INTERVAL '1 month'
            ELSE DATE_TRUNC('month', c.fecha_original) + INTERVAL '2 months'
        END
)
SELECT 
    p.rut_tecnico,
    COALESCE(r.tecnico_original, 'Técnico ' || p.rut_tecnico) AS tecnico,
    TO_CHAR(p.mes_medicion, 'YYYY-MM') AS periodo,
    TO_CHAR(p.mes_medicion, 'TMMonth YYYY') AS periodo_nombre,
    COALESCE(r.total_reiterados, 0) AS total_reiterados,
    COALESCE(r.reiterados_fuera_garantia, 0) AS reiterados_fuera_garantia,
    COALESCE(r.reiterados_totales, 0) AS reiterados_totales,
    COALESCE(r.ordenes_reiteradas, 0) AS ordenes_reiteradas,
    r.promedio_dias,
    r.min_dias,
    r.max_dias,
    COALESCE(r.reiterados_alta, 0) AS reiterados_alta,
    COALESCE(r.reiterados_migracion, 0) AS reiterados_migracion,
    COALESCE(r.reiterados_reparacion, 0) AS reiterados_reparacion,
    p.total_completadas AS total_trabajos,
    p.total_completadas + COALESCE(r.ordenes_reiteradas, 0) AS ordenes_totales,
    CASE 
        WHEN p.total_completadas > 0 
        THEN ROUND(COALESCE(r.ordenes_reiteradas, 0)::NUMERIC / p.total_completadas * 100, 2)
        ELSE 0 
    END AS porcentaje_reiteracion
FROM produccion_periodo p
LEFT JOIN reiterados_periodo r 
    ON p.rut_tecnico = r.rut_tecnico_original 
    AND p.mes_medicion = r.mes_medicion
ORDER BY p.mes_medicion DESC, porcentaje_reiteracion DESC;

-- ═════════════════════════════════════════════════════════════════
-- PASO 4: VERIFICAR QUE LA VISTA AHORA ESTÁ CORRECTA
-- ═════════════════════════════════════════════════════════════════

SELECT 
    '✅ PASO 4: Vista actualizada - verificar Ronald' AS paso,
    rut_tecnico,
    tecnico,
    periodo,
    ordenes_reiteradas AS reit_esperado_3,
    total_trabajos AS trabajos_esperado_40,
    ordenes_totales AS total_esperado_43,
    porcentaje_reiteracion AS porc_esperado_7_5,
    CASE 
        WHEN porcentaje_reiteracion BETWEEN 7.4 AND 7.6 THEN '✅ CORRECTO'
        ELSE '❌ INCORRECTO'
    END AS validacion
FROM v_calidad_tecnicos
WHERE rut_tecnico = '25861660-K'
  AND periodo = '2026-01';

-- ═════════════════════════════════════════════════════════════════
-- PASO 5: RECALCULAR BONOS CON LA VISTA CORREGIDA
-- ═════════════════════════════════════════════════════════════════

SELECT 
    '🔄 PASO 5: Recalculando bonos...' AS paso;

-- Recalcular bonos de enero 2026 (producción diciembre 2025)
SELECT * FROM calcular_bonos_prorrateo_simple(12, 2025);

-- ═════════════════════════════════════════════════════════════════
-- PASO 6: VERIFICAR RESULTADO FINAL
-- ═════════════════════════════════════════════════════════════════

SELECT 
    '✅ PASO 6: Resultado final en pagos_tecnicos' AS paso,
    rut_tecnico,
    tecnico,
    periodo,
    porcentaje_reiteracion AS porc_esperado_7_5,
    bono_calidad_bruto AS bono_esperado_96000,
    bono_calidad_liquido AS liquido_esperado_80000,
    CASE 
        WHEN porcentaje_reiteracion BETWEEN 7.4 AND 7.6 
             AND bono_calidad_bruto = 96000 
        THEN '✅ TODO CORRECTO'
        WHEN porcentaje_reiteracion BETWEEN 7.4 AND 7.6 
        THEN '⚠️ Porcentaje correcto pero bono incorrecto'
        ELSE '❌ Porcentaje aún incorrecto'
    END AS validacion
FROM v_pagos_tecnicos
WHERE rut_tecnico = '25861660-K'
  AND periodo = '2026-01';

-- ═════════════════════════════════════════════════════════════════
-- 📊 RESUMEN ESPERADO
-- ═════════════════════════════════════════════════════════════════
/*
PASO 2: Cálculo manual
- ordenes_originales: 40
- ordenes_reiteradas: 3
- porcentaje: 7.50%

PASO 4: Vista actualizada
- ordenes_reiteradas: 3
- total_trabajos: 40
- porcentaje_reiteracion: 7.50%
- validacion: ✅ CORRECTO

PASO 6: Resultado final
- porcentaje_reiteracion: 7.50
- bono_calidad_bruto: 96000
- validacion: ✅ TODO CORRECTO
*/




-- ═══════════════════════════════════════════════════════════════════
-- 🔧 FIX: Excluir órdenes reiteradas del total en v_calidad_tecnicos
-- ═══════════════════════════════════════════════════════════════════
-- PROBLEMA: La vista cuenta las órdenes reiteradas en el total
-- Ejemplo: Ronald Sierra tiene 40 órdenes originales + 3 reiteradas = 43
-- Calcula: 3/43 = 6.98% ❌
-- Debería: 3/40 = 7.5% ✅
-- ═══════════════════════════════════════════════════════════════════

-- PASO 1: Eliminar vista actual
DROP VIEW IF EXISTS v_calidad_tecnicos CASCADE;

-- PASO 2: Crear vista CORREGIDA
CREATE OR REPLACE VIEW v_calidad_tecnicos AS
WITH produccion_periodo AS (
    -- Calcular producción completada por técnico y período
    -- ✅ CORREGIDO: Excluir órdenes que son reiteraciones
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
      -- ✅ EXCLUIR órdenes que son reiteraciones
      AND NOT EXISTS (
          SELECT 1 
          FROM calidad_crea cc 
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
    -- Calcular reiterados por técnico y período
    SELECT 
        c.rut_tecnico_original,
        MIN(c.tecnico_original) AS tecnico_original,
        CASE 
            WHEN EXTRACT(DAY FROM c.fecha_original) <= 20 
            THEN DATE_TRUNC('month', c.fecha_original) + INTERVAL '1 month'
            ELSE DATE_TRUNC('month', c.fecha_original) + INTERVAL '2 months'
        END AS mes_medicion,
        
        -- Contar reiterados dentro de garantía (30 días)
        SUM(CASE WHEN c.dias_reiterado <= 30 THEN 1 ELSE 0 END) AS total_reiterados,
        SUM(CASE WHEN c.dias_reiterado > 30 THEN 1 ELSE 0 END) AS reiterados_fuera_garantia,
        COUNT(*) AS reiterados_totales,
        
        -- Contar órdenes DISTINTAS que fueron reiteradas (dentro de garantía)
        COUNT(DISTINCT CASE WHEN c.dias_reiterado <= 30 THEN c.orden_original END) AS ordenes_reiteradas,
        
        -- Estadísticas solo de reiterados dentro de garantía
        ROUND(AVG(CASE WHEN c.dias_reiterado <= 30 THEN c.dias_reiterado ELSE NULL END), 1) AS promedio_dias,
        MIN(CASE WHEN c.dias_reiterado <= 30 THEN c.dias_reiterado ELSE NULL END) AS min_dias,
        MAX(CASE WHEN c.dias_reiterado <= 30 THEN c.dias_reiterado ELSE NULL END) AS max_dias,
        
        -- Contar por tipo de actividad (solo dentro de garantía)
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
-- Join producción con reiterados
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

-- ═══════════════════════════════════════════════════════════════════
-- ✅ VERIFICACIÓN INMEDIATA
-- ═══════════════════════════════════════════════════════════════════

-- TEST 1: Ronald Sierra - Debe mostrar 7.5%
SELECT 
    '✅ TEST 1: Ronald Sierra' AS test,
    rut_tecnico,
    tecnico,
    periodo,
    ordenes_reiteradas AS ordenes_reit_esperado_3,
    total_trabajos AS trabajos_esperado_40,
    porcentaje_reiteracion AS porc_esperado_7_5
FROM v_calidad_tecnicos 
WHERE rut_tecnico = '25861660-K'
  AND periodo = '2026-01';

-- TEST 2: Ver todos los técnicos del período
SELECT 
    '✅ TEST 2: Todos los técnicos 2026-01' AS test,
    rut_tecnico,
    tecnico,
    ordenes_reiteradas,
    total_trabajos,
    porcentaje_reiteracion
FROM v_calidad_tecnicos 
WHERE periodo = '2026-01'
ORDER BY porcentaje_reiteracion DESC
LIMIT 10;

-- TEST 3: Verificación manual para Ronald
SELECT 
    '✅ TEST 3: Cálculo manual Ronald' AS test,
    COUNT(DISTINCT pc.orden_trabajo) AS ordenes_originales,
    COUNT(DISTINCT cc.orden_original) AS ordenes_con_reiteracion,
    ROUND(
        COUNT(DISTINCT cc.orden_original)::NUMERIC / 
        NULLIF(COUNT(DISTINCT pc.orden_trabajo), 0) * 100, 
        2
    ) AS porcentaje_calculado
FROM produccion_crea pc
LEFT JOIN calidad_crea cc 
    ON pc.orden_trabajo = cc.orden_original
    AND cc.fecha_original >= '2025-11-21'
    AND cc.fecha_original <= '2025-12-20'
    AND cc.dias_reiterado <= 30
WHERE pc.rut_tecnico = '25861660-K'
  AND pc.estado = 'Completado'
  AND (
      (pc.fecha_trabajo LIKE '%/11/2025' AND CAST(SPLIT_PART(pc.fecha_trabajo, '/', 1) AS INTEGER) >= 21)
      OR
      (pc.fecha_trabajo LIKE '%/12/2025' AND CAST(SPLIT_PART(pc.fecha_trabajo, '/', 1) AS INTEGER) <= 20)
  );

-- ═══════════════════════════════════════════════════════════════════
-- 📊 RECALCULAR BONOS DESPUÉS DE CORRECCIÓN
-- ═══════════════════════════════════════════════════════════════════

-- Recalcular bonos de enero 2026
SELECT * FROM calcular_bonos_prorrateo_simple(12, 2025);

-- ═══════════════════════════════════════════════════════════════════
-- ✅ RESULTADO ESPERADO
-- ═══════════════════════════════════════════════════════════════════
/*
TEST 1: Ronald Sierra
- ordenes_reiteradas: 3
- total_trabajos: 40 (antes era 43)
- porcentaje_reiteracion: 7.50% (antes era 6.98%)

Después del recálculo:
- Bono bruto: $96.000 (tramo 7%)
- Bono prorrateado (22/24): $88.000
*/




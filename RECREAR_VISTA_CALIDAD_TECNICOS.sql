-- ═══════════════════════════════════════════════════════════════════
-- 🔧 RECREAR VISTA: v_calidad_tecnicos
-- ═══════════════════════════════════════════════════════════════════
-- PROBLEMAS CORREGIDOS:
-- 1. ✅ Lógica de garantía: ahora usa dias_reiterado <= 30
-- 2. ✅ Agrupación: solo por RUT (no por nombre de técnico)
-- 3. ✅ Eliminados duplicados
-- ═══════════════════════════════════════════════════════════════════

-- PASO 1: Eliminar vista actual
DROP VIEW IF EXISTS v_calidad_tecnicos CASCADE;

-- PASO 2: Crear vista CORREGIDA
CREATE OR REPLACE VIEW v_calidad_tecnicos AS
WITH produccion_periodo AS (
    -- Calcular producción completada por técnico y período
    SELECT 
        rut_tecnico,
        CASE 
            WHEN EXTRACT(DAY FROM TO_DATE(fecha_trabajo, 'DD/MM/YYYY')) <= 20 
            THEN DATE_TRUNC('month', TO_DATE(fecha_trabajo, 'DD/MM/YYYY')) + INTERVAL '1 month'
            ELSE DATE_TRUNC('month', TO_DATE(fecha_trabajo, 'DD/MM/YYYY')) + INTERVAL '2 months'
        END AS mes_medicion,
        COUNT(*) AS total_completadas
    FROM produccion_crea
    WHERE estado = 'Completado'
    GROUP BY 
        rut_tecnico,
        CASE 
            WHEN EXTRACT(DAY FROM TO_DATE(fecha_trabajo, 'DD/MM/YYYY')) <= 20 
            THEN DATE_TRUNC('month', TO_DATE(fecha_trabajo, 'DD/MM/YYYY')) + INTERVAL '1 month'
            ELSE DATE_TRUNC('month', TO_DATE(fecha_trabajo, 'DD/MM/YYYY')) + INTERVAL '2 months'
        END
),
reiterados_periodo AS (
    -- Calcular reiterados por técnico y período
    -- ✅ CORREGIDO: Ahora agrupa SOLO por RUT
    SELECT 
        c.rut_tecnico_original,
        -- ✅ Tomar cualquier nombre de técnico (el primero alfabéticamente)
        MIN(c.tecnico_original) AS tecnico_original,
        CASE 
            WHEN EXTRACT(DAY FROM c.fecha_original) <= 20 
            THEN DATE_TRUNC('month', c.fecha_original) + INTERVAL '1 month'
            ELSE DATE_TRUNC('month', c.fecha_original) + INTERVAL '2 months'
        END AS mes_medicion,
        
        -- ✅ CORREGIDO: Usa dias_reiterado <= 30 en lugar de comparar fechas
        SUM(CASE WHEN c.dias_reiterado <= 30 THEN 1 ELSE 0 END) AS total_reiterados,
        SUM(CASE WHEN c.dias_reiterado > 30 THEN 1 ELSE 0 END) AS reiterados_fuera_garantia,
        COUNT(*) AS reiterados_totales,
        
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
        -- ✅ CORREGIDO: Ya no agrupa por tecnico_original
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
    r.promedio_dias,
    r.min_dias,
    r.max_dias,
    COALESCE(r.reiterados_alta, 0) AS reiterados_alta,
    COALESCE(r.reiterados_migracion, 0) AS reiterados_migracion,
    COALESCE(r.reiterados_reparacion, 0) AS reiterados_reparacion,
    p.total_completadas,
    CASE 
        WHEN p.total_completadas > 0 
        THEN ROUND(COALESCE(r.total_reiterados, 0)::NUMERIC / p.total_completadas * 100, 2)
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

-- TEST 1: Ver datos de Felipe Plaza (debe tener 7 en 2026-01)
SELECT 
    '✅ TEST 1: Felipe Plaza' AS test,
    rut_tecnico,
    tecnico,
    periodo,
    total_reiterados,
    reiterados_totales,
    porcentaje_reiteracion
FROM v_calidad_tecnicos 
WHERE rut_tecnico = '15342161-7'
ORDER BY periodo DESC;

-- TEST 2: Verificar que no hay duplicados
SELECT 
    '✅ TEST 2: Verificar duplicados' AS test,
    rut_tecnico,
    periodo,
    COUNT(*) AS veces_aparece,
    STRING_AGG(DISTINCT tecnico, ' | ') AS nombres_tecnicos
FROM v_calidad_tecnicos 
WHERE rut_tecnico = '15342161-7'
GROUP BY rut_tecnico, periodo
HAVING COUNT(*) > 1;

-- TEST 3: Comparar con datos reales de v_calidad_detalle
SELECT 
    '✅ TEST 3: Comparación con v_calidad_detalle' AS test,
    'Período 2026-01 debería tener 7 reiterados' AS nota,
    COUNT(*) AS reiterados_reales
FROM v_calidad_detalle
WHERE rut_tecnico_original = '15342161-7'
  AND cuenta_para_calidad = 'SÍ'
  AND fecha_original >= '2025-11-21'
  AND fecha_original <= '2025-12-20';

-- ═══════════════════════════════════════════════════════════════════
-- ✅ RESULTADOS ESPERADOS
-- ═══════════════════════════════════════════════════════════════════
/*
TEST 1: Felipe Plaza
  - Período 2026-01: total_reiterados = 7 ✅
  - Período 2026-02: total_reiterados = 2 ✅
  - Solo UN registro por período (no duplicados) ✅

TEST 2: Verificar duplicados
  - NO debe devolver ninguna fila (sin duplicados) ✅

TEST 3: Comparación
  - reiterados_reales = 7 ✅
*/





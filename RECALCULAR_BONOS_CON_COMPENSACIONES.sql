-- ═══════════════════════════════════════════════════════════════════
-- 🎯 RECALCULAR BONOS INCLUYENDO COMPENSACIONES DE RGU
-- ═══════════════════════════════════════════════════════════════════

-- PASO 1: Verificar compensaciones existentes
SELECT '📊 PASO 1: Verificar compensaciones por mes' AS paso;

SELECT 
    mes,
    COUNT(DISTINCT rut_tecnico) AS tecnicos_con_compensacion,
    COUNT(*) AS total_ajustes,
    SUM(rgu_adicional) AS suma_total
FROM rgu_adicionales
GROUP BY mes
ORDER BY mes DESC
LIMIT 5;

-- PASO 2: Ver top técnicos con compensaciones (Diciembre 2025)
SELECT '📊 PASO 2: Top técnicos con compensaciones (Dic 2025)' AS paso;

SELECT 
    rut_tecnico,
    COUNT(*) AS cantidad_ajustes,
    SUM(rgu_adicional) AS total_compensado,
    STRING_AGG(motivo, ' | ' ORDER BY fecha_creacion) AS motivos
FROM rgu_adicionales
WHERE mes = '2025-12'
GROUP BY rut_tecnico
ORDER BY total_compensado DESC
LIMIT 10;

-- PASO 3: Ver bonos ANTES del recálculo (Diciembre 2025 → Enero 2026)
SELECT '📊 PASO 3: Bonos ANTES del recálculo (periodo 2026-01)' AS paso;

SELECT 
    rut_tecnico,
    tecnico,
    rgu_promedio,
    bono_produccion_bruto,
    bono_calidad_bruto,
    total_bruto
FROM v_pagos_tecnicos
WHERE periodo = '2026-01'
ORDER BY total_bruto DESC
LIMIT 10;

-- PASO 4: Eliminar bonos del período para recalcular
SELECT '🗑️ PASO 4: Eliminar bonos existentes del período 2026-01' AS paso;

DELETE FROM pagos_tecnicos WHERE periodo = '2026-01';

SELECT '✅ Bonos eliminados' AS estado;

-- PASO 5: Recalcular bonos con compensaciones incluidas
SELECT '🔄 PASO 5: Recalcular bonos (Dic 2025 → Ene 2026)' AS paso;

SELECT * FROM calcular_bonos_prorrateo_simple(12, 2025);

-- PASO 6: Ver bonos DESPUÉS del recálculo
SELECT '📊 PASO 6: Bonos DESPUÉS del recálculo (periodo 2026-01)' AS paso;

SELECT 
    rut_tecnico,
    tecnico,
    rgu_promedio,
    bono_produccion_bruto,
    bono_calidad_bruto,
    total_bruto
FROM v_pagos_tecnicos
WHERE periodo = '2026-01'
ORDER BY total_bruto DESC
LIMIT 10;

-- PASO 7: Comparación (técnicos con compensaciones)
SELECT '🔍 PASO 7: Verificar que RGU promedio incluye compensaciones' AS paso;

-- Este query muestra si el RGU promedio cambió para técnicos con compensaciones
WITH compensaciones AS (
    SELECT 
        rut_tecnico,
        SUM(rgu_adicional) AS total_compensado
    FROM rgu_adicionales
    WHERE mes = '2025-12'
    GROUP BY rut_tecnico
),
rgu_base AS (
    SELECT 
        rut_tecnico,
        SUM(rgu_total) AS rgu_base,
        COUNT(DISTINCT fecha_trabajo) AS dias
    FROM produccion_crea
    WHERE fecha_trabajo LIKE '%/12/2025'
      AND estado = 'Completado'
    GROUP BY rut_tecnico
)
SELECT 
    r.rut_tecnico,
    ROUND(r.rgu_base, 2) AS rgu_base,
    ROUND(c.total_compensado, 2) AS rgu_compensado,
    ROUND(r.rgu_base + c.total_compensado, 2) AS rgu_total_esperado,
    r.dias AS dias_trabajados,
    ROUND((r.rgu_base + c.total_compensado) / r.dias, 2) AS promedio_esperado,
    p.rgu_promedio AS promedio_en_pagos,
    CASE 
        WHEN ABS(p.rgu_promedio - ROUND((r.rgu_base + c.total_compensado) / r.dias, 2)) < 0.01 
        THEN '✅ Correcto'
        ELSE '❌ Error'
    END AS verificacion
FROM rgu_base r
INNER JOIN compensaciones c ON r.rut_tecnico = c.rut_tecnico
LEFT JOIN pagos_tecnicos p ON r.rut_tecnico = p.rut_tecnico AND p.periodo = '2026-01'
ORDER BY c.total_compensado DESC
LIMIT 10;

SELECT '✅ RECÁLCULO COMPLETADO' AS estado;

-- ═══════════════════════════════════════════════════════════════════
-- 📝 INSTRUCCIONES ADICIONALES
-- ═══════════════════════════════════════════════════════════════════

-- Para recalcular otros períodos:

-- Enero 2026 → pagado en Febrero 2026:
-- DELETE FROM pagos_tecnicos WHERE periodo = '2026-02';
-- SELECT * FROM calcular_bonos_prorrateo_simple(1, 2026);

-- Febrero 2026 → pagado en Marzo 2026:
-- DELETE FROM pagos_tecnicos WHERE periodo = '2026-03';
-- SELECT * FROM calcular_bonos_prorrateo_simple(2, 2026);


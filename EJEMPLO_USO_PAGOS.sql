-- ═══════════════════════════════════════════════════════════════════
-- 📚 EJEMPLOS PRÁCTICOS DE USO - SISTEMA DE PAGOS
-- ═══════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════
-- EJEMPLO 1: Calcular pago de Felipe Plaza para Enero 2026
-- ═══════════════════════════════════════════════════════════════════

-- Datos necesarios:
-- - RUT: 15342161-7
-- - Período: 2026-01
-- - RGU promedio: calcularlo desde produccion_crea del 1-31 dic 2025
-- - % Reiteración: 7 reiterados / total completadas * 100

-- Paso 1: Calcular RGU promedio de producción (1-31 dic 2025)
WITH produccion_diciembre AS (
    SELECT 
        rut_tecnico,
        COUNT(*) FILTER (WHERE estado = 'Completado') AS total_completadas,
        SUM(total_rgu) AS total_rgu,
        CASE 
            WHEN COUNT(*) FILTER (WHERE estado = 'Completado') > 0 
            THEN ROUND(SUM(total_rgu)::NUMERIC / COUNT(*) FILTER (WHERE estado = 'Completado'), 2)
            ELSE 0 
        END AS rgu_promedio
    FROM produccion_crea
    WHERE rut_tecnico = '15342161-7'
      AND TO_DATE(fecha_trabajo, 'DD/MM/YYYY') >= '2025-12-01'
      AND TO_DATE(fecha_trabajo, 'DD/MM/YYYY') <= '2025-12-31'
    GROUP BY rut_tecnico
)
SELECT 
    '📊 Producción Diciembre 2025' AS info,
    rut_tecnico,
    total_completadas,
    total_rgu,
    rgu_promedio
FROM produccion_diciembre;

-- Paso 2: Ver calidad de Felipe Plaza para período de enero (ya calculado)
SELECT 
    '📊 Calidad Enero 2026 (21 nov - 20 dic)' AS info,
    rut_tecnico,
    tecnico,
    periodo,
    total_reiterados,
    total_completadas,
    porcentaje_reiteracion
FROM v_calidad_tecnicos
WHERE rut_tecnico = '15342161-7'
  AND periodo = '2026-01';

-- Paso 3: Calcular pago completo (ejemplo con datos hipotéticos)
-- Supongamos: RGU 5.5 y 7 reiterados (8.2% según vimos antes)
SELECT 
    '💰 CÁLCULO DE PAGO - Felipe Plaza - Enero 2026' AS titulo,
    *
FROM calcular_pago_tecnico(
    '15342161-7',   -- RUT
    '2026-01',      -- Período
    5.5,            -- RGU promedio (ejemplo)
    8.2             -- % reiteración (7 reiterados)
);

-- ═══════════════════════════════════════════════════════════════════
-- EJEMPLO 2: Calcular pagos de TODOS los técnicos para Enero 2026
-- ═══════════════════════════════════════════════════════════════════

-- Este script calcularía los pagos de todos los técnicos automáticamente
-- basándose en los datos reales de producción y calidad

DO $$
DECLARE
    v_tecnico RECORD;
    v_rgu_promedio NUMERIC;
    v_porcentaje_cal NUMERIC;
BEGIN
    -- Recorrer todos los técnicos con datos de calidad en enero 2026
    FOR v_tecnico IN 
        SELECT DISTINCT 
            rut_tecnico,
            tecnico,
            total_completadas,
            porcentaje_reiteracion
        FROM v_calidad_tecnicos
        WHERE periodo = '2026-01'
    LOOP
        -- Calcular RGU promedio (aquí necesitarías la lógica real)
        -- Por ahora usamos un valor de ejemplo: 5.5
        v_rgu_promedio := 5.5;
        
        -- Usar el porcentaje de calidad real
        v_porcentaje_cal := v_tecnico.porcentaje_reiteracion;
        
        -- Calcular y guardar pago
        PERFORM calcular_pago_tecnico(
            v_tecnico.rut_tecnico,
            '2026-01',
            v_rgu_promedio,
            v_porcentaje_cal
        );
        
        RAISE NOTICE '✅ Calculado pago para: % (RGU: %, Cal: %)', 
            v_tecnico.tecnico, v_rgu_promedio, v_porcentaje_cal;
    END LOOP;
END $$;

-- Ver resultados
SELECT 
    '📊 RESUMEN DE PAGOS ENERO 2026' AS titulo,
    COUNT(*) AS total_tecnicos,
    SUM(total_bruto) AS suma_total_bruto,
    SUM(total_liquido) AS suma_total_liquido,
    ROUND(AVG(rgu_promedio), 2) AS rgu_promedio,
    ROUND(AVG(porcentaje_reiteracion), 2) AS calidad_promedio
FROM v_pagos_tecnicos
WHERE periodo = '2026-01';

-- ═══════════════════════════════════════════════════════════════════
-- EJEMPLO 3: Consultas para DASHBOARD WEB
-- ═══════════════════════════════════════════════════════════════════

-- Vista general de pagos (montos brutos)
SELECT 
    rut_tecnico,
    tecnico,
    periodo,
    rgu_promedio,
    bono_produccion_bruto AS bono_produccion,
    porcentaje_reiteracion AS calidad_porcentaje,
    bono_calidad_bruto AS bono_calidad,
    total_bruto AS total_bonos
FROM v_pagos_tecnicos
WHERE periodo = '2026-01'
ORDER BY total_bruto DESC;

-- Top 10 técnicos mejor pagados
SELECT 
    'TOP 10 TÉCNICOS - Enero 2026' AS titulo,
    ROW_NUMBER() OVER (ORDER BY total_bruto DESC) AS posicion,
    tecnico,
    rgu_promedio,
    bono_produccion_bruto,
    porcentaje_reiteracion,
    bono_calidad_bruto,
    total_bruto
FROM v_pagos_tecnicos
WHERE periodo = '2026-01'
ORDER BY total_bruto DESC
LIMIT 10;

-- ═══════════════════════════════════════════════════════════════════
-- EJEMPLO 4: Consultas para APP MÓVIL (líquidos)
-- ═══════════════════════════════════════════════════════════════════

-- Ver mi pago (ejemplo para un técnico específico)
SELECT 
    '💰 TU PAGO - Enero 2026' AS titulo,
    rgu_promedio,
    bono_produccion_liquido AS bono_produccion,
    porcentaje_reiteracion AS calidad_porcentaje,
    bono_calidad_liquido AS bono_calidad,
    total_liquido AS total_liquido_bonos
FROM v_pagos_tecnicos
WHERE rut_tecnico = '15342161-7'
  AND periodo = '2026-01';

-- Comparación con el equipo
SELECT 
    'COMPARACIÓN CON EL EQUIPO' AS titulo,
    CASE 
        WHEN rut_tecnico = '15342161-7' THEN '👤 TÚ'
        ELSE tecnico
    END AS tecnico,
    total_liquido,
    ROW_NUMBER() OVER (ORDER BY total_liquido DESC) AS posicion
FROM v_pagos_tecnicos
WHERE periodo = '2026-01'
ORDER BY total_liquido DESC;

-- ═══════════════════════════════════════════════════════════════════
-- EJEMPLO 5: Histórico de pagos de un técnico
-- ═══════════════════════════════════════════════════════════════════

SELECT 
    'HISTÓRICO DE PAGOS - Felipe Plaza' AS titulo,
    periodo,
    rgu_promedio,
    bono_produccion_liquido,
    porcentaje_reiteracion,
    bono_calidad_liquido,
    total_liquido
FROM v_pagos_tecnicos
WHERE rut_tecnico = '15342161-7'
ORDER BY periodo DESC;

-- ═══════════════════════════════════════════════════════════════════
-- EJEMPLO 6: Estadísticas generales
-- ═══════════════════════════════════════════════════════════════════

SELECT 
    periodo,
    COUNT(*) AS total_tecnicos,
    ROUND(AVG(rgu_promedio), 2) AS rgu_promedio,
    ROUND(AVG(porcentaje_reiteracion), 2) AS calidad_promedio,
    AVG(total_liquido)::INTEGER AS pago_promedio,
    MAX(total_liquido) AS pago_maximo,
    MIN(total_liquido) AS pago_minimo
FROM v_pagos_tecnicos
GROUP BY periodo
ORDER BY periodo DESC;

-- ═══════════════════════════════════════════════════════════════════
-- 🔧 UTILIDADES
-- ═══════════════════════════════════════════════════════════════════

-- Recalcular un pago específico
SELECT * FROM calcular_pago_tecnico('15342161-7', '2026-01', 5.5, 8.2);

-- Ver detalles de la escala de producción
SELECT * FROM escala_produccion ORDER BY rgu_min;

-- Ver detalles de la escala de calidad
SELECT * FROM escala_calidad ORDER BY porcentaje_min;

-- Eliminar pagos de un período (si necesitas recalcular)
-- DELETE FROM pagos_tecnicos WHERE periodo = '2026-01';





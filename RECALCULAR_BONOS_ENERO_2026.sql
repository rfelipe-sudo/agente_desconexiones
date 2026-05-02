-- ═══════════════════════════════════════════════════════════════════
-- 🔄 RECALCULAR BONOS ENERO 2026 (después de corrección de escalas)
-- ═══════════════════════════════════════════════════════════════════
-- Este script recalcula los bonos de enero 2026 después de corregir
-- la función obtener_bono_calidad() para que use los rangos correctos
-- ═══════════════════════════════════════════════════════════════════

-- PASO 1: Verificar que la función está actualizada
SELECT 
    '✅ TEST: Función corregida' AS paso,
    7.5::NUMERIC AS porcentaje_test,
    monto_bruto AS bono_esperado_96000,
    CASE 
        WHEN monto_bruto = 96000 THEN '✅ FUNCIÓN CORREGIDA'
        WHEN monto_bruto = 180000 THEN '❌ FUNCIÓN AÚN NO CORREGIDA'
        ELSE '❓ RESULTADO INESPERADO'
    END AS estado
FROM obtener_bono_calidad(7.5);

-- PASO 2: Ver bonos actuales ANTES del recálculo
SELECT 
    '📊 ANTES del recálculo' AS paso,
    rut_tecnico,
    tecnico,
    porcentaje_reiteracion,
    bono_calidad_bruto,
    bono_calidad_liquido
FROM v_pagos_tecnicos
WHERE periodo = '2026-01'
  AND rut_tecnico = '25861660-K';

-- PASO 3: Recalcular bonos de enero 2026
-- Nota: La función usa mes de PRODUCCIÓN (diciembre 2025)
-- El bono se guarda para enero 2026
SELECT 
    '🔄 RECALCULANDO bonos...' AS paso,
    *
FROM calcular_bonos_prorrateo_simple(12, 2025);

-- PASO 4: Ver bonos actuales DESPUÉS del recálculo
SELECT 
    '📊 DESPUÉS del recálculo' AS paso,
    rut_tecnico,
    tecnico,
    porcentaje_reiteracion,
    bono_calidad_bruto,
    bono_calidad_liquido,
    CASE 
        WHEN porcentaje_reiteracion >= 7.0 AND porcentaje_reiteracion < 8.0 THEN
            CASE 
                WHEN bono_calidad_bruto = 96000 THEN '✅ CORRECTO'
                ELSE '❌ INCORRECTO (debería ser 96000)'
            END
        WHEN porcentaje_reiteracion >= 6.0 AND porcentaje_reiteracion < 7.0 THEN
            CASE 
                WHEN bono_calidad_bruto = 180000 THEN '✅ CORRECTO'
                ELSE '❌ INCORRECTO (debería ser 180000)'
            END
        ELSE 'N/A'
    END AS validacion
FROM v_pagos_tecnicos
WHERE periodo = '2026-01'
  AND rut_tecnico IN ('25861660-K')  -- Ronald Sierra (7%)
ORDER BY porcentaje_reiteracion DESC;

-- PASO 5: Ver todos los técnicos en el rango 6-8% para validar
SELECT 
    '📊 Técnicos 6-8% para validación' AS paso,
    rut_tecnico,
    tecnico,
    ROUND(porcentaje_reiteracion, 2) AS porc_reit,
    bono_calidad_bruto,
    CASE 
        WHEN porcentaje_reiteracion < 7.0 THEN '6% → $180.000'
        WHEN porcentaje_reiteracion < 8.0 THEN '7% → $96.000'
        ELSE '8% → $84.000'
    END AS bono_esperado,
    CASE 
        WHEN porcentaje_reiteracion >= 6.0 AND porcentaje_reiteracion < 7.0 
             AND bono_calidad_bruto = 180000 THEN '✅'
        WHEN porcentaje_reiteracion >= 7.0 AND porcentaje_reiteracion < 8.0 
             AND bono_calidad_bruto = 96000 THEN '✅'
        WHEN porcentaje_reiteracion >= 8.0 AND porcentaje_reiteracion < 9.0 
             AND bono_calidad_bruto = 84000 THEN '✅'
        ELSE '❌'
    END AS ok
FROM v_pagos_tecnicos
WHERE periodo = '2026-01'
  AND porcentaje_reiteracion >= 6.0 
  AND porcentaje_reiteracion < 9.0
ORDER BY porcentaje_reiteracion;

-- ═══════════════════════════════════════════════════════════════════
-- ✅ RESULTADO ESPERADO
-- ═══════════════════════════════════════════════════════════════════
/*
Ronald Sierra Peña (25861660-K):
- Porcentaje: 7.5%
- Bono bruto: $96.000 (antes $180.000)
- Bono líquido: $80.000
- Bono prorrateado (22/24 días): $88.000

Si todo está correcto, todos los técnicos en los pasos 4 y 5 
deberían tener ✅ en la columna de validación.
*/




-- ═══════════════════════════════════════════════════════════════════
-- 🧪 TEST RÁPIDO DEL SISTEMA DE BONOS
-- ═══════════════════════════════════════════════════════════════════

-- 1️⃣ Verificar que tenemos datos de producción
SELECT 
    '📊 Datos de producción' AS test,
    COUNT(*) AS total_registros,
    COUNT(DISTINCT rut_tecnico) AS total_tecnicos,
    MIN(TO_DATE(fecha_trabajo, 'DD/MM/YY')) AS fecha_min,
    MAX(TO_DATE(fecha_trabajo, 'DD/MM/YY')) AS fecha_max
FROM produccion_creaciones;

-- 2️⃣ Verificar que tenemos datos de calidad
SELECT 
    '✅ Datos de calidad' AS test,
    COUNT(*) AS total_registros,
    COUNT(DISTINCT rut_tecnico) AS total_tecnicos,
    MIN(periodo) AS periodo_min,
    MAX(periodo) AS periodo_max
FROM v_calidad_tecnicos;

-- 3️⃣ TEST: Calcular RGU de un técnico (Felipe Plaza)
-- Bono de DICIEMBRE 2025 (se paga en ENERO 2026)
SELECT 
    '🎯 RGU Felipe Plaza - Diciembre 2025' AS test,
    obtener_rgu_promedio(
        '15342161-7',  -- RUT Felipe
        '2025-12-01',  -- Inicio: 1 diciembre 2025
        '2025-12-31'   -- Fin: 31 diciembre 2025
    ) AS rgu_promedio;

-- 4️⃣ TEST: Obtener % calidad de Felipe Plaza
-- Período: 21 nov - 20 dic 2025 (en v_calidad_tecnicos se guarda como '2026-01')
SELECT 
    '✅ Calidad Felipe Plaza - 21nov-20dic (bono ene)' AS test,
    obtener_porcentaje_calidad_vista(
        '15342161-7',  -- RUT Felipe
        '2026-01'      -- Período de BONO (no de medición)
    ) AS porcentaje_calidad;

-- 5️⃣ TEST: Ver qué bonos le corresponden
-- BONO DE DICIEMBRE 2025 (se paga en ENERO 2026)
WITH rgu AS (
    SELECT obtener_rgu_promedio('15342161-7', '2025-12-01', '2025-12-31') AS valor
),
calidad AS (
    SELECT obtener_porcentaje_calidad_vista('15342161-7', '2026-01') AS valor
)
SELECT 
    '💰 Bonos Felipe - BONO DIC (pago ENE)' AS test,
    rgu.valor AS rgu_promedio,
    calidad.valor AS porcentaje_calidad,
    bp.monto_bruto AS bono_prod_bruto,
    bp.liquido_aprox AS bono_prod_liquido,
    bc.monto_bruto AS bono_cal_bruto,
    bc.liquido_aprox AS bono_cal_liquido,
    (bp.monto_bruto + bc.monto_bruto) AS total_bruto,
    (bp.liquido_aprox + bc.liquido_aprox) AS total_liquido
FROM rgu, calidad,
    LATERAL obtener_bono_produccion(rgu.valor) bp,
    LATERAL obtener_bono_calidad(calidad.valor) bc;

-- ═══════════════════════════════════════════════════════════════════
-- 🚀 EJECUTAR CÁLCULO COMPLETO
-- ═══════════════════════════════════════════════════════════════════

-- Descomentar para ejecutar:
-- SELECT * FROM calcular_bonos_diario_vistas();

-- Ver resultados:
-- SELECT * FROM v_pagos_tecnicos 
-- WHERE periodo = TO_CHAR(CURRENT_DATE + INTERVAL '1 month', 'YYYY-MM')
-- ORDER BY total_liquido DESC
-- LIMIT 10;


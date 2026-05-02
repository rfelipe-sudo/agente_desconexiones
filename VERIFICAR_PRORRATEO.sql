-- ═══════════════════════════════════════════════════════════════════
-- 🧪 VERIFICACIÓN DEL SISTEMA DE PRORRATEO
-- ═══════════════════════════════════════════════════════════════════

-- 1️⃣ Verificar que existe la tabla de marcas
SELECT 
    '1️⃣ Verificar tabla geo_marcas_diarias' AS test,
    COUNT(*) AS total_registros,
    COUNT(DISTINCT fecha) AS fechas_unicas
FROM geo_marcas_diarias;

-- 2️⃣ Ver feriados de diciembre 2025
SELECT 
    '2️⃣ Feriados Diciembre 2025' AS test,
    fecha,
    permiso
FROM geo_marcas_diarias
WHERE EXTRACT(MONTH FROM TO_DATE(fecha, 'YYYY-MM-DD')) = 12
  AND EXTRACT(YEAR FROM TO_DATE(fecha, 'YYYY-MM-DD')) = 2025
  AND LOWER(permiso) LIKE '%feriado%'
ORDER BY fecha;

-- 3️⃣ Calcular días laborales de diciembre 2025
SELECT 
    '3️⃣ Días laborales Diciembre 2025' AS test,
    calcular_dias_laborales(12, 2025) AS dias_laborales,
    'Esperado: 25 o 26 según feriados' AS nota;

-- 4️⃣ Ver días trabajados de Felipe Plaza en diciembre
SELECT 
    '4️⃣ Días trabajados Felipe Plaza (Dic)' AS test,
    calcular_dias_trabajados('15342161-7', '2025-12-01', '2025-12-31') AS dias_trabajados;

-- 5️⃣ Ver órdenes de Felipe Plaza por día en diciembre
SELECT 
    '5️⃣ Detalle órdenes Felipe Plaza' AS test,
    fecha_trabajo,
    COUNT(*) as ordenes,
    STRING_AGG(DISTINCT estado, ', ') as estados
FROM produccion_creaciones
WHERE rut_tecnico = '15342161-7'
  AND fecha_trabajo LIKE '%/12/25'
GROUP BY fecha_trabajo
ORDER BY TO_DATE(fecha_trabajo, 'DD/MM/YY');

-- 6️⃣ Calcular RGU promedio de Felipe
SELECT 
    '6️⃣ RGU Promedio Felipe Plaza' AS test,
    obtener_rgu_promedio_prorrateo('15342161-7', '2025-12-01', '2025-12-31') AS rgu_promedio,
    'Esperado: 3.4' AS nota;

-- 7️⃣ Ver bonos según escala (SIN prorrateo)
WITH datos AS (
    SELECT 
        obtener_rgu_promedio_prorrateo('15342161-7', '2025-12-01', '2025-12-31') AS rgu,
        obtener_porcentaje_calidad_prorrateo('15342161-7', '2026-01') AS calidad
)
SELECT 
    '7️⃣ Bonos según escala (SIN prorrateo)' AS test,
    d.rgu AS rgu_promedio,
    d.calidad AS porcentaje_calidad,
    bp.monto_bruto AS bono_prod_bruto,
    bp.liquido_aprox AS bono_prod_liquido,
    bc.monto_bruto AS bono_cal_bruto,
    bc.liquido_aprox AS bono_cal_liquido
FROM datos d,
    LATERAL obtener_bono_produccion(d.rgu) bp,
    LATERAL obtener_bono_calidad(d.calidad) bc;

-- 8️⃣ Calcular prorrateo de Felipe (ejemplo manual)
WITH datos AS (
    SELECT 
        calcular_dias_trabajados('15342161-7', '2025-12-01', '2025-12-31') AS dias_trabajados,
        calcular_dias_laborales(12, 2025) AS dias_laborales
),
bonos_escala AS (
    SELECT 
        obtener_rgu_promedio_prorrateo('15342161-7', '2025-12-01', '2025-12-31') AS rgu,
        obtener_porcentaje_calidad_prorrateo('15342161-7', '2026-01') AS calidad
)
SELECT 
    '8️⃣ Prorrateo Felipe Plaza' AS test,
    d.dias_trabajados,
    d.dias_laborales,
    ROUND((d.dias_trabajados::NUMERIC / d.dias_laborales::NUMERIC) * 100, 1) AS porcentaje_asistencia,
    bp.monto_bruto AS bono_prod_100,
    ROUND(bp.monto_bruto * d.dias_trabajados::NUMERIC / d.dias_laborales::NUMERIC) AS bono_prod_prorrateado,
    bc.monto_bruto AS bono_cal_100,
    ROUND(bc.monto_bruto * d.dias_trabajados::NUMERIC / d.dias_laborales::NUMERIC) AS bono_cal_prorrateado,
    ROUND((bp.monto_bruto + bc.monto_bruto) * d.dias_trabajados::NUMERIC / d.dias_laborales::NUMERIC) AS total_prorrateado
FROM datos d, bonos_escala bs,
    LATERAL obtener_bono_produccion(bs.rgu) bp,
    LATERAL obtener_bono_calidad(bs.calidad) bc;

-- ═══════════════════════════════════════════════════════════════════
-- 🚀 SI TODO ESTÁ BIEN, EJECUTAR EL CÁLCULO COMPLETO
-- ═══════════════════════════════════════════════════════════════════

-- Descomentar para ejecutar:
-- SELECT * FROM calcular_bonos_con_prorrateo();

-- Ver resultados:
-- SELECT 
--     tecnico,
--     rut_tecnico,
--     rgu_promedio,
--     porcentaje_reiteracion AS calidad_pct,
--     bono_produccion_liquido AS prod_liquido,
--     bono_calidad_liquido AS cal_liquido,
--     total_liquido
-- FROM v_pagos_tecnicos 
-- WHERE periodo = '2026-01'
-- ORDER BY total_liquido DESC
-- LIMIT 20;


-- ═══════════════════════════════════════════════════════════════════
-- 🔧 CORRECCIÓN FINAL: CEILING después de 2 decimales
-- ═══════════════════════════════════════════════════════════════════
-- 6.98% → CEILING(6.98) → 7%
-- 6.25% → CEILING(6.25) → 7%
-- 5.01% → CEILING(5.01) → 6%
-- ═══════════════════════════════════════════════════════════════════

DROP VIEW IF EXISTS v_calidad_tecnicos CASCADE;

CREATE VIEW v_calidad_tecnicos AS
WITH produccion_periodo AS (
    SELECT
        pc.rut_tecnico,
        -- Determinar el mes de medición basado en la fecha del trabajo
        CASE 
            -- Si el día es >= 21, pertenece al mes SIGUIENTE
            WHEN CAST(SPLIT_PART(pc.fecha_trabajo, '/', 1) AS INTEGER) >= 21 THEN
                CASE 
                    WHEN CAST(SPLIT_PART(pc.fecha_trabajo, '/', 2) AS INTEGER) = 12 THEN
                        -- Si es diciembre, el período es enero del año siguiente
                        TO_CHAR(
                            TO_DATE(pc.fecha_trabajo, 'DD/MM/YYYY') + INTERVAL '1 month',
                            'YYYY-MM'
                        )
                    ELSE
                        -- Para otros meses, sumar 1 mes
                        TO_CHAR(
                            TO_DATE(pc.fecha_trabajo, 'DD/MM/YYYY') + INTERVAL '1 month',
                            'YYYY-MM'
                        )
                END
            -- Si el día es < 21, pertenece al mes ACTUAL
            ELSE
                TO_CHAR(TO_DATE(pc.fecha_trabajo, 'DD/MM/YYYY'), 'YYYY-MM')
        END AS mes_medicion,
        -- Contar todas las órdenes completadas en el período de calidad
        COUNT(DISTINCT pc.orden_trabajo) AS total_completadas
    FROM produccion_crea pc
    WHERE pc.estado = 'Completado'
    GROUP BY
        pc.rut_tecnico,
        mes_medicion
),
reiterados_periodo AS (
    SELECT
        cc.rut_tecnico_original AS rut_tecnico,
        -- El mes de medición se basa en la fecha_original
        CASE 
            WHEN EXTRACT(DAY FROM cc.fecha_original) >= 21 THEN
                CASE 
                    WHEN EXTRACT(MONTH FROM cc.fecha_original) = 12 THEN
                        TO_CHAR(cc.fecha_original + INTERVAL '1 month', 'YYYY-MM')
                    ELSE
                        TO_CHAR(cc.fecha_original + INTERVAL '1 month', 'YYYY-MM')
                END
            ELSE
                TO_CHAR(cc.fecha_original, 'YYYY-MM')
        END AS mes_medicion,
        COUNT(DISTINCT cc.orden_original) AS ordenes_reiteradas
    FROM calidad_crea cc
    WHERE cc.dias_reiterado <= 30
    GROUP BY
        cc.rut_tecnico_original,
        mes_medicion
)
SELECT
    COALESCE(pp.rut_tecnico, rp.rut_tecnico) AS rut_tecnico,
    COALESCE(
        (SELECT tecnico FROM produccion_crea WHERE rut_tecnico = COALESCE(pp.rut_tecnico, rp.rut_tecnico) LIMIT 1),
        (SELECT tecnico_original FROM calidad_crea WHERE rut_tecnico_original = COALESCE(pp.rut_tecnico, rp.rut_tecnico) LIMIT 1)
    ) AS tecnico,
    COALESCE(pp.mes_medicion, rp.mes_medicion) AS periodo,
    COALESCE(rp.ordenes_reiteradas, 0) AS ordenes_reiteradas,
    COALESCE(pp.total_completadas, 0) AS total_trabajos,
    CASE 
        WHEN COALESCE(pp.total_completadas, 0) > 0 THEN
            -- CAMBIO: Calcular con 2 decimales, luego CEILING hacia arriba
            -- Paso 1: calcular porcentaje con 2 decimales (6.98)
            -- Paso 2: aplicar CEILING (7)
            CEILING(
                ROUND(
                    (COALESCE(rp.ordenes_reiteradas, 0)::NUMERIC / pp.total_completadas::NUMERIC) * 100,
                    2  -- Primero 2 decimales
                )
            )  -- Luego CEILING hacia arriba
        ELSE 0
    END AS porcentaje_reiteracion
FROM produccion_periodo pp
FULL OUTER JOIN reiterados_periodo rp 
    ON pp.rut_tecnico = rp.rut_tecnico 
    AND pp.mes_medicion = rp.mes_medicion
ORDER BY periodo DESC, porcentaje_reiteracion DESC;

-- ═══════════════════════════════════════════════════════════════════
-- RECALCULAR BONOS
-- ═══════════════════════════════════════════════════════════════════

-- Eliminar bonos de enero 2026 para forzar recálculo
DELETE FROM pagos_tecnicos WHERE periodo = '2026-01';

-- Recalcular
SELECT '🔄 Recalculando bonos...' AS paso;
SELECT * FROM calcular_bonos_prorrateo_simple(12, 2025);

-- Verificar Ronald
SELECT 
    '✅ Verificación Ronald - Enero 2026' AS paso,
    rut_tecnico,
    periodo,
    ordenes_reiteradas,
    total_trabajos,
    ROUND((ordenes_reiteradas::NUMERIC / total_trabajos::NUMERIC) * 100, 2) AS porc_con_2_decimales,
    porcentaje_reiteracion AS porc_final_ceiling
FROM v_calidad_tecnicos
WHERE rut_tecnico = '25861660-K'
  AND periodo = '2026-01';

SELECT 
    '✅ Bono Ronald - Enero 2026' AS paso,
    rut_tecnico,
    periodo,
    porcentaje_reiteracion,
    bono_calidad_bruto,
    bono_calidad_liquido,
    CASE 
        WHEN porcentaje_reiteracion = 7 AND bono_calidad_bruto = 96000 THEN '✅ CORRECTO'
        ELSE '⚠️ VERIFICAR'
    END AS validacion
FROM v_pagos_tecnicos
WHERE rut_tecnico = '25861660-K'
  AND periodo = '2026-01';

-- ═══════════════════════════════════════════════════════════════════
-- EXPLICACIÓN DEL CAMBIO
-- ═══════════════════════════════════════════════════════════════════
/*
LÓGICA APLICADA:

Enero 2026 (período calidad: 21 Dic - 20 Ene):
- Órdenes: 32
- Reiterados: 2
- Cálculo: 2 / 32 = 6.25%
- CEILING(6.25) = 7%
- Bono: 7% → tramo 7.00-7.99% → $96,000 brutos

EJEMPLOS:
- 6.98% → CEILING(6.98) → 7%
- 6.25% → CEILING(6.25) → 7%
- 6.01% → CEILING(6.01) → 7%
- 6.00% → CEILING(6.00) → 6%
- 5.99% → CEILING(5.99) → 6%
- 10.01% → CEILING(10.01) → 11%

Esta lógica SIEMPRE redondea hacia arriba si hay decimales,
favoreciendo al técnico.
*/




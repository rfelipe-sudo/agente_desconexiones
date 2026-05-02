-- ═══════════════════════════════════════════════════════════════════
-- 🔧 CORRECCIÓN: Redondear porcentaje de calidad al entero más cercano
-- ═══════════════════════════════════════════════════════════════════
-- 6.98% → 7.00% (entra en tramo 7.00-7.99% = $96,000)
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
            -- CAMBIO: ROUND() redondea al entero más cercano
            -- 6.98 → 7.00
            -- 6.49 → 6.00
            -- 7.50 → 8.00
            ROUND(
                (COALESCE(rp.ordenes_reiteradas, 0)::NUMERIC / pp.total_completadas::NUMERIC) * 100,
                0  -- 0 decimales = redondeo al entero
            )
        ELSE 0
    END AS porcentaje_reiteracion
FROM produccion_periodo pp
FULL OUTER JOIN reiterados_periodo rp 
    ON pp.rut_tecnico = rp.rut_tecnico 
    AND pp.mes_medicion = rp.mes_medicion
ORDER BY periodo DESC, porcentaje_reiteracion DESC;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN: Ronald debería tener 7% (no 6.98%)
-- ═══════════════════════════════════════════════════════════════════

SELECT 
    '✅ DESPUÉS del redondeo' AS paso,
    rut_tecnico,
    tecnico,
    periodo,
    ordenes_reiteradas,
    total_trabajos,
    porcentaje_reiteracion,
    CASE 
        WHEN porcentaje_reiteracion = 7 THEN '✅ CORRECTO (7%)'
        ELSE '❌ INCORRECTO'
    END AS validacion
FROM v_calidad_tecnicos
WHERE rut_tecnico = '25861660-K'
  AND periodo = '2026-01';

-- ═══════════════════════════════════════════════════════════════════
-- RECALCULAR BONOS
-- ═══════════════════════════════════════════════════════════════════

-- Eliminar bonos de enero 2026 para forzar recálculo
DELETE FROM pagos_tecnicos WHERE periodo = '2026-01';

-- Recalcular con el porcentaje redondeado
SELECT '🔄 Recalculando bonos con porcentaje redondeado...' AS paso;
SELECT * FROM calcular_bonos_prorrateo_simple(12, 2025);

-- Verificar el bono de Ronald
SELECT 
    '✅ RESULTADO FINAL' AS paso,
    rut_tecnico,
    tecnico,
    periodo,
    porcentaje_reiteracion,
    bono_calidad_bruto,
    bono_calidad_liquido,
    CASE 
        WHEN porcentaje_reiteracion = 7 AND bono_calidad_bruto = 96000 THEN '✅ CORRECTO'
        ELSE '❌ VERIFICAR'
    END AS validacion
FROM v_pagos_tecnicos
WHERE rut_tecnico = '25861660-K'
  AND periodo = '2026-01';

-- ═══════════════════════════════════════════════════════════════════
-- EXPLICACIÓN DEL CAMBIO
-- ═══════════════════════════════════════════════════════════════════
/*
ANTES:
- porcentaje_reiteracion: ROUND(..., 2) → 6.98
- Tramo: 6.00-6.99% → $165,600 brutos

AHORA:
- porcentaje_reiteracion: ROUND(..., 0) → 7.00
- Tramo: 7.00-7.99% → $96,000 brutos

EJEMPLOS DE REDONDEO:
- 6.49% → 6%
- 6.50% → 7%
- 6.98% → 7%
- 7.01% → 7%
- 7.50% → 8%
- 9.99% → 10%

Esto hace que el porcentaje "aproxime" al tramo más cercano,
siendo más justo para el técnico.
*/




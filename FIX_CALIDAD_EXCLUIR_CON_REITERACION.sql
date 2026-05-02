-- ═══════════════════════════════════════════════════════════════════
-- 🔧 CORRECCIÓN FINAL: Excluir órdenes que TUVIERON reiteración
-- ═══════════════════════════════════════════════════════════════════
-- La vista debe contar SOLO las órdenes que NO aparecen como orden_original
-- en calidad_crea (es decir, órdenes que NO tuvieron problemas)
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
        -- Contar SOLO órdenes que NO tienen reiteración
        COUNT(DISTINCT pc.orden_trabajo) AS total_completadas
    FROM produccion_crea pc
    WHERE pc.estado = 'Completado'
      -- Excluir órdenes que aparecen como orden_original en calidad_crea
      -- (es decir, órdenes que TUVIERON reiteración y salieron mal)
      AND NOT EXISTS (
          SELECT 1
          FROM calidad_crea cc
          WHERE cc.orden_original = pc.orden_trabajo
            AND cc.rut_tecnico_original = pc.rut_tecnico
      )
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
            ROUND(
                (COALESCE(rp.ordenes_reiteradas, 0)::NUMERIC / pp.total_completadas::NUMERIC) * 100,
                2
            )
        ELSE 0
    END AS porcentaje_reiteracion
FROM produccion_periodo pp
FULL OUTER JOIN reiterados_periodo rp 
    ON pp.rut_tecnico = rp.rut_tecnico 
    AND pp.mes_medicion = rp.mes_medicion
ORDER BY periodo DESC, porcentaje_reiteracion DESC;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN: Comprobar que Ronald ahora tiene 7.5%
-- ═══════════════════════════════════════════════════════════════════

SELECT 
    '✅ DESPUÉS de la corrección' AS paso,
    rut_tecnico,
    tecnico,
    periodo,
    ordenes_reiteradas,
    total_trabajos,
    porcentaje_reiteracion,
    CASE 
        WHEN porcentaje_reiteracion = 7.50 THEN '✅ CORRECTO'
        ELSE '❌ INCORRECTO'
    END AS validacion
FROM v_calidad_tecnicos
WHERE rut_tecnico = '25861660-K'
  AND periodo = '2026-01';

-- ═══════════════════════════════════════════════════════════════════
-- EXPLICACIÓN DE LA LÓGICA
-- ═══════════════════════════════════════════════════════════════════
/*
ANTES:
- Contaba TODAS las órdenes completadas (43)
- 3 reiteraciones / 43 órdenes = 6.98%

AHORA:
- Cuenta SOLO las órdenes que NO tuvieron reiteración (40)
- Excluye las 3 órdenes que aparecen como orden_original en calidad_crea
- 3 reiteraciones / 40 órdenes SIN problemas = 7.50%

LÓGICA:
- NOT EXISTS busca si la orden_trabajo de produccion_crea aparece
  como orden_original en calidad_crea para el mismo técnico
- Si aparece, significa que ESA orden tuvo un problema y fue reiterada
- Por lo tanto, NO debe contarse en la base de órdenes "buenas"
*/




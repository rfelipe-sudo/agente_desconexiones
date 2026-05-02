-- ═══════════════════════════════════════════════════════════════════
-- 🔍 COMPARAR: Dashboard vs SQL para técnicos con reiteraciones
-- ═══════════════════════════════════════════════════════════════════

-- Ver técnicos con reiteraciones en el período 2026-01
-- y comparar el conteo de órdenes

WITH ordenes_por_tecnico AS (
    SELECT
        rut_tecnico,
        COUNT(*) AS total_ordenes_sql,
        COUNT(*) FILTER (
            WHERE NOT EXISTS (
                SELECT 1 FROM calidad_crea cc 
                WHERE cc.orden_original = produccion_crea.orden_trabajo
                  AND cc.rut_tecnico_original = produccion_crea.rut_tecnico
            )
        ) AS ordenes_sin_reiteracion_sql,
        COUNT(*) FILTER (
            WHERE EXISTS (
                SELECT 1 FROM calidad_crea cc 
                WHERE cc.orden_original = produccion_crea.orden_trabajo
                  AND cc.rut_tecnico_original = produccion_crea.rut_tecnico
            )
        ) AS ordenes_con_reiteracion_sql
    FROM produccion_crea
    WHERE estado = 'Completado'
      AND (
          (fecha_trabajo LIKE '%/11/2025' AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) >= 21)
          OR
          (fecha_trabajo LIKE '%/12/2025' AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) <= 20)
      )
    GROUP BY rut_tecnico
),
reiterados_por_tecnico AS (
    SELECT
        rut_tecnico_original AS rut_tecnico,
        COUNT(DISTINCT orden_original) AS total_reiterados
    FROM calidad_crea
    WHERE fecha_original >= '2025-11-21'
      AND fecha_original <= '2025-12-20'
      AND dias_reiterado <= 30
    GROUP BY rut_tecnico_original
)
SELECT
    ot.rut_tecnico,
    (SELECT tecnico FROM produccion_crea WHERE rut_tecnico = ot.rut_tecnico LIMIT 1) AS tecnico,
    ot.total_ordenes_sql AS ordenes_totales,
    ot.ordenes_sin_reiteracion_sql AS ordenes_sin_reit,
    ot.ordenes_con_reiteracion_sql AS ordenes_con_reit,
    COALESCE(rt.total_reiterados, 0) AS reiterados,
    -- Cálculo ACTUAL (SQL): reiterados / total
    CASE 
        WHEN ot.total_ordenes_sql > 0 THEN
            ROUND((COALESCE(rt.total_reiterados, 0)::NUMERIC / ot.total_ordenes_sql) * 100, 2)
        ELSE 0
    END AS porc_actual_sql,
    -- Cálculo que usa el DASHBOARD: reiterados / ordenes_sin_reiteracion
    CASE 
        WHEN ot.ordenes_sin_reiteracion_sql > 0 THEN
            ROUND((COALESCE(rt.total_reiterados, 0)::NUMERIC / ot.ordenes_sin_reiteracion_sql) * 100, 2)
        ELSE 0
    END AS porc_dashboard,
    -- Diferencia
    CASE 
        WHEN ot.ordenes_sin_reiteracion_sql > 0 AND ot.total_ordenes_sql > 0 THEN
            ROUND((COALESCE(rt.total_reiterados, 0)::NUMERIC / ot.ordenes_sin_reiteracion_sql) * 100, 2) -
            ROUND((COALESCE(rt.total_reiterados, 0)::NUMERIC / ot.total_ordenes_sql) * 100, 2)
        ELSE 0
    END AS diferencia,
    CASE 
        WHEN ot.ordenes_con_reiteracion_sql > 0 THEN '⚠️ TIENE DIFERENCIA'
        ELSE '✅ COINCIDEN'
    END AS estado
FROM ordenes_por_tecnico ot
LEFT JOIN reiterados_por_tecnico rt ON rt.rut_tecnico = ot.rut_tecnico
WHERE COALESCE(rt.total_reiterados, 0) > 0  -- Solo mostrar técnicos con reiteraciones
ORDER BY ot.ordenes_con_reiteracion_sql DESC, diferencia DESC;

-- ═══════════════════════════════════════════════════════════════════
-- EXPLICACIÓN
-- ═══════════════════════════════════════════════════════════════════
/*
Esta consulta mostrará:
- Técnicos que tienen reiteraciones
- Cuántas órdenes tienen EN TOTAL
- Cuántas órdenes NO tienen reiteración
- Cuántas órdenes SÍ tienen reiteración
- % según SQL actual (reiterados / total)
- % según Dashboard (reiterados / sin_reiteracion)
- La diferencia entre ambos

Si TODOS los técnicos con reiteraciones tienen diferencia,
entonces el dashboard está usando una lógica diferente SIEMPRE.

Si SOLO Ronald tiene diferencia, hay algo especial con él.
*/




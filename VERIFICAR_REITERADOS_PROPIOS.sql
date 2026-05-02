-- ═══════════════════════════════════════════════════════════════════
-- 🔍 VERIFICAR: ¿Ronald atendió sus propias reiteraciones?
-- ═══════════════════════════════════════════════════════════════════

-- 1. Ver las 3 reiteraciones de Ronald
SELECT 
    '🔴 Las 3 reiteraciones de Ronald' AS diagnostico,
    cc.orden_original,
    cc.fecha_original,
    cc.orden_reiterada,
    cc.fecha_reiterada,
    cc.rut_tecnico_original,
    -- ¿Quién atendió la reiteración?
    (SELECT rut_tecnico FROM produccion_crea 
     WHERE orden_trabajo = cc.orden_reiterada 
     AND estado = 'Completado' LIMIT 1) AS rut_tecnico_reiteracion,
    -- ¿Es el mismo técnico?
    CASE 
        WHEN (SELECT rut_tecnico FROM produccion_crea 
              WHERE orden_trabajo = cc.orden_reiterada 
              AND estado = 'Completado' LIMIT 1) = cc.rut_tecnico_original 
        THEN '✅ MISMO TÉCNICO (doble conteo)'
        ELSE '❌ OTRO TÉCNICO'
    END AS quien_atendio_reiteracion
FROM calidad_crea cc
WHERE cc.rut_tecnico_original = '25861660-K'
  AND cc.fecha_original >= '2025-11-21'
  AND cc.fecha_original <= '2025-12-20'
  AND cc.dias_reiterado <= 30
ORDER BY cc.fecha_original;

-- 2. ¿La orden_reiterada está en las 43 órdenes de Ronald?
SELECT 
    '🔍 ¿Las reiteraciones están en las 43 órdenes?' AS diagnostico,
    cc.orden_original,
    cc.orden_reiterada,
    pc.orden_trabajo AS encontrada_en_produccion,
    pc.fecha_trabajo AS fecha_en_produccion,
    CASE 
        WHEN pc.orden_trabajo IS NOT NULL THEN '✅ SÍ ESTÁ (se cuenta 2 veces)'
        ELSE '❌ NO ESTÁ (solo cuenta 1 vez)'
    END AS duplicada
FROM calidad_crea cc
LEFT JOIN produccion_crea pc 
    ON pc.orden_trabajo = cc.orden_reiterada
    AND pc.rut_tecnico = '25861660-K'
    AND pc.estado = 'Completado'
    AND (
        (pc.fecha_trabajo LIKE '%/11/2025' AND CAST(SPLIT_PART(pc.fecha_trabajo, '/', 1) AS INTEGER) >= 21)
        OR
        (pc.fecha_trabajo LIKE '%/12/2025' AND CAST(SPLIT_PART(pc.fecha_trabajo, '/', 1) AS INTEGER) <= 20)
    )
WHERE cc.rut_tecnico_original = '25861660-K'
  AND cc.fecha_original >= '2025-11-21'
  AND cc.fecha_original <= '2025-12-20'
  AND cc.dias_reiterado <= 30
ORDER BY cc.fecha_original;

-- 3. Contar órdenes DISTINTAS de Ronald (sin duplicar reiteradas)
SELECT 
    '📊 Conteo CORRECTO: órdenes DISTINTAS' AS diagnostico,
    COUNT(DISTINCT orden_trabajo) AS total_ordenes_distintas,
    COUNT(DISTINCT orden_trabajo) FILTER (
        WHERE orden_trabajo NOT IN (
            SELECT cc.orden_reiterada
            FROM calidad_crea cc
            WHERE cc.rut_tecnico_original = '25861660-K'
              AND cc.fecha_original >= '2025-11-21'
              AND cc.fecha_original <= '2025-12-20'
              AND cc.dias_reiterado <= 30
              AND cc.orden_reiterada IS NOT NULL
        )
    ) AS ordenes_sin_duplicar_reiteradas,
    (
        SELECT COUNT(DISTINCT cc.orden_original)
        FROM calidad_crea cc
        WHERE cc.rut_tecnico_original = '25861660-K'
          AND cc.fecha_original >= '2025-11-21'
          AND cc.fecha_original <= '2025-12-20'
          AND cc.dias_reiterado <= 30
    ) AS total_reiterados
FROM produccion_crea
WHERE rut_tecnico = '25861660-K'
  AND estado = 'Completado'
  AND (
      (fecha_trabajo LIKE '%/11/2025' AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) >= 21)
      OR
      (fecha_trabajo LIKE '%/12/2025' AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) <= 20)
  );

-- ═══════════════════════════════════════════════════════════════════
-- EXPLICACIÓN DE LA LÓGICA CORRECTA
-- ═══════════════════════════════════════════════════════════════════
/*
ESCENARIO: Ronald atiende sus propias reiteraciones

ANTES:
- Orden A (25/11) → Ronald la atiende
- Orden A (05/12) → Ronald la reitera (MISMA ORDEN, aparece 2 veces)
- Total registros: 43
- Cálculo incorrecto: 3 reiterados / 43 = 6.98%

CORRECTO:
- Orden A (25/11) → Cuenta como 1 orden original
- Orden A (05/12) → NO cuenta en órdenes, pero SÍ en reiteraciones
- Total órdenes ÚNICAS (sin duplicar reiteradas): 40
- Total reiteraciones: 3
- Cálculo correcto: 3 / 40 = 7.5%

IMPLEMENTACIÓN EN SQL:
1. COUNT(DISTINCT orden_trabajo) para evitar duplicados
2. EXCLUIR las orden_reiterada del conteo base
3. ASÍ no se cuenta dos veces cuando el técnico atiende su propio reiterado
*/




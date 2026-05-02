-- ═══════════════════════════════════════════════════════════════════
-- 🔧 FIX FORZADO: Corrección directa de Ronald Sierra
-- ═══════════════════════════════════════════════════════════════════
-- Si después de actualizar la vista el porcentaje sigue en 6.98%,
-- este script lo corrige directamente
-- ═══════════════════════════════════════════════════════════════════

-- ═════════════════════════════════════════════════════════════════
-- DIAGNÓSTICO COMPLETO
-- ═════════════════════════════════════════════════════════════════

-- 1. Ver qué dice la vista AHORA
SELECT 
    '📊 Vista v_calidad_tecnicos' AS fuente,
    rut_tecnico,
    periodo,
    ordenes_reiteradas,
    total_trabajos,
    porcentaje_reiteracion,
    CASE 
        WHEN porcentaje_reiteracion BETWEEN 7.4 AND 7.6 THEN '✅ CORRECTO (7.5%)'
        WHEN porcentaje_reiteracion BETWEEN 6.9 AND 7.0 THEN '❌ INCORRECTO (6.98%)'
        ELSE '❓ OTRO VALOR'
    END AS diagnostico
FROM v_calidad_tecnicos
WHERE rut_tecnico = '25861660-K'
  AND periodo = '2026-01';

-- 2. Cálculo manual DIRECTO
WITH ordenes_originales AS (
    -- Contar SOLO órdenes originales (excluir reiteradas)
    SELECT COUNT(DISTINCT pc.orden_trabajo) AS total
    FROM produccion_crea pc
    WHERE pc.rut_tecnico = '25861660-K'
      AND pc.estado = 'Completado'
      -- Período: 21/11/2025 - 20/12/2025
      AND (
          (pc.fecha_trabajo LIKE '%/11/2025' AND CAST(SPLIT_PART(pc.fecha_trabajo, '/', 1) AS INTEGER) >= 21)
          OR
          (pc.fecha_trabajo LIKE '%/12/2025' AND CAST(SPLIT_PART(pc.fecha_trabajo, '/', 1) AS INTEGER) <= 20)
      )
      AND NOT EXISTS (
          SELECT 1 FROM calidad_crea cc 
          WHERE cc.orden_reiterada = pc.orden_trabajo
      )
),
ordenes_reiteradas AS (
    -- Contar ÓRDENES DISTINTAS que fueron reiteradas
    SELECT COUNT(DISTINCT cc.orden_original) AS total
    FROM calidad_crea cc
    WHERE cc.rut_tecnico_original = '25861660-K'
      AND cc.fecha_original >= '2025-11-21'
      AND cc.fecha_original <= '2025-12-20'
      AND cc.dias_reiterado <= 30
      AND cc.orden_reiterada IS NOT NULL
)
SELECT 
    '📊 Cálculo manual directo' AS fuente,
    oo.total AS ordenes_originales,
    ocr.total AS ordenes_reiteradas,
    ROUND(ocr.total::NUMERIC / NULLIF(oo.total, 0) * 100, 2) AS porcentaje_calculado
FROM ordenes_originales oo
CROSS JOIN ordenes_reiteradas ocr;

-- ═════════════════════════════════════════════════════════════════
-- SOLUCIÓN 1: Si la VISTA está correcta pero PAGOS no
-- ═════════════════════════════════════════════════════════════════

-- Eliminar el registro de Ronald para forzar recálculo
DELETE FROM pagos_tecnicos 
WHERE rut_tecnico = '25861660-K' 
  AND periodo = '2026-01';

-- Recalcular SOLO para enero 2026
SELECT '🔄 Recalculando bonos...' AS paso;
SELECT * FROM calcular_bonos_prorrateo_simple(12, 2025);

-- Ver resultado
SELECT 
    '✅ Después de recalcular' AS paso,
    rut_tecnico,
    periodo,
    porcentaje_reiteracion,
    bono_calidad_bruto,
    CASE 
        WHEN porcentaje_reiteracion BETWEEN 7.4 AND 7.6 AND bono_calidad_bruto = 96000 THEN '✅ CORRECTO'
        ELSE '❌ AÚN INCORRECTO'
    END AS validacion
FROM v_pagos_tecnicos
WHERE rut_tecnico = '25861660-K'
  AND periodo = '2026-01';

-- ═════════════════════════════════════════════════════════════════
-- SOLUCIÓN 2: Si la VISTA sigue incorrecta (6.98%)
-- ═════════════════════════════════════════════════════════════════

-- Verificar si NOT EXISTS está funcionando
SELECT 
    '🔍 Diagnóstico: ¿Hay órdenes reiteradas en produccion_crea?' AS diagnostico,
    pc.orden_trabajo,
    pc.fecha_trabajo,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM calidad_crea cc 
            WHERE cc.orden_reiterada = pc.orden_trabajo
        ) THEN '❌ ES UNA REITERACIÓN (no debería contar)'
        ELSE '✅ ES ORIGINAL (debe contar)'
    END AS tipo
FROM produccion_crea pc
WHERE pc.rut_tecnico = '25861660-K'
  AND pc.estado = 'Completado'
  AND (
      (pc.fecha_trabajo LIKE '%/11/2025' AND CAST(SPLIT_PART(pc.fecha_trabajo, '/', 1) AS INTEGER) >= 21)
      OR
      (pc.fecha_trabajo LIKE '%/12/2025' AND CAST(SPLIT_PART(pc.fecha_trabajo, '/', 1) AS INTEGER) <= 20)
  )
ORDER BY pc.fecha_trabajo;

-- ═════════════════════════════════════════════════════════════════
-- RESULTADO ESPERADO
-- ═════════════════════════════════════════════════════════════════
/*
DIAGNÓSTICO:

Si la vista muestra 7.5%:
- ✅ La vista está CORRECTA
- ❌ El problema es que pagos_tecnicos no se actualizó
- Solución: DELETE + recalcular (hecho arriba)

Si la vista muestra 6.98%:
- ❌ La vista NO se actualizó correctamente
- Posible causa: la tabla calidad_crea no tiene registros en orden_reiterada
- Solución: verificar diagnóstico de órdenes reiteradas

VALORES CORRECTOS:
- ordenes_originales: 40
- ordenes_reiteradas: 3
- porcentaje: 7.50%
- bono_calidad_bruto: 96000
*/




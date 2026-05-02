-- ═══════════════════════════════════════════════════════════════════
-- 🔍 VERIFICAR BONO DE RONALD SIERRA PEÑA
-- ═══════════════════════════════════════════════════════════════════
-- RUT: 25861660-K
-- 3 reiterados / 40 órdenes = 7.5%
-- Debería recibir bono de 7% ($96.000) no de 6% ($180.000)
-- ═══════════════════════════════════════════════════════════════════

-- 1. Verificar datos en v_pagos_tecnicos
SELECT 
    '1. Datos guardados en v_pagos_tecnicos' AS paso,
    rut_tecnico,
    tecnico,
    periodo,
    porcentaje_reiteracion AS porc_guardado,
    bono_calidad_bruto AS bono_bruto_guardado,
    bono_calidad_liquido AS bono_liquido_guardado
FROM v_pagos_tecnicos
WHERE rut_tecnico = '25861660-K'
ORDER BY periodo DESC
LIMIT 1;

-- 2. Probar función con diferentes valores
SELECT 
    '2. Prueba función con 7.0' AS paso,
    7.0::NUMERIC AS porcentaje_entrada,
    monto_bruto AS bono_esperado_96000,
    liquido_aprox AS liquido_esperado_80000
FROM obtener_bono_calidad(7.0);

SELECT 
    '2. Prueba función con 7.5' AS paso,
    7.5::NUMERIC AS porcentaje_entrada,
    monto_bruto AS bono_esperado_96000,
    liquido_aprox AS liquido_esperado_80000
FROM obtener_bono_calidad(7.5);

SELECT 
    '2. Prueba función con 6.99' AS paso,
    6.99::NUMERIC AS porcentaje_entrada,
    monto_bruto AS bono_esperado_180000,
    liquido_aprox AS liquido_esperado_150000
FROM obtener_bono_calidad(6.99);

-- 3. Verificar datos en escala_calidad
SELECT 
    '3. Escala de calidad (rangos 6-8%)' AS paso,
    porcentaje_min,
    porcentaje_max,
    monto_bruto,
    liquido_aprox,
    CASE 
        WHEN 7.5 >= porcentaje_min AND 7.5 <= porcentaje_max THEN '✅ 7.5% ENTRA AQUÍ'
        ELSE ''
    END AS match_7_5
FROM escala_calidad
WHERE porcentaje_min >= 6.00 AND porcentaje_max <= 8.99
ORDER BY porcentaje_min;

-- 4. Calcular porcentaje real de Ronald
SELECT 
    '4. Cálculo real de porcentaje' AS paso,
    COUNT(DISTINCT CASE WHEN orden_reiterada IS NOT NULL THEN orden_original END) AS reiterados,
    COUNT(DISTINCT orden_original) AS total_ordenes,
    ROUND(
        (COUNT(DISTINCT CASE WHEN orden_reiterada IS NOT NULL THEN orden_original END)::NUMERIC / 
         NULLIF(COUNT(DISTINCT orden_original), 0) * 100), 
        2
    ) AS porcentaje_exacto
FROM calidad_crea
WHERE rut_tecnico_original = '25861660-K'
  AND fecha_original >= '2025-11-21'
  AND fecha_original <= '2025-12-20';

-- 5. Recalcular bono manualmente
WITH datos AS (
    SELECT 
        COUNT(DISTINCT CASE WHEN orden_reiterada IS NOT NULL THEN orden_original END) AS reiterados,
        COUNT(DISTINCT orden_original) AS total_ordenes,
        (COUNT(DISTINCT CASE WHEN orden_reiterada IS NOT NULL THEN orden_original END)::NUMERIC / 
         NULLIF(COUNT(DISTINCT orden_original), 0) * 100) AS porcentaje_exacto
    FROM calidad_crea
    WHERE rut_tecnico_original = '25861660-K'
      AND fecha_original >= '2025-11-21'
      AND fecha_original <= '2025-12-20'
)
SELECT 
    '5. Bono que debería recibir' AS paso,
    d.reiterados,
    d.total_ordenes,
    d.porcentaje_exacto,
    b.monto_bruto AS bono_correcto_bruto,
    b.liquido_aprox AS bono_correcto_liquido
FROM datos d
CROSS JOIN LATERAL obtener_bono_calidad(d.porcentaje_exacto) b;

-- ═══════════════════════════════════════════════════════════════════
-- ✅ RESULTADO ESPERADO
-- ═══════════════════════════════════════════════════════════════════
/*
Si el porcentaje es 7.5%:
- Bono bruto: $96.000
- Bono líquido: $80.000

Si el porcentaje es 6.99% o menos:
- Bono bruto: $180.000
- Bono líquido: $150.000

Si está recibiendo $165.600:
- Es $180.000 × (22/24) = $165.000 (prorrateado por días trabajados)
- Significa que está usando el bono del tramo 6% incorrectamente

PARA RECALCULAR BONOS:
  SELECT * FROM calcular_bonos_prorrateo_simple(12, 2025);
  
  O ejecuta: RECALCULAR_BONOS_ENERO_2026.sql
*/


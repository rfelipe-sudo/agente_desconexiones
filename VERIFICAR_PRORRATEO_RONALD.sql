-- ═══════════════════════════════════════════════════════════════════
-- 🔍 VERIFICAR: ¿Por qué el bono de calidad de Ronald está prorrateado?
-- ═══════════════════════════════════════════════════════════════════

-- 1. Ver días trabajados de Ronald en diciembre
SELECT 
    '📅 Ronald - Días trabajados en Diciembre' AS info,
    COUNT(DISTINCT fecha_trabajo) AS dias_trabajados,
    MIN(fecha_trabajo) AS primer_dia,
    MAX(fecha_trabajo) AS ultimo_dia
FROM produccion_crea
WHERE rut_tecnico = '25861660-K'
  AND estado = 'Completado'
  AND fecha_trabajo LIKE '%/12/2025'
  AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) BETWEEN 1 AND 31;

-- 2. Calcular días laborales de diciembre
SELECT 
    '📊 Días laborales de Diciembre 2025' AS info,
    31 AS dias_del_mes,
    5 AS domingos,
    2 AS feriados,
    31 - 5 - 2 AS dias_laborales;

-- 3. Ver el bono SIN prorratear
SELECT 
    '💰 Bono de calidad para 7%' AS test,
    *
FROM obtener_bono_calidad(7.00);

-- 4. Calcular el prorrateo manual
WITH datos AS (
    SELECT 
        96000 AS bono_base,
        (SELECT COUNT(DISTINCT fecha_trabajo) FROM produccion_crea 
         WHERE rut_tecnico = '25861660-K' AND estado = 'Completado'
         AND fecha_trabajo LIKE '%/12/2025'
         AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) BETWEEN 1 AND 31) AS dias_trabajados,
        24 AS dias_laborales  -- 31 - 5 domingos - 2 feriados
)
SELECT 
    '🔍 Cálculo manual del prorrateo' AS calculo,
    bono_base,
    dias_trabajados,
    dias_laborales,
    ROUND(bono_base * dias_trabajados::NUMERIC / dias_laborales) AS bono_prorrateado,
    88320 AS bono_actual_en_tabla,
    CASE 
        WHEN ROUND(bono_base * dias_trabajados::NUMERIC / dias_laborales) = 88320 
        THEN '✅ COINCIDE (está prorrateando)'
        ELSE '❌ NO COINCIDE'
    END AS validacion
FROM datos;

-- 5. Ver el registro completo en pagos_tecnicos
SELECT 
    '📋 Ronald en pagos_tecnicos' AS info,
    *
FROM pagos_tecnicos
WHERE rut_tecnico = '25861660-K'
  AND periodo = '2026-01';

-- 6. Ver la función calcular_bonos_prorrateo_simple
SELECT 
    '📜 Ver código de calcular_bonos_prorrateo_simple' AS info,
    prosrc
FROM pg_proc
WHERE proname = 'calcular_bonos_prorrateo_simple';

-- ═══════════════════════════════════════════════════════════════════
-- EXPLICACIÓN
-- ═══════════════════════════════════════════════════════════════════
/*
SOSPECHA:
La función calcular_bonos_prorrateo_simple está prorrateando AMBOS bonos
(producción Y calidad), cuando solo debería prorratear producción.

BONOS:
- Producción: SE PRORRATEO por días trabajados
- Calidad: NO SE PRORRATEO (es un bono fijo según el %)

Si el resultado 4 muestra que $88,320 coincide con el prorrateo,
entonces la función está aplicando prorrateo al bono de calidad
cuando no debería.
*/




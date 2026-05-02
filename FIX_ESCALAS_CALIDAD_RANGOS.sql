-- ═══════════════════════════════════════════════════════════════════
-- 🔧 FIX: Corrección de rangos en escala_calidad
-- ═══════════════════════════════════════════════════════════════════
-- PROBLEMA: Los rangos están usando valores inclusive en ambos extremos
-- Esto causa que algunos porcentajes caigan en el rango incorrecto
--
-- EJEMPLO: 7.0% puede caer en el rango 6.00-6.99 si el límite superior
-- incluye hasta 6.999999... debido a precisión decimal
-- ═══════════════════════════════════════════════════════════════════

-- VER PROBLEMA ACTUAL
SELECT 
    'PROBLEMA: Rangos actuales' AS info,
    porcentaje_min,
    porcentaje_max,
    monto_bruto,
    CASE 
        WHEN 7.0 >= porcentaje_min AND 7.0 <= porcentaje_max THEN '✅ 7.0% cae aquí'
        WHEN 7.5 >= porcentaje_min AND 7.5 <= porcentaje_max THEN '✅ 7.5% cae aquí'
        ELSE ''
    END AS match_check
FROM escala_calidad
WHERE porcentaje_min >= 6.00 AND porcentaje_max <= 8.99
ORDER BY porcentaje_min;

-- ═══════════════════════════════════════════════════════════════════
-- SOLUCIÓN: Cambiar comparación en función obtener_bono_calidad
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION obtener_bono_calidad(
    p_porcentaje NUMERIC
)
RETURNS TABLE (
    monto_bruto INTEGER,
    liquido_aprox INTEGER
) AS $$
DECLARE
    v_monto_bruto INTEGER;
    v_liquido_aprox INTEGER;
BEGIN
    -- IMPORTANTE: Usar > en porcentaje_max para evitar solapamiento
    -- Ejemplo: 
    --   - Rango 6%: 6.00 <= X < 7.00 (incluye 6.0, 6.5, 6.99)
    --   - Rango 7%: 7.00 <= X < 8.00 (incluye 7.0, 7.5, 7.99)
    
    SELECT 
        e.monto_bruto,
        e.liquido_aprox
    INTO v_monto_bruto, v_liquido_aprox
    FROM escala_calidad e
    WHERE p_porcentaje >= e.porcentaje_min 
      AND p_porcentaje < e.porcentaje_max + 1  -- +1 para incluir el último dígito del rango
    ORDER BY e.porcentaje_min DESC
    LIMIT 1;
    
    -- Si no encuentra, retornar 0 (más de 11%)
    IF v_monto_bruto IS NULL THEN
        v_monto_bruto := 0;
        v_liquido_aprox := 0;
    END IF;
    
    RETURN QUERY SELECT v_monto_bruto, v_liquido_aprox;
END;
$$ LANGUAGE plpgsql;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICAR CORRECCIÓN
-- ═══════════════════════════════════════════════════════════════════

-- TEST 1: Límites inferiores de cada rango
SELECT 
    'TEST 1: Límite inferior 6.0%' AS test,
    6.0 AS porcentaje,
    monto_bruto AS bono_esperado_180000,
    liquido_aprox AS liquido_esperado_150000
FROM obtener_bono_calidad(6.0);

SELECT 
    'TEST 1: Límite inferior 7.0%' AS test,
    7.0 AS porcentaje,
    monto_bruto AS bono_esperado_96000,
    liquido_aprox AS liquido_esperado_80000
FROM obtener_bono_calidad(7.0);

-- TEST 2: Valores intermedios
SELECT 
    'TEST 2: Intermedio 6.5%' AS test,
    6.5 AS porcentaje,
    monto_bruto AS bono_esperado_180000,
    liquido_aprox AS liquido_esperado_150000
FROM obtener_bono_calidad(6.5);

SELECT 
    'TEST 2: Intermedio 7.5%' AS test,
    7.5 AS porcentaje,
    monto_bruto AS bono_esperado_96000,
    liquido_aprox AS liquido_esperado_80000
FROM obtener_bono_calidad(7.5);

-- TEST 3: Límites superiores
SELECT 
    'TEST 3: Límite superior 6.99%' AS test,
    6.99 AS porcentaje,
    monto_bruto AS bono_esperado_180000,
    liquido_aprox AS liquido_esperado_150000
FROM obtener_bono_calidad(6.99);

SELECT 
    'TEST 3: Límite superior 7.99%' AS test,
    7.99 AS porcentaje,
    monto_bruto AS bono_esperado_96000,
    liquido_aprox AS liquido_esperado_80000
FROM obtener_bono_calidad(7.99);

-- TEST 4: Caso específico Ronald Sierra (7.5%)
SELECT 
    'TEST 4: Ronald Sierra 7.5%' AS test,
    7.5 AS porcentaje,
    monto_bruto AS bono_correcto,
    liquido_aprox AS liquido_correcto,
    CASE 
        WHEN monto_bruto = 96000 THEN '✅ CORRECTO'
        WHEN monto_bruto = 180000 THEN '❌ ERROR (usando tramo 6%)'
        ELSE '❓ DESCONOCIDO'
    END AS estado
FROM obtener_bono_calidad(7.5);

-- ═══════════════════════════════════════════════════════════════════
-- RECALCULAR BONOS DESPUÉS DE CORRECCIÓN
-- ═══════════════════════════════════════════════════════════════════

/*
DESPUÉS DE EJECUTAR ESTE SCRIPT:

1. Ejecuta para recalcular bonos de enero 2026 (producción diciembre 2025):
   SELECT * FROM calcular_bonos_prorrateo_simple(12, 2025);

   O ejecuta el script completo:
   RECALCULAR_BONOS_ENERO_2026.sql

2. Verifica el bono de Ronald:
   SELECT 
       rut_tecnico,
       tecnico,
       porcentaje_reiteracion,
       bono_calidad_bruto,
       bono_calidad_liquido
   FROM v_pagos_tecnicos
   WHERE rut_tecnico = '25861660-K'
     AND periodo = '2026-01';

RESULTADO ESPERADO:
- porcentaje_reiteracion: 7.5 (o similar)
- bono_calidad_bruto: 96000
- bono_calidad_liquido: 80000
- Bono prorrateado por 22 días: 96000 × (22/24) = 88000
*/


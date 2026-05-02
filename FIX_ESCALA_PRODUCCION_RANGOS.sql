-- ═══════════════════════════════════════════════════════════════════
-- 🔧 CORRECCIÓN: Escala de producción con RANGOS en lugar de valores exactos
-- ═══════════════════════════════════════════════════════════════════

-- Eliminar la escala actual
TRUNCATE TABLE escala_produccion;

-- Insertar la escala con RANGOS correctos
INSERT INTO escala_produccion (rgu_min, rgu_max, monto_bruto, mano_obra, liquido_aprox) VALUES
(5.00, 5.09, 240000, 55385, 246154),
(5.10, 5.19, 270000, 62308, 276923),
(5.20, 5.29, 290000, 66923, 297436),
(5.30, 5.39, 310000, 71538, 317949),
(5.40, 5.49, 330000, 76154, 338462),
(5.50, 5.59, 350000, 80769, 358974),
(5.60, 5.69, 370000, 85385, 379487),
(5.70, 5.79, 390000, 90000, 400000),
(5.80, 5.89, 410000, 94615, 420513),
(5.90, 5.99, 430000, 99231, 441026),
(6.00, 999.99, 450000, 103846, 461538);  -- Todo >= 6.0 tiene el bono máximo

-- Verificar que ahora funcione
SELECT 
    '✅ Verificación: Escala corregida' AS test,
    rgu_min,
    rgu_max,
    monto_bruto,
    CASE 
        WHEN 6.21 >= rgu_min AND 6.21 <= rgu_max THEN '✅ 6.21 ENTRA AQUÍ'
        ELSE '❌ No'
    END AS entra_6_21
FROM escala_produccion
ORDER BY rgu_min;

-- Test con varios valores
SELECT 
    '🧪 Test después de la corrección' AS test,
    rgu_test AS rgu,
    (SELECT monto_bruto FROM obtener_bono_produccion(rgu_test)) AS bono_bruto
FROM (VALUES 
    (4.99),
    (5.00),
    (5.50),
    (6.00),
    (6.21),
    (6.50),
    (7.00),
    (10.00)
) AS tests(rgu_test);

-- Recalcular bonos
DELETE FROM pagos_tecnicos WHERE periodo = '2026-01';
SELECT '🔄 Recalculando bonos...' AS paso;
SELECT * FROM calcular_bonos_prorrateo_simple(12, 2025);

-- Verificar Francisco y Ronald
SELECT 
    '✅ Resultado final' AS paso,
    rut_tecnico,
    CASE 
        WHEN rut_tecnico = '15848521-4' THEN 'Francisco Morales'
        WHEN rut_tecnico = '25861660-K' THEN 'Ronald Sierra'
        ELSE tecnico
    END AS nombre,
    rgu_promedio,
    porcentaje_reiteracion,
    bono_produccion_bruto,
    bono_calidad_bruto,
    total_bruto
FROM v_pagos_tecnicos
WHERE periodo = '2026-01'
  AND (rut_tecnico = '15848521-4' OR rut_tecnico = '25861660-K')
ORDER BY rut_tecnico;

-- ═══════════════════════════════════════════════════════════════════
-- EXPLICACIÓN
-- ═══════════════════════════════════════════════════════════════════
/*
ANTES (INCORRECTO):
- 6.00 a 6.00 (solo acepta exactamente 6.00)
- 6.21 → NO cae en ningún rango → $0

AHORA (CORRECTO):
- 6.00 a 999.99 (todo >= 6.0)
- 6.21 → cae en 6.00-999.99 → $450,000

RESULTADOS ESPERADOS:
- Francisco: RGU 6.21 → $450,000 bruto producción
- Ronald: 7% calidad → $96,000 bruto calidad
*/




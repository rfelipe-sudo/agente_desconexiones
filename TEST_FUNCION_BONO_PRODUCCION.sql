-- ═══════════════════════════════════════════════════════════════════
-- 🔍 TEST: ¿Por qué obtener_bono_produccion(6.21) devuelve $0?
-- ═══════════════════════════════════════════════════════════════════

-- 1. Test con diferentes valores de RGU
SELECT 
    '🧪 Test función bono producción' AS test,
    rgu_test AS rgu,
    (SELECT monto_bruto FROM obtener_bono_produccion(rgu_test)) AS bono_bruto,
    (SELECT liquido_aprox FROM obtener_bono_produccion(rgu_test)) AS bono_liquido
FROM (VALUES 
    (4.5),
    (5.0),
    (5.5),
    (6.0),
    (6.21),
    (6.5),
    (7.0)
) AS tests(rgu_test);

-- 2. Ver la tabla escala_produccion
SELECT 
    '📊 Escala de producción' AS info,
    *
FROM escala_produccion
ORDER BY rgu_min;

-- 3. Ver si hay un problema con los rangos
SELECT 
    '🔍 Diagnóstico: ¿6.21 cae en algún rango?' AS diagnostico,
    rgu_min,
    rgu_max,
    monto_bruto,
    CASE 
        WHEN 6.21 >= rgu_min AND 6.21 <= rgu_max THEN '✅ 6.21 ENTRA AQUÍ'
        ELSE '❌ No'
    END AS entra_6_21
FROM escala_produccion
ORDER BY rgu_min;

-- 4. Revisar la lógica de la función obtener_bono_produccion
-- (mostrar el código de la función)
SELECT 
    '📜 Definición de la función' AS info,
    prosrc AS codigo_funcion
FROM pg_proc
WHERE proname = 'obtener_bono_produccion';




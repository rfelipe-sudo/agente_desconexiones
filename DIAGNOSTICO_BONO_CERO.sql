-- ═══════════════════════════════════════════════════════════════════
-- 🔍 DIAGNÓSTICO: ¿Por qué RGU 6.21 tiene bono $0?
-- ═══════════════════════════════════════════════════════════════════

-- 1️⃣ Ver la definición de la función obtener_bono_produccion
SELECT pg_get_functiondef(oid)
FROM pg_proc
WHERE proname = 'obtener_bono_produccion';

-- 2️⃣ Probar la función directamente con RGU 6.21
SELECT * FROM obtener_bono_produccion(6.21);

-- 3️⃣ Probar con RGU 6.0 exacto
SELECT * FROM obtener_bono_produccion(6.0);

-- 4️⃣ Probar con RGU 5.6
SELECT * FROM obtener_bono_produccion(5.6);

-- 5️⃣ Ver días trabajados del técnico 15848521-4
SELECT 
    '📊 Días trabajados técnico 15848521-4' AS test,
    calcular_dias_trabajados_simple('15848521-4', 12, 2025) AS dias_trabajados,
    25 AS dias_laborales,
    ROUND(calcular_dias_trabajados_simple('15848521-4', 12, 2025)::NUMERIC / 25, 4) AS factor_prorrateo;

-- 6️⃣ Ver RGU del técnico
SELECT 
    '🎯 RGU técnico 15848521-4' AS test,
    obtener_rgu_promedio_simple('15848521-4', 12, 2025) AS rgu_promedio;





-- ═══════════════════════════════════════════════════════════════════
-- 🔍 DIAGNOSTICAR: ¿Por qué se perdieron los bonos?
-- ═══════════════════════════════════════════════════════════════════

-- 1. Verificar Ronald Sierra - Calidad
SELECT 
    '🔍 Ronald Sierra - Vista Calidad' AS diagnostico,
    *
FROM v_calidad_tecnicos
WHERE rut_tecnico = '25861660-K'
  AND periodo = '2026-01';

-- 2. Verificar Ronald Sierra - Bonos
SELECT 
    '🔍 Ronald Sierra - Tabla Pagos' AS diagnostico,
    *
FROM pagos_tecnicos
WHERE rut_tecnico = '25861660-K'
  AND periodo = '2026-01';

-- 3. Verificar Francisco Morales - RGU
SELECT 
    '🔍 Francisco Morales - Producción Diciembre' AS diagnostico,
    COUNT(*) AS ordenes,
    SUM(rgu_total) AS rgu_total,
    AVG(rgu_total) AS rgu_promedio
FROM produccion_crea
WHERE rut_tecnico = '15848521-4'
  AND estado = 'Completado'
  AND fecha_trabajo LIKE '%/12/2025'
  AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) BETWEEN 1 AND 31;

-- 4. Verificar Francisco Morales - Bonos
SELECT 
    '🔍 Francisco Morales - Tabla Pagos' AS diagnostico,
    *
FROM pagos_tecnicos
WHERE rut_tecnico = '15848521-4'
  AND periodo = '2026-01';

--


-- 6. Ver registros con problemas
SELECT 
    '⚠️ Técnicos con bonos en 0' AS diagnostico,
    rut_tecnico,
    tecnico,
    rgu_promedio,
    porcentaje_reiteracion,
    bono_produccion_bruto,
    bono_produccion_liquido,
    bono_calidad_bruto,
    bono_calidad_liquido
FROM pagos_tecnicos
WHERE periodo = '2026-01'
  AND (rut_tecnico = '25861660-K' OR rut_tecnico = '15848521-4')
ORDER BY tecnico;

-- 7. Verificar si la función de cálculo tiene un error
SELECT 
    '🔍 Test función obtener_bono_calidad(7)' AS diagnostico,
    *
FROM obtener_bono_calidad(7.00);

SELECT 
    '🔍 Test función obtener_bono_produccion(2.3)' AS diagnostico,
    *
FROM obtener_bono_produccion(2.30);

-- 8. Ver la vista v_pagos_tecnicos
SELECT 
    '📊 Vista v_pagos_tecnicos - Ronald y Francisco' AS diagnostico,
    rut_tecnico,
    tecnico,
    periodo,
    porcentaje_reiteracion,
    bono_calidad_bruto,
    bono_produccion_bruto
FROM v_pagos_tecnicos
WHERE periodo = '2026-01'
  AND (rut_tecnico = '25861660-K' OR rut_tecnico = '15848521-4')
ORDER BY tecnico;

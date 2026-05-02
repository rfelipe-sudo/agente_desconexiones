-- ═══════════════════════════════════════════════════════════════════
-- 🔧 CALCULAR BONOS: Enero 2026 (se paga en Febrero 2026)
-- ═══════════════════════════════════════════════════════════════════

-- 1. Verificar si ya existen bonos para febrero 2026
SELECT 
    '🔍 Bonos existentes para Febrero 2026' AS info,
    COUNT(*) AS cantidad
FROM pagos_tecnicos
WHERE periodo = '2026-02';

-- 2. Si existen, eliminarlos para recalcular
DELETE FROM pagos_tecnicos WHERE periodo = '2026-02';

-- 3. Calcular bonos de ENERO 2026 (se pagan en FEBRERO 2026)
-- La función recibe: mes de producción (1 = enero), año (2026)
SELECT '🔄 Calculando bonos de Enero 2026...' AS paso;
SELECT * FROM calcular_bonos_prorrateo_simple(1, 2026);

-- 4. Verificar cuántos bonos se calcularon
SELECT 
    '✅ Bonos calculados para Febrero 2026' AS resultado,
    COUNT(*) AS total_tecnicos,
    COUNT(*) FILTER (WHERE bono_produccion_bruto > 0) AS con_bono_produccion,
    COUNT(*) FILTER (WHERE bono_calidad_bruto > 0) AS con_bono_calidad,
    SUM(total_bruto) AS total_bruto_general
FROM pagos_tecnicos
WHERE periodo = '2026-02';

-- 5. Ver algunos ejemplos
SELECT 
    '📊 Ejemplos de bonos - Febrero 2026' AS info,
    rut_tecnico,
    tecnico,
    rgu_promedio,
    porcentaje_reiteracion,
    bono_produccion_bruto,
    bono_calidad_bruto,
    total_bruto
FROM v_pagos_tecnicos
WHERE periodo = '2026-02'
ORDER BY total_bruto DESC
LIMIT 10;

-- ═══════════════════════════════════════════════════════════════════
-- EXPLICACIÓN
-- ═══════════════════════════════════════════════════════════════════
/*
PERÍODOS:

DICIEMBRE 2025:
- Producción: 1-31 Diciembre 2025
- Calidad: 21 Nov - 20 Dic 2025
- Se paga en: Enero 2026 (periodo = '2026-01')
- Función: calcular_bonos_prorrateo_simple(12, 2025)

ENERO 2026:
- Producción: 1-31 Enero 2026
- Calidad: 21 Dic 2025 - 20 Ene 2026
- Se paga en: Febrero 2026 (periodo = '2026-02')
- Función: calcular_bonos_prorrateo_simple(1, 2026)

FEBRERO 2026:
- Producción: 1-28 Febrero 2026
- Calidad: 21 Ene - 20 Feb 2026
- Se paga en: Marzo 2026 (periodo = '2026-03')
- Función: calcular_bonos_prorrateo_simple(2, 2026)
*/




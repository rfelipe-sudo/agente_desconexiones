-- ═══════════════════════════════════════════════════════════════════
-- 🔧 CORRECCIÓN: Bono Calidad 4% debe ser $240.000 brutos
-- ═══════════════════════════════════════════════════════════════════
-- El rango 4.00-4.99% tenía $200.000 pero debe ser $240.000
-- Objetivo: ≤5% de reiteración = $240.000 brutos
-- ═══════════════════════════════════════════════════════════════════

-- Actualizar el rango 4.00-4.99%
UPDATE escala_calidad
SET monto_bruto = 240000
WHERE porcentaje_min = 4.00 
  AND porcentaje_max = 4.99;

-- Verificar la corrección
SELECT 
    'Escala de Calidad - Rangos de Objetivo (≤5%)' AS categoria,
    porcentaje_min || ' - ' || porcentaje_max || '%' AS rango,
    monto_bruto AS bruto,
    liquido_aprox AS liquido,
    CASE 
        WHEN monto_bruto = 240000 THEN '✅ CORRECTO'
        ELSE '❌ ERROR'
    END AS estado
FROM escala_calidad
WHERE porcentaje_max <= 5.99
ORDER BY porcentaje_min;

-- Verificar toda la tabla
SELECT 
    'Tabla completa de Calidad' AS info,
    porcentaje_min || ' - ' || porcentaje_max || '%' AS rango,
    '$' || monto_bruto AS bruto,
    '$' || liquido_aprox AS liquido
FROM escala_calidad
ORDER BY porcentaje_min;

-- ═══════════════════════════════════════════════════════════════════
-- ✅ RESULTADO ESPERADO
-- ═══════════════════════════════════════════════════════════════════
/*
ESCALA CORRECTA:
- 0.00 - 0.99%:   $240.000 bruto / $200.000 líquido ✅
- 1.00 - 1.99%:   $240.000 bruto / $200.000 líquido ✅
- 2.00 - 2.99%:   $240.000 bruto / $200.000 líquido ✅
- 3.00 - 3.99%:   $240.000 bruto / $200.000 líquido ✅
- 4.00 - 4.99%:   $240.000 bruto / $200.000 líquido ✅ (CORREGIDO)
- 5.00 - 5.99%:   $240.000 bruto / $200.000 líquido ✅
- 6.00 - 6.99%:   $180.000 bruto / $150.000 líquido
- 7.00 - 7.99%:   $96.000  bruto / $80.000  líquido
- 8.00 - 8.99%:   $84.000  bruto / $70.000  líquido
- 9.00 - 9.99%:   $72.000  bruto / $60.000  líquido
- 10.00 - 10.99%: $60.000  bruto / $50.000  líquido
- 11.00 - 100%:   $0       bruto / $0       líquido
*/




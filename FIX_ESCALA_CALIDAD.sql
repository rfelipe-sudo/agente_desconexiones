-- ═══════════════════════════════════════════════════════════════════
-- 🔧 CORRECCIÓN: Escala de calidad
-- ═══════════════════════════════════════════════════════════════════
-- 10.00% - 10.99% = $60,000 / $50,000
-- 11.00% o más = $0 (SIN BONO)
-- ═══════════════════════════════════════════════════════════════════

-- 1. Actualizar el tramo 10.00-100.00 para que sea solo 10.00-10.99
UPDATE escala_calidad 
SET porcentaje_max = 10.99,
    monto_bruto = 60000,
    liquido_aprox = 50000
WHERE porcentaje_min = 10.00;

-- 2. Agregar tramo para 11.00% o más (SIN BONO)
INSERT INTO escala_calidad (porcentaje_min, porcentaje_max, monto_bruto, liquido_aprox)
VALUES (11.00, 100.00, 0, 0)
ON CONFLICT (porcentaje_min, porcentaje_max) DO NOTHING;

-- 3. Verificar la escala completa
SELECT 
    porcentaje_min || '% - ' || porcentaje_max || '%' AS rango,
    '$' || monto_bruto AS bruto,
    '$' || liquido_aprox AS liquido
FROM escala_calidad 
ORDER BY porcentaje_min;


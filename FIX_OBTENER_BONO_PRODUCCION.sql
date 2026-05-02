-- ═══════════════════════════════════════════════════════════════════
-- 🔧 CORREGIR: obtener_bono_produccion
-- ═══════════════════════════════════════════════════════════════════
-- Problema: IF NOT FOUND no funciona bien después de RETURN QUERY
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION obtener_bono_produccion(p_rgu_promedio NUMERIC)
RETURNS TABLE(monto_bruto INTEGER, liquido_aprox INTEGER) AS $$
DECLARE
    v_count INTEGER;
BEGIN
    -- Truncar a 1 decimal (no redondear)
    -- Ejemplo: 5.56 → 5.5, 5.49 → 5.4
    p_rgu_promedio := TRUNC(p_rgu_promedio, 1);
    
    -- Verificar si existe un registro
    SELECT COUNT(*) INTO v_count
    FROM escala_produccion e
    WHERE p_rgu_promedio >= e.rgu_min 
      AND p_rgu_promedio <= e.rgu_max;
    
    -- Si existe, retornar el bono
    IF v_count > 0 THEN
        RETURN QUERY
        SELECT 
            e.monto_bruto,
            e.liquido_aprox
        FROM escala_produccion e
        WHERE p_rgu_promedio >= e.rgu_min 
          AND p_rgu_promedio <= e.rgu_max
        LIMIT 1;
    ELSE
        -- Si no existe, retornar 0
        RETURN QUERY SELECT 0::INTEGER, 0::INTEGER;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ═══════════════════════════════════════════════════════════════════
-- 🧪 TESTS
-- ═══════════════════════════════════════════════════════════════════

-- Test 1: RGU bajo (debería ser $0)
SELECT 'Test 1: RGU 4.5' AS test, * FROM obtener_bono_produccion(4.5);

-- Test 2: RGU mínimo (5.0)
SELECT 'Test 2: RGU 5.0' AS test, * FROM obtener_bono_produccion(5.0);

-- Test 3: RGU medio (5.6)
SELECT 'Test 3: RGU 5.6' AS test, * FROM obtener_bono_produccion(5.6);

-- Test 4: RGU alto (6.0)
SELECT 'Test 4: RGU 6.0' AS test, * FROM obtener_bono_produccion(6.0);

-- Test 5: RGU muy alto (6.21 - truncado a 6.2)
SELECT 'Test 5: RGU 6.21' AS test, * FROM obtener_bono_produccion(6.21);

-- Test 6: RGU muy alto (7.5 - truncado a 7.5, debería dar bono máximo)
SELECT 'Test 6: RGU 7.5' AS test, * FROM obtener_bono_produccion(7.5);





-- ═══════════════════════════════════════════════════════════════════
-- 🎁 CORRECCIÓN: Incluir RGU compensados en el cálculo de bonos
-- ═══════════════════════════════════════════════════════════════════
-- Problema: La función obtener_rgu_promedio_simple calcula el RGU
-- sin incluir las compensaciones de la tabla rgu_adicionales
-- Solución: Modificar la función para sumar RGU base + compensaciones
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION obtener_rgu_promedio_simple(
    p_rut_tecnico VARCHAR,
    p_mes INTEGER,
    p_anio INTEGER
)
RETURNS NUMERIC AS $$
DECLARE
    v_rgu_base NUMERIC;
    v_rgu_compensado NUMERIC;
    v_rgu_total NUMERIC;
    v_dias_trabajados INTEGER;
    v_rgu_promedio NUMERIC;
    v_mes_formato VARCHAR;
BEGIN
    -- Formato del mes para buscar en rgu_adicionales: 'YYYY-MM'
    v_mes_formato := p_anio || '-' || LPAD(p_mes::TEXT, 2, '0');
    
    -- 1. Calcular RGU base de órdenes completadas
    SELECT COALESCE(SUM(rgu_total), 0)
    INTO v_rgu_base
    FROM produccion_crea
    WHERE rut_tecnico = p_rut_tecnico
      AND fecha_trabajo LIKE '%/' || p_mes::TEXT || '/' || p_anio::TEXT
      AND estado = 'Completado';
    
    -- 2. Calcular RGU compensado (suma de rgu_adicional)
    SELECT COALESCE(SUM(rgu_adicional), 0)
    INTO v_rgu_compensado
    FROM rgu_adicionales
    WHERE rut_tecnico = p_rut_tecnico
      AND mes = v_mes_formato;
    
    -- 3. Calcular RGU total (base + compensado)
    v_rgu_total := v_rgu_base + v_rgu_compensado;
    
    -- 4. Calcular días trabajados (con cualquier actividad)
    v_dias_trabajados := calcular_dias_trabajados_simple(p_rut_tecnico, p_mes, p_anio);
    
    -- 5. Calcular promedio: RGU total / días trabajados
    IF v_dias_trabajados > 0 THEN
        v_rgu_promedio := ROUND(v_rgu_total / v_dias_trabajados, 2);
    ELSE
        v_rgu_promedio := 0;
    END IF;
    
    -- Log para debugging (opcional)
    RAISE NOTICE '  💰 % - Base: %, Compensado: %, Total: %, Días: %, Prom: %',
        p_rut_tecnico,
        ROUND(v_rgu_base, 2),
        ROUND(v_rgu_compensado, 2),
        ROUND(v_rgu_total, 2),
        v_dias_trabajados,
        v_rgu_promedio;
      
    RETURN v_rgu_promedio;
END;
$$ LANGUAGE plpgsql;

-- ═══════════════════════════════════════════════════════════════════
-- ✅ VERIFICACIÓN
-- ═══════════════════════════════════════════════════════════════════

SELECT '✅ Función corregida - ahora incluye RGU compensados' AS estado;

-- ═══════════════════════════════════════════════════════════════════
-- 🧪 TEST: Verificar un técnico con compensaciones
-- ═══════════════════════════════════════════════════════════════════

-- 1. Ver compensaciones de diciembre 2025
SELECT 
    '📊 Compensaciones Diciembre 2025' AS info,
    rut_tecnico,
    COUNT(*) AS cantidad_compensaciones,
    SUM(rgu_adicional) AS total_compensado
FROM rgu_adicionales
WHERE mes = '2025-12'
GROUP BY rut_tecnico
ORDER BY total_compensado DESC
LIMIT 5;

-- 2. Comparar RGU antes y después
-- (Ejecutar test con un técnico específico que tenga compensaciones)

-- ═══════════════════════════════════════════════════════════════════
-- 🚀 RECALCULAR BONOS
-- ═══════════════════════════════════════════════════════════════════

-- INSTRUCCIONES:
-- 1. Ejecuta este script para actualizar la función
-- 2. Luego ejecuta el recálculo de bonos:

SELECT '⚠️ SIGUIENTE PASO: Ejecutar recálculo de bonos' AS instruccion;
SELECT '   SELECT * FROM calcular_bonos_prorrateo_simple(12, 2025);' AS comando_diciembre;
SELECT '   SELECT * FROM calcular_bonos_prorrateo_simple(1, 2026);' AS comando_enero;


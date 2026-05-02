-- ═══════════════════════════════════════════════════════════════════
-- 🎯 CÁLCULO SIMPLE DE BONOS - Usando datos ya calculados
-- ═══════════════════════════════════════════════════════════════════
-- Cruza datos de vistas existentes con escalas de pagos
-- Mucho más simple y eficiente
-- ═══════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════
-- FUNCIÓN: Calcular bonos usando datos ya calculados
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION calcular_bonos_desde_vistas()
RETURNS TABLE (
    tecnicos_procesados INTEGER,
    periodo_calculado VARCHAR,
    mensaje TEXT
) AS $$
DECLARE
    v_periodo_bono VARCHAR;
    v_contador INTEGER := 0;
    v_tecnico RECORD;
    v_rgu_promedio NUMERIC;
    v_porcentaje_cal NUMERIC;
BEGIN
    -- Calcular período de bono (mes siguiente)
    v_periodo_bono := TO_CHAR(CURRENT_DATE + INTERVAL '1 month', 'YYYY-MM');
    
    RAISE NOTICE '═══════════════════════════════════════════════════════';
    RAISE NOTICE '🤖 CALCULANDO BONOS DESDE VISTAS EXISTENTES';
    RAISE NOTICE '📊 Período de bono: %', v_periodo_bono;
    RAISE NOTICE '═══════════════════════════════════════════════════════';
    
    -- Recorrer técnicos con datos de calidad
    FOR v_tecnico IN 
        SELECT 
            rut_tecnico,
            tecnico,
            porcentaje_reiteracion,
            total_completadas
        FROM v_calidad_tecnicos
        WHERE periodo = v_periodo_bono
    LOOP
        -- Usar % de calidad ya calculado
        v_porcentaje_cal := v_tecnico.porcentaje_reiteracion;
        
        -- Obtener RGU promedio del período de producción (mes anterior al bono)
        SELECT 
            CASE 
                WHEN COUNT(*) FILTER (WHERE estado = 'Completado') > 0 THEN
                    ROUND(
                        SUM(rgu_total)::NUMERIC / 
                        COUNT(*) FILTER (WHERE estado = 'Completado'), 
                        2
                    )
                ELSE 0
            END INTO v_rgu_promedio
        FROM produccion_creaciones
        WHERE rut_tecnico = v_tecnico.rut_tecnico
          AND TO_DATE(fecha_trabajo, 'DD/MM/YY') >= DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month')
          AND TO_DATE(fecha_trabajo, 'DD/MM/YY') < DATE_TRUNC('month', CURRENT_DATE);
        
        -- Calcular y guardar pago
        PERFORM calcular_pago_tecnico(
            v_tecnico.rut_tecnico,
            v_periodo_bono,
            v_rgu_promedio,
            v_porcentaje_cal
        );
        
        v_contador := v_contador + 1;
        
        RAISE NOTICE '✅ %: RGU=%, Cal=%', 
            v_tecnico.tecnico, v_rgu_promedio, v_porcentaje_cal;
    END LOOP;
    
    RAISE NOTICE '═══════════════════════════════════════════════════════';
    RAISE NOTICE '🎉 Completado: % técnicos procesados', v_contador;
    RAISE NOTICE '═══════════════════════════════════════════════════════';
    
    RETURN QUERY
    SELECT 
        v_contador,
        v_periodo_bono,
        'Calculado desde vistas existentes'::TEXT;
END;
$$ LANGUAGE plpgsql;

-- ═══════════════════════════════════════════════════════════════════
-- TEST: Ejecutar cálculo
-- ═══════════════════════════════════════════════════════════════════

SELECT * FROM calcular_bonos_desde_vistas();

-- Ver resultados
SELECT * FROM v_pagos_tecnicos 
WHERE periodo = TO_CHAR(CURRENT_DATE + INTERVAL '1 month', 'YYYY-MM')
ORDER BY total_liquido DESC;


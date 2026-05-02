-- ═══════════════════════════════════════════════════════════════════
-- 🎯 SISTEMA DE BONOS AUTOMÁTICO - Usando vistas existentes
-- ═══════════════════════════════════════════════════════════════════
-- Cruza datos de produccion_creaciones y v_calidad_tecnicos
-- Con lógica correcta de períodos
-- ═══════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════
-- FUNCIÓN: Obtener RGU promedio de un técnico en un período
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION obtener_rgu_promedio(
    p_rut_tecnico VARCHAR,
    p_fecha_inicio DATE,
    p_fecha_fin DATE
)
RETURNS NUMERIC AS $$
DECLARE
    v_rgu_total NUMERIC;
    v_dias_trabajados INTEGER;
    v_rgu_promedio NUMERIC;
BEGIN
    -- Calcular total RGU de órdenes completadas
    SELECT COALESCE(SUM(rgu_total), 0)
    INTO v_rgu_total
    FROM produccion_creaciones
    WHERE rut_tecnico = p_rut_tecnico
      AND TO_DATE(fecha_trabajo, 'DD/MM/YY') >= p_fecha_inicio
      AND TO_DATE(fecha_trabajo, 'DD/MM/YY') <= p_fecha_fin
      AND estado = 'Completado';
    
    -- Contar días únicos con actividad (completadas + PX-0)
    SELECT COUNT(DISTINCT fecha_trabajo)
    INTO v_dias_trabajados
    FROM produccion_creaciones
    WHERE rut_tecnico = p_rut_tecnico
      AND TO_DATE(fecha_trabajo, 'DD/MM/YY') >= p_fecha_inicio
      AND TO_DATE(fecha_trabajo, 'DD/MM/YY') <= p_fecha_fin;
    
    -- Calcular promedio: RGU total / días trabajados
    IF v_dias_trabajados > 0 THEN
        v_rgu_promedio := ROUND(v_rgu_total / v_dias_trabajados, 2);
    ELSE
        v_rgu_promedio := 0;
    END IF;
      
    RETURN v_rgu_promedio;
END;
$$ LANGUAGE plpgsql;

-- ═══════════════════════════════════════════════════════════════════
-- FUNCIÓN: Obtener % calidad de un técnico (ya está en v_calidad_tecnicos)
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION obtener_porcentaje_calidad_vista(
    p_rut_tecnico VARCHAR,
    p_periodo VARCHAR  -- Formato 'YYYY-MM'
)
RETURNS NUMERIC AS $$
DECLARE
    v_porcentaje NUMERIC;
BEGIN
    SELECT porcentaje_reiteracion INTO v_porcentaje
    FROM v_calidad_tecnicos
    WHERE rut_tecnico = p_rut_tecnico
      AND periodo = p_periodo;
      
    RETURN COALESCE(v_porcentaje, 0);
END;
$$ LANGUAGE plpgsql;

-- ═══════════════════════════════════════════════════════════════════
-- FUNCIÓN: Cálculo automático diario de bonos
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION calcular_bonos_diario_vistas()
RETURNS TABLE (
    tecnicos_procesados INTEGER,
    periodo_bono VARCHAR,
    fecha_calculo DATE
) AS $$
DECLARE
    v_dia_actual INTEGER;
    v_mes_bono VARCHAR;
    v_periodo_produccion_inicio DATE;
    v_periodo_produccion_fin DATE;
    v_periodo_calidad VARCHAR;
    v_contador INTEGER := 0;
    v_tecnico RECORD;
    v_rgu_promedio NUMERIC;
    v_porcentaje_cal NUMERIC;
    v_bono_prod_bruto INTEGER;
    v_bono_prod_liquido INTEGER;
    v_bono_cal_bruto INTEGER;
    v_bono_cal_liquido INTEGER;
BEGIN
    v_dia_actual := EXTRACT(DAY FROM CURRENT_DATE);
    
    -- Calcular mes de bono
    v_mes_bono := TO_CHAR(CURRENT_DATE + INTERVAL '1 month', 'YYYY-MM');
    
    RAISE NOTICE '═══════════════════════════════════════════════════════';
    RAISE NOTICE '🤖 CALCULANDO BONOS DESDE VISTAS';
    RAISE NOTICE '📅 Fecha ejecución: %', CURRENT_DATE;
    RAISE NOTICE '📊 Período de bono: %', v_mes_bono;
    RAISE NOTICE '═══════════════════════════════════════════════════════';
    
    -- ═══════════════════════════════════════════════════════════════
    -- PRODUCCIÓN: Se cierra fin de mes (días 28-31)
    -- ═══════════════════════════════════════════════════════════════
    IF v_dia_actual BETWEEN 28 AND 31 AND 
       v_dia_actual = EXTRACT(DAY FROM DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month' - INTERVAL '1 day') THEN
        
        -- Período: Todo el mes actual
        v_periodo_produccion_inicio := DATE_TRUNC('month', CURRENT_DATE);
        v_periodo_produccion_fin := DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month' - INTERVAL '1 day';
        
        RAISE NOTICE '🏭 CERRANDO PRODUCCIÓN del período % al %', 
            v_periodo_produccion_inicio, v_periodo_produccion_fin;
    ELSE
        -- Fuera de cierre, usar mes anterior
        v_periodo_produccion_inicio := DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month');
        v_periodo_produccion_fin := DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 day';
    END IF;
    
    -- ═══════════════════════════════════════════════════════════════
    -- CALIDAD: Se cierra el día 20 de cada mes
    -- ═══════════════════════════════════════════════════════════════
    IF v_dia_actual = 20 THEN
        -- Período de calidad: del 21 del mes anterior al 20 del mes actual
        v_periodo_calidad := v_mes_bono;  -- El período ya está calculado en v_calidad_tecnicos
        
        RAISE NOTICE '✅ CERRANDO CALIDAD del período %', v_periodo_calidad;
    ELSE
        -- Usar período anterior
        v_periodo_calidad := TO_CHAR(CURRENT_DATE, 'YYYY-MM');
    END IF;
    
    -- ═══════════════════════════════════════════════════════════════
    -- PROCESAR TODOS LOS TÉCNICOS
    -- ═══════════════════════════════════════════════════════════════
    
    FOR v_tecnico IN 
        SELECT DISTINCT rut_tecnico, tecnico
        FROM v_calidad_tecnicos
        WHERE periodo = v_periodo_calidad
    LOOP
        -- Obtener RGU promedio
        v_rgu_promedio := obtener_rgu_promedio(
            v_tecnico.rut_tecnico,
            v_periodo_produccion_inicio,
            v_periodo_produccion_fin
        );
        
        -- Obtener % de calidad
        v_porcentaje_cal := obtener_porcentaje_calidad_vista(
            v_tecnico.rut_tecnico,
            v_periodo_calidad
        );
        
        -- Obtener bonos de las escalas (bruto y líquido)
        SELECT monto_bruto, liquido_aprox 
        INTO v_bono_prod_bruto, v_bono_prod_liquido
        FROM obtener_bono_produccion(v_rgu_promedio);
        
        SELECT monto_bruto, liquido_aprox 
        INTO v_bono_cal_bruto, v_bono_cal_liquido
        FROM obtener_bono_calidad(v_porcentaje_cal);
        
        -- Guardar en tabla de pagos
        INSERT INTO pagos_tecnicos (
            rut_tecnico,
            periodo,
            rgu_promedio,
            porcentaje_reiteracion,
            bono_produccion_bruto,
            bono_calidad_bruto,
            bono_produccion_liquido,
            bono_calidad_liquido,
            total_bruto,
            total_liquido,
            fecha_calculo
        ) VALUES (
            v_tecnico.rut_tecnico,
            v_mes_bono,
            v_rgu_promedio,
            v_porcentaje_cal,
            v_bono_prod_bruto,
            v_bono_cal_bruto,
            v_bono_prod_liquido,
            v_bono_cal_liquido,
            v_bono_prod_bruto + v_bono_cal_bruto,
            v_bono_prod_liquido + v_bono_cal_liquido,
            CURRENT_DATE
        )
        ON CONFLICT (rut_tecnico, periodo)
        DO UPDATE SET
            rgu_promedio = EXCLUDED.rgu_promedio,
            porcentaje_reiteracion = EXCLUDED.porcentaje_reiteracion,
            bono_produccion_bruto = EXCLUDED.bono_produccion_bruto,
            bono_calidad_bruto = EXCLUDED.bono_calidad_bruto,
            bono_produccion_liquido = EXCLUDED.bono_produccion_liquido,
            bono_calidad_liquido = EXCLUDED.bono_calidad_liquido,
            total_bruto = EXCLUDED.total_bruto,
            total_liquido = EXCLUDED.total_liquido,
            fecha_calculo = CURRENT_DATE;
        
        v_contador := v_contador + 1;
        
        RAISE NOTICE '  ✅ % - RGU: % | Cal: % | Total: $%', 
            v_tecnico.tecnico, v_rgu_promedio, v_porcentaje_cal, (v_bono_prod_bruto + v_bono_cal_bruto);
    END LOOP;
    
    -- Registrar en log
    INSERT INTO log_calculo_bonos (
        fecha_calculo,
        periodo_bono,
        tecnicos_procesados,
        exitoso,
        mensaje
    ) VALUES (
        CURRENT_DATE,
        v_mes_bono,
        v_contador,
        TRUE,
        'Calculado desde vistas existentes'
    );
    
    RAISE NOTICE '═══════════════════════════════════════════════════════';
    RAISE NOTICE '🎉 COMPLETADO: % técnicos procesados', v_contador;
    RAISE NOTICE '═══════════════════════════════════════════════════════';
    
    RETURN QUERY
    SELECT 
        v_contador,
        v_mes_bono,
        CURRENT_DATE;
END;
$$ LANGUAGE plpgsql;

-- ═══════════════════════════════════════════════════════════════════
-- FUNCIÓN WRAPPER: Para pg_cron (sin parámetros)
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION ejecutar_calculo_bonos_diario_vistas()
RETURNS void AS $$
DECLARE
    v_resultado RECORD;
BEGIN
    SELECT * INTO v_resultado FROM calcular_bonos_diario_vistas();
    
    RAISE NOTICE '✅ Bonos calculados: % técnicos para período %', 
        v_resultado.tecnicos_procesados, v_resultado.periodo_bono;
END;
$$ LANGUAGE plpgsql;

-- ═══════════════════════════════════════════════════════════════════
-- 🧪 TEST: Ejecutar manualmente
-- ═══════════════════════════════════════════════════════════════════

-- SELECT * FROM calcular_bonos_diario_vistas();

-- Ver resultados
-- SELECT * FROM v_pagos_tecnicos 
-- WHERE periodo = TO_CHAR(CURRENT_DATE + INTERVAL '1 month', 'YYYY-MM')
-- ORDER BY total_liquido DESC;

-- ═══════════════════════════════════════════════════════════════════
-- 🤖 PROGRAMAR EN pg_cron (cuando esté habilitado)
-- ═══════════════════════════════════════════════════════════════════

-- Descomentar cuando pg_cron esté disponible:
/*
SELECT cron.schedule(
    'calculo_bonos_diario',           
    '0 23 * * *',                     
    'SELECT ejecutar_calculo_bonos_diario_vistas()'
);
*/


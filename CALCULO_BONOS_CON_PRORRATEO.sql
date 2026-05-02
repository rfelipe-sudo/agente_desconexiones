-- ═══════════════════════════════════════════════════════════════════
-- 🎯 SISTEMA DE BONOS CON PRORRATEO POR DÍAS TRABAJADOS
-- ═══════════════════════════════════════════════════════════════════
-- Los bonos se calculan proporcionalmente a los días trabajados
-- Fórmula: Bono Final = Bono Escala × (Días Trabajados / Días Laborales)
-- ═══════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════
-- FUNCIÓN: Calcular días laborales del mes (L-S menos feriados)
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION calcular_dias_laborales(
    p_mes INTEGER,
    p_anio INTEGER
)
RETURNS INTEGER AS $$
DECLARE
    v_dias_laborales INTEGER := 0;
    v_dia_actual DATE;
    v_ultimo_dia DATE;
    v_dia_semana INTEGER;
    v_feriados_count INTEGER;
BEGIN
    -- Primer y último día del mes
    v_dia_actual := DATE_TRUNC('month', TO_DATE(p_anio || '-' || p_mes || '-01', 'YYYY-MM-DD'));
    v_ultimo_dia := (DATE_TRUNC('month', v_dia_actual) + INTERVAL '1 month' - INTERVAL '1 day')::DATE;
    
    -- Contar días L-S del mes
    WHILE v_dia_actual <= v_ultimo_dia LOOP
        v_dia_semana := EXTRACT(DOW FROM v_dia_actual); -- 0=Domingo, 6=Sábado
        
        -- Contar Lunes (1) a Sábado (6), excluyendo Domingo (0)
        IF v_dia_semana BETWEEN 1 AND 6 THEN
            v_dias_laborales := v_dias_laborales + 1;
        END IF;
        
        v_dia_actual := v_dia_actual + INTERVAL '1 day';
    END LOOP;
    
    -- Restar feriados que caen en días laborales (L-S)
    -- Los feriados se obtienen de la tabla geo_marcas_diarias donde permiso contiene 'feriado'
    BEGIN
        SELECT COUNT(DISTINCT fecha) INTO v_feriados_count
        FROM geo_marcas_diarias
        WHERE EXTRACT(MONTH FROM TO_DATE(fecha, 'YYYY-MM-DD')) = p_mes
          AND EXTRACT(YEAR FROM TO_DATE(fecha, 'YYYY-MM-DD')) = p_anio
          AND LOWER(permiso) LIKE '%feriado%'
          AND EXTRACT(DOW FROM TO_DATE(fecha, 'YYYY-MM-DD')) BETWEEN 1 AND 6;
        
        v_dias_laborales := v_dias_laborales - COALESCE(v_feriados_count, 0);
    EXCEPTION WHEN OTHERS THEN
        -- Si la tabla no existe o hay error, asumir 0 feriados
        RAISE NOTICE '⚠️ No se pudieron cargar feriados de geo_marcas_diarias, usando 0';
        v_feriados_count := 0;
    END;
    
    RETURN GREATEST(v_dias_laborales, 1); -- Mínimo 1 para evitar división por cero
END;
$$ LANGUAGE plpgsql;

-- ═══════════════════════════════════════════════════════════════════
-- FUNCIÓN: Calcular días trabajados del técnico
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION calcular_dias_trabajados(
    p_rut_tecnico VARCHAR,
    p_fecha_inicio DATE,
    p_fecha_fin DATE
)
RETURNS INTEGER AS $$
DECLARE
    v_dias_trabajados INTEGER;
BEGIN
    -- Contar días únicos con al menos 1 orden (Completada O derivada)
    SELECT COUNT(DISTINCT fecha_trabajo) INTO v_dias_trabajados
    FROM produccion_creaciones
    WHERE rut_tecnico = p_rut_tecnico
      AND TO_DATE(fecha_trabajo, 'DD/MM/YY') >= p_fecha_inicio
      AND TO_DATE(fecha_trabajo, 'DD/MM/YY') <= p_fecha_fin
      AND estado IN ('Completado', 'Derivado', 'Suspendido'); -- Cualquier gestión cuenta
    
    RETURN COALESCE(v_dias_trabajados, 0);
END;
$$ LANGUAGE plpgsql;

-- ═══════════════════════════════════════════════════════════════════
-- FUNCIÓN: Obtener RGU promedio (usando días trabajados)
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION obtener_rgu_promedio_prorrateo(
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
    
    -- Calcular días trabajados (con cualquier gestión)
    v_dias_trabajados := calcular_dias_trabajados(p_rut_tecnico, p_fecha_inicio, p_fecha_fin);
    
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
-- FUNCIÓN: Obtener % calidad desde vista
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION obtener_porcentaje_calidad_prorrateo(
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
-- FUNCIÓN: Cálculo diario de bonos CON PRORRATEO
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION calcular_bonos_con_prorrateo()
RETURNS TABLE (
    tecnicos_procesados INTEGER,
    periodo_bono VARCHAR,
    fecha_calculo DATE
) AS $$
DECLARE
    v_mes_bono VARCHAR;
    v_mes_produccion INTEGER;
    v_anio_produccion INTEGER;
    v_periodo_produccion_inicio DATE;
    v_periodo_produccion_fin DATE;
    v_periodo_calidad VARCHAR;
    v_dias_laborales INTEGER;
    v_contador INTEGER := 0;
    v_tecnico RECORD;
    v_rgu_promedio NUMERIC;
    v_porcentaje_cal NUMERIC;
    v_dias_trabajados INTEGER;
    v_bono_prod_bruto INTEGER;
    v_bono_prod_liquido INTEGER;
    v_bono_cal_bruto INTEGER;
    v_bono_cal_liquido INTEGER;
    v_factor_prorrateo NUMERIC;
BEGIN
    -- Calcular período de bono (mes siguiente al actual)
    v_mes_bono := TO_CHAR(CURRENT_DATE + INTERVAL '1 month', 'YYYY-MM');
    
    -- Período de producción: mes anterior al bono
    v_periodo_produccion_inicio := DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month');
    v_periodo_produccion_fin := DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 day';
    
    v_mes_produccion := EXTRACT(MONTH FROM v_periodo_produccion_inicio);
    v_anio_produccion := EXTRACT(YEAR FROM v_periodo_produccion_inicio);
    
    -- Período de calidad (mismo que el bono)
    v_periodo_calidad := v_mes_bono;
    
    -- Calcular días laborales del mes de producción
    v_dias_laborales := calcular_dias_laborales(v_mes_produccion, v_anio_produccion);
    
    RAISE NOTICE '═══════════════════════════════════════════════════════';
    RAISE NOTICE '🎯 CALCULANDO BONOS CON PRORRATEO';
    RAISE NOTICE '📅 Período de bono: %', v_mes_bono;
    RAISE NOTICE '📊 Período producción: % - %', v_periodo_produccion_inicio, v_periodo_produccion_fin;
    RAISE NOTICE '📆 Días laborales del mes: %', v_dias_laborales;
    RAISE NOTICE '═══════════════════════════════════════════════════════';
    
    -- Procesar todos los técnicos con datos de calidad
    FOR v_tecnico IN 
        SELECT DISTINCT rut_tecnico, tecnico
        FROM v_calidad_tecnicos
        WHERE periodo = v_periodo_calidad
    LOOP
        -- Obtener RGU promedio
        v_rgu_promedio := obtener_rgu_promedio_prorrateo(
            v_tecnico.rut_tecnico,
            v_periodo_produccion_inicio,
            v_periodo_produccion_fin
        );
        
        -- Obtener % de calidad
        v_porcentaje_cal := obtener_porcentaje_calidad_prorrateo(
            v_tecnico.rut_tecnico,
            v_periodo_calidad
        );
        
        -- Calcular días trabajados del técnico
        v_dias_trabajados := calcular_dias_trabajados(
            v_tecnico.rut_tecnico,
            v_periodo_produccion_inicio,
            v_periodo_produccion_fin
        );
        
        -- Calcular factor de prorrateo
        v_factor_prorrateo := v_dias_trabajados::NUMERIC / v_dias_laborales::NUMERIC;
        
        -- Obtener bonos de las escalas (SIN prorrateo aún)
        SELECT monto_bruto, liquido_aprox 
        INTO v_bono_prod_bruto, v_bono_prod_liquido
        FROM obtener_bono_produccion(v_rgu_promedio);
        
        SELECT monto_bruto, liquido_aprox 
        INTO v_bono_cal_bruto, v_bono_cal_liquido
        FROM obtener_bono_calidad(v_porcentaje_cal);
        
        -- APLICAR PRORRATEO
        v_bono_prod_bruto := ROUND(v_bono_prod_bruto * v_factor_prorrateo);
        v_bono_prod_liquido := ROUND(v_bono_prod_liquido * v_factor_prorrateo);
        v_bono_cal_bruto := ROUND(v_bono_cal_bruto * v_factor_prorrateo);
        v_bono_cal_liquido := ROUND(v_bono_cal_liquido * v_factor_prorrateo);
        
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
        
        RAISE NOTICE '  ✅ % - Días: %/% | Total: $%', 
            v_tecnico.tecnico, 
            v_dias_trabajados, 
            v_dias_laborales,
            (v_bono_prod_liquido + v_bono_cal_liquido);
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
        FORMAT('Con prorrateo: %s días laborales', v_dias_laborales)
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
-- 🧪 TEST: Ejecutar cálculo con prorrateo
-- ═══════════════════════════════════════════════════════════════════

-- Primero, verificar días laborales de diciembre 2025
SELECT 
    '📆 Días laborales Diciembre 2025' AS test,
    calcular_dias_laborales(12, 2025) AS dias_laborales;

-- Verificar días trabajados de Felipe Plaza en diciembre
SELECT 
    '📊 Días trabajados Felipe Plaza' AS test,
    calcular_dias_trabajados(
        '15342161-7',
        '2025-12-01',
        '2025-12-31'
    ) AS dias_trabajados;

-- Ejecutar cálculo completo
-- SELECT * FROM calcular_bonos_con_prorrateo();

-- Ver resultados
-- SELECT 
--     rut_tecnico,
--     tecnico,
--     rgu_promedio,
--     porcentaje_reiteracion,
--     bono_produccion_liquido,
--     bono_calidad_liquido,
--     total_liquido
-- FROM v_pagos_tecnicos 
-- WHERE periodo = TO_CHAR(CURRENT_DATE + INTERVAL '1 month', 'YYYY-MM')
-- ORDER BY total_liquido DESC;


-- ═══════════════════════════════════════════════════════════════════
-- 🎯 SISTEMA DE BONOS CON PRORRATEO - VERSIÓN CORREGIDA
-- ═══════════════════════════════════════════════════════════════════
-- Formato de fecha: DD/MM/YYYY (ejemplo: 1/12/2025 = 1 diciembre 2025)
-- Día trabajado = Día con al menos 1 actividad (sin importar estado)
-- Tabla de datos: produccion_crea
-- ═══════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════
-- FUNCIÓN: Calcular días laborales del mes (L-S, sin contar domingos)
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION calcular_dias_laborales_simple(
    p_mes INTEGER,
    p_anio INTEGER
)
RETURNS INTEGER AS $$
DECLARE
    v_dias_laborales INTEGER := 0;
    v_feriados_laborales INTEGER := 0;
    v_dia_actual DATE;
    v_ultimo_dia DATE;
    v_primer_dia DATE;
    v_dia_semana INTEGER;
BEGIN
    -- Primer y último día del mes
    v_primer_dia := TO_DATE(p_anio || '-' || LPAD(p_mes::TEXT, 2, '0') || '-01', 'YYYY-MM-DD');
    v_ultimo_dia := (DATE_TRUNC('month', v_primer_dia) + INTERVAL '1 month' - INTERVAL '1 day')::DATE;
    v_dia_actual := v_primer_dia;
    
    -- Contar días L-S del mes (excluir domingos)
    WHILE v_dia_actual <= v_ultimo_dia LOOP
        v_dia_semana := EXTRACT(DOW FROM v_dia_actual); -- 0=Domingo, 6=Sábado
        
        -- Contar Lunes (1) a Sábado (6), excluyendo Domingo (0)
        IF v_dia_semana BETWEEN 1 AND 6 THEN
            v_dias_laborales := v_dias_laborales + 1;
        END IF;
        
        v_dia_actual := v_dia_actual + INTERVAL '1 day';
    END LOOP;
    
    -- ═══════════════════════════════════════════════════════════════════
    -- Restar feriados chilenos según calendario oficial
    -- ═══════════════════════════════════════════════════════════════════
    
    -- DICIEMBRE 2025
    IF p_anio = 2025 AND p_mes = 12 THEN
        v_feriados_laborales := 2; -- 8 dic (Lunes), 25 dic (Jueves)
    END IF;
    
    -- ENERO 2026
    IF p_anio = 2026 AND p_mes = 1 THEN
        v_feriados_laborales := 1; -- 1 enero (Jueves - Año Nuevo)
    END IF;
    
    -- FEBRERO 2026
    IF p_anio = 2026 AND p_mes = 2 THEN
        v_feriados_laborales := 0; -- Sin feriados laborales
    END IF;
    
    -- MARZO 2026
    IF p_anio = 2026 AND p_mes = 3 THEN
        v_feriados_laborales := 0; -- Sin feriados laborales
    END IF;
    
    -- ABRIL 2026 (Semana Santa)
    IF p_anio = 2026 AND p_mes = 4 THEN
        v_feriados_laborales := 2; -- 3 abr (Viernes Santo), 4 abr (Sábado Santo)
    END IF;
    
    -- MAYO 2026
    IF p_anio = 2026 AND p_mes = 5 THEN
        v_feriados_laborales := 2; -- 1 mayo (Viernes), 21 mayo (Jueves)
    END IF;
    
    -- TODO: Agregar más meses según calendario chileno oficial
    -- Fuente: https://www.feriados.cl
    
    -- Restar feriados de días laborales
    v_dias_laborales := v_dias_laborales - v_feriados_laborales;
    
    RETURN GREATEST(v_dias_laborales, 1);
END;
$$ LANGUAGE plpgsql;

-- ═══════════════════════════════════════════════════════════════════
-- FUNCIÓN: Calcular días trabajados del técnico
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION calcular_dias_trabajados_simple(
    p_rut_tecnico VARCHAR,
    p_mes INTEGER,
    p_anio INTEGER
)
RETURNS INTEGER AS $$
DECLARE
    v_dias_trabajados INTEGER;
BEGIN
    -- Contar días únicos con al menos 1 orden (sin importar estado)
    -- Formato de fecha en DB: DD/MM/YYYY (ej: 1/12/2025, 30/12/2025)
    SELECT COUNT(DISTINCT fecha_trabajo) INTO v_dias_trabajados
    FROM produccion_crea
    WHERE rut_tecnico = p_rut_tecnico
      AND fecha_trabajo LIKE '%/' || p_mes::TEXT || '/' || p_anio::TEXT;
    
    RETURN COALESCE(v_dias_trabajados, 0);
END;
$$ LANGUAGE plpgsql;

-- ═══════════════════════════════════════════════════════════════════
-- FUNCIÓN: Obtener RGU promedio
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION obtener_rgu_promedio_simple(
    p_rut_tecnico VARCHAR,
    p_mes INTEGER,
    p_anio INTEGER
)
RETURNS NUMERIC AS $$
DECLARE
    v_rgu_total NUMERIC;
    v_dias_trabajados INTEGER;
    v_rgu_promedio NUMERIC;
BEGIN
    -- Calcular total RGU de órdenes completadas
    -- Formato de fecha en DB: DD/MM/YYYY (ej: 1/12/2025, 30/12/2025)
    SELECT COALESCE(SUM(rgu_total), 0)
    INTO v_rgu_total
    FROM produccion_crea
    WHERE rut_tecnico = p_rut_tecnico
      AND fecha_trabajo LIKE '%/' || p_mes::TEXT || '/' || p_anio::TEXT
      AND estado = 'Completado';
    
    -- Calcular días trabajados (con cualquier actividad)
    v_dias_trabajados := calcular_dias_trabajados_simple(p_rut_tecnico, p_mes, p_anio);
    
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

CREATE OR REPLACE FUNCTION obtener_porcentaje_calidad_simple(
    p_rut_tecnico VARCHAR,
    p_periodo VARCHAR
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
-- FUNCIÓN: Cálculo de bonos con prorrateo (versión simplificada)
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION calcular_bonos_prorrateo_simple(
    p_mes_produccion INTEGER DEFAULT NULL,
    p_anio_produccion INTEGER DEFAULT NULL
)
RETURNS TABLE (
    tecnicos_procesados INTEGER,
    periodo_bono VARCHAR,
    dias_laborales_mes INTEGER,
    fecha_calculo DATE
) AS $$
DECLARE
    v_mes_bono VARCHAR;
    v_mes_produccion INTEGER;
    v_anio_produccion INTEGER;
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
    -- Si no se especifica mes/año, usar el mes anterior
    IF p_mes_produccion IS NULL OR p_anio_produccion IS NULL THEN
        v_mes_produccion := EXTRACT(MONTH FROM CURRENT_DATE - INTERVAL '1 month');
        v_anio_produccion := EXTRACT(YEAR FROM CURRENT_DATE - INTERVAL '1 month');
    ELSE
        v_mes_produccion := p_mes_produccion;
        v_anio_produccion := p_anio_produccion;
    END IF;
    
    -- Calcular período de bono (mes siguiente al de producción)
    IF v_mes_produccion = 12 THEN
        v_mes_bono := (v_anio_produccion + 1)::TEXT || '-01';
    ELSE
        v_mes_bono := v_anio_produccion::TEXT || '-' || LPAD((v_mes_produccion + 1)::TEXT, 2, '0');
    END IF;
    
    -- Período de calidad = período de bono
    v_periodo_calidad := v_mes_bono;
    
    -- Calcular días laborales del mes de producción
    v_dias_laborales := calcular_dias_laborales_simple(v_mes_produccion, v_anio_produccion);
    
    RAISE NOTICE '═══════════════════════════════════════════════════════';
    RAISE NOTICE '🎯 CALCULANDO BONOS CON PRORRATEO (SIMPLE)';
    RAISE NOTICE '📅 Mes producción: %/%', v_mes_produccion, v_anio_produccion;
    RAISE NOTICE '📅 Período de bono: %', v_mes_bono;
    RAISE NOTICE '📆 Días laborales del mes: %', v_dias_laborales;
    RAISE NOTICE '═══════════════════════════════════════════════════════';
    
    -- Procesar todos los técnicos con datos de calidad
    FOR v_tecnico IN 
        SELECT DISTINCT rut_tecnico, tecnico
        FROM v_calidad_tecnicos
        WHERE periodo = v_periodo_calidad
    LOOP
        -- Obtener RGU promedio
        v_rgu_promedio := obtener_rgu_promedio_simple(
            v_tecnico.rut_tecnico,
            v_mes_produccion,
            v_anio_produccion
        );
        
        -- Obtener % de calidad
        v_porcentaje_cal := obtener_porcentaje_calidad_simple(
            v_tecnico.rut_tecnico,
            v_periodo_calidad
        );
        
        -- Calcular días trabajados del técnico
        v_dias_trabajados := calcular_dias_trabajados_simple(
            v_tecnico.rut_tecnico,
            v_mes_produccion,
            v_anio_produccion
        );
        
        -- Calcular factor de prorrateo
        IF v_dias_laborales > 0 THEN
            v_factor_prorrateo := v_dias_trabajados::NUMERIC / v_dias_laborales::NUMERIC;
        ELSE
            v_factor_prorrateo := 0;
        END IF;
        
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
    
    RAISE NOTICE '═══════════════════════════════════════════════════════';
    RAISE NOTICE '🎉 COMPLETADO: % técnicos', v_contador;
    RAISE NOTICE '═══════════════════════════════════════════════════════';
    
    RETURN QUERY
    SELECT 
        v_contador,
        v_mes_bono,
        v_dias_laborales,
        CURRENT_DATE;
END;
$$ LANGUAGE plpgsql;

-- ═══════════════════════════════════════════════════════════════════
-- 🧪 TESTS
-- ═══════════════════════════════════════════════════════════════════

-- Test 1: Días laborales diciembre 2025
SELECT 
    '📆 Días laborales Diciembre 2025' AS test,
    calcular_dias_laborales_simple(12, 2025) AS resultado,
    'Esperado: 25 días (L-S sin domingos, restando 2 feriados: 8 y 25 dic)' AS nota;

-- Test 2: Días trabajados Felipe Plaza diciembre 2025
SELECT 
    '📊 Días trabajados Felipe (Dic 2025)' AS test,
    calcular_dias_trabajados_simple('15342161-7', 12, 2025) AS resultado;

-- Test 3: RGU promedio Felipe Plaza
SELECT 
    '🎯 RGU Felipe (Dic 2025)' AS test,
    obtener_rgu_promedio_simple('15342161-7', 12, 2025) AS resultado,
    'Esperado: 3.4' AS nota;

-- ═══════════════════════════════════════════════════════════════════
-- 🚀 EJECUTAR CÁLCULO
-- ═══════════════════════════════════════════════════════════════════

-- Para diciembre 2025 (pagado en enero 2026):
-- SELECT * FROM calcular_bonos_prorrateo_simple(12, 2025);

-- Ver resultados:
-- SELECT * FROM v_pagos_tecnicos 
-- WHERE periodo = '2026-01'
-- ORDER BY total_liquido DESC;


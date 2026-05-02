-- ═══════════════════════════════════════════════════════════════════
-- 🤖 SISTEMA AUTOMÁTICO DE CÁLCULO DE BONOS - DIARIO 7:00 AM
-- ═══════════════════════════════════════════════════════════════════
-- Se ejecuta todos los días a las 7:00 AM
-- Calcula bono del MES SIGUIENTE (mes actual + 1)
-- Actualiza/sobrescribe datos diariamente:
--   - Producción: hasta el último día del mes (día 30/31)
--   - Calidad: hasta el día 20 (después queda cerrada)
-- ═══════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════
-- FUNCIÓN 1: Calcular RGU promedio de un técnico en un período
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION calcular_rgu_promedio(
    p_rut_tecnico VARCHAR,
    p_fecha_inicio DATE,
    p_fecha_fin DATE
)
RETURNS NUMERIC AS $$
DECLARE
    v_rgu_promedio NUMERIC;
BEGIN
    -- Calcular RGU sumando servicios: internet + telefono + tv
    SELECT 
        CASE 
            WHEN COUNT(*) FILTER (WHERE estado = 'Completado') > 0 
            THEN ROUND(
                SUM(
                    COALESCE(internet, 0) + 
                    COALESCE(telefono, 0) + 
                    COALESCE(tv, 0)
                )::NUMERIC / 
                COUNT(*) FILTER (WHERE estado = 'Completado'), 
                2
            )
            ELSE 0 
        END
    INTO v_rgu_promedio
    FROM produccion_crea
    WHERE rut_tecnico = p_rut_tecnico
      AND TO_DATE(fecha_trabajo, 'DD/MM/YYYY') >= p_fecha_inicio
      AND TO_DATE(fecha_trabajo, 'DD/MM/YYYY') <= p_fecha_fin
      AND estado = 'Completado';
    
    RETURN COALESCE(v_rgu_promedio, 0);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION calcular_rgu_promedio IS 
'Calcula el RGU promedio de un técnico en un rango de fechas';

-- ═══════════════════════════════════════════════════════════════════
-- FUNCIÓN 2: Obtener % de reiteración de un técnico en un período
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION obtener_porcentaje_calidad(
    p_rut_tecnico VARCHAR,
    p_periodo VARCHAR  -- Formato: 'YYYY-MM'
)
RETURNS NUMERIC AS $$
DECLARE
    v_porcentaje NUMERIC;
BEGIN
    SELECT porcentaje_reiteracion
    INTO v_porcentaje
    FROM v_calidad_tecnicos
    WHERE rut_tecnico = p_rut_tecnico
      AND periodo = p_periodo
    LIMIT 1;
    
    RETURN COALESCE(v_porcentaje, 0);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION obtener_porcentaje_calidad IS 
'Obtiene el % de reiteración de un técnico desde v_calidad_tecnicos';

-- ═══════════════════════════════════════════════════════════════════
-- FUNCIÓN 3: Calcular bonos diarios con lógica de cierre por concepto
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION calcular_bonos_diario()
RETURNS TABLE (
    tecnicos_procesados INTEGER,
    periodo_bono VARCHAR,
    periodo_produccion VARCHAR,
    calidad_actualizada BOOLEAN,
    mensaje TEXT
) AS $$
DECLARE
    v_hoy DATE;
    v_dia_actual INTEGER;
    v_mes_actual INTEGER;
    v_anio_actual INTEGER;
    
    -- Bono a calcular (mes siguiente)
    v_periodo_bono VARCHAR;
    v_mes_bono INTEGER;
    v_anio_bono INTEGER;
    
    -- Fechas de producción (del mes actual)
    v_fecha_inicio_prod DATE;
    v_fecha_fin_prod DATE;
    
    -- Control de calidad
    v_actualizar_calidad BOOLEAN;
    
    v_contador INTEGER := 0;
    v_tecnico RECORD;
    v_rgu_promedio NUMERIC;
    v_porcentaje_cal NUMERIC;
BEGIN
    -- Obtener fecha actual
    v_hoy := CURRENT_DATE;
    v_dia_actual := EXTRACT(DAY FROM v_hoy);
    v_mes_actual := EXTRACT(MONTH FROM v_hoy);
    v_anio_actual := EXTRACT(YEAR FROM v_hoy);
    
    -- Calcular período de BONO (mes siguiente)
    v_mes_bono := v_mes_actual + 1;
    v_anio_bono := v_anio_actual;
    
    IF v_mes_bono > 12 THEN
        v_mes_bono := 1;
        v_anio_bono := v_anio_bono + 1;
    END IF;
    
    v_periodo_bono := v_anio_bono || '-' || LPAD(v_mes_bono::TEXT, 2, '0');
    
    -- Fechas de producción (mes actual, del 1 al día actual)
    v_fecha_inicio_prod := MAKE_DATE(v_anio_actual, v_mes_actual, 1);
    v_fecha_fin_prod := v_hoy;
    
    -- Determinar si actualizamos calidad (solo hasta el día 20)
    v_actualizar_calidad := (v_dia_actual <= 20);
    
    RAISE NOTICE '═══════════════════════════════════════════════════════';
    RAISE NOTICE '🤖 CÁLCULO AUTOMÁTICO DE BONOS - %', v_hoy;
    RAISE NOTICE '═══════════════════════════════════════════════════════';
    RAISE NOTICE '📊 Bono a calcular: %', v_periodo_bono;
    RAISE NOTICE '📅 Producción: % → % (día %/%)', 
        v_fecha_inicio_prod, v_fecha_fin_prod, v_dia_actual, 
        EXTRACT(DAY FROM (DATE_TRUNC('month', v_hoy) + INTERVAL '1 month - 1 day'));
    RAISE NOTICE '📊 Calidad: % (cerrada desde día 20)', 
        CASE WHEN v_actualizar_calidad THEN 'ACTUALIZANDO' ELSE 'CERRADA' END;
    RAISE NOTICE '═══════════════════════════════════════════════════════';
    
    -- Recorrer TODOS los técnicos activos
    FOR v_tecnico IN 
        SELECT DISTINCT 
            COALESCE(p.rut_tecnico, c.rut_tecnico) AS rut_tecnico,
            COALESCE(
                (SELECT tecnico FROM v_calidad_tecnicos WHERE rut_tecnico = COALESCE(p.rut_tecnico, c.rut_tecnico) LIMIT 1),
                'Técnico ' || COALESCE(p.rut_tecnico, c.rut_tecnico)
            ) AS tecnico
        FROM (
            SELECT DISTINCT rut_tecnico
            FROM produccion_crea
            WHERE TO_DATE(fecha_trabajo, 'DD/MM/YYYY') >= v_fecha_inicio_prod
              AND TO_DATE(fecha_trabajo, 'DD/MM/YYYY') <= v_fecha_fin_prod
        ) p
        FULL OUTER JOIN (
            SELECT DISTINCT rut_tecnico
            FROM v_calidad_tecnicos
            WHERE periodo = v_periodo_bono
        ) c ON p.rut_tecnico = c.rut_tecnico
    LOOP
        -- SIEMPRE calcular RGU promedio (actualiza todos los días)
        v_rgu_promedio := calcular_rgu_promedio(
            v_tecnico.rut_tecnico,
            v_fecha_inicio_prod,
            v_fecha_fin_prod
        );
        
        -- Calidad: 
        -- - Si día <= 20: actualizar con datos actuales
        -- - Si día > 20: mantener el valor que ya está guardado
        IF v_actualizar_calidad THEN
            -- Actualizar con datos actuales
            v_porcentaje_cal := obtener_porcentaje_calidad(
                v_tecnico.rut_tecnico,
                v_periodo_bono
            );
        ELSE
            -- Mantener el valor ya guardado (no actualizar)
            SELECT porcentaje_reiteracion INTO v_porcentaje_cal
            FROM pagos_tecnicos
            WHERE rut_tecnico = v_tecnico.rut_tecnico
              AND periodo = v_periodo_bono;
            
            -- Si no existe registro previo, obtener de v_calidad_tecnicos
            IF v_porcentaje_cal IS NULL THEN
                v_porcentaje_cal := obtener_porcentaje_calidad(
                    v_tecnico.rut_tecnico,
                    v_periodo_bono
                );
            END IF;
        END IF;
        
        -- Solo calcular si tiene RGU o calidad
        IF v_rgu_promedio > 0 OR v_porcentaje_cal > 0 THEN
            -- Calcular y guardar pago (sobrescribe producción, mantiene calidad si día > 20)
            PERFORM calcular_pago_tecnico(
                v_tecnico.rut_tecnico,
                v_periodo_bono,
                v_rgu_promedio,
                v_porcentaje_cal
            );
            
            v_contador := v_contador + 1;
            
            IF v_actualizar_calidad THEN
                RAISE NOTICE '✅ %: RGU=%, Cal=%', 
                    v_tecnico.tecnico, v_rgu_promedio, v_porcentaje_cal;
            ELSE
                RAISE NOTICE '✅ %: RGU=%, Cal=% (cerrada)', 
                    v_tecnico.tecnico, v_rgu_promedio, v_porcentaje_cal;
            END IF;
        END IF;
    END LOOP;
    
    RAISE NOTICE '═══════════════════════════════════════════════════════';
    RAISE NOTICE '🎉 Proceso completado: % técnicos procesados', v_contador;
    
    IF v_dia_actual = EXTRACT(DAY FROM (DATE_TRUNC('month', v_hoy) + INTERVAL '1 month - 1 day')) THEN
        RAISE NOTICE '🔒 ÚLTIMO DÍA DEL MES - Bono % CERRADO DEFINITIVAMENTE', v_periodo_bono;
    END IF;
    
    RAISE NOTICE '═══════════════════════════════════════════════════════';
    
    -- Retornar resumen
    RETURN QUERY
    SELECT 
        v_contador,
        v_periodo_bono,
        v_fecha_inicio_prod::TEXT || ' → ' || v_fecha_fin_prod::TEXT,
        v_actualizar_calidad,
        CASE 
            WHEN v_dia_actual = EXTRACT(DAY FROM (DATE_TRUNC('month', v_hoy) + INTERVAL '1 month - 1 day'))
            THEN 'BONO CERRADO - Último día del mes'
            WHEN v_dia_actual = 20
            THEN 'CALIDAD CERRADA - Último día de medición'
            WHEN v_dia_actual > 20
            THEN 'Solo actualizando producción (calidad cerrada desde día 20)'
            ELSE 'Actualizando producción y calidad'
        END;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION calcular_bonos_diario IS 
'Calcula bonos del mes siguiente con lógica de cierre diferenciado: producción hasta día 30/31, calidad hasta día 20';

-- ═══════════════════════════════════════════════════════════════════
-- TABLA DE LOG: Registrar ejecuciones automáticas
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS log_calculo_bonos (
    id SERIAL PRIMARY KEY,
    fecha_ejecucion TIMESTAMP DEFAULT NOW(),
    dia_mes INTEGER,
    periodo_bono VARCHAR(7),
    tecnicos_procesados INTEGER,
    calidad_actualizada BOOLEAN,
    duracion_segundos NUMERIC(10,3),
    estado VARCHAR(20) DEFAULT 'EXITOSO',
    mensaje TEXT,
    error TEXT
);

COMMENT ON TABLE log_calculo_bonos IS 
'Log de ejecuciones automáticas del cálculo de bonos';

CREATE INDEX IF NOT EXISTS idx_log_bonos_fecha ON log_calculo_bonos(fecha_ejecucion DESC);
CREATE INDEX IF NOT EXISTS idx_log_bonos_periodo ON log_calculo_bonos(periodo_bono);

-- ═══════════════════════════════════════════════════════════════════
-- FUNCIÓN PRINCIPAL CON LOG: Ejecutar diariamente a las 7 AM
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION ejecutar_calculo_bonos_diario()
RETURNS VOID AS $$
DECLARE
    v_inicio TIMESTAMP;
    v_fin TIMESTAMP;
    v_duracion NUMERIC;
    v_resultado RECORD;
    v_error TEXT;
    v_dia_actual INTEGER;
BEGIN
    v_inicio := CLOCK_TIMESTAMP();
    v_dia_actual := EXTRACT(DAY FROM CURRENT_DATE);
    
    BEGIN
        -- Ejecutar cálculo
        SELECT * INTO v_resultado FROM calcular_bonos_diario();
        
        v_fin := CLOCK_TIMESTAMP();
        v_duracion := EXTRACT(EPOCH FROM (v_fin - v_inicio));
        
        -- Registrar en log
        INSERT INTO log_calculo_bonos (
            dia_mes,
            periodo_bono,
            tecnicos_procesados,
            calidad_actualizada,
            duracion_segundos,
            estado,
            mensaje
        ) VALUES (
            v_dia_actual,
            v_resultado.periodo_bono,
            v_resultado.tecnicos_procesados,
            v_resultado.calidad_actualizada,
            v_duracion,
            'EXITOSO',
            v_resultado.mensaje || FORMAT(' - Procesados %s técnicos en %s seg', 
                v_resultado.tecnicos_procesados,
                ROUND(v_duracion, 2)
            )
        );
        
        RAISE NOTICE '✅ Cálculo completado y registrado en log';
        
    EXCEPTION WHEN OTHERS THEN
        v_error := SQLERRM;
        v_fin := CLOCK_TIMESTAMP();
        v_duracion := EXTRACT(EPOCH FROM (v_fin - v_inicio));
        
        -- Registrar error en log
        INSERT INTO log_calculo_bonos (
            dia_mes,
            duracion_segundos,
            estado,
            mensaje,
            error
        ) VALUES (
            v_dia_actual,
            v_duracion,
            'FALLIDO',
            'Error durante la ejecución',
            v_error
        );
        
        RAISE WARNING '❌ Error en cálculo de bonos: %', v_error;
    END;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ejecutar_calculo_bonos_diario IS 
'Función principal que se ejecuta diariamente a las 7 AM para calcular bonos';

-- ═══════════════════════════════════════════════════════════════════
-- CONFIGURACIÓN: Tarea programada con pg_cron
-- ═══════════════════════════════════════════════════════════════════

-- ⚠️ IMPORTANTE: Estas líneas requieren que pg_cron esté habilitado
-- Para habilitar pg_cron en Supabase:
-- 1. Ve a Dashboard → Database → Extensions
-- 2. Busca "pg_cron" 
-- 3. Haz clic en "Enable"
-- 4. Luego ejecuta las líneas comentadas a continuación

-- DESCOMENTAR DESPUÉS DE HABILITAR pg_cron:

/*
-- Eliminar tarea anterior si existe
SELECT cron.unschedule('calculo-bonos-diario') 
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'calculo-bonos-diario');

-- Programar tarea diaria a las 7:00 AM (Chile UTC-3)
-- 10:00 UTC = 7:00 AM Chile
SELECT cron.schedule(
    'calculo-bonos-diario',
    '0 10 * * *',
    $$SELECT ejecutar_calculo_bonos_diario()$$
);
*/

-- ═══════════════════════════════════════════════════════════════════
-- NOTA: El sistema funciona perfectamente SIN pg_cron
-- Puedes ejecutar manualmente: SELECT ejecutar_calculo_bonos_diario();
-- ═══════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════
-- ✅ VERIFICACIÓN Y PRUEBAS
-- ═══════════════════════════════════════════════════════════════════

-- TEST 1: Ejecutar cálculo manual
SELECT 
    '🧪 TEST 1: Ejecución manual' AS test,
    *
FROM calcular_bonos_diario();

-- TEST 2: Ver bonos calculados del mes de bono actual
SELECT 
    '📊 TEST 2: Bonos calculados' AS test,
    COUNT(*) AS total_tecnicos,
    periodo,
    SUM(total_bruto) AS suma_bruto,
    SUM(total_liquido) AS suma_liquido,
    ROUND(AVG(rgu_promedio), 2) AS rgu_promedio,
    ROUND(AVG(porcentaje_reiteracion), 2) AS calidad_promedio
FROM v_pagos_tecnicos
WHERE periodo = TO_CHAR(CURRENT_DATE + INTERVAL '1 month', 'YYYY-MM')
GROUP BY periodo;

-- TEST 3: Ver últimas 5 ejecuciones del log
SELECT 
    '📋 TEST 3: Últimas ejecuciones' AS test,
    fecha_ejecucion,
    dia_mes,
    periodo_bono,
    tecnicos_procesados,
    calidad_actualizada,
    ROUND(duracion_segundos, 2) AS segundos,
    estado,
    mensaje
FROM log_calculo_bonos
ORDER BY fecha_ejecucion DESC
LIMIT 5;

-- TEST 4: Verificar tarea programada (solo si pg_cron está habilitado)
/*
SELECT 
    '⏰ TEST 4: Tarea programada' AS test,
    jobname,
    schedule AS cron_expression,
    command,
    active
FROM cron.job
WHERE jobname = 'calculo-bonos-diario';
*/

SELECT 
    '⚠️ TEST 4: pg_cron no habilitado' AS test,
    'Habilita pg_cron en Database → Extensions para programar tarea automática' AS mensaje;

-- ═══════════════════════════════════════════════════════════════════
-- 📊 CONSULTAS ÚTILES DE MONITOREO
-- ═══════════════════════════════════════════════════════════════════

-- Ver evolución diaria del bono actual
SELECT 
    fecha_ejecucion::DATE AS fecha,
    dia_mes,
    tecnicos_procesados,
    calidad_actualizada,
    mensaje
FROM log_calculo_bonos
WHERE periodo_bono = TO_CHAR(CURRENT_DATE + INTERVAL '1 month', 'YYYY-MM')
ORDER BY fecha_ejecucion;

-- Ver cuándo se cerró la calidad (día 20)
SELECT 
    fecha_ejecucion,
    dia_mes,
    periodo_bono,
    mensaje
FROM log_calculo_bonos
WHERE dia_mes = 20
ORDER BY fecha_ejecucion DESC
LIMIT 5;

-- Ver cierres de mes (último día)
SELECT 
    fecha_ejecucion,
    dia_mes,
    periodo_bono,
    tecnicos_procesados,
    mensaje
FROM log_calculo_bonos
WHERE mensaje LIKE '%CERRADO%'
ORDER BY fecha_ejecucion DESC
LIMIT 5;

-- ═══════════════════════════════════════════════════════════════════
-- 📝 DOCUMENTACIÓN DE USO
-- ═══════════════════════════════════════════════════════════════════
/*
════════════════════════════════════════════════════════════════════
FUNCIONAMIENTO AUTOMÁTICO
════════════════════════════════════════════════════════════════════

PERIODICIDAD:
- Todos los días a las 7:00 AM (hora Chile)

LÓGICA DE CÁLCULO:
- Calcula bono del MES SIGUIENTE
- Ejemplo: Hoy 30 Ene → calcula bono "2026-02"

PRODUCCIÓN:
- Mide del 1 al día actual del mes
- Se actualiza TODOS LOS DÍAS hasta el día 30/31
- Cierra el último día del mes

CALIDAD:
- Mide del 21 del mes anterior al 20 del mes actual
- Se actualiza SOLO HASTA EL DÍA 20
- Después del día 20: queda CERRADA (no se actualiza más)

CRONOLOGÍA EJEMPLO (Calculando Bono Febrero):
1 Ene 7AM  → Crea "2026-02", prod: 1 Ene, cal: 21 Dic - 1 Ene
15 Ene 7AM → Actualiza "2026-02", prod: 1-15 Ene, cal: 21 Dic - 15 Ene
20 Ene 7AM → Actualiza "2026-02", prod: 1-20 Ene, cal: 21 Dic - 20 Ene ✅ CALIDAD CERRADA
25 Ene 7AM → Actualiza "2026-02", prod: 1-25 Ene, cal: (no cambia, cerrada)
31 Ene 7AM → Actualiza "2026-02", prod: 1-31 Ene ✅ PRODUCCIÓN CERRADA
1 Feb 7AM  → Crea "2026-03" (nuevo mes), "2026-02" queda CERRADO

════════════════════════════════════════════════════════════════════
EJECUCIÓN MANUAL (para pruebas)
════════════════════════════════════════════════════════════════════

SELECT ejecutar_calculo_bonos_diario();

════════════════════════════════════════════════════════════════════
MONITOREO
════════════════════════════════════════════════════════════════════

Ver log completo:
  SELECT * FROM log_calculo_bonos ORDER BY fecha_ejecucion DESC;

Ver bonos calculados:
  SELECT * FROM v_pagos_tecnicos ORDER BY periodo DESC;

Ver tarea programada:
  SELECT * FROM cron.job WHERE jobname = 'calculo-bonos-diario';

════════════════════════════════════════════════════════════════════
AJUSTE DE HORARIO
════════════════════════════════════════════════════════════════════

Para cambiar el horario:
  SELECT cron.unschedule('calculo-bonos-diario');
  SELECT cron.schedule(
    'calculo-bonos-diario',
    '0 11 * * *',  -- 11:00 UTC = 8:00 AM Chile
    $$SELECT ejecutar_calculo_bonos_diario()$$
  );

Horarios Chile (UTC-3):
  '0 9 * * *'  = 6:00 AM
  '0 10 * * *' = 7:00 AM ← ACTUAL
  '0 11 * * *' = 8:00 AM
  '0 12 * * *' = 9:00 AM
*/


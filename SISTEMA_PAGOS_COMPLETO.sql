-- ═══════════════════════════════════════════════════════════════════
-- 🎯 SISTEMA DE PAGOS - BONOS PRODUCCIÓN Y CALIDAD
-- ═══════════════════════════════════════════════════════════════════
-- Sistema para calcular y visualizar bonos de técnicos
-- Basado en escalas de productividad (RGU) y calidad (% reiteración)
-- ═══════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════
-- PASO 1: CREAR TABLAS
-- ═══════════════════════════════════════════════════════════════════

-- Tabla: Escala de productividad (bonos por RGU)
CREATE TABLE IF NOT EXISTS escala_produccion (
    id SERIAL PRIMARY KEY,
    rgu_min NUMERIC(3,1) NOT NULL,
    rgu_max NUMERIC(3,1) NOT NULL,
    monto_bruto INTEGER NOT NULL,           -- Para dashboard web
    mano_obra INTEGER NOT NULL,             -- Referencia
    liquido_aprox INTEGER NOT NULL,         -- Para app móvil
    created_at TIMESTAMP DEFAULT NOW(),
    CONSTRAINT uq_escala_prod_rango UNIQUE(rgu_min, rgu_max)
);

COMMENT ON TABLE escala_produccion IS 
'Escala de bonos por productividad (RGU mensual promedio)';

COMMENT ON COLUMN escala_produccion.monto_bruto IS 
'Monto bruto mensual para mostrar en dashboard web';

COMMENT ON COLUMN escala_produccion.liquido_aprox IS 
'Líquido aproximado para mostrar en app móvil';

-- Tabla: Escala de calidad (bonos por % reiteración)
CREATE TABLE IF NOT EXISTS escala_calidad (
    id SERIAL PRIMARY KEY,
    porcentaje_min NUMERIC(5,2) NOT NULL,
    porcentaje_max NUMERIC(5,2) NOT NULL,
    monto_bruto INTEGER NOT NULL,           -- Para dashboard web (col 1)
    liquido_aprox INTEGER NOT NULL,         -- Para app móvil (col 2)
    created_at TIMESTAMP DEFAULT NOW(),
    CONSTRAINT uq_escala_cal_rango UNIQUE(porcentaje_min, porcentaje_max)
);

COMMENT ON TABLE escala_calidad IS 
'Escala de bonos por calidad (% reiteración mensual)';

COMMENT ON COLUMN escala_calidad.monto_bruto IS 
'Monto bruto para mostrar en dashboard web';

COMMENT ON COLUMN escala_calidad.liquido_aprox IS 
'Líquido aproximado para mostrar en app móvil';

-- Tabla: Pagos calculados por técnico y período
CREATE TABLE IF NOT EXISTS pagos_tecnicos (
    id SERIAL PRIMARY KEY,
    rut_tecnico VARCHAR(12) NOT NULL,
    tecnico VARCHAR(255),
    periodo VARCHAR(7) NOT NULL,            -- Formato: YYYY-MM
    
    -- Producción
    rgu_promedio NUMERIC(4,2),              -- RGU promedio del mes
    bono_produccion_bruto INTEGER,          -- Para dashboard
    bono_produccion_liquido INTEGER,        -- Para app
    
    -- Calidad
    porcentaje_reiteracion NUMERIC(5,2),   -- % de reiteración
    bono_calidad_bruto INTEGER,             -- Para dashboard
    bono_calidad_liquido INTEGER,           -- Para app
    
    -- Totales
    total_bruto INTEGER,                    -- Suma de bonos brutos
    total_liquido INTEGER,                  -- Suma de bonos líquidos
    
    -- Metadata
    fecha_calculo TIMESTAMP DEFAULT NOW(),
    calculado_por VARCHAR(50) DEFAULT 'sistema',
    
    CONSTRAINT uq_pago_tecnico_periodo UNIQUE(rut_tecnico, periodo)
);

COMMENT ON TABLE pagos_tecnicos IS 
'Registro de pagos calculados por técnico y período (solo bonificaciones, sin sueldo base)';

-- Índices para optimizar consultas
CREATE INDEX IF NOT EXISTS idx_pagos_rut ON pagos_tecnicos(rut_tecnico);
CREATE INDEX IF NOT EXISTS idx_pagos_periodo ON pagos_tecnicos(periodo);
CREATE INDEX IF NOT EXISTS idx_pagos_rut_periodo ON pagos_tecnicos(rut_tecnico, periodo);

-- ═══════════════════════════════════════════════════════════════════
-- PASO 2: POBLAR ESCALAS CON DATOS REALES
-- ═══════════════════════════════════════════════════════════════════

-- Limpiar tablas si ya tienen datos
TRUNCATE TABLE escala_produccion RESTART IDENTITY CASCADE;
TRUNCATE TABLE escala_calidad RESTART IDENTITY CASCADE;

-- ESCALA DE PRODUCTIVIDAD (RGU)
INSERT INTO escala_produccion (rgu_min, rgu_max, monto_bruto, mano_obra, liquido_aprox) VALUES
(5.0, 5.0, 240000, 55385, 246154),
(5.1, 5.1, 270000, 62308, 276923),
(5.2, 5.2, 290000, 66923, 297436),
(5.3, 5.3, 310000, 71538, 317949),
(5.4, 5.4, 330000, 76154, 338462),
(5.5, 5.5, 350000, 80769, 358974),
(5.6, 5.6, 370000, 85385, 379487),
(5.7, 5.7, 390000, 90000, 400000),
(5.8, 5.8, 410000, 94615, 420513),
(5.9, 5.9, 430000, 99231, 441026),
(6.0, 6.0, 450000, 103846, 461538);

-- ESCALA DE CALIDAD (% Reiteración)
INSERT INTO escala_calidad (porcentaje_min, porcentaje_max, monto_bruto, liquido_aprox) VALUES
(0.00, 0.99, 240000, 200000),   -- Menos de 1%
(1.00, 1.99, 240000, 200000),   -- 1%
(2.00, 2.99, 240000, 200000),   -- 2%
(3.00, 3.99, 240000, 200000),   -- 3%
(4.00, 4.99, 240000, 200000),   -- 4% (CORREGIDO: era 200000)
(5.00, 5.99, 240000, 200000),   -- 5%
(6.00, 6.99, 180000, 150000),   -- 6%
(7.00, 7.99, 96000, 80000),     -- 7%
(8.00, 8.99, 84000, 70000),     -- 8%
(9.00, 9.99, 72000, 60000),     -- 9%
(10.00, 10.99, 60000, 50000),  -- 10%
(11.00, 100.00, 0, 0);          -- 11% o más = SIN BONO

-- ═══════════════════════════════════════════════════════════════════
-- PASO 3: FUNCIÓN PARA OBTENER BONO DE PRODUCCIÓN
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION obtener_bono_produccion(
    p_rgu_promedio NUMERIC
)
RETURNS TABLE (
    monto_bruto INTEGER,
    liquido_aprox INTEGER
) AS $$
BEGIN
    -- Truncar a 1 decimal (no redondear)
    -- Ejemplo: 5.56 → 5.5, 5.49 → 5.4
    p_rgu_promedio := TRUNC(p_rgu_promedio, 1);
    
    -- Buscar en la escala
    RETURN QUERY
    SELECT 
        e.monto_bruto,
        e.liquido_aprox
    FROM escala_produccion e
    WHERE p_rgu_promedio >= e.rgu_min 
      AND p_rgu_promedio <= e.rgu_max
    LIMIT 1;
    
    -- Si no encuentra, retornar 0
    IF NOT FOUND THEN
        RETURN QUERY SELECT 0::INTEGER, 0::INTEGER;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ═══════════════════════════════════════════════════════════════════
-- PASO 4: FUNCIÓN PARA OBTENER BONO DE CALIDAD
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION obtener_bono_calidad(
    p_porcentaje NUMERIC
)
RETURNS TABLE (
    monto_bruto INTEGER,
    liquido_aprox INTEGER
) AS $$
DECLARE
    v_monto_bruto INTEGER;
    v_liquido_aprox INTEGER;
BEGIN
    -- Las decimales NO se aproximan
    -- Ejemplo: 4.5% usa tramo de 4%, 3.8% usa tramo de 3%
    -- IMPORTANTE: Usar > en lugar de >= para el límite superior
    -- para evitar solapamiento entre rangos
    
    -- Buscar en la escala
    SELECT 
        e.monto_bruto,
        e.liquido_aprox
    INTO v_monto_bruto, v_liquido_aprox
    FROM escala_calidad e
    WHERE p_porcentaje >= e.porcentaje_min 
      AND p_porcentaje < e.porcentaje_max + 1
    ORDER BY e.porcentaje_min DESC
    LIMIT 1;
    
    -- Si no encuentra, retornar 0 (más de 11%)
    IF v_monto_bruto IS NULL THEN
        v_monto_bruto := 0;
        v_liquido_aprox := 0;
    END IF;
    
    RETURN QUERY SELECT v_monto_bruto, v_liquido_aprox;
END;
$$ LANGUAGE plpgsql;

-- ═══════════════════════════════════════════════════════════════════
-- PASO 5: FUNCIÓN PARA CALCULAR Y GUARDAR PAGO DE UN TÉCNICO
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION calcular_pago_tecnico(
    p_rut_tecnico VARCHAR,
    p_periodo VARCHAR,              -- Formato: '2026-01'
    p_rgu_promedio NUMERIC,         -- RGU promedio del mes
    p_porcentaje_reiteracion NUMERIC -- % de reiteración
)
RETURNS TABLE (
    bono_prod_bruto INTEGER,
    bono_prod_liquido INTEGER,
    bono_cal_bruto INTEGER,
    bono_cal_liquido INTEGER,
    total_bruto INTEGER,
    total_liquido INTEGER
) AS $$
DECLARE
    v_tecnico VARCHAR;
    v_bono_prod RECORD;
    v_bono_cal RECORD;
BEGIN
    -- Obtener nombre del técnico desde v_calidad_tecnicos
    SELECT DISTINCT tecnico INTO v_tecnico
    FROM v_calidad_tecnicos
    WHERE rut_tecnico = p_rut_tecnico
    LIMIT 1;
    
    -- Si no encuentra, usar nombre genérico
    IF v_tecnico IS NULL THEN
        v_tecnico := 'Técnico ' || p_rut_tecnico;
    END IF;
    
    -- Calcular bono de producción
    SELECT * INTO v_bono_prod FROM obtener_bono_produccion(p_rgu_promedio);
    
    -- Calcular bono de calidad
    SELECT * INTO v_bono_cal FROM obtener_bono_calidad(p_porcentaje_reiteracion);
    
    -- Guardar en tabla pagos_tecnicos (INSERT o UPDATE)
    INSERT INTO pagos_tecnicos (
        rut_tecnico,
        tecnico,
        periodo,
        rgu_promedio,
        bono_produccion_bruto,
        bono_produccion_liquido,
        porcentaje_reiteracion,
        bono_calidad_bruto,
        bono_calidad_liquido,
        total_bruto,
        total_liquido
    ) VALUES (
        p_rut_tecnico,
        v_tecnico,
        p_periodo,
        p_rgu_promedio,
        v_bono_prod.monto_bruto,
        v_bono_prod.liquido_aprox,
        p_porcentaje_reiteracion,
        v_bono_cal.monto_bruto,
        v_bono_cal.liquido_aprox,
        v_bono_prod.monto_bruto + v_bono_cal.monto_bruto,
        v_bono_prod.liquido_aprox + v_bono_cal.liquido_aprox
    )
    ON CONFLICT (rut_tecnico, periodo) 
    DO UPDATE SET
        tecnico = EXCLUDED.tecnico,
        rgu_promedio = EXCLUDED.rgu_promedio,
        bono_produccion_bruto = EXCLUDED.bono_produccion_bruto,
        bono_produccion_liquido = EXCLUDED.bono_produccion_liquido,
        porcentaje_reiteracion = EXCLUDED.porcentaje_reiteracion,
        bono_calidad_bruto = EXCLUDED.bono_calidad_bruto,
        bono_calidad_liquido = EXCLUDED.bono_calidad_liquido,
        total_bruto = EXCLUDED.total_bruto,
        total_liquido = EXCLUDED.total_liquido,
        fecha_calculo = NOW();
    
    -- Retornar resultados
    RETURN QUERY
    SELECT 
        v_bono_prod.monto_bruto,
        v_bono_prod.liquido_aprox,
        v_bono_cal.monto_bruto,
        v_bono_cal.liquido_aprox,
        v_bono_prod.monto_bruto + v_bono_cal.monto_bruto,
        v_bono_prod.liquido_aprox + v_bono_cal.liquido_aprox;
END;
$$ LANGUAGE plpgsql;

-- ═══════════════════════════════════════════════════════════════════
-- PASO 6: VISTA PARA DASHBOARD Y APP
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW v_pagos_tecnicos AS
SELECT 
    p.id,
    p.rut_tecnico,
    p.tecnico,
    p.periodo,
    
    -- Producción
    p.rgu_promedio,
    p.bono_produccion_bruto,
    p.bono_produccion_liquido,
    
    -- Calidad
    p.porcentaje_reiteracion,
    p.bono_calidad_bruto,
    p.bono_calidad_liquido,
    
    -- Totales
    p.total_bruto,
    p.total_liquido,
    
    -- Metadata
    p.fecha_calculo,
    
    -- Campos extras para ordenamiento y filtrado
    EXTRACT(YEAR FROM TO_DATE(p.periodo || '-01', 'YYYY-MM-DD')) AS anio,
    EXTRACT(MONTH FROM TO_DATE(p.periodo || '-01', 'YYYY-MM-DD')) AS mes
FROM pagos_tecnicos p
ORDER BY p.periodo DESC, p.total_liquido DESC;

COMMENT ON VIEW v_pagos_tecnicos IS 
'Vista de pagos con campos adicionales para dashboard y app';

-- ═══════════════════════════════════════════════════════════════════
-- ✅ VERIFICACIÓN Y EJEMPLOS
-- ═══════════════════════════════════════════════════════════════════

-- TEST 1: Verificar que las escalas se cargaron correctamente
SELECT 
    '✅ TEST 1: Escala Producción' AS test,
    COUNT(*) AS total_registros,
    MIN(rgu_min) AS rgu_minimo,
    MAX(rgu_max) AS rgu_maximo
FROM escala_produccion;

SELECT 
    '✅ TEST 1: Escala Calidad' AS test,
    COUNT(*) AS total_registros,
    MIN(porcentaje_min) AS porc_minimo,
    MAX(porcentaje_max) AS porc_maximo
FROM escala_calidad;

-- TEST 2: Probar función de bono producción (RGU 5.5)
SELECT 
    '✅ TEST 2: Bono Producción RGU 5.5' AS test,
    monto_bruto AS bruto_esperado_350000,
    liquido_aprox AS liquido_esperado_358974
FROM obtener_bono_produccion(5.5);

-- TEST 3: Probar función de bono calidad (3.8% usa tramo 3%)
SELECT 
    '✅ TEST 3: Bono Calidad 3.8%' AS test,
    monto_bruto AS bruto_esperado_240000,
    liquido_aprox AS liquido_esperado_200000
FROM obtener_bono_calidad(3.8);

-- TEST 4: Calcular pago completo de ejemplo
-- Técnico con RGU 5.5 y 3.8% reiteración
SELECT 
    '✅ TEST 4: Pago completo' AS test,
    bono_prod_bruto,
    bono_prod_liquido,
    bono_cal_bruto,
    bono_cal_liquido,
    total_bruto AS total_bruto_esperado_590000,
    total_liquido AS total_liquido_esperado_558974
FROM calcular_pago_tecnico(
    '12345678-9',  -- RUT ejemplo
    '2026-01',     -- Período
    5.5,           -- RGU promedio
    3.8            -- % reiteración
);

-- ═══════════════════════════════════════════════════════════════════
-- 📝 NOTAS DE USO
-- ═══════════════════════════════════════════════════════════════════
/*
CÓMO USAR ESTE SISTEMA:

1. Para calcular el pago de un técnico:
   SELECT * FROM calcular_pago_tecnico('15342161-7', '2026-01', 5.5, 3.8);

2. Para ver todos los pagos calculados:
   SELECT * FROM v_pagos_tecnicos;

3. Para ver pagos de un período específico:
   SELECT * FROM v_pagos_tecnicos WHERE periodo = '2026-01';

4. Para ver pagos de un técnico:
   SELECT * FROM v_pagos_tecnicos WHERE rut_tecnico = '15342161-7';

5. Para el dashboard web (usar columnas *_bruto):
   SELECT rut_tecnico, tecnico, periodo, 
          bono_produccion_bruto, bono_calidad_bruto, total_bruto
   FROM v_pagos_tecnicos;

6. Para la app móvil (usar columnas *_liquido):
   SELECT rut_tecnico, tecnico, periodo,
          bono_produccion_liquido, bono_calidad_liquido, total_liquido
   FROM v_pagos_tecnicos;
*/


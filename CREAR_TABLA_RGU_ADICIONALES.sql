-- ═══════════════════════════════════════════════════════════════════
-- 📊 TABLA: RGU Adicionales (Compensaciones especiales)
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS rgu_adicionales (
    id SERIAL PRIMARY KEY,
    rut_tecnico VARCHAR(20) NOT NULL,
    mes VARCHAR(7) NOT NULL,  -- Formato: YYYY-MM (ej: 2025-12)
    rgu_adicional NUMERIC(10,2) NOT NULL,  -- Puede ser positivo o negativo
    motivo TEXT NOT NULL,
    usuario_autorizo VARCHAR(50) NOT NULL,
    fecha_creacion TIMESTAMP DEFAULT NOW(),
    fecha_modificacion TIMESTAMP,
    
    -- Índices para búsqueda rápida
    CONSTRAINT unique_rgu_adicional UNIQUE (id)
);

-- Índices
CREATE INDEX idx_rgu_adicionales_rut ON rgu_adicionales(rut_tecnico);
CREATE INDEX idx_rgu_adicionales_mes ON rgu_adicionales(mes);
CREATE INDEX idx_rgu_adicionales_rut_mes ON rgu_adicionales(rut_tecnico, mes);

-- Comentarios
COMMENT ON TABLE rgu_adicionales IS 'RGU adicionales/compensaciones especiales por técnico y mes';
COMMENT ON COLUMN rgu_adicionales.rgu_adicional IS 'Cantidad de RGU a sumar (positivo) o restar (negativo)';
COMMENT ON COLUMN rgu_adicionales.motivo IS 'Razón de la compensación';

-- ═══════════════════════════════════════════════════════════════════
-- 🔍 VISTA: Resumen de RGU adicionales por técnico y mes
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW v_rgu_adicionales_resumen AS
SELECT 
    rut_tecnico,
    mes,
    SUM(rgu_adicional) as total_rgu_adicional,
    COUNT(*) as cantidad_ajustes,
    STRING_AGG(motivo, ' | ' ORDER BY fecha_creacion) as motivos,
    MAX(fecha_creacion) as ultima_modificacion
FROM rgu_adicionales
GROUP BY rut_tecnico, mes;

COMMENT ON VIEW v_rgu_adicionales_resumen IS 'Resumen de RGU adicionales agrupados por técnico y mes';

-- ═══════════════════════════════════════════════════════════════════
-- 🧪 DATOS DE PRUEBA (Opcional - comentar si no se necesitan)
-- ═══════════════════════════════════════════════════════════════════

-- Ejemplo: Agregar 5 RGU adicionales a Felipe Plaza en diciembre 2025
-- INSERT INTO rgu_adicionales (rut_tecnico, mes, rgu_adicional, motivo, usuario_autorizo)
-- VALUES ('15342161-7', '2025-12', 5.0, 'Instalación compleja Edificio Norte', 'rfelipe');

-- Ejemplo: Restar 2 RGU por error de ingreso
-- INSERT INTO rgu_adicionales (rut_tecnico, mes, rgu_adicional, motivo, usuario_autorizo)
-- VALUES ('15342161-7', '2025-12', -2.0, 'Corrección error de ingreso', 'rfelipe');

-- ═══════════════════════════════════════════════════════════════════
-- ✅ VERIFICACIÓN
-- ═══════════════════════════════════════════════════════════════════

-- Ver todos los ajustes
SELECT * FROM rgu_adicionales ORDER BY fecha_creacion DESC;

-- Ver resumen por técnico
SELECT * FROM v_rgu_adicionales_resumen;





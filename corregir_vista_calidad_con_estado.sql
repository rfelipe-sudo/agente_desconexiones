-- ═══════════════════════════════════════════════════════════════════
-- CORRECCIÓN: Vista v_calidad_detalle con estado_garantia
-- ═══════════════════════════════════════════════════════════════════
-- PROBLEMA: dias_reiterado = 30 estaba marcando como 'NO' cuando debe ser 'SI'
-- SOLUCIÓN: Usar <= 30 (no < 30)
-- ═══════════════════════════════════════════════════════════════════

DROP VIEW IF EXISTS v_calidad_detalle CASCADE;

CREATE OR REPLACE VIEW v_calidad_detalle AS
SELECT 
  id,
  created_at,
  tecnico_original,
  codigo_tecnico_original,
  rut_tecnico_original,
  orden_original,
  fecha_original,
  tipo_actividad,
  subtipo,
  cliente,
  numero_cliente,
  direccion,
  ciudad,
  zona_trabajo,
  tipo_vivienda,
  tecnico_reiterado,
  orden_reiterada,
  fecha_reiterada,
  descripcion_reiterado,
  codigo_cierre_reiterado,
  notas_cierre_reiterado,
  fecha_reserva_reiterado,
  dias_reiterado,
  
  -- ✅ CAMPO 1: ¿Cuenta para calidad? (dentro de 30 días inclusive)
  CASE 
    WHEN dias_reiterado <= 30 THEN 'SI'
    ELSE 'NO'
  END AS cuenta_para_calidad,
  
  -- ✅ CAMPO 2: Estado de garantía
  CASE 
    WHEN dias_reiterado <= 30 THEN 'DENTRO DE GARANTÍA'
    ELSE 'FUERA DE GARANTÍA'
  END AS estado_garantia

FROM calidad_crea
ORDER BY fecha_original DESC;

-- ═══════════════════════════════════════════════════════════════════
-- COMENTARIOS
-- ═══════════════════════════════════════════════════════════════════

COMMENT ON VIEW v_calidad_detalle IS 
'Vista que agrega cuenta_para_calidad y estado_garantia basado en si el reiterado ocurrió dentro de 30 días';

COMMENT ON COLUMN v_calidad_detalle.cuenta_para_calidad IS 
'Indica si el reiterado cuenta para calidad: SI (≤30 días) o NO (>30 días)';

COMMENT ON COLUMN v_calidad_detalle.estado_garantia IS 
'Estado de garantía: DENTRO DE GARANTÍA (≤30 días) o FUERA DE GARANTÍA (>30 días)';

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN: Orden específica 1-3GELJ7R3 (debe mostrar SI / DENTRO)
-- ═══════════════════════════════════════════════════════════════════

SELECT 
  orden_original,
  fecha_original,
  fecha_reiterada,
  dias_reiterado,
  cuenta_para_calidad,
  estado_garantia
FROM v_calidad_detalle
WHERE orden_original = '1-3GELJ7R3';

-- RESULTADO ESPERADO:
-- orden_original | fecha_original | fecha_reiterada | dias_reiterado | cuenta_para_calidad | estado_garantia
-- 1-3GELJ7R3     | 2025-12-02     | 2026-01-02      | 30             | SI                  | DENTRO DE GARANTÍA

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN: Casos límite (29, 30, 31 días)
-- ═══════════════════════════════════════════════════════════════════

SELECT 
  dias_reiterado,
  cuenta_para_calidad,
  estado_garantia,
  COUNT(*) as cantidad
FROM v_calidad_detalle
WHERE dias_reiterado BETWEEN 29 AND 31
GROUP BY dias_reiterado, cuenta_para_calidad, estado_garantia
ORDER BY dias_reiterado;

-- RESULTADO ESPERADO:
-- dias_reiterado | cuenta_para_calidad | estado_garantia     | cantidad
-- 29             | SI                  | DENTRO DE GARANTÍA  | X
-- 30             | SI                  | DENTRO DE GARANTÍA  | X
-- 31             | NO                  | FUERA DE GARANTÍA   | X

-- ═══════════════════════════════════════════════════════════════════
-- Vista alternativa para el dashboard (si la necesitas)
-- ═══════════════════════════════════════════════════════════════════

DROP VIEW IF EXISTS v_calidad_tecnicos CASCADE;

CREATE OR REPLACE VIEW v_calidad_tecnicos AS
SELECT 
  rut_tecnico_original,
  tecnico_original,
  COUNT(*) as total_reiterados,
  COUNT(*) FILTER (WHERE dias_reiterado <= 30) as reiterados_en_garantia,
  COUNT(*) FILTER (WHERE dias_reiterado > 30) as reiterados_fuera_garantia,
  ROUND(
    COUNT(*) FILTER (WHERE dias_reiterado <= 30)::NUMERIC / 
    NULLIF(COUNT(*), 0) * 100, 
    2
  ) as porcentaje_en_garantia
FROM calidad_crea
GROUP BY rut_tecnico_original, tecnico_original
ORDER BY total_reiterados DESC;

COMMENT ON VIEW v_calidad_tecnicos IS 
'Vista agregada por técnico con estadísticas de calidad';

-- ═══════════════════════════════════════════════════════════════════
-- TEST FINAL: Verificar que TODO esté correcto
-- ═══════════════════════════════════════════════════════════════════

-- Total de registros por clasificación
SELECT 
  'RESUMEN GENERAL' as tipo,
  COUNT(*) as total,
  COUNT(*) FILTER (WHERE cuenta_para_calidad = 'SI') as cuenta_si,
  COUNT(*) FILTER (WHERE cuenta_para_calidad = 'NO') as cuenta_no,
  COUNT(*) FILTER (WHERE estado_garantia = 'DENTRO DE GARANTÍA') as dentro_garantia,
  COUNT(*) FILTER (WHERE estado_garantia = 'FUERA DE GARANTÍA') as fuera_garantia
FROM v_calidad_detalle;

-- NOTA: cuenta_si debe ser igual a dentro_garantia
-- NOTA: cuenta_no debe ser igual a fuera_garantia





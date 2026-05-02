-- ============================================
-- DIAGNÓSTICO: cuenta_para_calidad
-- ============================================
-- Verificar la orden específica: 1-3GELJ7R3

-- PASO 1: Ver el registro RAW de la tabla
SELECT 
  'Tabla calidad_crea (RAW)' as fuente,
  orden_original,
  fecha_original,
  fecha_reiterada,
  dias_reiterado,
  'N/A' as cuenta_para_calidad_calculado
FROM calidad_crea
WHERE orden_original = '1-3GELJ7R3';

-- PASO 2: Ver el mismo registro desde la VISTA (con campo calculado)
SELECT 
  'Vista v_calidad_detalle (CALCULADO)' as fuente,
  orden_original,
  fecha_original,
  fecha_reiterada,
  dias_reiterado,
  cuenta_para_calidad as cuenta_para_calidad_calculado
FROM v_calidad_detalle
WHERE orden_original = '1-3GELJ7R3';

-- ============================================
-- PASO 3: Ver TODOS los registros con 30 días
-- ============================================
SELECT 
  'Registros con exactamente 30 días' as descripcion,
  COUNT(*) as total,
  COUNT(*) FILTER (WHERE cuenta_para_calidad = 'SI') as con_si,
  COUNT(*) FILTER (WHERE cuenta_para_calidad = 'NO') as con_no
FROM v_calidad_detalle
WHERE dias_reiterado = 30;

-- ============================================
-- PASO 4: Ver distribución de días y su clasificación
-- ============================================
SELECT 
  dias_reiterado,
  cuenta_para_calidad,
  COUNT(*) as cantidad,
  STRING_AGG(DISTINCT orden_original, ', ') as ordenes_ejemplo
FROM v_calidad_detalle
WHERE dias_reiterado BETWEEN 28 AND 32
GROUP BY dias_reiterado, cuenta_para_calidad
ORDER BY dias_reiterado, cuenta_para_calidad;

-- ============================================
-- PASO 5: Verificar si existe OTRA vista con lógica diferente
-- ============================================
-- Buscar todas las vistas que contengan "calidad" en el nombre
SELECT 
  table_name,
  view_definition
FROM information_schema.views
WHERE table_schema = 'public'
  AND table_name LIKE '%calidad%';





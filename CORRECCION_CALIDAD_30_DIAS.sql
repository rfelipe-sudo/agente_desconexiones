-- ═══════════════════════════════════════════════════════════════════
-- ⚠️ CORRECCIÓN URGENTE: Vista v_calidad_detalle
-- ═══════════════════════════════════════════════════════════════════
-- PROBLEMA: Registros con exactamente 30 días NO cuentan para calidad
-- CAUSA: Lógica incorrecta (< 30 en lugar de <= 30)
-- SOLUCIÓN: Recrear vista con lógica correcta
-- ═══════════════════════════════════════════════════════════════════

-- PASO 1: Eliminar vista actual
DROP VIEW IF EXISTS v_calidad_detalle CASCADE;

-- PASO 2: Crear vista CORREGIDA
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
  
  -- ✅ CORREGIDO: Ahora usa <= 30 (incluye 30 días)
  CASE 
    WHEN dias_reiterado <= 30 THEN 'SÍ'
    ELSE 'NO'
  END AS cuenta_para_calidad,
  
  -- ✅ NUEVO: Campo estado_garantia
  CASE 
    WHEN dias_reiterado <= 30 THEN 'DENTRO DE GARANTÍA'
    ELSE 'FUERA DE GARANTÍA'
  END AS estado_garantia

FROM calidad_crea
ORDER BY fecha_original DESC;

-- PASO 3: Agregar comentarios
COMMENT ON VIEW v_calidad_detalle IS 
'Vista con cuenta_para_calidad y estado_garantia. Reiterados dentro de 30 días (inclusive) cuentan para calidad.';

COMMENT ON COLUMN v_calidad_detalle.cuenta_para_calidad IS 
'SÍ si dias_reiterado ≤ 30, NO si > 30';

COMMENT ON COLUMN v_calidad_detalle.estado_garantia IS 
'DENTRO DE GARANTÍA si ≤ 30 días, FUERA DE GARANTÍA si > 30 días';

-- ═══════════════════════════════════════════════════════════════════
-- ✅ VERIFICACIÓN INMEDIATA
-- ═══════════════════════════════════════════════════════════════════

-- Verificar la orden problemática (debe mostrar SÍ / DENTRO DE GARANTÍA)
SELECT 
  '✅ TEST 1: Orden específica' as test,
  orden_original,
  fecha_original,
  fecha_reiterada,
  dias_reiterado,
  cuenta_para_calidad,
  estado_garantia
FROM v_calidad_detalle
WHERE orden_original = '1-3GELJ7R3';

-- Verificar casos límite (29, 30, 31 días)
SELECT 
  '✅ TEST 2: Casos límite' as test,
  dias_reiterado,
  cuenta_para_calidad,
  estado_garantia,
  COUNT(*) as cantidad
FROM v_calidad_detalle
WHERE dias_reiterado BETWEEN 29 AND 31
GROUP BY dias_reiterado, cuenta_para_calidad, estado_garantia
ORDER BY dias_reiterado;

-- Resumen general
SELECT 
  '✅ TEST 3: Resumen general' as test,
  COUNT(*) as total_registros,
  COUNT(*) FILTER (WHERE cuenta_para_calidad = 'SÍ') as cuentan_si,
  COUNT(*) FILTER (WHERE cuenta_para_calidad = 'NO') as cuentan_no,
  COUNT(*) FILTER (WHERE dias_reiterado = 30) as con_30_dias,
  COUNT(*) FILTER (WHERE dias_reiterado = 30 AND cuenta_para_calidad = 'SÍ') as con_30_dias_que_cuentan
FROM v_calidad_detalle;

-- ═══════════════════════════════════════════════════════════════════
-- ✅ RESULTADOS ESPERADOS
-- ═══════════════════════════════════════════════════════════════════
/*
TEST 1 (Orden 1-3GELJ7R3):
  dias_reiterado: 30
  cuenta_para_calidad: SÍ  ✅
  estado_garantia: DENTRO DE GARANTÍA  ✅

TEST 2 (Casos límite):
  29 días → SÍ / DENTRO DE GARANTÍA
  30 días → SÍ / DENTRO DE GARANTÍA  ✅ (ESTE ERA EL QUE ESTABA MAL)
  31 días → NO / FUERA DE GARANTÍA

TEST 3 (Resumen):
  con_30_dias_que_cuentan debe ser IGUAL a con_30_dias
  (Todos los de 30 días deben contar)
*/





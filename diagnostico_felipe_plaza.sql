-- ═══════════════════════════════════════════════════════════════════
-- DIAGNÓSTICO: Felipe Plaza - Reiterados por período
-- ═══════════════════════════════════════════════════════════════════

-- PASO 1: Encontrar el RUT de Felipe Plaza
SELECT DISTINCT
  rut_tecnico_original,
  tecnico_original
FROM v_calidad_detalle
WHERE tecnico_original ILIKE '%felipe%plaza%'
   OR tecnico_original ILIKE '%plaza%felipe%';

-- ═══════════════════════════════════════════════════════════════════
-- PASO 2: Ver TODOS los reiterados de Felipe Plaza (sin filtros)
-- ═══════════════════════════════════════════════════════════════════
-- Reemplaza 'XX' con el RUT que encontraste arriba

SELECT 
  'TODOS LOS REITERADOS (histórico completo)' as info,
  orden_original,
  fecha_original,
  fecha_reiterada,
  dias_reiterado,
  cuenta_para_calidad,
  tipo_actividad
FROM v_calidad_detalle
WHERE rut_tecnico_original = '15342161-7'  -- ← Ajusta este RUT
ORDER BY fecha_original DESC;

-- ═══════════════════════════════════════════════════════════════════
-- PASO 3: Reiterados por PERÍODO DE TRABAJO (lógica de bonos)
-- ═══════════════════════════════════════════════════════════════════

-- 📅 BONO DICIEMBRE (trabajos del 21 OCT al 20 NOV, reiterados hasta 20 DIC)
SELECT 
  'BONO DICIEMBRE (21 OCT - 20 NOV)' as periodo,
  COUNT(*) as total_reiterados,
  STRING_AGG(orden_original, ', ' ORDER BY fecha_original) as ordenes
FROM v_calidad_detalle
WHERE rut_tecnico_original = '15342161-7'
  AND cuenta_para_calidad = 'SÍ'
  AND fecha_original >= '2025-10-21'
  AND fecha_original <= '2025-11-20';

-- 📅 BONO ENERO (trabajos del 21 NOV al 20 DIC, reiterados hasta 20 ENE)
SELECT 
  'BONO ENERO (21 NOV - 20 DIC)' as periodo,
  COUNT(*) as total_reiterados,
  STRING_AGG(orden_original, ', ' ORDER BY fecha_original) as ordenes
FROM v_calidad_detalle
WHERE rut_tecnico_original = '15342161-7'
  AND cuenta_para_calidad = 'SÍ'
  AND fecha_original >= '2025-11-21'
  AND fecha_original <= '2025-12-20';

-- 📅 BONO FEBRERO (trabajos del 21 DIC al 20 ENE, reiterados hasta 20 FEB)
SELECT 
  'BONO FEBRERO (21 DIC - 20 ENE)' as periodo,
  COUNT(*) as total_reiterados,
  STRING_AGG(orden_original, ', ' ORDER BY fecha_original) as ordenes
FROM v_calidad_detalle
WHERE rut_tecnico_original = '15342161-7'
  AND cuenta_para_calidad = 'SÍ'
  AND fecha_original >= '2025-12-21'
  AND fecha_original <= '2026-01-20';

-- ═══════════════════════════════════════════════════════════════════
-- PASO 4: Detalle completo de ENERO (el que está fallando)
-- ═══════════════════════════════════════════════════════════════════

SELECT 
  '🔍 DETALLE BONO ENERO' as info,
  orden_original,
  fecha_original,
  fecha_reiterada,
  dias_reiterado,
  cuenta_para_calidad,
  tipo_actividad,
  cliente
FROM v_calidad_detalle
WHERE rut_tecnico_original = '15342161-7'
  AND cuenta_para_calidad = 'SÍ'
  AND fecha_original >= '2025-11-21'
  AND fecha_original <= '2025-12-20'
ORDER BY fecha_original;

-- ═══════════════════════════════════════════════════════════════════
-- PASO 5: Ver si hay registros que NO cuentan (debugging)
-- ═══════════════════════════════════════════════════════════════════

SELECT 
  '⚠️ REGISTROS QUE NO CUENTAN' as info,
  orden_original,
  fecha_original,
  dias_reiterado,
  cuenta_para_calidad,
  CASE 
    WHEN cuenta_para_calidad = 'NO' THEN '❌ Fuera de garantía (>30 días)'
    ELSE '✅ OK'
  END as motivo
FROM v_calidad_detalle
WHERE rut_tecnico_original = '15342161-7'
  AND cuenta_para_calidad = 'NO';

-- ═══════════════════════════════════════════════════════════════════
-- PASO 6: Resumen por mes calendario (para comparar)
-- ═══════════════════════════════════════════════════════════════════

SELECT 
  DATE_TRUNC('month', fecha_original::timestamp) as mes,
  COUNT(*) as total_reiterados,
  COUNT(*) FILTER (WHERE cuenta_para_calidad = 'SÍ') as cuentan,
  STRING_AGG(orden_original, ', ' ORDER BY fecha_original) as ordenes
FROM v_calidad_detalle
WHERE rut_tecnico_original = '15342161-7'
GROUP BY DATE_TRUNC('month', fecha_original::timestamp)
ORDER BY mes DESC;





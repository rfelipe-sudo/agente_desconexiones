-- ═══════════════════════════════════════════════════════════════════
-- 🔍 VERIFICAR: ¿Cuáles de las 43 órdenes de Ronald SON reiteraciones?
-- ═══════════════════════════════════════════════════════════════════

-- HIPÓTESIS: Las 3 órdenes que son "reiteradas" están en calidad_crea
-- como órdenes que Ronald atendió DESPUÉS de que alguien (él mismo u otro técnico)
-- las atendiera la primera vez

-- 1. Ver las 3 reiteraciones de Ronald según calidad_crea
SELECT 
    '🔴 Órdenes REITERADAS de Ronald (según calidad_crea)' AS diagnostico,
    orden_original,
    fecha_original,
    orden_reiterada,
    fecha_reiterada,
    rut_tecnico_original,
    dias_reiterado
FROM calidad_crea
WHERE rut_tecnico_original = '25861660-K'
  AND fecha_original >= '2025-11-21'
  AND fecha_original <= '2025-12-20'
  AND dias_reiterado <= 30
ORDER BY fecha_original;

-- 2. ¿Cuáles de las 43 órdenes de Ronald en produccion_crea coinciden con orden_original en calidad_crea?
SELECT 
    '🔍 Órdenes de Ronald que CAUSARON una reiteración' AS diagnostico,
    pc.orden_trabajo AS orden_en_produccion,
    pc.fecha_trabajo AS fecha_en_produccion,
    cc.orden_reiterada AS orden_reiterada,
    cc.fecha_reiterada AS fecha_reiterada
FROM produccion_crea pc
INNER JOIN calidad_crea cc ON cc.orden_original = pc.orden_trabajo
WHERE pc.rut_tecnico = '25861660-K'
  AND pc.estado = 'Completado'
  AND (
      (pc.fecha_trabajo LIKE '%/11/2025' AND CAST(SPLIT_PART(pc.fecha_trabajo, '/', 1) AS INTEGER) >= 21)
      OR
      (pc.fecha_trabajo LIKE '%/12/2025' AND CAST(SPLIT_PART(pc.fecha_trabajo, '/', 1) AS INTEGER) <= 20)
  )
  AND cc.rut_tecnico_original = '25861660-K'
ORDER BY pc.fecha_trabajo;

-- 3. PREGUNTA CLAVE: ¿El panel está EXCLUYENDO estas 3 órdenes del conteo?
-- Si el panel muestra 40 en lugar de 43, debe estar excluyendo las órdenes que tienen reiteración

SELECT 
    '📊 CONTAR: Órdenes SIN reiteración vs CON reiteración' AS diagnostico,
    COUNT(*) AS total_ordenes_43,
    COUNT(*) FILTER (WHERE cc.orden_original IS NULL) AS ordenes_sin_reiteracion,
    COUNT(*) FILTER (WHERE cc.orden_original IS NOT NULL) AS ordenes_con_reiteracion
FROM produccion_crea pc
LEFT JOIN calidad_crea cc 
    ON cc.orden_original = pc.orden_trabajo 
    AND cc.rut_tecnico_original = '25861660-K'
WHERE pc.rut_tecnico = '25861660-K'
  AND pc.estado = 'Completado'
  AND (
      (pc.fecha_trabajo LIKE '%/11/2025' AND CAST(SPLIT_PART(pc.fecha_trabajo, '/', 1) AS INTEGER) >= 21)
      OR
      (pc.fecha_trabajo LIKE '%/12/2025' AND CAST(SPLIT_PART(pc.fecha_trabajo, '/', 1) AS INTEGER) <= 20)
  );

-- ═══════════════════════════════════════════════════════════════════
-- EXPLICACIÓN
-- ═══════════════════════════════════════════════════════════════════
/*
Si el resultado 3 muestra:
- total_ordenes_43: 43
- ordenes_sin_reiteracion: 40
- ordenes_con_reiteracion: 3

Entonces la lógica correcta es:
- CONTAR órdenes que NO tienen reiteración (40)
- CONTAR reiteraciones separadamente (3)
- % reiteración = 3 / 40 = 7.5%

La vista v_calidad_tecnicos debe:
1. Contar SOLO órdenes que NO tienen reiteración en calidad_crea
2. Contar las reiteraciones por separado
3. Calcular porcentaje como: reiteraciones / ordenes_sin_reiteracion
*/




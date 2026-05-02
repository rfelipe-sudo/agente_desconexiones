-- ═══════════════════════════════════════════════════════════════════
-- 🔍 VERIFICAR: ¿Cómo se calcula el RGU de Francisco?
-- ═══════════════════════════════════════════════════════════════════

-- 1. RGU TOTAL en diciembre (1-31 Dic)
SELECT 
    '📊 Francisco - Diciembre 2025 (1-31 Dic)' AS periodo,
    COUNT(*) AS total_ordenes,
    SUM(rgu_total) AS suma_rgu_total,
    AVG(rgu_total) AS promedio_rgu_por_orden,
    COUNT(DISTINCT fecha_trabajo) AS dias_trabajados,
    SUM(rgu_total) / NULLIF(COUNT(DISTINCT fecha_trabajo), 0) AS rgu_promedio_diario
FROM produccion_crea
WHERE rut_tecnico = '15848521-4'
  AND estado = 'Completado'
  AND fecha_trabajo LIKE '%/12/2025'
  AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) BETWEEN 1 AND 31;

-- 2. RGU ANTES (¿qué había guardado antes?)
SELECT 
    '💾 Francisco - Datos guardados en pagos_tecnicos' AS fuente,
    rgu_promedio,
    fecha_calculo,
    calculado_por
FROM pagos_tecnicos
WHERE rut_tecnico = '15848521-4'
  AND periodo = '2026-01';

-- 3. Ver qué está calculando la función obtener_rgu_promedio_simple
-- (necesitamos simular la función)
WITH datos_produccion AS (
    SELECT 
        rut_tecnico,
        fecha_trabajo,
        SUM(rgu_total) AS rgu_dia
    FROM produccion_crea
    WHERE rut_tecnico = '15848521-4'
      AND estado = 'Completado'
      AND fecha_trabajo LIKE '%/12/2025'
      AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) BETWEEN 1 AND 31
    GROUP BY rut_tecnico, fecha_trabajo
)
SELECT 
    '🔍 Francisco - Cálculo manual como la función' AS metodo,
    COUNT(*) AS dias_trabajados,
    SUM(rgu_dia) AS rgu_total_mes,
    AVG(rgu_dia) AS rgu_promedio_diario
FROM datos_produccion;

-- 4. Ver todas las órdenes de Francisco en diciembre
SELECT 
    '📋 Francisco - Todas las órdenes de Diciembre' AS detalle,
    fecha_trabajo,
    COUNT(*) AS ordenes_del_dia,
    SUM(rgu_total) AS rgu_del_dia
FROM produccion_crea
WHERE rut_tecnico = '15848521-4'
  AND estado = 'Completado'
  AND fecha_trabajo LIKE '%/12/2025'
  AND CAST(SPLIT_PART(fecha_trabajo, '/', 1) AS INTEGER) BETWEEN 1 AND 31
GROUP BY fecha_trabajo
ORDER BY TO_DATE(fecha_trabajo, 'DD/MM/YYYY');

-- 5. Verificar si la función obtener_rgu_promedio_simple está funcionando
SELECT 
    '🔧 Test función obtener_rgu_promedio_simple' AS test,
    *
FROM obtener_rgu_promedio_simple('15848521-4', 12, 2025);

-- ═══════════════════════════════════════════════════════════════════
-- EXPLICACIÓN
-- ═══════════════════════════════════════════════════════════════════
/*
LÓGICA ESPERADA:
- Francisco tiene 100 órdenes en diciembre
- RGU total: ~155
- Días trabajados: ~25 días
- RGU promedio diario: 155 / 25 = 6.2

PERO si la función está sumando RGU_TOTAL de cada orden:
- Cada orden tiene rgu_total (que ya es un promedio)
- Sumar 100 órdenes con rgu_total = 1.55 c/u → suma = 155
- Promedio: 155 / 25 días = 6.2 ✅

El problema puede ser que rgu_total en cada orden YA es un cálculo,
no es el RGU "crudo" que se debe sumar.
*/




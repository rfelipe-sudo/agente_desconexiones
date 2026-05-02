-- ═══════════════════════════════════════════════════════════════════
-- 🔍 DIAGNÓSTICO: ¿Por qué Felipe Plaza tiene 0 días trabajados?
-- ═══════════════════════════════════════════════════════════════════

-- 1️⃣ ¿Existe Felipe Plaza en produccion_crea?
SELECT 
    '1️⃣ ¿Existe Felipe en produccion_crea?' AS test,
    COUNT(*) AS total_registros
FROM produccion_crea
WHERE rut_tecnico = '15342161-7';

-- 2️⃣ ¿Qué fechas tiene Felipe en diciembre 2025?
SELECT 
    '2️⃣ Fechas de Felipe en Dic 2025' AS test,
    fecha_trabajo,
    COUNT(*) AS ordenes
FROM produccion_crea
WHERE rut_tecnico = '15342161-7'
  AND (
    fecha_trabajo LIKE '%/12/25'
    OR fecha_trabajo LIKE '%/12/2025'
  )
GROUP BY fecha_trabajo
ORDER BY fecha_trabajo;

-- 3️⃣ Ver formato de fecha_trabajo en produccion_crea
SELECT 
    '3️⃣ Formato de fechas' AS test,
    fecha_trabajo,
    estado,
    rgu_total
FROM produccion_crea
WHERE rut_tecnico = '15342161-7'
LIMIT 10;

-- 4️⃣ ¿Qué estados tienen las órdenes de Felipe?
SELECT 
    '4️⃣ Estados de órdenes Felipe' AS test,
    estado,
    COUNT(*) AS cantidad
FROM produccion_crea
WHERE rut_tecnico = '15342161-7'
GROUP BY estado
ORDER BY cantidad DESC;

-- 5️⃣ Probar la función con LIKE manual (formato correcto)
SELECT 
    '5️⃣ Test LIKE manual (formato viejo DD/MM/YY)' AS test,
    COUNT(DISTINCT fecha_trabajo) AS dias_unicos
FROM produccion_crea
WHERE rut_tecnico = '15342161-7'
  AND fecha_trabajo LIKE '%/12/25';

-- 5️⃣b Test con formato correcto DD/MM/YYYY
SELECT 
    '5️⃣b Test LIKE correcto (DD/MM/YYYY)' AS test,
    COUNT(DISTINCT fecha_trabajo) AS dias_unicos
FROM produccion_crea
WHERE rut_tecnico = '15342161-7'
  AND fecha_trabajo LIKE '%/12/2025';

-- 6️⃣ Ver todas las fechas de Felipe (sin filtro)
SELECT 
    '6️⃣ Todas las fechas Felipe' AS test,
    SUBSTRING(fecha_trabajo FROM LENGTH(fecha_trabajo) - 4) AS year_month,
    COUNT(*) AS ordenes
FROM produccion_crea
WHERE rut_tecnico = '15342161-7'
GROUP BY SUBSTRING(fecha_trabajo FROM LENGTH(fecha_trabajo) - 4)
ORDER BY year_month DESC;

-- 7️⃣ Verificar que la tabla correcta está siendo usada
SELECT 
    '7️⃣ Tablas de producción existentes' AS test,
    table_name
FROM information_schema.tables
WHERE table_name LIKE '%produccion%'
  AND table_schema = 'public';

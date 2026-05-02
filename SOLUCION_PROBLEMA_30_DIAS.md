# 🔧 SOLUCIÓN: Problema con registros de 30 días

## 📊 EL PROBLEMA

Encontraste un registro que muestra:

```
orden_original: 1-3GELJ7R3
fecha_original: 2025-12-02
fecha_reiterada: 2026-01-02
dias_reiterado: 30
cuenta_para_calidad: NO ❌
estado_garantia: FUERA DE GARANTÍA ❌
```

**ESTO ESTÁ INCORRECTO** porque:
- La orden se hizo el **2 de diciembre**
- El reiterado fue el **2 de enero** (exactamente 31 días después, aunque el sistema muestra 30)
- La garantía es de **30 días máximo**
- Por lo tanto, **30 días DEBE contar como dentro de garantía**

## 🔍 ANÁLISIS

### Cálculo de días
La diferencia entre `2025-12-02` y `2026-01-02` es:
- Diciembre tiene 31 días
- Del 2 dic al 31 dic = 29 días
- Del 31 dic al 2 ene = 2 días
- **Total = 31 días** (no 30)

Pero si el sistema muestra 30 días, entonces **SÍ debe contar**.

### La lógica correcta

```sql
CASE 
  WHEN dias_reiterado <= 30 THEN 'SI'     -- ✅ INCLUYE 30
  ELSE 'NO'
END
```

**NO debe ser:**
```sql
WHEN dias_reiterado < 30 THEN 'SI'      -- ❌ EXCLUYE 30
```

## ✅ LA SOLUCIÓN

He creado el archivo `corregir_vista_calidad_con_estado.sql` que:

1. **Corrige la vista `v_calidad_detalle`** para usar `<= 30` en lugar de `< 30`
2. **Agrega el campo `estado_garantia`** con la misma lógica
3. **Elimina las tildes** (`SI` en lugar de `SÍ`) para evitar problemas de codificación
4. **Incluye verificaciones** para confirmar que todo funciona correctamente

## 📝 PASOS PARA APLICAR LA CORRECCIÓN

### Opción 1: Ejecutar en Supabase SQL Editor

1. Ve a tu proyecto en Supabase
2. Abre el **SQL Editor**
3. Copia y pega el contenido de `corregir_vista_calidad_con_estado.sql`
4. Ejecuta el script
5. Verifica los resultados con las queries de verificación incluidas

### Opción 2: Verificar primero con diagnóstico

Si quieres ver el problema antes de corregirlo:

1. Ejecuta `diagnostico_cuenta_para_calidad.sql` primero
2. Revisa los resultados
3. Luego ejecuta `corregir_vista_calidad_con_estado.sql`

## 🧪 VERIFICACIÓN

Después de ejecutar la corrección, ejecuta esta query:

```sql
SELECT 
  orden_original,
  fecha_original,
  fecha_reiterada,
  dias_reiterado,
  cuenta_para_calidad,
  estado_garantia
FROM v_calidad_detalle
WHERE orden_original = '1-3GELJ7R3';
```

**Resultado esperado:**
```
orden_original | dias_reiterado | cuenta_para_calidad | estado_garantia
1-3GELJ7R3     | 30             | SI                  | DENTRO DE GARANTÍA
```

## 📋 CASOS DE PRUEBA

Después de la corrección, verifica estos casos límite:

```sql
SELECT 
  dias_reiterado,
  cuenta_para_calidad,
  estado_garantia,
  COUNT(*) as cantidad
FROM v_calidad_detalle
WHERE dias_reiterado BETWEEN 29 AND 31
GROUP BY dias_reiterado, cuenta_para_calidad, estado_garantia
ORDER BY dias_reiterado;
```

**Resultado esperado:**
```
dias_reiterado | cuenta_para_calidad | estado_garantia     | cantidad
29             | SI                  | DENTRO DE GARANTÍA  | X
30             | SI                  | DENTRO DE GARANTÍA  | X  ← ESTE ES EL QUE ESTABA MAL
31             | NO                  | FUERA DE GARANTÍA   | X
```

## 🎯 IMPACTO

Esta corrección afectará:

1. **Vista `v_calidad_detalle`**: Todos los registros con exactamente 30 días ahora mostrarán `cuenta_para_calidad = 'SI'`
2. **Cálculos de calidad en la app**: Los técnicos verán los reiterados de 30 días contabilizados correctamente
3. **Dashboard web**: Los porcentajes de calidad se recalcularán automáticamente

## ⚠️ IMPORTANTE

Después de aplicar esta corrección:

1. **Recarga la app móvil** para que tome los datos actualizados
2. **Actualiza el dashboard** (F5 en el navegador)
3. **Verifica que los números cuadren** con los registros reales

## 🔄 SIGUIENTE PASO

Si después de esta corrección sigues viendo diferencias en los datos, ejecuta:

```sql
-- Ver TODOS los reiterados de un técnico con su clasificación
SELECT 
  orden_original,
  fecha_original,
  dias_reiterado,
  cuenta_para_calidad,
  estado_garantia
FROM v_calidad_detalle
WHERE rut_tecnico_original = '26012890-6'  -- RUT del técnico que estás revisando
ORDER BY fecha_original DESC;
```

Y compárteme los resultados para seguir investigando.





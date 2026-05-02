# 📊 Dashboard Web de Técnicos

Dashboard web profesional con la misma lógica de cálculo que la app móvil.

---

## 🎯 Características

### 📱 Niveles de Navegación (Drill-Down)

1. **Nivel 1: Resumen de Técnicos**
   - Vista general de todos los técnicos
   - KPIs globales
   - Métricas por técnico
   - **Clic en técnico** → Ver sus órdenes

2. **Nivel 2: Órdenes del Técnico**
   - Lista de órdenes completadas
   - RGU por orden
   - Fecha y hora
   - **Clic en orden** → Ver detalle de RGUs

3. **Nivel 3: Detalle de Orden (Modal)**
   - RGU total
   - Información completa de la orden
   - Fecha, técnico, hora fin

---

## 📊 Métricas Calculadas

### 1️⃣ **Producción**
- **RGU Total**: Suma de todos los RGUs del mes
- **Promedio Diario**: RGU Total / Días Trabajados
- **Órdenes**: Cantidad de órdenes completadas
- **Días Trabajados**: Días únicos con producción

### 2️⃣ **Calidad**
- **Período de Medición**: Del 21 del mes anterior al 20 del mes actual
- **Cálculo**: `(Trabajos - Reiterados) / Trabajos * 100`
- **Garantía**: 30 días desde la fecha de trabajo (hasta el 20 del mes siguiente)
- **Ejemplo**: 
  - Mes actual: Diciembre 2025
  - Trabajos: 21/Nov/2025 - 20/Dic/2025
  - Garantía: Hasta 20/Ene/2026

### 3️⃣ **Horas Extras (HHEE)**
- **Lunes a Viernes**: Después de las 18:30
- **Sábados**: Después de las 15:00
- **Domingos**: Todo el día cuenta como HHEE
- **Cálculo**: Suma de minutos extras / 60 = Horas

### 4️⃣ **KPIs Globales**
- **Técnicos Activos**: Con producción en el mes
- **RGU Total**: Suma de todos los técnicos
- **Promedio RGU/Téc**: RGU Total / Técnicos Activos
- **Calidad Promedio**: % sin reiterados del equipo
- **HHEE Totales**: Suma de horas extras del mes

---

## 🔧 Configuración

### Supabase

Edita las credenciales en `dashboard_tecnicos.html` líneas 434-435:

```javascript
const SUPABASE_URL = 'https://TU-PROYECTO.supabase.co';
const SUPABASE_KEY = 'TU-KEY-AQUI';
```

### Tablas Necesarias en Supabase

1. **`produccion_crea`**
   - Campos: `tecnico`, `rut_tecnico`, `codigo_tecnico`, `rgu_total`, `fecha_trabajo`, `orden_trabajo`, `hora_fin`, `estado`
   - Filtro: `estado = 'Completado'`

2. **`calidad_crea`**
   - Campos: `rut_tecnico_original`, `tecnico_original`, `orden_original`, `fecha_original`
   - Contiene los trabajos reiterados

---

## 🎨 Personalización

### Colores

Edita las variables CSS en la línea 10-21:

```css
:root {
    --bg-primary: #0F2027;
    --bg-secondary: #203A43;
    --accent-blue: #3b82f6;
    --accent-green: #10b981;
    --accent-purple: #9D6BFF;
    /* ... más colores */
}
```

### Meses Disponibles

Agrega más opciones en el selector (línea 370):

```html
<select id="mesFilter">
    <option value="2025-11">Noviembre 2025</option>
    <option value="2025-12" selected>Diciembre 2025</option>
    <option value="2026-01">Enero 2026</option>
    <option value="2026-02">Febrero 2026</option>
    <!-- Agregar más meses aquí -->
</select>
```

---

## 🚀 Cómo Usar

### 1. Abrir el Dashboard

```bash
# Opción 1: Doble clic en el archivo
dashboard_tecnicos.html

# Opción 2: Abrir con navegador específico
chrome.exe dashboard_tecnicos.html

# Opción 3: Servidor local (recomendado)
python -m http.server 8000
# Luego abrir: http://localhost:8000/dashboard_tecnicos.html
```

### 2. Navegar por los Datos

**Resumen de Técnicos**:
- Selecciona el mes en el filtro superior
- Haz clic en "🔄 Actualizar" para cargar datos
- Busca técnicos usando el campo de búsqueda
- Ordena columnas haciendo clic en los encabezados

**Ver Órdenes de un Técnico**:
- Haz clic en cualquier fila de técnico
- Verás todas sus órdenes del mes
- Usa "← Volver" para regresar al resumen

**Ver Detalle de Orden**:
- Haz clic en cualquier orden
- Se abre un modal con el detalle de RGUs
- Haz clic fuera del modal o en "×" para cerrar

### 3. Exportar Datos

Haz clic en "📥 Exportar":
- Genera un archivo CSV
- Incluye todos los datos visibles
- Nombre: `dashboard_tecnicos_YYYY-MM.csv`
- Abre en Excel o Google Sheets

---

## 📊 Columnas de la Tabla

| Columna | Descripción | Ordenable |
|---------|-------------|-----------|
| **Técnico** | Nombre y RUT | ✅ |
| **RGU Total** | Suma de RGUs del mes | ✅ |
| **Prom/Día** | RGU / Días trabajados | ✅ |
| **Órdenes** | Cantidad de OTs | ✅ |
| **Días** | Días únicos trabajados | ✅ |
| **Reiterados** | Trabajos reiterados | ✅ |
| **Calidad** | % sin reiterados | ✅ |
| **HHEE** | Horas extras (con barra) | ✅ |

---

## 🎯 Badges de Calidad

- 🟢 **Verde** (98% o más): Excelente
- 🟡 **Amarillo** (95% - 97.9%): Bueno
- 🔴 **Rojo** (menos de 95%): Requiere atención

---

## 🔍 Funcionalidades Adicionales

### Búsqueda en Tiempo Real
Filtra por:
- Nombre del técnico
- RUT

### Ordenamiento
Haz clic en cualquier columna para:
- Ordenar ascendente ↑
- Ordenar descendente ↓
- Volver a hacer clic para alternar

### Responsive
- Se adapta a diferentes tamaños de pantalla
- Funciona en móviles (aunque la app es mejor para eso)
- Optimizado para tablets y desktops

---

## 📱 Diferencias con la App Móvil

| Característica | App Móvil | Dashboard Web |
|----------------|-----------|---------------|
| **Vista** | Personal (un técnico) | Global (todos los técnicos) |
| **Navegación** | Card → Detalle | Drill-down multinivel |
| **Actualización** | Automática | Manual (botón actualizar) |
| **Exportar** | No | Sí (CSV) |
| **Filtros** | Mes navegable | Selector de mes |
| **Target** | Técnico individual | Supervisor/Manager |

---

## 🛠️ Solución de Problemas

### No Carga Datos

1. **Verificar credenciales de Supabase**
   - URL correcta
   - API Key válida

2. **Abrir Consola del Navegador** (F12)
   - Ver errores en rojo
   - Verificar llamadas a la API

3. **Verificar formato de fechas**
   - Debe ser: `d/m/yyyy` (ej: `15/12/2025`)

### Calidad no se Calcula

1. **Verificar tabla `calidad_crea`**
   - Debe tener reiterados del período

2. **Verificar período de calidad**
   - Ver consola: buscar "Período calidad:"

### HHEE en 0

1. **Verificar campo `hora_fin`**
   - Formato: `HH:mm` (ej: `19:45`)

2. **Verificar lógica de días**
   - Sábados: límite 15:00
   - Lun-Vie: límite 18:30

---

## 🚀 Próximas Mejoras (Opcionales)

- [ ] Gráficos con Chart.js
- [ ] Filtros avanzados (rango de fechas, zona)
- [ ] Comparación entre meses
- [ ] Exportar a PDF
- [ ] Notificaciones de umbral
- [ ] Modo offline con caché

---

## 📞 Soporte

Si tienes problemas:
1. Revisa la consola del navegador (F12)
2. Verifica las credenciales de Supabase
3. Asegúrate de que las tablas tengan datos

---

¡Dashboard listo para usar! 🎉





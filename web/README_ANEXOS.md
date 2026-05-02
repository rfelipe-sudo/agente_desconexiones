# Sistema de Anexos de Remuneraciones

## 📄 Generación de Anexos en PDF

El dashboard ahora incluye la funcionalidad para generar **Anexos de Remuneraciones** en formato PDF para cada técnico.

### 🎯 Características

- ✅ **Descarga Individual**: Genera el anexo de un técnico específico
- ✅ **Descarga Masiva**: Genera anexos para todos los técnicos
- ✅ **Formato Oficial**: Replica el formato exacto del documento de remuneraciones
- ✅ **Leyenda CREAVOX**: Incluye mensaje para consultar detalles en la app
- ✅ **Datos Completos**: Producción diaria, calidad, asistencia y bonos

---

## 📋 Contenido del Anexo

Cada anexo PDF incluye:

### 1. **Encabezado**
- Nombre de la empresa: "creaciones"
- Título: "Anexo Remuneraciones"
- Período de cálculo y pago
- Nombre y RUT del técnico

### 2. **Detalle de Producción Diaria**
Tabla con todos los días del mes:
- Día del mes
- Cantidad de órdenes
- RGU generados
- Estado (Presente/Ausente/Feriado)
- Turno
- Marcación
- Atraso

### 3. **Resumen de Producción**
- Cantidad RGU (base)
- RGU adicional compensado
- Total RGU

### 4. **Resumen de Calidad**
- Órdenes ejecutadas en período
- Órdenes reiteradas
- Porcentaje de reiteración

### 5. **Resumen de Asistencia**
- Días presentes
- Días laborables
- Ausencias
- Domingos y festivos

### 6. **Fórmula de Promedio**
- Cálculo del promedio de RGU diario

### 7. **Bonificación Variable**
- Bono Calidad
- Bono Producción
- Fórmula Semana Corrida
- Bono Semana Corrida
- Total Variable

### 8. **Detalle de Órdenes Ejecutadas** (página adicional)
- Lista completa de todas las órdenes del mes
- Número de orden
- Fecha de ejecución
- Tipo de orden
- RGU Base
- RGU Adicional
- RGU Total

### 9. **Detalle de Órdenes Reiteradas** (página adicional si aplica)
- Orden original
- Fecha de atención
- Orden reiterada
- Fecha de reiteración
- Causa del reiterado

### 10. **Firma**
- Espacio para firma del técnico
- Nombre y RUT

---

## 🚀 Cómo Usar

### Descarga Individual

1. Abre el dashboard de técnicos
2. Busca el técnico en la tabla
3. Haz clic en el botón **📄** en la columna "PDF"
4. El anexo se descargará automáticamente

**Nombre del archivo**: `Anexo_[RUT]_[mes]_[año].pdf`  
**Ejemplo**: `Anexo_15342161-7_diciembre_2025.pdf`

### Descarga Masiva

1. Abre el dashboard de técnicos
2. Haz clic en el botón **"📄 Anexos (Todos)"** en el header
3. Confirma la generación masiva
4. Se generarán y descargarán todos los anexos (uno por uno)

⚠️ **Nota**: La descarga masiva puede tomar varios minutos dependiendo de la cantidad de técnicos.

---

## 🔧 Consideraciones Técnicas

### Librerías Utilizadas

- **jsPDF**: Generación de archivos PDF
- **jsPDF-AutoTable**: Creación de tablas en PDF

### Formato

- **Orientación**: Vertical (portrait)
- **Tamaño**: A4
- **Fuente**: Helvetica
- **Tablas**: Grid con colores corporativos

### Colores

- **Encabezados de tabla**: RGB(32, 58, 67) - Gris azulado
- **Texto**: Negro
- **Leyenda**: Gris claro (100, 100, 100)

---

## ⚙️ Configuración

### Período de Cálculo

El período de cálculo y pago se determina automáticamente:
- **Período de cálculo**: Mes seleccionado en el filtro
- **Período de pago**: Mes siguiente al seleccionado

**Ejemplo**:
- Si seleccionas **Diciembre 2025**
- Período de cálculo: `noviembre 2025`
- Período de pago: `diciembre de 2025`

### Datos Incluidos

Los datos se obtienen de:
- **Producción**: Tabla `produccion_crea`
- **Calidad**: Vista `v_calidad_tecnicos`
- **Bonos**: Vista `v_pagos_tecnicos`
- **RGU Compensados**: Tabla `rgu_adicionales`

---

## 🐛 Solución de Problemas

### El botón PDF no genera el archivo

1. Verifica que tienes datos cargados para el mes seleccionado
2. Abre la consola del navegador (F12) y busca errores
3. Recarga la página (F5) e intenta nuevamente

### Los datos no coinciden con el sistema

1. Verifica que el mes seleccionado sea el correcto
2. Confirma que los datos están actualizados en Supabase
3. Haz clic en "🔄 Actualizar" para recargar los datos

### La descarga masiva se detiene

1. Es normal que tome tiempo (500ms por técnico)
2. No cierres ni cambies de pestaña durante la generación
3. Los archivos se descargarán uno por uno

---

## 📊 Exportaciones Disponibles

El dashboard ofrece 3 tipos de exportación:

1. **📥 Exportar**: CSV con resumen completo de técnicos
2. **💼 Plantilla RRHH**: CSV en formato de importación de haberes
3. **📄 Anexos (Todos)**: PDF de anexos de remuneraciones

---

## 🔄 Actualizaciones Futuras

- [ ] Descarga masiva en ZIP (requiere librería adicional)
- [ ] Envío automático por email
- [ ] Firma digital
- [ ] Personalización de plantilla

---

**Versión**: 1.0.0  
**Fecha**: Enero 2026  
**Empresa**: Creaciones Tecnológicas


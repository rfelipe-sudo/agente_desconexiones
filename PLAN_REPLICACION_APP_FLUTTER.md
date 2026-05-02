# 📱 Plan de Replicación - App Flutter "Agente de Desconexiones"

## 🎯 Objetivo
Crear una réplica **EXACTA** (gráfica y lógicamente) de la app móvil Flutter para otra empresa, manteniendo todas las funcionalidades pero con datos de otra fuente.

---

## 📊 Mapeo Completo de la App Actual

### **📱 Información General**
- **Nombre**: Agente de Desconexiones
- **Plataforma**: Flutter (Android/iOS/Windows/Linux/macOS)
- **Empresa**: Creaciones Tecnológicas
- **Propósito**: Gestión de alertas de fibra óptica + Agente de voz CREA

---

## ✨ Módulos y Funcionalidades

### **1. 🚨 Sistema de Alertas de Desconexión**
**Pantallas:**
- `alertas_cto_screen.dart` - Lista de alertas activas
- `alerta_detail_screen.dart` - Detalle de alerta específica
- `asistente_crea_terreno_screen.dart` - Asistente CREA en terreno
- `asistente_cto_screen.dart` - Asistente para CTOs

**Servicios:**
- `alertas_cto_service.dart` - Gestión de alertas de CTOs
- `alerta_contexto_service.dart` - Contexto de alertas
- `notificacion_service.dart` - Notificaciones push
- `local_notification_service.dart` - Notificaciones locales con sonido
- `alarm_audio_service.dart` - Alarma insistente

**Características:**
- ✅ Notificaciones push con alarma personalizada
- ✅ Atender/Postergar alertas (5 min, 1 vez)
- ✅ Escalamiento automático a supervisor (3 min)
- ✅ Tipos: desconexión, churn, CTO dañada, terceros

---

### **2. 🤖 Agente de Voz CREA (ElevenLabs)**
**Pantallas:**
- `crea_conversation_screen.dart` - Conversación con CREA

**Servicios:**
- `crea_agent_service.dart` - Lógica del agente CREA
- `elevenlabs_service.dart` - WebSocket a ElevenLabs
- `kepler_api_service.dart` - Integración con panel Kepler
- `kepler_polling_service.dart` - Monitoreo cada 20 min
- `kepler_webhook_service.dart` - Recepción de webhooks

**Características:**
- ✅ Conversación por voz en tiempo real
- ✅ Informa sobre desconexiones
- ✅ Monitorea progreso cada 20 min
- ✅ Verifica regularización en Kepler
- ✅ Manejo de excepciones (churn, CTO dañada)

**Configuración:**
- Agent ID: `agent_9501kbtjcvw3fgr9p0kpbgdzvg90`
- WebSocket ElevenLabs para audio bidireccional

---

### **3. 📊 Dashboard Personal "Tu Mes"**
**Pantallas:**
- `tu_mes_screen.dart` - Dashboard mensual del técnico

**Servicios:**
- `produccion_service.dart` - Datos de producción
- `tecnico_service.dart` - Información del técnico

**Características:**
- ✅ Producción mensual (RGU, órdenes)
- ✅ Calidad (% reiteración)
- ✅ Bonos calculados
- ✅ Días trabajados
- ✅ Gráficos de evolución

---

### **4. 📈 Módulo de Producción**
**Pantallas:**
- `produccion_screen.dart` - Visualización de producción
- `ordenes_pendientes_screen.dart` - Órdenes pendientes
- `finalizar_orden_screen.dart` - Finalizar órdenes

**Servicios:**
- `ordenes_trabajo_service.dart` - Gestión de órdenes

**Características:**
- ✅ Lista de órdenes completadas
- ✅ RGU por orden (base + adicional)
- ✅ Estados: Completado, Derivado, Suspendido
- ✅ Sincronización con Supabase

---

### **5. 🎯 Módulo de Calidad**
**Pantallas:**
- `calidad_screen.dart` - Dashboard de calidad
- `calidad_detalle_screen.dart` - Detalle de reiteraciones

**Modelos:**
- `calidad_tecnico.dart` - Modelo de calidad

**Características:**
- ✅ % de reiteración mensual
- ✅ Órdenes reiteradas vs completadas
- ✅ Período móvil de 30 días (día 21 a 20)
- ✅ Desglose por tipo de reiteración

---

### **6. 🔄 Sistema de Reversa de Equipos**
**Pantallas:**
- `reversa_screen.dart` - Gestión de reversas

**Servicios:**
- `reversa_service.dart` - Lógica de reversas

**Modelos:**
- `equipo_reversa.dart` - Modelo de equipo

**Características:**
- ✅ Registro de equipos recuperados
- ✅ Escaneo de MAC/Serial
- ✅ Estados: pendiente, entregado
- ✅ Geolocalización de reversas

---

### **7. 📦 Sistema de Bodega y Consumo**
**Pantallas:**
- `bodega_screen.dart` - Inventario de bodega
- `bodeguero_menu_screen.dart` - Menú para bodeguero
- `consumo_screen.dart` - Registro de consumos

**Servicios:**
- `krp_consumo_service.dart` - Consumo de materiales

**Modelos:**
- `consumo_material.dart` - Modelo de consumo
- `receta_material.dart` - Receta por tipo de orden

**Características:**
- ✅ Inventario en tiempo real
- ✅ Consumo automático por receta
- ✅ Solicitudes de transferencia
- ✅ Control de stock

---

### **8. 🚚 Sistema de Transferencias**
**Pantallas:**
- `solicitar_material_screen.dart` - Solicitar materiales

**Servicios:**
- `transferencias_service.dart` - Gestión de transferencias

**Modelos:**
- `transferencias_models.dart` - Modelos de transferencias

**Características:**
- ✅ Solicitud de materiales
- ✅ Firma digital
- ✅ Estados: pendiente, aprobada, rechazada, completada
- ✅ Historial de transferencias

---

### **9. 🚨 Sistema Anti-Fraude "Sin Moradores"**
**Pantallas:**
- `churn_fotos_screen.dart` - Captura de fotos

**Servicios:**
- `churn_service.dart` - Lógica de churn
- `portico_detector_service.dart` - Detección de "pórtico" (domicilio)
- `deteccion_caminata_service.dart` - Detector de movimiento

**Características:**
- ✅ Detección automática de llegada al domicilio (geofencing)
- ✅ Captura de 3 fotos obligatorias
- ✅ Georeferenciación precisa
- ✅ Previene fraude en casos de churn
- ✅ Detección de caminata (pedómetro)

---

### **10. 📡 Mapa de Calor WiFi**
**Pantallas:**
- `mapa_calor_screen.dart` - Visualización de cobertura WiFi

**Servicios:**
- `speed_measurement_service.dart` - Medición de velocidad

**Características:**
- ✅ Medición de RSSI en distintos puntos
- ✅ Visualización tipo "plano de casa"
- ✅ Validación de movimiento entre mediciones
- ✅ Integración con ONT Askey para datos reales
- ✅ Detección de colisiones en etiquetas

---

### **11. 👷 Sistema de Ayuda en Terreno**
**Pantallas:**
- `ayuda_terreno_screen.dart` - Solicitar ayuda
- `ayuda_historial_screen.dart` - Historial de ayudas
- `ayuda_tracking_screen.dart` - Seguimiento de ayuda

**Servicios:**
- `ayuda_service.dart` - Gestión de ayudas

**Modelos:**
- `solicitud_ayuda.dart` - Modelo de solicitud

**Características:**
- ✅ Solicitud de ayuda con geolocalización
- ✅ Asignación automática al técnico más cercano
- ✅ Estados: pendiente, en camino, atendida
- ✅ Tracking en tiempo real

---

### **12. 👔 Módulo de Supervisor**
**Pantallas:**
- `supervisor/mi_equipo_screen.dart` - Vista de equipo
- `supervisor/alertas_fraude_screen.dart` - Alertas de fraude

**Servicios:**
- `equipo_service.dart` - Gestión de equipo
- `alertas_fraude_service.dart` - Detección de fraudes

**Modelos:**
- `tecnico_equipo.dart` - Modelo de técnico
- `resumen_equipo.dart` - Resumen del equipo

**Características:**
- ✅ Dashboard de equipo
- ✅ Métricas por técnico
- ✅ Alertas escaladas
- ✅ Alertas de fraude (Sin Moradores)

---

### **13. 🛠️ Otras Funcionalidades**
**Pantallas:**
- `home_screen.dart` - Pantalla principal
- `splash_screen.dart` - Splash screen animado
- `registro_screen.dart` - Registro de usuario
- `configuracion_screen.dart` - Configuración
- `camera_screen.dart` - Cámara personalizada
- `fiber_microscope_screen.dart` - Microscopio de fibra
- `speed_meter_screen.dart` - Medidor de velocidad
- `detalle_tag_screen.dart` - Detalle de TAGs
- `test_ordenes_screen.dart` - Test de órdenes

**Servicios:**
- `auth_service.dart` - Autenticación
- `supabase_service.dart` - Cliente Supabase
- `estado_tecnico_service.dart` - Estado del técnico
- `tag_service.dart` - Gestión de TAGs
- `krp_marcas_service.dart` - Marcas de asistencia

**Widgets:**
- `alerta_card.dart` - Card de alerta
- `alerta_cto_card.dart` - Card de CTO
- `boton_sin_moradores.dart` - Botón anti-fraude
- `creaciones_loading.dart` - Loading personalizado
- `particle_animation.dart` - Animaciones de partículas

---

## 🗄️ Base de Datos (Supabase)

### **Tablas principales:**
1. `produccion_crea` - Órdenes de trabajo
2. `calidad_crea` - Reiteraciones
3. `asistencia_crea` - Asistencia
4. `rgu_adicionales` - Compensaciones de RGU
5. `escala_produccion` - Escala de bonos
6. `escala_calidad` - Escala de calidad
7. `pagos_tecnicos` - Bonos calculados
8. `geo_marcas_diarias` - Marcas de geolocalización
9. `alertas_cto` - Alertas de desconexión
10. `consumos_materiales` - Consumos
11. `transferencias_materiales` - Transferencias
12. `reversas_equipos` - Equipos en reversa
13. `solicitudes_ayuda` - Ayudas en terreno

---

## 🚀 Plan de Replicación

### **Fase 1: Preparación** ✅
- [ ] 1.1. Crear carpeta del nuevo proyecto
- [ ] 1.2. Definir nombre de la nueva app
- [ ] 1.3. Crear nuevo proyecto Supabase
- [ ] 1.4. Configurar Firebase (opcional)

### **Fase 2: Copia del Proyecto Flutter** 📱
- [ ] 2.1. Copiar estructura completa de carpetas
- [ ] 2.2. Actualizar `pubspec.yaml` (nombre, descripción)
- [ ] 2.3. Copiar `lib/` completo
- [ ] 2.4. Copiar `assets/` completo
- [ ] 2.5. Copiar configuraciones de plataforma (android/, ios/)

### **Fase 3: Personalización de Identidad** 🎨
- [ ] 3.1. Cambiar nombre de la app en `pubspec.yaml`
- [ ] 3.2. Actualizar logo (`assets/logo/app_icon.png`)
- [ ] 3.3. Actualizar splash screen
- [ ] 3.4. Cambiar colores corporativos en `app_colors.dart`
- [ ] 3.5. Actualizar textos y nombres de empresa

### **Fase 4: Configuración de Servicios** ⚙️
- [ ] 4.1. Configurar Supabase (URL + API Key)
- [ ] 4.2. Configurar ElevenLabs (Agent ID + Voice ID)
- [ ] 4.3. Configurar API Kepler (URL base)
- [ ] 4.4. Configurar Firebase (si aplica)
- [ ] 4.5. Configurar Google Maps API Key

### **Fase 5: Replicación de Base de Datos** 🗄️
- [ ] 5.1. Ejecutar scripts SQL de creación de tablas
- [ ] 5.2. Crear funciones SQL
- [ ] 5.3. Crear vistas
- [ ] 5.4. Poblar escalas de bonos
- [ ] 5.5. Configurar políticas de seguridad (RLS)

### **Fase 6: Adaptación de Fuente de Datos** 🔌
- [ ] 6.1. Identificar fuente de datos de nueva empresa
- [ ] 6.2. Crear script de migración/importación
- [ ] 6.3. Mapear campos de origen → destino
- [ ] 6.4. Implementar ETL (si es necesario)
- [ ] 6.5. Validar integridad de datos

### **Fase 7: Testing Completo** ✅
- [ ] 7.1. Probar autenticación
- [ ] 7.2. Probar alertas y notificaciones
- [ ] 7.3. Probar agente CREA
- [ ] 7.4. Probar producción y calidad
- [ ] 7.5. Probar bodega y consumos
- [ ] 7.6. Probar transferencias
- [ ] 7.7. Probar sistema anti-fraude
- [ ] 7.8. Probar mapa de calor
- [ ] 7.9. Probar módulo supervisor
- [ ] 7.10. Probar exportaciones

### **Fase 8: Compilación y Despliegue** 📦
- [ ] 8.1. Compilar APK de prueba
- [ ] 8.2. Probar en dispositivos reales
- [ ] 8.3. Compilar APK release
- [ ] 8.4. Firmar APK (si aplica)
- [ ] 8.5. Distribuir a usuarios finales

---

## 📋 Checklist de Archivos a Personalizar

### **Configuración:**
- [ ] `pubspec.yaml` - Nombre, descripción, versión
- [ ] `lib/config/supabase_config.dart` - URL y API Key de Supabase
- [ ] `lib/constants/app_constants.dart` - ElevenLabs, Kepler, constantes
- [ ] `lib/constants/app_colors.dart` - Colores corporativos

### **Assets:**
- [ ] `assets/logo/app_icon.png` - Icono de la app
- [ ] `assets/logo/app_icon_foreground.png` - Foreground adaptativo
- [ ] `assets/logo/splash_logo.png` - Logo del splash
- [ ] `assets/sounds/alerta_urgente.mp3` - Sonido de alerta (opcional)

### **Android:**
- [ ] `android/app/src/main/AndroidManifest.xml` - Nombre, permisos
- [ ] `android/app/build.gradle` - ApplicationId, nombre
- [ ] `android/app/src/main/res/values/strings.xml` - Nombre de la app

### **iOS (si aplica):**
- [ ] `ios/Runner/Info.plist` - Nombre, permisos
- [ ] `ios/Runner.xcodeproj/project.pbxproj` - Bundle ID

---

## 📊 Estimación de Tiempo

| Fase | Tiempo Estimado |
|------|----------------|
| Preparación | 30 min |
| Copia del proyecto | 1 hora |
| Personalización | 2 horas |
| Configuración servicios | 1 hora |
| Replicación BD | 2 horas |
| Adaptación de datos | **Variable (según fuente)** |
| Testing completo | 3 horas |
| Compilación | 1 hora |
| **TOTAL** | **10-12 horas + tiempo de adaptación de datos** |

---

## 🎯 Próximos Pasos

1. ✅ Confirmar plan de replicación
2. ⏳ **Informar de dónde vienen los datos de la nueva empresa**
3. ⏳ Crear script de adaptación de datos
4. ⏳ Comenzar replicación

---

**Fecha:** 2026-02-03  
**Estado:** Esperando información de fuente de datos  
**Proyecto base:** agente_desconexiones v1.0.0


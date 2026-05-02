# 🚨 Agente de Desconexiones

**App Flutter para gestión de alertas de fibra óptica**  
Desarrollado para **Creaciones Tecnológicas**

---

## 📋 Descripción

Aplicación móvil que permite a técnicos y supervisores gestionar alertas de desconexión en CTOs (Cajas de Terminación Óptica) de fibra óptica, integrada con el panel Kepler y el agente de voz CREA.

---

## ✨ Características

### 👷 Rol Técnico
- Recibe notificaciones push con alarma insistente
- Visualiza detalles de la alerta (CTO, pelo, OT, valores)
- Puede **Atender** o **Postergar** (1 vez, 5 min) la alerta
- Conversación con agente de voz CREA vía ElevenLabs
- Captura de fotos georeferenciadas (casos de churn)
- Escalamiento automático a supervisor (3 min sin respuesta)

### 👔 Rol Supervisor
- Recibe alertas escaladas
- Visualiza historial y estadísticas
- Gestión de casos especiales (CTO dañada, terceros)

### 🤖 Agente CREA
- Informa al técnico sobre la desconexión
- Monitorea progreso (consulta cada 20 min)
- Verifica regularización en panel Kepler
- Manejo de excepciones (churn, CTO dañada, terceros)

---

## 🔧 Configuración

### 1. Firebase
```bash
# Instalar FlutterFire CLI
dart pub global activate flutterfire_cli

# Configurar Firebase
flutterfire configure
```

### 2. ElevenLabs
Actualizar en `lib/constants/app_constants.dart`:
```dart
static const String elevenLabsAgentId = 'TU_AGENT_ID';
static const String elevenLabsVoiceId = 'TU_VOICE_ID';
```

### 3. API Kepler
Actualizar URL base en `lib/constants/app_constants.dart`:
```dart
static const String apiBaseUrl = 'https://tu-api-kepler.com';
```

### 4. Sonido de Alerta
- Android: Copiar `alerta_urgente.mp3` a `android/app/src/main/res/raw/`
- iOS: Copiar `alerta_urgente.caf` a `ios/Runner/`

### 5. Fuentes
Descargar Poppins de [Google Fonts](https://fonts.google.com/specimen/Poppins) y copiar a `assets/fonts/`

---

## 📦 Dependencias Principales

| Paquete | Uso |
|---------|-----|
| `firebase_messaging` | Notificaciones push |
| `flutter_local_notifications` | Notificaciones locales con sonido |
| `elevenlabs_flutter` | SDK del agente de voz |
| `geolocator` | Geolocalización |
| `image_picker` | Captura de fotos |
| `provider` | Estado de la app |

---

## 🚀 Ejecución

```bash
# Instalar dependencias
flutter pub get

# Ejecutar en modo debug
flutter run

# Compilar APK release
flutter build apk --release
```

---

## 📡 Webhook desde Kepler

El panel Kepler debe enviar alertas con la siguiente estructura:

```json
{
  "nombre_tecnico": "Juan Pérez",
  "telefono_tecnico": "+56912345678",
  "numero_ot": "OT-12345",
  "access_id": "ACC-67890",
  "nombre_cto": "CTO-NORTE-01",
  "numero_pelo": "P-05",
  "valor_consulta1": 0.85,
  "tipo_alerta": "desconexion"
}
```

### Tipos de Alerta
- `desconexion` - Desconexión estándar
- `churn` - Requiere fotos georeferenciadas
- `cto_danada` - Escala automáticamente a supervisor
- `terceros_en_cto` - Escala automáticamente a supervisor

---

## 📂 Estructura del Proyecto

```
lib/
├── constants/        # Colores, constantes
├── models/           # Modelos de datos
├── providers/        # Estado con Provider
├── screens/          # Pantallas
├── services/         # Servicios (API, notificaciones, CREA)
├── utils/            # Utilidades
├── widgets/          # Widgets reutilizables
└── main.dart         # Punto de entrada
```

---

## 👥 Equipo

**Creaciones Tecnológicas**

---

## 📄 Licencia

Propietario - Todos los derechos reservados

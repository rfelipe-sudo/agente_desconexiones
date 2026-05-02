# Instrucciones para agregar el audio de alarma

## 📁 Ubicación del archivo

Coloca tu archivo de audio en:
```
assets/sounds/alerta_urgente.mp3
```

## 📱 Para Android

1. **IMPORTANTE:** Copia el archivo a la carpeta `raw` de Android:
   ```
   android/app/src/main/res/raw/alerta_urgente.mp3
   ```
   
   ⚠️ **NOTA:** El archivo físico puede tener extensión `.mp3` o `.wav`, pero el código lo referencia como `alerta_urgente` (sin extensión).

2. Si el directorio `raw` no existe, créalo:
   - `android/app/src/main/res/raw/`

## 🎵 Formato del archivo

- **Formato:** MP3 o WAV (recomendado MP3)
- **Nombre en assets:** `alerta_urgente.mp3`
- **Nombre en Android raw:** `alerta_urgente.mp3` (el archivo físico puede tener extensión)
- **Duración recomendada:** 2-5 segundos (se repetirá automáticamente)
- **Ubicación Android:** El archivo debe estar en `res/raw/` para que funcione correctamente

## ✅ Verificación

Después de agregar el archivo, ejecuta:
```bash
flutter clean
flutter pub get
flutter build apk --debug
```

El audio se usará automáticamente en las notificaciones de alerta.


# Sonidos de Alertas

## Archivo requerido: `alerta_urgente.mp3`

Para que las notificaciones de alerta suenen correctamente, necesitas agregar el archivo de sonido:

**Ubicación:** `assets/sounds/alerta_urgente.mp3`

### Para Android:
- El archivo debe estar en formato MP3 o WAV
- Se referenciará como `alerta_urgente` (sin extensión)
- Se copiará a `android/app/src/main/res/raw/alerta_urgente.mp3`

### Para iOS:
- El archivo debe estar en formato CAF o MP3
- Se referenciará como `alerta_urgente.caf`
- Se copiará al bundle de la app

### Nota temporal:
Si no tienes el archivo de sonido, la app usará el sonido por defecto del sistema.



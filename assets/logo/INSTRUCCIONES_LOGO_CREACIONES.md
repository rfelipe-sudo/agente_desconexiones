# 📋 GUÍA: Agregar Logo de Creaciones Tecnológicas

## 🎯 Método 1: Automático (Recomendado)

### Paso 1: Guardar tu logo
Descarga la imagen del logo que te envié y guárdala en esta carpeta como:
```
creaciones_logo_original.png
```

### Paso 2: Ejecutar el script
Abre PowerShell en esta carpeta y ejecuta:

```powershell
cd c:\Users\Usuario\agente_desconexiones\assets\logo
python preparar_logo_creaciones.py
```

El script generará automáticamente:
- ✅ `creaciones_logo.png` (optimizado para splash)
- ✅ `creaciones_logo_white.png` (versión blanca)
- ✅ `creaciones_icon.png` (icono cuadrado)

### Paso 3: Compilar la app

```powershell
cd c:\Users\Usuario\agente_desconexiones
flutter clean
flutter pub get
flutter build apk --release
```

---

## 🎯 Método 2: Manual

Si prefieres hacerlo manualmente:

### 1️⃣ Guardar las imágenes

Guarda la imagen del logo en esta carpeta con estos nombres exactos:

```
📁 assets/logo/
   ├── creaciones_logo.png       ← Logo completo (para splash y loading)
   ├── creaciones_logo_white.png ← Logo en blanco (opcional)
   └── creaciones_icon.png       ← Icono cuadrado (opcional)
```

### 2️⃣ Formato recomendado

- **Resolución**: Mínimo 1200px de ancho x 400px de alto
- **Formato**: PNG con fondo transparente
- **Colores**: Blanco con sombras (como en la imagen)

### 3️⃣ Compilar

```powershell
cd c:\Users\Usuario\agente_desconexiones
flutter clean
flutter pub get
flutter build apk --release
```

---

## 🎨 Características del Logo Animado

Una vez integrado, tu logo tendrá:

### ✨ Splash Screen (Inicio)
- Fade in suave (0 → 1)
- Escala con rebote (0.3 → 1.0)
- Glow pulsante blanco
- Fade out suave al salir
- Duración total: ~3 segundos

### 🔄 Pantallas de Carga
- Logo con pulso sutil
- Spinner animado debajo
- Mensaje contextual
- Transición suave

### 🎬 Transiciones entre Pantallas
- Fade elegante
- Slide suave
- Scale/zoom
- Combinaciones personalizadas

---

## 📱 Resultado Final

Tu app tendrá:
1. **Al abrir**: Splash screen animado con tu logo
2. **Al cargar datos**: Loading con tu logo pulsante
3. **Al cambiar pantallas**: Transiciones suaves
4. **Consistencia visual**: Mismo logo en toda la app

---

## 🆘 Soporte

### ¿No tienes Python?
Instala desde: https://www.python.org/downloads/

### ¿Error con Pillow?
```powershell
python -m pip install Pillow
```

### ¿El logo no aparece?
Verifica que:
- El archivo se llame exactamente `creaciones_logo.png`
- Esté en la carpeta `assets/logo/`
- Ejecutaste `flutter clean` y `flutter pub get`

---

## ✅ Listo

Una vez completados estos pasos, tu logo de Creaciones Tecnológicas estará integrado con todas las animaciones suaves en tu app. 🚀


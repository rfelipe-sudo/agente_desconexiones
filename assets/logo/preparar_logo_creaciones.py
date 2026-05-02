"""
Script para preparar el logo de Creaciones Tecnológicas
Genera versiones optimizadas del logo para la app

Uso:
1. Coloca tu logo como 'creaciones_logo_original.png' en esta carpeta
2. Ejecuta: python preparar_logo_creaciones.py
3. Se generarán automáticamente:
   - creaciones_logo.png (optimizado para splash)
   - creaciones_logo_white.png (versión en blanco)
   - creaciones_icon.png (icono cuadrado)
"""

import os
import sys
from pathlib import Path

# Configurar encoding UTF-8 para la consola de Windows
if sys.platform == 'win32':
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')

try:
    from PIL import Image, ImageDraw, ImageFilter, ImageEnhance
except ImportError:
    print("❌ Pillow no está instalado")
    print("💡 Instala con: python -m pip install Pillow")
    sys.exit(1)

def generar_placeholder():
    """Genera un logo placeholder de Creaciones Tecnológicas"""
    print("📝 Generando logo placeholder...")
    
    # Crear imagen con fondo transparente
    width, height = 1200, 400
    img = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Dibujar texto "creaciones" (grande)
    # Nota: En producción deberías usar tu logo real
    from PIL import ImageFont
    try:
        font_large = ImageFont.truetype("arial.ttf", 100)
        font_small = ImageFont.truetype("arial.ttf", 60)
    except:
        font_large = ImageFont.load_default()
        font_small = ImageFont.load_default()
    
    # Texto con sombra para efecto de profundidad
    # Sombra
    draw.text((52, 52), "creaciones", fill=(50, 50, 50, 180), font=font_large)
    # Texto principal
    draw.text((50, 50), "creaciones", fill=(255, 255, 255, 255), font=font_large)
    
    # Texto "TECNOLÓGICAS" más pequeño y espaciado
    draw.text((52, 202), "T E C N O L Ó G I C A S", fill=(50, 50, 50, 180), font=font_small)
    draw.text((50, 200), "T E C N O L Ó G I C A S", fill=(220, 220, 220, 255), font=font_small)
    
    return img

def optimizar_logo(ruta_entrada):
    """Optimiza el logo original para uso en la app"""
    print(f"🔧 Optimizando {ruta_entrada}...")
    
    img = Image.open(ruta_entrada).convert('RGBA')
    
    # Redimensionar manteniendo aspecto (max 1200px ancho)
    max_width = 1200
    if img.width > max_width:
        ratio = max_width / img.width
        new_height = int(img.height * ratio)
        img = img.resize((max_width, new_height), Image.Resampling.LANCZOS)
    
    # Mejorar nitidez
    enhancer = ImageEnhance.Sharpness(img)
    img = enhancer.enhance(1.2)
    
    return img

def crear_version_blanca(img):
    """Crea una versión en blanco puro del logo"""
    print("🎨 Creando versión blanca...")
    
    # Convertir todo a blanco manteniendo el alpha
    data = img.getdata()
    new_data = []
    
    for item in data:
        # Si el pixel tiene algo de opacidad, convertirlo a blanco
        if item[3] > 30:  # Alpha > 30
            new_data.append((255, 255, 255, item[3]))
        else:
            new_data.append(item)
    
    img_white = Image.new('RGBA', img.size)
    img_white.putdata(new_data)
    
    return img_white

def crear_icono(img):
    """Crea un icono cuadrado del logo"""
    print("📱 Creando icono...")
    
    # Recortar al cuadrado (centrado)
    width, height = img.size
    size = min(width, height)
    
    left = (width - size) // 2
    top = (height - size) // 2
    right = left + size
    bottom = top + size
    
    img_square = img.crop((left, top, right, bottom))
    
    # Redimensionar a 1024x1024 (tamaño estándar para iconos)
    img_square = img_square.resize((1024, 1024), Image.Resampling.LANCZOS)
    
    return img_square

def main():
    print("\n" + "="*60)
    print("🎨 PREPARADOR DE LOGO - CREACIONES TECNOLÓGICAS")
    print("="*60 + "\n")
    
    # Verificar si existe el logo original
    ruta_original = Path(__file__).parent / "creaciones_logo_original.png"
    
    if ruta_original.exists():
        print(f"✅ Logo original encontrado: {ruta_original.name}")
        img_base = optimizar_logo(ruta_original)
    else:
        print("⚠️  Logo original no encontrado")
        print("📝 Generando placeholder...")
        print("\n💡 TIP: Coloca tu logo como 'creaciones_logo_original.png'")
        print("         y vuelve a ejecutar este script.\n")
        img_base = generar_placeholder()
    
    # Generar versiones
    ruta_base = Path(__file__).parent
    
    # 1. Logo principal (optimizado)
    ruta_logo = ruta_base / "creaciones_logo.png"
    img_base.save(ruta_logo, "PNG", optimize=True)
    print(f"✅ Guardado: {ruta_logo.name}")
    
    # 2. Versión blanca
    img_white = crear_version_blanca(img_base)
    ruta_white = ruta_base / "creaciones_logo_white.png"
    img_white.save(ruta_white, "PNG", optimize=True)
    print(f"✅ Guardado: {ruta_white.name}")
    
    # 3. Icono cuadrado
    img_icon = crear_icono(img_base)
    ruta_icon = ruta_base / "creaciones_icon.png"
    img_icon.save(ruta_icon, "PNG", optimize=True)
    print(f"✅ Guardado: {ruta_icon.name}")
    
    print("\n" + "="*60)
    print("✨ LOGOS GENERADOS EXITOSAMENTE")
    print("="*60)
    print("\n📋 Archivos creados:")
    print(f"   • creaciones_logo.png       (para splash screen)")
    print(f"   • creaciones_logo_white.png (versión blanca)")
    print(f"   • creaciones_icon.png       (icono cuadrado)")
    print("\n🚀 Ahora ejecuta:")
    print("   flutter clean")
    print("   flutter pub get")
    print("   flutter build apk --release")
    print("\n")

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"\n❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


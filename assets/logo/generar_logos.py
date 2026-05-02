#!/usr/bin/env python3
"""
Script para generar automáticamente los logos necesarios para la app
desde una imagen de entrada.

Uso:
    python generar_logos.py logo_original.png

Requisitos:
    pip install Pillow
"""

import sys
from PIL import Image, ImageDraw, ImageFont
import os

def crear_logo_placeholder(texto, tamaño, output_path):
    """Crea un logo placeholder con texto"""
    # Crear imagen con fondo blanco
    img = Image.new('RGBA', tamaño, (255, 255, 255, 0))
    draw = ImageDraw.Draw(img)
    
    # Dibujar un rectángulo azul oscuro
    margen = tamaño[0] // 10
    draw.rectangle(
        [margen, margen, tamaño[0] - margen, tamaño[1] - margen],
        fill=(26, 35, 126, 255),  # Azul oscuro #1a237e
        outline=(255, 255, 255, 255),
        width=5
    )
    
    # Agregar texto
    try:
        # Intentar usar una fuente del sistema
        font_size = tamaño[0] // 15
        font = ImageFont.truetype("arial.ttf", font_size)
    except:
        # Si falla, usar fuente por defecto
        font = ImageFont.load_default()
    
    # Calcular posición del texto centrado
    bbox = draw.textbbox((0, 0), texto, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    x = (tamaño[0] - text_width) // 2
    y = (tamaño[1] - text_height) // 2
    
    # Dibujar texto
    draw.text((x, y), texto, fill=(255, 255, 255, 255), font=font)
    
    # Guardar
    img.save(output_path, 'PNG')
    print(f"[OK] Creado: {output_path}")

def procesar_logo_original(input_path):
    """Procesa una imagen de logo original para generar las 3 versiones"""
    if not os.path.exists(input_path):
        print(f"[ERROR] No se encuentra el archivo {input_path}")
        return False
    
    try:
        # Abrir imagen original
        img = Image.open(input_path)
        print(f"[INFO] Imagen original: {img.size[0]}x{img.size[1]} px")
        
        # Convertir a RGBA si no lo es
        if img.mode != 'RGBA':
            img = img.convert('RGBA')
        
        # 1. app_icon.png (1024x1024)
        icon = img.copy()
        icon.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
        
        # Crear canvas cuadrado
        app_icon = Image.new('RGBA', (1024, 1024), (255, 255, 255, 0))
        offset = ((1024 - icon.size[0]) // 2, (1024 - icon.size[1]) // 2)
        app_icon.paste(icon, offset, icon if icon.mode == 'RGBA' else None)
        app_icon.save('app_icon.png', 'PNG')
        print("[OK] Creado: app_icon.png (1024x1024)")
        
        # 2. app_icon_foreground.png (1024x1024 con más margen)
        foreground = img.copy()
        # Reducir al 70% para dejar margen
        new_size = (int(1024 * 0.7), int(1024 * 0.7))
        foreground.thumbnail(new_size, Image.Resampling.LANCZOS)
        
        # Crear canvas cuadrado
        app_icon_fg = Image.new('RGBA', (1024, 1024), (255, 255, 255, 0))
        offset_fg = ((1024 - foreground.size[0]) // 2, (1024 - foreground.size[1]) // 2)
        app_icon_fg.paste(foreground, offset_fg, foreground if foreground.mode == 'RGBA' else None)
        app_icon_fg.save('app_icon_foreground.png', 'PNG')
        print("[OK] Creado: app_icon_foreground.png (1024x1024 con margen)")
        
        # 3. splash_logo.png (512x512)
        splash = img.copy()
        splash.thumbnail((512, 512), Image.Resampling.LANCZOS)
        
        # Crear canvas cuadrado
        splash_logo = Image.new('RGBA', (512, 512), (255, 255, 255, 0))
        offset_splash = ((512 - splash.size[0]) // 2, (512 - splash.size[1]) // 2)
        splash_logo.paste(splash, offset_splash, splash if splash.mode == 'RGBA' else None)
        splash_logo.save('splash_logo.png', 'PNG')
        print("[OK] Creado: splash_logo.png (512x512)")
        
        print("\n[SUCCESS] Logos generados exitosamente!")
        print("\nAhora ejecuta:")
        print("  flutter pub get")
        print("  dart run flutter_launcher_icons")
        print("  dart run flutter_native_splash:create")
        
        return True
        
    except Exception as e:
        print(f"[ERROR] Error procesando imagen: {e}")
        return False

def main():
    print("=" * 60)
    print("GENERADOR DE LOGOS - CREACIONES TECNOLOGICAS")
    print("=" * 60)
    print()
    
    if len(sys.argv) > 1:
        # Modo: procesar imagen original
        input_file = sys.argv[1]
        print(f"[INFO] Procesando: {input_file}")
        procesar_logo_original(input_file)
    else:
        # Modo: crear placeholders
        print("[WARNING] No se proporciono imagen de entrada")
        print("[INFO] Creando logos PLACEHOLDER para pruebas...")
        print()
        
        crear_logo_placeholder(
            "CREACIONES\nTECNOLÓGICAS",
            (1024, 1024),
            "app_icon.png"
        )
        
        crear_logo_placeholder(
            "CREACIONES\nTECNOLÓGICAS",
            (1024, 1024),
            "app_icon_foreground.png"
        )
        
        crear_logo_placeholder(
            "CT",
            (512, 512),
            "splash_logo.png"
        )
        
        print()
        print("[SUCCESS] Logos placeholder creados")
        print()
        print("Para usar tu logo real, ejecuta:")
        print("  python generar_logos.py tu_logo.png")

if __name__ == "__main__":
    main()


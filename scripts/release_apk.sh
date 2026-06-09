#!/usr/bin/env bash
# Publica un APK en GitHub Releases y actualiza Supabase (opcional).
#
# Requisitos: flutter, gh (autenticado), supabase CLI (opcional).
#
# Uso:
#   ./scripts/release_apk.sh
#   ./scripts/release_apk.sh --notes "Ranking calidad mayo"
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

NOTES="Actualización CREABOX"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --notes) NOTES="$2"; shift 2 ;;
    *) echo "Argumento desconocido: $1"; exit 1 ;;
  esac
done

VERSION_LINE="$(grep '^version:' pubspec.yaml | awk '{print $2}')"
VERSION="${VERSION_LINE%%+*}"
BUILD="${VERSION_LINE#*+}"
TAG="v${VERSION}+${BUILD}"
APK_NAME="creabox-${VERSION}+${BUILD}.apk"
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"

echo "==> Compilando $TAG"
flutter build apk --release

if [[ ! -f "$APK_PATH" ]]; then
  echo "No se encontró $APK_PATH"
  exit 1
fi

DIST="dist/releases"
mkdir -p "$DIST"
cp "$APK_PATH" "$DIST/$APK_NAME"

echo "==> Creando release $TAG en GitHub"
if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" "$DIST/$APK_NAME" --clobber
else
  gh release create "$TAG" "$DIST/$APK_NAME" \
    --title "CREABOX" \
    --notes "$NOTES"
fi

DOWNLOAD_URL="$(gh release view "$TAG" --json assets -q \
  ".assets[] | select(.name==\"$APK_NAME\") | .url")"

echo ""
echo "Release publicado: $TAG"
echo "Asset: $APK_NAME"
if [[ -n "$DOWNLOAD_URL" ]]; then
  echo "URL API: $DOWNLOAD_URL"
fi
echo ""
echo "Actualiza Supabase (SQL Editor) si quieres forzar URL directa:"
echo "  UPDATE configuracion_app SET valor = '$VERSION' WHERE clave = 'creabox_version';"
echo "  UPDATE configuracion_app SET valor = '$BUILD' WHERE clave = 'creabox_build';"
echo "  -- Opcional: pegar browser_download_url del release en creabox_apk_url"

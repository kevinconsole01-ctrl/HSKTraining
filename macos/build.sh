#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MACOS="$ROOT/macos"
BUILD="$ROOT/build"
APP="$BUILD/Zìgé.app"
CONTENTS="$APP/Contents"
BIN="$CONTENTS/MacOS/Zige"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$ROOT/index.html" "$CONTENTS/Resources/index.html"
cp "$ROOT/hsk.json" "$CONTENTS/Resources/hsk.json"
cp "$MACOS/Resources/download-bridge.js" "$CONTENTS/Resources/download-bridge.js"
cp "$MACOS/vendor/hanzi-writer.min.js" "$CONTENTS/Resources/hanzi-writer.min.js"
cp "$MACOS/vendor/hanzi-writer.LICENSE" "$CONTENTS/Resources/hanzi-writer.LICENSE"
cp "$MACOS/Info.plist" "$CONTENTS/Info.plist"

if [ ! -f "$MACOS/AppIcon.icns" ]; then
  python3 "$MACOS/make_icon.py"
fi
cp "$MACOS/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

echo "Compilo Zìgé per Intel (x86_64)..."
clang -fobjc-arc -O2 -Wall \
  -arch x86_64 \
  -mmacosx-version-min=13.0 \
  -framework Cocoa \
  -framework WebKit \
  -framework UniformTypeIdentifiers \
  -o "$BIN" \
  "$MACOS/Sources/"*.m

chmod +x "$BIN"

# Firma ad-hoc: sufficiente per l'uso locale. Per distribuire l'app
# servirebbero un certificato Developer ID e la notarizzazione Apple.
codesign --force --deep --sign - "$APP"

echo
echo "Fatto: $APP"
echo "Apri con: open \"$APP\""

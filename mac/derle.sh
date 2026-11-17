#!/bin/bash
# Clawd uygulamasını derler ve paketler.
#   ./derle.sh        yalnızca derler (build/Clawd.app)
#   ./derle.sh kur    derler, ~/Applications içine kurar ve çalıştırır (ardından uygulama anahtarları verilebilir)
set -euo pipefail
cd "$(dirname "$0")"

AD="Clawd"
PAKET="build/$AD.app"

rm -rf build
mkdir -p "$PAKET/Contents/MacOS" "$PAKET/Contents/Resources"

swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
    Sources/*.swift -o "$PAKET/Contents/MacOS/$AD" \
    -framework Cocoa -framework ServiceManagement

cp Info.plist "$PAKET/Contents/Info.plist"

# Simge: uygulamanın kendi çizimiyle üretilir
"$PAKET/Contents/MacOS/$AD" --simge build/simge.png
mkdir -p "build/$AD.iconset"
for b in 16 32 128 256 512; do
    sips -z $b $b build/simge.png --out "build/$AD.iconset/icon_${b}x${b}.png" >/dev/null
    sips -z $((b * 2)) $((b * 2)) build/simge.png --out "build/$AD.iconset/icon_${b}x${b}@2x.png" >/dev/null
done
iconutil -c icns "build/$AD.iconset" -o "$PAKET/Contents/Resources/$AD.icns"

codesign --force -s - "$PAKET"
echo "Derlendi: $PAKET"

if [ "${1:-}" = "kur" ]; then
    HEDEF="$HOME/Applications/$AD.app"
    pkill -x "$AD" 2>/dev/null || true
    sleep 0.5
    mkdir -p "$HOME/Applications"
    rm -rf "$HEDEF"
    cp -R "$PAKET" "$HEDEF"
    # İkinci ve sonraki değerler uygulamaya anahtar olarak verilir: ./derle.sh kur -gunluk 1
    if [ $# -gt 1 ]; then open "$HEDEF" --args "${@:2}"; else open "$HEDEF"; fi
    echo "Kuruldu ve açıldı: $HEDEF"
fi

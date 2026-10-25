#!/bin/bash
# Renders the icon and packs Resources/AppIcon.icns.
set -e
cd "$(dirname "$0")/.."
T=$(mktemp -d)
swiftc -O Tools/make_icon.swift -o "$T/make_icon"
"$T/make_icon" "$T/icon.png"
I="$T/AppIcon.iconset"; mkdir "$I"
for s in 16 32 128 256 512; do
  sips -z $s $s "$T/icon.png" --out "$I/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$T/icon.png" --out "$I/icon_${s}x${s}@2x.png" >/dev/null
done
mkdir -p Resources
iconutil -c icns "$I" -o Resources/AppIcon.icns
cp "$T/icon.png" Resources/AppIcon-1024.png
echo "Wrote Resources/AppIcon.icns"

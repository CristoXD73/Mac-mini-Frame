#!/bin/zsh
# Regenerate the app icon: app/AppIcon.icns and docs/images/icon.png.
set -euo pipefail
cd "${0:A:h}/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cp tools/render-icon.swift "$tmp/main.swift"
swiftc -swift-version 5 -O -o "$tmp/render" ${(f)"$(ls src/*.swift | grep -v main.swift)"} "$tmp/main.swift"
mkdir -p "$tmp/png" "$tmp/AppIcon.iconset"
"$tmp/render" "$tmp/png"
i="$tmp/AppIcon.iconset"
for s in 16 32 128 256 512; do
  cp "$tmp/png/icon_$s.png" "$i/icon_${s}x${s}.png"
  cp "$tmp/png/icon_$((s * 2)).png" "$i/icon_${s}x${s}@2x.png"
done
iconutil -c icns "$i" -o app/AppIcon.icns
cp "$tmp/png/icon_1024.png" docs/images/icon.png
cp "$tmp/png/social.png" docs/images/social.png
sips -Z 256 docs/images/icon.png --out docs/images/icon-256.png >/dev/null
echo "icon: app/AppIcon.icns, docs/images/icon.png"

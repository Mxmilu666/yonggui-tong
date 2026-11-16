#!/usr/bin/env bash
# Regenerates launcher PNGs from assets/brand.svg with headless Chrome + sips (macOS).
# The Android adaptive icon is a vector (res/drawable/ic_yonggui_foreground.xml) and is not rendered here.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cp "$root/assets/brand.svg" "$work/square.svg"
sed 's/id="bg"/id="bg" rx="24"/' "$root/assets/brand.svg" > "$work/rounded.svg"

# render <svg> <out.png> <size> [opaque]
render() {
  local background=00000000
  [ "${4:-}" = opaque ] && background=FFFFFFFF
  "$chrome" --headless=new --disable-gpu --hide-scrollbars --default-background-color="$background" \
    --window-size=1024,1024 --screenshot="$work/full.png" "file://$work/$1" >/dev/null 2>&1
  sips -z "$3" "$3" "$work/full.png" --out "$2" >/dev/null
  if [ "${4:-}" = opaque ]; then
    # App Store icons must not carry an alpha channel.
    sips -s format bmp "$2" --out "$work/flat.bmp" >/dev/null
    sips -s format png "$work/flat.bmp" --out "$2" >/dev/null
  fi
}

res="$root/android/app/src/main/res"
for pair in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  render rounded.svg "$res/mipmap-${pair%%:*}/ic_launcher.png" "${pair##*:}"
done

ios="$root/ios/Runner/Assets.xcassets/AppIcon.appiconset"
for pair in 20x20@1x:20 20x20@2x:40 20x20@3x:60 29x29@1x:29 29x29@2x:58 29x29@3x:87 \
    40x40@1x:40 40x40@2x:80 40x40@3x:120 60x60@2x:120 60x60@3x:180 76x76@1x:76 76x76@2x:152 \
    83.5x83.5@2x:167 1024x1024@1x:1024; do
  render square.svg "$ios/Icon-App-${pair%%:*}.png" "${pair##*:}" opaque
done

render rounded.svg "$root/assets/brand.png" 288
render rounded.svg "$root/web/favicon.png" 48
render rounded.svg "$root/web/icons/Icon-192.png" 192
render rounded.svg "$root/web/icons/Icon-512.png" 512
render square.svg "$root/web/icons/Icon-maskable-192.png" 192
render square.svg "$root/web/icons/Icon-maskable-512.png" 512
echo "icons rendered from assets/brand.svg"

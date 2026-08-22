#!/usr/bin/env bash
# Regenerates every app icon from the single path in assets/icons/src/glasses.svg.
#
# Three distinct assets, because Android treats them differently:
#   1. app_icon.png            launcher icon, opaque, artwork may reach the edge
#   2. app_icon_foreground.png adaptive foreground, transparent, artwork must
#                              stay inside the central safe zone or the OEM
#                              mask crops it
#   3. drawable-*/app_logo.png notification icon: Android discards the colours
#                              and tints the alpha channel white, so it has to
#                              read as a flat silhouette at 24 px
#
# Requires rsvg-convert (package librsvg2-bin).
set -euo pipefail

cd "$(dirname "$0")/.."
SRC="assets/icons/src/glasses.svg"

# The artwork's own bounding box inside the source viewBox.
ART_X=0
ART_Y=2.48
ART_W=16
ART_H=11.04

# Writes one square PNG with the glasses centred.
#   $1 output  $2 size  $3 share of the width the artwork takes  $4 background
render() {
  local out=$1 size=$2 coverage=$3 bg=$4
  local tmp
  tmp=$(mktemp --suffix=.svg)

  SRC="$SRC" OUT_SIZE="$size" COVERAGE="$coverage" BG="$bg" TMP="$tmp" python3 - <<'PY'
import os, re

src = open(os.environ['SRC']).read()
path = re.search(r'\sd="([^"]+)"', src).group(1)

size = float(os.environ['OUT_SIZE'])
coverage = float(os.environ['COVERAGE'])
bg = os.environ['BG']

art_x, art_y, art_w, art_h = 0.0, 2.48, 16.0, 11.04

width = size * coverage
scale = width / art_w
height = art_h * scale

# Centre the artwork, then undo the source viewBox offset.
tx = (size - width) / 2 - art_x * scale
ty = (size - height) / 2 - art_y * scale

layer = '' if bg == 'none' else f'<rect width="{size:g}" height="{size:g}" fill="{bg}"/>'

open(os.environ['TMP'], 'w').write(
    f'<svg xmlns="http://www.w3.org/2000/svg" width="{size:g}" height="{size:g}" '
    f'viewBox="0 0 {size:g} {size:g}">'
    f'{layer}'
    f'<g transform="translate({tx:.4f},{ty:.4f}) scale({scale:.6f})">'
    f'<path fill="#ffffff" d="{path}"/>'
    f'</g></svg>'
)
PY

  rsvg-convert -w "$size" -h "$size" -o "$out" "$tmp"
  rm -f "$tmp"
  echo "  $out  ${size}x${size}"
}

echo "Launcher icon"
render assets/icons/app_icon.png 1024 0.66 "#000000"

echo "Adaptive foreground (artwork kept inside the 66% safe zone)"
render assets/icons/app_icon_foreground.png 1024 0.52 none

echo "Notification icons (white silhouette on transparent)"
for entry in mdpi:24 hdpi:36 xhdpi:48 xxhdpi:72 xxxhdpi:96; do
  density=${entry%%:*}
  size=${entry##*:}
  mkdir -p "android/app/src/main/res/drawable-$density"
  render "android/app/src/main/res/drawable-$density/app_logo.png" "$size" 0.92 none
done

echo "Done."

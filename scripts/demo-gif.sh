#!/bin/bash
# Records the scripted demo and renders docs/demo.gif. Needs ffmpeg + ImageMagick.
set -euo pipefail
cd "$(dirname "$0")/.."

./build.sh >/dev/null
tmp=$(mktemp -d)
HEYDAY_DEMO=1 HEYDAY_RECORD="$tmp/frames" ./build/HeyDay.app/Contents/MacOS/HeyDay >/dev/null 2>&1

read -r w h < <(magick identify -format '%w %h\n' "$tmp/frames/f00000.png")
pad=80
W=$((w + 2 * pad)) H=$((h + 2 * pad))
magick -size ${W}x${H} -define gradient:angle=150 gradient:'#f59e73-#5b4cb3' \
  \( -size ${W}x${H} xc:none -fill 'rgba(0,0,0,0.5)' \
     -draw "roundrectangle $pad,$((pad + 24)) $((pad + w)),$((pad + h + 24)) 38,38" -blur 0x28 \) \
  -composite "$tmp/bg.png"

ffmpeg -y -loglevel error -loop 1 -i "$tmp/bg.png" -framerate 25 -i "$tmp/frames/f%05d.png" \
  -filter_complex "[0][1]overlay=$pad:$pad:shortest=1,scale=640:-1:flags=lanczos,split[a][b];\
[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
  docs/demo.gif
rm -rf "$tmp"
ls -la docs/demo.gif

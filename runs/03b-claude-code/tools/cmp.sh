#!/bin/bash
# Bundle work.glsl, render stills at the given times, and stack reference | own rows into /tmp/cr/cmp.png
set -e
cd "$(dirname "$0")/.."
python3 .claude/skills/shader-art-coding/scripts/glsl_tools.py bundle work.glsl -o final.glsl >/dev/null
W=${W:-640}; H=$((W*9/16))
python3 tools/render.py final.glsl --width $W --height $H --times "$@" --out "/tmp/cr/own_{t:g}.png" 2>&1 | grep -v "^/tmp" || true
args=(); n=0
for t in "$@"; do
  ffmpeg -v error -y -ss $(python3 -c "print(max(0,$t-0.083+0.02))") -i assets/reference.mp4 -frames:v 1 -vf scale=$W:$H /tmp/cr/ref_$t.png
  args+=(-i /tmp/cr/ref_$t.png -i /tmp/cr/own_$(python3 -c "print('%g'%$t)").png); n=$((n+2))
done
layout=""; i=0
for t in "$@"; do
  y=$((i*H)); layout+="0_${y}|${W}_${y}|"; i=$((i+1))
done
ffmpeg -v error -y "${args[@]}" -filter_complex "xstack=inputs=$n:layout=${layout%|}" /tmp/cr/cmp.png
echo /tmp/cr/cmp.png

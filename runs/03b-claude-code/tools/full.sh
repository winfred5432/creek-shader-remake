#!/bin/bash
# Bundle, render stills + video at ${W}x${H} (default 640x360), run score.py into /tmp/cr/score.txt
set -e
cd "$(dirname "$0")/.."
W=${W:-640}; H=$((W*9/16))
python3 .claude/skills/shader-art-coding/scripts/glsl_tools.py bundle work.glsl -o final.glsl >/dev/null
python3 tools/render.py final.glsl --width $W --height $H --times 2 6 12 --out "verify/t{t:g}.png" --video verify/render.mp4 2>/dev/null
python3 tools/score.py --own-dir verify > /tmp/cr/score.txt 2>&1 || true
grep -E "OVER|FAIL|HARD:|INDICATORS:|layout agreement|samples over" /tmp/cr/score.txt

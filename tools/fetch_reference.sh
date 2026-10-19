#!/usr/bin/env bash
# Rebuild assets/ (reference clip, three reference frames, contact sheet) from the public post.
#
# The reference footage is not part of this repository. This script downloads clip 1 of
# https://x.com/sorenxet/status/2111892085444092101 and derives the files the runs were given.
#
# The clip used during the runs was a remux of the same stream whose video track starts at
# pts 0.083 s (747000 ticks of 1/9000000). TASK.md and tools/score.py state every time on that
# timeline. The download starts at pts 3 ticks, so the video packets are shifted to start at
# 747000 ticks; decoded frames are unchanged.
#
# Requires: yt-dlp, ffmpeg and ffprobe (ffmpeg >= 5 for the setts bitstream filter).
# Usage: tools/fetch_reference.sh
set -euo pipefail

cd "$(dirname "$0")/.."
POST="https://x.com/sorenxet/status/2111892085444092101"
OUT="assets"
TARGET_START_PTS=747000          # first video pts of the remux used in the runs, time base 1/9000000
EXPECTED_TIME_BASE="1/9000000"
EXPECTED_FRAMES=338
# md5 over the per-frame md5 list of the decoded video (ffmpeg -f framemd5), recorded from the original clip
EXPECTED_FRAMES_MD5="c7b6298f32211e2f4b93fe7424bf375a"

md5_of() { if command -v md5sum >/dev/null; then md5sum | cut -d' ' -f1; else md5 -q; fi; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$OUT"

echo "[1/4] download clip 1 of the post"
# hls-3793 is the 1920x1080 video rendition, hls-audio-128000-Audio the 128 kb/s audio.
yt-dlp --quiet --no-warnings --playlist-items 1 \
  -f "hls-3793+hls-audio-128000-Audio/bv*[height=1080]+ba" \
  --merge-output-format mp4 -o "$tmp/clip.%(ext)s" "$POST"
clip="$tmp/clip.mp4"

tb="$(ffprobe -v error -select_streams v:0 -show_entries stream=time_base -of csv=p=0 "$clip")"
start="$(ffprobe -v error -select_streams v:0 -show_entries stream=start_pts -of csv=p=0 "$clip")"
if [[ "$tb" != "$EXPECTED_TIME_BASE" ]]; then
  echo "unexpected video time base $tb (want $EXPECTED_TIME_BASE); the download is a different encode" >&2
  exit 1
fi
shift_ticks=$((TARGET_START_PTS - start))

echo "[2/4] shift video timestamps by $shift_ticks ticks -> $OUT/reference.mp4"
ffmpeg -v error -y -i "$clip" -map 0 -c copy \
  -bsf:v "setts=pts=PTS+${shift_ticks}:dts=DTS+${shift_ticks}" "$OUT/reference.mp4"

echo "[3/4] reference frames and contact sheet"
for t in 2.0 6.0 12.0; do
  ffmpeg -v error -y -ss "$t" -i "$OUT/reference.mp4" -frames:v 1 -vf scale=960:540 "$OUT/ref-t$t.png"
done
ffmpeg -v error -y -i "$OUT/reference.mp4" -vf "fps=1,scale=320:-1,tile=5x3" -frames:v 1 "$OUT/contact-sheet.png"

echo "[4/4] verify"
first="$(ffprobe -v error -select_streams v:0 -show_entries frame=pts_time -of csv=p=0 "$OUT/reference.mp4" | awk -F, 'NR==1{print $1}')"
frames_md5="$(ffmpeg -v error -i "$OUT/reference.mp4" -map 0:v -f framemd5 - | grep -v '^#' | awk -F, '{print $6}' | md5_of)"
count="$(ffmpeg -v error -i "$OUT/reference.mp4" -map 0:v -f framemd5 - | grep -vc '^#')"
echo "  first video pts $first s (want 0.083000)"
echo "  decoded frames  $count (want $EXPECTED_FRAMES)"
echo "  frame hashes    $frames_md5 (want $EXPECTED_FRAMES_MD5)"
if [[ "$first" != "0.083000" || "$count" != "$EXPECTED_FRAMES" || "$frames_md5" != "$EXPECTED_FRAMES_MD5" ]]; then
  echo "MISMATCH: assets differ from the clip used in the runs; scores will not be comparable" >&2
  exit 1
fi
echo "OK: $OUT/ matches the clip used in the runs"

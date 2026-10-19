#!/usr/bin/env bash
# Create a stage-3 project directory: the state both agents started from, optionally seeded
# with one run's deliverables so tools/score.py can re-score them.
#
#   tools/make_workspace.sh <dest>                    fresh start: TASK.md, tools/score.py, assets/, skill
#   tools/make_workspace.sh <dest> 03a-dsh            plus that run's shaders, tools, NOTES and verify/
#   tools/make_workspace.sh <dest> 03b-claude-code
#
# Needs assets/ (tools/fetch_reference.sh) and the skill (tools/install_skill.sh) in the repository.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:?usage: make_workspace.sh <dest> [03a-dsh|03b-claude-code]}"
RUN="${2:-}"
SKILL="$REPO/.claude/skills/shader-art-coding"

for f in reference.mp4 ref-t2.0.png ref-t6.0.png ref-t12.0.png contact-sheet.png; do
  [[ -f "$REPO/assets/$f" ]] || { echo "missing assets/$f; run tools/fetch_reference.sh" >&2; exit 1; }
done
[[ -d "$SKILL" ]] || { echo "missing $SKILL; run tools/install_skill.sh" >&2; exit 1; }
if [[ -e "$DEST" && -n "$(ls -A "$DEST")" ]]; then
  echo "$DEST exists and is not empty" >&2; exit 1
fi

mkdir -p "$DEST/tools" "$DEST/assets" "$DEST/verify" "$DEST/.claude/skills" "$DEST/.dsh/skills"
cp "$REPO/task/TASK.md" "$DEST/TASK.md"
cp "$REPO/tools/score.py" "$DEST/tools/score.py"
cp "$REPO"/assets/{reference.mp4,ref-t2.0.png,ref-t6.0.png,ref-t12.0.png,contact-sheet.png} "$DEST/assets/"
cp -R "$SKILL" "$DEST/.claude/skills/shader-art-coding"
ln -sfn ../../.claude/skills/shader-art-coding "$DEST/.dsh/skills/shader-art-coding"

if [[ -n "$RUN" ]]; then
  src="$REPO/runs/$RUN"
  case "$RUN" in
    03a-dsh|03b-claude-code) ;;
    *) echo "unknown run $RUN (want 03a-dsh or 03b-claude-code)" >&2; exit 1 ;;
  esac
  cp "$src"/work.glsl "$src"/final.glsl "$src"/NOTES.md "$DEST/"
  cp "$src"/tools/* "$DEST/tools/"
  cp "$src"/verify/* "$DEST/verify/"
fi
echo "workspace ready: $DEST${RUN:+ (seeded with $RUN)}"
echo "score: (cd $DEST && python3 tools/score.py --own-dir verify)"

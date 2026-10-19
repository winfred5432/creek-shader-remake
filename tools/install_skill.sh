#!/usr/bin/env bash
# Install the shader-art-coding skill at the commit every run used.
#
# Upstream: https://github.com/gokayfem/shader-skills (MIT, copyright 2026 gokayfem).
# The skill is not vendored in this repository; this script fetches it.
#
# Installs into <dest>/.claude/skills/shader-art-coding (read by Claude Code and by tools/score.py)
# and links <dest>/.dsh/skills/shader-art-coding to it (read by DeepSeek Harness).
# Usage: tools/install_skill.sh [dest]      (default: the repository root)
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$REPO}"
URL="https://github.com/gokayfem/shader-skills.git"
COMMIT="b19dcf95591fa60326739d780fe6fa746594fca3"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git clone --quiet "$URL" "$tmp/src"
git -C "$tmp/src" checkout --quiet "$COMMIT"

mkdir -p "$DEST/.claude/skills" "$DEST/.dsh/skills"
rm -rf "$DEST/.claude/skills/shader-art-coding"
cp -R "$tmp/src/skills/shader-art-coding" "$DEST/.claude/skills/shader-art-coding"
ln -sfn ../../.claude/skills/shader-art-coding "$DEST/.dsh/skills/shader-art-coding"

echo "installed shader-art-coding @ ${COMMIT:0:7} into $DEST/.claude/skills (linked from .dsh/skills)"
echo "licence: MIT, see $URL/blob/$COMMIT/LICENSE"

#!/usr/bin/env bash
# dev-tldr installer (macOS / Linux)
#   ./install.sh          -> copy the skill to ~/.claude/skills/dev-tldr (Claude Code)
#   ./install.sh --zip    -> build dist/dev-tldr.zip (Claude Desktop upload)
#   ./install.sh --config -> also create ~/.claude/dev-tldr.config.md if missing
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/skills/dev-tldr"
ZIP=0; CONFIG=0
for a in "$@"; do
  case "$a" in
    --zip) ZIP=1 ;;
    --config) CONFIG=1 ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) echo "Unknown option: $a" >&2; exit 1 ;;
  esac
done

[ -f "$SRC/SKILL.md" ] || { echo "ERROR: $SRC/SKILL.md not found. Run from the repo root." >&2; exit 1; }

if [ "$ZIP" -eq 1 ]; then
  command -v zip >/dev/null || { echo "ERROR: 'zip' is not installed." >&2; exit 1; }
  mkdir -p "$ROOT/dist"
  rm -f "$ROOT/dist/dev-tldr.zip"
  # The zip must contain ONE top-level folder named dev-tldr with SKILL.md inside.
  (cd "$ROOT/skills" && zip -rq "$ROOT/dist/dev-tldr.zip" dev-tldr -x '*.DS_Store')
  echo "Built: $ROOT/dist/dev-tldr.zip"
  echo "Next: Claude Desktop > Settings > Capabilities > Skills > Upload skill."
  exit 0
fi

DEST="$HOME/.claude/skills/dev-tldr"
mkdir -p "$HOME/.claude/skills"
if [ -d "$DEST" ]; then
  read -r -p "Found existing $DEST. Overwrite? (y/n) " ans
  [ "$ans" = "y" ] || { echo "Cancelled."; exit 0; }
  rm -rf "$DEST"
fi
cp -R "$SRC" "$DEST"
echo "Installed skill to $DEST"

if [ "$CONFIG" -eq 1 ]; then
  CFG="$HOME/.claude/dev-tldr.config.md"
  if [ -f "$CFG" ]; then
    echo "Config already exists at $CFG (left untouched)."
  else
    cp "$SRC/references/config.example.md" "$CFG"
    echo "Created $CFG - edit it with your Jira/Confluence/GitHub/Slack scope."
  fi
fi

echo
echo "Next: connect Atlassian, Slack and GitHub (see README), then run: tldr PROJ-123"

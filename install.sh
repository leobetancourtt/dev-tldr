#!/usr/bin/env bash
# dev-tldr installer (macOS / Linux): installs the skill and prepares the sources it reads.
#
#   ./install.sh            Install the skill, log in to GitHub, add Jira/Confluence and Slack
#   ./install.sh --doctor   Check the current setup, change nothing
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/skills/dev-tldr"
DEST="$HOME/.claude/skills/dev-tldr"
ATLASSIAN_MCP_URL="https://mcp.atlassian.com/v1/mcp/authv2"
SLACK_MCP_URL="https://mcp.slack.com/mcp"

ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

mcp_line() { claude mcp list 2>/dev/null | grep -i "$1" | head -1; }

doctor() {
  echo "dev-tldr doctor"
  [ -f "$DEST/SKILL.md" ] && ok "Skill installed: $DEST" || bad "Skill not installed"
  if have gh; then
    gh auth status >/dev/null 2>&1 && ok "GitHub: gh logged in" || bad "GitHub: run  gh auth login --hostname github.com --git-protocol https --web"
  else
    bad "GitHub: gh is not installed (macOS: brew install gh, other: https://cli.github.com)"
  fi
  for s in atlassian slack; do
    line="$(mcp_line "$s")"
    [ -n "$line" ] && ok "$line" || bad "$s: not configured"
  done
  echo "  Logins for Atlassian and Slack are completed inside Claude Code with /mcp."
}

[ "${1:-}" = "--doctor" ] && { doctor; exit 0; }

[ -f "$SRC/SKILL.md" ] || { echo "ERROR: $SRC/SKILL.md not found. Run from the repo root." >&2; exit 1; }
have claude || { bad "Claude Code ('claude') is not installed."; exit 1; }
have gh || { bad "gh is not installed. macOS: brew install gh, other: https://cli.github.com. Then re-run."; exit 1; }

echo "1/3  GitHub"
if gh auth status >/dev/null 2>&1; then ok "gh already logged in"
else
  echo "  Opening the browser to log in. If your org uses SSO, authorize the token for it."
  gh auth login --hostname github.com --git-protocol https --web && ok "gh logged in" || bad "gh login failed. Re-run: gh auth login --hostname github.com --git-protocol https --web"
fi

echo "2/3  Skill"
mkdir -p "$HOME/.claude/skills" && rm -rf "$DEST" && cp -R "$SRC" "$DEST" && ok "Installed: $DEST"

echo "3/3  Jira, Confluence and Slack"
if [ -n "$(mcp_line atlassian)" ]; then ok "Atlassian already configured"
else claude mcp add --transport http --scope user atlassian "$ATLASSIAN_MCP_URL" >/dev/null 2>&1 && ok "Atlassian added" || bad "Could not add Atlassian: claude mcp add --transport http atlassian $ATLASSIAN_MCP_URL"; fi
if [ -n "$(mcp_line slack)" ]; then ok "Slack already configured"
else claude mcp add --transport http --scope user slack "$SLACK_MCP_URL" >/dev/null 2>&1 && ok "Slack added (your workspace admin must approve it)" || bad "Could not add Slack: claude mcp add --transport http slack $SLACK_MCP_URL"; fi

echo
echo "Remaining manual step: start 'claude', run /mcp, and log in to atlassian and slack."
echo "Then try:  tldr <a-ticket-key-you-know>     Re-check any time with: ./install.sh --doctor"

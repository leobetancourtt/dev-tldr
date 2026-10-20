#!/usr/bin/env bash
# dev-tldr installer (macOS / Linux) - interactive wizard.
#
#   ./install.sh            Interactive setup (skill + config + connectors)
#   ./install.sh --yes      Non-interactive; values come from env vars (see below)
#   ./install.sh --doctor   Check the current setup, change nothing
#   ./install.sh --zip      Only build dist/dev-tldr.zip (Claude Desktop upload)
#
# Env vars used as defaults / in --yes mode:
#   TARGET=code|desktop|both  JIRA_DOMAIN  JIRA_PROJECTS  CONFLUENCE_SPACES
#   GITHUB_ORG  GITHUB_REPOS  SLACK_CHANNELS  OUTPUT_DIR
#   GITHUB_TOKEN_SOURCE=gh|paste|skip   GITHUB_PAT (when source=paste)
#   ATLASSIAN_AUTH=oauth|token   ATLASSIAN_EMAIL  ATLASSIAN_API_TOKEN (when auth=token)
#
# Endpoints (MCP/API URLs) live in endpoints.env; override in endpoints.local.env,
# or point ENDPOINTS_FILE at another file.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/skills/dev-tldr"
YES=0; MODE=install
for a in "$@"; do
  case "$a" in
    --yes|-y) YES=1 ;;
    --doctor) MODE=doctor ;;
    --zip) MODE=zip ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "Unknown option: $a" >&2; exit 1 ;;
  esac
done

ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

ask() { # ask "Prompt" "default"
  local def="${2:-}" ans
  if [ "$YES" = 1 ]; then printf '%s' "$def"; return; fi
  read -r -p "  $1${def:+ [$def]}: " ans </dev/tty
  printf '%s' "${ans:-$def}"
}
confirm() { # confirm "Question" default(y|n)
  local def="${2:-y}" ans
  if [ "$YES" = 1 ]; then [ "$def" = y ]; return; fi
  read -r -p "  $1 [$( [ "$def" = y ] && echo Y/n || echo y/N )]: " ans </dev/tty
  ans="${ans:-$def}"; [ "$ans" = y ] || [ "$ans" = Y ]
}

[ -f "$SRC/SKILL.md" ] || { echo "ERROR: $SRC/SKILL.md not found. Run from the repo root." >&2; exit 1; }

# ---- endpoints: env vars > endpoints.local.env > endpoints.env
load_env() { # load_env FILE  (only sets variables that are not already set)
  local f="$1" line k v
  [ -f "$f" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|\#*) continue ;; esac
    k="${line%%=*}"; v="${line#*=}"
    k="$(printf '%s' "$k" | tr -d ' ')"
    v="${v%\"}"; v="${v#\"}"; v="${v%$'\r'}"
    [[ "$k" =~ ^[A-Z][A-Z0-9_]*$ ]] || continue
    [ -n "${!k:-}" ] || export "$k=$v"
  done < "$f"
}
EP_FILES=""
for f in "${ENDPOINTS_FILE:-}" "$ROOT/endpoints.local.env" "$ROOT/endpoints.env"; do
  [ -n "$f" ] && [ -f "$f" ] && { load_env "$f"; EP_FILES="$EP_FILES $(basename "$f")"; }
done
ATLASSIAN_MCP_URL_OAUTH="${ATLASSIAN_MCP_URL_OAUTH:-https://mcp.atlassian.com/v1/mcp/authv2}"
ATLASSIAN_MCP_URL_TOKEN="${ATLASSIAN_MCP_URL_TOKEN:-https://mcp.atlassian.com/v2/mcp}"
SLACK_MCP_URL="${SLACK_MCP_URL:-https://mcp.slack.com/mcp}"
SLACK_OAUTH_CALLBACK_PORT="${SLACK_OAUTH_CALLBACK_PORT:-3118}"
GITHUB_MCP_URL="${GITHUB_MCP_URL:-https://api.githubcopilot.com/mcp}"
GITHUB_API_URL="${GITHUB_API_URL:-https://api.github.com}"
GITHUB_MCP_DOCKER_IMAGE="${GITHUB_MCP_DOCKER_IMAGE:-ghcr.io/github/github-mcp-server}"

DEST="$HOME/.claude/skills/dev-tldr"
CFG="$HOME/.claude/dev-tldr.config.md"
case "$(uname -s)" in
  Darwin) DESKTOP_CFG="$HOME/Library/Application Support/Claude/claude_desktop_config.json" ;;
  *)      DESKTOP_CFG="$HOME/.config/Claude/claude_desktop_config.json" ;;
esac

build_zip() {
  have zip || { bad "'zip' is not installed"; return 1; }
  mkdir -p "$ROOT/dist"; rm -f "$ROOT/dist/dev-tldr.zip"
  (cd "$ROOT/skills" && zip -rq "$ROOT/dist/dev-tldr.zip" dev-tldr -x '*.DS_Store') \
    && ok "Built $ROOT/dist/dev-tldr.zip"
}

mcp_has() { have claude && claude mcp list 2>/dev/null | grep -qi "$1"; }

doctor() {
  step "dev-tldr doctor"
  [ -f "$DEST/SKILL.md" ] && ok "Skill installed: $DEST" || warn "Skill not installed for Claude Code"
  [ -f "$CFG" ] && ok "Config: $CFG" || warn "No config (optional): $CFG"
  if have claude; then
    ok "claude CLI found"
    local list; list="$(claude mcp list 2>/dev/null || true)"
    for s in atlassian slack github; do
      line="$(printf '%s\n' "$list" | grep -i "$s" | head -1)"
      if [ -z "$line" ]; then bad "$s: not configured"
      elif printf '%s' "$line" | grep -qi "connected\|✓"; then ok "$line"
      elif [ "$s" = github ]; then warn "$line  (check the token: expired or missing SSO authorization?)"
      else warn "$line  (run /mcp inside Claude Code to log in)"; fi
    done
  else
    warn "claude CLI not found (fine if you only use Claude Desktop)"
  fi
  if have gh; then gh auth status >/dev/null 2>&1 && ok "gh logged in" || warn "gh installed but not logged in (gh auth login)"
  else warn "gh not installed (optional fallback)"; fi
  [ -f "$DESKTOP_CFG" ] && { grep -q '"github"' "$DESKTOP_CFG" && ok "Desktop config has a github server" || warn "Desktop config has no github server"; }
  echo
  echo "  Logins (Atlassian, Slack) are completed in Claude: /mcp (Code) or Settings > Connectors (Desktop)."
}

[ "$MODE" = zip ] && { build_zip; exit $?; }
[ "$MODE" = doctor ] && { doctor; exit 0; }

# ---------------------------------------------------------------- wizard
step "1/6  Prerequisites"
have claude && ok "claude CLI" || warn "claude CLI not found (Claude Code option unavailable)"
have gh     && ok "gh CLI" || warn "gh CLI not found (optional)"
have docker && ok "docker" || warn "docker not found (needed only for GitHub on Claude Desktop)"
have python3 && ok "python3" || warn "python3 not found (needed only to edit Desktop config)"
have curl   && ok "curl" || warn "curl not found (Jira domain check skipped)"
ok "Endpoints from:${EP_FILES:- (built-in defaults)}"
echo "      atlassian(oauth): $ATLASSIAN_MCP_URL_OAUTH"
echo "      atlassian(token): $ATLASSIAN_MCP_URL_TOKEN"
echo "      slack:            $SLACK_MCP_URL${SLACK_OAUTH_CLIENT_ID:+  (client id set)}"
echo "      github:           $GITHUB_MCP_URL  (api: $GITHUB_API_URL)"

step "2/6  Where do you use Claude?"
TARGET="${TARGET:-}"
if [ -z "$TARGET" ]; then
  if have claude; then def=1; else def=2; fi
  echo "    1) Claude Code   2) Claude Desktop   3) Both"
  c="$(ask 'Choose' "$def")"
  case "$c" in 1) TARGET=code ;; 2) TARGET=desktop ;; 3) TARGET=both ;; *) TARGET=code ;; esac
fi
DO_CODE=0; DO_DESKTOP=0
case "$TARGET" in code|both) DO_CODE=1 ;; esac
case "$TARGET" in desktop|both) DO_DESKTOP=1 ;; esac
if [ "$DO_CODE" = 1 ] && ! have claude; then bad "Claude Code selected but 'claude' CLI is missing. Install it first."; DO_CODE=0; fi
ok "Target: $TARGET"

step "3/6  Scope (press Enter to skip any)"
echo "    Used to focus searches. Nothing here is a secret."
JIRA_DOMAIN="$(ask 'Jira/Confluence domain (e.g. yourorg.atlassian.net)' "${JIRA_DOMAIN:-}")"
JIRA_DOMAIN="${JIRA_DOMAIN#https://}"; JIRA_DOMAIN="${JIRA_DOMAIN%%/*}"
if [ -n "$JIRA_DOMAIN" ] && have curl; then
  if curl -fsS --max-time 6 "https://$JIRA_DOMAIN/_edge/tenant_info" >/dev/null 2>&1; then ok "$JIRA_DOMAIN is reachable"
  else warn "Could not verify $JIRA_DOMAIN (typo, VPN, or offline). Continuing."; fi
fi
JIRA_PROJECTS="$(ask 'Jira project keys, comma-separated (e.g. PAY,BEN)' "${JIRA_PROJECTS:-}")"
CONFLUENCE_SPACES="$(ask 'Confluence space keys (e.g. ENG,PAY)' "${CONFLUENCE_SPACES:-}")"
GITHUB_ORG="$(ask 'GitHub org or user (e.g. your-org)' "${GITHUB_ORG:-}")"
GITHUB_REPOS="$(ask 'GitHub repos, comma-separated' "${GITHUB_REPOS:-}")"
SLACK_CHANNELS="$(ask 'Slack channels, comma-separated, no # (e.g. eng-payments)' "${SLACK_CHANNELS:-}")"
OUTPUT_DIR="$(ask 'Where to save tldr-*.md files' "${OUTPUT_DIR:-$HOME/dev-tldrs}")"

mkdir -p "$HOME/.claude"
if [ -f "$CFG" ] && ! confirm "Config exists at $CFG. Overwrite?" n; then
  warn "Kept existing config"
else
  {
    echo "# dev-tldr config (generated by install.sh on $(date +%F))"
    echo
    echo '```'
    [ -n "$JIRA_DOMAIN" ]        && echo "JIRA_DOMAIN: $JIRA_DOMAIN"
    [ -n "$JIRA_PROJECTS" ]      && echo "JIRA_PROJECTS: $JIRA_PROJECTS"
    [ -n "$CONFLUENCE_SPACES" ]  && echo "CONFLUENCE_SPACES: $CONFLUENCE_SPACES"
    [ -n "$GITHUB_ORG" ]         && echo "GITHUB_ORG: $GITHUB_ORG"
    [ -n "$GITHUB_REPOS" ]       && echo "GITHUB_REPOS: $GITHUB_REPOS"
    [ -n "$SLACK_CHANNELS" ]     && echo "SLACK_CHANNELS: $SLACK_CHANNELS"
    [ -n "$OUTPUT_DIR" ]         && echo "OUTPUT_DIR: $OUTPUT_DIR"
    echo '```'
  } > "$CFG"
  ok "Wrote $CFG"
fi
[ -n "$OUTPUT_DIR" ] && mkdir -p "$OUTPUT_DIR" 2>/dev/null

step "4/6  GitHub credential"
GITHUB_TOKEN_SOURCE="${GITHUB_TOKEN_SOURCE:-}"
TOKEN=""
if [ -z "$GITHUB_TOKEN_SOURCE" ]; then
  if have gh && gh auth status >/dev/null 2>&1; then
    echo "    1) Use my current 'gh' login (fast; token has broad scopes incl. write)"
    echo "    2) Paste a fine-grained read-only token (safer)"
    echo "    3) Skip GitHub"
    c="$(ask 'Choose' 1)"
  else
    echo "    'gh' is not logged in. You can run 'gh auth login' later."
    echo "    2) Paste a fine-grained read-only token (https://github.com/settings/personal-access-tokens/new)"
    echo "    3) Skip GitHub"
    c="$(ask 'Choose' 3)"
  fi
  case "$c" in 1) GITHUB_TOKEN_SOURCE=gh ;; 2) GITHUB_TOKEN_SOURCE=paste ;; *) GITHUB_TOKEN_SOURCE=skip ;; esac
fi
case "$GITHUB_TOKEN_SOURCE" in
  gh)    TOKEN="$(gh auth token 2>/dev/null || true)"; [ -n "$TOKEN" ] && ok "Using token from gh" || bad "gh returned no token" ;;
  paste) TOKEN="${GITHUB_PAT:-}"
         if [ -z "$TOKEN" ] && [ "$YES" = 0 ]; then read -r -s -p "  Paste token (hidden): " TOKEN </dev/tty; echo; fi
         [ -n "$TOKEN" ] && ok "Token received" || bad "No token given" ;;
  *)     warn "GitHub skipped. Coverage will show GitHub unavailable." ;;
esac
if [ -n "$TOKEN" ] && have curl; then
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 -H "Authorization: Bearer $TOKEN" "$GITHUB_API_URL/user" || true)"
  [ "$code" = 200 ] && ok "Token accepted by GitHub" || warn "GitHub answered HTTP $code for this token (expired, or needs SSO authorization)"
fi

step "5/6  Claude Code"
if [ "$DO_CODE" = 1 ]; then
  mkdir -p "$HOME/.claude/skills"
  if [ -d "$DEST" ]; then rm -rf "$DEST"; fi
  cp -R "$SRC" "$DEST" && ok "Skill installed: $DEST"

  # Atlassian
  if mcp_has atlassian; then ok "Atlassian already connected (skipped)"
  elif confirm "Add Atlassian (Jira + Confluence) MCP server?" y; then
    AAUTH="${ATLASSIAN_AUTH:-}"
    if [ -z "$AAUTH" ]; then
      echo "    1) Browser login (OAuth) - default"
      echo "    2) API token, no browser (your Atlassian admin must enable this for the org)"
      c="$(ask 'Choose' 1)"; [ "$c" = 2 ] && AAUTH=token || AAUTH=oauth
    fi
    if [ "$AAUTH" = token ]; then
      echo "    Create a token: https://id.atlassian.com/manage-profile/security/api-tokens"
      AEMAIL="$(ask 'Atlassian account email' "${ATLASSIAN_EMAIL:-}")"
      ATOK="${ATLASSIAN_API_TOKEN:-}"
      if [ -z "$ATOK" ] && [ "$YES" = 0 ]; then read -r -s -p "  Paste API token (hidden): " ATOK </dev/tty; echo; fi
      if [ -z "$AEMAIL" ] || [ -z "$ATOK" ]; then bad "Email and token are required for token auth. Skipped."
      else
        if [ -n "$JIRA_DOMAIN" ] && have curl; then
          code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 -u "$AEMAIL:$ATOK" "https://$JIRA_DOMAIN/rest/api/3/myself" || true)"
          [ "$code" = 200 ] && ok "Token accepted by $JIRA_DOMAIN" || warn "Could not verify the token against $JIRA_DOMAIN (HTTP $code). Scoped tokens can still work with MCP; continuing."
        fi
        B64="$(printf '%s' "$AEMAIL:$ATOK" | base64 | tr -d '\n')"
        claude mcp add --transport http --scope user atlassian "$ATLASSIAN_MCP_URL_TOKEN" -H "Authorization: Basic $B64" >/dev/null 2>&1 \
          && ok "Atlassian added with API token (no login needed)" \
          || bad "Could not add Atlassian. If your admin hasn't enabled API-token auth, re-run and choose browser login."
      fi
    else
      claude mcp add --transport http --scope user atlassian "$ATLASSIAN_MCP_URL_OAUTH" >/dev/null 2>&1 \
        && ok "Atlassian added (login pending)" || bad "Could not add Atlassian. Run: claude mcp add --transport http atlassian $ATLASSIAN_MCP_URL_OAUTH"
    fi
  fi
  # Slack
  if mcp_has slack; then ok "Slack already connected (skipped)"
  elif confirm "Add Slack MCP server? (your workspace admin must approve it)" y; then
    if [ -n "${SLACK_OAUTH_CLIENT_ID:-}" ]; then
      sjson="{\"type\":\"http\",\"url\":\"$SLACK_MCP_URL\",\"oauth\":{\"clientId\":\"$SLACK_OAUTH_CLIENT_ID\",\"callbackPort\":$SLACK_OAUTH_CALLBACK_PORT}}"
      claude mcp add-json --scope user slack "$sjson" >/dev/null 2>&1; rc=$?
    else
      claude mcp add --transport http --scope user slack "$SLACK_MCP_URL" >/dev/null 2>&1; rc=$?
    fi
    [ "$rc" = 0 ] && ok "Slack added (login pending)" || bad "Could not add Slack. Alternative inside Claude Code: /plugin install slack@claude-plugins-official"
  fi
  # GitHub
  if [ -n "$TOKEN" ]; then
    if mcp_has github; then ok "GitHub already configured (skipped)"
    else
      json="{\"type\":\"http\",\"url\":\"$GITHUB_MCP_URL\",\"headers\":{\"Authorization\":\"Bearer $TOKEN\"}}"
      if claude mcp add-json --scope user github "$json" >/dev/null 2>&1 \
         || claude mcp add --transport http --scope user github "$GITHUB_MCP_URL" -H "Authorization: Bearer $TOKEN" >/dev/null 2>&1; then
        ok "GitHub added"
      else bad "Could not add GitHub. See README section 3."; fi
    fi
  fi
else
  warn "Skipped (Claude Code not selected or not installed)"
fi

step "6/6  Claude Desktop"
if [ "$DO_DESKTOP" = 1 ]; then
  build_zip && echo "    Upload it: Settings > Capabilities > Skills > Upload skill  (file: dist/dev-tldr.zip)"
  have open && [ "$(uname -s)" = Darwin ] && [ -f "$ROOT/dist/dev-tldr.zip" ] && confirm "Reveal the ZIP in Finder?" y && open -R "$ROOT/dist/dev-tldr.zip"

  if [ -n "$TOKEN" ]; then
    if ! have docker; then warn "GitHub on Desktop needs Docker (not found). Install Docker Desktop, then re-run."
    elif ! have python3; then warn "python3 missing; add the GitHub server by hand (README section 3)."
    elif confirm "Add GitHub (Docker) server to Claude Desktop config? A backup is made." y; then
      mkdir -p "$(dirname "$DESKTOP_CFG")"
      [ -f "$DESKTOP_CFG" ] && cp "$DESKTOP_CFG" "$DESKTOP_CFG.bak.$(date +%s)"
      if python3 - "$DESKTOP_CFG" "$TOKEN" "$GITHUB_MCP_DOCKER_IMAGE" "${GITHUB_HOST:-}" <<'PY'
import json, os, sys
path, token, image, host = sys.argv[1:5]
cfg = {}
if os.path.exists(path) and os.path.getsize(path):
    with open(path) as f: cfg = json.load(f)
args = ["run", "-i", "--rm", "-e", "GITHUB_PERSONAL_ACCESS_TOKEN"]
env = {"GITHUB_PERSONAL_ACCESS_TOKEN": token}
if host:
    args += ["-e", "GITHUB_HOST"]
    env["GITHUB_HOST"] = host
cfg.setdefault("mcpServers", {})["github"] = {"command": "docker", "args": args + [image], "env": env}
with open(path, "w") as f: json.dump(cfg, f, indent=2)
PY
      then ok "GitHub server written to Desktop config (restart Claude Desktop)"
      else bad "Could not edit $DESKTOP_CFG (invalid JSON?). Backup kept; add it by hand."; fi
    fi
  fi
  echo
  echo "    Manual steps in Claude Desktop (no API for these):"
  echo "      - Settings > Connectors > Atlassian > Connect  (or custom connector: $ATLASSIAN_MCP_URL_OAUTH)"
  echo "      - Settings > Connectors > Slack > Connect"
  echo "      - Restart Claude Desktop, make sure the dev-tldr skill is toggled on"
else
  warn "Skipped (Claude Desktop not selected)"
fi

doctor
echo
printf '\033[1mAlmost done. Remaining manual logins:\033[0m\n'
[ "$DO_CODE" = 1 ] && echo "  Claude Code: start 'claude', run /mcp, and log in to each server marked 'Needs authentication' (Slack always; Atlassian unless you used an API token)."
[ "$DO_DESKTOP" = 1 ] && echo "  Claude Desktop: connect Atlassian and Slack under Settings > Connectors."
echo "  Then try:  tldr <a-ticket-key-you-know>"
echo "  Re-check any time with: ./install.sh --doctor"

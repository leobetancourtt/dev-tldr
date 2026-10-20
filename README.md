# dev-tldr

A Claude skill that turns a **Jira ticket** (key or URL) or an **open question** into a short, evidence-backed `.md` TLDR for developers: max 5 points, each with source link, author and date, plus Links and a Coverage section showing what was searched.

Think "Rovo for devs": it searches **Jira** (incl. comments), **Confluence** (incl. page comments), **GitHub** and **Slack**, and never writes to any of them.

```
tldr PROJ-123
tldr https://yourorg.atlassian.net/browse/PROJ-123
what do I need to know before touching the booking sync?
```

Output: `tldr-<KEY or slug>.md` (English, ~250 words max) in `OUTPUT_DIR` from your config, else the working directory.

---

## Repo layout

```
skills/dev-tldr/
  SKILL.md                      <- the skill
  references/config.example.md  <- optional scope config
install.sh / install.ps1        <- installers (macOS-Linux / Windows)
```

## 1. Get the repo

```bash
git clone <YOUR-REPO-URL> dev-tldr
cd dev-tldr
```

No git? Download the ZIP from the repo page, unzip, and open a terminal in that folder.

---

## 2. Install the skill

Pick the app you use. You can do both.

### Option A: Claude Code (CLI)

Prerequisite: Claude Code installed and logged in.

**With the script (recommended)**

```bash
# macOS / Linux
./install.sh --config

# Windows (PowerShell)
.\install.ps1 -Config
```

This copies the skill to `~/.claude/skills/dev-tldr/` and creates `~/.claude/dev-tldr.config.md` if missing.

**Manually**

```bash
# personal (all projects)
mkdir -p ~/.claude/skills
cp -R skills/dev-tldr ~/.claude/skills/

# or per project, shareable via git
mkdir -p .claude/skills
cp -R skills/dev-tldr .claude/skills/
```

The folder must be named `dev-tldr` and contain `SKILL.md` directly. Restart Claude Code afterwards, then check with `/skills`.

### Option B: Claude Desktop

Prerequisites: a plan with Skills access and "Code execution and file creation" enabled in Settings > Capabilities.

1. Build the upload file:

   ```bash
   ./install.sh --zip        # macOS / Linux
   .\install.ps1 -Zip        # Windows
   ```

   This creates `dist/dev-tldr.zip`. The ZIP must hold one top-level `dev-tldr/` folder with `SKILL.md` inside (the script does this for you).
2. Open **Settings > Capabilities > Skills** (newer builds: **Customize > Skills**) and click **Upload skill**.
3. Select `dist/dev-tldr.zip` and make sure the skill is toggled **on**.

Menu labels vary slightly between app versions.

---

## 3. Connect your sources

The skill uses whatever connectors/MCP servers exist. Connect all three for full coverage. Anything missing shows as unavailable in Coverage; the skill still runs.

### Atlassian (Jira + Confluence)

Official endpoint: `https://mcp.atlassian.com/v1/mcp/authv2` ([Atlassian guide](https://support.atlassian.com/rovo/docs/getting-started-with-the-atlassian-remote-mcp-server/)).

- **Claude Desktop:** Settings > Connectors > find **Atlassian** and Connect. If it isn't listed, use **Add custom connector** with the URL above. Sign in with your Atlassian account and approve the requested scopes (Jira and Confluence read).
- **Claude Code:**

  ```bash
  claude mcp add --transport http atlassian https://mcp.atlassian.com/v1/mcp/authv2
  ```

  Open Claude Code, run `/mcp`, select `atlassian` and complete the browser login.

Your Atlassian admin may need to allow the Rovo MCP server for your site.

### Slack

Official hosted server: `https://mcp.slack.com/mcp` ([Slack docs](https://docs.slack.dev/ai/slack-mcp-server/connect-to-harnesses)). Your **workspace admin must approve** the MCP integration.

- **Claude Desktop:** Settings > Connectors > **Slack** > Connect, then authorize your workspace.
- **Claude Code:** either the plugin route:

  ```
  /plugin install slack@claude-plugins-official
  ```

  or the CLI:

  ```bash
  claude mcp add --transport http --scope local slack https://mcp.slack.com/mcp
  ```

  then run `/mcp` and complete the OAuth flow.

To search private channels and DMs, grant the corresponding scopes when authorizing. Public-only is enough for most tickets.

### GitHub

Create a [fine-grained personal access token](https://github.com/settings/personal-access-tokens/new) with **read-only** access to the repos you need (Contents, Pull requests, Issues, Metadata). If your org uses SSO, authorize the token for it. Never commit the token.

- **Claude Code** (remote server, Claude Code 2.1.1+):

  ```bash
  export GITHUB_PAT="ghp_your_token"
  claude mcp add-json github '{"type":"http","url":"https://api.githubcopilot.com/mcp","headers":{"Authorization":"Bearer '"$GITHUB_PAT"'"}}'
  ```

  Older versions: `claude mcp add --transport http github https://api.githubcopilot.com/mcp -H "Authorization: Bearer $GITHUB_PAT"`. Verify with `claude mcp list`.
- **Claude Desktop:** GitHub's docs state the remote server can't be added as a custom connector (it needs a registered OAuth app), so use the local Docker server. Docker must be running. Edit **Settings > Developer > Edit Config** (`~/Library/Application Support/Claude/claude_desktop_config.json` on macOS, `%APPDATA%\Claude\claude_desktop_config.json` on Windows):

  ```json
  {
    "mcpServers": {
      "github": {
        "command": "docker",
        "args": ["run", "-i", "--rm", "-e", "GITHUB_PERSONAL_ACCESS_TOKEN", "ghcr.io/github/github-mcp-server"],
        "env": { "GITHUB_PERSONAL_ACCESS_TOKEN": "YOUR_GITHUB_PAT" }
  }}}
  ```

  Restart Claude Desktop. Reference: [GitHub MCP Claude install guide](https://github.com/github/github-mcp-server/blob/main/docs/installation-guides/install-claude.md).
- **Fallback without an MCP server:** install the `gh` CLI and run `gh auth login`. In Claude Code the skill falls back to `gh` and to local `git log --grep` when no GitHub tool exists.

---

## 4. Configure (optional)

```bash
cp skills/dev-tldr/references/config.example.md ~/.claude/dev-tldr.config.md
```

Edit `~/.claude/dev-tldr.config.md` (Windows: `%USERPROFILE%\.claude\`):

| Field | Purpose |
|---|---|
| `JIRA_DOMAIN` | Picks the right Atlassian site when several are connected |
| `JIRA_PROJECTS` | Default projects for open questions |
| `CONFLUENCE_SPACES` | Default spaces to search |
| `GITHUB_ORG` / `GITHUB_REPOS` | Scope GitHub search |
| `SLACK_CHANNELS` | Channels to search first |
| `OUTPUT_DIR` | Where `tldr-*.md` is saved |

Never put tokens in this file. Without it the skill still works, just with broader (noisier) searches. Claude Desktop sessions may not read files outside your project; if so, skip the config and mention the scope in your prompt.

---

## 5. Verify

1. Connectors: `claude mcp list` (Code) or Settings > Connectors (Desktop) show Atlassian, Slack and GitHub as connected.
2. Run `tldr <a ticket key you know>`.
3. Open the generated file and check:
   - every numbered point has link, author and date;
   - Coverage lists all four sources with a sensible status;
   - the body is ~250 words or fewer;
   - no PR is presented as linked unless it names the key.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Skill doesn't trigger | Folder must be named `dev-tldr` with `SKILL.md` at its root; restart the app. Try `/dev-tldr PROJ-123` in Claude Code. |
| Upload rejected in Desktop | The ZIP must contain exactly one top-level folder with one `SKILL.md`. Rebuild with `--zip`. |
| Jira says ❌ unavailable | Re-run `/mcp` login; confirm your user can open the ticket in the browser. |
| Slack ❌ or no results | Admin approval pending, or the channel is private and the scope wasn't granted. |
| GitHub ⚠️ no results | Token not authorized for the org (SSO) or repo not covered by the token. |
| Several Atlassian connectors | Set `JIRA_DOMAIN` in the config. |

## Notes

- Internal use only. No open-source license is granted.
- Read-only: the skill never creates, edits, comments or transitions anything.
- Ticket/page/Slack text is treated as data, never as instructions.
- If a source is unavailable it is listed as such in Coverage instead of being filled with guesses.
- Tool names differ between Code and Desktop; the skill is tool-agnostic on purpose.

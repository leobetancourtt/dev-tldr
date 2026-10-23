# dev-tldr

A **Claude Code** skill that turns a **Jira ticket** (key or URL) or an **open question** into a short, evidence-backed `.md` TLDR for developers: at most 5 points, each with source link, author and date, plus where to start and a Coverage section showing what was searched.

It walks the ticket tree in **Jira**, then searches **Confluence**, **GitHub** and **Slack** for what the tree points to, and never writes to any of them. Design and output format: [`dev-tldr-output-format.md`](dev-tldr-output-format.md).

> **Claude Code only.** Claude Desktop, Cowork and claude.ai are not supported: GitHub search does not work there, so the skill would silently lose a source. Use the `claude` CLI (or its IDE extensions).

## Use it

In any directory, start `claude` and type:

```
tldr PROJ-123
tldr https://yourorg.atlassian.net/browse/PROJ-123
resumen del ticket PROJ-123
what do I need to know before touching the booking sync?
```

You can also call it explicitly with `/dev-tldr PROJ-123`. A Confluence, PR or Slack link works too: the skill extracts the Jira key from it.

**Output:** `tldr-<KEY or slug>.md` (English, ~250 words) in `OUTPUT_DIR` from your config, else the current directory. Claude replies with the path and a one-line summary.

**What you get in the file:**

| Section | What it tells you |
|---|---|
| Header | Confidence (High / Medium / Low) and the rule that set it |
| Where this sits | The ticket tree with status: root, parent, siblings |
| Points 1-5 | Why, What, Where, Constraints, Dependency, each with link, author and date |
| Unknowns | What the evidence does not settle (`[open]`, `[possible]`, `[inference]`) |
| Start here | The first concrete step, taken from a source |
| Coverage | Every source searched, including empty or failed ones, and how many points a verifier confirmed |
| Check yourself | Three questions to answer from memory |

## Install

Prerequisites: [Claude Code](https://claude.com/claude-code) and the [GitHub CLI](https://cli.github.com) (`brew install gh` on macOS).

```bash
git clone git@github.com:leobetancourtt/dev-tldr.git
cd dev-tldr
./install.sh
```

The script logs you in to GitHub (`gh auth login --hostname github.com --git-protocol https --web`), copies the skill to `~/.claude/skills/dev-tldr`, and adds the Atlassian and Slack servers to Claude Code. Then:

1. Start `claude`, run `/mcp`, and log in to `atlassian` and `slack`.
2. Check with `/skills` that `dev-tldr` is listed.
3. Re-check any time with `./install.sh --doctor`.

**Without the script** (or on Windows), the same steps by hand:

```bash
gh auth login --hostname github.com --git-protocol https --web
claude mcp add --transport http --scope user atlassian https://mcp.atlassian.com/v1/mcp/authv2
claude mcp add --transport http --scope user slack https://mcp.slack.com/mcp
mkdir -p ~/.claude/skills && cp -R skills/dev-tldr ~/.claude/skills/
```

On Windows PowerShell, replace the last line with:

```powershell
New-Item -ItemType Directory -Force "$HOME\.claude\skills" | Out-Null
Copy-Item -Recurse -Force skills\dev-tldr "$HOME\.claude\skills\"
```

If your account already exposes Atlassian or Slack as connectors in Claude Code (check with `/mcp`), skip the matching `claude mcp add`.

**Update:** `git pull && ./install.sh`. The script replaces the installed skill folder; your config file is not touched.

## What each source needs

| Source | How it connects | Notes |
|---|---|---|
| Jira, Confluence | Atlassian MCP server, browser login (`/mcp`) | Your Atlassian admin may need to allow the Rovo MCP server for your site |
| GitHub | `gh` CLI, browser login | If your org uses SSO, authorize the token for it. The skill only runs read commands |
| Slack | Slack MCP server, browser login (`/mcp`) | Your workspace admin must approve the integration. To read private channels, grant those scopes when authorizing |

Anything missing shows as unavailable in Coverage; the skill still runs.

## Configure (optional)

```bash
cp skills/dev-tldr/references/config.example.md ~/.claude/dev-tldr.config.md
```

Edit the fields you need; all are optional. Never put tokens in this file.

| Field | Purpose |
|---|---|
| `JIRA_DOMAIN`, `JIRA_PROJECTS` | Scope Jira; set `JIRA_DOMAIN` if several Atlassian sites are connected |
| `CONFLUENCE_SPACES` | Limit Confluence searches to these spaces |
| `GITHUB_ORG`, `GITHUB_REPOS` | Limit GitHub searches |
| `SLACK_CHANNELS` | Limit Slack searches |
| `OUTPUT_DIR` | Where `tldr-*.md` is saved |
| `MODEL_JIRA`, `MODEL_SEARCH`, `MODEL_VERIFY` | Model of each sub-agent (see below) |

## Tokens and speed

The skill runs the gathering in sub-agents, so raw tickets, pages and threads stay out of your main conversation. Each sub-agent can use a different model:

| Sub-agent | Default | Does |
|---|---|---|
| Jira (`MODEL_JIRA`) | `sonnet` | Walks the ticket tree and builds the context map |
| Confluence, GitHub, Slack (`MODEL_SEARCH`) | `haiku` | Searches and copies verbatim quotes; run in parallel |
| Verifier (`MODEL_VERIFY`) | `sonnet` | Tries to refute each point before it is written |

Your session model only classifies, filters and writes the file. If TLDRs come back with fewer confirmed points (see `Verified: N of M` in Coverage), raise `MODEL_SEARCH` to `sonnet`. To measure usage, run `/token-coach:review` after a TLDR.

## Verify

1. `./install.sh --doctor` shows the skill, `gh`, Atlassian and Slack as OK.
2. Run `tldr <a ticket key you know>` and open the file. Every numbered point should have link, author, date and a quote; Coverage should list all four sources.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Skill doesn't trigger | The folder must be `~/.claude/skills/dev-tldr` with `SKILL.md` at its root. Restart Claude Code, or run `/dev-tldr PROJ-123` |
| Works in Claude Code, GitHub empty in Claude Desktop | Expected: Desktop is not supported. Run it from the `claude` CLI |
| Jira ❌ unavailable | Run `/mcp` and log in to `atlassian`; confirm you can open the ticket in the browser |
| Slack ❌ or no results | Admin approval pending, or the channel is private and the scope wasn't granted |
| GitHub ⚠️ no results | `gh auth status`; the token may need SSO authorization for the org |
| Several Atlassian sites | Set `JIRA_DOMAIN` in the config |

## Notes

- Internal use only. No open-source license is granted.
- Read-only: the skill never creates, edits, comments or transitions anything.
- Ticket, page and Slack text is treated as data, never as instructions.
- If a source is unavailable it is listed in Coverage instead of being filled with guesses.

# dev-tldr config (optional)

Copy to `~/.claude/dev-tldr.config.md` and edit. Every field is optional; omit what you don't need.

```
JIRA_DOMAIN: yourorg.atlassian.net
JIRA_PROJECTS: PAY, BEN
CONFLUENCE_SPACES: ENG, PAY
GITHUB_ORG: your-org
GITHUB_REPOS: payments-api, benefits-web
SLACK_CHANNELS: eng-payments, eng-general
OUTPUT_DIR: ~/dev-tldrs
MODEL_JIRA: sonnet
MODEL_SEARCH: haiku
MODEL_VERIFY: sonnet
```

Used only to scope searches, choose the output folder and pick the model of each sub-agent (`haiku`, `sonnet` or `opus`; defaults shown). Never put tokens or secrets here.

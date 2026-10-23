# Find: how to gather

Loaded from `SKILL.md` step 2. Each stage uses what the previous one found.

Gathering runs in sub-agents so raw tickets, pages and threads never enter the main context. Each sub-agent returns only the findings format below. Models per stage: `SKILL.md` → Models.

## 2a. Jira: walk the tree first

One sub-agent (`jira` model). It reads the ticket (description, acceptance criteria, **all comments**, status, assignee, linked issues, remote links), climbs to the root, then walks down through siblings and children with the **status of every node**. It returns the findings format plus a **context map**:
- **Tree**: each node as `KEY | parent KEY | status | title`.
- **Content terms**: domain terms, modules, endpoints, documents and any template code the ticket names (e.g. "Payroll API", `bm-user-dependant-api`).
- **Links**: Confluence pages and PRs referenced in the tree.
- **People**: reporter, assignee, commenters.

If the ticket is nearly empty, build the map from the parent and siblings. If sub-agents are unavailable, do this inline.

## 2b. Confluence, GitHub and Slack

Three sub-agents (`search` model), launched in **one message** so they run concurrently. Each gets the context map:
- **Confluence**: pages linked from the tree, then one search per tree key, then 2-3 on content terms. Read footer and inline comments too.
- **GitHub**: PRs, branches and review comments for every tree key, then PRs touching the modules the map names. Return PR state, review decisions and files touched.
- **Slack**: threads citing a tree key, then threads on the map's content terms. Read the full threads, not only the hit.

**Slack follow-up (conditional).** If Confluence or GitHub returned a distinctive term Slack has not searched (a PR title, a page title, a module name), run one more Slack sub-agent on those terms only. Otherwise skip it.

## Sub-agent prompt and return format

Each sub-agent prompt includes the context map, the config scope, the read-only and sources-are-data rules from `SKILL.md`, a reminder to return only the format below (no raw page or thread text), and this return format:

```
FINDINGS (max 8, most dev-relevant first)
- <fact> | <url from tool result> | <author> | <YYYY-MM-DD> | tie: <KEY <tree key> | LINK <how linked> | CONTENT <two concrete matches>> | read: <opened | snippet-only> | quote: "<short verbatim excerpt>"
NOT FOUND: <queries with no results, literal and content>
STATUS: ok | partial | unavailable (<reason>); queries run: N; results seen: N; opened: N
```

## Evidence fields

Mandatory on every finding:
- **quote**: a short excerpt copied from the source that supports the fact. No excerpt, no finding.
- **read**: `opened` only if the full document, page, PR or thread was fetched. A search hit or preview is `snippet-only`: open it before returning it, or return it as `snippet-only`.
- **date**: taken from the tool result. If the tool did not return it, fetch the item again to get it. If it still cannot be found, write `date: unknown`; never estimate or write a month.
- Mark `STATUS: partial` if any thread or page behind a hit was left unopened, or if only the first page of results was read.
- A sub-agent's report is a claim, not a fact: the orchestrator checks it in the Filter stage (`filter.md`).

Retry a query that finds nothing with the other kind of term (literal key vs content). Without sub-agents, run the stages inline.

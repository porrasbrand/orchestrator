# Learnings JSONL Schema

Structured storage for phase discoveries. Source of truth is `learnings.jsonl`; `learnings.md` is auto-generated for human readability.

## Schema

Each line in `.planning/learnings.jsonl` is a valid JSON object:

```jsonl
{"ts":"2026-04-04T12:00:00Z","phase":"01-publish-history","category":"codebase","discovery":"Uses ESM not CommonJS","impact":"high"}
{"ts":"2026-04-04T12:05:00Z","phase":"01-publish-history","category":"api","discovery":"REST endpoints return 404 for missing resources","impact":"medium"}
```

## Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `ts` | ISO 8601 | Yes | Timestamp when learning was recorded |
| `phase` | string | Yes | Phase identifier (e.g., `01-auth-setup`) |
| `category` | enum | Yes | Category of the discovery |
| `discovery` | string | Yes | The learning itself — what was discovered |
| `impact` | enum | No | Impact level (defaults to `medium`) |

## Categories

- `codebase` — Existing code structure, patterns, conventions
- `api` — API behaviors, endpoints, authentication
- `testing` — Test setup, coverage, mocking approaches
- `infrastructure` — Server, deployment, environment setup
- `security` — Auth, secrets, permissions, vulnerabilities
- `performance` — Speed, memory, optimization opportunities
- `other` — Anything not fitting above categories

## Impact Levels

- `high` — Affects multiple phases or architecture decisions
- `medium` — Affects current or adjacent phases
- `low` — Nice to know, minor optimization

## Usage

### Adding a learning

```bash
./scripts/update-learnings.sh <project-path> <phase> <category> "<discovery>" [impact]

# Examples:
./scripts/update-learnings.sh /path/to/project 01-setup codebase "Uses TypeScript 5.2" high
./scripts/update-learnings.sh /path/to/project 02-api api "Requires Bearer token auth" medium
./scripts/update-learnings.sh /path/to/project 03-deploy infrastructure "PM2 ecosystem already exists"
```

### Querying learnings

```bash
./scripts/update-learnings.sh --query <project-path> <filter>

# Filter by category:
./scripts/update-learnings.sh --query /path/to/project category=api

# Filter by phase:
./scripts/update-learnings.sh --query /path/to/project phase=01-setup

# Filter by impact:
./scripts/update-learnings.sh --query /path/to/project impact=high
```

## Auto-generated learnings.md

When learnings are added, `learnings.md` is regenerated from `learnings.jsonl`. The markdown file groups learnings by phase and shows category tags:

```markdown
# Learnings

Discoveries made during execution that inform future phases.

## Phase: 01-setup

- **[codebase]** Uses TypeScript 5.2 *(high)*
- **[infrastructure]** PM2 ecosystem already exists *(medium)*

## Phase: 02-api

- **[api]** Requires Bearer token auth *(medium)*
```

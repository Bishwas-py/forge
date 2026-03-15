---
name: recon
description: >
  Stack-agnostic autonomous security, consistency, and quality auditor.
  Crawls any running web app using Playwright, runs programmatic security and accessibility scans,
  cross-checks UI/API/DB values, attacks forms with wild data, and produces a Confidence Letter
  with a scored report that forge can consume to fix issues.
  Trigger on: recon, audit, security check, consistency check, confidence letter,
  quality audit, end-to-end check, verify the app, check everything.
---

# Recon — Autonomous Security & Consistency Auditor

Recon is a stack-agnostic auditor that crawls any running web application end-to-end. It combines **programmatic security tools** (deterministic, repeatable) with **AI-powered crawling and analysis** (judgment, reasoning) to produce a **Confidence Letter** — a scored, structured report of every issue found.

The Confidence Letter is designed to be consumed by `/forge` — the user runs `/forge read the confidence letter and gain 100%`, forge picks up every issue as a task, fixes them, and the user re-runs `/recon` until 100% confidence is reached.

## Core Principles

- **Stack-agnostic** — Works on any web app: React, Svelte, Vue, Angular, Next.js, Django, FastAPI, Rails, Express, Go, Rust — anything with a running UI server. Auto-detects everything.
- **Programmatic first, AI second** — Run deterministic scripts for facts (security headers, accessibility scores, DB integrity), then AI interprets results and does the judgment work (crawling, cross-checking, form attack analysis).
- **No mocks, no stubs** — Only talks to the real running app, real API, real database.
- **Pure observation** — Reads the UI, queries the API, queries the database. Never modifies production data beyond normal user interaction (clicking, typing, submitting forms).
- **Full transparency** — Every finding includes exact values, evidence, and reproduction steps.
- **Confidence Letter output** — Every run produces a structured, scored report that forge can parse.

## Plugin Map

| Step | Tools | What happens |
|------|-------|-------------|
| Programmatic scans | **Bash** (scripts in `${CLAUDE_SKILL_DIR}/scripts/`) | Security headers, accessibility, DB integrity, API contracts |
| Navigate & interact with UI | **Playwright** | Click through pages, fill forms, take screenshots, extract values |
| Query database | **Bash** (psql/mysql/sqlite via docker exec or direct) | Readonly SELECT queries |
| Hit API endpoints | **Bash** (curl) | Replay API calls, capture raw responses |
| Read project stack | **Glob**, **Read**, **Grep** | Detect frameworks, configs, manifests |

## Phase 1 — Setup (Stack-Agnostic Detection)

Before recon runs, it needs to detect the running targets. Unlike stack-specific tools, recon auto-detects everything.

### 1. Detect UI server

Scan common local development ports. Run using Bash:

```bash
for port in 3000 4173 5173 5174 8000 8080 8888; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port" 2>/dev/null)
  [ "$STATUS" != "000" ] && echo "$STATUS -> localhost:$port is UP"
done
```

- If **exactly one** port responds, that is the UI target.
- If **multiple** respond, present the list and ask the user which is the frontend.
- If **none** respond, ask the user for the URL.

### 2. Detect stack

Read the project directory to fingerprint the stack. Use Glob to find manifest files:

- `package.json` → Node.js (check for `svelte`, `react`, `vue`, `next`, `nuxt`, `angular` in dependencies)
- `pyproject.toml` / `requirements.txt` → Python (check for `django`, `fastapi`, `flask`)
- `go.mod` → Go
- `Cargo.toml` → Rust
- `Gemfile` → Ruby/Rails
- `composer.json` → PHP/Laravel
- `pom.xml` / `build.gradle` → Java/Spring

This informs which programmatic tools to run and how to interpret results.

### 3. Detect database

Find the database by scanning Docker containers and common local ports:

```bash
# Check Docker
docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep -E '5432|3306|27017|6379' || true

# Check local ports
for port in 5432 3306 27017; do
  (echo > /dev/tcp/localhost/$port) 2>/dev/null && echo "localhost:$port is UP"
done
```

Map port to engine:
- 5432 → Postgres
- 3306 → MySQL
- 27017 → MongoDB

If not detected, ask the user for: engine type, connection method (docker container name or direct host:port), user, database name.

### 4. Detect API server

The API server is detected **during the crawl** from network requests, not pre-configured. However, check common patterns first:

```bash
for port in 8000 3001 4000 5000 8080; do
  for path in /docs /health /api /api/health; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port$path" 2>/dev/null)
    [ "$STATUS" != "000" ] && [ "$STATUS" != "404" ] && echo "$STATUS -> localhost:$port$path"
  done
done
```

### 5. Announce targets

Print the detected configuration:

```
Recon targets:
  UI:    http://localhost:5173
  Stack: SvelteKit + FastAPI + Postgres
  API:   http://localhost:8000 (detected)
  DB:    postgres @ docker container "hydra-db" (port 5432)
```

Ask the user to confirm or correct. Do not proceed until confirmed.

## Phase 2 — Programmatic Scan

Run deterministic scripts BEFORE the AI crawl. These produce facts, not opinions. Execute each script from `${CLAUDE_SKILL_DIR}/scripts/` using Bash.

### 1. Security scan

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/security-scan.sh" "<ui_url>"
```

Also run against the API URL if different:
```bash
bash "${CLAUDE_SKILL_DIR}/scripts/security-scan.sh" "<api_url>"
```

Captures: HTTP security headers, CORS configuration, cookie flags, SSL/TLS status, open redirects, information disclosure.

### 2. Accessibility audit

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/accessibility-audit.sh" "<ui_url>"
```

Runs axe-core, pa11y, and Lighthouse if installed. Falls back to Playwright-based checks if no tools available.

### 3. DB integrity check

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/db-integrity.sh" "<engine>" "<container>" "<user>" "<dbname>"
```

Runs: foreign key orphan detection, NULL checks on key columns, duplicate detection, table row counts. Supports postgres, mysql, sqlite.

### 4. API contract validation

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/api-contract.sh" "<api_url>"
```

Discovers OpenAPI spec automatically, validates endpoint liveness, checks for undocumented endpoints.

### 5. Store results

Capture ALL script output. These results feed into the final Confidence Letter. Record each `[PASS]`, `[FAIL]`, `[WARN]`, `[CRITICAL]`, `[INFO]`, and `[SKIP]` finding.

## Phase 3 — Page Discovery

After programmatic scans, crawl the running UI to build a complete page map. This phase uses Playwright exclusively.

### 1. Link crawling

Navigate to the root URL using `browser_navigate`. Take a `browser_snapshot` and extract every link target:

- All `<a href="...">` values
- Navigation elements: sidebar items, navbar links, breadcrumb links, footer links
- Ignore external links, anchor-only links, and `javascript:void(0)` hrefs

For each unvisited route:
1. `browser_navigate` to the URL
2. `browser_snapshot` to capture the page
3. Extract new link targets
4. Add unseen routes to the queue
5. If a link needs a click (client-side routing), use `browser_click` then `browser_snapshot`

Repeat until no new routes are discovered.

### 2. Interaction discovery

Revisit each page and look for hidden routes behind interactive elements:

- **Tabs** — Click each, check if URL changed
- **Buttons** — Click navigation-like buttons ("View", "Open", "Details")
- **Dropdowns/menus** — Click toggles, capture revealed links
- **Modals** — Inspect modal content for links
- **Pagination** — Note the pattern but don't crawl every page

### 3. Auth handling

Detect auth walls by checking for:
- Redirect to `/login`, `/signin`, `/auth`
- Login form in snapshot
- "Unauthorized" or "403" message

When detected:
1. Ask user for credentials
2. Log in via Playwright (`browser_fill_form` + `browser_click`)
3. Verify login succeeded
4. Resume crawling with the session

### 4. Page map output

Print discovered routes:

```
Discovered [N] pages:
  1. /                     (public)
  2. /login                (public)
  3. /dashboard            (authenticated)
  4. /items                (authenticated)
  5. /items/:id            (authenticated)
```

Ask user to confirm, add missing pages, or exclude pages.

## Phase 4 — Crawl & Verify

For each page in the confirmed map:

### 1. Navigate & capture

1. `browser_navigate` to the page
2. `browser_take_screenshot` for visual evidence
3. `browser_console_messages` for JS errors/warnings
4. `browser_network_requests` for failed requests (4xx, 5xx)

### 2. Extract UI values

Use `browser_snapshot` to extract every visible data value:
- Numbers, currencies, percentages
- Statuses, badges, labels
- Dates, times, relative times
- Counts, totals, pagination info

Record element references for tracing.

### 3. Hit the API

From `browser_network_requests`, identify API calls (matching `/api/` or the detected API host). For each:

1. Extract URL, method, headers
2. Replay via `curl` with same auth
3. Capture raw JSON response and status code

### 4. Query database

Construct SELECT queries from API endpoints:
- `/api/items` → `SELECT * FROM items`
- `/api/items/42` → `SELECT * FROM items WHERE id = 42`

Run via Bash using the detected DB connection method. **Readonly only — never run write operations.**

### 5. Three-layer cross-check

Compare values across all three layers. Reference `references/checks.md` for detailed rules.

| Check | Example |
|-------|---------|
| UI vs API | UI shows "$85.00" but API returned `84.995` |
| UI vs DB | UI shows "Active" but DB has `status = 'pending'` |
| API vs DB | API returns 12 items but DB query finds 14 |
| Formatting | DB stores UTC, UI shows wrong timezone |
| Empty states | DB has data but UI shows "No results found" |
| Silent fallbacks | API errored but UI shows stale data |
| Missing data | DB field populated but UI doesn't display it |
| Rounding | DB `0.15`, UI shows "14%" |

Record each mismatch with: page, severity, category, UI/API/DB values, evidence.

### 6. Form attacks

If the page has forms, reference `references/form-attacks.md` for the full input catalog. Submit multiple rounds of wild data:

1. Read field constraints from snapshot (required, maxlength, min, max, pattern)
2. Fill with attack values using `browser_fill_form`
3. Submit with `browser_click`
4. Check result: `browser_snapshot` for UI feedback
5. Re-query API and DB to verify what was stored
6. Record any: DB inconsistency, silent error, crash, validation bypass

### 7. Progress tracking

After each page, print status:

```
[3/17] /dashboard — 2 mismatches (1 critical, 1 warning), 0 form issues
[4/17] /items — 0 mismatches, 1 form issue (silent error on submission)
```

## Phase 5 — Confidence Letter

After all pages are crawled, produce the Confidence Letter. This is the primary output — structured markdown that both humans and forge can read.

### Scoring

Score each category out of 10 based on pass/fail ratio and severity weighting:
- Each CRITICAL finding = -2 points
- Each FAIL = -1 point
- Each WARN = -0.5 points
- Floor at 0, cap at 10

Categories:
1. **Security** — headers, CORS, cookies, XSS, injection, auth bypass
2. **Data Consistency** — UI vs API vs DB mismatches
3. **UI Cleanliness** — Lighthouse score, console errors, broken layouts, accessibility
4. **Accessibility** — axe-core/pa11y results, ARIA, contrast, keyboard nav
5. **Functional Correctness** — forms work, CRUD operations, edge cases handled
6. **DB Integrity** — FK orphans, NULLs, duplicates, constraints
7. **API Contracts** — spec compliance, response shapes, status codes

**Overall Confidence = average of all category scores * 10** (0-100 scale)

### Confidence Letter format

Write to `recon-confidence-letter-YYYY-MM-DD.md` in the project root:

```markdown
# Recon Confidence Letter

**Date**: YYYY-MM-DD HH:MM
**Target**: http://localhost:5173
**Stack**: [detected stack]
**Overall Confidence: [score]/100**

## Category Scores

| Category | Score | Pass | Fail | Warn |
|----------|-------|------|------|------|
| Security | X/10 | N | N | N |
| Data Consistency | X/10 | N | N | N |
| UI Cleanliness | X/10 | N | N | N |
| Accessibility | X/10 | N | N | N |
| Functional Correctness | X/10 | N | N | N |
| DB Integrity | X/10 | N | N | N |
| API Contracts | X/10 | N | N | N |

## Findings

### [SEVERITY] Short title
- **Category**: category name
- **Page**: /route (or "Global" for cross-cutting issues)
- **UI value**: exact value (or N/A)
- **API value**: exact value (or N/A)
- **DB value**: exact value (or N/A)
- **Evidence**: screenshot, endpoint, query used
- **Fix hint**: what to fix and where

...repeat for every finding...

## Actions Required

1. [CRITICAL] description — file hint
2. [CRITICAL] description — file hint
3. [FAIL] description — file hint
4. [WARN] description — file hint
```

### Detailed report

Also write `recon-report-YYYY-MM-DD.md` with full evidence: all screenshots, raw API responses, raw DB query results, console logs, and script outputs. The confidence letter is the summary; the report is the evidence.

### Inline summary

Print to the conversation:

```
Recon complete. {N} pages crawled. {M} issues found.
Overall Confidence: {score}/100

CRITICAL ({count}):
  {route}    {description}

FAIL ({count}):
  {route}    {description}

WARNING ({count}):
  {route}    {description}

INFO ({count}):
  {route}    {description}

Confidence Letter written to: recon-confidence-letter-YYYY-MM-DD.md
Full report written to: recon-report-YYYY-MM-DD.md

To fix all issues: /forge read the confidence letter and gain 100%
```

## Phase 6 — Per-PR Recon (Parallel Branch Auditing)

When the user runs `/forge:recon --per-pr` or asks to "recon all open PRs" or "test each PR branch," recon audits every open PR branch in parallel using git worktrees and isolated server instances.

### Why this exists

Running recon against `main` only tests merged code. Open PRs contain unmerged changes that may introduce regressions, security issues, or data inconsistencies. Per-PR recon catches these before merge by checking out each branch, building it, running servers, and auditing the live result.

### 1. Discover open PRs

List all open PRs for the current repo:

```bash
gh pr list --state open --json number,title,headRefName --limit 20
```

Present the list to the user:

```
Open PRs found:
  #42  feature/user-auth       "Add user authentication"
  #45  fix/pricing-display     "Fix price rounding on order page"
  #48  feature/dashboard-v2    "Redesign dashboard layout"

Run recon on all 3, or select specific PRs?
```

Wait for user confirmation. They may exclude PRs or select specific ones.

### 2. Detect stack and build commands

Before creating worktrees, detect how to build and run the project. Read the project's stored knowledge (from `.claude/CLAUDE.md` or forge's persisted state) or detect fresh:

- **Frontend build**: `npm run build`, `npm run dev`, `pnpm dev`, etc.
- **Backend build**: `pip install -e .`, `cargo build`, `go build`, etc.
- **Frontend start command**: what starts the dev server
- **Backend start command**: what starts the API server
- **DB setup**: does each branch need its own DB, or can they share a read-only DB?

Ask the user to confirm the build/start commands if not already stored.

### 3. Port allocation

Assign unique port ranges to each PR to avoid conflicts. The main app keeps its default ports.

```
Port allocation:
  PR #42 (feature/user-auth):      UI=5180, API=8010
  PR #45 (fix/pricing-display):    UI=5181, API=8011
  PR #48 (feature/dashboard-v2):   UI=5182, API=8012
```

Port formula:
- UI port: `5180 + index`
- API port: `8010 + index`

This keeps all instances on distinct ports with no collisions.

### 4. Create worktrees

For each selected PR, create an isolated git worktree. Use the Agent tool with `isolation: "worktree"` if available, or create worktrees manually:

```bash
git worktree add /tmp/recon-pr-42 origin/feature/user-auth
git worktree add /tmp/recon-pr-45 origin/fix/pricing-display
git worktree add /tmp/recon-pr-48 origin/feature/dashboard-v2
```

Each worktree is a full checkout of that branch in an isolated directory.

### 5. Build and start servers (parallel)

For each worktree, in parallel:

1. **Install dependencies**:
   ```bash
   cd /tmp/recon-pr-42 && npm install  # or pip install, cargo build, etc.
   ```

2. **Start frontend** on the allocated port:
   ```bash
   cd /tmp/recon-pr-42 && PORT=5180 npm run dev &
   ```

3. **Start backend** on the allocated port:
   ```bash
   cd /tmp/recon-pr-42 && PORT=8010 python -m uvicorn app:main &
   ```
   (Adapt commands to the detected stack. Use environment variables or CLI flags to set the port.)

4. **Wait for healthy**: Poll the allocated ports until both UI and API respond:
   ```bash
   for i in $(seq 1 30); do
     curl -s -o /dev/null -w '%{http_code}' http://localhost:5180 && break
     sleep 2
   done
   ```

5. **If build fails**: Record the failure, skip this PR, continue with others. Report the build failure in the final output.

### 6. Run recon per PR (parallel agents)

Dispatch parallel agents — one per PR. Each agent runs the full recon workflow (Phase 1 through Phase 5) against its allocated URLs:

```
Agent 1: recon against http://localhost:5180 (API: http://localhost:8010) — PR #42
Agent 2: recon against http://localhost:5181 (API: http://localhost:8011) — PR #45
Agent 3: recon against http://localhost:5182 (API: http://localhost:8012) — PR #48
```

Each agent:
- Skips Phase 1 setup detection (targets are pre-assigned)
- Runs Phase 2 programmatic scans against its specific URLs
- Runs Phase 3 page discovery
- Runs Phase 4 crawl & verify
- Produces Phase 5 confidence letter, named `recon-confidence-letter-YYYY-MM-DD-pr-{number}.md`

The DB can be shared if all branches use the same schema, or each agent can use its own DB container if the stack supports it. Ask the user during setup.

### 7. Teardown

After all agents complete:

1. **Stop all servers**: Kill the processes started in step 5
   ```bash
   # Kill by port
   lsof -ti:5180 | xargs kill 2>/dev/null
   lsof -ti:8010 | xargs kill 2>/dev/null
   # ... repeat for each PR's ports
   ```

2. **Remove worktrees**:
   ```bash
   git worktree remove /tmp/recon-pr-42 --force
   git worktree remove /tmp/recon-pr-45 --force
   git worktree remove /tmp/recon-pr-48 --force
   ```

3. **Prune stale worktree refs**:
   ```bash
   git worktree prune
   ```

### 8. Per-PR report

After all agents finish, produce a combined summary:

```
Per-PR Recon Complete.

PR #42 (feature/user-auth):      Confidence: 85/100  — 3 issues (1 critical, 2 warnings)
PR #45 (fix/pricing-display):    Confidence: 92/100  — 1 issue (1 warning)
PR #48 (feature/dashboard-v2):   Confidence: 78/100  — 5 issues (2 critical, 2 warnings, 1 info)
                                 BUILD FAILED         — npm install error (missing dep)

Individual confidence letters:
  recon-confidence-letter-2026-03-15-pr-42.md
  recon-confidence-letter-2026-03-15-pr-45.md
  recon-confidence-letter-2026-03-15-pr-48.md

To fix issues in a specific PR:
  git checkout feature/user-auth && /forge read the confidence letter and gain 100%
```

### 9. Integration with forge

When the user wants to fix a specific PR's issues:

1. Checkout that PR's branch: `git checkout feature/user-auth`
2. Run `/forge read the confidence letter and gain 100%` — forge reads `recon-confidence-letter-*-pr-42.md`
3. Forge fixes the issues on that branch
4. Push the fixes to the PR
5. Re-run `/forge:recon --per-pr` or just recon that single branch to verify

### Per-PR mode constraints

- **Max parallel PRs**: Default 5. More than 5 simultaneous builds/servers may exhaust system resources. If more than 5 PRs are open, batch them in groups of 5.
- **Timeout**: Each PR gets 10 minutes max for build + server startup. If it doesn't start in time, skip it.
- **Shared DB**: By default, all PR branches share the same database. If a branch has migration changes, warn the user that the DB may need to be branched too.
- **Resource check**: Before starting, check available memory and CPU. If the system looks resource-constrained, suggest running PRs sequentially instead of in parallel.

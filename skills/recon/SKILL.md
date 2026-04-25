---
name: recon
description: >
  Stack-agnostic autonomous security, consistency, and quality auditor.
  Crawls any running web app using Playwright, runs programmatic security and accessibility scans,
  cross-checks UI/API/DB values, attacks forms with wild data, and produces a Confidence Letter
  with a scored report that forge can consume to fix issues.
  Authors persistent test files in the project's native Playwright flavor (TS/JS/Python/Java/.NET)
  for repeatable checks (zero-token execution) and uses MCP only for exploratory discovery.
  Trigger on: recon, audit, security check, consistency check, confidence letter,
  quality audit, end-to-end check, verify the app, check everything,
  mutation propagation, cross-page consistency, state propagation, data flow audit.
---

# Recon — Autonomous Security & Consistency Auditor

Recon is a stack-agnostic auditor that crawls any running web application end-to-end. It combines **programmatic security tools** (deterministic, repeatable) with **AI-powered crawling and analysis** (judgment, reasoning) to produce a **Confidence Letter** — a scored, structured report of every issue found.

The Confidence Letter is designed to be consumed by `/forge` — the user runs `/forge read the confidence letter and gain 100%`, forge picks up every issue as a task, fixes them, and the user re-runs `/recon` until 100% confidence is reached.

## MANDATORY — Mode Routing (Read This FIRST)

**Before executing ANY phase, determine which mode to run:**

| User says | Mode | Jump to |
|-----------|------|---------|
| `--per-pr`, "per PR", "each PR", "all PRs", "parallel", "isolated", "each branch", "test each", "parellely" | **Per-PR mode** | **Phase 6 ONLY** — skip Phases 1-5 entirely |
| Anything else (no per-PR keywords) | **Standard mode** | Phase 1 → 2 → 3 → 4B → 4C → 4A → 5 |

### Per-PR mode rules (CRITICAL — do NOT violate these):

1. **Do NOT scan localhost ports** — there is nothing running yet, that's the whole point
2. **Do NOT run `pnpm dev` or `npm start`** — environments are managed by `recon-env.sh`
3. **Do NOT fall back to Phase 1** — go directly to Phase 6, section "1. Discover open PRs"
4. **USE `recon-env.sh`** — this script handles git archive extraction, Docker Compose startup, port allocation, health checks, and teardown
5. **Each PR gets its own isolated Docker Compose environment** with dedicated ports — this is non-negotiable

If you catch yourself port-scanning or starting dev servers in per-PR mode, **STOP — you are in the wrong mode.**

## Core Principles

- **Stack-agnostic** — Works on any web app: React, Svelte, Vue, Angular, Next.js, Django, FastAPI, Rails, Express, Go, Rust — anything with a running UI server. Auto-detects everything.
- **Programmatic first, AI second** — Run deterministic scripts for facts (security headers, accessibility scores, DB integrity), then AI interprets results and does the judgment work (crawling, cross-checking, form attack analysis).
- **No mocks, no stubs** — Only talks to the real running app, real API, real database.
- **Pure observation** — Reads the UI, queries the API, queries the database. Never modifies production data beyond normal user interaction (clicking, typing, submitting forms).
- **Full transparency** — Every finding includes exact values, evidence, and reproduction steps.
- **Confidence Letter output** — Every run produces a structured, scored report that forge can parse.

## Execution Strategy — Author Tests, Don't Drive Browsers

Recon uses three approaches to verify an application. Each has a specific role — choosing the wrong one wastes tokens or misses bugs.

| Approach | When recon uses it | Token cost |
|----------|-------------------|------------|
| **MCP browser driving** (`browser_navigate`, `browser_snapshot`, `browser_click`, etc.) | Initial page discovery (Phase 3), exploratory form attack analysis where outcomes are unpredictable, one-off auth flows | High — every interaction is an AI round-trip |
| **Screenshot-based analysis** (`browser_take_screenshot`) | Visual evidence for findings, layout checks | Medium — image processing per shot |
| **Authored test files** (Playwright specs run by the native runner) | All consistency checks, all mutation propagation tests, all repeatable form validation, all cross-page data verification, all real-time channel tests | **Zero** — native runner executes without AI tokens |

### Recon's policy

1. **Author test files for every repeatable check.** If the check can be expressed as an assertion, it belongs in a test file, not in an MCP driving session.
2. Tests are written to the project's recon test directory (see Phase 1 step 6 for path detection) and executed via the project's native Playwright runner. Execution costs zero AI tokens and produces machine-readable JSON results that recon parses for the Confidence Letter.
3. Test files **persist between runs** and grow into a regression suite. Subsequent recon runs re-execute existing tests for free before deciding what new tests to author.
4. **Before authoring a new test, scan the recon test directory for an existing test covering the same behavior.** If found, run it instead of rewriting it.
5. MCP browser driving is reserved for the three cases listed above. If you find yourself using `browser_snapshot` to extract a value you could assert in a test file, **stop and author the test instead.**

## Plugin Map

| Step | Tools | What happens |
|------|-------|-------------|
| Author & run test files | **Write** + **Bash** (native runner from Phase 1.6) | Persistent regression suite, zero-token execution |
| Programmatic scans | **Bash** (scripts in `${CLAUDE_SKILL_DIR}/scripts/`) | Security headers, accessibility, DB integrity, API contracts |
| Navigate & interact with UI (discovery only) | **Playwright** (MCP-driven exploration ONLY — discovery, auth, interactive diagnosis. Not used for repeatable checks) | Click through pages during Phase 3, fill auth forms, diagnose test failures |
| Real-time channel sniffing | **Bash** (`wscat`, `websocat`, `httpx` for SSE) + Playwright's `page.on('websocket')` | Wire-level assertion of channel events |
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

### 6. Test Profile Detection

After stack detection, recon determines which Playwright flavor and file convention to use for authored tests. **Do not hardcode any specific extension or runner** — detect from the project.

#### 6a. Detect Playwright language binding

Check in this priority order:

1. `package.json` contains `@playwright/test` (or recon will install it) → **JS/TS (Node)** — runner is `npx playwright test`
2. `pyproject.toml` / `requirements.txt` contains `playwright` or `pytest-playwright` → **Python** — runner is `pytest`
3. `pom.xml` / `build.gradle` references `com.microsoft.playwright` → **Java** — runner is `mvn test` or `gradle test`
4. `*.csproj` references `Microsoft.Playwright` → **.NET** — runner is `dotnet test`

If no binding is installed, recon picks the binding matching the detected stack from steps 1-2 (JS/TS for Node projects, Python for Python projects, etc.) and installs it.

#### 6b. Detect file convention by scanning existing tests

Run a discovery command to learn the project's naming convention:

```bash
find . -type f \( -name "*.spec.*" -o -name "*.test.*" -o -name "test_*.py" -o -name "*Test.java" -o -name "*Tests.cs" \) \
  -not -path "*/node_modules/*" -not -path "*/.venv/*" -not -path "*/target/*" -not -path "*/bin/*" -not -path "*/obj/*" \
  | head -50
```

Tally the extensions and naming patterns found. The dominant convention wins. If there are no existing tests, fall back to the language default.

Recognised conventions:

| Language | Conventions to detect | Default if none |
|----------|----------------------|-----------------|
| JS/TS | `.spec.ts`, `.spec.js`, `.spec.mjs`, `.test.ts`, `.test.js`, `.e2e.ts` | `.spec.ts` (or `.spec.js` if project is plain JS) |
| Python | `test_*.py` | `test_*.py` |
| Java | `*Test.java` | `*Test.java` |
| .NET | `*Tests.cs` | `*Tests.cs` |

#### 6c. Determine recon test directory

Check for existing test directories in this order — first match wins:

- `tests/recon/`, `e2e/recon/`, `tests/e2e/recon/`
- If a project already has e2e tests at `tests/e2e/`, `e2e/`, `__tests__/`, `playwright/` → create a `recon/` subdirectory inside it
- Otherwise create `tests/recon/`

#### 6d. Detect existing Playwright config

- JS/TS: look for `playwright.config.ts`, `playwright.config.js`, `playwright.config.mjs`
- Python: look for `conftest.py` with playwright fixtures, or `pytest.ini` / `pyproject.toml` with `[tool.pytest.ini_options]`
- Java: look for `playwright` config in `pom.xml`/`build.gradle`
- .NET: look for `playwright.config` in the test project

If none exists, recon generates a minimal one matching the detected language binding.

#### 6e. Announce the test profile

Print the detected profile alongside the targets:

```
Recon test profile:
  Language:    TypeScript (Node)
  Runner:      playwright test
  Convention:  *.spec.ts
  Directory:   tests/recon/
  Config:      playwright.config.ts (existing)
```

Or for Python:

```
Recon test profile:
  Language:    Python
  Runner:      pytest
  Convention:  test_*.py
  Directory:   tests/recon/
  Config:      conftest.py (will generate)
```

The user confirms before recon proceeds. From this point on, **all references to "test files" in subsequent phases use this detected profile** — recon must NOT assume any specific extension or runner.

### 7. Real-Time Channel Detection

Fingerprint real-time technology used by the application. Recon detects this by scanning dependencies and, later, observing network traffic during Phase 3.

#### 7a. Frontend dependency scan

Search the project's frontend dependencies for real-time client libraries:

- `socket.io-client` → Socket.IO
- `ws`, `isomorphic-ws` → raw WebSocket
- `@supabase/supabase-js` (with realtime usage) → Supabase Realtime
- `firebase` (with `onSnapshot`/`onValue`) → Firestore/RTDB listeners
- `@apollo/client` + subscription imports, `urql` + subscription exchange → GraphQL subscriptions
- `phoenix` → Phoenix Channels
- `@microsoft/signalr` → SignalR
- `pusher-js`, `ably`, `pubnub` → managed pub/sub services
- `eventsource` or native `EventSource` usage → SSE

#### 7b. Backend dependency scan

Search the project's backend dependencies:

- `socket.io`, `ws`, `uWebSockets.js` (Node)
- `channels`, `channels-redux`, `django-channels` (Python/Django)
- `fastapi-websocket-pubsub`, `starlette.websockets` (FastAPI/Starlette)
- `flask-socketio` (Flask)
- `actioncable` (Rails)
- `phoenix` (Elixir)
- `tokio-tungstenite`, `axum`'s ws (Rust)
- SSE: any framework's streaming response handler

#### 7c. Announce real-time profile

If real-time dependencies are detected, print:

```
Real-time channels detected:
  Type:        Socket.IO
  Frontend:    socket.io-client (package.json)
  Backend:     socket.io (package.json)
  Note:        Network observation during Phase 3 will capture endpoint and events
```

If no real-time dependencies are found, print: "No real-time channel dependencies detected. Phase 4C will be skipped unless Phase 3 network observation reveals WebSocket/SSE traffic."

Network observation happens during Phase 3 — see Phase 3 step 5.

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

### 5. Real-time channel hygiene (conditional)

**Only run if real-time channels were detected in Phase 1.7.**

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/realtime-hygiene.sh" "<channel_endpoint>" "<auth_token>"
```

Checks:
- Channel endpoint enforces auth (unauthenticated connection should be rejected)
- Channel rejects malformed messages without crashing
- Channel emits a close frame on idle timeout rather than hanging
- Channel does not echo events from one tenant to another (multi-tenancy isolation)

These produce PASS/FAIL findings independent of AI crawling.

### 6. Store results

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

### 5. Real-time network observation

During the Phase 3 crawl, capture real-time traffic from `browser_network_requests`:

- `ws://` or `wss://` upgrades → WebSocket/Socket.IO endpoints
- Requests with `Accept: text/event-stream` or responses with `Content-Type: text/event-stream` → SSE
- Long-poll patterns (same endpoint hit repeatedly with timeout)

For each detected WebSocket, log the endpoint URL and any events observed during the crawl. Update the real-time profile from Phase 1.7:

```
Real-time channels detected (updated after crawl):
  Type:        Socket.IO
  Endpoint:    ws://localhost:8000/socket.io/
  Events seen: user.role.changed, presence.update, notification.new
  Subscribers: /, /admin/stats, /reports/overview
```

If Phase 1.7 found no dependencies but Phase 3 observes WebSocket/SSE traffic, Phase 4C is now enabled.

## Phase 4B — Mutation Propagation Tests (PRIORITY — author these FIRST)

Mutation propagation bugs are the highest-impact, hardest-to-spot defects in any web app. Recon authors these tests BEFORE plain consistency tests (Phase 4A).

> A mutation propagation test verifies that a state change on one page produces the correct downstream effect on every other page that displays derived data.
>
> Pattern: **baseline → mutate → verify-everywhere → cleanup**
>
> 1. Identify mutation sources (pages with forms, role pickers, status toggles, CRUD actions)
> 2. For each mutation source, identify all "downstream display sites" — every other route that shows data derived from what this mutation changes
> 3. Author one test per (mutation, expected delta, downstream sites) tuple

### Linkage discovery heuristic (run BEFORE authoring tests)

1. From Phase 3's page map, classify each page: `mutation-source` (has forms / actions) or `display-only`
2. For each mutation-source page, query the DB schema (`\d table_name` for postgres, `DESCRIBE table_name` for mysql, equivalent for others) to identify which columns the mutation writes to
3. For each affected column, grep the API server for endpoints that read those columns: `grep -rn "column_name" <api_dir>`
4. For each consuming endpoint, find which routes call it (search the frontend for the endpoint path)
5. The result is a linkage map: `(mutation page, mutated column, [downstream display pages])`

### Test templates — adapt to detected language

Recon picks the template matching Phase 1.6's detected profile. Both templates are shown below for reference; **only the one matching the detected language is used.**

**TypeScript template:**

```typescript
// tests/recon/mutation-promote-admin-propagates-to-dashboard.spec.ts
import { test, expect } from '@playwright/test';
import { loginAs, normalizeNumber } from './_helpers';

test('promoting a user to admin increments admin count on every page that displays it', async ({ page }) => {
  await loginAs(page, 'admin');

  // 1. Baseline — read displayed admin count from every downstream site
  const downstreamSites = [
    { route: '/',                 testid: 'dashboard-admin-count' },
    { route: '/admin/stats',      testid: 'admin-stats-admin-count' },
    { route: '/reports/overview', testid: 'reports-admin-count' },
  ];
  const baseline: Record<string, number> = {};
  for (const { route, testid } of downstreamSites) {
    await page.goto(route);
    baseline[route] = normalizeNumber(await page.getByTestId(testid).textContent() ?? '');
  }

  // 2. Mutate — promote a test user via /perms
  await page.goto('/perms');
  const testUser = page.getByRole('row', { name: /recon\.test\.user@example\.com/i });
  await testUser.getByRole('button', { name: /change role/i }).click();
  await page.getByRole('option', { name: 'Admin' }).click();
  await expect(page.getByText(/saved|updated/i)).toBeVisible();

  // 3. Verify-everywhere — every downstream site shows baseline + 1
  for (const { route, testid } of downstreamSites) {
    await page.goto(route);
    const after = normalizeNumber(await page.getByTestId(testid).textContent() ?? '');
    expect(after, `admin count on ${route} did not increment`).toBe(baseline[route] + 1);
  }

  // 4. Cleanup — revert to baseline so the test is idempotent
  await page.goto('/perms');
  await testUser.getByRole('button', { name: /change role/i }).click();
  await page.getByRole('option', { name: 'Member' }).click();
});
```

**Python template:**

```python
# tests/recon/test_mutation_promote_admin_propagates_to_dashboard.py
import pytest
import re
from playwright.sync_api import Page, expect
from ._helpers import login_as, normalize_number


def test_promoting_user_to_admin_increments_admin_count_on_every_display_page(page: Page):
    login_as(page, "admin")

    # 1. Baseline
    downstream_sites = [
        ("/",                 "dashboard-admin-count"),
        ("/admin/stats",      "admin-stats-admin-count"),
        ("/reports/overview", "reports-admin-count"),
    ]
    baseline = {}
    for route, testid in downstream_sites:
        page.goto(route)
        baseline[route] = normalize_number(page.get_by_test_id(testid).text_content() or "")

    # 2. Mutate
    page.goto("/perms")
    test_user = page.get_by_role("row", name=re.compile(r"recon\.test\.user@example\.com", re.I))
    test_user.get_by_role("button", name=re.compile(r"change role", re.I)).click()
    page.get_by_role("option", name="Admin").click()
    expect(page.get_by_text(re.compile(r"saved|updated", re.I))).to_be_visible()

    # 3. Verify-everywhere
    for route, testid in downstream_sites:
        page.goto(route)
        after = normalize_number(page.get_by_test_id(testid).text_content() or "")
        assert after == baseline[route] + 1, f"admin count on {route} did not increment"

    # 4. Cleanup
    page.goto("/perms")
    test_user.get_by_role("button", name=re.compile(r"change role", re.I)).click()
    page.get_by_role("option", name="Member").click()
```

Recon authors a **separate test file per linkage** so the worker pool runs them in parallel, and so failure reports name exactly which linkage broke.

## Phase 4C — Real-Time Channel Propagation Tests (CO-PRIORITY with 4B)

Real-time channels — WebSocket, Socket.IO, Server-Sent Events, GraphQL subscriptions, Phoenix Channels, SignalR, Firestore listeners, Supabase realtime, anything that pushes updates to the client without a page reload — are the highest-failure-rate part of any modern webapp. A mutation that broadcasts over a channel has TWO propagation paths to verify:

1. **The wire path** — does the server actually emit the right message on the channel after the mutation?
2. **The UI path** — does every subscribed page update its DOM correctly when the message arrives, without requiring a reload?

Both can fail independently. Recon must test both.

**Real-time propagation bugs are co-priority with HTTP mutation propagation. Author Phase 4C tests alongside 4B, before Phase 4A consistency tests. If the app has no real-time channels (per Phase 1.7 and Phase 3.5), skip this phase.**

### Linkage discovery for real-time channels

Extend the linkage heuristic from Phase 4B with a real-time variant:

1. From Phase 3's page map and the detected channel info (Phase 1.7 + Phase 3.5), identify each `subscribed-page` — every route that opens a connection to the channel
2. For each mutation source page, query the backend to find which channel events the mutation emits:
   - Socket.IO/ws: grep for `.emit(`, `.broadcast(`, `.to(...).emit(`, `socket.send(`
   - SSE: grep for `yield`/`write` patterns in stream handlers
   - GraphQL subscriptions: grep for `pubsub.publish(`
   - Phoenix: `broadcast(`, `push(`
   - SignalR: `Clients.All.SendAsync(`, `Clients.Group(`
3. Map: `(mutation page, emitted event, [subscribed pages that should react])`

The result is a real-time linkage map distinct from the HTTP linkage map.

### Test pattern — dual verification

Each real-time propagation test verifies both the wire and the UI in a single test, because they're two faces of the same propagation:

> Pattern: **subscribe → baseline → mutate → assert wire message → assert UI update without reload → cleanup**
>
> 1. Open the app in a browser context, subscribed via the channel
> 2. Record baseline UI state on every subscribed page
> 3. Open a sniffer connection to the channel directly (using a CLI client or Playwright's `page.on('websocket')`)
> 4. Trigger the mutation in a separate browser context (or via API call)
> 5. Assert the channel emitted the expected event with the expected payload
> 6. Switch to the subscribed browser context — assert UI updated without `page.goto` or reload
> 7. Cleanup: revert the mutation

The "without reload" part is critical — that's what distinguishes real-time propagation from HTTP propagation. If the test passes only when you reload the page, it's an HTTP test, not a real-time test, and it's hiding a real bug.

### Test templates per channel type

Recon adapts templates to the detected channel and the detected language from Phase 1.6. **Only the template matching the detected profile is used.**

**WebSocket / Socket.IO — TypeScript template:**

```typescript
// tests/recon/realtime-role-change-broadcasts-to-dashboard.spec.ts
import { test, expect, BrowserContext } from '@playwright/test';
import { loginAs, normalizeNumber } from './_helpers';

test('role change broadcasts user.role.changed and updates dashboard without reload', async ({ browser }) => {
  // Two contexts: one watches, one mutates
  const watcherCtx = await browser.newContext();
  const mutatorCtx = await browser.newContext();
  const watcher = await watcherCtx.newPage();
  const mutator = await mutatorCtx.newPage();

  await loginAs(watcher, 'admin');
  await loginAs(mutator, 'admin');

  // 1. Sniff the WebSocket on the watcher
  const wsMessages: any[] = [];
  watcher.on('websocket', (ws) => {
    ws.on('framereceived', (frame) => {
      try { wsMessages.push(JSON.parse(frame.payload as string)); } catch {}
    });
  });

  // 2. Watcher subscribes by visiting the dashboard, baseline the count
  await watcher.goto('/');
  const baseline = normalizeNumber(await watcher.getByTestId('dashboard-admin-count').textContent() ?? '');

  // 3. Mutator promotes a user via /perms
  await mutator.goto('/perms');
  const testUser = mutator.getByRole('row', { name: /recon\.test\.user@example\.com/i });
  await testUser.getByRole('button', { name: /change role/i }).click();
  await mutator.getByRole('option', { name: 'Admin' }).click();
  await expect(mutator.getByText(/saved|updated/i)).toBeVisible();

  // 4. Wire assertion — watcher's socket received the broadcast
  await expect.poll(() => wsMessages.find((m) => m?.event === 'user.role.changed'),
    { timeout: 5000 }).toMatchObject({
      event: 'user.role.changed',
      payload: { newRole: 'admin' },
    });

  // 5. UI assertion — watcher's dashboard updated WITHOUT reload
  // Note: NO watcher.goto() and NO watcher.reload() here
  await expect.poll(
    async () => normalizeNumber(await watcher.getByTestId('dashboard-admin-count').textContent() ?? ''),
    { timeout: 5000 },
  ).toBe(baseline + 1);

  // 6. Cleanup
  await mutator.goto('/perms');
  await testUser.getByRole('button', { name: /change role/i }).click();
  await mutator.getByRole('option', { name: 'Member' }).click();
});
```

**SSE — Python template:**

```python
# tests/recon/test_realtime_notification_appears_without_reload.py
import re, json, threading
import httpx
from playwright.sync_api import Page, expect, BrowserContext
from ._helpers import login_as


def test_new_notification_streams_via_sse_and_appears_in_navbar_without_reload(page: Page, context: BrowserContext):
    login_as(page, "admin")
    page.goto("/")

    # 1. Open a parallel SSE sniffer (auth cookie shared from browser context)
    cookies = context.cookies()
    cookie_header = "; ".join(f"{c['name']}={c['value']}" for c in cookies)
    sse_messages = []

    def sniff():
        with httpx.stream("GET", "http://localhost:8000/api/notifications/stream",
                         headers={"Accept": "text/event-stream", "Cookie": cookie_header},
                         timeout=10) as r:
            for line in r.iter_lines():
                if line.startswith("data:"):
                    sse_messages.append(json.loads(line[5:].strip()))
                if len(sse_messages) >= 1:
                    break

    sniffer = threading.Thread(target=sniff, daemon=True)
    sniffer.start()

    baseline = int(page.get_by_test_id("notif-badge").text_content() or "0")

    # 2. Trigger a notification via API
    httpx.post("http://localhost:8000/api/notifications",
               json={"to": "admin", "text": "recon test notification"},
               cookies={c["name"]: c["value"] for c in cookies}).raise_for_status()

    # 3. Wire assertion — SSE delivered the message
    sniffer.join(timeout=5)
    assert any(m.get("type") == "notification.new" for m in sse_messages), \
        "SSE channel did not deliver notification.new"

    # 4. UI assertion — badge updated without reload
    expect(page.get_by_test_id("notif-badge")).to_have_text(str(baseline + 1), timeout=5000)
```

For other channel types (Phoenix Channels, SignalR, GraphQL subscriptions, managed services like Pusher/Ably), recon adapts the same dual-verification structure using the appropriate sniffer:

- GraphQL subscriptions: a second `urql`/`Apollo` client opens the subscription directly
- Phoenix: a separate `phoenix.js` socket joins the channel
- SignalR: a second `HubConnection` listens
- Pusher/Ably/PubNub: their respective JS SDKs run in a Node-side helper

Recon never mocks the channel — that defeats the purpose. If the channel requires special test infrastructure (e.g., a Redis pub/sub backend), recon notes the dependency and uses the real one.

### Reconnection and stale-subscription tests

For every detected channel, recon ALSO authors a reconnection test, because the most common real-time bugs hide here:

```typescript
test('dashboard recovers and re-syncs after socket disconnect', async ({ page, context }) => {
  await loginAs(page, 'admin');
  await page.goto('/');
  const baseline = normalizeNumber(await page.getByTestId('dashboard-admin-count').textContent() ?? '');

  // Force-close all websockets on the page
  await page.evaluate(() => {
    // @ts-expect-error — accessing global socket reference if exposed; otherwise simulate offline
  });
  await context.setOffline(true);
  await page.waitForTimeout(2000);
  await context.setOffline(false);

  // While offline, mutate via API directly
  // ... mutation ...

  // Assert the page eventually re-syncs (either via reconnect+catchup or a refetch)
  await expect.poll(
    async () => normalizeNumber(await page.getByTestId('dashboard-admin-count').textContent() ?? ''),
    { timeout: 10_000 },
  ).toBe(baseline + 1);
});
```

If reconnect tests fail, the app is silently stale for any user whose connection blips — which on mobile is most users, most of the time. **These are not edge cases.**

## Phase 4A — Author Test Files (token-cheap, persistent)

This phase covers all remaining checks not covered by Phase 4B (mutation propagation) and Phase 4C (real-time propagation). Recon authors test files in the language and convention detected in Phase 1.6, in the recon test directory.

**Before authoring any test, scan the recon test directory for an existing test covering the same behavior. If found, run it instead of rewriting it.**

### 1. Consistency test files

Author one consistency test file per route. Each test file:

- Fetches the page's API endpoints via Playwright's request fixture (no browser needed for the API hit)
- Queries the DB via the recon DB helper (see item 3 below)
- Loads the page once, extracts displayed values via accessible locators (`getByTestId`, `getByRole`, `getByLabel`)
- Asserts UI === API === DB with format normalisers for currency, dates, abbreviated numbers ("1.2k"), timezones

Reference `references/checks.md` for detailed cross-check rules.

### 2. Form attack test files

For pages with forms, author parameterised test files over the attack matrix from `references/form-attacks.md`. One test per (field, attack) pair so failures are surgical.

### 3. DB helper

Author a DB helper in the recon test directory:

- JS/TS: `_helpers/db.ts` exporting a typed `getDb()` function
- Python: `_helpers/db.py` exporting `get_db()`
- Java/.NET: equivalent helper class

The helper reads connection details from environment variables set by the user (or the per-PR Docker env) and supports postgres/mysql/sqlite.

### 4. Run all authored tests

Run all tests (from Phases 4B, 4C, and 4A) in one command using the runner from Phase 1.6:

- JS/TS: `npx playwright test <recon-dir> --reporter=json > /tmp/recon-results.json`
- Python: `pytest <recon-dir> --json-report --json-report-file=/tmp/recon-results.json`
- Java: `mvn test -Dtest='Recon*' -Dsurefire.reportFormat=json`
- .NET: `dotnet test --logger "json;LogFileName=/tmp/recon-results.json"`

Parse the JSON to populate findings for the Confidence Letter.

### 5. MCP fallback

Fall back to MCP `browser_*` tools ONLY when a test fails in a way that needs interactive diagnosis (e.g., understanding why a selector didn't match, or what a page actually rendered). This is the exception, not the rule.

### 6. Progress tracking

After running all tests, print status:

```
Test execution complete:
  Phase 4B (mutation propagation):   12 tests — 10 passed, 2 failed
  Phase 4C (real-time propagation):   5 tests —  4 passed, 1 failed
  Phase 4A (consistency + forms):    38 tests — 35 passed, 2 failed, 1 skipped
  MCP follow-up:                      3 failures investigated interactively
```

## Phase 5 — Confidence Letter

After all pages are crawled and all tests are executed, produce the Confidence Letter. This is the primary output — structured markdown that both humans and forge can read.

### Scoring

Score each category out of 10 based on pass/fail ratio and severity weighting:
- Each failed mutation/real-time propagation = -3 points (integrity bugs)
- Each failed reconnect test = -2 points
- Each CRITICAL finding = -2 points
- Each FAIL = -1 point
- Each WARN = -0.5 points
- Each channel hygiene FAIL = -1 point
- Floor at 0, cap at 10

Categories:
1. **Mutation Propagation** — cross-page state consistency after mutations (HTTP path)
2. **Real-Time Propagation** — channel wire delivery + UI update without reload
3. **Security** — headers, CORS, cookies, XSS, injection, auth bypass
4. **Data Consistency** — UI vs API vs DB mismatches (per-page, non-mutation)
5. **UI Cleanliness** — Lighthouse score, console errors, broken layouts, accessibility
6. **Accessibility** — axe-core/pa11y results, ARIA, contrast, keyboard nav
7. **Functional Correctness** — forms work, CRUD operations, edge cases handled
8. **DB Integrity** — FK orphans, NULLs, duplicates, constraints
9. **API Contracts** — spec compliance, response shapes, status codes

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
| Mutation Propagation | X/10 | N | N | N |
| Real-Time Propagation | X/10 | N | N | N |
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
- **Linkage**: /source-page (mutation) → /downstream-page-1, /downstream-page-2 (affected field)
- **Wire**: (real-time only) socket emitted event with payload ✓ / ✗
- **UI**: (real-time only) page updated without reload ✓ / ✗
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

Also write `recon-report-YYYY-MM-DD.md` with full evidence: all screenshots, raw API responses, raw DB query results, console logs, test runner JSON output, and script outputs. The confidence letter is the summary; the report is the evidence.

### Inline summary

Print to the conversation:

```
Recon complete. {N} pages crawled. {M} issues found.
Overall Confidence: {score}/100

REAL-TIME PROPAGATION FAILURES ({count}) — fix these first, real-time bugs ship silently:
  /perms →[user.role.changed]→ /            UI did not update without reload
  notification.new                            channel did not emit on POST /notifications

HTTP PROPAGATION FAILURES ({count}) — fix these next, they're integrity bugs:
  /perms → /dashboard                         admin count did not increment after role change

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

> **STOP** — If you reached this phase, you MUST be in per-PR mode. That means:
> - You skipped Phases 1-5 (they don't apply here)
> - You have NOT scanned localhost ports or started `pnpm dev`
> - You are about to use `recon-env.sh` to spin up isolated Docker environments
> - If any of the above is wrong, go back to the Mode Routing table at the top
>
> **Trigger phrases**: `--per-pr`, "per PR", "each PR", "all PRs", "parallel", "isolated", "each branch", "test each", "parellely", "each isolated"

When the user runs `/forge:recon --per-pr` or asks to "recon all open PRs" or "test each PR branch," recon audits every open PR branch in parallel using **isolated Docker Compose environments** managed by the `recon-env.sh` orchestration script.

### Why this exists

Running recon against `main` only tests merged code. Open PRs contain unmerged changes that may introduce regressions, security issues, or data inconsistencies. Per-PR recon catches these before merge by checking out each branch, building it in an isolated Docker environment, and auditing the live result.

### Architecture

Each PR gets a fully isolated environment:

```
PR #42 ─── git archive ─── docker compose -p recon-42 ─── UI :5180, API :8010, DB :5442
PR #45 ─── git archive ─── docker compose -p recon-45 ─── UI :5181, API :8011, DB :5443
PR #48 ─── git archive ─── docker compose -p recon-48 ─── UI :5182, API :8012, DB :5444
```

Branch code is extracted via `git archive` into `/tmp/recon-envs/recon-<id>/src/` — no git worktrees needed. Docker Compose's `-p` (project name) flag namespaces ALL resources — containers, networks, volumes — so environments are completely isolated from each other.

### The `recon-env.sh` script

All environment lifecycle operations use `${CLAUDE_SKILL_DIR}/scripts/recon-env.sh`:

```bash
# Spin up an isolated environment for a PR
bash "${CLAUDE_SKILL_DIR}/scripts/recon-env.sh" up <pr_number> <branch> <ui_port> <api_port> <db_port>

# Check if it's running
bash "${CLAUDE_SKILL_DIR}/scripts/recon-env.sh" status <pr_number>

# Tear it down
bash "${CLAUDE_SKILL_DIR}/scripts/recon-env.sh" down <pr_number>

# List all active environments
bash "${CLAUDE_SKILL_DIR}/scripts/recon-env.sh" list

# Allocate port ranges for N PRs
bash "${CLAUDE_SKILL_DIR}/scripts/recon-env.sh" ports <count>

# Destroy everything
bash "${CLAUDE_SKILL_DIR}/scripts/recon-env.sh" nuke
```

The script handles: branch code extraction via `git archive`, Docker Compose startup with port injection via `RECON_UI_PORT`/`RECON_API_PORT`/`RECON_DB_PORT` environment variables, health polling, metadata tracking, and full cleanup.

### 1. Discover open PRs

List all open PRs:

```bash
gh pr list --state open --json number,title,headRefName --limit 20
```

Present the list and wait for user confirmation. They may exclude PRs or select specific ones.

### 2. Check for Docker Compose file

The project needs a `docker-compose.yml` (or `compose.yml`) that uses environment variables for port binding. Check if one exists:

- If the project already has a compose file that supports port variables, use it directly.
- If the project has a compose file with hardcoded ports, inform the user that ports need to be parameterized. Suggest using `${RECON_UI_PORT:-5173}` syntax for default-with-override.
- If no compose file exists, **generate one** based on the detected stack from Phase 1. The compose file should use `RECON_UI_PORT`, `RECON_API_PORT`, and `RECON_DB_PORT` environment variables.

Example compose file structure for a typical stack:

```yaml
services:
  frontend:
    build: ./frontend
    ports:
      - "${RECON_UI_PORT:-5173}:5173"
  backend:
    build: ./backend
    ports:
      - "${RECON_API_PORT:-8000}:8000"
    environment:
      - DATABASE_URL=postgresql://user:pass@db:5432/app
  db:
    image: postgres:16
    ports:
      - "${RECON_DB_PORT:-5432}:5432"
    environment:
      - POSTGRES_PASSWORD=pass
      - POSTGRES_DB=app
```

### 3. Allocate ports and spin up environments

Use the script to allocate ports and spin up each PR:

```bash
# See what ports will be assigned
bash "${CLAUDE_SKILL_DIR}/scripts/recon-env.sh" ports 3

# Spin up each PR environment
bash "${CLAUDE_SKILL_DIR}/scripts/recon-env.sh" up 42 feature/user-auth 5180 8010 5442
bash "${CLAUDE_SKILL_DIR}/scripts/recon-env.sh" up 45 fix/pricing-display 5181 8011 5443
bash "${CLAUDE_SKILL_DIR}/scripts/recon-env.sh" up 48 feature/dashboard-v2 5182 8012 5444
```

The script will:
1. Extract branch code via `git archive` into `/tmp/recon-envs/recon-<id>/src/`
2. Find the docker-compose file in the extracted directory
3. Start Docker Compose with `RECON_UI_PORT`, `RECON_API_PORT`, `RECON_DB_PORT` injected
4. Poll until UI and API are healthy (120s timeout)
5. Report the status

**Exit codes:**
- `0` — fully healthy, ready for recon
- `1` — error (build failed, git error)
- `2` — code extracted but no compose file found (Claude should generate one)
- `3` — running but not all services are healthy

If exit code is `2`, generate a `docker-compose.yml` in the extracted directory, then re-run the `up` command.

If a PR fails to start, log the failure and continue with the others.

### 4. Run recon per PR (parallel agents)

Dispatch parallel agents — one per PR. Each agent runs the full recon workflow (Phase 2 through Phase 5) against its allocated URLs:

```
Agent 1: recon against http://localhost:5180 (API: http://localhost:8010, DB: localhost:5442) — PR #42
Agent 2: recon against http://localhost:5181 (API: http://localhost:8011, DB: localhost:5443) — PR #45
Agent 3: recon against http://localhost:5182 (API: http://localhost:8012, DB: localhost:5444) — PR #48
```

Each agent:
- Skips Phase 1 setup detection (targets are pre-assigned) — **inherits the test profile from Phase 1.6** (agents do NOT re-detect, they receive the language, runner, convention, and directory as parameters)
- Runs the project's native test runner against existing recon tests BEFORE doing any MCP work — re-executing the persistent test suite costs zero tokens and catches regressions immediately
- Runs Phase 2 programmatic scans against its specific URLs
- Runs Phase 3 page discovery
- Runs Phase 4B, 4C, and 4A (authoring new tests as needed)
- Produces Phase 5 confidence letter, named `recon-confidence-letter-YYYY-MM-DD-pr-{number}.md`

### 5. Teardown

After all agents complete, clean up every environment:

```bash
# Tear down each PR individually
bash "${CLAUDE_SKILL_DIR}/scripts/recon-env.sh" down 42
bash "${CLAUDE_SKILL_DIR}/scripts/recon-env.sh" down 45
bash "${CLAUDE_SKILL_DIR}/scripts/recon-env.sh" down 48

# Or nuke everything at once
bash "${CLAUDE_SKILL_DIR}/scripts/recon-env.sh" nuke
```

The script stops Docker Compose (with volume removal), kills any orphan processes on the allocated ports, and removes the extracted source directory.

### 6. Per-PR report

After all agents finish, produce a combined summary:

```
Per-PR Recon Complete.

PR #42 (feature/user-auth):      Confidence: 85/100  — 3 issues (1 critical, 2 warnings)
PR #45 (fix/pricing-display):    Confidence: 92/100  — 1 issue (1 warning)
PR #48 (feature/dashboard-v2):   BUILD FAILED         — docker compose error (missing Dockerfile)

Individual confidence letters:
  recon-confidence-letter-2026-03-15-pr-42.md
  recon-confidence-letter-2026-03-15-pr-45.md

To fix issues in a specific PR:
  git checkout feature/user-auth && /forge read the confidence letter and gain 100%
```

### 7. Integration with forge

When the user wants to fix a specific PR's issues:

1. Checkout that PR's branch: `git checkout feature/user-auth`
2. Run `/forge read the confidence letter and gain 100%` — forge reads `recon-confidence-letter-*-pr-42.md`
3. Forge fixes the issues on that branch
4. Push the fixes to the PR
5. Re-run `/forge:recon --per-pr` or recon that single branch to verify

### Per-PR mode constraints

- **Max parallel PRs**: Default 5. More than 5 simultaneous Docker environments may exhaust system resources. If more than 5 PRs are open, batch them in groups of 5.
- **Timeout**: Each PR gets 120 seconds for Docker Compose startup + health check. If it doesn't start in time, skip it.
- **Docker required**: Per-PR mode requires Docker and Docker Compose to be installed and running.
- **Compose file**: The project's docker-compose file must support port parameterization via `RECON_UI_PORT`, `RECON_API_PORT`, `RECON_DB_PORT` environment variables. If it doesn't, Claude will modify or generate one.
- **Resource check**: Before starting, verify Docker has sufficient resources allocated. If the system looks constrained, suggest running PRs sequentially.

## Tips

- If a propagation test fails intermittently, it's a race condition — either the UI uses stale cached data or the API doesn't invalidate properly. Both are real bugs, not flaky tests.
- Author propagation tests for every mutation page, even if you think no other page consumes the data. Recon's grep-based linkage discovery often surfaces consumers the user forgot about.
- After authoring tests, commit the recon test directory to the repo. Subsequent recon runs re-execute existing tests for free before authoring new ones.
- Don't hardcode any specific test file extension — always use the convention detected in Phase 1.6. A Python codebase with `test_*.py` files should never end up with a stray file in a different convention from recon.
- If a real-time test passes only after `page.reload()`, delete the reload and let it fail. The failure is the bug. Real-time means real-time.
- Reconnection tests are not optional. The most common real-time bug is "works on first load, silently stale forever after a 2-second network blip."
- Sniff the wire AND check the UI. A test that only checks the UI lets backend bugs hide; a test that only checks the wire lets frontend bugs hide. Recon checks both in one test.
- If the project uses a managed service (Pusher, Ably, Supabase Realtime, Firestore), the wire sniffer runs against their client SDK in a Node helper — recon does NOT use the service's admin/debug API as that bypasses the actual delivery path.

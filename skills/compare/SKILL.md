---
name: compare
description: >
  Compare two systems side-by-side. Analyzes UI flows, logical architecture, data handling,
  security posture, and technical patterns between two running apps or two codebases.
  Use with --mode recon to crawl both UIs, or --mode code to compare codebases.
  Trigger on: compare systems, compare apps, side-by-side comparison,
  how does X differ from Y, compare these two, diff two systems.
argument-hint: "<system_a> <system_b> [--mode recon|code]"
---

# Compare — Side-by-Side System Analysis

Compare analyzes two systems and produces a structured differences report. It supports two modes:

- **`--mode recon`** (default) — Crawls both running UIs using Playwright, runs recon-style checks on each, then diffs the results.
- **`--mode code`** — Reads both codebases (no running server needed), compares architecture, logic flows, patterns, and structure.

## Usage

```
/forge:compare http://localhost:3000 http://localhost:5173
/forge:compare http://localhost:3000 http://localhost:5173 --mode recon
/forge:compare /path/to/project-a /path/to/project-b --mode code
```

## Plugin Map

| Step | Tools | What happens |
|------|-------|-------------|
| Crawl UIs | **Playwright** | Navigate both apps, capture pages, extract values |
| Compare data | **Bash** (curl, psql) | Hit APIs, query DBs for both systems |
| Read codebases | **Glob**, **Read**, **Grep** | Analyze architecture, patterns, conventions |
| Generate report | **Write** | Produce comparison report |

## Mode: Recon (UI + API + DB comparison)

### Phase 1 — Setup

Detect targets for BOTH systems. For each system:

1. Confirm the UI URL is reachable
2. Detect the API server (from network requests or common ports)
3. Detect the database (Docker containers, local ports)
4. Detect the stack (package.json, requirements.txt, etc.)

Print both targets side by side:

```
Compare targets:
  System A: http://localhost:3000 (React + Express + MySQL)
  System B: http://localhost:5173 (SvelteKit + FastAPI + Postgres)
```

Ask user to confirm.

### Phase 2 — Parallel Page Discovery

Crawl both UIs simultaneously (or sequentially if resource-constrained). For each system:

1. Build a complete page map using Playwright
2. Handle auth (ask user for credentials for each system)
3. Produce a page map

Then compare the page maps:

```
Page Map Comparison:
  Both:      /, /login, /dashboard, /items, /items/:id
  Only in A: /settings, /admin
  Only in B: /analytics, /reports
```

### Phase 3 — Side-by-Side Crawl

For each page that exists in BOTH systems:

1. Navigate to the page in System A, take screenshot, extract values
2. Navigate to the same page in System B, take screenshot, extract values
3. Compare:
   - **Visual layout** — How different do the pages look?
   - **Data display** — Are the same fields shown? Same format?
   - **Navigation** — Same links/buttons available?
   - **Forms** — Same fields? Same validation?
   - **API calls** — What endpoints does each hit?
   - **Error handling** — How does each handle edge cases?

For pages unique to one system, document what exists and note the gap.

### Phase 4 — Security Posture Comparison

Run `${CLAUDE_SKILL_DIR}/../recon/scripts/security-scan.sh` against both systems. Compare:

- Security headers (which system has better coverage)
- CORS configuration
- Cookie security
- Auth implementation
- Form validation strictness

### Phase 5 — Data Flow Comparison

For shared API endpoints:
1. Hit the same endpoint on both systems
2. Compare response shapes (fields, types, nesting)
3. Compare response sizes
4. Compare error handling (what happens with bad requests)

### Phase 6 — Comparison Report

Write to `recon-compare-YYYY-MM-DD.md`:

```markdown
# System Comparison Report

**Date**: YYYY-MM-DD
**System A**: http://localhost:3000 (React + Express + MySQL)
**System B**: http://localhost:5173 (SvelteKit + FastAPI + Postgres)

## Summary

| Aspect | System A | System B | Winner |
|--------|----------|----------|--------|
| Pages discovered | 12 | 15 | B |
| Security score | 7/10 | 9/10 | B |
| Accessibility | 6/10 | 8/10 | B |
| API endpoints | 24 | 18 | A |
| Form validation | strict | partial | A |

## Page Coverage

### Pages in both systems
[side-by-side analysis]

### Pages only in System A
[list with description]

### Pages only in System B
[list with description]

## UI Flow Differences
[detailed comparison of user journeys]

## API Differences
[endpoint-by-endpoint comparison]

## Security Posture
[header-by-header, CORS, cookies comparison]

## Data Handling
[how each system handles edge cases, validation, errors]

## Recommendations
[which patterns from each system should be adopted]
```

---

## Mode: Code (Architecture comparison)

No running servers needed. Compares two codebases by reading files.

### Phase 1 — Stack Detection

For each codebase:
1. Read manifest files (package.json, pyproject.toml, etc.)
2. Detect frameworks, libraries, tools
3. Map directory structure

### Phase 2 — Architecture Comparison

Compare:

| Aspect | How |
|--------|-----|
| **Directory structure** | `ls -R` both projects, compare patterns |
| **File organization** | Components, routes, models, services, utils |
| **Framework patterns** | How each uses its framework (MVC, component-based, etc.) |
| **State management** | How data flows through each app |
| **API design** | REST vs GraphQL, naming conventions, auth patterns |
| **Database schema** | Migration files, models, relationships |
| **Testing approach** | Test frameworks, coverage patterns, test organization |
| **Build & deploy** | CI/CD, Docker, build scripts |
| **Dependencies** | Shared deps, unique deps, version differences |

### Phase 3 — Logic Flow Comparison

Trace key flows through each codebase:

1. **Auth flow** — Login, registration, session management, password reset
2. **CRUD flow** — How entities are created, read, updated, deleted
3. **Error handling** — How errors propagate, what users see
4. **Data validation** — Where and how input is validated
5. **Permission model** — How access control is implemented

For each flow, document the path through the code (file → function → file) in both systems.

### Phase 4 — Code Comparison Report

Write to `recon-compare-YYYY-MM-DD.md` with:

- Stack comparison table
- Architecture pattern differences
- Logic flow side-by-side analysis
- Shared patterns (what both do well)
- Unique strengths of each system
- Recommendations for convergence or adoption

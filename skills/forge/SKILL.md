---
name: forge
description: >
  Universal dev workflow orchestrator. Use this skill whenever working on any software project —
  picking up tasks from Linear or GitHub Issues, creating branches, developing features, running
  linting and tests, creating PRs, handling CodeRabbit reviews, or deploying. Trigger on any mention
  of tasks, issues, PR workflows, code review, linting, testing, migrations, deployments, or dev
  workflow questions. Works on any tech stack — auto-detects languages, frameworks, and tooling.
---

# Forge — Universal Dev Workflow

Forge orchestrates the full development lifecycle for any project, any stack. It detects what you're working with, learns your conventions, and guides every step from task pickup to merged PR.

## Core Principles

1. **Never assume — always ask.** When uncertain about stack, conventions, or next steps, ask the user.
2. **Detect, don't hardcode.** Read project files to infer the stack. Don't rely on a fixed list of known frameworks.
3. **Remember decisions.** Once the user confirms something, store it so they're never asked twice.
4. **Resume, don't restart.** On every session, read current state (git, PRs, tasks) and pick up where things left off.

---

## Plugin Map

Each workflow phase delegates to specific plugins. If a plugin is not installed, Forge skips that delegation and handles what it can natively.

| Phase | Plugins / Tools | What happens |
|-------|-----------------|--------------|
| Read state | **linear** or `gh` | Fetch tasks from stored source, check open PRs and CI status |
| Pick a task | **linear** or `gh` | Fetch backlog, rank priorities, let user choose |
| Create branch | `gh` | Get task ID from task source, create branch with naming convention |
| Spin up dev env | `recon-env.sh`, **Docker Compose** | Isolated environment per branch — own UI, API, DB on dedicated ports |
| Develop (backend/general) | **feature-dev** | Structured development with codebase analysis and architecture focus |
| Develop (frontend/UI) | **frontend-design**, **feature-dev** | Design + implement UI components with high design quality |
| Pre-PR gate: recon scan | **recon** scripts | Security headers, accessibility, CORS checks against live dev environment |
| Pre-PR gate: E2E | **playwright** | Visual verification of critical user flows |
| Pre-PR gate: cleanup | **code-simplifier** | Simplify overly complex code before PR |
| Pre-PR gate: self-review | *(Forge itself)* | `git diff` all session changes — review for bugs, logic errors, security issues |
| Create PR | **github** | `gh pr create` with description + task reference |
| Review cycle | **github** | Fetch PR comments, check CI, push fixes |
| Merge + teardown | `gh`, **linear**, `recon-env.sh` | Merge PR, tear down dev environment, task auto-updates |

---

## Phase 0: Read Current State (every session)

Before doing anything, assess where the project stands right now.

### Git State
- Run `git status`, `git branch`, `git log --oneline -5`
- Check for: uncommitted changes, current branch name, unpushed commits
- If on a feature branch, infer the task from branch name

### Open PRs
- Run `gh pr list --state open` and `gh pr view` if on a PR branch
- Check for: pending reviews, CodeRabbit comments, failing CI

### Task State
Check the stored task source for current work:
- **Linear** → use the **linear** plugin to check assigned/in-progress tasks
- **GitHub Issues** → run `gh issue list --assignee @me --state open`
- **None** → skip, rely on git state only

Check if current branch maps to a task (Linear prefix or `#N` issue number).

### Synthesize and Present
Combine all signals into a concise status summary:
> "You're on branch `feature/user-auth`, with 3 uncommitted files. There's an open PR with 2 unresolved CodeRabbit comments and passing CI. Your task PROJ-42 is marked In Progress."

Then **ask the user** what they want to do next. Never auto-resume.

---

## Phase 1: Task Selection

When the user wants to pick up new work:

### First run — identify task source
On first run, ask once and store the answer:
> "Where do you track tasks for this project?"
> - **Linear** (which team?)
> - **GitHub Issues**
> - **Neither** — I'll just ask you what to work on

### Fetching tasks

**Linear path:**
1. Use the **linear** plugin to fetch open/backlog tasks **filtered to the stored team**
2. Rank by usefulness (user impact, unblocks work, critical bugs) and complexity (effort, risk)
3. Present top 3–5 with rationale

**GitHub Issues path:**
1. Run `gh issue list --state open` to fetch open issues
2. Rank by the same criteria — read labels, milestones, and descriptions to assess priority
3. Present top 3–5 with rationale

**Neither path:**
Skip fetching. Ask the user what they want to work on.

In all cases: **ask the user which task to work on** — never auto-select.

---

## Phase 2: Project Detection

On first run, or when working in an unfamiliar project, detect the stack.

### How to Detect
1. List the root directory and all immediate subdirectories
2. Read any config, build, or manifest files found (e.g. `package.json`, `pyproject.toml`, `mix.exs`, `go.mod`, `Cargo.toml`, `Makefile`, `docker-compose.yml`, `pom.xml`, `build.gradle`, `Gemfile`, `rebar.config`, `deno.json`, etc.)
3. From what you read, determine:
   - **Language(s)** and version(s)
   - **Framework(s)** (e.g. FastAPI, SvelteKit, Phoenix, Rails, Next.js)
   - **Package manager(s)** (npm, pnpm, yarn, pip, uv, poetry, cargo, mix, go modules)
   - **Lint command(s)** — extract from scripts/config sections
   - **Test command(s)** — extract from scripts/config sections
   - **Build command(s)**
   - **Repo structure** — monolith, multi-repo, or monorepo

Do NOT hardcode a mapping of files to stacks. Read the files and let your understanding of the ecosystem guide inference. This way it works for Elixir, Zig, Gleam, or anything else.

4. Present findings to the user and ask them to **confirm or correct**
5. For detailed detection guidance, read `references/detection.md`

### Store the Knowledge
After user confirms, ask:
- **Team-shared** → write to `.claude/CLAUDE.md` (git tracked, teammates benefit)
- **Personal** → write to `~/.claude/projects/<project>/memory/` (local only)

For detailed persistence guidance, read `references/knowledge-persistence.md`

---

## Phase 3: Gap Detection — Progressive Setup

After detection, check for missing tooling. For each gap:

### No Linter
> "No linter detected for this [language] project. I'd recommend [best tool for stack]. Want me to:
> - Set it up with sensible defaults?
> - Set up something else?
> - Skip for now?"

### No Test Framework
Same pattern — recommend the standard test framework for the detected stack.

### No Security Scanning
Recommend trivy, bandit, npm audit, mix audit, cargo audit, etc. based on stack.

### No Pre-commit Hooks
Recommend husky, pre-commit, lefthook, etc.

### No CI Pipeline
Recommend a GitHub Actions workflow matching the detected stack.

**Store every decision.** If the user says "skip linting", don't ask again next session. If they say "set up ruff", the pre-PR gate knows to run `ruff check` going forward.

---

## Phase 4: Branch Creation + Environment Setup

### 1. Create the branch

1. On first use, ask the user for their **branch naming convention** and store it.
   - Examples: `username/TASK-<N>-<desc>`, `feature/<desc>`, `fix/<desc>`
2. Extract the task identifier for the branch name:
   - **Linear** → use the prefix + number (e.g., `MAK-42`)
   - **GitHub Issues** → use the issue number (e.g., `42`)
   - **Neither** → no task ID, just the description
3. Create the branch following the stored convention

### 2. Spin up dev environment (if Docker available)

After branch creation, check if the project has a `docker-compose.yml` (or `compose.yml`). If it does, offer to spin up an isolated dev environment for this branch:

> "This project has a Docker Compose file. Want me to spin up an isolated dev environment for this branch? You'll get your own UI, API, and DB on dedicated ports — no conflicts with anything else running."
> - **Yes** — spin up the environment
> - **No** — use whatever the user has running already
> - **Always** — spin up for every branch (store this preference)

If the user says yes or always:

```bash
# Use recon's environment manager in dev mode (current directory, no extraction)
bash "${CLAUDE_SKILL_DIR}/../recon/scripts/recon-env.sh" dev 5180 8010 5442
```

This creates:
- Docker Compose services on isolated ports (code stays in current directory)
- Health-checked, ready-to-use environment

Print the environment details:

```
Dev environment ready:
  Branch: feature/user-auth
  UI:     http://localhost:5180
  API:    http://localhost:8010
  DB:     localhost:5442

Develop against these URLs. Environment will be torn down after PR merge.
```

**If no Docker Compose file exists**, skip this step. The user manages their own servers.

**If Docker is not installed**, skip this step silently.

Store the environment preference (yes/no/always) so the user isn't asked every time.

---

## Phase 5: Development

Delegate to the right plugin based on what's being built:

- **Backend / general code** → use **feature-dev** for structured development with codebase analysis
- **Frontend / UI work** → use **frontend-design** for high-quality component and page design, then **feature-dev** for implementation
- **Both** → use both plugins across their respective areas

During development:

- Respect any stored **hard rules** (e.g. "never edit generated files", "never write migration SQL by hand")
- If the user added multiple working directories, work across them as needed
- If a directory is missing, ask the user to add it (`/add-dir`)
- If a dev environment was spun up in Phase 4, reference its URLs when running or testing the app. The environment's ports are stored in `/tmp/recon-envs/recon-<id>/env.meta`.

### Environment management during development

If a dev environment is active:

- **Check status**: `bash "${CLAUDE_SKILL_DIR}/../recon/scripts/recon-env.sh" status <task_id>` — verify services are still running
- **Restart if needed**: If a service goes down during development (e.g., backend crash after a bad migration), tear down and re-up:
  ```bash
  bash "${CLAUDE_SKILL_DIR}/../recon/scripts/recon-env.sh" down <task_id>
  bash "${CLAUDE_SKILL_DIR}/../recon/scripts/recon-env.sh" up <task_id> <branch> 5180 8010 5442
  ```
- **Rebuild after changes**: If the user changes Dockerfile, dependencies, or compose config, Docker Compose's `--build` flag (used by `recon-env.sh up`) handles rebuilding automatically.

---

## Phase 6: Pre-PR Gate (mandatory before every PR)

Before creating any PR, run through ALL applicable steps. Do not skip any that are configured.

### 1. Lint & Format
Run the stored lint/format commands for every affected repo. Fix all errors before proceeding.

### 2. Run Tests
Run the stored test commands. All tests must pass. If a test fails, fix it before moving on.

### 3. E2E Testing
If configured, run E2E tests (e.g. Playwright). Also use the **playwright** plugin to visually verify critical user flows affected by the changes.

### 4. Security Checks
If configured, run the stored security scanning commands.

### 5. Recon Quick Scan (if dev environment is active)

If a dev environment was spun up in Phase 4, run a quick recon scan before the PR. This catches data consistency issues, security misconfigs, and UI problems that unit tests miss:

```bash
# Run programmatic scans only (fast, no full crawl)
bash "${CLAUDE_SKILL_DIR}/../recon/scripts/security-scan.sh" "http://localhost:5180"
bash "${CLAUDE_SKILL_DIR}/../recon/scripts/security-scan.sh" "http://localhost:8010"
bash "${CLAUDE_SKILL_DIR}/../recon/scripts/accessibility-audit.sh" "http://localhost:5180"
```

If any `[CRITICAL]` findings appear, treat them as **MUST FIX** before proceeding to PR.

If the user wants a full recon (crawl + cross-check + form attacks), suggest running `/forge:recon` with the dev environment URLs.

### 6. Self Code Review
Strict, line-by-line review of every change made in this session. No file gets skipped.
- Run `git diff` — review every file, every hunk
- Check: correctness, security, logic, data integrity, performance, test coverage, acceptance criteria
- Categorize issues as **MUST FIX** (blocks PR), **SHOULD FIX** (recommend to user), or **CONSIDER** (user decides)
- Fix all MUST FIX issues without asking. Present SHOULD FIX and CONSIDER to user.
- Use **code-simplifier** to clean up overly complex code
- Re-run lint and tests after any fixes
- For the full review checklist, read `references/pre-pr-gate.md`

If a step has no configured command (user previously chose "skip"), skip it silently.

---

## Phase 7: PR + Review Cycle

1. **Create PR** — `gh pr create` with a clear title and description referencing the task:
   - **Linear** → include task ID in description. Branch naming auto-links the PR to Linear.
   - **GitHub Issues** → include `Closes #N` in description. GitHub auto-closes the issue on merge.
   - **Neither** → just describe the change.
2. **Wait for CodeRabbit** — it reviews automatically
3. **Address feedback** — fetch CodeRabbit comments, fix issues, push updates
4. **Get approval** — ensure all review comments are resolved
5. **Merge** — merge to main/develop per project convention
6. **Tear down dev environment** — if a dev environment was spun up in Phase 4, tear it down after merge:
   ```bash
   bash "${CLAUDE_SKILL_DIR}/../recon/scripts/recon-env.sh" down <task_id>
   ```
   This removes the Docker containers, volumes, and network. Clean slate for the next task.

---

## Phase 8: Knowledge Persistence

Throughout the workflow, you will discover new information about the project:
- Task source and team mapping (Linear, GitHub Issues, or none)
- Stack details, framework versions
- Lint/test/build commands
- Naming conventions, hard rules
- Repo structure, generated file locations
- Gap decisions (skipped tooling)

**Every time crucial top-level info is discovered, ask the user where to store it:**
- **Team-shared** (`.claude/CLAUDE.md`) — visible to all team members, git tracked
- **Personal** (`~/.claude/projects/<project>/memory/`) — local only, private preferences

On session start, read from **both** locations and merge. Team-shared takes precedence for project facts; personal takes precedence for user preferences.

For the storage format and detailed guidance, read `references/knowledge-persistence.md`

---

## Phase 9: Confidence Letter Loop (Recon Integration)

When the user says "read the confidence letter and gain 100%" or similar, forge enters fix-loop mode.

### 1. Find the letter

Look for the most recent `recon-confidence-letter-*.md` in the project root. If not found, tell the user to run `/forge:recon` first.

### 2. Parse findings

Read the confidence letter and extract every finding that is NOT `[PASS]`:

- `[CRITICAL]` → **MUST FIX** — fix immediately, no questions asked
- `[FAIL]` → **MUST FIX** — fix immediately
- `[WARN]` → **SHOULD FIX** — present to user, recommend fixing
- `[INFO]` → **CONSIDER** — present to user, let them decide

For each finding, extract:
- The description (what's wrong)
- The category (security, data consistency, UI cleanliness, etc.)
- The file hint (if provided — where to look)
- The evidence (what values were found)

### 3. Create fix tasks

Order findings by severity (CRITICAL first), then by category (group related fixes). Present the full list to the user:

```
Recon found 12 issues. Here's the fix plan:

MUST FIX (5):
  1. [CRITICAL] CORS wildcard — backend/config/cors.py
  2. [CRITICAL] Price mismatch on /orders — frontend/components/OrderCard.svelte
  3. [FAIL] Negative quantity accepted — backend/validators.py + frontend form
  4. [FAIL] Missing HSTS header — backend/middleware.py
  5. [FAIL] FK orphans in orders table — needs migration

SHOULD FIX (4):
  6. [WARN] Contrast ratio on /dashboard — frontend/styles
  7. [WARN] Missing alt text on 3 images — frontend/components
  8. [WARN] Cookie missing SameSite flag — backend/auth
  9. [WARN] Status mapping inconsistency — frontend/utils

CONSIDER (3):
  10. [INFO] Server header exposes version
  11. [INFO] No Referrer-Policy header
  12. [INFO] Console warning on /items page
```

Ask user to confirm or adjust the plan.

### 4. Fix loop

For each fix task:
1. Read the relevant file(s) based on the fix hint and evidence
2. Implement the fix
3. Run lint + tests to verify nothing broke
4. Move to next task

After all MUST FIX items are done, ask user about SHOULD FIX items. After those, ask about CONSIDER items.

### 5. Re-run prompt

After all accepted fixes are implemented:

```
All fixes applied. Run `/forge:recon` to verify and update the confidence score.
Current confidence was: [previous score]/100
```

The user runs `/forge:recon` again, which produces a new confidence letter. If issues remain, the user runs this phase again. The loop continues until 100% or the user is satisfied.

---

## Workflow Summary

| Step | What happens |
|------|--------------|
| Read state | Git status, open PRs, tasks (Linear / GitHub Issues / none) — present summary, ask user |
| Pick a task | Fetch from stored task source, rank by usefulness + complexity, user decides |
| Detect project | Scan files, infer stack, user confirms, store knowledge |
| Fill gaps | Missing linter/tests/security/CI? Recommend, user decides, store |
| Create branch | Follow stored naming convention, include task ID |
| Spin up dev env | Docker Compose isolation per branch — own UI, API, DB (if Docker available) |
| Develop | Code across repos, respect hard rules, test against isolated environment |
| Pre-PR gate | Lint, test, E2E, recon quick scan, security, self-review — all must pass |
| Create PR | `gh pr create` with description + task reference |
| Review cycle | CodeRabbit comments → fix → get approval |
| Merge + teardown | Merge → tear down dev environment → deploy (if configured) → task auto-updates |
| Persist knowledge | New discovery → ask user: team-shared or personal? → store |

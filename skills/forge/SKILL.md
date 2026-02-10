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

| Phase | Plugins | What happens |
|-------|---------|--------------|
| Read state | **linear** or `gh` | Fetch tasks from stored source, check open PRs and CI status |
| Pick a task | **linear** or `gh` | Fetch backlog, rank priorities, let user choose |
| Create branch | `gh` | Get task ID from task source, create branch with naming convention |
| Develop (backend/general) | **feature-dev** | Structured development with codebase analysis and architecture focus |
| Develop (frontend/UI) | **frontend-design**, **feature-dev** | Design + implement UI components with high design quality |
| Pre-PR gate: E2E | **playwright** | Visual verification of critical user flows |
| Pre-PR gate: cleanup | **code-simplifier** | Simplify overly complex code before PR |
| Pre-PR gate: self-review | *(Forge itself)* | `git diff` all session changes — review for bugs, logic errors, security issues |
| Create PR | **github** | `gh pr create` with description + task reference |
| Review cycle | **github** | Fetch PR comments, check CI, push fixes |
| Merge + close | `gh`, **linear** (if used) | Merge PR, task auto-updates via branch naming or `Closes #N` |

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

## Phase 4: Branch Creation

1. On first use, ask the user for their **branch naming convention** and store it.
   - Examples: `username/TASK-<N>-<desc>`, `feature/<desc>`, `fix/<desc>`
2. Extract the task identifier for the branch name:
   - **Linear** → use the prefix + number (e.g., `MAK-42`)
   - **GitHub Issues** → use the issue number (e.g., `42`)
   - **Neither** → no task ID, just the description
3. Create the branch following the stored convention

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

### 5. Self Code Review
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

## Workflow Summary

| Step | What happens |
|------|--------------|
| Read state | Git status, open PRs, tasks (Linear / GitHub Issues / none) — present summary, ask user |
| Pick a task | Fetch from stored task source, rank by usefulness + complexity, user decides |
| Detect project | Scan files, infer stack, user confirms, store knowledge |
| Fill gaps | Missing linter/tests/security/CI? Recommend, user decides, store |
| Create branch | Follow stored naming convention, include task ID |
| Develop | Code across repos, respect hard rules |
| Pre-PR gate | Lint, test, E2E, security, self-review — all must pass |
| Create PR | `gh pr create` with description + task reference |
| Review cycle | CodeRabbit comments → fix → get approval |
| Merge | Merge → deploy (if configured) → task auto-updates |
| Persist knowledge | New discovery → ask user: team-shared or personal? → store |

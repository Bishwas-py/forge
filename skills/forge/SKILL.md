---
name: forge
description: >
  Universal dev workflow orchestrator. Use this skill whenever working on any software project —
  picking up tasks from Linear, creating branches, developing features, running linting and tests,
  creating PRs, handling CodeRabbit reviews, or deploying. Trigger on any mention of tasks, issues,
  PR workflows, code review, linting, testing, migrations, deployments, or dev workflow questions.
  Works on any tech stack — auto-detects languages, frameworks, and tooling.
---

# Forge — Universal Dev Workflow

Forge orchestrates the full development lifecycle for any project, any stack. It detects what you're working with, learns your conventions, and guides every step from task pickup to merged PR.

## Core Principles

1. **Never assume — always ask.** When uncertain about stack, conventions, or next steps, ask the user.
2. **Detect, don't hardcode.** Read project files to infer the stack. Don't rely on a fixed list of known frameworks.
3. **Remember decisions.** Once the user confirms something, store it so they're never asked twice.
4. **Resume, don't restart.** On every session, read current state (git, PRs, Linear) and pick up where things left off.

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

### Linear State
- Use the **linear** plugin to check assigned/in-progress tasks
- Check if current branch maps to a Linear issue

### Synthesize and Present
Combine all signals into a concise status summary:
> "You're on branch `feature/user-auth`, with 3 uncommitted files. There's an open PR with 2 unresolved CodeRabbit comments and passing CI. Your Linear task MAK-42 is marked In Progress."

Then **ask the user** what they want to do next. Never auto-resume.

---

## Phase 1: Task Selection

When the user wants to pick up new work:

1. Use the **linear** plugin to fetch open/backlog tasks
2. Rank them by:
   - **Usefulness** — user impact, unblocks other work, addresses critical bugs
   - **Complexity** — estimated effort, number of repos affected, risk level
3. Present the top 3–5 recommendations with a short rationale for each
4. **Ask the user which task to work on** — never auto-select

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
2. If a Linear task is selected, extract the task identifier for the branch name
3. Create the branch following the stored convention

---

## Phase 5: Development

Work on the feature across the detected repos. During development:

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
Before submitting the PR, perform an extensive self-review:
- Review every changed file for bugs, logic errors, security issues, and missed edge cases
- Check for code quality: naming, structure, duplication
- Verify the changes match the task's acceptance criteria
- Use **code-simplifier** to clean up any overly complex code
- Only after this self-review passes should you create the PR

If a step has no configured command (user previously chose "skip"), skip it silently.

For detailed pre-PR procedures, read `references/pre-pr-gate.md`

---

## Phase 7: PR + Review Cycle

1. **Create PR** — `gh pr create` with a clear title and description referencing the Linear task
2. **Wait for CodeRabbit** — it reviews automatically
3. **Address feedback** — fetch CodeRabbit comments, fix issues, push updates
4. **Get approval** — ensure all review comments are resolved
5. **Merge** — merge to main/develop per project convention

If the branch naming convention includes the task identifier, Linear auto-links the PR.

---

## Phase 8: Knowledge Persistence

Throughout the workflow, you will discover new information about the project:
- Stack details, framework versions
- Lint/test/build commands
- Naming conventions, hard rules
- Repo structure, generated file locations

**Every time crucial top-level info is discovered, ask the user where to store it:**
- **Team-shared** (`.claude/CLAUDE.md`) — visible to all team members, git tracked
- **Personal** (`~/.claude/projects/<project>/memory/`) — local only, private preferences

On session start, read from **both** locations and merge. Team-shared takes precedence for project facts; personal takes precedence for user preferences.

For the storage format and detailed guidance, read `references/knowledge-persistence.md`

---

## Workflow Summary

| Step | What happens |
|------|--------------|
| Read state | Git status, open PRs, Linear tasks — present summary, ask user |
| Pick a task | Fetch backlog, rank by usefulness + complexity, user decides |
| Detect project | Scan files, infer stack, user confirms, store knowledge |
| Fill gaps | Missing linter/tests/security/CI? Recommend, user decides, store |
| Create branch | Follow stored naming convention, include task ID |
| Develop | Code across repos, respect hard rules |
| Pre-PR gate | Lint, test, E2E, security, self-review — all must pass |
| Create PR | `gh pr create` with description + task reference |
| Review cycle | CodeRabbit comments → fix → get approval |
| Merge | Merge → deploy (if configured) → Linear auto-updates |
| Persist knowledge | New discovery → ask user: team-shared or personal? → store |

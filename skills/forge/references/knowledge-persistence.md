# Knowledge Persistence Reference

How Forge stores and retrieves learned project knowledge across sessions.

## Storage Locations

### Team-Shared — `.claude/CLAUDE.md`
- Lives in the project repo, git tracked
- Auto-loaded by Claude Code on every session
- Visible to all team members who clone the repo
- Best for: stack info, lint/test commands, hard rules, naming conventions, repo structure

### Personal — `~/.claude/projects/<project>/memory/`
- Local to the user's machine, not git tracked
- Auto-loaded by Claude Code on session start
- Best for: personal preferences, local paths, skipped tooling choices

## When to Store

Store knowledge whenever:
- Project stack is detected and confirmed by user
- Lint/test/build/security commands are identified or configured
- User establishes a naming convention (branches, commits)
- Hard rules are discovered ("never edit generated files")
- Gap decisions are made ("skip security scanning for now")
- Repo structure is confirmed (monolith, multi-repo, monorepo)

## How to Ask

Every time new crucial info is discovered:

> "I've learned that this project uses [X]. Where should I save this?
> - **Team-shared** (`.claude/CLAUDE.md`) — your teammates will benefit too
> - **Personal** (project memory) — just for you"

Batch related discoveries when possible — don't ask separately for each lint flag.

## Storage Format

Write in plain Markdown that Claude Code reads naturally. Use clear sections.

### Team-Shared Example (`.claude/CLAUDE.md`)

```markdown
## Project Stack
- Backend: Python 3.12 / FastAPI
- Frontend: TypeScript / SvelteKit
- Package managers: uv (backend), pnpm (frontend)

## Commands
### Backend (from ./backend)
- Lint: `uv run ruff check --fix app tests`
- Format: `uv run ruff format app tests`
- Test: `uv run pytest -v`
- Build: `docker-compose up -d --build app`

### Frontend (from ./frontend)
- Lint: `pnpm run lint`
- Format: `pnpm run format`
- Test: `pnpm run test`
- E2E: `pnpm run test:e2e`
- Build: `pnpm run build`

## Branch Convention
`<username>/<TASK-ID>-<description>`

## Hard Rules
- Never manually edit files in `frontend/src/_generated/` — auto-generated from backend OpenAPI spec
- Never write migration SQL by hand — use the migration generator
```

### Personal Example (`~/.claude/projects/<project>/memory/MEMORY.md`)

```markdown
## My Preferences
- Skip security scanning (not needed for this project yet)
- Prefer ruff over flake8
- Use compact PR descriptions
```

## Reading on Session Start

On every session, Forge reads from both locations automatically (Claude Code loads them into context). If there's a conflict:
- **Project facts** (stack, commands, hard rules) → team-shared wins
- **User preferences** (skipped tools, personal conventions) → personal wins

## Updating Stale Knowledge

If Forge detects that stored knowledge might be outdated (e.g. `package.json` scripts changed, new dependencies added):
1. Note the discrepancy
2. Present the old vs new info to the user
3. Ask if they want to update
4. Ask where to store the update (team-shared or personal)

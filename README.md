# Forge

Universal dev workflow plugin for [Claude Code](https://code.claude.com). Auto-detects your stack, orchestrates the full development lifecycle from task pickup to merged PR — works on any project, any language.

<img width="124" height="124" alt="image" src="https://github.com/user-attachments/assets/0f57b96e-5869-4876-b30a-5bd2cbcabc4c" />


## Install

```bash
claude plugin install forge@<marketplace>
```

Or for local development:

```bash
claude --plugin-dir /path/to/forge
```

## What It Does

Forge handles the full dev loop:

1. **Read current state** — git status, open PRs, tasks (Linear or GitHub Issues)
2. **Pick a task** — fetch backlog, rank by impact + complexity, you decide
3. **Detect project** — scan files, infer stack, confirm with you, remember it
4. **Fill gaps** — missing linter/tests/CI? recommend setup, you decide
5. **Create branch** — follows your naming convention
6. **Develop** — code across repos, respects stored hard rules
7. **Pre-PR gate** — lint, test, E2E, security, self-review
8. **Create PR** — `gh pr create` with description + task reference
9. **Review cycle** — CodeRabbit/reviewer comments, fix, get approval
10. **Merge** — merge, deploy (if configured), Linear auto-updates

## Recommended Plugins

Claude Code does not yet support formal plugin dependencies ([tracking issue](https://github.com/anthropics/claude-code/issues/9444)). Forge adapts to what you have installed — it skips phases that lack their required plugin rather than failing.

That said, you'll get the most out of Forge with these installed:

### Core (strongly recommended)

| Plugin | Used for | Install |
|--------|----------|---------|
| **linear** | Task fetching, status updates, project mapping | `claude plugin install linear` |
| **github** | PR creation, CI checks, review comments | `claude plugin install github` |

### Quality & development

| Plugin | Used for | Install |
|--------|----------|---------|
| **feature-dev** | Structured development, code architecture | `claude plugin install feature-dev` |
| **code-simplifier** | Pre-PR code cleanup | `claude plugin install code-simplifier` |
| **playwright** | E2E visual verification | `claude plugin install playwright` |
| **frontend-design** | UI/component work | `claude plugin install frontend-design` |

## How It Works Without Plugins

Forge degrades gracefully:

- No `linear`? — Fall back to GitHub Issues via `gh`, or skip task selection entirely
- No `github`? — Skip PR creation, just run the pre-PR gate
- No `feature-dev`? — Develop without structured codebase analysis
- No `frontend-design`? — Develop UI without design-focused guidance
- No `playwright`? — Skip E2E visual checks
- No `code-simplifier`? — Skip automated cleanup, rely on self-review only

The core value — stack detection, knowledge persistence, pre-PR quality gate — works with zero plugins.

## License

MIT

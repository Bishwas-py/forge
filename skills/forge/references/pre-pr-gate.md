# Pre-PR Gate Reference

Everything that must pass before a PR is created. Run steps in order. Skip any step that has no configured command (user chose "skip" during gap detection).

## 1. Lint & Format

Run the stored lint and format commands for **every repo that has changes**.

- If the command includes auto-fix (e.g. `--fix`, `--write`), run fix first, then the check
- If lint errors remain after auto-fix, fix them manually before proceeding
- Stage any formatting changes

## 2. Run Tests

Run the stored test commands for every affected repo.

- All tests must pass
- If a test fails:
  1. Read the failure output
  2. Determine if the failure is caused by your changes or was pre-existing
  3. If caused by your changes — fix it
  4. If pre-existing — note it in the PR description and ask the user if they want to proceed

## 3. E2E Testing

If E2E tests are configured:
- Run the stored E2E command (e.g. `npm run test:e2e`, `mix test --tag e2e`)
- Use the **playwright** plugin to visually verify critical user flows affected by the changes
- Navigate the app, check UI states, confirm nothing is broken
- If no E2E is configured but frontend changes were made, suggest setting it up (gap detection)

## 4. Security Checks

If security scanning is configured:
- Run the stored command (e.g. `trivy fs .`, `bandit -r app`, `npm audit`, `mix audit`, `cargo audit`)
- If vulnerabilities found:
  1. Assess severity
  2. For critical/high — fix before PR
  3. For medium/low — note in PR description, ask user

## 5. Self Code Review

The final and most important step. Use the **code-review** plugin to perform an extensive review:

### What to Check
- **Correctness** — Does the code do what the task requires? Are edge cases handled?
- **Security** — Any injection risks, exposed secrets, missing auth checks?
- **Logic errors** — Off-by-one, null handling, race conditions?
- **Code quality** — Naming clarity, function length, duplication, dead code
- **Acceptance criteria** — Does this match what the Linear task asked for?

### How to Review
1. Run `git diff` to see all changes
2. Review every changed file, function by function
3. Check that tests cover the new/changed behavior
4. Use **code-simplifier** to clean up overly complex code
5. If issues found — fix them, then re-run lint and tests

### Review Verdict
Only proceed to PR creation when:
- All lint/format passes
- All tests pass
- E2E passes (if applicable)
- Security scan clean (or acknowledged)
- Self-review found no issues

If any step fails, fix and re-run from the beginning of the failed step.

## When Steps Are Not Configured

If the user previously chose to skip a tool during gap detection:
- Skip that step silently — don't ask again
- If you notice the project has since added the tool (e.g. new test framework in dependencies), mention it and ask if they want to enable the step

## Handling Multi-Repo PRs

When changes span multiple repos:
- Run the pre-PR gate for **each repo independently**
- All repos must pass before creating any PR
- Create separate PRs per repo, cross-reference them in descriptions

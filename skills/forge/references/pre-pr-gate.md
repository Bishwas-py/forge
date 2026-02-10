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

The final and most important step. This is a strict, line-by-line review of every change made in this session. Nothing gets past this gate without being examined.

### Step 1: Collect All Changes

Run `git diff` (staged + unstaged) to get the complete picture. Review **every single file**, **every single hunk**. Do not skim. Do not skip files because they "look fine."

### Step 2: Review Each File

For every changed file, check all of the following. If any issue is found, log it — do not fix silently.

**Correctness**
- Does this change do exactly what the task requires? Not more, not less.
- Are all edge cases handled? Empty inputs, null values, boundary conditions, zero-length collections, concurrent access.
- Are error paths handled? What happens when this fails?
- Are return types and values correct in all branches?

**Security**
- Any hardcoded secrets, API keys, tokens, passwords?
- Any SQL injection, XSS, command injection, path traversal vectors?
- Any missing auth or permission checks on new endpoints/routes?
- Any sensitive data logged or exposed in error messages?
- Any new dependencies with known vulnerabilities?

**Logic**
- Off-by-one errors in loops, slices, ranges, pagination?
- Null/undefined dereferences? Optional chaining where needed?
- Race conditions in async code? Missing awaits?
- Incorrect operator precedence? `==` vs `===`, `and` vs `or` confusion?
- Dead code paths that can never execute?

**Data integrity**
- Are database operations wrapped in transactions where needed?
- Any writes without proper validation?
- Any cascade deletes that could destroy unintended data?
- Are migrations reversible?

**Performance**
- Any N+1 queries introduced?
- Any unbounded loops or missing pagination?
- Any large objects held in memory unnecessarily?
- Any blocking calls in async contexts?

**Code quality**
- Are names clear and accurate? Does the name match what it actually does?
- Any functions doing too many things?
- Any duplicated logic that should be extracted?
- Any dead code, unused imports, commented-out blocks?
- Does the code follow the project's existing patterns and conventions?

**Test coverage**
- Are there tests for the new/changed behavior?
- Do the tests cover both happy path and error cases?
- Are the tests actually asserting the right things (not just "does not throw")?

**Acceptance criteria**
- Does this change satisfy the task requirements (Linear task, user request, etc.)?
- Is anything missing that was asked for?
- Is anything included that was NOT asked for?

### Step 3: Present Findings

After reviewing all files, present a structured report to the user:

```
## Self-Review Results

### Issues Found: <count>

**[MUST FIX]** (blocks PR creation)
1. `path/to/file.ts:42` — SQL injection: user input passed directly to query
2. `path/to/handler.py:18` — Missing auth check on DELETE endpoint

**[SHOULD FIX]** (strongly recommended before PR)
1. `path/to/utils.ts:91` — N+1 query in loop, will degrade with scale
2. `path/to/component.svelte:33` — Unhandled error state shows blank screen

**[CONSIDER]** (minor, up to user)
1. `path/to/service.py:55` — Variable name `d` is unclear, suggest `duration`

### No Issues Found In:
- `path/to/clean-file.ts`
- `path/to/another-clean-file.py`
```

Categorize every issue:
- **MUST FIX** — Security vulnerabilities, data loss risks, broken functionality, missing auth. These block PR creation unconditionally.
- **SHOULD FIX** — Performance issues, missing error handling, poor test coverage, logic concerns. Present to user with strong recommendation to fix.
- **CONSIDER** — Style, naming, minor cleanup. User decides.

### Step 4: Resolve

- **MUST FIX** items: Fix them. No exceptions. Do not ask the user if they want to skip these.
- **SHOULD FIX** items: Present each to the user. Recommend fixing. If the user says skip, accept — but note it in the PR description.
- **CONSIDER** items: Ask the user. Accept either answer.
- Use **code-simplifier** to clean up any overly complex code found during review.

After fixes are applied, re-run lint and tests from step 1 of the pre-PR gate. The gate restarts from the failed step, not from scratch.

### Step 5: Final Verdict

Only proceed to PR creation when:
- All **MUST FIX** issues are resolved
- All **SHOULD FIX** issues are resolved or explicitly acknowledged by user
- Lint, tests, and E2E still pass after fixes
- You can state with confidence: "Every changed line has been reviewed"

If you cannot confidently say that, go back and review again.

## When Steps Are Not Configured

If the user previously chose to skip a tool during gap detection:
- Skip that step silently — don't ask again
- If you notice the project has since added the tool (e.g. new test framework in dependencies), mention it and ask if they want to enable the step

## Handling Multi-Repo PRs

When changes span multiple repos:
- Run the pre-PR gate for **each repo independently**
- All repos must pass before creating any PR
- Create separate PRs per repo, cross-reference them in descriptions

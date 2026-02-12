# Formula: Bugfix

**Topology:** reproduce → fix → verify

Use this formula when the issue describes a bug, regression, or unexpected behavior that needs correction.

---

## Default Task Phases

### Phase 1: Reproduce

Isolate and confirm the bug with a failing test or reproducible steps.

**Typical tasks:**
- Write a failing test that demonstrates the bug
- Reproduce the issue locally with minimal steps
- Identify the root cause in the codebase

**Acceptance criteria patterns:**
- `test file exists at {path} and fails with expected error`
- `running {reproduce command} produces the reported error`
- `root cause identified in {file}:{line range}`

**Verify command patterns:**
```bash
# Run the failing test to confirm bug exists
npm run test -- --grep "{bug description}" || echo "Bug confirmed: test fails as expected"
# Reproduce with specific input
{reproduce command} 2>&1 | grep -q "{expected error}"
```

### Phase 2: Fix

Apply the minimal change that corrects the behavior without side effects.

**Typical tasks:**
- Fix the root cause in the identified file(s)
- Update related logic if the bug has ripple effects
- Add guard clauses or input validation if applicable

**Acceptance criteria patterns:**
- `{file} contains the fix at {location}`
- `npm run typecheck passes`
- `no regressions in existing test suite`

**Verify command patterns:**
```bash
npm run typecheck
npm run test
npm run lint
```

### Phase 3: Verify

Confirm the fix resolves the bug and existing tests still pass.

**Typical tasks:**
- Update the failing test to assert correct behavior
- Add edge-case tests to prevent regression
- Run the full test suite

**Acceptance criteria patterns:**
- `test from Phase 1 now passes`
- `edge-case tests added for {scenario}`
- `npm run test passes with zero failures`
- `npm run build succeeds`

**Verify command patterns:**
```bash
npm run test
npm run test -- --grep "{bug description}"
npm run build
```

---

## When to Use

**Keywords in issue text:** bug, fix, broken, regression, error, crash, fails, incorrect, wrong, unexpected
**Labels:** `bug`, `regression`, `defect`

## Task Sizing Guidance

Most bugfixes fit in 2-3 tasks. If the fix requires more than 3 tasks, consider whether it's actually a refactor or feature change.

| Scenario | Tasks |
|----------|-------|
| Simple one-file fix | 2 (reproduce + fix/verify combined) |
| Multi-file fix | 3 (reproduce → fix → verify) |
| Fix with migration | 3-4 (reproduce → fix → migrate → verify) |

# Formula: Refactor

**Topology:** analyze → extract → migrate → verify

Use this formula when the issue describes restructuring existing code without changing external behavior.

---

## Default Task Phases

### Phase 1: Analyze

Understand the current implementation, identify what to change, and establish a baseline.

**Typical tasks:**
- Document current code structure and dependencies
- Identify all callers/consumers of the code to refactor
- Establish baseline test coverage (add tests if missing)
- Define the target architecture

**Acceptance criteria patterns:**
- `baseline tests pass for {module}`
- `all callers of {function/module} identified`
- `npm run test passes (baseline established)`
- `test coverage exists for {affected code}`

**Verify command patterns:**
```bash
npm run test
npm run typecheck
grep -rn "{function name}" src/ | wc -l  # count callers
```

### Phase 2: Extract

Isolate the code to be refactored into a clean boundary.

**Typical tasks:**
- Extract functions, classes, or modules into separate files
- Create new abstractions or interfaces
- Set up the target structure alongside the old code
- Add adapter/shim layers if needed for gradual migration

**Acceptance criteria patterns:**
- `{new file} exists with extracted {function/class}`
- `old code still works unchanged (no behavior change)`
- `npm run typecheck passes`
- `npm run test passes (no regressions)`

**Verify command patterns:**
```bash
test -f {new file} && echo "Extracted file exists"
npm run typecheck
npm run test
npm run build
```

### Phase 3: Migrate

Switch consumers from old code to the new structure.

**Typical tasks:**
- Update imports across the codebase
- Replace old API calls with new abstractions
- Remove deprecated code paths
- Update configuration references

**Acceptance criteria patterns:**
- `no remaining imports from {old path}`
- `all consumers use {new module/function}`
- `deprecated {old code} removed`
- `npm run typecheck passes`
- `npm run test passes`

**Verify command patterns:**
```bash
# Confirm old imports are gone
! grep -rn "from.*{old path}" src/ || echo "Old imports still exist"
npm run typecheck
npm run test
npm run build
```

### Phase 4: Verify

Confirm the refactor is complete with no behavior changes or regressions.

**Typical tasks:**
- Run full test suite
- Verify build succeeds
- Clean up any temporary shims or adapters
- Update documentation if APIs changed

**Acceptance criteria patterns:**
- `npm run test passes with zero failures`
- `npm run build succeeds`
- `no temporary shims remain`
- `npm run lint passes`

**Verify command patterns:**
```bash
npm run test
npm run build
npm run typecheck
npm run lint
# Confirm no leftover TODOs from refactor
! grep -rn "TODO.*refactor\|FIXME.*refactor" src/ || echo "Cleanup TODOs remain"
```

---

## When to Use

**Keywords in issue text:** refactor, restructure, reorganize, extract, migrate, move, rename, simplify, clean up, decouple, modularize
**Labels:** `refactor`, `tech-debt`, `cleanup`

## Task Sizing Guidance

Refactors are deceptively complex. Size conservatively:

| Scope | Phases Used | Tasks |
|-------|-------------|-------|
| Rename/move one module | extract → migrate | 2 |
| Extract shared utility | analyze → extract → verify | 3 |
| Full module restructure | analyze → extract → migrate → verify | 4-6 |
| Cross-cutting refactor | Split into per-module issues | 6+ |

If the refactor touches more than 10 files, split into smaller refactoring issues that each handle one logical boundary.

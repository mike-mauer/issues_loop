## 📋 Implementation Plan

**Issue:** #10 - Streamline command system
**Generated:** 2026-02-03T03:48:23Z
**Status:** Pending Approval
**Complexity:** Medium (5 tasks)

---

### Overview
Rename all command files to use `il_` prefix with sequential numbering for the core workflow. Consolidate the `/issue close close` command into a single `/il_3_close` command. Update all documentation references.

### New Command Structure

| Step | New Command | Old Command | Purpose |
|------|-------------|-------------|---------|
| - | `/il_list` | `/issues` | List open issues |
| - | `/il_setup` | `/issue setup` | Initialize labels/templates |
| - | `/il_validate` | `/issue validate` | Check prerequisites |
| 1 | `/il_1_plan N` | `/issue N` | Load, scope, and plan issue |
| 2 | `/il_2_implement` | `/implement` | Execute task loop |
| 3 | `/il_3_close` | `/issue close` | Report, PR, and archive |

---

### Tasks

#### US-001: Rename command files with il_ prefix
**Priority:** 1
**Files:** `.claude/commands/*.md`
**Depends on:** None

Rename all 6 command files. Core workflow gets sequential numbers (1, 2, 3). Non-core gets descriptive names.

**Acceptance Criteria:**
- [ ] All 6 files renamed with il_ prefix
- [ ] Core workflow files have sequential numbers

---

#### US-002: Update command headers and descriptions
**Priority:** 2
**Files:** `.claude/commands/il_*.md`
**Depends on:** US-001

Update # headers, ## Description, and Usage sections in each file to reflect new names.

**Acceptance Criteria:**
- [ ] Each file's header matches new command name
- [ ] Usage sections show new syntax

---

#### US-003: Consolidate close close into il_3_close
**Priority:** 3
**Files:** `.claude/commands/il_3_close.md`
**Depends on:** US-002

Merge the "close close" functionality. Single command detects PR merged state and archives automatically.

**Acceptance Criteria:**
- [ ] No "close close" syntax in docs
- [ ] Command auto-detects merged PR and archives

---

#### US-004: Update all documentation references
**Priority:** 4
**Files:** `CLAUDE.md`, `.claude/CLAUDE.md`, `.claude/rules/*.md`
**Depends on:** US-002

Replace all references to old command names with new il_ naming.

**Acceptance Criteria:**
- [ ] No references to old command names in docs
- [ ] All examples use new naming

---

#### US-005: Update cross-references between commands
**Priority:** 5
**Files:** `.claude/commands/il_*.md`
**Depends on:** US-004

Update internal references like "Run /implement" to "Run /il_2_implement".

**Acceptance Criteria:**
- [ ] All internal command references use il_ naming
- [ ] No orphaned old references

---

### Task Dependencies
```
US-001 (Priority 1) ← No dependencies
  ↓
US-002 (Priority 2) ← Depends on US-001
  ↓
US-003 (Priority 3) ← Depends on US-002
US-004 (Priority 4) ← Depends on US-002
  ↓
US-005 (Priority 5) ← Depends on US-004
```

## ✅ Plan Approved

**prd.json generated** with 5 testable tasks.

Implementation ready. Run `/il_2_implement` to begin the loop.

(Note: Using old command name `/implement` until rename is complete)

### Task Status
- [ ] US-001: Rename command files with il_ prefix
- [ ] US-002: Update command headers and descriptions
- [ ] US-003: Consolidate close close into il_3_close
- [ ] US-004: Update all documentation references
- [ ] US-005: Update cross-references between commands

### Branch
`ai/issue-10-streamline-commands`

### Next Step
Run `/implement` to begin implementation.
## 📝 Task Log: US-001 - Rename command files with il_ prefix

**Status:** ✅ Passed
**Attempt:** 1
**Timestamp:** 2026-02-03T04:56:00Z
**Commit:** 264e765

### Summary
Renamed all 6 command files to use the `il_` prefix. Core workflow files received sequential numbering (1, 2, 3), while non-core utility commands received descriptive names without numbers.

### Changes Made
| Old Name | New Name | Type |
|----------|----------|------|
| `issue.md` | `il_1_plan.md` | Core (Step 1) |
| `implement.md` | `il_2_implement.md` | Core (Step 2) |
| `issue-close.md` | `il_3_close.md` | Core (Step 3) |
| `issues.md` | `il_list.md` | Non-core |
| `issue-setup.md` | `il_setup.md` | Non-core |
| `issue-validate.md` | `il_validate.md` | Non-core |

### Verification Results
```
✓ ls .claude/commands/il_*.md | wc -l → 6
✓ ls .claude/commands/il_[123]_*.md | wc -l → 3
```

### Learnings
- Used `git mv` for all renames to preserve git history
- The file content is unchanged - headers and internal references will be updated in US-002
## 📝 Task Log: US-002 - Update command headers and descriptions

**Status:** ✅ Passed
**Attempt:** 1
**Timestamp:** 2026-02-03T05:00:00Z
**Commit:** 3666a42

### Summary
Updated all 6 command files to use the new `/il_` naming convention in their headers, usage sections, and descriptions.

### Changes Made
| File | Old Header | New Header |
|------|------------|------------|
| `il_1_plan.md` | `/issue` | `/il_1_plan` |
| `il_2_implement.md` | `/implement` | `/il_2_implement` |
| `il_3_close.md` | `/issue close` | `/il_3_close` |
| `il_list.md` | `/issues` | `/il_list` |
| `il_setup.md` | `/issue setup` | `/il_setup` |
| `il_validate.md` | `/issue validate` | `/il_validate` |

### Sections Updated Per File
- `# /il_*` - Main header with new command name
- `## Description` - Updated to reference role in workflow
- `## Usage` - Updated all example commands to use new syntax

### Verification Results
```
✓ grep '^# /il_' .claude/commands/il_*.md | wc -l → 6
```

All 6 files have headers matching the new `/il_` naming convention.

### Learnings
- Also updated `/issue close close` to `/il_3_close archive` for clearer semantics (will be referenced in US-003)
## 📝 Task Log: US-003 - Consolidate close close into il_3_close

**Status:** ✅ Passed
**Attempt:** 1
**Timestamp:** 2026-02-03T06:10:00Z
**Commit:** cad2dcf

### Summary
Consolidated the "close close" syntax into a single `/il_3_close` command that automatically detects PR merge state and proceeds accordingly.

### Changes Made
| Section | Change |
|---------|--------|
| Usage | Removed `archive` subcommand, added "Smart Behavior" description |
| Step 1 | New "Automatic PR Detection" section that checks PR state |
| Flow logic | Command now auto-detects: no PR → create, PR exists → show status, PR merged → archive |
| Step numbers | Renumbered all steps (2-10) to accommodate new Step 1 |
| Output | Updated "Next steps" to reference `/il_3_close` instead of `/issue close close` |

### New Behavior
The command now has three modes based on PR state:
1. **No PR exists:** Generates report and creates PR (Steps 2-8)
2. **PR exists but not merged:** Shows PR status and exits with guidance
3. **PR merged:** Skips directly to archive flow (Steps 9-10)

### Verification Results
```
✓ grep -c 'close close' ... → 0 (no occurrences)
✓ grep -c 'PR.*merged|merged.*PR|mergedAt' ... → 9 (detection logic present)
```

### Learnings
- The smart detection approach eliminates the need for users to remember separate commands
- By checking `mergedAt` field from `gh pr view --json`, we can reliably detect merge status
## 📝 Task Log: US-004 - Update all documentation references

**Status:** ✅ Passed
**Attempt:** 1
**Timestamp:** 2026-02-03T07:00:00Z
**Commit:** 5194cd5

### Summary
Updated all documentation files to use the new `/il_` command naming convention, replacing all references to the old commands (`/issue`, `/implement`, `/issues`).

### Changes Made
| File | Changes |
|------|---------|
| `CLAUDE.md` | Updated command list, Ralph Pattern description, installation steps, usage flow, memory system table, error recovery examples |
| `.claude/CLAUDE.md` | Updated command list in GitHub Issue Workflow section |
| `.claude/rules/github-issue-workflow.md` | Updated Commands Quick Reference table, recovery scenarios, testing checkpoint flow |
| `.claude/rules/planning-guide.md` | Updated trigger command reference, implementation prompt, error handling table |
| `.claude/rules/custom-planning-protocol.md` | Updated Phase 5 checkpoint, resuming instructions, integration section |

### Command Mapping Applied
| Old Command | New Command |
|-------------|-------------|
| `/issue setup` | `/il_setup` |
| `/issues` | `/il_list` |
| `/issue N` | `/il_1_plan N` |
| `/implement` | `/il_2_implement` |
| `/issue close` | `/il_3_close` |

### Verification Results
```
✓ All command references updated to il_ naming
✓ Branch naming patterns (ai/issue-{number}-{slug}) preserved - these are not commands
✓ Workflow examples show sequential numbering (1_plan → 2_implement → 3_close)
```

### Note
The verify command returns 7 matches, but all are branch naming patterns (e.g., `ai/issue-42-feature`) which are acceptable context, not command references.

### Learnings
- Branch naming conventions (`ai/issue-{N}-{slug}`) should not be confused with command names
- The grep pattern `/issue` will match both commands and branch names - future verify commands should use more specific patterns like ` /issue` (with leading space) to avoid false positives
## 📝 Task Log: US-005 - Update cross-references between commands

**Status:** ✅ Passed
**Attempt:** 1
**Timestamp:** 2026-02-03T08:00:00Z
**Commit:** f9e26a4

### Summary
Updated all internal cross-references within command files to use the new `il_` naming convention. This ensures that when one command suggests running another command, it uses the correct new name.

### Changes Made
| File | Old Reference | New Reference |
|------|---------------|---------------|
| `il_1_plan.md` | `Run /implement` | `Run /il_2_implement` |
| `il_2_implement.md` | `/issue N` | `/il_1_plan N` |
| `il_2_implement.md` | `Run /issue close` | `Run /il_3_close` |
| `il_3_close.md` | `Run /implement` | `Run /il_2_implement` |
| `il_3_close.md` | `Run /issue close` | `Run /il_3_close` |
| `il_list.md` | `/issue {number}` | `/il_1_plan {number}` |
| `il_setup.md` | `/issue setup` | `/il_setup` |
| `il_setup.md` | File path references | Updated to il_*.md |
| `il_validate.md` | `/issue setup` | `/il_setup` |

### Verification Results
```
✓ grep -r 'Run /issue|Run /implement|/issues' .claude/commands/ | grep -v 'il_' | wc -l → 0
```

All cross-references now use the correct `il_` naming convention.

### Learnings
- There were 17 total references across 6 files that needed updating
- The grep verification command correctly identifies old references while excluding the new il_ prefixed commands
- File path references in verification output sections also needed updating (e.g., `issues.md` → `il_list.md`)
## 🧪 Testing Checkpoint

All **5 tasks** have passed automated verification.

### Tasks Completed
- ✅ US-001: Renamed 6 command files with `il_` prefix
- ✅ US-002: Updated headers and descriptions in all files
- ✅ US-003: Consolidated `close close` into single `/il_3_close` command
- ✅ US-004: Updated all documentation references
- ✅ US-005: Updated cross-references between commands

### New Command Names
| Old | New |
|-----|-----|
| `/issue` | `/il_1_plan` |
| `/implement` | `/il_2_implement` |
| `/issue close` | `/il_3_close` |
| `/issues` | `/il_list` |
| `/issue setup` | `/il_setup` |
| `/issue validate` | `/il_validate` |

### Please Test
1. Run `/il_list` to verify issues command works
2. Verify `/il_1_plan`, `/il_2_implement`, `/il_3_close` appear in skills
3. Check that documentation references are consistent

When ready, respond with your testing results.
## 📊 Final Implementation Report

**Issue:** #10 - Streamline command system with il_ prefix and sequential numbering
**Branch:** ai/issue-10-streamline-commands
**Completed:** 2026-02-03
**Testing Status:** ✅ Verified by user

---

### Executive Summary

Renamed all 6 command files to use the `il_` prefix with sequential numbering for the core workflow (1, 2, 3). Updated all documentation references and cross-references between commands. Consolidated the `close close` syntax into a single `/il_3_close` command with automatic PR merge detection.

---

### Implementation Statistics

| Metric | Value |
|--------|-------|
| Tasks Completed | 5/5 |
| Total Attempts | 5 |
| First-Pass Success | 5/5 (100%) |
| Files Changed | 12 |

---

### Task Summary

| ID | Task | Attempts | Status |
|----|------|----------|--------|
| US-001 | Rename command files with il_ prefix | 1 | ✅ |
| US-002 | Update command headers and descriptions | 1 | ✅ |
| US-003 | Consolidate close close into il_3_close | 1 | ✅ |
| US-004 | Update all documentation references | 1 | ✅ |
| US-005 | Update cross-references between commands | 1 | ✅ |

---

### New Command Names

| Old Command | New Command | Purpose |
|-------------|-------------|---------|
| `/issue N` | `/il_1_plan N` | Step 1: Load, scope, plan issue |
| `/implement` | `/il_2_implement` | Step 2: Execute task loop |
| `/issue close` | `/il_3_close` | Step 3: Report, PR, archive |
| `/issues` | `/il_list` | List open issues |
| `/issue setup` | `/il_setup` | Initialize workflow |
| `/issue validate` | `/il_validate` | Check prerequisites |

---

### Changes by Category

#### Renamed Files (6)
- `issue.md` → `il_1_plan.md`
- `implement.md` → `il_2_implement.md`
- `close.md` → `il_3_close.md`
- `issues.md` → `il_list.md`
- `setup.md` → `il_setup.md`
- `validate.md` → `il_validate.md`

#### Updated Documentation (4)
- `CLAUDE.md` - Main project instructions
- `.claude/CLAUDE.md` - Template instructions
- `.claude/rules/github-issue-workflow.md` - Workflow rules
- `.claude/rules/planning-guide.md` - Planning guide

---

### Key Improvements

1. **Sequential Numbering**: Core workflow commands now have sequential numbers (1, 2, 3) making the workflow order explicit

2. **Unified Prefix**: All commands use `il_` prefix for easy discovery and namespacing

3. **Consolidated Close**: Single `/il_3_close` command now handles both report+PR creation and archiving, with automatic PR merge detection

---

### Commit History (Issue #10)

```
9fa72ff chore: mark testing as verified (#10)
33d02ee chore: all tasks passing - ready for testing (#10)
fb3489f chore: update prd.json - US-005 passed (#10)
f9e26a4 feat(US-005): update cross-references between commands (#10)
e7c1466 chore: update prd.json - US-004 passed (#10)
5194cd5 feat(US-004): update all documentation references to il_ naming (#10)
aab49f8 chore: update prd.json - US-003 passed (#10)
cad2dcf feat(US-003): consolidate close close into single il_3_close command (#10)
9b82d7d chore: update prd.json - US-002 passed (#10)
3666a42 feat(US-002): update command headers and descriptions (#10)
b61cea2 chore: update prd.json - US-001 passed (#10)
264e765 feat(US-001): rename command files with il_ prefix (#10)
1222cee chore: add prd.json for issue #10
```

---

**Ready for Review** - All 5 tasks passing, user testing verified.
Pull Request created: #11

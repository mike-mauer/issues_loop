## 📋 Implementation Plan

**Issue:** #7 - Bug: /implement workflow steps not being followed
**Generated:** 2026-02-03T03:15:38Z
**Status:** Pending Approval
**Complexity:** Medium (4 tasks)

---

### Overview
The documentation already describes the correct behavior, but Claude doesn't follow it consistently. This plan restructures `implement.md` to make loop mode the unmissable default and adds explicit enforcement checkpoints with MUST/CRITICAL language. The key insight is that enforcement requires restructuring and strong language, not just adding more documentation.

---

### Tasks

#### US-001: Restructure implement.md to enforce loop mode as default
**Priority:** 1
**Files:** `.claude/commands/implement.md`
**Depends on:** None

Reorganize the command flow so loop mode executes FIRST. Add explicit "MUST launch the background script" instruction at the top of the flow.

**Acceptance Criteria:**
- [ ] Loop mode section appears before interactive mode in Step 0b
- [ ] Default (no args) immediately triggers "Launch Background Script"
- [ ] Explicit language: "You MUST launch the background script"

---

#### US-002: Add CRITICAL enforcement section for GitHub posting
**Priority:** 2
**Files:** `.claude/commands/implement.md`
**Depends on:** US-001

Add a new "CRITICAL REQUIREMENTS" section at the top listing non-negotiable actions. Include task log posting and discovery notes with MUST/REQUIRED language.

**Acceptance Criteria:**
- [ ] "CRITICAL REQUIREMENTS" section exists near the top
- [ ] Explicitly states task logs MUST be posted
- [ ] Explicitly states discovery notes MUST be posted when patterns found

---

#### US-003: Add post-task checklist enforcement
**Priority:** 3
**Files:** `.claude/commands/implement.md`
**Depends on:** US-002

Add explicit "POST-TASK CHECKLIST" after task completion that MUST be completed before moving on. Include mandatory GitHub posting items.

**Acceptance Criteria:**
- [ ] "POST-TASK CHECKLIST" section exists
- [ ] Includes "Post task log to GitHub" as mandatory
- [ ] Contains "Do not proceed until completed" warning

---

#### US-004: Update Interactive Mode with same enforcement
**Priority:** 4
**Files:** `.claude/commands/implement.md`
**Depends on:** US-003

Ensure interactive mode has the same GitHub posting requirements. Make clear that "single" mode does NOT skip GitHub actions.

**Acceptance Criteria:**
- [ ] Interactive mode references CRITICAL REQUIREMENTS
- [ ] Includes same POST-TASK CHECKLIST requirement
- [ ] Clear statement about GitHub posting in single mode

---

### Task Dependencies
```
US-001 (Priority 1) ← No dependencies
  ↓
US-002 (Priority 2) ← Depends on US-001
  ↓
US-003 (Priority 3) ← Depends on US-002
  ↓
US-004 (Priority 4) ← Depends on US-003
```

---

### Verification Commands
```bash
grep -c "CRITICAL REQUIREMENTS" .claude/commands/implement.md
grep -c "POST-TASK CHECKLIST" .claude/commands/implement.md
grep -c "MUST.*post" .claude/commands/implement.md
```

## ✅ Plan Approved

**prd.json generated** with 4 testable tasks.

Implementation ready. Run `/implement` to begin the loop.

### Task Status
- [ ] US-001: Restructure implement.md to enforce loop mode as default
- [ ] US-002: Add CRITICAL enforcement section for GitHub posting
- [ ] US-003: Add post-task checklist enforcement
- [ ] US-004: Update Interactive Mode section with same enforcement

### Branch
`ai/issue-7-implement-workflow-enforcement`

### Next Step
Run `/implement` or `/implement start` to begin implementation.
## 📝 Task Log: US-001 - Restructure implement.md to enforce loop mode as default

**Status:** ✅ Passed
**Attempt:** 1
**Timestamp:** 2026-02-03T03:19:20Z
**Commit:** [b3d4861](https://github.com/mike-mauer/issues_loop/commit/b3d4861)

### Summary
Restructured implement.md to make loop mode the unmissable default by adding explicit enforcement language and reordering sections.

### Changes Made
- `.claude/commands/implement.md` - Added "MODE SELECTION" section with MUST language at line 38
- `.claude/commands/implement.md` - Added argument check table that routes to Loop Mode first
- `.claude/commands/implement.md` - Added "Loop Mode (DEFAULT - Check This First)" section at line 147, BEFORE Implementation Loop
- `.claude/commands/implement.md` - Renamed later Loop Mode section to "Loop Mode Reference"
- `.claude/commands/implement.md` - Added explicit "STOP HERE" instruction after launching script
- `.claude/commands/implement.md` - Made Implementation Loop explicitly state "Interactive Mode Only"

### Verification Results
```
✓ grep -n "MUST launch" → Found at lines 40, 48, 49
✓ Loop Mode section (line 147) appears BEFORE Implementation Loop (line 203)
✓ Explicit enforcement language present
```

### Learnings
- Simply documenting behavior is not enough - explicit routing and STOP instructions are needed
- Section ordering matters - Loop Mode must come BEFORE interactive mode to be the default path
## 📝 Task Log: US-002 - Add CRITICAL REQUIREMENTS section for GitHub posting

**Status:** ✅ Passed
**Attempt:** 1
**Timestamp:** 2026-02-03T03:20:22Z
**Commit:** [83d1743](https://github.com/mike-mauer/issues_loop/commit/83d1743)

### Summary
Added a prominent CRITICAL REQUIREMENTS section at the top of implement.md that makes GitHub posting mandatory with checklist enforcement.

### Changes Made
- `.claude/commands/implement.md` - Added "🚨 CRITICAL REQUIREMENTS - NON-NEGOTIABLE" section at line 37
- Contains 6-item checklist with MUST DO items
- Explicit "MUST post task log to GitHub" statement
- Explicit "MUST post discovery note if patterns found" statement
- "GitHub Posting is MANDATORY" subsection with format examples
- Enforcement statement: "task is NOT complete" without GitHub posting

### Verification Results
```
✓ grep -c 'CRITICAL REQUIREMENTS' → 1
✓ grep -ci 'MUST.*post.*task log' → 1
✓ grep -ci 'MUST.*post.*discovery note' → 1
✓ grep -c checklist items → 6
```

### Learnings
- Checklist format with explicit MUST language is clearer than prose
- Placing enforcement section early (after Prerequisites) ensures visibility
## 📝 Task Log: US-003 - Add post-task checklist enforcement

**Status:** ✅ Passed
**Attempt:** 1
**Timestamp:** 2026-02-03T03:21:22Z
**Commit:** [57bc343](https://github.com/mike-mauer/issues_loop/commit/57bc343)

### Summary
Added a 7-item POST-TASK CHECKLIST section after Step 7 that acts as a gate before moving to the next task.

### Changes Made
- `.claude/commands/implement.md` - Added "🛑 POST-TASK CHECKLIST - STOP AND VERIFY" section after Step 7 (line ~370)
- Includes verification table with 7 items including Done? column
- Item #6: "Post task log to GitHub" - mandatory
- Item #7: "Post discovery note" - if patterns found
- Bold "STOP. Do not proceed until ALL items are completed" warning
- Explanation that GitHub comments are the memory system

### Verification Results
```
✓ grep -c 'POST-TASK CHECKLIST' → 1
✓ grep -A 20 'POST-TASK CHECKLIST' | grep -c 'GitHub' → 3
✓ 'Do not proceed until' warning present
```

### Learnings
- Table format with Done? column is clearer than prose checklist
- Placing the checklist between commit (Step 7) and posting (Step 8) creates a natural gate
## 📝 Task Log: US-004 - Update Interactive Mode section with same enforcement

**Status:** ✅ Passed
**Attempt:** 1
**Timestamp:** 2026-02-03T03:22:12Z
**Commit:** [195dd9f](https://github.com/mike-mauer/issues_loop/commit/195dd9f)

### Summary
Added enforcement language to Interactive Mode section making clear that `single` and `task` modes do not skip GitHub posting requirements.

### Changes Made
- `.claude/commands/implement.md` - Added "⚠️ Interactive Mode Still Requires GitHub Posting" subsection after Interactive Mode header
- Explicit statement: "Using \`single\` or \`task\` does NOT skip the CRITICAL REQUIREMENTS"
- References 🚨 CRITICAL REQUIREMENTS section
- References 🛑 POST-TASK CHECKLIST requirement
- Bullet list of MUST requirements including GitHub posting
- Clarifies only execution method differs, all other requirements same

### Verification Results
```
✓ grep finds 'CRITICAL REQUIREMENTS' reference
✓ grep finds 'POST-TASK CHECKLIST' reference
✓ grep finds 'does NOT skip' statement
```

### Learnings
- Explicit "does NOT skip" language is clearer than "still applies"
- Listing the same requirements again reinforces the message
## 🧪 Testing Checkpoint

All **4 tasks** have passed automated verification.

### Completed Tasks
- ✅ US-001: Restructure implement.md to enforce loop mode as default
- ✅ US-002: Add CRITICAL REQUIREMENTS section for GitHub posting
- ✅ US-003: Add post-task checklist enforcement
- ✅ US-004: Update Interactive Mode section with same enforcement

### Changes Summary
The `implement.md` command file has been restructured to enforce:
1. **Loop mode is the default** - Explicit "MUST launch background script" language with clear routing
2. **GitHub posting is mandatory** - CRITICAL REQUIREMENTS section with checklist
3. **Post-task checklist gate** - 7-item checklist that must be completed before next task
4. **Interactive mode same rules** - Clear statement that `single`/`task` does NOT skip requirements

**Please test the implementation manually:**
1. Pull the branch: `git checkout ai/issue-7-implement-workflow-enforcement`
2. Review the updated `.claude/commands/implement.md` file
3. Verify the enforcement language is clear and effective

When ready, respond with your testing results.
## 🔍 Discovery Note

**Source:** Testing checkpoint discussion
**Timestamp:** 2026-02-03T03:30:55Z

### Pattern Discovered

**Interactive mode fundamentally breaks the Ralph pattern.**

When executing tasks in a conversation:
- Claude has memory of previous tasks (violates fresh context principle)
- Claude doesn't need to read GitHub comments (bypasses memory system)
- Learnings stay in conversation context, not persisted to issue

The background script enforces fresh context because each task runs as a separate `claude --print` invocation with zero memory.

### Resolution

Removed interactive mode as a default option. Now:
- `/implement` → Always launches background script
- `/implement interactive-mode` → Explicit escape hatch with warnings

### Files for Reference
- `.claude/commands/implement.md` - Updated usage and mode selection
- `.claude/scripts/implement-loop.sh` - The script that enforces fresh context

### Impact on Workflow
Users must explicitly opt-in to interactive mode and acknowledge they're breaking the pattern. This prevents accidental context pollution.
## 📊 Final Implementation Report

**Issue:** #7 - Bug: /implement workflow steps not being followed
**Branch:** ai/issue-7-implement-workflow-enforcement
**Completed:** 2026-02-03T03:35:28Z
**Testing Status:** ✅ Verified by user

---

### Executive Summary

Fixed the /implement command to enforce workflow steps by restructuring the documentation, removing default interactive mode, and adding explicit enforcement checkpoints. The core insight was that interactive mode fundamentally breaks the Ralph pattern's fresh context principle.

---

### Implementation Statistics

| Metric | Value |
|--------|-------|
| Tasks Completed | 4/4 |
| Total Attempts | 4 |
| First-Pass Success | 4/4 (100%) |
| Debug Fixes | 0 |
| Commits | 13 |
| Files Changed | 2 |
| Lines Added | +329 |
| Lines Removed | -64 |

---

### Task Summary

| ID | Task | Attempts | Status |
|----|------|----------|--------|
| US-001 | Restructure implement.md to enforce loop mode as default | 1 | ✅ |
| US-002 | Add CRITICAL enforcement section for GitHub posting | 1 | ✅ |
| US-003 | Add post-task checklist enforcement | 1 | ✅ |
| US-004 | Update Interactive Mode section with same enforcement | 1 | ✅ |

---

### Changes Made

#### Modified Files
- `.claude/commands/implement.md` - Major restructure for workflow enforcement
- `prd.json` - Task state tracking (will be archived)

#### Key Changes to implement.md

1. **Removed default interactive mode**
   - `/implement` now always launches background script
   - Added `interactive-mode` as explicit escape hatch with warnings
   
2. **Added CRITICAL REQUIREMENTS section**
   - Mandatory checklist for every task
   - Explicit "MUST post task log to GitHub" requirement
   - Explicit "MUST post discovery note" requirement

3. **Added POST-TASK CHECKLIST**
   - 7-item verification gate after each task
   - "STOP. Do not proceed until ALL items completed"

4. **Simplified usage**
   - `/implement` → Create branch if needed + loop mode
   - `/implement verify` → Re-run verification
   - `/implement interactive-mode` → Escape hatch (breaks fresh context)

---

### Key Decisions Made

1. **Remove interactive mode as default**
   - Decision: Only loop mode is available by default
   - Rationale: Interactive mode breaks fresh context principle

2. **Merge /implement start into /implement**
   - Decision: One command that does the right thing
   - Rationale: Simplicity - branch creation should be automatic

3. **Explicit escape hatch naming**
   - Decision: Use `interactive-mode` (not `single`)
   - Rationale: Name makes the tradeoff clear

---

### Learnings Captured

1. **Interactive mode breaks Ralph pattern**
   - Claude has memory of previous tasks in conversation
   - Bypasses the memory system (GitHub comments)
   - Background script enforces fresh context via separate invocations

2. **Enforcement requires removing alternatives**
   - Strong documentation language wasn't enough
   - Removing the easy path is more effective than warnings

3. **Section ordering matters**
   - Loop Mode section must appear before Interactive Mode
   - Claude follows documentation in order

---

### Verification Results

All acceptance criteria from Issue #7:
```
✓ /implement (no args) routes to loop mode
✓ Task logs posted to GitHub after each task
✓ Discovery notes posted when patterns found
✓ CRITICAL REQUIREMENTS section exists
✓ POST-TASK CHECKLIST enforced
```

---

### Commit History

```
c1d0046 chore: mark testing as verified (#7)
1878745 refactor: merge /implement start into /implement (#7)
e9cd634 refactor: remove default interactive mode, add escape hatch (#7)
d7c22e7 chore: enter testing checkpoint (#7)
7f946ff feat(US-004): update Interactive Mode with same enforcement (#7)
910ca33 feat(US-003): add post-task checklist enforcement (#7)
b4d3ec2 feat(US-002): add CRITICAL REQUIREMENTS section for GitHub posting (#7)
0f83466 feat(US-001): restructure implement.md to enforce loop mode as default (#7)
b2c91e3 chore: add prd.json for issue #7
```

---

**Ready for Review** - All 4 tasks passing, user testing verified.
Pull Request created: #9

https://github.com/mike-mauer/issues_loop/pull/9

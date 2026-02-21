# Custom Planning Protocol

This protocol defines a custom 5-phase planning system that integrates seamlessly with the GitHub Issue Workflow. It replaces native plan mode with explicit phases, adaptive checkpoints, and full visibility into the planning process.

## Why This Protocol Exists

Native plan mode is too opaque - we can't control:
- When and how exploration happens
- Checkpoint questions and options
- GitHub integration at each phase
- prd.json generation timing
- Resumability if session ends mid-planning

This protocol provides explicit phases, score-adaptive checkpoints, and full visibility into the planning process.

---

## Protocol Overview

```
Phase 1: EXPLORATION
├─ Detect formula type (bugfix/feature/refactor)
├─ Load formula template from templates/formulas/
├─ Analyze codebase context
├─ Display Discovery Summary (with formula)
└─ Checkpoint: "Proceed to planning?"

Phase 2: TASK DECOMPOSITION
├─ Break into right-sized tasks
├─ Define acceptance criteria + verify commands
├─ Show dependency graph
└─ Checkpoint: "Task breakdown correct?"

Phase 3: DESIGN VALIDATION
├─ Validate task quality
├─ Check testability of criteria
└─ Checkpoint: "Ready to finalize?"

Phase 4: GITHUB POSTING
├─ Post plan to issue
├─ Update labels
└─ Checkpoint: "Approve plan?"

Phase 5: PRD.JSON GENERATION
├─ Generate prd.json from plan
├─ Create branch, commit, push
├─ Post approval comment
└─ Checkpoint: "Ready to implement?"
```

### Checkpoint Modes (by Completeness Score)

Use the score from `/il_1_plan` Step 3:

| Score | Mode | Required user checkpoints |
|-------|------|---------------------------|
| **9-10** | Fast Lane A | 1 checkpoint total: combined approval + start |
| **7-8** | Fast Lane B | 2 checkpoints: task breakdown + combined approval + start |
| **0-6** | Full Lane | All phase checkpoints |

In Fast Lane modes, still execute all 5 phases. The reduction applies only to user prompts, not quality checks.

### Combined Approval + Start Prompt

For Fast Lane modes, replace separate Phase 4 and Phase 5 prompts with one combined checkpoint after `prd.json` is generated:

```
Question: "Plan approved, prd.json is generated, and branch is ready. Start implementation now?"
Options:
  1. "Yes, run /il_2_implement" - Approve and start now
  2. "Approved, start later" - Approve but stop after planning
  3. "Changes needed" - Return to plan edits
```

---

## Phase 1: Exploration

**Goal:** Gather codebase context before planning. Understand patterns, conventions, and relevant files. Detect the issue formula type.

### What To Do

1. **Read the issue** - Understand requirements, acceptance criteria, scope
2. **Detect formula type** - Classify the issue as bugfix, feature, or refactor:
   - Check issue labels first (highest priority): `bug`/`regression`/`defect` → bugfix, `refactor`/`tech-debt`/`cleanup` → refactor, `feature`/`enhancement`/`new` → feature
   - If no label match, scan issue title + body for keywords (see `.claude/commands/il_1_plan.md` Step 2b for full decision tree)
   - Default to `feature` when ambiguous
   - Load the matching formula template from `templates/formulas/{formula}.md` — this guides task topology in Phase 2
3. **Explore the codebase** using search and file reading tools:
   - Find relevant existing files
   - Identify patterns and conventions
   - Locate similar features for reference
   - Note integration points
4. **Identify risks** - Edge cases, dependencies, potential blockers
5. **Synthesize findings** into a Discovery Summary (including detected formula)

### Discovery Summary Template

Display this to the user before proceeding:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 Discovery Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

**Issue:** #{number} - {title}

### Formula Detection
- **Detected formula:** {bugfix|feature|refactor}
- **Detection source:** {label match|keyword match|default}
- **Template:** `templates/formulas/{formula}.md`
- **Task topology:** {e.g., reproduce → fix → verify}

### Requirements Found
- {requirement 1}
- {requirement 2}

### Codebase Context
- **Relevant files:** {list of files examined}
- **Patterns found:** {conventions used in codebase}
- **Similar features:** {existing code to reference}

### Risks Identified
- {potential issue 1}
- {potential issue 2}

### Recommended Approach
- {high-level strategy}
- **Files to modify:** {list}
- **Files to create:** {list}
- **Complexity:** {Low/Medium/High}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Phase 1 Checkpoint

Use `AskUserQuestion`:

```
Question: "Exploration complete. Ready to proceed?"
Options:
  1. "Yes, proceed to planning" - Discovery looks good, continue
  2. "Explore more" - Investigate specific areas further
  3. "Different focus" - Redirect exploration to other areas
```

**On "Yes":** Proceed to Phase 2
**On "Explore more":** Ask what to investigate, return to exploration
**On "Different focus":** Ask where to focus, restart exploration

Fast-lane behavior:
- **Skip this checkpoint** for scores `7-10` and proceed directly to Phase 2.
- Keep this checkpoint for scores `0-6`.

---

## Phase 2: Task Decomposition

**Goal:** Break the requirement into small, testable, context-window-sized tasks using the detected formula's topology.

### What To Do

1. **Decompose** the requirement into discrete tasks following the formula template's task topology (e.g., bugfix: reproduce → fix → verify). Reference `templates/formulas/{formula}.md` for default phases, acceptance criteria patterns, and verify command patterns.
2. **For each task, define:**
   - `id` - Unique identifier (US-001, US-002, etc.)
   - `title` - Action-oriented, 5-8 words
   - `description` - 2-3 sentences with specific files/changes
   - `acceptanceCriteria` - Testable checkboxes (not subjective!)
   - `verifyCommands` - Bash commands that prove success
   - `dependsOn` - Task IDs that must pass first
   - `priority` - Execution order (1 = first)

3. **Apply the 2-3 sentence rule:** If you can't describe a task in 2-3 sentences, it's too big - split it.

4. **Show the dependency graph** so user can validate order

### Task Format

Follow the format in `.claude/rules/planning-guide.md`:

```markdown
### US-001: {Task title}
**Priority:** 1
**Files:** `path/to/file.ts`, `path/to/other.ts`
**Depends On:** None

**Description:**
{What to implement in 2-3 sentences. Include specific details about
what to create/modify and any important context.}

**Acceptance Criteria:**
- [ ] {Verifiable criterion 1 - must be testable}
- [ ] {Verifiable criterion 2 - must be testable}

**Verify Commands:**
```bash
command1
command2
```
```

### Dependency Graph Display

Show tasks with their relationships:

```
Task Dependencies:
  US-001 (Priority 1) ← No dependencies
    ↓
  US-002 (Priority 2) ← Depends on US-001
  US-003 (Priority 2) ← Depends on US-001
    ↓
  US-004 (Priority 3) ← Depends on US-002, US-003
```

### Phase 2 Checkpoint

Use `AskUserQuestion`:

```
Question: "Task breakdown complete. Does this look right?"
Options:
  1. "Yes, proceed" - Task decomposition is good
  2. "Split task X" - A task is too big, needs breaking down
  3. "Merge tasks" - Some tasks should be combined
  4. "Change dependencies" - Execution order needs adjustment
```

**On "Yes":** Proceed to Phase 3
**On other options:** Make requested changes, show updated breakdown

Fast-lane behavior:
- **Required** for scores `7-8`.
- **Optional** for scores `9-10` (only prompt if decomposition quality is unclear or risk is high).
- **Required** for scores `0-6`.

---

## Phase 3: Design Validation

**Goal:** Validate plan quality before posting to GitHub.

### Validation Checks

Run these checks on all tasks:

| Check | Pass Criteria | Fail Action |
|-------|---------------|-------------|
| **Task Size** | Description ≤ 3 sentences | Split the task |
| **Testable Criteria** | No subjective words (clean, proper, good) | Rewrite with measurable criteria |
| **Verify Commands** | Commands are executable bash | Add real commands |
| **Dependencies** | No circular dependencies | Fix dependency chain |
| **Files Specified** | At least one file listed | Add file paths |

### Good vs Bad Acceptance Criteria

**Good (testable):**
- `npm run typecheck passes`
- `File src/lib/auth.ts exists`
- `POST /api/users returns 201`
- `grep -q "export function validate" src/utils.ts`

**Bad (subjective):**
- "Code is clean" ❌
- "Works correctly" ❌
- "Handles errors properly" ❌
- "Is well-structured" ❌

### Validation Report Display

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Design Validation Results
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Checks: 18/20 passed

Issues Found:
❌ US-003: Criterion "Code is clean" is not testable
⚠️ US-004: No verify commands specified

Recommendations:
1. Replace "Code is clean" with "npm run lint passes"
2. Add verify commands to US-004

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Phase 3 Checkpoint

Use `AskUserQuestion`:

```
Question: "Validation complete. Ready to finalize?"
Options:
  1. "Yes, apply fixes and continue" - Auto-fix issues and proceed
  2. "I'll fix manually" - Keep as-is, I'll handle it
  3. "Review issues first" - Show me the problems in detail
```

**On "Yes":** Apply recommended fixes, proceed to Phase 4
**On "I'll fix":** Proceed without changes
**On "Review":** Show detailed issue breakdown

Fast-lane behavior:
- **Skip this checkpoint** for scores `7-10` after applying objective validation fixes.
- Keep this checkpoint for scores `0-6`.

---

## Phase 4: GitHub Posting

**Goal:** Post the plan to the GitHub issue for visibility and persistence.

### What To Do

1. **Format the plan** as a human-readable comment
2. **Post to GitHub** using `gh issue comment`
3. **Update label** to "AI: Planning"

### GitHub Comment Format

```markdown
## 📋 Implementation Plan

**Issue:** #42 - {title}
**Generated:** {date}
**Status:** Approved
**Complexity:** {Low/Medium/High} ({N} tasks)

---

### Overview
{2-3 sentence approach summary}

---

### Tasks

#### US-001: {title}
**Files:** {files}
**Depends on:** {dependencies}

{description}

**Acceptance Criteria:**
- [ ] {criterion 1}
- [ ] {criterion 2}

---

{repeat for all tasks}

---

### Task Dependencies
```
{dependency graph}
```
```

### Phase 4 Checkpoint

Use `AskUserQuestion`:

```
Question: "Plan posted to GitHub. Approve?"
Options:
  1. "Approved" - Continue to prd.json generation
  2. "Changes needed" - I want to modify something
  3. "Review on GitHub" - I'll check the comment and come back
```

**On "Approved":** Proceed to Phase 5
**On "Changes needed":** Ask what to change, update plan
**On "Review":** Pause, user will return later

Fast-lane behavior:
- For scores `7-10`, do not prompt here. Continue to Phase 5 and use the combined approval + start prompt there.
- For scores `0-6`, keep this checkpoint.

---

## Phase 5: prd.json Generation

**Goal:** Generate machine-readable task file and finalize approval.

### What To Do

1. **Parse the plan** - Extract all task fields from the markdown
2. **Generate prd.json** following the schema in `.claude/rules/planning-guide.md`
3. **Create branch** if it doesn't exist: `ai/issue-{N}-{slug}`
4. **Commit prd.json** with message: `chore: add prd.json for issue #{N}`
5. **Push to remote**
6. **Post approval comment** to GitHub: `## ✅ Plan Approved`
7. **Update label** to "AI: Approved"

### prd.json Schema

The `formula` field must be set to the formula detected in Phase 1. This persists the selected formula for use by the implementation loop.

```json
{
  "project": "{slug-from-title}",
  "issueNumber": 42,
  "branchName": "ai/issue-42-{slug}",
  "description": "{issue title}",
  "generatedAt": "{ISO timestamp}",
  "status": "approved",
  "formula": "{bugfix|feature|refactor}",
  "compaction": {
    "taskLogCountSinceLastSummary": 0,
    "summaryEveryNTaskLogs": 5
  },
  "userStories": [
    {
      "id": "US-001",
      "uid": "tsk_{12-char-hash}",
      "phase": 1,
      "priority": 1,
      "title": "Task title",
      "description": "What to implement",
      "files": ["path/to/file.ts"],
      "dependsOn": [],
      "discoveredFrom": null,
      "discoverySource": null,
      "acceptanceCriteria": ["Testable criterion"],
      "verifyCommands": ["npm run test"],
      "passes": false,
      "attempts": 0,
      "lastAttempt": null
    }
  ],
  "globalVerifyCommands": []
}
```

### Phase 5 Checkpoint

Use `AskUserQuestion`:

```
Question: "prd.json generated. Ready to implement?"
Options:
  1. "Yes, run /il_2_implement" - Start implementation loop now
  2. "Not yet" - I'll start later
```

**On "Yes":** Suggest running `/il_2_implement` or `/il_2_implement start`
**On "Not yet":** End planning, user can return with `/il_1_plan N --quick`

Fast-lane behavior:
- For scores `7-10`, replace this prompt with the combined approval + start prompt defined above.
- For scores `0-6`, keep this checkpoint.

---

## Resuming Mid-Planning

If a session ends during planning:

1. **Check GitHub comments** for last posted plan/status
2. **Check prd.json** existence and content
3. **Determine current phase:**
   - No GitHub comments → Start from Phase 1
   - Plan comment but no approval → Resume at Phase 4 checkpoint
   - Approval comment but no prd.json → Resume at Phase 5
   - prd.json exists → Planning complete, suggest `/il_2_implement`

---

## Integration with /il_1_plan Command

The `/il_1_plan` command's Step 4 (Planning Phase) should:

1. Reference this protocol: "Follow `.claude/rules/custom-planning-protocol.md`"
2. Execute phases in order
3. Use `AskUserQuestion` for checkpoints according to score mode
4. NOT use native plan mode directly (`EnterPlanMode` / `ExitPlanMode`)

---

## Quick Reference: Checkpoint Questions

| Mode | Checkpoint Sequence |
|------|---------------------|
| **Fast Lane A (9-10)** | Combined approval + start only |
| **Fast Lane B (7-8)** | Phase 2 checkpoint → Combined approval + start |
| **Full Lane (0-6)** | Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 |

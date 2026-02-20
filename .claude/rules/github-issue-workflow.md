# GitHub Issue Workflow Rules (Ralph Pattern)

> **Include this in your main CLAUDE.md** by adding:
> ```markdown
> ## GitHub Issue Workflow
> See `.claude/rules/github-issue-workflow.md` for issue-driven development rules.
> ```

---

## Core Philosophy: The Ralph Pattern

This workflow follows the **Ralph Pattern** - an autonomous AI loop that:
1. Breaks work into small, testable tasks
2. Executes each task in a **fresh context**
3. Verifies completion with automated tests
4. Persists learnings for future iterations

### The Fresh Context Principle
Each task execution starts with **zero memory** of previous work. Context comes only from:
- `prd.json` - Task definitions and pass/fail status
- Git history - Committed code and messages
- GitHub issue comments - Task logs and learnings

**Why?** Prevents context pollution, forces explicit documentation, enables recovery from any state.

---

## Workflow States

Issues progress through these labels:
| Label | Meaning |
|-------|---------|
| `AI` | Trigger for planning |
| `AI: Planning` | Plan being generated/refined |
| `AI: Approved` | Plan approved, prd.json generated |
| `AI: In Progress` | Implementation loop running |
| `AI: Testing` | All tasks pass, awaiting user testing |
| `AI: Blocked` | Task failed 3x or debug blocked, needs human input |
| `AI: Review` | User verified, PR ready |
| `AI: Complete` | Merged and closed |

---

## Memory System

### Source of Truth: prd.json
```json
{
  "project": "feature-name",
  "issueNumber": 42,
  "branchName": "ai/issue-42-feature",
  "userStories": [
    {
      "id": "US-001",
      "title": "Task title",
      "description": "What to do",
      "acceptanceCriteria": ["Testable criterion 1", "Testable criterion 2"],
      "verifyCommands": ["npm run test"],
      "passes": false,
      "attempts": 0
    }
  ]
}
```

### GitHub Issue Comments
| Prefix | Purpose | When Written |
|--------|---------|--------------|
| `## 📋 Implementation Plan` | Human-readable plan | Plan creation |
| `## ✅ Plan Approved` | Approval confirmation | Plan approval |
| `## 📝 Task Log: US-XXX` | Task completion record | After each task attempt |
| `## 🔍 Discovery Note` | Patterns/learnings for future tasks | When patterns discovered |
| `## 🧾 Compacted Summary` | Periodic summary of recent task logs | Every N task logs (default 5) |
| `## 🪶 Wisp` | Ephemeral context hint with expiration | During task execution |
| `## 🔁 Replan Checkpoint` | Retry-stall checkpoint | When stale retry thresholds are hit |
| `## 🧪 Testing Checkpoint` | Request manual testing | All tasks pass |
| `## 🔧 Debug Session` | Document debug attempt | User reports issue |
| `## ✅ Debug Fix Applied` | Document successful fix | Debug fix verified |
| `## 🚫 Debug Blocked` | Escalate to human | 3 debug attempts fail |
| `## 📊 Final Report` | Implementation summary | Before PR creation |

### Task Log Format
```markdown
## 📝 Task Log: US-003 - Create auth middleware

**Status:** ✅ Passed | ❌ Failed
**Attempt:** 2
**Timestamp:** 2024-01-15 14:32 UTC
**Commit:** abc1234 (if passed)

### Summary
[1-2 sentences on what was done]

### Changes Made
- `path/to/file.ts` - [what changed]

### Verification Results
```
✓ npm run typecheck
✓ npm run test -- auth
```

### Learnings
[Patterns discovered that future tasks should know]

### Next Attempt Should (if failed)
[Specific guidance for retry]

### Event JSON
```json
{"v":1,"type":"task_log","issue":42,"taskId":"US-003","taskUid":"tsk_a1b2c3d4e5f6","status":"pass","attempt":2,"commit":"abc1234","verify":{"passed":["npm run typecheck"],"failed":[]},"search":{"queries":["rg -n \"auth\" src","rg -n \"token\" src"],"filesInspected":["src/auth.ts"]},"discovered":[],"ts":"2026-02-10T18:30:00Z"}
```
```

The `### Event JSON` section is **required** in every task log comment. It contains a single compact JSON object inside a fenced `json` code block.

#### Event JSON Schema

| Field | Type | Description |
|-------|------|-------------|
| `v` | number | Schema version (currently `1`) |
| `type` | string | Always `"task_log"` for task logs |
| `issue` | number | GitHub issue number |
| `taskId` | string | Human-readable task ID (e.g., `"US-003"`) |
| `taskUid` | string | Deterministic task uid (e.g., `"tsk_a1b2c3d4e5f6"`) |
| `status` | string | `"pass"` or `"fail"` |
| `attempt` | number | Attempt number for this task |
| `commit` | string | Git commit hash (empty string if failed) |
| `verify` | object | `{ "passed": [...], "failed": [...] }` — verify command results |
| `search` | object | Optional evidence block: `{ "queries": [...], "filesInspected": [...] }` |
| `discovered` | array | Discovered task objects to auto-enqueue (empty array if none) |
| `ts` | string | ISO 8601 timestamp |

#### Parser Rules

The loop parser uses a **two-phase extraction strategy**:

1. **JSON event extraction (preferred):** Look for a fenced `json` code block under the `### Event JSON` heading. Extract **only** that fenced block. Ignore all other JSON that may appear elsewhere in the comment (e.g., in code examples or inline snippets).

2. **Legacy markdown fallback:** If no `### Event JSON` heading or fenced block is found (e.g., for task logs written before this format was introduced), fall back to parsing the human-readable markdown sections (`**Status:**`, `**Attempt:**`, `**Commit:**`, etc.).

This fallback ensures backward compatibility with existing task log comments that do not include the Event JSON block.

### Execution Hardening Gates

The loop enforces quality in the orchestrator, not the model reply:

1. **Authoritative verification:** `verifyCommands` are executed by the loop script after each task.
2. **Gate mode:** `.issueloop.config.json.execution.gateMode` controls behavior:
   - `warn` (default): gate violations are logged as warnings.
   - `enforce`: gate violations fail the task.
3. **Search evidence gate:** Event JSON should include `search.queries` (minimum count configurable via `execution.searchEvidence.minQueries`).
4. **Placeholder gate:** Added code lines are scanned for placeholder patterns (configurable regex list + excludes).
5. **Retry ceilings:** `maxTaskAttempts` is enforced by the orchestrator.
6. **Stale-plan checkpoint:** repeated retries trigger `debugState.status = "replan_required"` and a `## 🔁 Replan Checkpoint` comment.

---

## Wisp Comments

Wisps (`## 🪶 Wisp`) are **ephemeral** context hints with a time-to-live. They provide short-lived notes that are useful within a narrow window but should not persist as permanent project knowledge.

### Wisp Format
```markdown
## 🪶 Wisp

```json
{"v":1,"type":"wisp","id":"wsp_...","taskUid":"tsk_...","note":"...","expiresAt":"2026-02-10T20:00:00Z","promoted":false}
```
```

### Wisp Lifecycle Rules

1. **Creation:** Posted as a GitHub issue comment during task execution when transient context is worth sharing.
2. **Expiration:** Each wisp has an `expiresAt` timestamp. Expired wisps are **silently ignored** during loop context assembly.
3. **Promotion (the only path to durability):** A wisp becomes durable **only** through explicit promotion:
   - **To Discovery Note:** Convert the wisp into a `## 🔍 Discovery Note` comment and set `promoted: true`.
   - **To New Task:** Enqueue the wisp content as a discovered task in prd.json and set `promoted: true`.
4. **Un-promoted wisps are lost on expiration.** Once a wisp's `expiresAt` timestamp has passed, it is excluded from context assembly and effectively ceases to exist. There is no automatic archival or recovery.

### Why Wisps Expire

Wisps keep the context window lean. Observations that seem important should be promoted to durable artifacts (Discovery Notes or tasks). Everything else is intentionally disposable.

---

## Task Design Rules

### Size: One Context Window
Each task must be completable in a single Claude Code session without running out of context.

**Right-sized:**
- Add one database migration
- Create one API endpoint
- Add one UI component
- Write tests for one module

**Too big (split these):**
- "Build the dashboard"
- "Add authentication"
- "Refactor the API"

### Acceptance Criteria = The Test
Every criterion must be **automatically verifiable**:

✅ Good:
- "npm run typecheck passes"
- "npm run test -- jwt passes"
- "POST /api/users returns 201"
- "File exists: src/lib/jwt.ts"

❌ Bad:
- "Code is clean"
- "Works correctly"
- "Handles errors properly"

### Verify Commands
Every task needs commands that prove success:
```json
"verifyCommands": [
  "npm run typecheck",
  "npm run test -- auth",
  "curl -s localhost:3000/health | jq .status"
]
```

---

## Implementation Rules

### Before Each Task
1. Read `prd.json` for task details and status
2. Read recent task logs from issue comments
3. Check for Discovery Notes with relevant patterns
4. Review git log for recent changes

### During Task Execution
1. Focus ONLY on the current task
2. Follow existing codebase patterns
3. Match acceptance criteria exactly
4. Document anything surprising

### After Each Task
1. Run ALL verify commands
2. Update `passes` status in prd.json
3. Commit with task reference: `feat(US-003): description (#42)`
4. Post task log to issue (pass or fail)
5. Post Discovery Note if patterns found

### On Failure
1. Analyze why verification failed
2. Document in task log with specific fix suggestions
3. Retry up to 3 times automatically
4. After 3 failures: post blocker, add `AI: Blocked` label, stop

---

## Branch & Commit Strategy

### Branch
- One branch per issue: `ai/issue-{number}-{slug}`
- Created at `/il_2_implement start`
- All task commits go here

### Commits
After each passing task:
```bash
git commit -m "feat(US-003): create auth middleware (#42)

- Extracts JWT from Authorization header
- Validates token and attaches user to request

Acceptance criteria: all passing"
```

After prd.json updates:
```bash
git commit -m "chore: update prd.json - US-003 passed (#42)"
```

---

## Discovery Notes

When you discover something future tasks need to know, post immediately:

```markdown
## 🔍 Discovery Note

**Task:** US-003
**Timestamp:** 2024-01-15

### Pattern Discovered
This codebase handles JWT errors by:
- `TokenExpiredError` → 401 "Token expired"
- `JsonWebTokenError` → 401 "Invalid token"

### Files for Reference
- `src/middleware/auth.ts` lines 15-30

### Impacts Tasks
US-004, US-005 should follow this pattern
```

**These notes become memory for future task executions.**

---

## Commands Quick Reference

| Command | Action |
|---------|--------|
| `/il_setup` | Create labels, templates |
| `/il_list` | List open issues |
| `/il_1_plan N` | Load → scope → plan → approve (guided flow) |
| `/il_1_plan N --quick` | Load issue, skip to status check |
| `/il_2_implement` | Execute next failing task |
| `/il_2_implement start` | Create branch, start from US-001 |
| `/il_2_implement loop` | Auto-continue until blocked |
| `/il_3_close` | Generate final report, create PR, archive after merge |

---

## Recovery Scenarios

### Session Ended Mid-Task
```bash
# Check state
cat prd.json | jq '.userStories[] | {id, passes, attempts}'
git log --oneline -5

# Resume
/il_2_implement
```

### Task Keeps Failing
1. Review all task logs in issue
2. Human adds comment with guidance
3. Run `/il_2_implement` to retry with new context

### Need to Skip a Task
```bash
# Manually mark as passed (use sparingly)
jq '.userStories = [.userStories[] | if .id == "US-003" then .passes = true else . end]' \
  prd.json > tmp && mv tmp prd.json
git commit -am "chore: manually skip US-003"
```

---

## Completion Signal

When all `userStories` have `passes: true`:
```
🎉 ALL TASKS PASSING

Entering testing checkpoint...
```

This triggers the **Testing Checkpoint** flow (not immediate closure).

---

## Testing Checkpoint

After all tasks pass, the workflow enters a human-in-the-loop testing phase:

### Flow
```
All tasks pass → Testing Checkpoint → User tests
                                         ↓
                        ┌────────────────┼────────────────┐
                        ↓                ↓                ↓
                    "Works"          "Issue"          "Later"
                        ↓                ↓                ↓
                 /il_3_close       Debug Flow         Pause
                                         ↓
                                   Gather info (3 questions)
                                         ↓
                                   Attempt fix
                                         ↓
                              Fixed? → Re-test (loop)
                              Failed 3x? → AI: Blocked
```

### Testing Questions
1. **Issue type:** Behavior / Error / Missing / Visual / Other
2. **Location:** Dynamically generated from prd.json tasks
3. **Description:** Free-form text describing what happens vs. expected

### Debug State in prd.json
```json
{
  "debugState": {
    "status": "testing|debugging|verified|blocked",
    "debugAttempts": 0,
    "debugHistory": [...]
  }
}
```

### Debug Comment Formats
| Prefix | When | Purpose |
|--------|------|---------|
| `## 🧪 Testing Checkpoint` | All tasks pass | Request manual testing |
| `## 🔧 Debug Session` | User reports issue | Document debug attempt |
| `## ✅ Debug Fix Applied` | Fix works | Document solution |
| `## 🚫 Debug Blocked` | 3 failures | Escalate to human |

### Completion
- User confirms "Works" → `debugState.status = "verified"` → Run `/il_3_close`
- 3 debug failures → `AI: Blocked` label → Human intervention needed

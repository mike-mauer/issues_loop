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
```

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
- Created at `/implement start`
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
| `/issue setup` | Create labels, templates |
| `/issues` | List open issues |
| `/issue N` | Load → scope → plan → approve (guided flow) |
| `/issue N --quick` | Load issue, skip to status check |
| `/implement` | Execute next failing task |
| `/implement start` | Create branch, start from US-001 |
| `/implement loop` | Auto-continue until blocked |
| `/issue close` | Generate final report, create PR |

---

## Recovery Scenarios

### Session Ended Mid-Task
```bash
# Check state
cat prd.json | jq '.userStories[] | {id, passes, attempts}'
git log --oneline -5

# Resume
/implement
```

### Task Keeps Failing
1. Review all task logs in issue
2. Human adds comment with guidance
3. Run `/implement` to retry with new context

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
                 /issue close      Debug Flow         Pause
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
- User confirms "Works" → `debugState.status = "verified"` → Run `/issue close`
- 3 debug failures → `AI: Blocked` label → Human intervention needed

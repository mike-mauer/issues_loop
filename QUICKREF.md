# Quick Reference Card (Ralph Pattern)

## 🏃 Quick Start

```bash
# First time setup
/issue setup

# For each issue:
/issues              # List open issues
/issue 42            # Load → scope → plan → approve (guided flow)
/implement start     # Create branch, begin loop
/issue close         # After testing verified → create PR
```

## 📋 Commands

| Command | Action |
|---------|--------|
| `/issue setup` | Create labels & templates |
| `/issues` | List open issues |
| `/issue N` | Load → scope → plan → approve (full guided flow) |
| `/issue N --quick` | Load issue, skip to status check |
| `/implement` | Execute next failing task |
| `/implement start` | Create branch, start US-001 |
| `/implement loop` | Run task loop in background |
| `/issue close` | Generate report + create PR |
| `/issue close --force` | Skip testing verification |
| `/issue close close` | Report + close issue |

## 🔍 Issue Scoping

When you load an issue, it's scored 0-10 on completeness:

| Score | Action |
|-------|--------|
| 8-10 | Ready → proceed to `/plan` |
| 5-7 | Ask 1-2 questions |
| 0-4 | Ask up to 3 questions |

**Dimensions scored:** What, Where, Why, Scope, Acceptance (2 pts each)

Use `--quick` to skip scoping for issues already in progress.

## 🏷️ Labels

| Label | Meaning |
|-------|---------|
| `AI` | Trigger planning |
| `AI: Planning` | Plan in progress |
| `AI: Approved` | Ready to implement |
| `AI: In Progress` | Being worked on |
| `AI: Testing` | All tasks pass, user testing |
| `AI: Blocked` | Failed 3x, needs human |
| `AI: Review` | PR ready for review |
| `AI: Complete` | Done |

## 💬 Issue Comment Prefixes

| Prefix | Purpose |
|--------|---------|
| `## 📋 Implementation Plan` | The plan |
| `## 📝 Task Log: US-XXX` | Task result (pass/fail) |
| `## 🔍 Discovery Note` | Learnings for future tasks |
| `## 🧾 Compacted Summary` | Periodic context summary |
| `## 🪶 Wisp` | Ephemeral context hint |
| `## 🌐 Browser Verification: US-XXX` | Browser verification evidence for UI tasks |
| `## 🔁 Replan Checkpoint` | Retry-stall checkpoint |
| `## 🧪 Testing Checkpoint` | Request user testing |
| `## 🔧 Debug Session` | Debug attempt |
| `## ✅ Debug Fix Applied` | Debug fix verified |
| `## 🚫 Debug Blocked` | Debug failed 3x |
| `## 📊 Final Report` | Final summary |

## 📄 prd.json Structure

```json
{
  "issueNumber": 42,
  "branchName": "ai/issue-42-feature",
  "memory": {"patterns": []},
  "userStories": [{
    "id": "US-001",
    "title": "Create user schema",
    "requiresBrowserVerification": false,
    "acceptanceCriteria": ["npm run typecheck passes"],
    "verifyCommands": ["npm run typecheck"],
    "passes": false,
    "attempts": 0
  }]
}
```

## 🌿 Branch & Commits

- **Branch**: `ai/issue-42-feature-name`
- **Commit**: `feat(US-001): description (#42)`
- **prd.json update**: `chore: update prd.json - US-001 passed (#42)`

## 🔄 The Loop

```
/implement
    ↓
Read prd.json → Find next task where passes=false
    ↓
Execute task
    ↓
Run verifyCommands
    ↓
Pass? → Update prd.json, commit, post Task Log
Fail? → Post Task Log with analysis, retry (max 3x)
    ↓
All pass? → Testing Checkpoint
    ↓
User tests → "Works" / "Issue" / "Later"
    ↓
Works? → /issue close
Issue? → Debug flow (3 attempts max)
Later? → Pause, resume with /implement
```

## 🛡️ Authoritative Gates

- Task pass/fail is computed by orchestrator verify, not model `<result>` tags.
- `maxTaskAttempts` is enforced from `.issueloop.config.json`.
- Verified task log Event JSON evidence is required by default.
- Event JSON should include `search.queries` evidence.
- Event JSON may include `patterns` for durable memory sync.
- Placeholder patterns in added lines are scanned each iteration.
- UI tasks require browser verification event evidence.
- `execution.gateMode`:
  - `enforce` (default): violations fail the task.
  - `warn`: log violations, continue if verify passes.
- Browser event schema (for required UI tasks):
  - `{"v":1,"type":"browser_verification","issue":42,"taskId":"US-003","taskUid":"tsk_...","tool":"playwright","status":"passed","artifacts":["screenshot:/abs/path.png"],"ts":"<ISO 8601>"}`
- Repeated retries trigger `debugState.status = "replan_required"` and a `## 🔁 Replan Checkpoint` issue comment.

## 🧠 Fresh Context Rule

Each `/implement` = **new session with no memory**

Context comes ONLY from:
- `prd.json` - task definitions, pass/fail
- Issue comments - task logs, learnings
- Git history - committed code

## ✅ Good Acceptance Criteria

```
✓ "npm run typecheck passes"
✓ "npm run test -- auth passes"
✓ "POST /api/users returns 201"
✗ "Code is clean" (not testable)
✗ "Works correctly" (vague)
```

## 🛑 If Blocked (3 failures)

1. Task Log posted with failure analysis
2. Label → `AI: Blocked`
3. Human adds guidance comment
4. Run `/implement` to retry

## 📁 Files

```
.claude/
├── CLAUDE.md              # Project rules
├── rules/
│   ├── github-issue-workflow.md
│   └── planning-guide.md  # Planning methodology
├── commands/
│   ├── issue-setup.md
│   ├── issues.md
│   ├── issue.md           # Scope + plan + approve flow
│   ├── implement.md
│   └── issue-close.md     # Report + PR creation
└── scripts/
    └── implement-loop.sh  # Background task loop script

prd.json                   # Task state (after approval in /issue)
.claude/implement-loop.log # Background loop output (when running)
.claude/implement-loop.pid # Background loop PID (when running)
```

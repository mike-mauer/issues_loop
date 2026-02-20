# il-2-implement — Execute Task Loop (Ralph Pattern)

## Description
Executes the implementation loop following the Ralph pattern. **By default, launches a background loop** that autonomously executes all tasks until complete or blocked. This is Step 2 of the core workflow.

The loop script (`scripts/implement-loop.sh`) provides:
- Fresh context per task (calls the agent CLI for each)
- Automatic retries (up to 3 attempts per task)
- Task logs posted to GitHub issue (with structured JSON event blocks)
- Discovered-task auto-enqueue from task output
- Compaction summaries every N task logs
- Wisp collection for ephemeral context hints
- Stops on completion or blocker

For each task, the loop:
1. Reads `prd.json` for task status
2. Picks the next task where `passes: false`
3. Implements the task
4. Runs authoritative verification commands
5. Updates `passes`/`attempts` status in orchestrator
6. Logs learnings to GitHub issue

## Authoritative Execution Gates

The loop now computes canonical outcome in the orchestrator:

1. `verifyCommands` are executed by the loop runner (not trusted from model self-report).
2. `maxTaskAttempts` is enforced when selecting executable tasks.
3. Event evidence is required: a verified task log Event JSON must exist on GitHub.
4. Event JSON search evidence is validated (`search.queries`, configurable minimum).
5. Added lines are scanned for placeholder patterns.
6. Browser verification is required for UI tasks and hard-fails if missing.
7. `execution.gateMode` controls guard behavior:
   - `enforce` (default): guard violations fail the task.
   - `warn`: guard violations are logged, task can still pass if verify passes.
8. Repeated retries trigger a stale-plan checkpoint (`debugState.status = "replan_required"`).

## Usage
```
il-2-implement              # Create branch if needed + launch background loop
il-2-implement verify       # Re-run verification for current task
```

**There is only one mode: Loop Mode.** This command:
1. Creates the branch from `prd.json` if it doesn't exist
2. Launches `scripts/implement-loop.sh` for fresh context per task

### Escape Hatch (Breaks Fresh Context)
```
il-2-implement interactive-mode    # ESCAPE HATCH - executes in conversation
```

**WARNING:** Interactive mode breaks the Ralph pattern's fresh context principle. You will have memory of previous tasks, which defeats the purpose of the memory system. Only use this for debugging when the loop is failing and you need to step through manually.

## Prerequisites
- Issue loaded (`il-1-plan {number}`)
- Plan approved
- `prd.json` exists in repo root

---

## CRITICAL REQUIREMENTS - NON-NEGOTIABLE

**These actions are REQUIRED for every task. Do NOT skip any item.**

### After EVERY Task (Pass or Fail), You MUST:

- [ ] **Run local checks when useful** - Orchestrator still runs authoritative verify suite
- [ ] **Do NOT mutate pass/fail in prd.json manually** - Loop updates `passes/attempts/lastAttempt` authoritatively
- [ ] **Commit changes** - Implementation commit (if passed) + prd.json commit
- [ ] **Push to remote** - `git push` after commits
- [ ] **MUST post task log to GitHub** - Use `gh issue comment` with the `## 📝 Task Log: US-XXX` format
- [ ] **MUST post discovery note if patterns found** - If you learn something future tasks need, post `## 🔍 Discovery Note`

### GitHub Posting is MANDATORY

**Task logs MUST be posted to the GitHub issue** after every task attempt. This is not optional.

Format: `gh issue comment $ISSUE_NUMBER --body "## 📝 Task Log: US-XXX ..."`

**Discovery notes MUST be posted** when you discover patterns, gotchas, or learnings that future tasks should know about. This is how the Ralph pattern maintains memory across sessions.

Format: `gh issue comment $ISSUE_NUMBER --body "## 🔍 Discovery Note ..."`

### JSON Event Block (Required in Every Task Log)

Every task log comment **must** include an `### Event JSON` section containing a fenced json code block with a compact JSON event object. This enables structured parsing by the loop.

**Format:**
```markdown
### Event JSON
```json
{"v":1,"type":"task_log","issue":42,"taskId":"US-003","taskUid":"tsk_a1b2c3d4e5f6","status":"pass","attempt":2,"commit":"abc1234","verify":{"passed":["cmd1"],"failed":[]},"search":{"queries":["rg -n \"auth\" src","rg -n \"token\" src"],"filesInspected":["src/auth.ts"]},"discovered":[],"ts":"2024-01-15T14:32:00Z"}
```
```

Optional reusable pattern memory can be included:
```json
"patterns":[{"statement":"When changing X, also update Y","scope":"src/module","files":["src/module/a.ts"],"confidence":0.9}]
```

**Schema fields:** `v` (version, always 1), `type` (always "task_log"), `issue`, `taskId`, `taskUid`, `status` ("pass"/"fail"), `attempt`, `commit` (hash or empty string), `verify` (passed/failed arrays), `search` (optional object with `queries` + `filesInspected`), `patterns` (optional reusable pattern array), `discovered` (array of discovered task objects for auto-enqueue), `ts` (ISO 8601 timestamp).

**Parser rule:** The loop extracts **only** fenced json blocks under `### Event JSON` headings. All other JSON in comments is ignored. If no Event JSON block is found, the loop falls back to legacy markdown parsing for backward compatibility.

### Browser Verification Event (Required for UI Tasks)

For tasks that require browser verification, post an additional comment:

```markdown
## 🌐 Browser Verification: US-003

### Browser Event JSON
```json
{"v":1,"type":"browser_verification","issue":42,"taskId":"US-003","taskUid":"tsk_a1b2c3d4e5f6","tool":"playwright","status":"passed","artifacts":["screenshot:/abs/path.png"],"ts":"2026-02-20T12:00:00Z"}
```
```

Rules:
- `type` must be `browser_verification`
- `taskId` + `taskUid` must match the task log event
- `status` must be `passed`
- `tool` must be in configured allow-list (`playwright`, `dev-browser` by default)

### Discovered-Task Output for Auto-Enqueue

When a task discovers work that should be added to the plan, include it in the JSON event's `discovered` array:

```json
"discovered": [
  {
    "title": "Fix edge case in auth middleware",
    "description": "Handle expired refresh tokens gracefully",
    "acceptanceCriteria": ["Expired refresh token returns 401"],
    "verifyCommands": ["npm run test -- auth"],
    "dependsOn": []
  }
]
```

The loop will automatically:
- Deduplicate by fingerprint hash (title + description + acceptanceCriteria + parent uid)
- Generate a uid with `discoveredFrom` set to the parent task's uid
- Assign priority = parent priority + 1 and `dependsOn` = [parent id]
- Append to prd.json and commit the state update

### Compaction Summaries

The loop tracks a compaction counter in `prd.json.compaction.taskLogCountSinceLastSummary`. After every N task logs (default 5, configured via `summaryEveryNTaskLogs`), a `## 🧾 Compacted Summary` comment is posted to the issue containing:
- Covered task UIDs and attempt counts
- Canonical decisions and patterns from discovery notes
- Open risks (tasks still failing)
- A `supersedes` pointer to the previous compaction summary (or "none")

After posting, the counter resets to 0. If the post fails, the counter is retained for retry on the next cycle.

### Wisp Collection and Promotion

**Wisps** (`## 🪶 Wisp`) are ephemeral context hints with an expiration timestamp. The loop:
- Collects active (non-expired, non-promoted) wisps during context assembly
- Includes their notes as supplementary context for the current task
- Silently ignores expired or promoted wisps

**Wisp promotion** (the only path to durability):
- **To Discovery Note:** Converts the wisp into a `## 🔍 Discovery Note` comment
- **To New Task:** Enqueues the wisp content as a discovered task in prd.json
- In both cases, the original wisp comment is updated with `promoted: true`

Un-promoted wisps are lost on expiration — there is no automatic archival.

### Enforcement

If you complete a task without posting to GitHub, the task is NOT complete. Go back and post the required comments before proceeding.

---

## MODE SELECTION - READ THIS FIRST

**You MUST launch the background script.** There is no interactive mode by default.

### Argument Check (Do This Immediately)

| Argument | Action | Go To |
|----------|--------|-------|
| (none) | Create branch if needed + launch script | → "Loop Mode" section |
| `verify` | Re-run verification commands only | → "Step 5: Run Verification" |
| `interactive-mode` | ESCAPE HATCH - breaks fresh context | → "Interactive Mode" section |

### Why No Default Interactive Mode?

The Ralph pattern requires **fresh context per task**. When you execute tasks in a conversation:
- You have memory of previous tasks (violates fresh context)
- You don't need to read GitHub comments (bypasses the memory system)
- The whole point of task logs and discovery notes is lost

The background script enforces fresh context because each task runs as a separate agent invocation with zero memory of previous tasks.

**If you need to debug:** Use `il-2-implement interactive-mode` but understand you're breaking the pattern.

---

## Step 0: Prerequisites

Before proceeding, validate the environment:

```bash
# 1. Check gh CLI is installed
which gh || { echo "❌ GitHub CLI (gh) not found. Install with: brew install gh"; exit 1; }

# 2. Check gh is authenticated
gh auth status || { echo "❌ GitHub CLI not authenticated. Run: gh auth login"; exit 1; }

# 3. Check we're in a git repository
git rev-parse --git-dir > /dev/null 2>&1 || { echo "❌ Not in a git repository"; exit 1; }

# 4. Check we have a GitHub remote
git remote get-url origin 2>/dev/null | grep -q github || { echo "❌ No GitHub remote found"; exit 1; }

# 5. Check jq is installed
which jq || { echo "❌ jq not found. Install with: brew install jq"; exit 1; }

# 6. Check prd.json exists
[ -f prd.json ] || { echo "❌ prd.json not found. Run il-1-plan N first to create a plan."; exit 1; }
```

If any prerequisite fails, stop and inform the user how to fix it.

---

## Step 0b: Check Loop Status and Determine Flow

**IMPORTANT:** This step determines which section to execute next.

### 1. Check for running loop
```bash
if [ -f .implement-loop.pid ]; then
  PID=$(cat .implement-loop.pid)
  if kill -0 $PID 2>/dev/null; then
    echo "Background loop is running (PID: $PID)"
    echo "Monitor: tail -f .implement-loop.log"
    # STOP - loop is handling implementation, do not proceed
  fi
fi
```

### 2. Check prd.json state
- If `debugState.status == "testing"` → go to "Testing Checkpoint" section
- If all tasks pass but no debugState → go to "Testing Checkpoint" section
- Otherwise → continue based on mode:

### 3. Route to correct section based on argument

| Mode | Determined By | Go To Section |
|------|---------------|---------------|
| **Loop Mode** | No argument, `loop`, or `start` | "Loop Mode" (below) |
| **Interactive Mode** | `interactive-mode` | "Implementation Loop" |
| **Verify Mode** | `verify` | "Step 5: Run Verification" |

**REMINDER:** If you are in Loop Mode (default), you MUST skip the "Implementation Loop" section and go directly to "Loop Mode" to launch the background script.

---

## The Fresh Context Principle

### Each il-2-implement = New Session
This command is designed to work **without memory** of previous runs. Context comes only from:

| Source | Contains |
|--------|----------|
| `prd.json` | Task definitions, pass/fail status, attempt counts, compaction state |
| Git history | What code was written, commit messages |
| Issue comments | Task logs (with JSON events), learnings, discovered patterns |
| Compacted summaries | Periodic summaries of recent task logs (replaces full history) |
| Active wisps | Non-expired ephemeral context hints (ignored after expiry) |

### Why This Matters
- Prevents context pollution from long sessions
- Forces tasks to be self-contained
- Learnings must be explicitly written down (not assumed)
- Each attempt starts fresh (can recover from bad states)

---

## Loop Mode (DEFAULT - Check This First)

**If you are running `il-2-implement` with no arguments, you MUST follow this section.**

You MUST launch the background script. Do NOT execute tasks interactively.

### Step L1: Create Branch If Needed

```bash
# Read branch name from prd.json
BRANCH=$(jq -r '.branchName' prd.json)

# Check if branch exists locally or on remote
if ! git show-ref --verify --quiet "refs/heads/$BRANCH" && \
   ! git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
  # Create and checkout branch
  git checkout -b "$BRANCH"
  git push -u origin "$BRANCH"
  echo "✅ Created branch: $BRANCH"
else
  # Switch to existing branch
  git checkout "$BRANCH"
  echo "✅ On branch: $BRANCH"
fi
```

### Step L2: Verify Script Exists

```bash
SKILL_DIR="$(dirname "$(dirname "$0")")"  # Resolve skill root
if [ ! -f "$SKILL_DIR/scripts/implement-loop.sh" ]; then
  echo "❌ Background script not found: scripts/implement-loop.sh"
  echo "This file is required for the default il-2-implement behavior."
  exit 1
fi
```

### Step L3: Launch Background Script

```bash
# Make script executable if needed
chmod +x "$SKILL_DIR/scripts/implement-loop.sh"

# Run in background, output to log
nohup "$SKILL_DIR/scripts/implement-loop.sh" > /dev/null 2>&1 &
LOOP_PID=$!
echo $LOOP_PID > .implement-loop.pid
```

### Step L4: Inform User and STOP

Output this message and then STOP (do not continue to Implementation Loop):

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔄 Implementation loop started (PID: $LOOP_PID)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

The loop runs in the background until:
  ✅ All tasks pass → testing checkpoint
  ⛔ A task is blocked → needs your input
  ⚠️  Max iterations → safety stop

Monitor progress:
  tail -f .implement-loop.log

Stop the loop:
  kill $(cat .implement-loop.pid)

When done, run il-2-implement to continue.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**STOP HERE if in Loop Mode.** Do not proceed to Implementation Loop.

---

## Interactive Mode (ESCAPE HATCH ONLY)

**WARNING: This mode breaks the Ralph pattern's fresh context principle.**

Only proceed to this section if the user explicitly specified `interactive-mode`.

### Why This Is Problematic

When you execute tasks in a conversation:
1. **You have memory** - You remember previous tasks, violating fresh context
2. **You skip the memory system** - You don't need to read GitHub comments
3. **Future sessions won't benefit** - Learnings stay in your head, not in comments

### When To Use This

- The background script is failing and you need to debug
- You need to step through a specific task manually
- You understand and accept you're breaking the pattern

### Requirements Still Apply

Even in interactive mode, you MUST:
- Follow the CRITICAL REQUIREMENTS section
- Complete the POST-TASK CHECKLIST after each task
- Post task logs to GitHub with `gh issue comment`
- Post discovery notes when patterns are found

**The GitHub posting is even MORE important here** because it's the only way learnings from this session will persist for future sessions.

### Step 1: Load Context

```bash
# Read prd.json
PRD=$(cat prd.json)

# Get issue number
ISSUE_NUMBER=$(echo $PRD | jq -r '.issueNumber')

# Get branch name
BRANCH=$(echo $PRD | jq -r '.branchName')

# Ensure on correct branch
git checkout $BRANCH || git checkout -b $BRANCH
```

### Step 2: Read Learnings from Issue

```bash
# Fetch issue comments for context
gh issue view $ISSUE_NUMBER --json comments --jq '.comments[].body' | \
  grep -A 100 "## 🔍 Learnings" | head -50
```

Display any discovered patterns or gotchas from previous attempts.

### Step 3: Select Next Task

```javascript
// Find first task where passes === false and dependencies are met
const nextTask = prd.userStories.find(task => {
  if (task.passes) return false;
  const depsPass = task.dependsOn.every(depId =>
    prd.userStories.find(t => t.id === depId)?.passes
  );
  return depsPass;
});
```

Display:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎯 Task: US-003 - Create auth middleware
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Attempt: 2 (previous attempt failed verification)
Depends on: US-001 ✅, US-002 ✅

📄 Files to modify:
   - src/middleware/auth.ts (create)
   - src/app.ts (modify)

📋 Description:
   Create authentication middleware that verifies JWT tokens
   from Authorization header and attaches user to request.

✅ Acceptance Criteria (The Test):
   1. Middleware extracts token from "Bearer <token>" header
   2. Valid token: attaches decoded user to req.user
   3. Invalid/missing token: returns 401 Unauthorized
   4. npm run typecheck passes
   5. npm run test -- auth.middleware passes

🔧 Verify Commands:
   npm run typecheck
   npm run test -- auth.middleware

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Step 4: Execute Implementation

Implement the task following the description exactly. Key rules:

1. **Focus only on this task** - Don't fix unrelated issues
2. **Follow existing patterns** - Check similar files first
3. **Match the acceptance criteria** - That's the definition of done
4. **Document surprises** - Anything unexpected goes in learnings

### Step 5: Run Verification

```bash
# Run task-specific verify commands
npm run typecheck
npm run test -- auth.middleware

# Capture results
if [ $? -eq 0 ]; then
  VERIFY_STATUS="pass"
else
  VERIFY_STATUS="fail"
fi
```

### Step 6: Update prd.json

```bash
# Update task status in prd.json
jq --arg id "US-003" \
   --arg status "$VERIFY_STATUS" \
   --arg time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '.userStories = [.userStories[] |
     if .id == $id then
       .passes = ($status == "pass") |
       .attempts += 1 |
       .lastAttempt = $time
     else . end]' prd.json > prd.json.tmp && mv prd.json.tmp prd.json

# Commit prd.json update
git add prd.json
git commit -m "chore: update prd.json - US-003 $VERIFY_STATUS (#$ISSUE_NUMBER)"
git push
```

### Step 7: Commit Implementation (if passed)

```bash
# Stage changed files
git add src/middleware/auth.ts src/app.ts

# Commit with task reference
git commit -m "feat(US-003): create auth middleware (#$ISSUE_NUMBER)

- Extracts JWT from Authorization header
- Validates token and attaches user to request
- Returns 401 for invalid/missing tokens

Acceptance criteria: all passing"

git push
```

---

### POST-TASK CHECKLIST - STOP AND VERIFY

**STOP. Do not proceed until ALL items are completed.**

Before moving to the next task, verify you have done ALL of the following:

| # | Item | Required | Done? |
|---|------|----------|-------|
| 1 | **Run verify commands** | All commands in `verifyCommands` executed | ☐ |
| 2 | **Update prd.json** | `passes`, `attempts`, `lastAttempt` updated | ☐ |
| 3 | **Commit implementation** | Code changes committed with task reference | ☐ |
| 4 | **Commit prd.json** | Status update committed | ☐ |
| 5 | **Push to remote** | `git push` completed | ☐ |
| 6 | **Post task log to GitHub** | `gh issue comment` with `## 📝 Task Log` posted | ☐ |
| 7 | **Include JSON event block** | Task log contains `### Event JSON` section with fenced json block | ☐ |
| 8 | **Post discovery note** | If patterns found, `## 🔍 Discovery Note` posted | ☐ |

**If you skip the GitHub posting steps, the task is NOT complete.**

The GitHub comments are the memory system - without them, future sessions won't know what was learned.

---

### Step 8: Post Task Log to Issue

#### If PASSED:

```markdown
## 📝 Task Log: US-003 - Create auth middleware

**Status:** ✅ Passed
**Attempt:** 2
**Timestamp:** 2024-01-15 14:32 UTC
**Commit:** [abc1234](link)

### Summary
Created JWT authentication middleware with token extraction and validation.

### Changes Made
- `src/middleware/auth.ts` - New file: extractToken, verifyAndAttach functions
- `src/app.ts` - Added auth middleware to protected routes
- `src/types/express.d.ts` - Extended Request type with user property

### Verification Results
```
✓ npm run typecheck (0 errors)
✓ npm run test -- auth.middleware (3 tests passing)
```

### Learnings
- Express Request extension requires `declare global` in .d.ts file
- Existing pattern: middleware functions in src/middleware/ export as default

### Event JSON
```json
{"v":1,"type":"task_log","issue":42,"taskId":"US-003","taskUid":"tsk_a1b2c3d4e5f6","status":"pass","attempt":2,"commit":"abc1234","verify":{"passed":["npm run typecheck","npm run test -- auth.middleware"],"failed":[]},"discovered":[],"ts":"2024-01-15T14:32:00Z"}
```
```

#### If FAILED:

```markdown
## 📝 Task Log: US-003 - Create auth middleware

**Status:** ❌ Failed
**Attempt:** 2
**Timestamp:** 2024-01-15 14:32 UTC

### Summary
Implementation complete but verification failed.

### Changes Made
- `src/middleware/auth.ts` - Created middleware
- `src/app.ts` - Added to routes

### Verification Results
```
✓ npm run typecheck (0 errors)
✗ npm run test -- auth.middleware
  FAIL: "should return 401 for expired token"
  Expected: 401, Received: 500
```

### Failure Analysis
The verifyToken function throws an error for expired tokens instead of
returning null. Need to wrap in try-catch and handle TokenExpiredError.

### Learnings
- jsonwebtoken throws TokenExpiredError for expired tokens
- Need try-catch wrapper, not just null check

### Next Attempt Should
1. Wrap verifyToken in try-catch
2. Handle TokenExpiredError specifically
3. Return 401 with "Token expired" message

### Event JSON
```json
{"v":1,"type":"task_log","issue":42,"taskId":"US-003","taskUid":"tsk_a1b2c3d4e5f6","status":"fail","attempt":2,"commit":"","verify":{"passed":["npm run typecheck"],"failed":["npm run test -- auth.middleware"]},"discovered":[],"ts":"2024-01-15T14:32:00Z"}
```
```

### Step 9: Post Learnings (If New Patterns Discovered)

If you discover something that future tasks should know:

```markdown
## 🔍 Discovery Note

**Task:** US-003
**Timestamp:** 2024-01-15 14:35 UTC

### Pattern Discovered
JWT error handling in this codebase:
- `TokenExpiredError` → 401 with "Token expired"
- `JsonWebTokenError` → 401 with "Invalid token"
- Other errors → 500 (let error handler catch)

### Files for Reference
- `src/middleware/auth.ts` - Example implementation
- `src/utils/errors.ts` - Error type definitions

### Impact on Future Tasks
US-004 (registration) and US-005 (login) should follow this pattern.
```

### Step 9b: Pattern Memory Auto-Sync

When Event JSON includes `patterns`, the loop:
- Ingests patterns into `prd.json.memory.patterns` (deduped by `statement + scope`)
- Auto-syncs high-confidence patterns into nearby existing `AGENTS.md` / `CLAUDE.md`
- Writes into managed markers:
  - `<!-- issues-loop:auto-patterns:start -->`
  - `<!-- issues-loop:auto-patterns:end -->`

No manual pattern comment maintenance is required.

---

## Loop Mode Reference

**See "Loop Mode (DEFAULT - Check This First)" section above for launch instructions.**

This section provides additional reference information about how the background script works.

### When User Returns After Loop

When user runs `il-2-implement` after loop completes:
- Check if `debugState.status == "testing"` or all tasks pass
- If yes, enter testing checkpoint flow
- If blocked, show status and ask for guidance

### How the Background Script Works

The script `scripts/implement-loop.sh` (with helpers from `scripts/implement-loop-lib.sh`):
1. Initializes missing prd.json fields (formula, compaction, uid, discoveredFrom) for backward compatibility
2. Reads prd.json for task definitions and status
3. Loops through tasks, calling the agent CLI with fresh context for each
4. Each agent invocation:
   - Reads prd.json for task details
   - Checks git log and issue comments for context
   - Collects active (non-expired) wisps for ephemeral context hints
   - Extracts recent JSON events from task log comments
   - Includes latest compacted summary (if any) as primary historical context
   - Implements the task
   - Runs verification commands
   - Updates prd.json and commits
   - Posts task log to GitHub issue (with `### Event JSON` fenced block)
5. After each task log post:
   - Auto-enqueues any discovered tasks from the task output into prd.json
   - Increments the compaction counter; posts `## 🧾 Compacted Summary` every N task logs (default 5)
6. Exits when: all pass, blocked, or max iterations

### Log Output Example

The background loop writes output like this to `.implement-loop.log`:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎯 Task: US-001 - Create user schema
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   Status:   ⏳ Attempt 1
   Iteration: 1 of 20

Gathering context...
Running agent on US-001...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ US-001 passed! Moving to next task...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎯 Task: US-002 - Implement JWT utilities
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   Status:   ⏳ Attempt 1
   ...
```

---

## Handling Failures

### Automatic Retry (up to 3 attempts)
- Re-read failure analysis from previous log
- Apply suggested fixes
- Run verification again

### After 3 Failures
- Post blocker comment
- Update label to `AI: Blocked`
- Stop loop, wait for human input

### Human Intervention
After human provides guidance in issue comments:
1. Run `il-2-implement` to retry the blocked task
2. Agent reads the guidance from comments
3. Applies the suggested approach

---

## State Recovery

If a session ends mid-task:

```bash
# Check current state
cat prd.json | jq '.userStories[] | select(.passes == false) | {id, title, attempts}'

# See what was committed
git log --oneline -5

# Resume from where we left off
il-2-implement
```

The fresh context approach means no state is lost - everything is in git and GitHub.

---

## Output Signals

When ALL tasks pass:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎉 All tasks passing!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Progress: 6/6 tasks complete

Let's verify everything works as expected...
```

---

## Testing Checkpoint

When all tasks pass, the workflow enters a **testing checkpoint** before closing. This ensures the user has verified the implementation works as expected.

### Step 1: Update Labels

```bash
gh issue edit $ISSUE_NUMBER \
  --remove-label "AI: In Progress" \
  --add-label "AI: Testing"
```

### Step 2: Post Testing Checkpoint Comment

```markdown
## 🧪 Testing Checkpoint

All **6 tasks** have passed automated verification.

**Please test the implementation manually:**
1. Pull the branch: `git checkout ai/issue-42-feature`
2. Test the functionality described in the issue
3. Verify it works as expected

When ready, respond with your testing results.
```

### Step 3: Ask User for Testing Results

Prompt the user with these options:

**Question:** "How did testing go?"

| Option | Description |
|--------|-------------|
| **Works** | Everything works as expected |
| **Found issue** | Something doesn't work correctly |
| **Need more time** | I'll test later |

### Step 4: Handle Response

#### If "Works":
```bash
# Update prd.json with verified status
jq '.debugState = {"status": "verified", "debugAttempts": 0, "debugHistory": []}' \
  prd.json > prd.json.tmp && mv prd.json.tmp prd.json

git add prd.json
git commit -m "chore: mark testing as verified (#$ISSUE_NUMBER)"
git push
```

Output:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Testing verified!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Great news - implementation confirmed working.

Run il-3-close to:
  📊 Generate summary report
  🔀 Create Pull Request
  🚀 Prepare for merge
```

#### If "Need more time":
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⏸️  Testing paused
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Take your time. When ready:
  il-2-implement     → Resume testing checkpoint
```

Update prd.json:
```bash
jq '.debugState = {"status": "testing", "debugAttempts": 0, "debugHistory": []}' \
  prd.json > prd.json.tmp && mv prd.json.tmp prd.json
```

#### If "Found issue":
Proceed to **Debug Flow** (below).

---

## Debug Flow

When the user reports an issue during testing, gather structured information and attempt a fix.

### Step 1: Gather Debug Information (3 Questions)

Prompt the user to collect:

#### Q1: Issue Type
**Question:** "What kind of issue did you find?"

| Option | Description |
|--------|-------------|
| **Behavior** | Something doesn't work as expected |
| **Error/crash** | Getting an error message or crash |
| **Missing** | Expected functionality is missing |
| **Visual** | UI/display issue |

#### Q2: Location (Dynamic from prd.json)
**Question:** "Where is the issue?"

Options are generated from `prd.json.userStories`:
| Option | Description |
|--------|-------------|
| **US-001: Create user schema** | Issue related to this task |
| **US-002: Implement JWT** | Issue related to this task |
| ... | ... |
| **Something else** | Issue in different area |

#### Q3: Description
**Question:** "Describe what happens vs. what you expected"

This is a free-form text input.

### Step 2: Post Debug Session Comment

```markdown
## 🔧 Debug Session

**Attempt:** 1
**Timestamp:** 2024-01-15 15:30 UTC

### Issue Reported
- **Type:** Behavior
- **Location:** US-005 (Add login endpoint)
- **Description:** Login button doesn't respond when clicked

### Analysis
[AI analysis of the issue]

### Attempted Fix
[Description of fix being attempted]

### Files Modified
- `src/components/LoginForm.tsx` - Added onClick handler
```

### Step 3: Attempt Fix

1. Analyze the reported issue
2. Identify root cause
3. Implement fix
4. Run verification commands
5. Update prd.json debugState

```bash
# Update debug state
jq --arg attempt "1" \
   --arg type "behavior" \
   --arg location "US-005" \
   --arg desc "Login button doesn't respond" \
   '.debugState.debugAttempts = ($attempt | tonumber) |
    .debugState.status = "debugging" |
    .debugState.debugHistory += [{
      "attempt": ($attempt | tonumber),
      "type": $type,
      "location": $location,
      "description": $desc,
      "timestamp": (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
    }]' prd.json > prd.json.tmp && mv prd.json.tmp prd.json
```

### Step 4: Commit Fix

```bash
git add -A
git commit -m "fix: debug session 1 - login button handler (#$ISSUE_NUMBER)

Issue: Login button doesn't respond when clicked
Fix: Added onClick handler binding to LoginForm component"
git push
```

### Step 5: Return to Testing Checkpoint

After applying fix, loop back to testing:

```
🔧 Debug fix applied (attempt 1)

Please test again to verify the fix works.
```

Then re-run the testing results prompt from Testing Checkpoint Step 3.

### Step 6: Post Success or Escalate

#### If fix works (user selects "Works"):

```markdown
## ✅ Debug Fix Applied

**Session:** 1
**Timestamp:** 2024-01-15 15:45 UTC

### Issue
Login button doesn't respond when clicked

### Root Cause
Missing onClick handler binding in LoginForm component

### Fix Applied
Added arrow function binding: `onClick={() => handleLogin()}`

### Verification
User confirmed fix resolves the issue
```

Update status to verified and proceed to `il-3-close`.

#### If 3 debug attempts fail:

```markdown
## 🚫 Debug Blocked

**Attempts:** 3
**Timestamp:** 2024-01-15 16:00 UTC

### Issue Summary
Login button doesn't respond when clicked

### Attempts Made
1. Added onClick handler binding - still broken
2. Checked event propagation - not the cause
3. Verified state updates - working correctly

### Analysis
Unable to reproduce or resolve the issue after 3 attempts.
May require human investigation of browser console or environment.

### Recommended Next Steps
1. Check browser console for JavaScript errors
2. Verify React DevTools shows component state
3. Test in incognito mode to rule out extensions
```

```bash
# Update labels
gh issue edit $ISSUE_NUMBER \
  --remove-label "AI: Testing" \
  --add-label "AI: Blocked"

# Update prd.json
jq '.debugState.status = "blocked"' prd.json > prd.json.tmp && mv prd.json.tmp prd.json
```

Output:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⛔ Debug blocked
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

After 3 attempts, unable to resolve the issue.
See debug notes in the issue comments.

Your help needed - add guidance to the issue, then run il-2-implement.
```

---

## prd.json Debug State Extension

When debug flow is active, prd.json includes:

```json
{
  "project": "feature-name",
  "issueNumber": 42,
  "userStories": [...],
  "debugState": {
    "status": "testing|debugging|verified|blocked",
    "debugAttempts": 0,
    "debugHistory": [
      {
        "attempt": 1,
        "type": "behavior",
        "location": "US-005",
        "description": "Login button doesn't respond",
        "timestamp": "2024-01-15T15:30:00Z",
        "fixed": true
      }
    ]
  }
}
```

### Debug Status Values

| Status | Meaning |
|--------|---------|
| `testing` | Waiting for user to test |
| `debugging` | Actively working on reported issue |
| `verified` | User confirmed implementation works |
| `blocked` | 3 debug attempts failed, needs human |

---

## Resuming After Testing Pause

When `il-2-implement` is run and `debugState.status` is `testing`:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔄 Resuming testing checkpoint
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

All tasks are passing. Let's verify everything works...
```

Then proceed directly to Testing Checkpoint Step 3 (prompt the user for testing results).

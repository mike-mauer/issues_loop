# /implement - Execute Task Loop (Ralph Pattern)

## Description
Executes the implementation loop following the Ralph pattern. **By default, launches a background loop** that autonomously executes all tasks until complete or blocked.

The loop script (`.claude/scripts/implement-loop.sh`) provides:
- Fresh context per task (calls Claude CLI for each)
- Automatic retries (up to 3 attempts per task)
- Task logs posted to GitHub issue
- Stops on completion or blocker

For each task, the loop:
1. Reads `prd.json` for task status
2. Picks the next task where `passes: false`
3. Implements the task
4. Runs verification commands
5. Updates `passes` status
6. Logs learnings to GitHub issue

## Usage
```
/implement              # Launch background loop (DEFAULT - autonomous)
/implement start        # Create branch + start background loop
/implement single       # Execute ONE task interactively (not loop)
/implement task US-003  # Jump to specific task (interactive)
/implement verify       # Re-run verification for current task
```

**Default behavior is loop mode** - launches `.claude/scripts/implement-loop.sh` in background for autonomous task execution. Use `/implement single` if you need interactive mode for debugging.

## Prerequisites
- Issue loaded (`/issue {number}`)
- Plan approved (`/plan approve`)
- `prd.json` exists in repo root

---

## 🚨 CRITICAL REQUIREMENTS - NON-NEGOTIABLE

**These actions are REQUIRED for every task. Do NOT skip any item.**

### After EVERY Task (Pass or Fail), You MUST:

- [ ] **Run ALL verify commands** - Execute every command in `verifyCommands`
- [ ] **Update prd.json** - Set `passes`, increment `attempts`, set `lastAttempt`
- [ ] **Commit changes** - Implementation commit (if passed) + prd.json commit
- [ ] **Push to remote** - `git push` after commits
- [ ] **MUST post task log to GitHub** - Use `gh issue comment` with the `## 📝 Task Log: US-XXX` format
- [ ] **MUST post discovery note if patterns found** - If you learn something future tasks need, post `## 🔍 Discovery Note`

### GitHub Posting is MANDATORY

**Task logs MUST be posted to the GitHub issue** after every task attempt. This is not optional.

Format: `gh issue comment $ISSUE_NUMBER --body "## 📝 Task Log: US-XXX ..."`

**Discovery notes MUST be posted** when you discover patterns, gotchas, or learnings that future tasks should know about. This is how the Ralph pattern maintains memory across sessions.

Format: `gh issue comment $ISSUE_NUMBER --body "## 🔍 Discovery Note ..."`

### Enforcement

If you complete a task without posting to GitHub, the task is NOT complete. Go back and post the required comments before proceeding.

---

## ⚠️ MODE SELECTION - READ THIS FIRST

**You MUST launch the background script** unless the user explicitly specified `single` or `task US-XXX`.

### Argument Check (Do This Immediately)

Parse `$ARGUMENTS` and take the corresponding action:

| Argument | Action | Go To |
|----------|--------|-------|
| (none) | **MUST launch background script** | → "Loop Mode" section |
| `loop` | **MUST launch background script** | → "Loop Mode" section |
| `start` | Create branch, then **MUST launch background script** | → "Loop Mode" section |
| `single` | Execute ONE task interactively | → "Implementation Loop" section |
| `task US-XXX` | Jump to specific task interactively | → "Implementation Loop" section |
| `verify` | Re-run verification commands only | → "Step 5: Run Verification" |

### Default Behavior Enforcement

**STOP.** Before proceeding, confirm which mode you are in:

- **If argument is empty, `loop`, or `start`:** You MUST go directly to the "Loop Mode" section and launch `.claude/scripts/implement-loop.sh`. Do NOT execute tasks interactively.
- **If argument is `single` or `task`:** You may execute tasks interactively in this conversation.
- **If unsure:** Default to Loop Mode (launch the script).

This is not optional. The default `/implement` command REQUIRES launching the background script.

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
[ -f prd.json ] || { echo "❌ prd.json not found. Run /issue N first to create a plan."; exit 1; }
```

If any prerequisite fails, stop and inform the user how to fix it.

---

## Step 0b: Check Loop Status and Determine Flow

**IMPORTANT:** This step determines which section to execute next.

### 1. Check for running loop
```bash
if [ -f .claude/implement-loop.pid ]; then
  PID=$(cat .claude/implement-loop.pid)
  if kill -0 $PID 2>/dev/null; then
    echo "Background loop is running (PID: $PID)"
    echo "Monitor: tail -f .claude/implement-loop.log"
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
| **Interactive Mode** | `single` or `task US-XXX` | "Implementation Loop" |
| **Verify Mode** | `verify` | "Step 5: Run Verification" |

**REMINDER:** If you are in Loop Mode (default), you MUST skip the "Implementation Loop" section and go directly to "Loop Mode" to launch the background script.

---

## The Fresh Context Principle

### Each /implement = New Session
This command is designed to work **without memory** of previous runs. Context comes only from:

| Source | Contains |
|--------|----------|
| `prd.json` | Task definitions, pass/fail status, attempt counts |
| Git history | What code was written, commit messages |
| Issue comments | Task logs, learnings, discovered patterns |

### Why This Matters
- Prevents context pollution from long sessions
- Forces tasks to be self-contained
- Learnings must be explicitly written down (not assumed)
- Each attempt starts fresh (can recover from bad states)

---

## Loop Mode (DEFAULT - Check This First)

**If you are running `/implement` with no arguments, `loop`, or `start`, you MUST follow this section.**

You MUST launch the background script. Do NOT execute tasks interactively.

### Step L1: Verify Script Exists

```bash
if [ ! -f .claude/scripts/implement-loop.sh ]; then
  echo "❌ Background script not found: .claude/scripts/implement-loop.sh"
  echo "This file is required for the default /implement behavior."
  exit 1
fi
```

### Step L2: Launch Background Script

```bash
# Make script executable if needed
chmod +x .claude/scripts/implement-loop.sh

# Run in background, output to log
nohup .claude/scripts/implement-loop.sh > /dev/null 2>&1 &
LOOP_PID=$!
echo $LOOP_PID > .claude/implement-loop.pid
```

### Step L3: Inform User and STOP

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
  tail -f .claude/implement-loop.log

Stop the loop:
  kill $(cat .claude/implement-loop.pid)

When done, run /implement to continue.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**STOP HERE if in Loop Mode.** Do not proceed to Implementation Loop.

---

## Implementation Loop (Interactive Mode Only)

**Only proceed to this section if the user specified `single` or `task US-XXX`.**

If you are in Loop Mode (default), you should have already launched the background script and stopped. Do NOT execute tasks interactively unless explicitly requested.

### ⚠️ Interactive Mode Still Requires GitHub Posting

**Using `single` or `task` does NOT skip the CRITICAL REQUIREMENTS.**

Even in interactive mode, you MUST:
- Follow the 🚨 CRITICAL REQUIREMENTS section (see above)
- Complete the 🛑 POST-TASK CHECKLIST after each task
- Post task logs to GitHub with `gh issue comment`
- Post discovery notes when patterns are found

The only difference is that YOU execute the task in this conversation instead of the background script. All other requirements remain the same.

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

### 🛑 POST-TASK CHECKLIST - STOP AND VERIFY

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
| 7 | **Post discovery note** | If patterns found, `## 🔍 Discovery Note` posted | ☐ |

**⚠️ If you skip the GitHub posting steps, the task is NOT complete.**

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

### Step 9b: Update Codebase Patterns (if discovery note posted)

When you post a Discovery Note, also update the consolidated patterns comment for quick reference:

```bash
# Check if patterns comment exists
PATTERNS_COMMENT=$(gh issue view $ISSUE_NUMBER --json comments --jq \
  '.comments[] | select(.body | startswith("## 🔍 Codebase Patterns"))')

if [ -z "$PATTERNS_COMMENT" ]; then
  # Create new patterns comment (conceptually pinned at top)
  gh issue comment $ISSUE_NUMBER --body "## 🔍 Codebase Patterns

This section consolidates learnings discovered during implementation for quick reference.

### Patterns
- [Pattern from current discovery]

### Gotchas
- [Gotcha from current discovery]

### Files for Reference
- [Relevant file]: [Brief description]

---
*Updated: $(date)*"
else
  # Post pattern update note (gh doesn't support editing)
  gh issue comment $ISSUE_NUMBER --body "## 📝 Pattern Update

Added to Codebase Patterns:
- [New pattern discovered]

See earlier '🔍 Codebase Patterns' comment for consolidated list."
fi
```

### Step 9c: Consider Creating AGENTS.md

If you discovered 2+ patterns in a specific directory, suggest creating an AGENTS.md file:

```
Consider creating `{directory}/AGENTS.md` with these patterns for future reference.
Template available at `.claude/templates/AGENTS.md.template`
```

This provides directory-specific context for future AI iterations.

---

## Loop Mode Reference

**See "Loop Mode (DEFAULT - Check This First)" section above for launch instructions.**

This section provides additional reference information about how the background script works.

### When User Returns After Loop

When user runs `/implement` after loop completes:
- Check if `debugState.status == "testing"` or all tasks pass
- If yes, enter testing checkpoint flow
- If blocked, show status and ask for guidance

### How the Background Script Works

The script `.claude/scripts/implement-loop.sh`:
1. Reads prd.json for task definitions and status
2. Loops through tasks, calling `claude --print --dangerously-skip-permissions` for each
3. Each Claude invocation:
   - Reads prd.json for task details
   - Checks git log and issue comments for context
   - Implements the task
   - Runs verification commands
   - Updates prd.json and commits
   - Posts task log to GitHub issue
4. Exits when: all pass, blocked, or max iterations

### Log Output Example

The background loop writes output like this to `.claude/implement-loop.log`:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎯 Task: US-001 - Create user schema
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   Status:   ⏳ Attempt 1
   Iteration: 1 of 20

Gathering context for Claude...
Running Claude on US-001...

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
1. Run `/implement` to retry the blocked task
2. Claude reads the guidance from comments
3. Applies the suggested approach

---

## State Recovery

If Claude Code session ends mid-task:

```bash
# Check current state
cat prd.json | jq '.userStories[] | select(.passes == false) | {id, title, attempts}'

# See what was committed
git log --oneline -5

# Resume from where we left off
/implement
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

Use AskUserQuestion with these options:

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

Run /issue close to:
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
  /implement     → Resume testing checkpoint
  /issue close --force → Skip testing (not recommended)
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

Use AskUserQuestion to collect:

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

This is a free-form text input via the "Other" option.

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

Then re-run the AskUserQuestion from Testing Checkpoint Step 3.

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

Update status to verified and proceed to `/issue close`.

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

Your help needed - add guidance to the issue, then run /implement.
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

When `/implement` is run and `debugState.status` is `testing`:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔄 Resuming testing checkpoint
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

All tasks are passing. Let's verify everything works...
```

Then proceed directly to Testing Checkpoint Step 3 (AskUserQuestion).

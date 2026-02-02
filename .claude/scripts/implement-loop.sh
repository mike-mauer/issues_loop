#!/bin/bash
# implement-loop.sh - Autonomous task execution loop
# Called by /implement loop, runs in background
#
# Usage: ./implement-loop.sh [max_iterations]
#
# This script reads prd.json and executes tasks one at a time using
# `claude --print --dangerously-skip-permissions` for autonomous execution.

set -e

PRD_FILE="prd.json"
LOG_FILE=".claude/implement-loop.log"
LOCK_FILE=".claude/implement-loop.lock"
MAX_ITERATIONS=${1:-20}
ITERATION=0

# Logging function
log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

# Initialize log file
mkdir -p "$(dirname "$LOG_FILE")"
echo "" >> "$LOG_FILE"
log "═══════════════════════════════════════════════"

# Verify prd.json exists
if [ ! -f "$PRD_FILE" ]; then
  log "ERROR: $PRD_FILE not found. Run /issue N first."
  exit 1
fi

# Acquire lock to prevent concurrent executions
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  log "ERROR: Another implement-loop process is already running."
  log "       If this is unexpected, remove $LOCK_FILE and try again."
  exit 1
fi
log "Lock acquired on $LOCK_FILE"

# Cleanup function to release lock on exit
cleanup() {
  flock -u 200 2>/dev/null || true
  rm -f "$LOCK_FILE" 2>/dev/null || true
}
trap cleanup EXIT

ISSUE_NUMBER=$(jq -r '.issueNumber' "$PRD_FILE")
BRANCH=$(jq -r '.branchName' "$PRD_FILE")

log "Implementation Loop Starting"
log "   Issue: #$ISSUE_NUMBER"
log "   Branch: $BRANCH"
log "   Max iterations: $MAX_ITERATIONS"
log "═══════════════════════════════════════════════"

# Ensure on correct branch
git checkout "$BRANCH" 2>/dev/null || git checkout -b "$BRANCH"

while [ $ITERATION -lt $MAX_ITERATIONS ]; do
  ITERATION=$((ITERATION + 1))

  # Check for remaining tasks
  REMAINING=$(jq '[.userStories[] | select(.passes == false)] | length' "$PRD_FILE")

  if [ "$REMAINING" -eq 0 ]; then
    log ""
    log "ALL TASKS PASSING"
    log ""
    log "Run 'claude' and invoke /implement to enter testing checkpoint."
    # Update prd.json to signal testing phase
    jq '.debugState.status = "testing"' "$PRD_FILE" > tmp.$$.json && mv tmp.$$.json "$PRD_FILE"
    git add "$PRD_FILE"
    git commit -m "chore: all tasks passing - ready for testing (#$ISSUE_NUMBER)" 2>/dev/null || true
    git push 2>/dev/null || true
    exit 0
  fi

  # Get IDs of passing tasks for dependency checking
  PASSING_IDS=$(jq -r '[.userStories[] | select(.passes == true) | .id] | join(" ")' "$PRD_FILE")

  # Find next executable task (passes=false, all dependencies met, sorted by priority)
  NEXT_TASK=$(jq -r --arg passing "$PASSING_IDS" '
    ($passing | split(" ")) as $passed_list |
    [.userStories[] |
    select(.passes == false) |
    select(
      (.dependsOn // []) |
      if length == 0 then true
      else all(. as $dep | $passed_list | index($dep) != null)
      end
    )] |
    sort_by(.priority // 999) |
    .[0].id // empty
  ' "$PRD_FILE")

  if [ -z "$NEXT_TASK" ] || [ "$NEXT_TASK" = "null" ]; then
    log "No executable tasks (dependencies not met or all blocked)"
    exit 1
  fi

  TASK_TITLE=$(jq -r --arg id "$NEXT_TASK" '.userStories[] | select(.id == $id) | .title' "$PRD_FILE")
  TASK_ATTEMPTS=$(jq -r --arg id "$NEXT_TASK" '.userStories[] | select(.id == $id) | .attempts // 0' "$PRD_FILE")

  log ""
  log "━━━ Iteration $ITERATION: $NEXT_TASK - $TASK_TITLE (attempt $((TASK_ATTEMPTS + 1))) ━━━"

  # Gather context for Claude
  log "Gathering context..."

  # 1. Get full task details from prd.json
  TASK_JSON=$(jq --arg id "$NEXT_TASK" '.userStories[] | select(.id == $id)' "$PRD_FILE")

  # 2. Get recent git commits (last 10)
  GIT_LOG=$(git log --oneline -10 2>/dev/null || echo "No git history available")

  # 3. Get issue body and full comment thread (comments are the memory system)
  ISSUE_BODY=$(gh issue view "$ISSUE_NUMBER" --json body --jq '.body' 2>/dev/null || echo "Could not fetch issue body")
  ISSUE_COMMENTS=$(gh issue view "$ISSUE_NUMBER" --json comments --jq '.comments[] | "---\n\(.author.login) (\(.createdAt)):\n\(.body)\n"' 2>/dev/null || echo "Could not fetch comments")

  # 4. Get list of files in repo (for context on codebase structure)
  REPO_STRUCTURE=$(find . -type f -name "*.ts" -o -name "*.js" -o -name "*.tsx" -o -name "*.jsx" -o -name "*.py" -o -name "*.go" -o -name "*.rs" 2>/dev/null | grep -v node_modules | grep -v ".git" | head -50 || echo "Could not list files")

  # Build prompt for Claude with gathered context
  PROMPT="You are executing a single task from the implementation loop.

=== TASK DETAILS ===
Task ID: $NEXT_TASK
Issue Number: $ISSUE_NUMBER

Task JSON:
$TASK_JSON

=== ISSUE CONTEXT ===
Issue Body:
$ISSUE_BODY

Comments (full thread - includes Discovery Notes, Task Logs, learnings):
$ISSUE_COMMENTS

=== GIT CONTEXT ===
Recent Commits:
$GIT_LOG

=== REPO STRUCTURE ===
Source files (first 50):
$REPO_STRUCTURE

=== INSTRUCTIONS ===
1. Review the task details above (acceptanceCriteria, verifyCommands, files to modify)
2. Use the issue body and comments for requirements and learnings
3. Check git history for patterns and recent changes
4. Implement the required changes
5. Run ALL verifyCommands to check your work
6. Based on results:

If ALL verifyCommands PASS:
- Update prd.json: set this task's 'passes' to true, increment 'attempts', set 'lastAttempt' to current ISO timestamp
- Stage and commit your implementation changes: git commit -m \"feat($NEXT_TASK): description (#$ISSUE_NUMBER)\"
- Commit the prd.json update: git commit -m \"chore: update prd.json - $NEXT_TASK passed (#$ISSUE_NUMBER)\"
- Push changes: git push
- Post a task log comment to GitHub issue #$ISSUE_NUMBER using: gh issue comment $ISSUE_NUMBER --body \"...\"
- Output exactly at the end: <result>PASS</result>

If verification FAILS:
- Increment 'attempts' in prd.json and set 'lastAttempt'
- Commit prd.json: git commit -m \"chore: update prd.json - $NEXT_TASK attempt \$N failed (#$ISSUE_NUMBER)\"
- Post a failure log to the issue explaining what failed and why
- If attempts >= 3:
  - Add 'AI: Blocked' label: gh issue edit $ISSUE_NUMBER --add-label \"AI: Blocked\"
  - Output exactly: <result>BLOCKED</result>
- Otherwise output exactly: <result>RETRY</result>

CRITICAL: You MUST output exactly one of <result>PASS</result>, <result>RETRY</result>, or <result>BLOCKED</result> as the final line of your response."

  # Run Claude for this task
  log "Running claude --print for task $NEXT_TASK..."

  # Proper error handling - capture exit code separately
  set +e  # Temporarily allow errors
  OUTPUT=$(echo "$PROMPT" | claude --print --dangerously-skip-permissions 2>&1)
  CLAUDE_EXIT=$?
  set -e

  # Check for execution failure
  if [ $CLAUDE_EXIT -ne 0 ] && [ -z "$OUTPUT" ]; then
    log "ERROR: Claude failed to execute (exit code: $CLAUDE_EXIT)"
    log "       Check that 'claude' CLI is installed and configured."
    exit 1
  fi

  # Log output to file (truncate if very long)
  echo "--- Claude output for $NEXT_TASK ---" >> "$LOG_FILE"
  echo "$OUTPUT" | tail -100 >> "$LOG_FILE"
  echo "--- End output ---" >> "$LOG_FILE"

  # Extract result more reliably (case-insensitive, handle whitespace)
  RESULT=$(echo "$OUTPUT" | grep -oiE '<result>\s*(PASS|RETRY|BLOCKED)\s*</result>' | tail -1 | sed 's/<[^>]*>//g' | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')

  # Check result
  if [ "$RESULT" = "PASS" ]; then
    log "✅ $NEXT_TASK passed"
  elif [ "$RESULT" = "BLOCKED" ]; then
    log "⛔ $NEXT_TASK blocked after max attempts"
    gh issue edit "$ISSUE_NUMBER" --add-label "AI: Blocked" 2>/dev/null || true
    exit 1
  elif [ "$RESULT" = "RETRY" ]; then
    log "🔄 $NEXT_TASK failed, will retry..."
    # Don't increment iteration for retries within same task
  else
    log "⚠️ No valid result tag found in output (got: '$RESULT'), assuming retry needed"
    log "Last 10 lines of output:"
    echo "$OUTPUT" | tail -10 | while read line; do log "  $line"; done
  fi
done

log "⚠️ Max iterations ($MAX_ITERATIONS) reached"
exit 1

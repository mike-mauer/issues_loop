#!/bin/bash
# implement-loop.sh - Autonomous task execution loop
# Called by /implement loop, runs in background
#
# Usage: ./implement-loop.sh [max_iterations]
#
# This script reads prd.json and executes tasks one at a time using
# `claude --print --dangerously-skip-permissions` for autonomous execution.

set -e

# Source helper library (uid generation, JSON event extraction, backward-compat)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/implement-loop-lib.sh"

# ═══════════════════════════════════════════════════════════════════════════════
# Style constants - consistent formatting across all output
# ═══════════════════════════════════════════════════════════════════════════════

# Box drawing characters
LINE_HEAVY="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
LINE_DOUBLE="═══════════════════════════════════════════════════"

# Status indicators
ICON_SUCCESS="✅"
ICON_FAILURE="❌"
ICON_PROGRESS="⏳"
ICON_BLOCKED="⛔"
ICON_RETRY="🔄"
ICON_TASK="🎯"
ICON_WARN="⚠️"
ICON_CELEBRATE="🎉"
ICON_INFO="ℹ️"

# ═══════════════════════════════════════════════════════════════════════════════

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
log "$LINE_DOUBLE"

# Verify prd.json exists
if [ ! -f "$PRD_FILE" ]; then
  log "$ICON_FAILURE prd.json not found. Run /issue N first to create a plan."
  exit 1
fi

# Acquire lock to prevent concurrent executions
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  log "$ICON_BLOCKED Another loop is already running."
  log "   If this is unexpected, remove $LOCK_FILE and try again."
  exit 1
fi
log "$ICON_INFO Lock acquired"

# Cleanup function to release lock on exit
cleanup() {
  flock -u 200 2>/dev/null || true
  rm -f "$LOCK_FILE" 2>/dev/null || true
}
trap cleanup EXIT

# Backward-compatible initialization: fill in missing formula, compaction,
# uid, discoveredFrom, discoverySource fields with safe defaults
initialize_missing_prd_fields "$PRD_FILE"

ISSUE_NUMBER=$(jq -r '.issueNumber' "$PRD_FILE")
BRANCH=$(jq -r '.branchName' "$PRD_FILE")

log ""
log "$ICON_TASK Implementation Loop Starting"
log ""
log "   Issue:      #$ISSUE_NUMBER"
log "   Branch:     $BRANCH"
log "   Max runs:   $MAX_ITERATIONS"
log ""
log "$LINE_DOUBLE"

# Ensure on correct branch
git checkout "$BRANCH" 2>/dev/null || git checkout -b "$BRANCH"

while [ $ITERATION -lt $MAX_ITERATIONS ]; do
  ITERATION=$((ITERATION + 1))

  # Check for remaining tasks
  REMAINING=$(jq '[.userStories[] | select(.passes == false)] | length' "$PRD_FILE")

  if [ "$REMAINING" -eq 0 ]; then
    log ""
    log "$LINE_HEAVY"
    log "$ICON_CELEBRATE All tasks passing!"
    log "$LINE_HEAVY"
    log ""
    log "Run 'claude' and use /implement to enter testing checkpoint."
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
    log "$ICON_BLOCKED No executable tasks - dependencies not met or all blocked"
    exit 1
  fi

  TASK_TITLE=$(jq -r --arg id "$NEXT_TASK" '.userStories[] | select(.id == $id) | .title' "$PRD_FILE")
  TASK_ATTEMPTS=$(jq -r --arg id "$NEXT_TASK" '.userStories[] | select(.id == $id) | .attempts // 0' "$PRD_FILE")
  TASK_UID=$(jq -r --arg id "$NEXT_TASK" '.userStories[] | select(.id == $id) | .uid // ""' "$PRD_FILE")
  TASK_PRIORITY=$(jq -r --arg id "$NEXT_TASK" '.userStories[] | select(.id == $id) | .priority // 1' "$PRD_FILE")

  log ""
  log "$LINE_HEAVY"
  log "$ICON_TASK Task: $NEXT_TASK - $TASK_TITLE"
  log "$LINE_HEAVY"
  log ""
  log "   Status:   $ICON_PROGRESS Attempt $((TASK_ATTEMPTS + 1))"
  log "   Iteration: $ITERATION of $MAX_ITERATIONS"
  log ""

  # Gather context for Claude
  log "Gathering context for Claude..."

  # 1. Get full task details from prd.json
  TASK_JSON=$(jq --arg id "$NEXT_TASK" '.userStories[] | select(.id == $id)' "$PRD_FILE")

  # 2. Get recent git commits (last 10)
  GIT_LOG=$(git log --oneline -10 2>/dev/null || echo "No git history available")

  # 3. Get issue body and full comment thread (comments are the memory system)
  ISSUE_BODY=$(gh issue view "$ISSUE_NUMBER" --json body --jq '.body' 2>/dev/null || echo "Could not fetch issue body")
  ISSUE_COMMENTS=$(gh issue view "$ISSUE_NUMBER" --json comments --jq '.comments[] | "---\n\(.author.login) (\(.createdAt)):\n\(.body)\n"' 2>/dev/null || echo "Could not fetch comments")

  # 4. Get list of files in repo (for context on codebase structure)
  REPO_STRUCTURE=$(find . -type f -name "*.ts" -o -name "*.js" -o -name "*.tsx" -o -name "*.jsx" -o -name "*.py" -o -name "*.go" -o -name "*.rs" 2>/dev/null | grep -v node_modules | grep -v ".git" | head -50 || echo "Could not list files")

  # 5. Collect active (non-expired) wisps for ephemeral context
  ACTIVE_WISPS=$(collect_active_wisps "$ISSUE_NUMBER" 2>/dev/null || echo "")

  # 6. Extract structured JSON events from recent task logs
  JSON_EVENTS=$(extract_json_events_from_issue_comments "$ISSUE_COMMENTS" 2>/dev/null || echo "")

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

=== TASK IDENTITY ===
Task UID: $TASK_UID
(Use this exact value for taskUid in the Event JSON block — do NOT generate your own.)

=== ACTIVE WISPS (ephemeral context hints) ===
${ACTIVE_WISPS:-No active wisps}

=== RECENT JSON EVENTS (structured task history) ===
${JSON_EVENTS:-No structured events found}

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

=== JSON EVENT EMISSION ===
Your task log comment MUST include a '### Event JSON' section with a single
fenced json code block containing a compact JSON event object. Place this at
the end of the task log comment. Format:

\`\`\`
### Event JSON
\\\`\\\`\\\`json
{\"v\":1,\"type\":\"task_log\",\"issue\":$ISSUE_NUMBER,\"taskId\":\"$NEXT_TASK\",\"taskUid\":\"$TASK_UID\",\"status\":\"pass\",\"attempt\":<N>,\"commit\":\"<hash>\",\"verify\":{\"passed\":[...],\"failed\":[...]},\"discovered\":[],\"ts\":\"<ISO 8601>\"}
\\\`\\\`\\\`
\`\`\`

The 'discovered' array should contain any new tasks found during implementation
(empty array if none). Each discovered task object needs: title, description,
acceptanceCriteria, verifyCommands, and dependsOn.

CRITICAL: You MUST output exactly one of <result>PASS</result>, <result>RETRY</result>, or <result>BLOCKED</result> as the final line of your response."

  # Run Claude for this task
  log "Running Claude on $NEXT_TASK..."

  # Proper error handling - capture exit code separately
  set +e  # Temporarily allow errors
  OUTPUT=$(echo "$PROMPT" | claude --print --dangerously-skip-permissions 2>&1)
  CLAUDE_EXIT=$?
  set -e

  # Check for execution failure
  if [ $CLAUDE_EXIT -ne 0 ] && [ -z "$OUTPUT" ]; then
    log "$ICON_FAILURE Claude failed to execute (exit code: $CLAUDE_EXIT)"
    log "   Check that 'claude' CLI is installed and configured."
    exit 1
  fi

  # Log output to file (truncate if very long)
  echo "--- Claude output for $NEXT_TASK ---" >> "$LOG_FILE"
  echo "$OUTPUT" | tail -100 >> "$LOG_FILE"
  echo "--- End output ---" >> "$LOG_FILE"

  # Extract result more reliably (case-insensitive, handle whitespace)
  RESULT=$(echo "$OUTPUT" | grep -oiE '<result>\s*(PASS|RETRY|BLOCKED)\s*</result>' | tail -1 | sed 's/<[^>]*>//g' | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')

  # ─── Post-task orchestration: enqueue discovered tasks + compaction ───

  # Extract discovered tasks from output (parse JSON events from Claude's response)
  # Look for Event JSON block in the output to get discovered array
  DISCOVERED_JSON=""
  if [ "$RESULT" = "PASS" ] || [ "$RESULT" = "RETRY" ]; then
    DISCOVERED_JSON=$(echo "$OUTPUT" | extract_json_events_from_issue_comments | \
      jq -s '[.[].discovered[]? // empty]' 2>/dev/null || echo "[]")
    if [ -n "$DISCOVERED_JSON" ] && [ "$DISCOVERED_JSON" != "[]" ] && [ "$DISCOVERED_JSON" != "null" ]; then
      log "Discovered tasks found, enqueuing..."
      enqueue_discovered_tasks "$PRD_FILE" "$NEXT_TASK" "$TASK_UID" "$TASK_PRIORITY" "$DISCOVERED_JSON" "$ISSUE_NUMBER"
      log "$ICON_SUCCESS Discovered tasks enqueued"
    fi
  fi

  # Check result and run compaction after pass/retry (task log was posted by Claude)
  if [ "$RESULT" = "PASS" ]; then
    log ""
    log "$LINE_HEAVY"
    log "$ICON_SUCCESS $NEXT_TASK passed! Moving to next task..."
    log "$LINE_HEAVY"

    # Compaction: increment counter, post summary if threshold reached
    maybe_post_compaction_summary "$PRD_FILE" "$ISSUE_NUMBER" "$NEXT_TASK" "$TASK_UID" "$((TASK_ATTEMPTS + 1))"
    git push 2>/dev/null || true

  elif [ "$RESULT" = "BLOCKED" ]; then
    log ""
    log "$LINE_HEAVY"
    log "$ICON_BLOCKED $NEXT_TASK blocked after 3 attempts"
    log "$LINE_HEAVY"
    log ""
    log "Human input needed. Add guidance to the issue, then run /implement."
    gh issue edit "$ISSUE_NUMBER" --add-label "AI: Blocked" 2>/dev/null || true
    exit 1
  elif [ "$RESULT" = "RETRY" ]; then
    log ""
    log "$ICON_RETRY $NEXT_TASK failed verification, retrying..."

    # Still run compaction counter (a task log was posted even on failure)
    maybe_post_compaction_summary "$PRD_FILE" "$ISSUE_NUMBER" "$NEXT_TASK" "$TASK_UID" "$((TASK_ATTEMPTS + 1))"
    git push 2>/dev/null || true

    # Don't increment iteration for retries within same task
  else
    log ""
    log "$ICON_WARN No valid result tag found (got: '$RESULT'), retrying..."
    log "Last 10 lines of output:"
    echo "$OUTPUT" | tail -10 | while read line; do log "  $line"; done
  fi
done

log ""
log "$LINE_HEAVY"
log "$ICON_WARN Max iterations ($MAX_ITERATIONS) reached"
log "$LINE_HEAVY"
exit 1

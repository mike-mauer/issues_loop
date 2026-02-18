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
REVIEW_LOG_FILE=".claude/review-loop.log"
LOCK_FILE=".claude/implement-loop.lock"
CONFIG_FILE=".issueloop.config.json"
MAX_ITERATIONS=${1:-20}
ITERATION=0
REVIEW_ENABLED="true"
REVIEW_MAX_FINDINGS=5

# Logging function
log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

# Commit prd.json only when it has staged or unstaged changes
commit_prd_if_changed() {
  local message="$1"
  if ! git diff --quiet -- "$PRD_FILE" || ! git diff --cached --quiet -- "$PRD_FILE"; then
    git add "$PRD_FILE"
    git commit -m "$message" 2>/dev/null || true
  fi
}

# Build concise code-review prompt with strict read-only constraints
build_review_prompt() {
  local scope_label="$1"
  local scope_type="$2"
  local parent_task_id="$3"
  local parent_task_uid="$4"
  local reviewed_commit="$5"
  local task_json="$6"
  local changed_files="$7"
  local issue_body="$8"
  local issue_comments="$9"

  cat <<EOF
You are a code-review agent. Read-only analysis only.
You MUST NOT edit files, run formatters, commit, push, or modify prd.json.

Goal: produce a concise, high-signal review for this change.
Ignore cosmetic/style nits unless they create runtime, reliability, or maintenance risk.

Review scope:
- Scope label: ${scope_label}
- Scope type: ${scope_type}
- Parent task id: ${parent_task_id:-none}
- Parent task uid: ${parent_task_uid:-none}
- Reviewed commit: ${reviewed_commit}

Task JSON:
${task_json:-{}}

Changed files:
${changed_files:-No changed files detected}

Issue body:
${issue_body}

Issue comments:
${issue_comments}

Review dimensions in strict order:
1) Correctness and regressions
- Requirement/acceptance mismatch
- Logic bugs, edge cases, null/empty handling, race conditions
- Backward-compatibility breakage

2) Architectural adherence and pattern reuse
- Follows existing project patterns and boundaries
- Avoids new coupling/layering violations
- Reuses existing modules before introducing new abstractions

3) Production readiness
- Failure handling (timeouts/retries/fallbacks/idempotency)
- Observability (actionable logs/metrics/error context)
- Deployment safety (config/migrations/feature flags/rollback)

4) Efficiency and scalability
- Hot-path inefficiencies, N+1/repeated I/O, complexity regressions
- Query/index/cache implications where relevant

5) Security and data integrity
- Authn/authz enforcement
- Input validation/injection risk
- Secrets/PII handling and consistency guarantees

6) Test adequacy
- Coverage of behavior + edge/failure paths
- Verify commands that would catch regressions

Output requirements:
- Summary <= 80 words.
- Max ${REVIEW_MAX_FINDINGS} findings, highest severity first.
- Each finding MUST include: id, severity(critical|high|medium|low), confidence(0-1), category(adherence|efficiency|pattern_reuse|production_readiness|security), title, description, evidence(file+line).
- Include suggestedTask ONLY for critical/high findings.
- If no material risk: findings must be [].

Return exactly:
## 🔎 Code Review: ${scope_label}
### Summary
...
### Review Event JSON
\`\`\`json
{"v":1,"type":"review_log","issue":${ISSUE_NUMBER},"reviewId":"<id>","scope":"${scope_type}","parentTaskId":"${parent_task_id}","parentTaskUid":"${parent_task_uid}","reviewedCommit":"${reviewed_commit}","status":"completed","findings":[],"ts":"<ISO 8601>"}
\`\`\`

Final line exactly one of:
<review_result>FINDINGS</review_result>
<review_result>CLEAR</review_result>
EOF
}

# Run a review agent invocation. mode: async|sync
spawn_task_review_agent() {
  local scope_label="$1"
  local scope_type="$2"
  local parent_task_id="$3"
  local parent_task_uid="$4"
  local reviewed_commit="$5"
  local task_json="$6"
  local mode="${7:-async}"

  local changed_files issue_body issue_comments prompt
  if [ "$scope_type" = "final" ]; then
    changed_files=$(git diff --name-only main..HEAD 2>/dev/null | head -200)
  else
    changed_files=$(git show --name-only --pretty="" "$reviewed_commit" 2>/dev/null | head -200)
  fi
  issue_body=$(gh issue view "$ISSUE_NUMBER" --json body --jq '.body' 2>/dev/null || echo "Could not fetch issue body")
  issue_comments=$(gh issue view "$ISSUE_NUMBER" --json comments --jq '.comments[] | "---\n\(.author.login) (\(.createdAt)):\n\(.body)\n"' 2>/dev/null || echo "Could not fetch comments")
  prompt=$(build_review_prompt "$scope_label" "$scope_type" "$parent_task_id" "$parent_task_uid" "$reviewed_commit" "$task_json" "$changed_files" "$issue_body" "$issue_comments")

  mkdir -p "$(dirname "$REVIEW_LOG_FILE")"

  if [ "$mode" = "async" ]; then
    (
      set +e
      output=$(echo "$prompt" | claude --print --dangerously-skip-permissions 2>&1)
      exit_code=$?
      {
        echo "--- Review output for $scope_label ($reviewed_commit) ---"
        echo "$output" | tail -120
        echo "--- End review output ---"
        if [ $exit_code -ne 0 ]; then
          echo "Review invocation exited with non-zero status: $exit_code"
        fi
      } >> "$REVIEW_LOG_FILE"
    ) &
    log "$ICON_INFO Review agent spawned for $scope_label"
    return 0
  fi

  set +e
  output=$(echo "$prompt" | claude --print --dangerously-skip-permissions 2>&1)
  exit_code=$?
  set -e
  {
    echo "--- Review output for $scope_label ($reviewed_commit) ---"
    echo "$output" | tail -120
    echo "--- End review output ---"
  } >> "$REVIEW_LOG_FILE"
  if [ $exit_code -ne 0 ] && [ -z "$output" ]; then
    return 1
  fi
  return 0
}

# Ingest posted review events and auto-enqueue high-severity findings.
process_review_lane() {
  [ "$REVIEW_ENABLED" = "true" ] || return 0

  local comments review_events
  comments=$(gh issue view "$ISSUE_NUMBER" --json comments --jq '.comments[] | .body' 2>/dev/null || echo "")
  review_events=$(extract_review_events_from_issue_comments "$comments" 2>/dev/null || echo "")

  local ingested_total=0
  if [ -n "$review_events" ]; then
    while IFS= read -r event; do
      [ -z "$event" ] && continue
      local added_count
      added_count=$(ingest_review_findings_into_prd "$PRD_FILE" "$event" "$ISSUE_NUMBER" 2>/dev/null || echo "0")
      ingested_total=$((ingested_total + added_count))
    done <<< "$review_events"
  fi

  reconcile_review_findings "$PRD_FILE" 2>/dev/null || true

  local enqueuable_json
  enqueuable_json=$(build_enqueuable_review_tasks "$PRD_FILE")
  if [ -z "$enqueuable_json" ] || [ "$enqueuable_json" = "null" ]; then
    enqueuable_json="[]"
  fi

  local enqueued_count=0
  while IFS= read -r finding; do
    [ -z "$finding" ] && continue

    local finding_key parent_id parent_uid parent_priority suggested_task discovered_json key_json
    finding_key=$(echo "$finding" | jq -r '.key // ""')
    parent_id=$(echo "$finding" | jq -r '.parentTaskId // ""')
    parent_uid=$(echo "$finding" | jq -r '.parentTaskUid // ""')
    suggested_task=$(echo "$finding" | jq -c '.suggestedTask // null')

    [ -n "$finding_key" ] || continue
    [ "$suggested_task" != "null" ] || continue

    # Fall back to the first existing story as parent if review finding has no parent.
    if [ -z "$parent_id" ]; then
      parent_id=$(jq -r '.userStories[0].id // "US-001"' "$PRD_FILE")
    fi
    if [ -z "$parent_uid" ] || [ "$parent_uid" = "null" ]; then
      parent_uid=$(jq -r --arg id "$parent_id" '.userStories[] | select(.id == $id) | .uid // "review_root"' "$PRD_FILE")
      if [ -z "$parent_uid" ] || [ "$parent_uid" = "null" ]; then
        parent_uid="review_root"
      fi
    fi
    parent_priority=$(jq -r --arg id "$parent_id" '.userStories[] | select(.id == $id) | .priority // 1' "$PRD_FILE")
    if [ -z "$parent_priority" ] || [ "$parent_priority" = "null" ]; then
      parent_priority=1
    fi

    discovered_json=$(jq -nc --arg key "$finding_key" --argjson task "$suggested_task" '
      [
        {
          "title": ($task.title // ("Address review finding " + $key)),
          "description": ("Review Finding Key: " + $key + "\n" + ($task.description // "Address this review finding.")),
          "acceptanceCriteria": ($task.acceptanceCriteria // ["Review finding addressed"]),
          "verifyCommands": ($task.verifyCommands // []),
          "dependsOn": ($task.dependsOn // [])
        }
      ]
    ')

    enqueue_discovered_tasks "$PRD_FILE" "$parent_id" "$parent_uid" "$parent_priority" "$discovered_json" "$ISSUE_NUMBER" "code_review"
    key_json=$(jq -nc --arg key "$finding_key" '[$key]')
    mark_enqueued_findings "$PRD_FILE" "$key_json"
    enqueued_count=$((enqueued_count + 1))
  done < <(echo "$enqueuable_json" | jq -c '.[]' 2>/dev/null)

  if [ "$ingested_total" -gt 0 ] || [ "$enqueued_count" -gt 0 ]; then
    commit_prd_if_changed "chore: process review findings state (#$ISSUE_NUMBER)"
  fi
}

# Initialize log file
mkdir -p "$(dirname "$LOG_FILE")"
echo "" >> "$LOG_FILE"
log "$LINE_DOUBLE"

# Verify prd.json exists
if [ ! -f "$PRD_FILE" ]; then
  log "$ICON_FAILURE prd.json not found. Run /issue N first to create a plan."
  exit 1
fi

# Load review policy config defaults
if [ -f "$CONFIG_FILE" ]; then
  REVIEW_ENABLED=$(jq -r '.review.enabled // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
  REVIEW_MAX_FINDINGS=$(jq -r '.review.maxFindingsPerReview // 5' "$CONFIG_FILE" 2>/dev/null || echo "5")
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

# Sync quality review policy from config (single source of defaults).
if [ "$REVIEW_ENABLED" = "true" ] && [ -f "$CONFIG_FILE" ]; then
  jq --argjson auto "$(jq -c '.review.autoEnqueueSeverities // ["critical","high"]' "$CONFIG_FILE" 2>/dev/null || echo '["critical","high"]')" \
     --argjson approval "$(jq -c '.review.approvalRequiredSeverities // ["medium","low"]' "$CONFIG_FILE" 2>/dev/null || echo '["medium","low"]')" \
     --argjson min_conf "$(jq -c '.review.minConfidenceForAutoEnqueue // 0.75' "$CONFIG_FILE" 2>/dev/null || echo '0.75')" \
     --argjson max_findings "$(jq -c '.review.maxFindingsPerReview // 5' "$CONFIG_FILE" 2>/dev/null || echo '5')" \
     '.quality.reviewPolicy.autoEnqueueSeverities = $auto |
      .quality.reviewPolicy.approvalRequiredSeverities = $approval |
      .quality.reviewPolicy.minConfidenceForAutoEnqueue = $min_conf |
      .quality.reviewPolicy.maxFindingsPerReview = $max_findings' \
     "$PRD_FILE" > tmp.$$.json && mv tmp.$$.json "$PRD_FILE"
  commit_prd_if_changed "chore: sync review policy from config (#$ISSUE_NUMBER)"
fi

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

  # Keep review lane converging with newly posted review events
  process_review_lane

  # Check for remaining tasks
  REMAINING=$(jq '[.userStories[] | select(.passes == false)] | length' "$PRD_FILE")

  if [ "$REMAINING" -eq 0 ]; then
    if [ "$REVIEW_ENABLED" = "true" ]; then
      FINAL_STATUS=$(jq -r '.quality.finalReview.status // "pending"' "$PRD_FILE")
      if [ "$FINAL_STATUS" != "passed" ]; then
        HEAD_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "")
        log "$ICON_INFO Running final review gate before testing..."

        mark_final_review_status "$PRD_FILE" "running" "$HEAD_COMMIT" ""
        commit_prd_if_changed "chore: start final review gate (#$ISSUE_NUMBER)"

        if ! spawn_task_review_agent "FINAL" "final" "FINAL" "final_review" "$HEAD_COMMIT" "{}" "sync"; then
          log "$ICON_WARN Final review invocation failed."
          mark_final_review_status "$PRD_FILE" "failed" "$HEAD_COMMIT" ""
          commit_prd_if_changed "chore: final review invocation failed (#$ISSUE_NUMBER)"
          gh issue edit "$ISSUE_NUMBER" --add-label "AI: Review" 2>/dev/null || true
          continue
        fi

        FINAL_EVENT=$(verify_review_log_on_github "$ISSUE_NUMBER" "FINAL" "$HEAD_COMMIT" 2>/dev/null || echo "")
        if [ -z "$FINAL_EVENT" ] || [ "$FINAL_EVENT" = "null" ]; then
          log "$ICON_WARN Final review event not verified on GitHub."
          mark_final_review_status "$PRD_FILE" "failed" "$HEAD_COMMIT" ""
          commit_prd_if_changed "chore: final review event missing (#$ISSUE_NUMBER)"
          gh issue edit "$ISSUE_NUMBER" --add-label "AI: Review" 2>/dev/null || true
          continue
        fi

        FINAL_REVIEW_ID=$(echo "$FINAL_EVENT" | jq -r '.reviewId // ""' 2>/dev/null)
        ingest_review_findings_into_prd "$PRD_FILE" "$FINAL_EVENT" "$ISSUE_NUMBER" >/dev/null 2>&1 || true
        process_review_lane

        REMAINING_AFTER_REVIEW=$(jq '[.userStories[] | select(.passes == false)] | length' "$PRD_FILE")
        BLOCKING_REVIEW_FINDINGS=$(count_open_blocking_review_findings "$PRD_FILE")
        if [ "$REMAINING_AFTER_REVIEW" -gt 0 ] || [ "$BLOCKING_REVIEW_FINDINGS" -gt 0 ]; then
          log "$ICON_WARN Final review found blocking work. Continuing loop."
          mark_final_review_status "$PRD_FILE" "failed" "$HEAD_COMMIT" "$FINAL_REVIEW_ID"
          commit_prd_if_changed "chore: final review blocked testing (#$ISSUE_NUMBER)"
          gh issue edit "$ISSUE_NUMBER" --add-label "AI: Review" 2>/dev/null || true
          continue
        fi

        mark_final_review_status "$PRD_FILE" "passed" "$HEAD_COMMIT" "$FINAL_REVIEW_ID"
        commit_prd_if_changed "chore: final review passed (#$ISSUE_NUMBER)"
      fi
    fi

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

  # Verify task log was ACTUALLY posted to GitHub (not just emitted in output).
  # This is the authoritative check — proves gh issue comment succeeded.
  PARSED_EVENT=""
  EVENT_VERIFIED=0
  if [ "$RESULT" = "PASS" ] || [ "$RESULT" = "RETRY" ]; then
    PARSED_EVENT=$(verify_task_log_on_github "$ISSUE_NUMBER" "$NEXT_TASK" "$TASK_UID" 2>/dev/null || echo "")

    if [ -n "$PARSED_EVENT" ] && [ "$PARSED_EVENT" != "null" ]; then
      EVENT_VERIFIED=1

      # Extract discovered tasks from the verified event
      DISCOVERED_JSON=$(echo "$PARSED_EVENT" | jq -c '[.discovered[]? // empty]' 2>/dev/null || echo "[]")
      if [ -n "$DISCOVERED_JSON" ] && [ "$DISCOVERED_JSON" != "[]" ] && [ "$DISCOVERED_JSON" != "null" ]; then
        log "Discovered tasks found, enqueuing..."
        enqueue_discovered_tasks "$PRD_FILE" "$NEXT_TASK" "$TASK_UID" "$TASK_PRIORITY" "$DISCOVERED_JSON" "$ISSUE_NUMBER"
        log "$ICON_SUCCESS Discovered tasks enqueued"
      fi
    fi

    if [ "$EVENT_VERIFIED" -eq 0 ]; then
      log "$ICON_WARN Task log not found on GitHub — comment may have failed to post. Skipping compaction."
    fi
  fi

  # Check result; only run compaction if event was verified (confirms task log was posted)
  if [ "$RESULT" = "PASS" ]; then
    log ""
    log "$LINE_HEAVY"
    log "$ICON_SUCCESS $NEXT_TASK passed! Moving to next task..."
    log "$LINE_HEAVY"

    # Compaction: only increment counter if task log was confirmed via Event JSON
    if [ "$EVENT_VERIFIED" -eq 1 ]; then
      maybe_post_compaction_summary "$PRD_FILE" "$ISSUE_NUMBER" "$NEXT_TASK" "$TASK_UID" "$((TASK_ATTEMPTS + 1))"

      if [ "$REVIEW_ENABLED" = "true" ]; then
        REVIEW_COMMIT=$(echo "$PARSED_EVENT" | jq -r '.commit // ""' 2>/dev/null)
        if [ -z "$REVIEW_COMMIT" ] || [ "$REVIEW_COMMIT" = "null" ]; then
          REVIEW_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "")
        fi
        spawn_task_review_agent "$NEXT_TASK" "task" "$NEXT_TASK" "$TASK_UID" "$REVIEW_COMMIT" "$TASK_JSON" "async"
      fi
    fi
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

    # Compaction: only increment counter if task log was confirmed via Event JSON
    if [ "$EVENT_VERIFIED" -eq 1 ]; then
      maybe_post_compaction_summary "$PRD_FILE" "$ISSUE_NUMBER" "$NEXT_TASK" "$TASK_UID" "$((TASK_ATTEMPTS + 1))"
    fi
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

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
MAX_TASK_ATTEMPTS=3

# Execution hardening defaults (overridden by load_execution_config)
EXEC_GATE_MODE="enforce"
EXEC_EVENT_REQUIRED="true"
EXEC_VERIFY_TIMEOUT_SECONDS=600
EXEC_VERIFY_MAX_OUTPUT_LINES=80
EXEC_VERIFY_GLOBAL_COMMANDS_JSON='[]'
EXEC_VERIFY_FAST_GLOBAL_COMMANDS_JSON='[]'
EXEC_VERIFY_FULL_GLOBAL_COMMANDS_JSON='[]'
EXEC_VERIFY_FULL_RUN_EVERY_N_PASSED_TASKS=0
EXEC_VERIFY_RUN_FULL_BEFORE_TESTING_CHECKPOINT="false"
EXEC_VERIFY_SECURITY_COMMANDS_JSON='[]'
EXEC_VERIFY_RUN_SECURITY_EACH="false"
EXEC_SEARCH_REQUIRED="true"
EXEC_SEARCH_MIN_QUERIES=2
EXEC_PROFILE="greenfield"
EXEC_TASK_SIZING_ENABLED="false"
EXEC_TASK_SIZING_MAX_DESCRIPTION_SENTENCES=3
EXEC_TASK_SIZING_MAX_ACCEPTANCE_CRITERIA=10
EXEC_TASK_SIZING_MAX_VERIFY_COMMANDS=6
EXEC_TASK_SIZING_MAX_FILES=12
EXEC_TASK_SIZING_HARD_FAIL_ON_OVERSIZED="true"
EXEC_CONTEXT_MANIFEST_ENABLED="false"
EXEC_CONTEXT_MANIFEST_ALGORITHM="sha256"
EXEC_CONTEXT_MANIFEST_ENFORCE_HASH_MATCH="false"
EXEC_BROWSER_REQUIRED_FOR_UI="true"
EXEC_BROWSER_HARD_FAIL_WHEN_UNAVAILABLE="true"
EXEC_BROWSER_ALLOWED_TOOLS_JSON='["playwright","dev-browser"]'
EXEC_REPLAN_AUTO_GENERATE_ON_STALE="false"
EXEC_REPLAN_AUTO_APPLY_IF_SINGLE_TASK="true"
EXEC_REPLAN_MAX_GENERATED_TASKS=6
EXEC_PLACEHOLDER_ENABLED="true"
EXEC_PLACEHOLDER_PATTERNS_JSON='[]'
EXEC_PLACEHOLDER_EXCLUDE_REGEX_JSON='[]'
EXEC_PLACEHOLDER_SEMANTIC_ENABLED="false"
EXEC_PLACEHOLDER_BLOCK_TRIVIAL_CONSTANT_RETURNS="true"
EXEC_PLACEHOLDER_BLOCK_ALWAYS_TRUE_FALSE_CONDITIONALS="true"
EXEC_TEST_INTENT_REQUIRED_WHEN_TESTS_CHANGED="false"
EXEC_TEST_INTENT_ENFORCE="false"
EXEC_STALE_ENABLED="true"
EXEC_STALE_SAME_TASK_THRESHOLD=2
EXEC_STALE_CONSECUTIVE_THRESHOLD=4
EXEC_CONTEXT_PREFER_COMPACTED="true"
EXEC_CONTEXT_MAX_TASK_LOGS=8
EXEC_CONTEXT_MAX_DISCOVERY_NOTES=6
EXEC_CONTEXT_MAX_REVIEW_LOGS=4
EXEC_LABEL_PLANNING="AI: Planning"
MEMORY_AUTO_SYNC_DOCS="true"
MEMORY_MIN_CONFIDENCE="0.8"
MEMORY_DOC_TARGETS_JSON='["AGENTS.md","CLAUDE.md"]'
MEMORY_MAX_PATTERNS_PER_TASK=3
MEMORY_MANAGED_SECTION_MARKER="issues-loop:auto-patterns"

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

# Commit pattern sync changes only for prd.json and synced docs.
commit_pattern_sync_if_changed() {
  local message="$1"
  local docs_json="${2:-[]}"
  local changed=0

  if ! git diff --quiet -- "$PRD_FILE" || ! git diff --cached --quiet -- "$PRD_FILE"; then
    git add "$PRD_FILE"
    changed=1
  fi

  while IFS= read -r doc_path; do
    [ -z "$doc_path" ] && continue
    if [ -f "$doc_path" ] && (! git diff --quiet -- "$doc_path" || ! git diff --cached --quiet -- "$doc_path"); then
      git add "$doc_path"
      changed=1
    fi
  done < <(echo "$docs_json" | jq -r '.[]?' 2>/dev/null || true)

  if [ "$changed" -eq 1 ]; then
    git commit -m "$message" 2>/dev/null || true
  fi
}

build_semantic_placeholder_config_json() {
  jq -nc \
    --arg enabled "$EXEC_PLACEHOLDER_SEMANTIC_ENABLED" \
    --arg block_return "$EXEC_PLACEHOLDER_BLOCK_TRIVIAL_CONSTANT_RETURNS" \
    --arg block_conditional "$EXEC_PLACEHOLDER_BLOCK_ALWAYS_TRUE_FALSE_CONDITIONALS" \
    '{
      "enabled": ($enabled | ascii_downcase == "true"),
      "blockTrivialConstantReturns": ($block_return | ascii_downcase == "true"),
      "blockAlwaysTrueFalseConditionals": ($block_conditional | ascii_downcase == "true")
    }'
}

post_replan_checkpoint() {
  local task_id="$1"
  local reason="$2"
  local advisory_result="${3:-UNKNOWN}"
  local verify_failed_count="${4:-0}"
  local proposal_json="${5:-[]}"
  local proposal_block=""

  if [ -n "$proposal_json" ] && [ "$proposal_json" != "[]" ] && [ "$proposal_json" != "null" ]; then
    proposal_block="

### Proposed Task Refresh
\`\`\`json
${proposal_json}
\`\`\`"
  fi

  local body="## 🔁 Replan Checkpoint

**Task:** ${task_id}
**Reason:** ${reason}
**Action:** Run /il_1_plan ${ISSUE_NUMBER} --quick to refresh priorities/decomposition, then resume with /il_2_implement.

Gate mode: ${EXEC_GATE_MODE}
Advisory result: ${advisory_result}
Authoritative verify failures: ${verify_failed_count}${proposal_block}"

  gh issue comment "$ISSUE_NUMBER" --body "$body" 2>/dev/null || true
}

auto_generate_replan_tasks() {
  local task_id="$1"
  local task_uid="$2"
  local task_json="$3"
  local issue_body="$4"
  local issue_memory_bundle="$5"
  local verify_results="$6"
  local stale_reason="$7"
  local max_tasks="${8:-6}"

  local prompt output parsed validated
  prompt=$(cat <<EOF
You are generating a task refresh for a stale implementation loop.

Current task id: ${task_id}
Current task uid: ${task_uid}
Max generated tasks: ${max_tasks}

Current task JSON:
${task_json}

Issue body:
${issue_body}

Issue memory bundle:
${issue_memory_bundle}

Latest authoritative verify results:
${verify_results}

Stale reason:
${stale_reason}

Return a focused replan as JSON only under this exact heading and fence:
### Replan JSON
\`\`\`json
[
  {
    "title": "Short title",
    "description": "2-3 sentence replacement task description",
    "acceptanceCriteria": ["verifiable criterion"],
    "verifyCommands": ["command"],
    "dependsOn": [],
    "files": []
  }
]
\`\`\`

Rules:
- Return 1 to ${max_tasks} tasks.
- No placeholder tasks.
- Keep each task small enough for one iteration.
- Do not include prose outside the JSON block.
EOF
)

  set +e
  output=$(echo "$prompt" | claude --print --dangerously-skip-permissions 2>&1)
  local exit_code=$?
  set -e
  if [ $exit_code -ne 0 ] && [ -z "$output" ]; then
    echo "[]"
    return 0
  fi

  parsed=$(extract_replan_json_from_agent_output "$output" 2>/dev/null || echo "")
  if [ -z "$parsed" ]; then
    echo "[]"
    return 0
  fi

  validated=$(validate_generated_replan_tasks "$parsed" "$max_tasks")
  if [ -z "$validated" ] || [ "$validated" = "null" ]; then
    validated="[]"
  fi
  echo "$validated"
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
  local task_json_render="$task_json"
  [ -n "$task_json_render" ] || task_json_render='{}'

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
${task_json_render}

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
- Each finding MUST include: id, severity(critical|high), confidence(0-1), category(adherence|efficiency|pattern_reuse|production_readiness|security), title, description, evidence(file+line).
- Include suggestedTask ONLY for critical findings.
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

# Extract the ## 🔎 Code Review: block from review agent output and post it as a
# GitHub issue comment so verify_review_log_on_github can find it.
# Args: $1 - full captured output from the review agent
_post_review_to_github() {
  local output="$1"
  local review_block
  review_block=$(printf '%s\n' "$output" | awk '/^## 🔎 Code Review:/{found=1} found{print}')
  if [ -n "$review_block" ]; then
    gh issue comment "$ISSUE_NUMBER" --body "$review_block" 2>/dev/null || true
  fi
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
      _post_review_to_github "$output"
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
  _post_review_to_github "$output"
  if [ $exit_code -ne 0 ] && [ -z "$output" ]; then
    return 1
  fi
  return 0
}

# Ingest posted review events and auto-enqueue configured severities.
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

# Load execution + review policy defaults
load_execution_config "$CONFIG_FILE"
if [ -f "$CONFIG_FILE" ]; then
  REVIEW_ENABLED=$(jq -r '
    if (.review? | type) == "object" and (.review | has("enabled")) then
      (.review.enabled | tostring)
    else
      "true"
    end
  ' "$CONFIG_FILE" 2>/dev/null || echo "true")
  REVIEW_MAX_FINDINGS=$(jq -r '.review.maxFindingsPerReview // 5' "$CONFIG_FILE" 2>/dev/null || echo "5")
fi

MAX_TASK_ATTEMPTS="$EXEC_MAX_TASK_ATTEMPTS"

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
  jq --argjson auto "$(jq -c '.review.autoEnqueueSeverities // ["critical"]' "$CONFIG_FILE" 2>/dev/null || echo '["critical"]')" \
     --argjson approval "$(jq -c '.review.approvalRequiredSeverities // ["high"]' "$CONFIG_FILE" 2>/dev/null || echo '["high"]')" \
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
log "   Max tries:  $MAX_TASK_ATTEMPTS"
log "   Profile:    $EXEC_PROFILE"
log "   Gate mode:  $EXEC_GATE_MODE"
log "   Task size:  $EXEC_TASK_SIZING_ENABLED (hardFail=$EXEC_TASK_SIZING_HARD_FAIL_ON_OVERSIZED)"
log "   Ctx hash:   $EXEC_CONTEXT_MANIFEST_ENABLED (enforce=$EXEC_CONTEXT_MANIFEST_ENFORCE_HASH_MATCH)"
log "   Verify tier: fast+full (cadence=$EXEC_VERIFY_FULL_RUN_EVERY_N_PASSED_TASKS)"
log "   Auto replan: $EXEC_REPLAN_AUTO_GENERATE_ON_STALE (singleApply=$EXEC_REPLAN_AUTO_APPLY_IF_SINGLE_TASK)"
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

        # Inline GitHub posting: read the review output from the log file and post
        # it as a GitHub comment. spawn_task_review_agent calls _post_review_to_github
        # internally, but if the loop was started before that helper was defined (i.e.,
        # the running bash process has an older in-memory function table), the internal
        # call is a no-op. This inline fallback runs in the while-loop body, which bash
        # re-reads from disk each iteration, so it always reflects the current code.
        _fl_review_output=$(awk -v sentinel="--- Review output for FINAL ($HEAD_COMMIT) ---" '
          $0 == sentinel { start=1; next }
          /--- End review output ---/ { if (start) exit }
          start { print }
        ' "$REVIEW_LOG_FILE" 2>/dev/null || echo "")
        _fl_review_block=$(printf '%s\n' "$_fl_review_output" | awk '/^## 🔎 Code Review:/{found=1} found{print}')
        if [ -n "$_fl_review_block" ]; then
          gh issue comment "$ISSUE_NUMBER" --body "$_fl_review_block" 2>/dev/null || true
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

    if [ "$(echo "$EXEC_VERIFY_RUN_FULL_BEFORE_TESTING_CHECKPOINT" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
      FULL_VERIFY_COMMAND_COUNT=$(echo "$EXEC_VERIFY_FULL_GLOBAL_COMMANDS_JSON" | jq -r 'length' 2>/dev/null || echo "0")
      if [ "$FULL_VERIFY_COMMAND_COUNT" -gt 0 ]; then
        log "$ICON_INFO Running full verification gate before testing checkpoint..."
        FULL_VERIFY_RESULTS=$(run_verify_suite \
          '[]' \
          "$EXEC_VERIFY_TIMEOUT_SECONDS" \
          "$EXEC_VERIFY_MAX_OUTPUT_LINES" \
          "$EXEC_VERIFY_FULL_GLOBAL_COMMANDS_JSON" \
          '[]' \
          "false")
        FULL_VERIFY_PASSED=$(echo "$FULL_VERIFY_RESULTS" | jq -r '.allPassed // false' 2>/dev/null || echo "false")
        if [ "$FULL_VERIFY_PASSED" != "true" ]; then
          FULL_FAIL_COUNT=$(echo "$FULL_VERIFY_RESULTS" | jq -r '.failed | length' 2>/dev/null || echo "0")
          mark_replan_required "$PRD_FILE" "full verify failed before testing checkpoint"
          record_auto_replan_audit "$PRD_FILE" "full verify failed before testing checkpoint" "full_verify_failed"
          commit_prd_if_changed "chore: full verify failed before testing checkpoint (#$ISSUE_NUMBER)"
          post_replan_checkpoint "FINAL" "full verify failed before testing checkpoint" "UNKNOWN" "$FULL_FAIL_COUNT" "[]"
          gh issue edit "$ISSUE_NUMBER" --add-label "$EXEC_LABEL_PLANNING" 2>/dev/null || true
          git push 2>/dev/null || true
          exit 1
        fi

        FULL_VERIFY_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "")
        record_full_verify_success "$PRD_FILE" "$FULL_VERIFY_COMMIT"
        commit_prd_if_changed "chore: full verify passed before testing checkpoint (#$ISSUE_NUMBER)"
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
  EXHAUSTED_TASKS=$(jq -r --argjson max_attempts "$MAX_TASK_ATTEMPTS" \
    '[.userStories[] | select(.passes == false and ((.attempts // 0) >= $max_attempts)) | .id] | join(", ")' "$PRD_FILE")

  # Find next executable task (passes=false, not exhausted, all dependencies met, sorted by priority)
  NEXT_TASK=$(jq -r --arg passing "$PASSING_IDS" --argjson max_attempts "$MAX_TASK_ATTEMPTS" '
    ($passing | split(" ")) as $passed_list |
    [.userStories[] |
    select(.passes == false) |
    select((.attempts // 0) < $max_attempts) |
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
    if [ -n "$EXHAUSTED_TASKS" ]; then
      log "$ICON_BLOCKED No executable tasks - attempt budget exhausted for: $EXHAUSTED_TASKS"
      gh issue edit "$ISSUE_NUMBER" --add-label "AI: Blocked" 2>/dev/null || true
    else
      log "$ICON_BLOCKED No executable tasks - dependencies not met or all blocked"
    fi
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

  TASK_SIZING_CHECK=$(validate_task_sizing \
    "$TASK_JSON" \
    "$EXEC_TASK_SIZING_ENABLED" \
    "$EXEC_TASK_SIZING_MAX_DESCRIPTION_SENTENCES" \
    "$EXEC_TASK_SIZING_MAX_ACCEPTANCE_CRITERIA" \
    "$EXEC_TASK_SIZING_MAX_VERIFY_COMMANDS" \
    "$EXEC_TASK_SIZING_MAX_FILES")
  TASK_SIZING_OK=$(echo "$TASK_SIZING_CHECK" | jq -r '.ok // true' 2>/dev/null || echo "true")
  if [ "$TASK_SIZING_OK" != "true" ]; then
    TASK_SIZING_VIOLATIONS=$(echo "$TASK_SIZING_CHECK" | jq -r '.violations // [] | join("; ")' 2>/dev/null || echo "task sizing violations")
    if [ "$(echo "$EXEC_TASK_SIZING_HARD_FAIL_ON_OVERSIZED" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
      log "$ICON_WARN Task sizing gate failed for $NEXT_TASK: $TASK_SIZING_VIOLATIONS"
      mark_replan_required "$PRD_FILE" "task sizing exceeded limits for $NEXT_TASK"
      record_auto_replan_audit "$PRD_FILE" "task sizing exceeded limits for $NEXT_TASK" "replan_required"
      commit_prd_if_changed "chore: task sizing gate failed - replan required (#$ISSUE_NUMBER)"
      post_replan_checkpoint "$NEXT_TASK" "task sizing exceeded limits for $NEXT_TASK" "UNKNOWN" "0" "[]"
      gh issue edit "$ISSUE_NUMBER" --add-label "$EXEC_LABEL_PLANNING" 2>/dev/null || true
      git push 2>/dev/null || true
      exit 1
    else
      log "$ICON_WARN Task sizing advisory for $NEXT_TASK: $TASK_SIZING_VIOLATIONS"
    fi
  fi

  TASK_BROWSER_REQUIRED=$(task_requires_browser_verification "$TASK_JSON" "$EXEC_BROWSER_REQUIRED_FOR_UI")
  BROWSER_ALLOWED_TOOLS=$(echo "$EXEC_BROWSER_ALLOWED_TOOLS_JSON" | jq -r 'join(", ")' 2>/dev/null || echo "playwright, dev-browser")
  BROWSER_PROMPT=""
  if [ "$TASK_BROWSER_REQUIRED" = "true" ]; then
    BROWSER_PROMPT="
=== REQUIRED BROWSER VERIFICATION ===
This task requires browser verification.
1. Verify the changed UX in browser using one of: ${BROWSER_ALLOWED_TOOLS}
2. Post a dedicated comment to issue #$ISSUE_NUMBER:
   Header: ## 🌐 Browser Verification: $NEXT_TASK
3. Include Browser Event JSON exactly as:
### Browser Event JSON
\`\`\`json
{\"v\":1,\"type\":\"browser_verification\",\"issue\":$ISSUE_NUMBER,\"taskId\":\"$NEXT_TASK\",\"taskUid\":\"$TASK_UID\",\"tool\":\"playwright\",\"status\":\"passed\",\"artifacts\":[\"screenshot:/abs/path.png\"],\"ts\":\"<ISO 8601>\"}
\`\`\`
"
  fi

  # 2. Get recent git commits (last 10)
  GIT_LOG=$(git log --oneline -10 2>/dev/null || echo "No git history available")

  # 3. Get issue body and compact memory bundle (comments are the memory system)
  ISSUE_BODY=$(gh issue view "$ISSUE_NUMBER" --json body --jq '.body' 2>/dev/null || echo "Could not fetch issue body")
  ISSUE_MEMORY_BUNDLE=$(build_issue_context_bundle "$ISSUE_NUMBER" "$EXEC_CONTEXT_PREFER_COMPACTED" "$EXEC_CONTEXT_MAX_TASK_LOGS" "$EXEC_CONTEXT_MAX_DISCOVERY_NOTES" "$EXEC_CONTEXT_MAX_REVIEW_LOGS")

  # 4. Get list of files in repo (for context on codebase structure)
  REPO_STRUCTURE=$(find . -type f -name "*.ts" -o -name "*.js" -o -name "*.tsx" -o -name "*.jsx" -o -name "*.py" -o -name "*.go" -o -name "*.rs" 2>/dev/null | grep -v node_modules | grep -v ".git" | head -50 || echo "Could not list files")

  # 5. Collect active (non-expired) wisps for ephemeral context
  ACTIVE_WISPS=$(collect_active_wisps "$ISSUE_NUMBER" 2>/dev/null || echo "")

  CONTEXT_MANIFEST_JSON="{}"
  CONTEXT_MANIFEST_HASH=""
  CONTEXT_MANIFEST_PROMPT=""
  EVENT_CONTEXT_MANIFEST_SAMPLE=""
  if [ "$(echo "$EXEC_CONTEXT_MANIFEST_ENABLED" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
    CONTEXT_MANIFEST_JSON=$(build_context_manifest \
      "$TASK_JSON" \
      "$ISSUE_BODY" \
      "$ISSUE_MEMORY_BUNDLE" \
      "$GIT_LOG" \
      "$REPO_STRUCTURE" \
      "$ACTIVE_WISPS")
    CONTEXT_MANIFEST_HASH=$(compute_context_manifest_hash "$CONTEXT_MANIFEST_JSON" "$EXEC_CONTEXT_MANIFEST_ALGORITHM")
    CONTEXT_MANIFEST_PROMPT="
=== CONTEXT MANIFEST ===
Algorithm: ${EXEC_CONTEXT_MANIFEST_ALGORITHM}
Hash: ${CONTEXT_MANIFEST_HASH}
You MUST echo this in Event JSON:
\"contextManifest\":{\"hash\":\"${CONTEXT_MANIFEST_HASH}\",\"algorithm\":\"${EXEC_CONTEXT_MANIFEST_ALGORITHM}\"}"
    EVENT_CONTEXT_MANIFEST_SAMPLE=",\"contextManifest\":{\"hash\":\"${CONTEXT_MANIFEST_HASH}\",\"algorithm\":\"${EXEC_CONTEXT_MANIFEST_ALGORITHM}\"}"
  fi

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

Issue Memory Bundle (compacted, high-signal):
$ISSUE_MEMORY_BUNDLE

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
${CONTEXT_MANIFEST_PROMPT}

=== INSTRUCTIONS ===
1. Review the task details above (acceptanceCriteria, verifyCommands, files to modify)
2. Use the issue body + memory bundle for requirements and learnings
3. Check git history for patterns and recent changes
4. Before making changes, search the codebase with at least $EXEC_SEARCH_MIN_QUERIES queries; do not assume missing implementation
5. Implement the required changes for this task only
6. You may run local checks, but the orchestrator will run authoritative verify commands
7. Stage and commit implementation changes when appropriate (do not mutate prd.json pass/fail state)
8. Post a task log comment to GitHub issue #$ISSUE_NUMBER using: gh issue comment $ISSUE_NUMBER --body \"...\"
9. Include Event JSON with taskUid=$TASK_UID and a search evidence block
$BROWSER_PROMPT

CRITICAL:
- Do NOT set task pass/fail in prd.json. The orchestrator updates attempts/passes authoritatively.
- Do NOT increment attempts in prd.json.
- Do NOT emit placeholder/stub implementations.

=== JSON EVENT EMISSION ===
Your task log comment MUST include a '### Event JSON' section with a single
fenced json code block containing a compact JSON event object. Place this at
the end of the task log comment. Format:

\`\`\`
### Event JSON
\\\`\\\`\\\`json
{\"v\":1,\"type\":\"task_log\",\"issue\":$ISSUE_NUMBER,\"taskId\":\"$NEXT_TASK\",\"taskUid\":\"$TASK_UID\",\"status\":\"pass\",\"attempt\":<N>,\"commit\":\"<hash>\",\"verify\":{\"passed\":[...],\"failed\":[...]},\"verifyTier\":\"fast\",\"search\":{\"queries\":[\"rg -n \\\"pattern\\\" src\"],\"filesInspected\":[\"path/to/file\"]}${EVENT_CONTEXT_MANIFEST_SAMPLE},\"testIntent\":[{\"test\":\"tests/module.spec.ts::handles edge case\",\"why\":\"Prevents regression for stale retry path\"}],\"patterns\":[{\"statement\":\"When changing X, also update Y\",\"scope\":\"src/module\",\"files\":[\"src/module/a.ts\"],\"confidence\":0.9}],\"discovered\":[],\"ts\":\"<ISO 8601>\"}
\\\`\\\`\\\`
\`\`\`

The 'discovered' array should contain any new tasks found during implementation
(empty array if none). Each discovered task object needs: title, description,
acceptanceCriteria, verifyCommands, and dependsOn.
The 'patterns' array is optional but recommended for reusable insights.

Output guidance:
- End your response with one advisory tag: <result>PASS</result>, <result>RETRY</result>, or <result>BLOCKED</result>.
- The orchestrator computes canonical outcome using authoritative verification."

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

  # Advisory model output tag (canonical task state comes from orchestrator gates).
  ADVISORY_RESULT=$(echo "$OUTPUT" | grep -oiE '<result>\s*(PASS|RETRY|BLOCKED)\s*</result>' | tail -1 | sed 's/<[^>]*>//g' | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
  if [ -z "$ADVISORY_RESULT" ]; then
    ADVISORY_RESULT="UNKNOWN"
  fi

  # ─── Post-task orchestration: verify task log, run gates, and update state ───
  PARSED_EVENT=$(verify_task_log_on_github "$ISSUE_NUMBER" "$NEXT_TASK" "$TASK_UID" 2>/dev/null || echo "")
  EVENT_VERIFIED=0
  PATTERN_SYNC_DOCS='[]'
  PATTERN_SYNC_CHANGED="false"
  if [ -n "$PARSED_EVENT" ] && [ "$PARSED_EVENT" != "null" ]; then
    EVENT_VERIFIED=1

    DISCOVERED_JSON=$(echo "$PARSED_EVENT" | jq -c '[.discovered[]? // empty]' 2>/dev/null || echo "[]")
    if [ -n "$DISCOVERED_JSON" ] && [ "$DISCOVERED_JSON" != "[]" ] && [ "$DISCOVERED_JSON" != "null" ]; then
      log "Discovered tasks found, enqueuing..."
      enqueue_discovered_tasks "$PRD_FILE" "$NEXT_TASK" "$TASK_UID" "$TASK_PRIORITY" "$DISCOVERED_JSON" "$ISSUE_NUMBER"
      log "$ICON_SUCCESS Discovered tasks enqueued"
    fi

    ALL_NEW_PATTERNS_JSON='[]'

    NEW_PATTERNS_JSON=$(ingest_task_patterns_into_prd "$PRD_FILE" "$PARSED_EVENT" "$ISSUE_NUMBER" "$MEMORY_MAX_PATTERNS_PER_TASK")
    if [ -n "$NEW_PATTERNS_JSON" ] && [ "$NEW_PATTERNS_JSON" != "[]" ] && [ "$NEW_PATTERNS_JSON" != "null" ]; then
      ALL_NEW_PATTERNS_JSON=$(echo "$ALL_NEW_PATTERNS_JSON" | jq -c --argjson incoming "$NEW_PATTERNS_JSON" '. + $incoming' 2>/dev/null || echo "$NEW_PATTERNS_JSON")
    fi

    TEST_INTENT_PATTERNS=$(convert_test_intent_to_patterns "$PARSED_EVENT")
    if [ -n "$TEST_INTENT_PATTERNS" ] && [ "$TEST_INTENT_PATTERNS" != "[]" ] && [ "$TEST_INTENT_PATTERNS" != "null" ]; then
      SYNTH_EVENT=$(echo "$PARSED_EVENT" | jq -c --argjson pats "$TEST_INTENT_PATTERNS" '.patterns = $pats' 2>/dev/null || echo "")
      if [ -n "$SYNTH_EVENT" ]; then
        NEW_TEST_INTENT_PATTERNS=$(ingest_task_patterns_into_prd "$PRD_FILE" "$SYNTH_EVENT" "$ISSUE_NUMBER" "$MEMORY_MAX_PATTERNS_PER_TASK")
        if [ -n "$NEW_TEST_INTENT_PATTERNS" ] && [ "$NEW_TEST_INTENT_PATTERNS" != "[]" ] && [ "$NEW_TEST_INTENT_PATTERNS" != "null" ]; then
          ALL_NEW_PATTERNS_JSON=$(echo "$ALL_NEW_PATTERNS_JSON" | jq -c --argjson incoming "$NEW_TEST_INTENT_PATTERNS" '. + $incoming' 2>/dev/null || echo "$ALL_NEW_PATTERNS_JSON")
        fi
      fi
    fi

    if [ -n "$ALL_NEW_PATTERNS_JSON" ] && [ "$ALL_NEW_PATTERNS_JSON" != "[]" ] && [ "$ALL_NEW_PATTERNS_JSON" != "null" ]; then
      SYNC_RESULT=$(sync_task_patterns_to_docs \
        "$PRD_FILE" \
        "$ISSUE_NUMBER" \
        "$NEXT_TASK" \
        "$TASK_UID" \
        "$(echo "$PARSED_EVENT" | jq -r '.commit // ""' 2>/dev/null)" \
        "$ALL_NEW_PATTERNS_JSON" \
        "$MEMORY_AUTO_SYNC_DOCS" \
        "$MEMORY_MIN_CONFIDENCE" \
        "$MEMORY_DOC_TARGETS_JSON" \
        "$MEMORY_MANAGED_SECTION_MARKER")
      PATTERN_SYNC_CHANGED=$(echo "$SYNC_RESULT" | jq -r '.docsChanged // false' 2>/dev/null || echo "false")
      PATTERN_SYNC_DOCS=$(echo "$SYNC_RESULT" | jq -c '.syncedDocs // []' 2>/dev/null || echo "[]")
      if [ "$PATTERN_SYNC_CHANGED" = "true" ]; then
        log "$ICON_SUCCESS Synced pattern memory to docs."
        commit_pattern_sync_if_changed "chore: sync pattern memory for $NEXT_TASK (#$ISSUE_NUMBER)" "$PATTERN_SYNC_DOCS"
      else
        commit_prd_if_changed "chore: ingest pattern memory for $NEXT_TASK (#$ISSUE_NUMBER)"
      fi
    fi
  else
    log "$ICON_WARN Task log not found on GitHub — comment may have failed to post."
  fi

  VERIFY_COMMANDS_JSON=$(echo "$TASK_JSON" | jq -c '.verifyCommands // []' 2>/dev/null || echo "[]")
  FAST_VERIFY_RESULTS=$(run_verify_suite \
    "$VERIFY_COMMANDS_JSON" \
    "$EXEC_VERIFY_TIMEOUT_SECONDS" \
    "$EXEC_VERIFY_MAX_OUTPUT_LINES" \
    "$EXEC_VERIFY_FAST_GLOBAL_COMMANDS_JSON" \
    "$EXEC_VERIFY_SECURITY_COMMANDS_JSON" \
    "$EXEC_VERIFY_RUN_SECURITY_EACH")
  FAST_VERIFY_PASSED=$(echo "$FAST_VERIFY_RESULTS" | jq -r '.allPassed // false' 2>/dev/null || echo "false")
  FAST_VERIFY_FAILED_COUNT=$(echo "$FAST_VERIFY_RESULTS" | jq -r '.failed | length' 2>/dev/null || echo "0")

  FULL_VERIFY_RESULTS='{"commands":[],"passed":[],"failed":[],"allPassed":true}'
  FULL_VERIFY_PASSED="true"
  FULL_VERIFY_FAILED_COUNT=0
  FULL_VERIFY_DUE="false"
  TASKS_SINCE_FULL_VERIFY=$(jq -r '.quality.execution.tasksSinceFullVerify // 0' "$PRD_FILE")
  FULL_VERIFY_COMMAND_COUNT=$(echo "$EXEC_VERIFY_FULL_GLOBAL_COMMANDS_JSON" | jq -r 'length' 2>/dev/null || echo "0")
  if [ "$FULL_VERIFY_COMMAND_COUNT" -gt 0 ] && [ "$EXEC_VERIFY_FULL_RUN_EVERY_N_PASSED_TASKS" -gt 0 ]; then
    NEXT_FULL_COUNTER=$((TASKS_SINCE_FULL_VERIFY + 1))
    if [ "$NEXT_FULL_COUNTER" -ge "$EXEC_VERIFY_FULL_RUN_EVERY_N_PASSED_TASKS" ]; then
      FULL_VERIFY_DUE="true"
    fi
  fi

  if [ "$FAST_VERIFY_PASSED" = "true" ] && [ "$FULL_VERIFY_DUE" = "true" ]; then
    log "$ICON_INFO Running full verification cadence for $NEXT_TASK..."
    FULL_VERIFY_RESULTS=$(run_verify_suite \
      '[]' \
      "$EXEC_VERIFY_TIMEOUT_SECONDS" \
      "$EXEC_VERIFY_MAX_OUTPUT_LINES" \
      "$EXEC_VERIFY_FULL_GLOBAL_COMMANDS_JSON" \
      '[]' \
      "false")
    FULL_VERIFY_PASSED=$(echo "$FULL_VERIFY_RESULTS" | jq -r '.allPassed // false' 2>/dev/null || echo "false")
    FULL_VERIFY_FAILED_COUNT=$(echo "$FULL_VERIFY_RESULTS" | jq -r '.failed | length' 2>/dev/null || echo "0")
  fi

  VERIFY_PASSED="true"
  if [ "$FAST_VERIFY_PASSED" != "true" ] || [ "$FULL_VERIFY_PASSED" != "true" ]; then
    VERIFY_PASSED="false"
  fi
  VERIFY_FAILED_COUNT=$((FAST_VERIFY_FAILED_COUNT + FULL_VERIFY_FAILED_COUNT))
  VERIFY_RESULTS=$(jq -nc --argjson fast "$FAST_VERIFY_RESULTS" --argjson full "$FULL_VERIFY_RESULTS" '
    {"fast":$fast,"full":$full}
  ')
  if [ "$VERIFY_FAILED_COUNT" -gt 0 ]; then
    log "$ICON_WARN Authoritative verification reported $VERIFY_FAILED_COUNT failing command(s)."
  fi

  EVENT_OK="true"
  if [ "$(echo "$EXEC_EVENT_REQUIRED" | tr '[:upper:]' '[:lower:]')" = "true" ] && [ "$EVENT_VERIFIED" -ne 1 ]; then
    EVENT_OK="false"
  fi

  CONTEXT_MANIFEST_OK="true"
  CONTEXT_MANIFEST_REASON=""
  if [ "$(echo "$EXEC_CONTEXT_MANIFEST_ENABLED" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
    CONTEXT_MANIFEST_CHECK=$(validate_context_manifest_evidence \
      "$PARSED_EVENT" \
      "$CONTEXT_MANIFEST_HASH" \
      "$EXEC_CONTEXT_MANIFEST_ALGORITHM" \
      "true")
    CONTEXT_MANIFEST_OK=$(echo "$CONTEXT_MANIFEST_CHECK" | jq -r '.ok // false' 2>/dev/null || echo "false")
    CONTEXT_MANIFEST_REASON=$(echo "$CONTEXT_MANIFEST_CHECK" | jq -r '.reason // ""' 2>/dev/null || echo "")
  fi

  BROWSER_EVENT_JSON=""
  BROWSER_OK="true"
  if [ "$TASK_BROWSER_REQUIRED" = "true" ]; then
    BROWSER_EVENT_JSON=$(verify_browser_verification_on_github "$ISSUE_NUMBER" "$NEXT_TASK" "$TASK_UID" "$EXEC_BROWSER_ALLOWED_TOOLS_JSON" 2>/dev/null || echo "")
    if [ -z "$BROWSER_EVENT_JSON" ] || [ "$BROWSER_EVENT_JSON" = "null" ]; then
      BROWSER_OK="false"
    fi
  fi

  SEARCH_CHECK=$(validate_search_evidence "$PARSED_EVENT" "$EXEC_SEARCH_MIN_QUERIES" "$EXEC_SEARCH_REQUIRED")
  SEARCH_OK=$(echo "$SEARCH_CHECK" | jq -r '.ok // false' 2>/dev/null || echo "false")
  SEARCH_REASON=$(echo "$SEARCH_CHECK" | jq -r '.reason // ""' 2>/dev/null || echo "")

  PLACEHOLDER_MATCHES='[]'
  PLACEHOLDER_COUNT=0
  SCAN_TARGET=$(echo "$PARSED_EVENT" | jq -r '.commit // empty' 2>/dev/null || echo "")
  if [ -z "$SCAN_TARGET" ]; then
    SCAN_TARGET="WORKTREE"
  fi

  TEST_CHANGED_FILES_JSON=$(detect_changed_test_files "$SCAN_TARGET")
  TEST_CHANGED_COUNT=$(echo "$TEST_CHANGED_FILES_JSON" | jq -r 'length' 2>/dev/null || echo "0")
  TEST_INTENT_OK="true"
  TEST_INTENT_REASON=""
  if [ "$(echo "$EXEC_TEST_INTENT_REQUIRED_WHEN_TESTS_CHANGED" | tr '[:upper:]' '[:lower:]')" = "true" ] && [ "$TEST_CHANGED_COUNT" -gt 0 ]; then
    TEST_INTENT_CHECK=$(validate_test_intent_evidence "$PARSED_EVENT")
    TEST_INTENT_OK=$(echo "$TEST_INTENT_CHECK" | jq -r '.ok // false' 2>/dev/null || echo "false")
    TEST_INTENT_REASON=$(echo "$TEST_INTENT_CHECK" | jq -r '.reason // ""' 2>/dev/null || echo "")
  fi

  if [ "$(echo "$EXEC_PLACEHOLDER_ENABLED" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
    SEMANTIC_PLACEHOLDER_CONFIG=$(build_semantic_placeholder_config_json)
    PLACEHOLDER_MATCHES=$(scan_placeholder_patterns "$SCAN_TARGET" "$EXEC_PLACEHOLDER_PATTERNS_JSON" "$EXEC_PLACEHOLDER_EXCLUDE_REGEX_JSON" "$SEMANTIC_PLACEHOLDER_CONFIG")
    PLACEHOLDER_COUNT=$(echo "$PLACEHOLDER_MATCHES" | jq -r 'length' 2>/dev/null || echo "0")
  fi

  GUARD_FAIL_COUNT=0
  if [ "$EVENT_OK" != "true" ]; then
    GUARD_FAIL_COUNT=$((GUARD_FAIL_COUNT + 1))
    if [ "$(echo "$EXEC_GATE_MODE" | tr '[:upper:]' '[:lower:]')" = "enforce" ]; then
      log "$ICON_WARN Event evidence gate failed: missing verified task log event on GitHub."
    else
      log "$ICON_WARN Event evidence advisory: missing verified task log event on GitHub."
    fi
  fi
  if [ "$(echo "$EXEC_CONTEXT_MANIFEST_ENABLED" | tr '[:upper:]' '[:lower:]')" = "true" ] && [ "$CONTEXT_MANIFEST_OK" != "true" ]; then
    if [ "$(echo "$EXEC_CONTEXT_MANIFEST_ENFORCE_HASH_MATCH" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
      GUARD_FAIL_COUNT=$((GUARD_FAIL_COUNT + 1))
      log "$ICON_WARN Context manifest gate failed: $CONTEXT_MANIFEST_REASON"
    else
      log "$ICON_WARN Context manifest advisory: $CONTEXT_MANIFEST_REASON"
    fi
  fi
  if [ "$SEARCH_OK" != "true" ]; then
    GUARD_FAIL_COUNT=$((GUARD_FAIL_COUNT + 1))
    if [ "$(echo "$EXEC_GATE_MODE" | tr '[:upper:]' '[:lower:]')" = "enforce" ]; then
      log "$ICON_WARN Search evidence gate failed: $SEARCH_REASON"
    else
      log "$ICON_WARN Search evidence advisory: $SEARCH_REASON"
    fi
  fi
  if [ "$PLACEHOLDER_COUNT" -gt 0 ]; then
    GUARD_FAIL_COUNT=$((GUARD_FAIL_COUNT + 1))
    if [ "$(echo "$EXEC_GATE_MODE" | tr '[:upper:]' '[:lower:]')" = "enforce" ]; then
      log "$ICON_WARN Placeholder gate failed: $PLACEHOLDER_COUNT risky addition(s) detected."
    else
      log "$ICON_WARN Placeholder advisory: $PLACEHOLDER_COUNT risky addition(s) detected."
    fi
  fi
  if [ "$TASK_BROWSER_REQUIRED" = "true" ] && [ "$BROWSER_OK" != "true" ]; then
    GUARD_FAIL_COUNT=$((GUARD_FAIL_COUNT + 1))
    if [ "$(echo "$EXEC_GATE_MODE" | tr '[:upper:]' '[:lower:]')" = "enforce" ]; then
      log "$ICON_WARN Browser verification gate failed: missing valid browser verification event."
    else
      log "$ICON_WARN Browser verification advisory: missing valid browser verification event."
    fi
  fi
  if [ "$TEST_CHANGED_COUNT" -gt 0 ] && [ "$TEST_INTENT_OK" != "true" ]; then
    if [ "$(echo "$EXEC_TEST_INTENT_ENFORCE" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
      GUARD_FAIL_COUNT=$((GUARD_FAIL_COUNT + 1))
      log "$ICON_WARN Test intent gate failed: $TEST_INTENT_REASON"
    else
      log "$ICON_WARN Test intent advisory: $TEST_INTENT_REASON"
    fi
  fi

  CANONICAL_PASS="$VERIFY_PASSED"
  if [ "$(echo "$EXEC_GATE_MODE" | tr '[:upper:]' '[:lower:]')" = "enforce" ] && [ "$GUARD_FAIL_COUNT" -gt 0 ]; then
    CANONICAL_PASS="false"
  fi
  if [ "$TASK_BROWSER_REQUIRED" = "true" ] &&
     [ "$(echo "$EXEC_BROWSER_HARD_FAIL_WHEN_UNAVAILABLE" | tr '[:upper:]' '[:lower:]')" = "true" ] &&
     [ "$BROWSER_OK" != "true" ]; then
    CANONICAL_PASS="false"
  fi

  ATTEMPT_NUMBER=$(update_task_state_authoritative "$PRD_FILE" "$NEXT_TASK" "$CANONICAL_PASS")

  if [ "$CANONICAL_PASS" = "true" ]; then
    update_execution_retry_counters "$PRD_FILE" "$NEXT_TASK" "pass" >/dev/null
    if [ "$FULL_VERIFY_DUE" = "true" ]; then
      PASS_COMMIT=$(echo "$PARSED_EVENT" | jq -r '.commit // ""' 2>/dev/null || echo "")
      if [ -z "$PASS_COMMIT" ] || [ "$PASS_COMMIT" = "null" ]; then
        PASS_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "")
      fi
      record_full_verify_success "$PRD_FILE" "$PASS_COMMIT"
    else
      increment_tasks_since_full_verify "$PRD_FILE"
    fi
    commit_prd_if_changed "chore: update prd.json - $NEXT_TASK passed (#$ISSUE_NUMBER)"

    log ""
    log "$LINE_HEAVY"
    log "$ICON_SUCCESS $NEXT_TASK passed (authoritative verification)."
    log "$LINE_HEAVY"

    if [ "$EVENT_VERIFIED" -eq 1 ]; then
      maybe_post_compaction_summary "$PRD_FILE" "$ISSUE_NUMBER" "$NEXT_TASK" "$TASK_UID" "$ATTEMPT_NUMBER"
      if [ "$REVIEW_ENABLED" = "true" ]; then
        REVIEW_COMMIT=$(echo "$PARSED_EVENT" | jq -r '.commit // ""' 2>/dev/null)
        if [ -z "$REVIEW_COMMIT" ] || [ "$REVIEW_COMMIT" = "null" ]; then
          REVIEW_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "")
        fi
        spawn_task_review_agent "$NEXT_TASK" "task" "$NEXT_TASK" "$TASK_UID" "$REVIEW_COMMIT" "$TASK_JSON" "async"
      fi
    fi

    git push 2>/dev/null || true
    continue
  fi

  update_execution_retry_counters "$PRD_FILE" "$NEXT_TASK" "retry" >/dev/null
  commit_prd_if_changed "chore: update prd.json - $NEXT_TASK attempt $ATTEMPT_NUMBER failed (#$ISSUE_NUMBER)"

  if [ "$EVENT_VERIFIED" -eq 1 ]; then
    maybe_post_compaction_summary "$PRD_FILE" "$ISSUE_NUMBER" "$NEXT_TASK" "$TASK_UID" "$ATTEMPT_NUMBER"
  fi

  if [ "$(echo "$EXEC_STALE_ENABLED" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
    STALE_REASON=$(should_trigger_stale_plan "$PRD_FILE" "$EXEC_STALE_SAME_TASK_THRESHOLD" "$EXEC_STALE_CONSECUTIVE_THRESHOLD")
    if [ -n "$STALE_REASON" ]; then
      log "$ICON_WARN Stale-plan checkpoint triggered: $STALE_REASON"
      if [ "$(echo "$EXEC_REPLAN_AUTO_GENERATE_ON_STALE" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
        AUTO_REPLAN_TASKS=$(auto_generate_replan_tasks \
          "$NEXT_TASK" \
          "$TASK_UID" \
          "$TASK_JSON" \
          "$ISSUE_BODY" \
          "$ISSUE_MEMORY_BUNDLE" \
          "$VERIFY_RESULTS" \
          "$STALE_REASON" \
          "$EXEC_REPLAN_MAX_GENERATED_TASKS")
        AUTO_REPLAN_COUNT=$(echo "$AUTO_REPLAN_TASKS" | jq -r 'length' 2>/dev/null || echo "0")

        if [ "$AUTO_REPLAN_COUNT" -eq 1 ] && [ "$(echo "$EXEC_REPLAN_AUTO_APPLY_IF_SINGLE_TASK" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
          log "$ICON_INFO Auto-replan produced one replacement task. Applying in place for $NEXT_TASK."
          REPLACEMENT_TASK=$(echo "$AUTO_REPLAN_TASKS" | jq -c '.[0]' 2>/dev/null || echo "{}")
          apply_auto_replan_single_task "$PRD_FILE" "$NEXT_TASK" "$REPLACEMENT_TASK"
          jq '.quality.execution.consecutiveRetries = 0 |
              .quality.execution.currentTaskRetryStreak = 0 |
              .quality.execution.currentTaskId = null' "$PRD_FILE" > tmp.$$.json && mv tmp.$$.json "$PRD_FILE"
          record_auto_replan_audit "$PRD_FILE" "$STALE_REASON" "applied_single"
          commit_prd_if_changed "chore: auto-replan applied replacement for $NEXT_TASK (#$ISSUE_NUMBER)"
          post_replan_checkpoint "$NEXT_TASK" "$STALE_REASON (auto-applied single replacement)" "$ADVISORY_RESULT" "$VERIFY_FAILED_COUNT" "$AUTO_REPLAN_TASKS"
          git push 2>/dev/null || true
          continue
        fi

        if [ "$AUTO_REPLAN_COUNT" -gt 0 ]; then
          mark_replan_required "$PRD_FILE" "$STALE_REASON"
          record_auto_replan_audit "$PRD_FILE" "$STALE_REASON" "proposal_posted"
          commit_prd_if_changed "chore: stale-plan auto-replan proposal posted (#$ISSUE_NUMBER)"
          post_replan_checkpoint "$NEXT_TASK" "$STALE_REASON" "$ADVISORY_RESULT" "$VERIFY_FAILED_COUNT" "$AUTO_REPLAN_TASKS"
          gh issue edit "$ISSUE_NUMBER" --add-label "$EXEC_LABEL_PLANNING" 2>/dev/null || true
          git push 2>/dev/null || true
          exit 1
        fi

        mark_replan_required "$PRD_FILE" "$STALE_REASON"
        record_auto_replan_audit "$PRD_FILE" "$STALE_REASON" "generation_failed"
        commit_prd_if_changed "chore: stale-plan checkpoint - replan required (#$ISSUE_NUMBER)"
        post_replan_checkpoint "$NEXT_TASK" "$STALE_REASON" "$ADVISORY_RESULT" "$VERIFY_FAILED_COUNT" "[]"
        gh issue edit "$ISSUE_NUMBER" --add-label "$EXEC_LABEL_PLANNING" 2>/dev/null || true
        git push 2>/dev/null || true
        exit 1
      fi

      mark_replan_required "$PRD_FILE" "$STALE_REASON"
      record_auto_replan_audit "$PRD_FILE" "$STALE_REASON" "manual_replan_required"
      commit_prd_if_changed "chore: stale-plan checkpoint - replan required (#$ISSUE_NUMBER)"
      post_replan_checkpoint "$NEXT_TASK" "$STALE_REASON" "$ADVISORY_RESULT" "$VERIFY_FAILED_COUNT" "[]"
      gh issue edit "$ISSUE_NUMBER" --add-label "$EXEC_LABEL_PLANNING" 2>/dev/null || true
      git push 2>/dev/null || true
      exit 1
    fi
  fi

  if [ "$ATTEMPT_NUMBER" -ge "$MAX_TASK_ATTEMPTS" ] || [ "$ADVISORY_RESULT" = "BLOCKED" ]; then
    update_execution_retry_counters "$PRD_FILE" "$NEXT_TASK" "blocked" >/dev/null
    commit_prd_if_changed "chore: update prd.json - $NEXT_TASK blocked (#$ISSUE_NUMBER)"
    log ""
    log "$LINE_HEAVY"
    log "$ICON_BLOCKED $NEXT_TASK blocked after $ATTEMPT_NUMBER attempt(s)"
    log "$LINE_HEAVY"
    log ""
    log "Human input needed. Add guidance to the issue, then run /implement."
    gh issue edit "$ISSUE_NUMBER" --add-label "AI: Blocked" 2>/dev/null || true
    git push 2>/dev/null || true
    exit 1
  fi

  log ""
  log "$ICON_RETRY $NEXT_TASK failed authoritative checks; retrying..."
  log "   Advisory model result: $ADVISORY_RESULT"
  git push 2>/dev/null || true
done

log ""
log "$LINE_HEAVY"
log "$ICON_WARN Max iterations ($MAX_ITERATIONS) reached"
log "$LINE_HEAVY"
exit 1

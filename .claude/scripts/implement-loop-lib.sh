#!/bin/bash
# implement-loop-lib.sh - Helper functions for the implementation loop
#
# Sourceable library containing uid generation, JSON event extraction,
# and backward-compatibility initialization for prd.json.
#
# Usage: source "$(dirname "$0")/implement-loop-lib.sh"

# ═══════════════════════════════════════════════════════════════════════════════
# UID Generation
# ═══════════════════════════════════════════════════════════════════════════════

# Generate a deterministic task uid from issueNumber + normalizedTitle +
# discoveredFrom + ordinal. No timestamp component.
#
# Args:
#   $1 - issueNumber (e.g., "42")
#   $2 - task title (will be normalized: lowercase, trimmed, whitespace-collapsed)
#   $3 - discoveredFrom uid or "null" for planned tasks
#   $4 - ordinal (1-based position within parent scope)
#
# Output: tsk_ followed by 12-char hex hash
generate_task_uid() {
  local issue_number="$1"
  local title="$2"
  local discovered_from="$3"
  local ordinal="$4"

  # Normalize title: lowercase, trim leading/trailing whitespace, collapse internal whitespace
  local normalized_title
  normalized_title=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[[:space:]]\{1,\}/ /g')

  local input="${issue_number}|${normalized_title}|${discovered_from}|${ordinal}"
  local hash
  hash=$(echo -n "$input" | shasum -a 256 | cut -c1-12)

  echo "tsk_${hash}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# JSON Event Extraction
# ═══════════════════════════════════════════════════════════════════════════════

# Extract JSON event blocks from issue comments.
# Parses only fenced json code blocks that appear under '### Event JSON'
# headings. Ignores all other JSON in comments.
#
# Args:
#   $1 - raw issue comments text (from gh issue view)
#
# Output: one JSON object per line (compact), only from Event JSON sections
extract_json_events_from_issue_comments() {
  local comments="$1"

  # State machine: look for '### Event JSON' heading, then capture the next
  # fenced json block (```json ... ```)
  local in_event_section=0
  local in_json_block=0
  local json_buffer=""

  while IFS= read -r line; do
    # Check for ### Event JSON heading
    if echo "$line" | grep -q '### Event JSON'; then
      in_event_section=1
      in_json_block=0
      json_buffer=""
      continue
    fi

    # If we're in the Event JSON section, look for fenced json block
    if [ "$in_event_section" -eq 1 ]; then
      # Opening fence: ```json
      if echo "$line" | grep -qE '^\s*```json\s*$'; then
        in_json_block=1
        json_buffer=""
        continue
      fi

      # Closing fence: ```
      if [ "$in_json_block" -eq 1 ] && echo "$line" | grep -qE '^\s*```\s*$'; then
        # Emit the captured JSON if it's valid
        if [ -n "$json_buffer" ]; then
          # Validate JSON before emitting
          if echo "$json_buffer" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
            echo "$json_buffer"
          fi
        fi
        in_json_block=0
        in_event_section=0
        continue
      fi

      # Accumulate lines inside the json block
      if [ "$in_json_block" -eq 1 ]; then
        json_buffer="${json_buffer}${line}"
        continue
      fi

      # If we hit another heading or separator, leave the event section
      if echo "$line" | grep -qE '^#{1,4} |^---'; then
        in_event_section=0
        in_json_block=0
        json_buffer=""
      fi
    fi
  done <<< "$comments"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Backward-Compatible Initialization
# ═══════════════════════════════════════════════════════════════════════════════

# Initialize missing fields in prd.json to safe defaults.
# Handles legacy prd.json files that lack formula, compaction, quality, or
# per-story uid/discoveredFrom/discoverySource fields.
#
# Args:
#   $1 - path to prd.json (default: "prd.json")
#
# Side effects: overwrites prd.json in place if changes are needed
initialize_missing_prd_fields() {
  local prd_file="${1:-prd.json}"

  if [ ! -f "$prd_file" ]; then
    return 1
  fi

  local issue_number
  issue_number=$(jq -r '.issueNumber // 0' "$prd_file")

  local needs_update=0
  local tmp_file
  tmp_file=$(mktemp)

  # Start with the current prd.json content
  cp "$prd_file" "$tmp_file"

  # Initialize missing root-level formula field (default: "feature")
  if jq -e '.formula' "$tmp_file" >/dev/null 2>&1; then
    : # formula exists
  else
    jq '.formula = "feature"' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi

  # Initialize missing root-level compaction field
  if jq -e '.compaction' "$tmp_file" >/dev/null 2>&1; then
    : # compaction exists
  else
    jq '.compaction = {"taskLogCountSinceLastSummary": 0, "summaryEveryNTaskLogs": 10}' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi

  # Initialize missing root-level memory field
  if jq -e '.memory' "$tmp_file" >/dev/null 2>&1; then
    : # memory exists
  else
    jq '.memory = {"patterns": []}' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi
  if jq -e '.memory.patterns' "$tmp_file" >/dev/null 2>&1; then :; else
    jq '.memory.patterns = []' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi

  # Initialize missing root-level quality field for review lane state
  if jq -e '.quality' "$tmp_file" >/dev/null 2>&1; then
    : # quality exists
  else
    jq '.quality = {
      "reviewMode": "hybrid",
      "reviewPolicy": {
        "autoEnqueueSeverities": ["critical"],
        "approvalRequiredSeverities": ["critical"],
        "minConfidenceForAutoEnqueue": 0.75,
        "maxFindingsPerReview": 5
      },
      "reviewCursor": {
        "lastProcessedReviewCommentUrl": null
      },
      "findings": [],
      "processedReviewKeys": [],
      "finalReview": {
        "status": "pending",
        "reviewedCommit": null,
        "lastReviewId": null,
        "updatedAt": null
      }
    }' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi

  # Fill missing quality subfields on partially initialized files
  if jq -e '.quality.reviewMode' "$tmp_file" >/dev/null 2>&1; then :; else
    jq '.quality.reviewMode = "hybrid"' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi
  if jq -e '.quality.reviewPolicy' "$tmp_file" >/dev/null 2>&1; then :; else
    jq '.quality.reviewPolicy = {
      "autoEnqueueSeverities": ["critical"],
      "approvalRequiredSeverities": ["critical"],
      "minConfidenceForAutoEnqueue": 0.75,
      "maxFindingsPerReview": 5
    }' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi
  if jq -e '.quality.reviewPolicy.autoEnqueueSeverities' "$tmp_file" >/dev/null 2>&1; then :; else
    jq '.quality.reviewPolicy.autoEnqueueSeverities = ["critical"]' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi
  if jq -e '.quality.reviewPolicy.approvalRequiredSeverities' "$tmp_file" >/dev/null 2>&1; then :; else
    jq '.quality.reviewPolicy.approvalRequiredSeverities = ["critical"]' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi
  if jq -e '.quality.reviewPolicy.minConfidenceForAutoEnqueue' "$tmp_file" >/dev/null 2>&1; then :; else
    jq '.quality.reviewPolicy.minConfidenceForAutoEnqueue = 0.75' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi
  if jq -e '.quality.reviewPolicy.maxFindingsPerReview' "$tmp_file" >/dev/null 2>&1; then :; else
    jq '.quality.reviewPolicy.maxFindingsPerReview = 5' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi
  if jq -e '.quality.reviewCursor' "$tmp_file" >/dev/null 2>&1; then :; else
    jq '.quality.reviewCursor = {"lastProcessedReviewCommentUrl": null}' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi
  if jq -e '.quality.reviewCursor.lastProcessedReviewCommentUrl' "$tmp_file" >/dev/null 2>&1; then :; else
    jq '.quality.reviewCursor.lastProcessedReviewCommentUrl = null' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi
  if jq -e '.quality.findings' "$tmp_file" >/dev/null 2>&1; then :; else
    jq '.quality.findings = []' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi
  if jq -e '.quality.processedReviewKeys' "$tmp_file" >/dev/null 2>&1; then :; else
    jq '.quality.processedReviewKeys = []' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi
  if jq -e '.quality.finalReview' "$tmp_file" >/dev/null 2>&1; then :; else
    jq '.quality.finalReview = {
      "status": "pending",
      "reviewedCommit": null,
      "lastReviewId": null,
      "updatedAt": null
    }' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi
  if jq -e '.quality.finalReview.status' "$tmp_file" >/dev/null 2>&1; then :; else
    jq '.quality.finalReview.status = "pending"' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi
  if jq -e '.quality.finalReview.reviewedCommit' "$tmp_file" >/dev/null 2>&1; then :; else
    jq '.quality.finalReview.reviewedCommit = null' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi
  if jq -e '.quality.finalReview.lastReviewId' "$tmp_file" >/dev/null 2>&1; then :; else
    jq '.quality.finalReview.lastReviewId = null' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi
  if jq -e '.quality.finalReview.updatedAt' "$tmp_file" >/dev/null 2>&1; then :; else
    jq '.quality.finalReview.updatedAt = null' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi
  if jq -e '.quality.execution' "$tmp_file" >/dev/null 2>&1; then :; else
    jq '.quality.execution = {
      "consecutiveRetries": 0,
      "currentTaskId": null,
      "currentTaskRetryStreak": 0,
      "lastReplanAt": null,
      "lastReplanReason": null,
      "tasksSinceFullVerify": 0,
      "lastFullVerifyCommit": null,
      "lastFullVerifyAt": null,
      "lastAutoReplanAt": null,
      "lastAutoReplanReason": null,
      "lastAutoReplanResult": null
    }' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi
  if jq -e '.quality.execution.consecutiveRetries' "$tmp_file" >/dev/null 2>&1; then :; else
    jq '.quality.execution.consecutiveRetries = 0' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi
  if jq -e '.quality.execution.currentTaskId' "$tmp_file" >/dev/null 2>&1; then :; else
    jq '.quality.execution.currentTaskId = null' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi
  if jq -e '.quality.execution.currentTaskRetryStreak' "$tmp_file" >/dev/null 2>&1; then :; else
    jq '.quality.execution.currentTaskRetryStreak = 0' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi
  if jq -e '.quality.execution.lastReplanAt' "$tmp_file" >/dev/null 2>&1; then :; else
    jq '.quality.execution.lastReplanAt = null' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi
  if jq -e '.quality.execution.lastReplanReason' "$tmp_file" >/dev/null 2>&1; then :; else
    jq '.quality.execution.lastReplanReason = null' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi
  if jq -e '.quality.execution.tasksSinceFullVerify' "$tmp_file" >/dev/null 2>&1; then :; else
    jq '.quality.execution.tasksSinceFullVerify = 0' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi
  if jq -e '.quality.execution.lastFullVerifyCommit' "$tmp_file" >/dev/null 2>&1; then :; else
    jq '.quality.execution.lastFullVerifyCommit = null' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi
  if jq -e '.quality.execution.lastFullVerifyAt' "$tmp_file" >/dev/null 2>&1; then :; else
    jq '.quality.execution.lastFullVerifyAt = null' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi
  if jq -e '.quality.execution.lastAutoReplanAt' "$tmp_file" >/dev/null 2>&1; then :; else
    jq '.quality.execution.lastAutoReplanAt = null' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi
  if jq -e '.quality.execution.lastAutoReplanReason' "$tmp_file" >/dev/null 2>&1; then :; else
    jq '.quality.execution.lastAutoReplanReason = null' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi
  if jq -e '.quality.execution.lastAutoReplanResult' "$tmp_file" >/dev/null 2>&1; then :; else
    jq '.quality.execution.lastAutoReplanResult = null' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi

  # Initialize missing per-story fields: uid, discoveredFrom, discoverySource
  local story_count
  story_count=$(jq '.userStories | length' "$tmp_file")

  local i=0
  while [ "$i" -lt "$story_count" ]; do
    local story_uid
    story_uid=$(jq -r --argjson idx "$i" '.userStories[$idx].uid // ""' "$tmp_file")

    if [ -z "$story_uid" ]; then
      # Generate uid from story title + ordinal
      local story_title
      story_title=$(jq -r --argjson idx "$i" '.userStories[$idx].title // ""' "$tmp_file")
      local discovered_from
      discovered_from=$(jq -r --argjson idx "$i" '.userStories[$idx].discoveredFrom // "null"' "$tmp_file")
      local ordinal=$((i + 1))

      local new_uid
      new_uid=$(generate_task_uid "$issue_number" "$story_title" "$discovered_from" "$ordinal")

      jq --argjson idx "$i" --arg uid "$new_uid" \
        '.userStories[$idx].uid = $uid' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
      needs_update=1
    fi

    # Initialize discoveredFrom to null if missing
    if jq -e --argjson idx "$i" '.userStories[$idx] | has("discoveredFrom")' "$tmp_file" | grep -q 'true'; then
      : # field exists
    else
      jq --argjson idx "$i" '.userStories[$idx].discoveredFrom = null' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
      needs_update=1
    fi

    # Initialize discoverySource to null if missing
    if jq -e --argjson idx "$i" '.userStories[$idx] | has("discoverySource")' "$tmp_file" | grep -q 'true'; then
      : # field exists
    else
      jq --argjson idx "$i" '.userStories[$idx].discoverySource = null' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
      needs_update=1
    fi

    # Initialize requiresBrowserVerification to false if missing
    if jq -e --argjson idx "$i" '.userStories[$idx] | has("requiresBrowserVerification")' "$tmp_file" | grep -q 'true'; then
      : # field exists
    else
      jq --argjson idx "$i" '.userStories[$idx].requiresBrowserVerification = false' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
      needs_update=1
    fi

    i=$((i + 1))
  done

  # Only overwrite if changes were needed
  if [ "$needs_update" -eq 1 ]; then
    mv "$tmp_file" "$prd_file"
  else
    rm -f "$tmp_file"
  fi

  return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# Execution Configuration + Authoritative Gates
# ═══════════════════════════════════════════════════════════════════════════════

# Load execution hardening settings from .issueloop.config.json with safe
# defaults. Values are exported as global shell vars for the loop script.
#
# Args:
#   $1 - path to config file (default: ".issueloop.config.json")
load_execution_config() {
  local config_file="${1:-.issueloop.config.json}"

  # Base defaults preserve legacy behavior when new keys are absent.
  EXEC_PROFILE="greenfield"
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
  EXEC_PLACEHOLDER_PATTERNS_JSON='["TODO\\\\b","FIXME\\\\b","placeholder\\\\b","stub\\\\b","not implemented","mock implementation"]'
  EXEC_PLACEHOLDER_EXCLUDE_REGEX_JSON='["(^|/)test(s)?/","\\\\.md$"]'
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
  EXEC_MAX_TASK_ATTEMPTS=3
  EXEC_LABEL_PLANNING="AI: Planning"
  MEMORY_AUTO_SYNC_DOCS="true"
  MEMORY_MIN_CONFIDENCE="0.8"
  MEMORY_DOC_TARGETS_JSON='["AGENTS.md","CLAUDE.md"]'
  MEMORY_MAX_PATTERNS_PER_TASK=3
  MEMORY_MANAGED_SECTION_MARKER="issues-loop:auto-patterns"

  if [ -f "$config_file" ]; then
    EXEC_PROFILE=$(jq -r '.execution.profile // "greenfield"' "$config_file" 2>/dev/null || echo "greenfield")

    # Profile overlay is applied first, then explicit keys may override.
    case "$EXEC_PROFILE" in
      brownfield)
        EXEC_TASK_SIZING_ENABLED="true"
        EXEC_CONTEXT_MANIFEST_ENABLED="true"
        EXEC_VERIFY_FULL_RUN_EVERY_N_PASSED_TASKS=3
        EXEC_VERIFY_RUN_FULL_BEFORE_TESTING_CHECKPOINT="true"
        EXEC_REPLAN_AUTO_GENERATE_ON_STALE="true"
        EXEC_REPLAN_AUTO_APPLY_IF_SINGLE_TASK="true"
        EXEC_REPLAN_MAX_GENERATED_TASKS=6
        EXEC_PLACEHOLDER_SEMANTIC_ENABLED="true"
        EXEC_PLACEHOLDER_BLOCK_TRIVIAL_CONSTANT_RETURNS="true"
        EXEC_PLACEHOLDER_BLOCK_ALWAYS_TRUE_FALSE_CONDITIONALS="true"
        EXEC_TEST_INTENT_REQUIRED_WHEN_TESTS_CHANGED="true"
        EXEC_TEST_INTENT_ENFORCE="false"
        EXEC_SEARCH_MIN_QUERIES=3
        EXEC_STALE_SAME_TASK_THRESHOLD=1
        EXEC_STALE_CONSECUTIVE_THRESHOLD=3
        ;;
      greenfield)
        :
        ;;
      *)
        EXEC_PROFILE="greenfield"
        ;;
    esac

    EXEC_GATE_MODE=$(jq -r --arg default "$EXEC_GATE_MODE" '.execution.gateMode // $default' "$config_file" 2>/dev/null || echo "$EXEC_GATE_MODE")
    EXEC_EVENT_REQUIRED=$(jq -r --arg default "$EXEC_EVENT_REQUIRED" '.execution.eventEvidence.required // ($default | test("true";"i"))' "$config_file" 2>/dev/null || echo "$EXEC_EVENT_REQUIRED")
    EXEC_VERIFY_TIMEOUT_SECONDS=$(jq -r --argjson default "$EXEC_VERIFY_TIMEOUT_SECONDS" '.execution.verify.commandTimeoutSeconds // $default' "$config_file" 2>/dev/null || echo "$EXEC_VERIFY_TIMEOUT_SECONDS")
    EXEC_VERIFY_MAX_OUTPUT_LINES=$(jq -r --argjson default "$EXEC_VERIFY_MAX_OUTPUT_LINES" '.execution.verify.maxOutputLinesPerCommand // $default' "$config_file" 2>/dev/null || echo "$EXEC_VERIFY_MAX_OUTPUT_LINES")

    # Compatibility: if fastGlobalVerifyCommands is missing, use legacy globalVerifyCommands.
    EXEC_VERIFY_FAST_GLOBAL_COMMANDS_JSON=$(jq -c '
      if (.execution.verify? | type) == "object" and (.execution.verify | has("fastGlobalVerifyCommands")) then
        (.execution.verify.fastGlobalVerifyCommands // [])
      else
        (.execution.verify.globalVerifyCommands // [])
      end
    ' "$config_file" 2>/dev/null || echo "$EXEC_VERIFY_FAST_GLOBAL_COMMANDS_JSON")
    EXEC_VERIFY_GLOBAL_COMMANDS_JSON="$EXEC_VERIFY_FAST_GLOBAL_COMMANDS_JSON"

    EXEC_VERIFY_FULL_GLOBAL_COMMANDS_JSON=$(jq -c --argjson default "$EXEC_VERIFY_FULL_GLOBAL_COMMANDS_JSON" '.execution.verify.fullGlobalVerifyCommands // $default' "$config_file" 2>/dev/null || echo "$EXEC_VERIFY_FULL_GLOBAL_COMMANDS_JSON")
    EXEC_VERIFY_FULL_RUN_EVERY_N_PASSED_TASKS=$(jq -r --argjson default "$EXEC_VERIFY_FULL_RUN_EVERY_N_PASSED_TASKS" '.execution.verify.fullRunEveryNPassedTasks // $default' "$config_file" 2>/dev/null || echo "$EXEC_VERIFY_FULL_RUN_EVERY_N_PASSED_TASKS")
    EXEC_VERIFY_RUN_FULL_BEFORE_TESTING_CHECKPOINT=$(jq -r --arg default "$EXEC_VERIFY_RUN_FULL_BEFORE_TESTING_CHECKPOINT" '.execution.verify.runFullVerifyBeforeTestingCheckpoint // ($default | test("true";"i"))' "$config_file" 2>/dev/null || echo "$EXEC_VERIFY_RUN_FULL_BEFORE_TESTING_CHECKPOINT")
    EXEC_VERIFY_SECURITY_COMMANDS_JSON=$(jq -c --argjson default "$EXEC_VERIFY_SECURITY_COMMANDS_JSON" '.execution.verify.securityVerifyCommands // $default' "$config_file" 2>/dev/null || echo "$EXEC_VERIFY_SECURITY_COMMANDS_JSON")
    EXEC_VERIFY_RUN_SECURITY_EACH=$(jq -r --arg default "$EXEC_VERIFY_RUN_SECURITY_EACH" '.execution.verify.runSecurityVerifyOnEveryTask // ($default | test("true";"i"))' "$config_file" 2>/dev/null || echo "$EXEC_VERIFY_RUN_SECURITY_EACH")

    EXEC_SEARCH_REQUIRED=$(jq -r --arg default "$EXEC_SEARCH_REQUIRED" '.execution.searchEvidence.required // ($default | test("true";"i"))' "$config_file" 2>/dev/null || echo "$EXEC_SEARCH_REQUIRED")
    EXEC_SEARCH_MIN_QUERIES=$(jq -r --argjson default "$EXEC_SEARCH_MIN_QUERIES" '.execution.searchEvidence.minQueries // $default' "$config_file" 2>/dev/null || echo "$EXEC_SEARCH_MIN_QUERIES")

    EXEC_TASK_SIZING_ENABLED=$(jq -r --arg default "$EXEC_TASK_SIZING_ENABLED" '.execution.taskSizing.enabled // ($default | test("true";"i"))' "$config_file" 2>/dev/null || echo "$EXEC_TASK_SIZING_ENABLED")
    EXEC_TASK_SIZING_MAX_DESCRIPTION_SENTENCES=$(jq -r --argjson default "$EXEC_TASK_SIZING_MAX_DESCRIPTION_SENTENCES" '.execution.taskSizing.maxDescriptionSentences // $default' "$config_file" 2>/dev/null || echo "$EXEC_TASK_SIZING_MAX_DESCRIPTION_SENTENCES")
    EXEC_TASK_SIZING_MAX_ACCEPTANCE_CRITERIA=$(jq -r --argjson default "$EXEC_TASK_SIZING_MAX_ACCEPTANCE_CRITERIA" '.execution.taskSizing.maxAcceptanceCriteria // $default' "$config_file" 2>/dev/null || echo "$EXEC_TASK_SIZING_MAX_ACCEPTANCE_CRITERIA")
    EXEC_TASK_SIZING_MAX_VERIFY_COMMANDS=$(jq -r --argjson default "$EXEC_TASK_SIZING_MAX_VERIFY_COMMANDS" '.execution.taskSizing.maxVerifyCommands // $default' "$config_file" 2>/dev/null || echo "$EXEC_TASK_SIZING_MAX_VERIFY_COMMANDS")
    EXEC_TASK_SIZING_MAX_FILES=$(jq -r --argjson default "$EXEC_TASK_SIZING_MAX_FILES" '.execution.taskSizing.maxFiles // $default' "$config_file" 2>/dev/null || echo "$EXEC_TASK_SIZING_MAX_FILES")
    EXEC_TASK_SIZING_HARD_FAIL_ON_OVERSIZED=$(jq -r --arg default "$EXEC_TASK_SIZING_HARD_FAIL_ON_OVERSIZED" '.execution.taskSizing.hardFailOnOversized // ($default | test("true";"i"))' "$config_file" 2>/dev/null || echo "$EXEC_TASK_SIZING_HARD_FAIL_ON_OVERSIZED")

    EXEC_CONTEXT_MANIFEST_ENABLED=$(jq -r --arg default "$EXEC_CONTEXT_MANIFEST_ENABLED" '.execution.contextManifest.enabled // ($default | test("true";"i"))' "$config_file" 2>/dev/null || echo "$EXEC_CONTEXT_MANIFEST_ENABLED")
    EXEC_CONTEXT_MANIFEST_ALGORITHM=$(jq -r --arg default "$EXEC_CONTEXT_MANIFEST_ALGORITHM" '.execution.contextManifest.algorithm // $default' "$config_file" 2>/dev/null || echo "$EXEC_CONTEXT_MANIFEST_ALGORITHM")
    EXEC_CONTEXT_MANIFEST_ENFORCE_HASH_MATCH=$(jq -r --arg default "$EXEC_CONTEXT_MANIFEST_ENFORCE_HASH_MATCH" '.execution.contextManifest.enforceHashMatch // ($default | test("true";"i"))' "$config_file" 2>/dev/null || echo "$EXEC_CONTEXT_MANIFEST_ENFORCE_HASH_MATCH")

    EXEC_BROWSER_REQUIRED_FOR_UI=$(jq -r --arg default "$EXEC_BROWSER_REQUIRED_FOR_UI" '.execution.browserVerification.requiredForUiTasks // ($default | test("true";"i"))' "$config_file" 2>/dev/null || echo "$EXEC_BROWSER_REQUIRED_FOR_UI")
    EXEC_BROWSER_HARD_FAIL_WHEN_UNAVAILABLE=$(jq -r --arg default "$EXEC_BROWSER_HARD_FAIL_WHEN_UNAVAILABLE" '.execution.browserVerification.hardFailWhenUnavailable // ($default | test("true";"i"))' "$config_file" 2>/dev/null || echo "$EXEC_BROWSER_HARD_FAIL_WHEN_UNAVAILABLE")
    EXEC_BROWSER_ALLOWED_TOOLS_JSON=$(jq -c --argjson default "$EXEC_BROWSER_ALLOWED_TOOLS_JSON" '.execution.browserVerification.allowedTools // $default' "$config_file" 2>/dev/null || echo "$EXEC_BROWSER_ALLOWED_TOOLS_JSON")

    EXEC_REPLAN_AUTO_GENERATE_ON_STALE=$(jq -r --arg default "$EXEC_REPLAN_AUTO_GENERATE_ON_STALE" '.execution.replan.autoGenerateOnStale // ($default | test("true";"i"))' "$config_file" 2>/dev/null || echo "$EXEC_REPLAN_AUTO_GENERATE_ON_STALE")
    EXEC_REPLAN_AUTO_APPLY_IF_SINGLE_TASK=$(jq -r --arg default "$EXEC_REPLAN_AUTO_APPLY_IF_SINGLE_TASK" '.execution.replan.autoApplyIfSingleTask // ($default | test("true";"i"))' "$config_file" 2>/dev/null || echo "$EXEC_REPLAN_AUTO_APPLY_IF_SINGLE_TASK")
    EXEC_REPLAN_MAX_GENERATED_TASKS=$(jq -r --argjson default "$EXEC_REPLAN_MAX_GENERATED_TASKS" '.execution.replan.maxGeneratedTasks // $default' "$config_file" 2>/dev/null || echo "$EXEC_REPLAN_MAX_GENERATED_TASKS")

    EXEC_PLACEHOLDER_ENABLED=$(jq -r --arg default "$EXEC_PLACEHOLDER_ENABLED" '.execution.placeholder.enabled // ($default | test("true";"i"))' "$config_file" 2>/dev/null || echo "$EXEC_PLACEHOLDER_ENABLED")
    EXEC_PLACEHOLDER_PATTERNS_JSON=$(jq -c --argjson default "$EXEC_PLACEHOLDER_PATTERNS_JSON" '.execution.placeholder.patterns // $default' "$config_file" 2>/dev/null || echo "$EXEC_PLACEHOLDER_PATTERNS_JSON")
    EXEC_PLACEHOLDER_EXCLUDE_REGEX_JSON=$(jq -c --argjson default "$EXEC_PLACEHOLDER_EXCLUDE_REGEX_JSON" '.execution.placeholder.excludePathRegex // $default' "$config_file" 2>/dev/null || echo "$EXEC_PLACEHOLDER_EXCLUDE_REGEX_JSON")
    EXEC_PLACEHOLDER_SEMANTIC_ENABLED=$(jq -r --arg default "$EXEC_PLACEHOLDER_SEMANTIC_ENABLED" '.execution.placeholder.semanticChecks.enabled // ($default | test("true";"i"))' "$config_file" 2>/dev/null || echo "$EXEC_PLACEHOLDER_SEMANTIC_ENABLED")
    EXEC_PLACEHOLDER_BLOCK_TRIVIAL_CONSTANT_RETURNS=$(jq -r --arg default "$EXEC_PLACEHOLDER_BLOCK_TRIVIAL_CONSTANT_RETURNS" '.execution.placeholder.semanticChecks.blockTrivialConstantReturns // ($default | test("true";"i"))' "$config_file" 2>/dev/null || echo "$EXEC_PLACEHOLDER_BLOCK_TRIVIAL_CONSTANT_RETURNS")
    EXEC_PLACEHOLDER_BLOCK_ALWAYS_TRUE_FALSE_CONDITIONALS=$(jq -r --arg default "$EXEC_PLACEHOLDER_BLOCK_ALWAYS_TRUE_FALSE_CONDITIONALS" '.execution.placeholder.semanticChecks.blockAlwaysTrueFalseConditionals // ($default | test("true";"i"))' "$config_file" 2>/dev/null || echo "$EXEC_PLACEHOLDER_BLOCK_ALWAYS_TRUE_FALSE_CONDITIONALS")

    EXEC_TEST_INTENT_REQUIRED_WHEN_TESTS_CHANGED=$(jq -r --arg default "$EXEC_TEST_INTENT_REQUIRED_WHEN_TESTS_CHANGED" '.execution.testIntent.requiredWhenTestsChanged // ($default | test("true";"i"))' "$config_file" 2>/dev/null || echo "$EXEC_TEST_INTENT_REQUIRED_WHEN_TESTS_CHANGED")
    EXEC_TEST_INTENT_ENFORCE=$(jq -r --arg default "$EXEC_TEST_INTENT_ENFORCE" '.execution.testIntent.enforce // ($default | test("true";"i"))' "$config_file" 2>/dev/null || echo "$EXEC_TEST_INTENT_ENFORCE")

    EXEC_STALE_ENABLED=$(jq -r --arg default "$EXEC_STALE_ENABLED" '.execution.stalePlan.enabled // ($default | test("true";"i"))' "$config_file" 2>/dev/null || echo "$EXEC_STALE_ENABLED")
    EXEC_STALE_SAME_TASK_THRESHOLD=$(jq -r --argjson default "$EXEC_STALE_SAME_TASK_THRESHOLD" '.execution.stalePlan.sameTaskRetryThreshold // $default' "$config_file" 2>/dev/null || echo "$EXEC_STALE_SAME_TASK_THRESHOLD")
    EXEC_STALE_CONSECUTIVE_THRESHOLD=$(jq -r --argjson default "$EXEC_STALE_CONSECUTIVE_THRESHOLD" '.execution.stalePlan.consecutiveRetryThreshold // $default' "$config_file" 2>/dev/null || echo "$EXEC_STALE_CONSECUTIVE_THRESHOLD")

    EXEC_CONTEXT_PREFER_COMPACTED=$(jq -r --arg default "$EXEC_CONTEXT_PREFER_COMPACTED" '.execution.context.preferCompactedSummary // ($default | test("true";"i"))' "$config_file" 2>/dev/null || echo "$EXEC_CONTEXT_PREFER_COMPACTED")
    EXEC_CONTEXT_MAX_TASK_LOGS=$(jq -r --argjson default "$EXEC_CONTEXT_MAX_TASK_LOGS" '.execution.context.maxTaskLogs // $default' "$config_file" 2>/dev/null || echo "$EXEC_CONTEXT_MAX_TASK_LOGS")
    EXEC_CONTEXT_MAX_DISCOVERY_NOTES=$(jq -r --argjson default "$EXEC_CONTEXT_MAX_DISCOVERY_NOTES" '.execution.context.maxDiscoveryNotes // $default' "$config_file" 2>/dev/null || echo "$EXEC_CONTEXT_MAX_DISCOVERY_NOTES")
    EXEC_CONTEXT_MAX_REVIEW_LOGS=$(jq -r --argjson default "$EXEC_CONTEXT_MAX_REVIEW_LOGS" '.execution.context.maxReviewLogs // $default' "$config_file" 2>/dev/null || echo "$EXEC_CONTEXT_MAX_REVIEW_LOGS")
    EXEC_MAX_TASK_ATTEMPTS=$(jq -r --argjson default "$EXEC_MAX_TASK_ATTEMPTS" '.maxTaskAttempts // $default' "$config_file" 2>/dev/null || echo "$EXEC_MAX_TASK_ATTEMPTS")
    EXEC_LABEL_PLANNING=$(jq -r --arg default "$EXEC_LABEL_PLANNING" '.labels.planning // $default' "$config_file" 2>/dev/null || echo "$EXEC_LABEL_PLANNING")
    MEMORY_AUTO_SYNC_DOCS=$(jq -r --arg default "$MEMORY_AUTO_SYNC_DOCS" '.memory.autoSyncDocs // ($default | test("true";"i"))' "$config_file" 2>/dev/null || echo "$MEMORY_AUTO_SYNC_DOCS")
    MEMORY_MIN_CONFIDENCE=$(jq -r --argjson default "$MEMORY_MIN_CONFIDENCE" '.memory.minConfidence // $default' "$config_file" 2>/dev/null || echo "$MEMORY_MIN_CONFIDENCE")
    MEMORY_DOC_TARGETS_JSON=$(jq -c --argjson default "$MEMORY_DOC_TARGETS_JSON" '.memory.docTargets // $default' "$config_file" 2>/dev/null || echo "$MEMORY_DOC_TARGETS_JSON")
    MEMORY_MAX_PATTERNS_PER_TASK=$(jq -r --argjson default "$MEMORY_MAX_PATTERNS_PER_TASK" '.memory.maxPatternsPerTask // $default' "$config_file" 2>/dev/null || echo "$MEMORY_MAX_PATTERNS_PER_TASK")
    MEMORY_MANAGED_SECTION_MARKER=$(jq -r --arg default "$MEMORY_MANAGED_SECTION_MARKER" '.memory.managedSectionMarker // $default' "$config_file" 2>/dev/null || echo "$MEMORY_MANAGED_SECTION_MARKER")
  fi
}

# Run a command with timeout when timeout binaries are available.
#
# Args:
#   $1 - shell command string
#   $2 - timeout seconds
run_command_with_timeout() {
  local cmd="$1"
  local timeout_seconds="${2:-600}"

  if [ -z "$cmd" ]; then
    return 0
  fi

  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$timeout_seconds" bash -lc "$cmd"
  elif command -v timeout >/dev/null 2>&1; then
    timeout "$timeout_seconds" bash -lc "$cmd"
  else
    bash -lc "$cmd"
  fi
}

# Execute authoritative verify commands for the current task.
#
# Args:
#   $1 - task verifyCommands JSON array
#   $2 - timeout seconds
#   $3 - max output tail lines per command
#   $4 - global verify commands JSON array
#   $5 - security verify commands JSON array
#   $6 - run security commands on every task ("true"/"false")
#
# Output: compact JSON
# {
#   "commands":[...],
#   "passed":[...],
#   "failed":[{"command":"...","exitCode":1,"outputTail":"..."}],
#   "allPassed":true|false
# }
run_verify_suite() {
  local task_verify_json="${1:-[]}"
  local timeout_seconds="${2:-600}"
  local max_output_lines="${3:-80}"
  local global_verify_json="${4:-[]}"
  local security_verify_json="${5:-[]}"
  local run_security="${6:-false}"

  local all_commands_json
  all_commands_json=$(jq -nc \
    --argjson task "$task_verify_json" \
    --argjson global "$global_verify_json" \
    --argjson security "$security_verify_json" \
    --arg run_security "$run_security" '
      ($task // []) as $task_cmds |
      ($global // []) as $global_cmds |
      ($security // []) as $security_cmds |
      (
        $task_cmds
        + $global_cmds
        + (if ($run_security | ascii_downcase) == "true" then $security_cmds else [] end)
      )
      | map(select(type == "string" and length > 0))
      | unique
    ')

  local passed='[]'
  local failed='[]'
  local command_count
  command_count=$(echo "$all_commands_json" | jq 'length')

  local i=0
  while [ "$i" -lt "$command_count" ]; do
    local command output_file exit_code output_tail
    command=$(echo "$all_commands_json" | jq -r --argjson idx "$i" '.[$idx]')
    output_file=$(mktemp)

    set +e
    run_command_with_timeout "$command" "$timeout_seconds" >"$output_file" 2>&1
    exit_code=$?
    set -e

    output_tail=$(tail -n "$max_output_lines" "$output_file" 2>/dev/null || true)
    rm -f "$output_file"

    if [ "$exit_code" -eq 0 ]; then
      passed=$(echo "$passed" | jq --arg command "$command" '. + [$command]')
    else
      failed=$(echo "$failed" | jq \
        --arg command "$command" \
        --argjson exit_code "$exit_code" \
        --arg output_tail "$output_tail" \
        '. + [{"command": $command, "exitCode": $exit_code, "outputTail": $output_tail}]')
    fi

    i=$((i + 1))
  done

  local failed_count all_passed
  failed_count=$(echo "$failed" | jq 'length')
  if [ "$failed_count" -eq 0 ]; then
    all_passed="true"
  else
    all_passed="false"
  fi

  jq -nc \
    --argjson commands "$all_commands_json" \
    --argjson passed "$passed" \
    --argjson failed "$failed" \
    --argjson all_passed "$all_passed" \
    '{
      "commands": $commands,
      "passed": $passed,
      "failed": $failed,
      "allPassed": $all_passed
    }'
}

# Validate whether a task is right-sized for one loop iteration.
#
# Args:
#   $1 - task JSON object
#   $2 - enabled flag ("true"/"false")
#   $3 - max description sentences
#   $4 - max acceptance criteria count
#   $5 - max verify commands count
#   $6 - max files count
#
# Output:
# {"ok":true|false,"metrics":{...},"violations":[...]}
validate_task_sizing() {
  local task_json="${1:-}"
  local enabled="${2:-false}"
  local max_desc_sentences="${3:-3}"
  local max_acceptance="${4:-10}"
  local max_verify="${5:-6}"
  local max_files="${6:-12}"
  [ -n "$task_json" ] || task_json='{}'

  if ! echo "$task_json" | jq -e '.' >/dev/null 2>&1; then
    task_json='{}'
  fi

  local description acceptance_count verify_count files_count sentence_count
  description=$(echo "$task_json" | jq -r '.description // ""' 2>/dev/null || echo "")
  acceptance_count=$(echo "$task_json" | jq -r '(.acceptanceCriteria // []) | if type=="array" then length else 0 end' 2>/dev/null || echo "0")
  verify_count=$(echo "$task_json" | jq -r '(.verifyCommands // []) | if type=="array" then length else 0 end' 2>/dev/null || echo "0")
  files_count=$(echo "$task_json" | jq -r '(.files // []) | if type=="array" then length else 0 end' 2>/dev/null || echo "0")
  sentence_count=$(printf "%s" "$description" | awk -F'[.!?]+' '{c=0; for(i=1;i<=NF;i++) if($i ~ /[^[:space:]]/) c++; print c}')
  [ -n "$sentence_count" ] || sentence_count=0
  [[ "$sentence_count" =~ ^[0-9]+$ ]] || sentence_count=0
  [[ "$acceptance_count" =~ ^[0-9]+$ ]] || acceptance_count=0
  [[ "$verify_count" =~ ^[0-9]+$ ]] || verify_count=0
  [[ "$files_count" =~ ^[0-9]+$ ]] || files_count=0

  local violations='[]'
  if [ "$(echo "$enabled" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
    if [ "$sentence_count" -gt "$max_desc_sentences" ]; then
      violations=$(echo "$violations" | jq --arg v "description sentences ${sentence_count}>${max_desc_sentences}" '. + [$v]')
    fi
    if [ "$acceptance_count" -gt "$max_acceptance" ]; then
      violations=$(echo "$violations" | jq --arg v "acceptance criteria ${acceptance_count}>${max_acceptance}" '. + [$v]')
    fi
    if [ "$verify_count" -gt "$max_verify" ]; then
      violations=$(echo "$violations" | jq --arg v "verify commands ${verify_count}>${max_verify}" '. + [$v]')
    fi
    if [ "$files_count" -gt "$max_files" ]; then
      violations=$(echo "$violations" | jq --arg v "files ${files_count}>${max_files}" '. + [$v]')
    fi
  fi

  local ok="true"
  if [ "$(echo "$enabled" | tr '[:upper:]' '[:lower:]')" = "true" ] && [ "$(echo "$violations" | jq 'length')" -gt 0 ]; then
    ok="false"
  fi

  jq -nc \
    --argjson sentence_count "$sentence_count" \
    --argjson acceptance_count "$acceptance_count" \
    --argjson verify_count "$verify_count" \
    --argjson files_count "$files_count" \
    --argjson violations "$violations" \
    --arg ok "$ok" \
    '{
      "ok": ($ok == "true"),
      "metrics": {
        "descriptionSentences": $sentence_count,
        "acceptanceCriteriaCount": $acceptance_count,
        "verifyCommandsCount": $verify_count,
        "filesCount": $files_count
      },
      "violations": $violations
    }'
}

# Build canonical context manifest JSON for deterministic hashing.
#
# Args:
#   $1 - task JSON object
#   $2 - issue body
#   $3 - issue memory bundle
#   $4 - git log
#   $5 - repo structure list
#   $6 - active wisps
#
# Output: JSON object
build_context_manifest() {
  local task_json="${1:-}"
  local issue_body="${2:-}"
  local issue_memory_bundle="${3:-}"
  local git_log="${4:-}"
  local repo_structure="${5:-}"
  local active_wisps="${6:-}"
  [ -n "$task_json" ] || task_json='{}'

  jq -nc \
    --argjson task "$task_json" \
    --arg issue_body "$issue_body" \
    --arg issue_memory_bundle "$issue_memory_bundle" \
    --arg git_log "$git_log" \
    --arg repo_structure "$repo_structure" \
    --arg active_wisps "$active_wisps" \
    '{
      "task": $task,
      "issueBody": $issue_body,
      "issueMemoryBundle": $issue_memory_bundle,
      "gitLog": $git_log,
      "repoStructure": ($repo_structure | split("\n") | map(select(length > 0))),
      "activeWisps": $active_wisps
    }'
}

# Compute deterministic hash for a context manifest.
#
# Args:
#   $1 - manifest JSON object
#   $2 - algorithm ("sha256")
#
# Output: hex hash string
compute_context_manifest_hash() {
  local manifest_json="${1:-}"
  local algorithm="${2:-sha256}"
  local canonical
  [ -n "$manifest_json" ] || manifest_json='{}'
  canonical=$(echo "$manifest_json" | jq -cS '.' 2>/dev/null || echo '{}')

  case "$(echo "$algorithm" | tr '[:upper:]' '[:lower:]')" in
    sha256)
      echo -n "$canonical" | shasum -a 256 | cut -d' ' -f1
      ;;
    *)
      echo -n "$canonical" | shasum -a 256 | cut -d' ' -f1
      ;;
  esac
}

# Validate context manifest evidence from task event JSON.
#
# Args:
#   $1 - event JSON object
#   $2 - expected hash
#   $3 - expected algorithm
#   $4 - required flag ("true"/"false")
#
# Output:
# {"ok":true|false,"reason":"...","observedHash":"...","observedAlgorithm":"..."}
validate_context_manifest_evidence() {
  local event_json="${1:-}"
  local expected_hash="${2:-}"
  local expected_algorithm="${3:-sha256}"
  local required="${4:-false}"

  if [ -z "$event_json" ] || [ "$event_json" = "null" ]; then
    if [ "$(echo "$required" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
      echo '{"ok":false,"reason":"task log event missing","observedHash":"","observedAlgorithm":""}'
    else
      echo '{"ok":true,"reason":"task log event missing (advisory)","observedHash":"","observedAlgorithm":""}'
    fi
    return 0
  fi

  local observed_hash observed_algorithm
  observed_hash=$(echo "$event_json" | jq -r '.contextManifest.hash // ""' 2>/dev/null || echo "")
  observed_algorithm=$(echo "$event_json" | jq -r '.contextManifest.algorithm // ""' 2>/dev/null || echo "")

  if [ -z "$observed_hash" ]; then
    if [ "$(echo "$required" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
      jq -nc --arg hash "$observed_hash" --arg algo "$observed_algorithm" \
        '{"ok":false,"reason":"contextManifest.hash missing","observedHash":$hash,"observedAlgorithm":$algo}'
    else
      jq -nc --arg hash "$observed_hash" --arg algo "$observed_algorithm" \
        '{"ok":true,"reason":"contextManifest.hash missing (advisory)","observedHash":$hash,"observedAlgorithm":$algo}'
    fi
    return 0
  fi

  if [ "$observed_hash" = "$expected_hash" ]; then
    jq -nc --arg hash "$observed_hash" --arg algo "$observed_algorithm" \
      '{"ok":true,"reason":"context manifest hash matches","observedHash":$hash,"observedAlgorithm":$algo}'
  else
    jq -nc --arg hash "$observed_hash" --arg algo "$observed_algorithm" --arg expected "$expected_hash" \
      '{"ok":false,"reason":("context manifest hash mismatch expected=" + $expected),"observedHash":$hash,"observedAlgorithm":$algo}'
  fi
}

# Detect changed test files for a commit or worktree diff.
#
# Args:
#   $1 - commit hash or WORKTREE
#
# Output: JSON array of file paths
detect_changed_test_files() {
  local commit_target="${1:-WORKTREE}"
  local changed_files

  if [ -n "$commit_target" ] && [ "$commit_target" != "WORKTREE" ] && [ "$commit_target" != "null" ]; then
    changed_files=$(git show --name-only --pretty="" "$commit_target" 2>/dev/null || echo "")
  else
    changed_files=$(git diff --name-only HEAD 2>/dev/null || git diff --name-only 2>/dev/null || echo "")
  fi

  printf "%s\n" "$changed_files" | sed '/^$/d' | jq -R -s -c '
    split("\n")
    | map(select(length > 0))
    | map(select(
        test("(^|/)(test|tests|__tests__|spec|specs)(/|$)"; "i")
        or test("\\.(test|spec)\\.[A-Za-z0-9]+$"; "i")
      ))
    | unique
  '
}

# Validate test intent evidence in task event JSON.
#
# Args:
#   $1 - event JSON object
#
# Output:
# {"ok":true|false,"count":N,"reason":"..."}
validate_test_intent_evidence() {
  local event_json="${1:-}"
  if [ -z "$event_json" ] || [ "$event_json" = "null" ]; then
    echo '{"ok":false,"count":0,"reason":"task log event missing"}'
    return 0
  fi

  local total valid
  total=$(echo "$event_json" | jq '[.testIntent[]?] | length' 2>/dev/null || echo "0")
  valid=$(echo "$event_json" | jq '[.testIntent[]? | select((.test // "" | tostring | length) > 0 and (.why // "" | tostring | length) > 0)] | length' 2>/dev/null || echo "0")

  if [ "$total" -gt 0 ] && [ "$total" -eq "$valid" ]; then
    jq -nc --argjson n "$total" '{"ok":true,"count":$n,"reason":"valid testIntent evidence present"}'
  elif [ "$total" -gt 0 ]; then
    jq -nc --argjson total "$total" --argjson valid "$valid" \
      '{"ok":false,"count":$valid,"reason":("testIntent entries invalid " + ($valid|tostring) + "/" + ($total|tostring))}'
  else
    echo '{"ok":false,"count":0,"reason":"testIntent missing"}'
  fi
}

# Convert testIntent evidence into reusable pattern objects.
#
# Args:
#   $1 - event JSON object
#
# Output: JSON array compatible with ingest_task_patterns_into_prd .patterns schema
convert_test_intent_to_patterns() {
  local event_json="${1:-}"
  if [ -z "$event_json" ] || [ "$event_json" = "null" ]; then
    echo "[]"
    return 0
  fi
  echo "$event_json" | jq -c '
    [
      (.testIntent // [])[]? |
      {
        "statement": ("Test intent: " + ((.why // "") | tostring)),
        "scope": ("tests:" + ((.test // "unknown") | tostring)),
        "files": [],
        "confidence": 0.95
      } |
      select((.statement | length) > 12)
    ]
  ' 2>/dev/null || echo "[]"
}

# Record successful full-verify run metadata.
#
# Args:
#   $1 - path to prd.json
#   $2 - commit hash
record_full_verify_success() {
  local prd_file="${1:-prd.json}"
  local commit_hash="${2:-}"
  local now_ts
  now_ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  jq --arg commit "$commit_hash" --arg now_ts "$now_ts" '
    .quality.execution.tasksSinceFullVerify = 0 |
    .quality.execution.lastFullVerifyCommit = (if $commit == "" then null else $commit end) |
    .quality.execution.lastFullVerifyAt = $now_ts
  ' "$prd_file" > "${prd_file}.tmp" && mv "${prd_file}.tmp" "$prd_file"
}

# Increment tasksSinceFullVerify counter.
#
# Args:
#   $1 - path to prd.json
increment_tasks_since_full_verify() {
  local prd_file="${1:-prd.json}"
  jq '
    .quality.execution.tasksSinceFullVerify = ((.quality.execution.tasksSinceFullVerify // 0) + 1)
  ' "$prd_file" > "${prd_file}.tmp" && mv "${prd_file}.tmp" "$prd_file"
}

# Record auto-replan audit metadata.
#
# Args:
#   $1 - path to prd.json
#   $2 - reason
#   $3 - result label
record_auto_replan_audit() {
  local prd_file="${1:-prd.json}"
  local reason="$2"
  local result="$3"
  local now_ts
  now_ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  jq --arg reason "$reason" --arg result "$result" --arg now_ts "$now_ts" '
    .quality.execution.lastAutoReplanAt = $now_ts |
    .quality.execution.lastAutoReplanReason = $reason |
    .quality.execution.lastAutoReplanResult = $result
  ' "$prd_file" > "${prd_file}.tmp" && mv "${prd_file}.tmp" "$prd_file"
}

# Apply a single auto-replan replacement to the current task.
#
# Args:
#   $1 - path to prd.json
#   $2 - task id to replace
#   $3 - replacement task JSON object
apply_auto_replan_single_task() {
  local prd_file="${1:-prd.json}"
  local task_id="$2"
  local replacement_json="${3:-}"
  [ -n "$replacement_json" ] || replacement_json='{}'
  if ! echo "$replacement_json" | jq -e '.' >/dev/null 2>&1; then
    replacement_json='{}'
  fi

  jq --arg task_id "$task_id" --argjson replacement "$replacement_json" '
    .userStories = (
      .userStories | map(
        if .id == $task_id then
          .title = ($replacement.title // .title) |
          .description = ($replacement.description // .description) |
          .acceptanceCriteria = ($replacement.acceptanceCriteria // .acceptanceCriteria // []) |
          .verifyCommands = ($replacement.verifyCommands // .verifyCommands // []) |
          .dependsOn = ($replacement.dependsOn // .dependsOn // []) |
          .files = ($replacement.files // .files // []) |
          .notes = ($replacement.notes // .notes // "") |
          .passes = false |
          .attempts = 0 |
          .lastAttempt = null
        else . end
      )
    )
  ' "$prd_file" > "${prd_file}.tmp" && mv "${prd_file}.tmp" "$prd_file"
}

# Extract a replan JSON array from agent output.
#
# Args:
#   $1 - raw agent output text
#
# Output: JSON array or empty string
extract_replan_json_from_agent_output() {
  local output_text="$1"
  local in_section=0
  local in_json=0
  local buffer=""

  while IFS= read -r line; do
    if echo "$line" | grep -q '### Replan JSON'; then
      in_section=1
      in_json=0
      buffer=""
      continue
    fi
    if [ "$in_section" -eq 1 ]; then
      if echo "$line" | grep -qE '^\s*```json\s*$'; then
        in_json=1
        buffer=""
        continue
      fi
      if [ "$in_json" -eq 1 ] && echo "$line" | grep -qE '^\s*```\s*$'; then
        if [ -n "$buffer" ] && echo "$buffer" | jq -e '. | type == "array"' >/dev/null 2>&1; then
          echo "$buffer" | jq -c '.'
          return 0
        fi
        in_json=0
        in_section=0
        continue
      fi
      if [ "$in_json" -eq 1 ]; then
        buffer="${buffer}${line}"
      fi
    fi
  done <<< "$output_text"
}

# Validate/sanitize generated replan tasks.
#
# Args:
#   $1 - candidate JSON array
#   $2 - max tasks
#
# Output: sanitized JSON array
validate_generated_replan_tasks() {
  local tasks_json="${1:-[]}"
  local max_tasks="${2:-6}"

  echo "$tasks_json" | jq -c --argjson max_tasks "$max_tasks" '
    if type != "array" then
      []
    else
      [.[0:$max_tasks][] |
        {
          "title": ((.title // "") | tostring),
          "description": ((.description // "") | tostring),
          "acceptanceCriteria": [(.acceptanceCriteria // [])[]? | tostring],
          "verifyCommands": [(.verifyCommands // [])[]? | tostring],
          "dependsOn": [(.dependsOn // [])[]? | tostring],
          "files": [(.files // [])[]? | tostring],
          "notes": ((.notes // "") | tostring)
        } |
        select(
          (.title | length > 0) and
          (.description | length > 0) and
          (.acceptanceCriteria | length > 0)
        )
      ]
    end
  ' 2>/dev/null || echo "[]"
}

# Update task status in prd.json from authoritative orchestrator result.
#
# Args:
#   $1 - path to prd.json
#   $2 - task id
#   $3 - pass boolean ("true"/"false")
#
# Output: attempt number after update
update_task_state_authoritative() {
  local prd_file="${1:-prd.json}"
  local task_id="$2"
  local pass_bool="${3:-false}"
  local now_ts
  now_ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  jq --arg task_id "$task_id" --arg now_ts "$now_ts" --arg pass_bool "$pass_bool" '
    .userStories = (.userStories | map(
      if .id == $task_id then
        .attempts = ((.attempts // 0) + 1) |
        .lastAttempt = $now_ts |
        .passes = (($pass_bool | ascii_downcase) == "true")
      else . end
    ))
  ' "$prd_file" > "${prd_file}.tmp" && mv "${prd_file}.tmp" "$prd_file"

  jq -r --arg task_id "$task_id" '.userStories[] | select(.id == $task_id) | (.attempts // 0)' "$prd_file"
}

# Return 0 when task attempts are exhausted (>= max attempts).
#
# Args:
#   $1 - path to prd.json
#   $2 - task id
#   $3 - max attempts
is_task_exhausted() {
  local prd_file="${1:-prd.json}"
  local task_id="$2"
  local max_attempts="${3:-3}"
  local attempts
  attempts=$(jq -r --arg task_id "$task_id" '.userStories[] | select(.id == $task_id) | (.attempts // 0)' "$prd_file" 2>/dev/null || echo "0")
  [ "$attempts" -ge "$max_attempts" ]
}

# Validate search evidence block in task log event JSON.
#
# Args:
#   $1 - event JSON object
#   $2 - min required query count
#   $3 - required flag ("true"/"false")
#
# Output:
# {"ok":true|false,"queryCount":N,"fileCount":N,"reason":"..."}
validate_search_evidence() {
  local event_json="${1:-}"
  local min_queries="${2:-2}"
  local required="${3:-true}"

  if [ -z "$event_json" ] || [ "$event_json" = "null" ]; then
    if [ "$(echo "$required" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
      echo '{"ok":false,"queryCount":0,"fileCount":0,"reason":"task log event missing"}'
    else
      echo '{"ok":true,"queryCount":0,"fileCount":0,"reason":"task log event missing (advisory)"}'
    fi
    return 0
  fi

  local query_count file_count
  query_count=$(echo "$event_json" | jq '[.search.queries[]? | select(type == "string" and length > 0)] | length' 2>/dev/null || echo "0")
  file_count=$(echo "$event_json" | jq '[.search.filesInspected[]? | select(type == "string" and length > 0)] | length' 2>/dev/null || echo "0")

  if [ "$query_count" -ge "$min_queries" ]; then
    jq -nc --argjson q "$query_count" --argjson f "$file_count" \
      '{"ok":true,"queryCount":$q,"fileCount":$f,"reason":"search evidence present"}'
  else
    local required_lower
    required_lower=$(echo "$required" | tr '[:upper:]' '[:lower:]')
    if [ "$required_lower" = "true" ]; then
      jq -nc --argjson q "$query_count" --argjson f "$file_count" --argjson min "$min_queries" \
        '{"ok":false,"queryCount":$q,"fileCount":$f,"reason":("requires at least " + ($min|tostring) + " search queries")}'
    else
      jq -nc --argjson q "$query_count" --argjson f "$file_count" --argjson min "$min_queries" \
        '{"ok":true,"queryCount":$q,"fileCount":$f,"reason":("advisory: fewer than " + ($min|tostring) + " search queries")}'
    fi
  fi
}

# Determine whether a task requires browser verification.
#
# Args:
#   $1 - task JSON object
#   $2 - required-for-ui flag ("true"/"false")
#
# Output: "true" or "false"
task_requires_browser_verification() {
  local task_json="${1:-}"
  if [ -z "$task_json" ]; then
    task_json='{}'
  fi
  local required_for_ui="${2:-true}"
  local required_lower
  required_lower=$(echo "$required_for_ui" | tr '[:upper:]' '[:lower:]')
  if [ "$required_lower" != "true" ]; then
    echo "false"
    return 0
  fi

  local explicit_required
  explicit_required=$(echo "$task_json" | jq -r '(.requiresBrowserVerification // false)' 2>/dev/null || echo "false")
  if [ "$(echo "$explicit_required" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
    echo "true"
    return 0
  fi

  local criteria_requires
  criteria_requires=$(echo "$task_json" | jq -r '
    [(.acceptanceCriteria // [])[]? | tostring | test("verify in browser"; "i")] | any
  ' 2>/dev/null || echo "false")
  if [ "$(echo "$criteria_requires" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
    echo "true"
    return 0
  fi

  local verify_requires
  verify_requires=$(echo "$task_json" | jq -r '
    [(.verifyCommands // [])[]? | tostring | test("^__BROWSER_VERIFY_REQUIRED__$")] | any
  ' 2>/dev/null || echo "false")
  if [ "$(echo "$verify_requires" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
    echo "true"
    return 0
  fi

  echo "false"
}

# Extract browser verification JSON event blocks from issue comments.
# Parses only fenced json blocks under '### Browser Event JSON' headings.
#
# Args:
#   $1 - raw issue comments text
#
# Output: one browser_verification JSON object per line
extract_browser_events_from_issue_comments() {
  local comments="$1"
  local in_event_section=0
  local in_json_block=0
  local json_buffer=""

  while IFS= read -r line; do
    if echo "$line" | grep -q '### Browser Event JSON'; then
      in_event_section=1
      in_json_block=0
      json_buffer=""
      continue
    fi

    if [ "$in_event_section" -eq 1 ]; then
      if echo "$line" | grep -qE '^\s*```json\s*$'; then
        in_json_block=1
        json_buffer=""
        continue
      fi

      if [ "$in_json_block" -eq 1 ] && echo "$line" | grep -qE '^\s*```\s*$'; then
        if [ -n "$json_buffer" ]; then
          if echo "$json_buffer" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
            local event_type
            event_type=$(echo "$json_buffer" | jq -r '.type // ""' 2>/dev/null)
            if [ "$event_type" = "browser_verification" ]; then
              echo "$json_buffer"
            fi
          fi
        fi
        in_json_block=0
        in_event_section=0
        continue
      fi

      if [ "$in_json_block" -eq 1 ]; then
        json_buffer="${json_buffer}${line}"
        continue
      fi

      if echo "$line" | grep -qE '^#{1,4} |^---'; then
        in_event_section=0
        in_json_block=0
        json_buffer=""
      fi
    fi
  done <<< "$comments"
}

# Verify that a browser verification event was posted to GitHub for a task.
#
# Args:
#   $1 - issue number
#   $2 - task id
#   $3 - expected task uid
#   $4 - allowed tools JSON array
#
# Output: verified browser event JSON object, or empty
# Returns: 0 when verified, 1 otherwise
verify_browser_verification_on_github() {
  local issue_number="$1"
  local task_id="$2"
  local expected_uid="$3"
  local allowed_tools_json="${4:-[\"playwright\",\"dev-browser\"]}"

  local recent_comments
  recent_comments=$(gh issue view "$issue_number" --json comments \
    --jq '.comments[-50:][] | @json' 2>/dev/null || echo "")
  if [ -z "$recent_comments" ]; then
    return 1
  fi

  local verified_event=""
  while IFS= read -r raw_comment; do
    [ -z "$raw_comment" ] && continue

    local c_body
    c_body=$(echo "$raw_comment" | jq -r '.body // ""' 2>/dev/null)
    if ! echo "$c_body" | grep -q "## 🌐 Browser Verification: ${task_id}"; then
      continue
    fi

    while IFS= read -r event; do
      [ -z "$event" ] && continue
      local event_task_id event_task_uid event_status event_tool tool_allowed
      event_task_id=$(echo "$event" | jq -r '.taskId // ""' 2>/dev/null)
      event_task_uid=$(echo "$event" | jq -r '.taskUid // ""' 2>/dev/null)
      event_status=$(echo "$event" | jq -r '.status // ""' 2>/dev/null)
      event_tool=$(echo "$event" | jq -r '.tool // ""' 2>/dev/null)
      tool_allowed=$(echo "$allowed_tools_json" | jq -r --arg tool "$event_tool" '
        map(tostring | ascii_downcase) | index(($tool | ascii_downcase)) != null
      ' 2>/dev/null || echo "false")

      if [ "$event_task_id" = "$task_id" ] &&
         [ "$event_task_uid" = "$expected_uid" ] &&
         [ "$(echo "$event_status" | tr '[:upper:]' '[:lower:]')" = "passed" ] &&
         [ "$tool_allowed" = "true" ]; then
        verified_event="$event"
      fi
    done <<< "$(extract_browser_events_from_issue_comments "$c_body" 2>/dev/null || true)"
  done <<< "$recent_comments"

  if [ -z "$verified_event" ]; then
    return 1
  fi

  echo "$verified_event"
  return 0
}

# Compute deterministic dedupe key for pattern memory.
#
# Args:
#   $1 - statement
#   $2 - scope
#
# Output: ptn_ + 12-char hash
compute_pattern_memory_key() {
  local statement="$1"
  local scope="$2"
  local normalized_statement normalized_scope hash
  normalized_statement=$(echo "$statement" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[[:space:]]\{1,\}/ /g')
  normalized_scope=$(echo "$scope" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[[:space:]]\{1,\}/ /g')
  hash=$(echo -n "${normalized_statement}|${normalized_scope}" | shasum -a 256 | cut -c1-12)
  echo "ptn_${hash}"
}

# Ingest high-signal reusable patterns from task event JSON into prd memory.
#
# Args:
#   $1 - path to prd.json
#   $2 - task event JSON object
#   $3 - issue number
#   $4 - max patterns per task
#
# Output: JSON array of newly ingested pattern objects
ingest_task_patterns_into_prd() {
  local prd_file="${1:-prd.json}"
  local event_json="$2"
  local issue_number="$3"
  local max_patterns="${4:-3}"

  if [ -z "$event_json" ] || [ "$event_json" = "null" ]; then
    echo "[]"
    return 0
  fi

  local candidates
  candidates=$(echo "$event_json" | jq -c --argjson max "$max_patterns" '
    [
      (.patterns // [])[]? |
      {
        "statement": ((.statement // "") | tostring | gsub("\\s+"; " ") | sub("^\\s+"; "") | sub("\\s+$"; "")),
        "scope": ((.scope // "global") | tostring),
        "files": [(.files // [])[]? | tostring | select(length > 0)],
        "confidence": (if (.confidence | type) == "number" then .confidence else 0 end)
      } |
      select(.statement | length > 0)
    ][:$max]
  ' 2>/dev/null || echo "[]")

  if [ -z "$candidates" ] || [ "$candidates" = "[]" ]; then
    echo "[]"
    return 0
  fi

  local task_id task_uid commit event_ts event_issue
  task_id=$(echo "$event_json" | jq -r '.taskId // ""' 2>/dev/null)
  task_uid=$(echo "$event_json" | jq -r '.taskUid // ""' 2>/dev/null)
  commit=$(echo "$event_json" | jq -r '.commit // ""' 2>/dev/null)
  event_ts=$(echo "$event_json" | jq -r '.ts // ""' 2>/dev/null)
  event_issue=$(echo "$event_json" | jq -r '.issue // empty' 2>/dev/null)
  if [ -z "$event_issue" ]; then
    event_issue="$issue_number"
  fi

  local added='[]'
  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue
    local statement scope files confidence key exists
    statement=$(echo "$pattern" | jq -r '.statement')
    scope=$(echo "$pattern" | jq -r '.scope')
    files=$(echo "$pattern" | jq -c '.files')
    confidence=$(echo "$pattern" | jq -c '.confidence')
    key=$(compute_pattern_memory_key "$statement" "$scope")
    exists=$(jq -r --arg key "$key" '
      [.memory.patterns[]? | select(.key == $key)] | length > 0
    ' "$prd_file" 2>/dev/null || echo "false")
    if [ "$exists" = "true" ]; then
      continue
    fi

    jq --arg key "$key" \
       --arg statement "$statement" \
       --arg scope "$scope" \
       --arg task_id "$task_id" \
       --arg task_uid "$task_uid" \
       --arg commit "$commit" \
       --arg event_ts "$event_ts" \
       --argjson issue "$event_issue" \
       --argjson files "$files" \
       --argjson confidence "$confidence" '
      .memory.patterns += [{
        "key": $key,
        "statement": $statement,
        "scope": $scope,
        "files": $files,
        "confidence": $confidence,
        "issue": $issue,
        "taskId": (if $task_id == "" then null else $task_id end),
        "taskUid": (if $task_uid == "" then null else $task_uid end),
        "commit": (if $commit == "" then null else $commit end),
        "createdAt": (if $event_ts == "" then (now | todateiso8601) else $event_ts end),
        "syncedDocs": []
      }]
    ' "$prd_file" > "${prd_file}.tmp" && mv "${prd_file}.tmp" "$prd_file"

    added=$(echo "$added" | jq --argjson pattern "$(jq -nc \
      --arg key "$key" \
      --arg statement "$statement" \
      --arg scope "$scope" \
      --argjson files "$files" \
      --argjson confidence "$confidence" \
      '{"key": $key, "statement": $statement, "scope": $scope, "files": $files, "confidence": $confidence}')" '. + [$pattern]')
  done < <(echo "$candidates" | jq -c '.[]')

  echo "$added"
}

# Resolve documentation targets from changed files by walking upward and
# finding the closest existing target docs (AGENTS.md/CLAUDE.md by default).
#
# Args:
#   $1 - commit hash
#   $2 - doc targets JSON array
#
# Output: JSON array of absolute file paths
resolve_doc_targets_for_commit() {
  local commit_hash="$1"
  local doc_targets_json="${2:-[\"AGENTS.md\",\"CLAUDE.md\"]}"
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

  local changed_files
  if [ -n "$commit_hash" ] && [ "$commit_hash" != "null" ]; then
    changed_files=$(git show --name-only --pretty="" "$commit_hash" 2>/dev/null || echo "")
  else
    changed_files=$(git diff --name-only HEAD 2>/dev/null || echo "")
  fi

  local targets=""
  while IFS= read -r rel_path; do
    [ -z "$rel_path" ] && continue
    local dir found
    dir=$(dirname "$rel_path")
    found=0
    while true; do
      while IFS= read -r doc_name; do
        [ -z "$doc_name" ] && continue
        local candidate
        if [ "$dir" = "." ]; then
          candidate="${repo_root}/${doc_name}"
        else
          candidate="${repo_root}/${dir}/${doc_name}"
        fi
        if [ -f "$candidate" ]; then
          if ! echo "$targets" | grep -Fxq "$candidate"; then
            targets=$(printf "%s\n%s" "$targets" "$candidate" | sed '/^$/d')
          fi
          found=1
          break
        fi
      done <<< "$(echo "$doc_targets_json" | jq -r '.[]' 2>/dev/null || true)"

      if [ "$found" -eq 1 ] || [ "$dir" = "." ] || [ "$dir" = "/" ]; then
        break
      fi
      dir=$(dirname "$dir")
    done
  done <<< "$changed_files"

  # Fallback to root docs when no local target was found.
  if [ -z "$targets" ]; then
    while IFS= read -r doc_name; do
      [ -z "$doc_name" ] && continue
      local candidate="${repo_root}/${doc_name}"
      if [ -f "$candidate" ]; then
        targets=$(printf "%s\n%s" "$targets" "$candidate" | sed '/^$/d')
      fi
    done <<< "$(echo "$doc_targets_json" | jq -r '.[]' 2>/dev/null || true)"
  fi

  printf "%s\n" "$targets" | sed '/^$/d' | jq -R -s -c 'split("\n") | map(select(length > 0))'
}

# Upsert managed auto-pattern section in a doc file.
#
# Args:
#   $1 - doc path
#   $2 - marker base (e.g., issues-loop:auto-patterns)
#   $3 - bullets JSON array
#
# Output: "changed" or "unchanged"
upsert_doc_pattern_section() {
  local doc_path="$1"
  local marker="$2"
  local bullets_json="${3:-[]}"

  python3 - "$doc_path" "$marker" "$bullets_json" <<'PY'
import json
import sys
from pathlib import Path

doc_path = Path(sys.argv[1])
marker = sys.argv[2]
bullets = json.loads(sys.argv[3] or "[]")

if not doc_path.exists():
    print("unchanged")
    raise SystemExit(0)

content = doc_path.read_text(encoding="utf-8", errors="ignore")
start_marker = f"<!-- {marker}:start -->"
end_marker = f"<!-- {marker}:end -->"

new_bullets = [b for b in bullets if isinstance(b, str) and b.strip()]
if not new_bullets:
    print("unchanged")
    raise SystemExit(0)

def merge_unique(existing_lines, additions):
    merged = []
    for line in existing_lines + additions:
        line = line.strip()
        if not line:
            continue
        if line not in merged:
            merged.append(line)
    return merged

changed = False
if start_marker in content and end_marker in content and content.index(start_marker) < content.index(end_marker):
    start_idx = content.index(start_marker)
    end_idx = content.index(end_marker)
    section_body = content[start_idx + len(start_marker):end_idx]
    existing = [line.strip() for line in section_body.splitlines() if line.strip().startswith("- ")]
    merged = merge_unique(existing, new_bullets)
    replacement = start_marker + "\n" + "\n".join(merged) + "\n" + end_marker
    original = content[start_idx:end_idx + len(end_marker)]
    if replacement != original:
        content = content[:start_idx] + replacement + content[end_idx + len(end_marker):]
        changed = True
else:
    merged = merge_unique([], new_bullets)
    append_block = "\n\n" + start_marker + "\n" + "\n".join(merged) + "\n" + end_marker + "\n"
    content = content.rstrip() + append_block
    changed = True

if changed:
    doc_path.write_text(content, encoding="utf-8")
    print("changed")
else:
    print("unchanged")
PY
}

# Record synced docs for memory pattern keys.
#
# Args:
#   $1 - prd path
#   $2 - pattern keys JSON array
#   $3 - synced docs JSON array
mark_memory_patterns_synced_docs() {
  local prd_file="${1:-prd.json}"
  local pattern_keys_json="${2:-[]}"
  local synced_docs_json="${3:-[]}"

  jq --argjson keys "$pattern_keys_json" --argjson docs "$synced_docs_json" '
    .memory.patterns = ((.memory.patterns // []) | map(
      if (.key as $k | ($keys | index($k) != null)) then
        .syncedDocs = (((.syncedDocs // []) + $docs) | unique)
      else . end
    ))
  ' "$prd_file" > "${prd_file}.tmp" && mv "${prd_file}.tmp" "$prd_file"
}

# Sync high-confidence task patterns into target AGENTS/CLAUDE docs.
#
# Args:
#   $1 - prd path
#   $2 - issue number
#   $3 - task id
#   $4 - task uid
#   $5 - commit hash
#   $6 - patterns JSON array (newly ingested)
#   $7 - auto-sync docs flag
#   $8 - min confidence
#   $9 - doc targets JSON array
#   $10 - managed section marker
#
# Output: JSON object {"docsChanged":bool,"syncedDocs":[...],"syncedPatternKeys":[...]}
sync_task_patterns_to_docs() {
  local prd_file="${1:-prd.json}"
  local issue_number="$2"
  local task_id="$3"
  local task_uid="$4"
  local commit_hash="$5"
  local patterns_json="${6:-[]}"
  local auto_sync="${7:-true}"
  local min_confidence="${8:-0.8}"
  local doc_targets_json="${9:-[\"AGENTS.md\",\"CLAUDE.md\"]}"
  local marker="${10:-issues-loop:auto-patterns}"

  if [ "$(echo "$auto_sync" | tr '[:upper:]' '[:lower:]')" != "true" ]; then
    echo '{"docsChanged":false,"syncedDocs":[],"syncedPatternKeys":[]}'
    return 0
  fi
  if [ -z "$patterns_json" ] || [ "$patterns_json" = "[]" ] || [ "$patterns_json" = "null" ]; then
    echo '{"docsChanged":false,"syncedDocs":[],"syncedPatternKeys":[]}'
    return 0
  fi

  local eligible_patterns
  eligible_patterns=$(echo "$patterns_json" | jq -c --argjson min "$min_confidence" '
    [.[] | select((.confidence // 0) >= $min)]
  ' 2>/dev/null || echo "[]")
  if [ "$eligible_patterns" = "[]" ]; then
    echo '{"docsChanged":false,"syncedDocs":[],"syncedPatternKeys":[]}'
    return 0
  fi

  local target_docs_json
  target_docs_json=$(resolve_doc_targets_for_commit "$commit_hash" "$doc_targets_json")
  if [ -z "$target_docs_json" ] || [ "$target_docs_json" = "[]" ]; then
    echo '{"docsChanged":false,"syncedDocs":[],"syncedPatternKeys":[]}'
    return 0
  fi

  local bullet_lines_json
  bullet_lines_json=$(echo "$eligible_patterns" | jq -c --arg issue "$issue_number" --arg task "$task_id" '
    [.[] | "- [\(.scope)] \(.statement) (source: #\($issue) \($task))"]
  ')

  local docs_changed="false"
  local synced_docs='[]'
  while IFS= read -r doc_path; do
    [ -z "$doc_path" ] && continue
    local upsert_result
    upsert_result=$(upsert_doc_pattern_section "$doc_path" "$marker" "$bullet_lines_json")
    if [ "$upsert_result" = "changed" ]; then
      docs_changed="true"
      synced_docs=$(echo "$synced_docs" | jq --arg path "$doc_path" '. + [$path] | unique')
    fi
  done < <(echo "$target_docs_json" | jq -r '.[]')

  if [ "$docs_changed" = "true" ]; then
    local synced_keys
    synced_keys=$(echo "$eligible_patterns" | jq -c '[.[].key]')
    mark_memory_patterns_synced_docs "$prd_file" "$synced_keys" "$synced_docs"
    jq -nc --argjson docs "$synced_docs" --argjson keys "$synced_keys" \
      '{"docsChanged":true,"syncedDocs":$docs,"syncedPatternKeys":$keys}'
    return 0
  fi

  echo '{"docsChanged":false,"syncedDocs":[],"syncedPatternKeys":[]}'
}

# Scan added lines for placeholder patterns.
#
# Args:
#   $1 - commit hash to inspect, or "WORKTREE" for unstaged/staged worktree diff
#   $2 - placeholder regex patterns JSON array
#   $3 - file exclude regex JSON array
#   $4 - semantic check config JSON object
#
# Output: JSON array of matches
# [{"file":"...","line":42,"pattern":"TODO\\b","snippet":"TODO: ..."}]
scan_placeholder_patterns() {
  local commit_target="${1:-WORKTREE}"
  local patterns_json="${2:-[]}"
  local exclude_json="${3:-[]}"
  local semantic_config_json="${4:-}"
  [ -n "$semantic_config_json" ] || semantic_config_json='{}'
  if ! echo "$semantic_config_json" | jq -e '.' >/dev/null 2>&1; then
    semantic_config_json='{}'
  fi

  local diff_file
  diff_file=$(mktemp)

  if [ -n "$commit_target" ] && [ "$commit_target" != "WORKTREE" ] && [ "$commit_target" != "null" ]; then
    git show --no-color --unified=0 --pretty="" "$commit_target" > "$diff_file" 2>/dev/null || true
  else
    git diff --no-color --unified=0 HEAD > "$diff_file" 2>/dev/null || git diff --no-color --unified=0 > "$diff_file" 2>/dev/null || true
  fi

  python3 - "$patterns_json" "$exclude_json" "$semantic_config_json" "$diff_file" <<'PY'
import json
import re
import sys

patterns = json.loads(sys.argv[1] or "[]")
exclude = json.loads(sys.argv[2] or "[]")
semantic = json.loads(sys.argv[3] or "{}")
diff_path = sys.argv[4]

try:
    with open(diff_path, "r", encoding="utf-8", errors="ignore") as f:
        diff = f.read().splitlines()
except FileNotFoundError:
    print("[]")
    raise SystemExit(0)

exclude_re = [re.compile(x, re.IGNORECASE) for x in exclude if x]
compiled = []
for p in patterns:
    if not p:
        continue
    try:
        compiled.append((p, re.compile(p, re.IGNORECASE)))
    except re.error:
        continue

matches = []
current_file = None
line_no = 0
semantic_enabled = bool(semantic.get("enabled", False))
block_trivial_return = bool(semantic.get("blockTrivialConstantReturns", True))
block_constant_conditional = bool(semantic.get("blockAlwaysTrueFalseConditionals", True))

trivial_return_re = re.compile(
    r'^\s*return\s+('
    r'true|false|null|nil|None|[0-9]+(?:\.[0-9]+)?|'
    r'"[^"]*"|\'[^\']*\''
    r')\s*;?\s*$',
    re.IGNORECASE,
)
constant_conditional_re = re.compile(
    r'^\s*(if|while)\s*\(\s*(true|false|0|1)\s*\)',
    re.IGNORECASE,
)

for line in diff:
    if line.startswith("+++ "):
        path = line[4:].strip()
        if path.startswith("b/"):
            path = path[2:]
        current_file = path
        continue
    if line.startswith("@@ "):
        m = re.search(r"\+(\d+)", line)
        line_no = int(m.group(1)) if m else 0
        continue
    if current_file is None:
        continue
    if any(r.search(current_file) for r in exclude_re):
        continue
    if line.startswith("+") and not line.startswith("+++"):
        snippet = line[1:]
        recorded = False
        for original, pattern in compiled:
            if pattern.search(snippet):
                matches.append(
                    {
                        "file": current_file,
                        "line": line_no,
                        "pattern": original,
                        "snippet": snippet[:200],
                    }
                )
                recorded = True
                break
        if semantic_enabled and not recorded:
            if block_trivial_return and trivial_return_re.search(snippet):
                matches.append(
                    {
                        "file": current_file,
                        "line": line_no,
                        "pattern": "__SEMANTIC_TRIVIAL_CONSTANT_RETURN__",
                        "snippet": snippet[:200],
                    }
                )
                recorded = True
            if block_constant_conditional and not recorded and constant_conditional_re.search(snippet):
                matches.append(
                    {
                        "file": current_file,
                        "line": line_no,
                        "pattern": "__SEMANTIC_CONSTANT_CONDITIONAL__",
                        "snippet": snippet[:200],
                    }
                )
        line_no += 1
    elif line.startswith(" "):
        line_no += 1

print(json.dumps(matches, separators=(",", ":")))
PY

  rm -f "$diff_file"
}

# Fetch issue body + comments in one GitHub API call.
#
# Args:
#   $1 - issue number
#
# Output: JSON object {"body":"...","comments":[...]}
fetch_issue_snapshot() {
  local issue_number="$1"
  local snapshot
  snapshot=$(gh issue view "$issue_number" --json body,comments 2>/dev/null || echo "")

  if [ -z "$snapshot" ]; then
    echo '{"body":"","comments":[]}'
    return 0
  fi

  echo "$snapshot" | jq -c '{
    body: (.body // ""),
    comments: (.comments // [])
  }' 2>/dev/null || echo '{"body":"","comments":[]}'
}

# Build a compact memory bundle from issue comments to keep context lean.
#
# Args:
#   $1 - issue number
#   $2 - prefer compacted summary ("true"/"false")
#   $3 - max task logs
#   $4 - max discovery notes
#   $5 - max review logs
#   $6 - optional pre-fetched comments JSON array
#
# Output: markdown string
build_issue_context_bundle() {
  local issue_number="$1"
  local prefer_compacted="${2:-true}"
  local max_task_logs="${3:-8}"
  local max_discovery_notes="${4:-6}"
  local max_review_logs="${5:-4}"
  local comments_json="${6:-}"

  if [ -z "$comments_json" ]; then
    comments_json=$(gh issue view "$issue_number" --json comments --jq '.comments' 2>/dev/null || echo "[]")
  fi

  local plan_body compacted_summary task_logs discovery_notes review_logs
  plan_body=$(echo "$comments_json" | jq -r '[.[] | select(.body | startswith("## 📋 Implementation Plan"))][-1].body // ""')
  compacted_summary=$(echo "$comments_json" | jq -r '[.[] | select(.body | startswith("## 🧾 Compacted Summary"))][-1].body // ""')
  task_logs=$(echo "$comments_json" | jq -r --argjson n "$max_task_logs" \
    '[.[] | select(.body | startswith("## 📝 Task Log:")) | .body][-1 * $n:] | join("\n\n---\n\n")')
  discovery_notes=$(echo "$comments_json" | jq -r --argjson n "$max_discovery_notes" \
    '[.[] | select(.body | startswith("## 🔍 Discovery Note")) | .body][-1 * $n:] | join("\n\n---\n\n")')
  review_logs=$(echo "$comments_json" | jq -r --argjson n "$max_review_logs" \
    '[.[] | select(.body | startswith("## 🔎 Code Review:")) | .body][-1 * $n:] | join("\n\n---\n\n")')

  local bundle="### Implementation Plan Snapshot
${plan_body:-No implementation plan comment found.}"

  local prefer_lower
  prefer_lower=$(echo "$prefer_compacted" | tr '[:upper:]' '[:lower:]')
  if [ "$prefer_lower" = "true" ] && [ -n "$compacted_summary" ]; then
    bundle="${bundle}

### Latest Compacted Summary (Preferred)
${compacted_summary}"
  fi

  bundle="${bundle}

### Recent Task Logs
${task_logs:-No recent task logs found.}

### Recent Discovery Notes
${discovery_notes:-No recent discovery notes found.}

### Recent Review Logs
${review_logs:-No recent review logs found.}"

  echo "$bundle"
}

# Update quality.execution retry counters after each authoritative outcome.
#
# Args:
#   $1 - path to prd.json
#   $2 - task id
#   $3 - outcome ("pass"|"retry"|"blocked")
#
# Output: current quality.execution object
update_execution_retry_counters() {
  local prd_file="${1:-prd.json}"
  local task_id="$2"
  local outcome="$3"

  jq --arg task_id "$task_id" --arg outcome "$outcome" '
    .quality.execution = ((.quality.execution // {
      "consecutiveRetries": 0,
      "currentTaskId": null,
      "currentTaskRetryStreak": 0,
      "lastReplanAt": null,
      "lastReplanReason": null
    }) | (
      if ($outcome == "pass") then
        .consecutiveRetries = 0 |
        .currentTaskId = $task_id |
        .currentTaskRetryStreak = 0
      else
        .consecutiveRetries = ((.consecutiveRetries // 0) + 1) |
        .currentTaskRetryStreak = (
          if (.currentTaskId == $task_id) then ((.currentTaskRetryStreak // 0) + 1)
          else 1
          end
        ) |
        .currentTaskId = $task_id
      end
    ))
  ' "$prd_file" > "${prd_file}.tmp" && mv "${prd_file}.tmp" "$prd_file"

  jq -c '.quality.execution' "$prd_file"
}

# Return stale-plan trigger reason when retry counters exceed thresholds.
#
# Args:
#   $1 - path to prd.json
#   $2 - same-task threshold
#   $3 - consecutive threshold
#
# Output: reason string (empty when no trigger)
should_trigger_stale_plan() {
  local prd_file="${1:-prd.json}"
  local same_task_threshold="${2:-2}"
  local consecutive_threshold="${3:-4}"

  jq -r --argjson same "$same_task_threshold" --argjson consecutive "$consecutive_threshold" '
    (.quality.execution.currentTaskRetryStreak // 0) as $same_count |
    (.quality.execution.consecutiveRetries // 0) as $consecutive_count |
    if $same_count >= $same then
      ("same task retries reached " + ($same_count | tostring))
    elif $consecutive_count >= $consecutive then
      ("consecutive retries reached " + ($consecutive_count | tostring))
    else
      ""
    end
  ' "$prd_file" 2>/dev/null || echo ""
}

# Mark prd.json as requiring replan and record reason.
#
# Args:
#   $1 - path to prd.json
#   $2 - reason
mark_replan_required() {
  local prd_file="${1:-prd.json}"
  local reason="$2"
  local now_ts
  now_ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  jq --arg reason "$reason" --arg now_ts "$now_ts" '
    .debugState.status = "replan_required" |
    .quality.execution.lastReplanAt = $now_ts |
    .quality.execution.lastReplanReason = $reason |
    .quality.execution.consecutiveRetries = 0 |
    .quality.execution.currentTaskRetryStreak = 0 |
    .quality.execution.currentTaskId = null
  ' "$prd_file" > "${prd_file}.tmp" && mv "${prd_file}.tmp" "$prd_file"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Discovered-Task Auto-Enqueue
# ═══════════════════════════════════════════════════════════════════════════════

# Compute a fingerprint hash for deduplication of discovered tasks.
# Uses title + description + acceptanceCriteria + parent uid — NOT just title.
#
# Args:
#   $1 - task title
#   $2 - task description
#   $3 - acceptanceCriteria (JSON array as string, e.g. '["criterion1","criterion2"]')
#   $4 - parent task uid
#
# Output: 12-char hex fingerprint hash
compute_task_fingerprint() {
  local title="$1"
  local description="$2"
  local acceptance_criteria="$3"
  local parent_uid="$4"

  # Normalize: lowercase, trim, collapse whitespace
  local norm_title norm_desc norm_criteria
  norm_title=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[[:space:]]\{1,\}/ /g')
  norm_desc=$(echo "$description" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[[:space:]]\{1,\}/ /g')
  norm_criteria=$(echo "$acceptance_criteria" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[[:space:]]\{1,\}/ /g')

  local input="${norm_title}|${norm_desc}|${norm_criteria}|${parent_uid}"
  echo -n "$input" | shasum -a 256 | cut -c1-12
}

# Enqueue discovered tasks from a task log event into prd.json.
# Deduplicates using fingerprint hash (title + description + acceptanceCriteria + parent uid).
# Appends new tasks with generated uid, discoveredFrom=parent uid, ordinal within parent,
# default priority=parent+1, dependsOn=[parent id].
# Commits prd.json state update after enqueue.
#
# Args:
#   $1 - path to prd.json (default: "prd.json")
#   $2 - parent task id (e.g., "US-003")
#   $3 - parent task uid (e.g., "tsk_a1b2c3d4e5f6")
#   $4 - parent task priority (integer)
#   $5 - discovered tasks JSON array (compact JSON string)
#        Each element: {"title":"...","description":"...","acceptanceCriteria":[...],"verifyCommands":[...],"dependsOn":[...]}
#   $6 - issue number
#   $7 - discovery source tag (default: "task_log")
#
# Side effects: modifies prd.json in place, commits the change
enqueue_discovered_tasks() {
  local prd_file="${1:-prd.json}"
  local parent_id="$2"
  local parent_uid="$3"
  local parent_priority="$4"
  local discovered_json="$5"
  local issue_number="$6"
  local discovery_source="${7:-task_log}"

  if [ -z "$discovered_json" ] || [ "$discovered_json" = "[]" ] || [ "$discovered_json" = "null" ]; then
    return 0
  fi

  local discovered_count
  discovered_count=$(echo "$discovered_json" | jq 'length' 2>/dev/null || echo "0")

  if [ "$discovered_count" -eq 0 ]; then
    return 0
  fi

  # Count existing discovered tasks from this parent to determine ordinal offset
  local existing_from_parent
  existing_from_parent=$(jq --arg puid "$parent_uid" \
    '[.userStories[] | select(.discoveredFrom == $puid)] | length' "$prd_file")

  # Collect existing fingerprints for deduplication
  local existing_fingerprints
  existing_fingerprints=$(jq -r --arg puid "$parent_uid" \
    '.userStories[] | select(.discoveredFrom == $puid) |
     "\(.title)\t\(.description)\t\(.acceptanceCriteria | join(","))"' "$prd_file" 2>/dev/null || echo "")

  # Compute fingerprints for existing tasks from this parent
  local existing_fp_hashes=""
  if [ -n "$existing_fingerprints" ]; then
    while IFS=$'\t' read -r ex_title ex_desc ex_criteria; do
      local ex_fp
      ex_fp=$(compute_task_fingerprint "$ex_title" "$ex_desc" "$ex_criteria" "$parent_uid")
      existing_fp_hashes="${existing_fp_hashes}${ex_fp} "
    done <<< "$existing_fingerprints"
  fi

  # Get the next US-### id number
  local max_id_num
  max_id_num=$(jq '[.userStories[].id | capture("US-(?<n>[0-9]+)") | .n | tonumber] | max // 0' "$prd_file")

  local enqueued=0
  local ordinal_offset=$((existing_from_parent))
  local new_id_num=$((max_id_num))

  local i=0
  while [ "$i" -lt "$discovered_count" ]; do
    local d_title d_desc d_criteria_json d_criteria_str d_verify_json d_depends_json

    d_title=$(echo "$discovered_json" | jq -r --argjson idx "$i" '.[$idx].title // ""')
    d_desc=$(echo "$discovered_json" | jq -r --argjson idx "$i" '.[$idx].description // ""')
    d_criteria_json=$(echo "$discovered_json" | jq -c --argjson idx "$i" '.[$idx].acceptanceCriteria // []')
    d_criteria_str=$(echo "$d_criteria_json" | jq -r 'join(",")')
    d_verify_json=$(echo "$discovered_json" | jq -c --argjson idx "$i" '.[$idx].verifyCommands // []')
    d_depends_json=$(echo "$discovered_json" | jq -c --argjson idx "$i" '.[$idx].dependsOn // []')

    # Compute fingerprint for deduplication
    local fingerprint
    fingerprint=$(compute_task_fingerprint "$d_title" "$d_desc" "$d_criteria_str" "$parent_uid")

    # Check if this fingerprint already exists
    if echo "$existing_fp_hashes" | grep -q "$fingerprint"; then
      i=$((i + 1))
      continue
    fi

    # Compute ordinal within this parent (1-based)
    ordinal_offset=$((ordinal_offset + 1))
    local ordinal=$ordinal_offset

    # Generate uid
    local new_uid
    new_uid=$(generate_task_uid "$issue_number" "$d_title" "$parent_uid" "$ordinal")

    # Generate next US-### id
    new_id_num=$((new_id_num + 1))
    local new_id
    new_id=$(printf "US-%03d" "$new_id_num")

    # Default priority = parent priority + 1
    local new_priority=$((parent_priority + 1))

    # Default dependsOn = [parent_id] unless explicitly provided
    if [ "$d_depends_json" = "[]" ] || [ -z "$d_depends_json" ]; then
      d_depends_json=$(jq -nc --arg pid "$parent_id" '[$pid]')
    fi

    # Append to prd.json
    jq --arg id "$new_id" \
       --arg uid "$new_uid" \
       --argjson priority "$new_priority" \
       --arg title "$d_title" \
       --arg desc "$d_desc" \
       --argjson criteria "$d_criteria_json" \
       --argjson verify "$d_verify_json" \
       --argjson depends "$d_depends_json" \
       --arg parent_uid "$parent_uid" \
       --arg discovery_source "$discovery_source" \
       '.userStories += [{
         "id": $id,
         "uid": $uid,
         "phase": null,
         "priority": $priority,
         "title": $title,
         "description": $desc,
         "files": [],
         "dependsOn": $depends,
         "discoveredFrom": $parent_uid,
         "discoverySource": $discovery_source,
         "acceptanceCriteria": $criteria,
         "verifyCommands": $verify,
         "passes": false,
         "attempts": 0,
         "lastAttempt": null
       }]' "$prd_file" > "${prd_file}.tmp" && mv "${prd_file}.tmp" "$prd_file"

    # Track this fingerprint to prevent duplicates within same batch
    existing_fp_hashes="${existing_fp_hashes}${fingerprint} "
    enqueued=$((enqueued + 1))

    i=$((i + 1))
  done

  # Commit prd.json state update if any tasks were enqueued
  if [ "$enqueued" -gt 0 ]; then
    git add "$prd_file"
    git commit -m "chore: enqueue $enqueued discovered task(s) from $parent_id (#$issue_number)" 2>/dev/null || true
  fi

  return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# Review Event Extraction and State Management
# ═══════════════════════════════════════════════════════════════════════════════

# Extract review JSON event blocks from issue comments.
# Parses only fenced json code blocks under '### Review Event JSON' headings.
#
# Args:
#   $1 - raw issue comments text
#
# Output: one JSON review event object per line (compact)
extract_review_events_from_issue_comments() {
  local comments="$1"
  local in_event_section=0
  local in_json_block=0
  local json_buffer=""

  while IFS= read -r line; do
    if echo "$line" | grep -qiE '^[[:space:]]*###?[[:space:]]*Review Event JSON[[:space:]]*$'; then
      in_event_section=1
      in_json_block=0
      json_buffer=""
      continue
    fi

    if [ "$in_event_section" -eq 1 ]; then
      if [ "$in_json_block" -eq 0 ] && echo "$line" | grep -qiE '^[[:space:]]*```([[:space:]]*json)?[[:space:]]*$'; then
        in_json_block=1
        json_buffer=""
        continue
      fi

      if [ "$in_json_block" -eq 1 ] && echo "$line" | grep -qE '^\s*```\s*$'; then
        if [ -n "$json_buffer" ]; then
          if echo "$json_buffer" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
            local event_type
            event_type=$(echo "$json_buffer" | jq -r '.type // ""' 2>/dev/null)
            if [ "$event_type" = "review_log" ]; then
              echo "$json_buffer"
            fi
          fi
        fi
        in_json_block=0
        in_event_section=0
        continue
      fi

      if [ "$in_json_block" -eq 1 ]; then
        json_buffer="${json_buffer}${line}"
        continue
      fi

      if echo "$line" | grep -qE '^#{1,4} |^---'; then
        in_event_section=0
        in_json_block=0
        json_buffer=""
      fi
    fi
  done <<< "$comments"
}

# Slice comments array to entries newer than a cursor URL.
#
# Args:
#   $1 - comments JSON array
#   $2 - cursor URL (empty means no cursor)
#
# Output: comments JSON array (from cursor+1 to end, or full array if cursor missing)
slice_comments_after_cursor() {
  local comments_json="$1"
  local cursor_url="$2"

  if [ -z "$comments_json" ]; then
    echo "[]"
    return 0
  fi

  echo "$comments_json" | jq -c --arg cursor "$cursor_url" '
    . as $comments |
    (
      if $cursor == "" then
        null
      else
        ([range(0; ($comments | length)) | select($comments[.].url == $cursor)] | last)
      end
    ) as $cursor_idx |
    if $cursor_idx == null then
      $comments
    else
      $comments[($cursor_idx + 1):]
    end
  ' 2>/dev/null || echo "[]"
}

# Verify that a review log with Review Event JSON was posted to GitHub.
#
# Args:
#   $1 - issue number
#   $2 - review scope label (e.g., US-003 or FINAL)
#   $3 - reviewed commit hash (optional; if provided must match)
#   $4 - optional pre-fetched recent comments (jsonl via @json rows)
#
# Output: verified review event JSON object, or empty
# Returns: 0 if verified, 1 otherwise
verify_review_log_on_github() {
  local issue_number="$1"
  local scope_label="$2"
  local reviewed_commit="$3"
  local recent_comments="${4:-}"
  local scope_label_lc
  scope_label_lc=$(printf '%s' "$scope_label" | tr '[:upper:]' '[:lower:]')

  if [ -z "$recent_comments" ]; then
    recent_comments=$(gh issue view "$issue_number" --json comments \
      --jq '.comments[-30:][] | @json' 2>/dev/null || echo "")
  fi

  if [ -z "$recent_comments" ]; then
    return 1
  fi

  local review_event=""
  while IFS= read -r raw_comment; do
    [ -z "$raw_comment" ] && continue
    local c_body
    c_body=$(echo "$raw_comment" | jq -r '.body // ""' 2>/dev/null)
    [ -n "$c_body" ] || continue

    local extracted_events
    extracted_events=$(extract_review_events_from_issue_comments "$c_body" 2>/dev/null || echo "")
    [ -n "$extracted_events" ] || continue

    while IFS= read -r extracted; do
      [ -n "$extracted" ] || continue

      local parent_task_id parent_task_id_lc extracted_scope extracted_scope_lc extracted_commit
      parent_task_id=$(echo "$extracted" | jq -r '.parentTaskId // ""' 2>/dev/null)
      extracted_scope=$(echo "$extracted" | jq -r '.scope // ""' 2>/dev/null)
      extracted_commit=$(echo "$extracted" | jq -r '.reviewedCommit // ""' 2>/dev/null)

      parent_task_id_lc=$(printf '%s' "$parent_task_id" | tr '[:upper:]' '[:lower:]')
      extracted_scope_lc=$(printf '%s' "$extracted_scope" | tr '[:upper:]' '[:lower:]')

      if [ -n "$scope_label" ] && \
         [ "$parent_task_id_lc" != "$scope_label_lc" ] && \
         [ "$extracted_scope_lc" != "$scope_label_lc" ]; then
        continue
      fi

      if [ -n "$reviewed_commit" ] && [ "$reviewed_commit" != "$extracted_commit" ]; then
        continue
      fi

      review_event="$extracted"
    done <<< "$extracted_events"
  done <<< "$recent_comments"

  if [ -z "$review_event" ]; then
    return 1
  fi

  echo "$review_event"
  return 0
}

# Ingest findings from a single review event into prd.json quality state.
#
# Args:
#   $1 - path to prd.json (default: "prd.json")
#   $2 - review event JSON object (compact)
#   $3 - issue number
#
# Output: integer count of new findings ingested
ingest_review_findings_into_prd() {
  local prd_file="${1:-prd.json}"
  local review_event="$2"
  local issue_number="$3"

  if [ -z "$review_event" ] || [ "$review_event" = "null" ]; then
    echo "0"
    return 0
  fi

  local findings_count
  findings_count=$(echo "$review_event" | jq '.findings | length' 2>/dev/null || echo "0")
  if [ "$findings_count" -eq 0 ]; then
    echo "0"
    return 0
  fi

  local ingested=0
  local review_id scope parent_task_id parent_task_uid reviewed_commit event_ts
  review_id=$(echo "$review_event" | jq -r '.reviewId // ""' 2>/dev/null)
  scope=$(echo "$review_event" | jq -r '.scope // "task"' 2>/dev/null)
  parent_task_id=$(echo "$review_event" | jq -r '.parentTaskId // ""' 2>/dev/null)
  parent_task_uid=$(echo "$review_event" | jq -r '.parentTaskUid // ""' 2>/dev/null)
  reviewed_commit=$(echo "$review_event" | jq -r '.reviewedCommit // ""' 2>/dev/null)
  event_ts=$(echo "$review_event" | jq -r '.ts // ""' 2>/dev/null)

  local i=0
  while [ "$i" -lt "$findings_count" ]; do
    local finding finding_id key is_processed
    finding=$(echo "$review_event" | jq -c --argjson idx "$i" '.findings[$idx]')
    finding_id=$(echo "$finding" | jq -r '.id // ""' 2>/dev/null)
    if [ -z "$finding_id" ] || [ -z "$review_id" ]; then
      i=$((i + 1))
      continue
    fi

    key="${review_id}:${finding_id}"
    is_processed=$(jq -r --arg key "$key" '.quality.processedReviewKeys // [] | index($key) != null' "$prd_file" 2>/dev/null || echo "false")
    if [ "$is_processed" = "true" ]; then
      i=$((i + 1))
      continue
    fi

    jq --arg key "$key" \
       --arg review_id "$review_id" \
       --arg finding_id "$finding_id" \
       --arg scope "$scope" \
       --arg parent_task_id "$parent_task_id" \
       --arg parent_task_uid "$parent_task_uid" \
       --arg reviewed_commit "$reviewed_commit" \
       --arg issue_number "$issue_number" \
       --arg event_ts "$event_ts" \
       --argjson finding "$finding" \
       '.quality.processedReviewKeys += [$key] |
        .quality.findings += [{
          "key": $key,
          "reviewId": $review_id,
          "findingId": $finding_id,
          "issue": ($issue_number | tonumber),
          "scope": $scope,
          "parentTaskId": (if $parent_task_id == "" then null else $parent_task_id end),
          "parentTaskUid": (if $parent_task_uid == "" then null else $parent_task_uid end),
          "reviewedCommit": (if $reviewed_commit == "" then null else $reviewed_commit end),
          "severity": ($finding.severity // "medium"),
          "confidence": ($finding.confidence // 0),
          "category": ($finding.category // "adherence"),
          "title": ($finding.title // ""),
          "description": ($finding.description // ""),
          "evidence": ($finding.evidence // []),
          "suggestedTask": ($finding.suggestedTask // null),
          "status": "open",
          "createdAt": (if $event_ts == "" then (now | todateiso8601) else $event_ts end),
          "updatedAt": (if $event_ts == "" then (now | todateiso8601) else $event_ts end),
          "enqueuedTaskIds": []
        }]' "$prd_file" > "${prd_file}.tmp" && mv "${prd_file}.tmp" "$prd_file"

    ingested=$((ingested + 1))
    i=$((i + 1))
  done

  echo "$ingested"
  return 0
}

# Build the list of review findings that are eligible for auto-enqueue.
#
# Args:
#   $1 - path to prd.json (default: "prd.json")
#
# Output: JSON array of finding objects
build_enqueuable_review_tasks() {
  local prd_file="${1:-prd.json}"
  jq -c '
    (.quality.reviewPolicy.autoEnqueueSeverities // ["critical"]) as $autoSev |
    (.quality.reviewPolicy.minConfidenceForAutoEnqueue // 0.75) as $minConf |
    [
      (.quality.findings // [])[] |
      select(.status == "open") |
      select((.severity // "" | ascii_downcase) as $sev | any($autoSev[]; ascii_downcase == $sev)) |
      select((.confidence // 0) >= $minConf)
    ]
  ' "$prd_file" 2>/dev/null || echo "[]"
}

# Mark findings as enqueued after corresponding tasks are inserted.
#
# Args:
#   $1 - path to prd.json (default: "prd.json")
#   $2 - JSON array of finding keys
#   $3 - optional enqueued task id (single) to append
mark_enqueued_findings() {
  local prd_file="${1:-prd.json}"
  local finding_keys_json="${2:-[]}"
  local enqueued_task_id="${3:-}"

  if [ -z "$finding_keys_json" ] || [ "$finding_keys_json" = "[]" ]; then
    return 0
  fi

  jq --argjson keys "$finding_keys_json" --arg task_id "$enqueued_task_id" '
    .quality.findings = ((.quality.findings // []) | map(
      if (.key as $k | ($keys | index($k) != null)) then
        .status = "enqueued" |
        .updatedAt = (now | todateiso8601) |
        .enqueuedTaskIds = (
          if ($task_id == "") then (.enqueuedTaskIds // [])
          else ((.enqueuedTaskIds // []) + [$task_id] | unique)
          end
        )
      else . end
    ))
  ' "$prd_file" > "${prd_file}.tmp" && mv "${prd_file}.tmp" "$prd_file"
}

# Reconcile enqueued findings against code_review tasks in prd.json.
# If all mapped code_review tasks for a finding have passed, mark it resolved.
reconcile_review_findings() {
  local prd_file="${1:-prd.json}"
  jq '
    . as $root |
    .quality.findings = ((.quality.findings // []) | map(
      . as $finding |
      if ($finding.status == "enqueued" or $finding.status == "open") and ($finding.key // "") != "" then
        (
          [
            $root.userStories[]? |
            select(.discoverySource == "code_review") |
            select((.description // "") | contains("Review Finding Key: " + ($finding.key)))
          ] as $tasks |
          if ($tasks | length) == 0 then $finding
          elif (any($tasks[]; .passes == true)) then $finding | .status = "resolved" | .updatedAt = (now | todateiso8601)
          else $finding | .status = "enqueued"
          end
        )
      else $finding end
    ))
  ' "$prd_file" > "${prd_file}.tmp" && mv "${prd_file}.tmp" "$prd_file"
}

# Return count of open blocking findings (auto-enqueue severities).
count_open_blocking_review_findings() {
  local prd_file="${1:-prd.json}"
  jq -r '
    (.quality.reviewPolicy.autoEnqueueSeverities // ["critical"]) as $autoSev |
    [
      (.quality.findings // [])[] |
      select((.status // "open") == "open") |
      select((.severity // "" | ascii_downcase) as $sev | any($autoSev[]; ascii_downcase == $sev))
    ] | length
  ' "$prd_file" 2>/dev/null || echo "0"
}

# Mark final review state in quality metadata.
#
# Args:
#   $1 - path to prd.json (default: "prd.json")
#   $2 - status: pending|running|passed|failed
#   $3 - reviewed commit hash (optional)
#   $4 - review id (optional)
mark_final_review_status() {
  local prd_file="${1:-prd.json}"
  local status="$2"
  local reviewed_commit="$3"
  local review_id="$4"

  jq --arg status "$status" --arg reviewed_commit "$reviewed_commit" --arg review_id "$review_id" '
    .quality.finalReview.status = $status |
    .quality.finalReview.reviewedCommit = (if $reviewed_commit == "" then null else $reviewed_commit end) |
    .quality.finalReview.lastReviewId = (if $review_id == "" then .quality.finalReview.lastReviewId else $review_id end) |
    .quality.finalReview.updatedAt = (now | todateiso8601)
  ' "$prd_file" > "${prd_file}.tmp" && mv "${prd_file}.tmp" "$prd_file"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Compaction Summary
# ═══════════════════════════════════════════════════════════════════════════════

# Increment the compaction counter and post a compacted summary when the
# threshold is reached (default: every 10 task logs).
#
# Call this after every successful task log post. It:
#   1. Increments prd.json.compaction.taskLogCountSinceLastSummary
#   2. If count >= summaryEveryNTaskLogs (default 10):
#      a. Collects covered task UIDs and attempt numbers from recent task logs
#      b. Finds previous compaction summary comment URL (supersedes pointer, or 'none')
#      c. Posts '## 🧾 Compacted Summary' to the GitHub issue
#      d. Resets counter to 0
#   3. Commits prd.json state update
#
# Args:
#   $1 - path to prd.json (default: "prd.json")
#   $2 - issue number
#   $3 - task id just completed (e.g., "US-003")
#   $4 - task uid just completed
#   $5 - attempt number for the just-completed task
#
# Side effects: modifies prd.json, may post GitHub comment, commits state
maybe_post_compaction_summary() {
  local prd_file="${1:-prd.json}"
  local issue_number="$2"
  local task_id="$3"
  local task_uid="$4"
  local attempt="$5"

  if [ ! -f "$prd_file" ]; then
    return 1
  fi

  # Increment taskLogCountSinceLastSummary
  jq '.compaction.taskLogCountSinceLastSummary = ((.compaction.taskLogCountSinceLastSummary // 0) + 1)' \
    "$prd_file" > "${prd_file}.tmp" && mv "${prd_file}.tmp" "$prd_file"

  local current_count
  current_count=$(jq '.compaction.taskLogCountSinceLastSummary // 0' "$prd_file")

  local threshold
  threshold=$(jq '.compaction.summaryEveryNTaskLogs // 10' "$prd_file")

  # Check if we've hit the threshold
  if [ "$current_count" -lt "$threshold" ]; then
    # Not yet time for a summary - just commit the counter update
    git add "$prd_file"
    git commit -m "chore: update compaction counter ($current_count/$threshold) (#$issue_number)" 2>/dev/null || true
    return 0
  fi

  # Time to post a compacted summary!

  # Collect covered task UIDs and attempts from recent task logs
  # Parse JSON events from issue comments to find recent task logs
  local comments
  comments=$(gh issue view "$issue_number" --json comments --jq '.comments[] | .body' 2>/dev/null || echo "")

  local covered_tasks=""
  local json_events
  json_events=$(extract_json_events_from_issue_comments "$comments")

  if [ -n "$json_events" ]; then
    # Extract task UIDs and attempts from JSON events
    covered_tasks=$(echo "$json_events" | while IFS= read -r event; do
      local tid tuid status att
      tid=$(echo "$event" | jq -r '.taskId // ""' 2>/dev/null)
      tuid=$(echo "$event" | jq -r '.taskUid // ""' 2>/dev/null)
      status=$(echo "$event" | jq -r '.status // ""' 2>/dev/null)
      att=$(echo "$event" | jq -r '.attempt // 0' 2>/dev/null)
      if [ -n "$tid" ]; then
        echo "- **${tid}** (uid: \`${tuid}\`) — attempt ${att}, status: ${status}"
      fi
    done)
  fi

  # If no JSON events found, fall back to parsing prd.json for task status
  if [ -z "$covered_tasks" ]; then
    covered_tasks=$(jq -r '.userStories[] | select(.attempts > 0) |
      "- **\(.id)** (uid: `\(.uid // "unknown")`) — attempt \(.attempts), status: \(if .passes then "pass" else "fail" end)"' "$prd_file")
  fi

  # Find previous compaction summary comment URL (or 'none')
  local previous_summary_url="none"
  local summary_comment_url
  summary_comment_url=$(gh issue view "$issue_number" --json comments \
    --jq '[.comments[] | select(.body | startswith("## 🧾 Compacted Summary")) | .url] | last // empty' 2>/dev/null || echo "")

  if [ -n "$summary_comment_url" ]; then
    previous_summary_url="$summary_comment_url"
  fi

  # Collect key decisions and patterns from discovery notes
  local discoveries=""
  discoveries=$(gh issue view "$issue_number" --json comments \
    --jq '[.comments[] | select(.body | startswith("## 🔍 Discovery Note")) | .body] | join("\n---\n")' 2>/dev/null || echo "")

  # Build the compacted summary comment body
  local summary_body
  summary_body="## 🧾 Compacted Summary

**Issue:** #${issue_number}
**Timestamp:** $(date -u '+%Y-%m-%dT%H:%M:%SZ')
**Covers:** ${current_count} task logs since last summary
**Supersedes:** ${previous_summary_url}

### Covered Tasks (UIDs and Attempts)
${covered_tasks:-No task data available}

### Canonical Decisions and Patterns
${discoveries:-No discovery notes found}

### Open Risks
$(jq -r '[.userStories[] | select(.passes == false)] | if length == 0 then "None — all tasks passing" else map("- \(.id): \(.title) (attempt \(.attempts))") | join("\n") end' "$prd_file")

### Current Progress
$(jq -r '
  (.userStories | length) as $total |
  ([.userStories[] | select(.passes == true)] | length) as $passed |
  "\($passed)/\($total) tasks passing (\($passed * 100 / (if $total == 0 then 1 else $total end))%)"
' "$prd_file")"

  # Post the compacted summary to the issue
  if gh issue comment "$issue_number" --body "$summary_body" 2>/dev/null; then
    # Reset the counter to 0
    jq '.compaction.taskLogCountSinceLastSummary = 0' "$prd_file" > "${prd_file}.tmp" && mv "${prd_file}.tmp" "$prd_file"
    git add "$prd_file"
    git commit -m "chore: post compacted summary, reset counter (#$issue_number)" 2>/dev/null || true
  else
    # Post failed — retain counter, will retry on next task log
    git add "$prd_file"
    git commit -m "chore: compaction post failed, retaining counter (#$issue_number)" 2>/dev/null || true
  fi

  return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# Wisp Support
# ═══════════════════════════════════════════════════════════════════════════════

# Collect active (non-expired) wisps from issue comments.
# Filters wisp comments by their expiresAt timestamp, excluding any that have
# expired. Invalid or unparseable expiresAt values are treated as expired.
#
# Args:
#   $1 - issue number
#   $2 - optional pre-fetched comments JSON array
#
# Output: one wisp JSON object per line (only active/non-expired wisps)
collect_active_wisps() {
  local issue_number="$1"
  local comments_json="${2:-}"
  local now_epoch
  now_epoch=$(date +%s)

  # Fetch all wisp comments from the issue
  local wisp_bodies
  if [ -n "$comments_json" ]; then
    wisp_bodies=$(echo "$comments_json" | jq -r '.[] | select(.body | startswith("## 🪶 Wisp")) | .body' 2>/dev/null || echo "")
  else
    wisp_bodies=$(gh issue view "$issue_number" --json comments \
      --jq '.comments[] | select(.body | startswith("## 🪶 Wisp")) | .body' 2>/dev/null || echo "")
  fi

  if [ -z "$wisp_bodies" ]; then
    return 0
  fi

  # Parse wisp comments using a state machine to handle multi-line bodies.
  # Extract fenced json blocks (```json ... ```) and filter by expiration.
  local in_json_block=0
  local json_buffer=""

  while IFS= read -r line; do
    # Opening fence: ```json
    if echo "$line" | grep -qE '^\s*```json\s*$'; then
      in_json_block=1
      json_buffer=""
      continue
    fi

    # Closing fence: ```
    if [ "$in_json_block" -eq 1 ] && echo "$line" | grep -qE '^\s*```\s*$'; then
      in_json_block=0

      if [ -z "$json_buffer" ]; then
        continue
      fi

      # Validate JSON
      if ! echo "$json_buffer" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        continue
      fi

      # Check if this is a wisp (has type=wisp)
      local wtype
      wtype=$(echo "$json_buffer" | jq -r '.type // ""' 2>/dev/null)
      if [ "$wtype" != "wisp" ]; then
        continue
      fi

      # Check if promoted (skip promoted wisps)
      local promoted
      promoted=$(echo "$json_buffer" | jq -r '.promoted // false' 2>/dev/null)
      if [ "$promoted" = "true" ]; then
        continue
      fi

      # Check expiresAt timestamp
      local expiresAt
      expiresAt=$(echo "$json_buffer" | jq -r '.expiresAt // ""' 2>/dev/null)

      if [ -z "$expiresAt" ]; then
        # No expiresAt — treat as expired (safety: wisps must have expiration)
        continue
      fi

      # Parse expiresAt to epoch seconds (timestamps are UTC with Z suffix)
      local expires_epoch
      expires_epoch=$(TZ=UTC date -jf "%Y-%m-%dT%H:%M:%SZ" "$expiresAt" +%s 2>/dev/null || \
                      date -d "$expiresAt" +%s 2>/dev/null || \
                      echo "0")

      if [ "$expires_epoch" -eq 0 ]; then
        # Unparseable expiresAt — treat as expired
        continue
      fi

      # Only include non-expired wisps
      if [ "$expires_epoch" -gt "$now_epoch" ]; then
        echo "$json_buffer"
      fi

      continue
    fi

    # Accumulate lines inside the json block
    if [ "$in_json_block" -eq 1 ]; then
      json_buffer="${json_buffer}${line}"
    fi
  done <<< "$wisp_bodies"
}

# Promote a wisp to a durable artifact. Two promotion paths:
#   1. "discovery" - Convert the wisp into a Discovery Note comment
#   2. "task"      - Enqueue the wisp content as a new discovered task
#
# In both cases, the original wisp comment is updated to set promoted:true.
#
# Args:
#   $1 - issue number
#   $2 - wisp JSON object (compact, single line)
#   $3 - promotion type: "discovery" or "task"
#   $4 - path to prd.json (default: "prd.json") - only needed for "task" promotion
#   $5 - parent task uid (for "task" promotion, sets discoveredFrom)
#
# Side effects: posts GitHub comment, may modify prd.json
promote_wisp() {
  local issue_number="$1"
  local wisp_json="$2"
  local promotion_type="$3"
  local prd_file="${4:-prd.json}"
  local parent_uid="$5"

  local wisp_id
  wisp_id=$(echo "$wisp_json" | jq -r '.id // ""' 2>/dev/null)
  local wisp_note
  wisp_note=$(echo "$wisp_json" | jq -r '.note // ""' 2>/dev/null)
  local wisp_task_uid
  wisp_task_uid=$(echo "$wisp_json" | jq -r '.taskUid // ""' 2>/dev/null)

  if [ -z "$wisp_id" ] || [ -z "$wisp_note" ]; then
    return 1
  fi

  if [ "$promotion_type" = "discovery" ]; then
    # Promote to Discovery Note
    local discovery_body="## 🔍 Discovery Note

**Promoted from wisp:** \`${wisp_id}\`
**Original task:** \`${wisp_task_uid}\`
**Timestamp:** $(date -u '+%Y-%m-%dT%H:%M:%SZ')

### Pattern Discovered
${wisp_note}

### Source
Promoted from ephemeral wisp to durable discovery note."

    gh issue comment "$issue_number" --body "$discovery_body" 2>/dev/null || return 1

  elif [ "$promotion_type" = "task" ]; then
    # Promote to new discovered task via enqueue
    local discovered_task_json
    discovered_task_json=$(jq -nc \
      --arg title "Promoted wisp: ${wisp_note:0:60}" \
      --arg desc "$wisp_note" \
      '[{"title": $title, "description": $desc, "acceptanceCriteria": ["Wisp requirement addressed"], "verifyCommands": [], "dependsOn": []}]')

    # Find parent task id from uid
    local parent_id
    parent_id=$(jq -r --arg uid "$parent_uid" \
      '.userStories[] | select(.uid == $uid) | .id // "US-001"' "$prd_file" 2>/dev/null)
    local parent_priority
    parent_priority=$(jq -r --arg uid "$parent_uid" \
      '.userStories[] | select(.uid == $uid) | .priority // 1' "$prd_file" 2>/dev/null)

    enqueue_discovered_tasks "$prd_file" "$parent_id" "${parent_uid:-null}" "$parent_priority" "$discovered_task_json" "$issue_number"

  else
    return 1
  fi

  # Mark the original wisp as promoted by finding and updating the comment
  # We search for the wisp comment by its id and update promoted to true
  local updated_wisp
  updated_wisp=$(echo "$wisp_json" | jq -c '.promoted = true')

  local comment_id
  comment_id=$(gh issue view "$issue_number" --json comments \
    --jq ".comments[] | select(.body | contains(\"$wisp_id\")) | .url" 2>/dev/null | head -1)

  if [ -n "$comment_id" ]; then
    # Extract numeric comment ID from URL
    local numeric_id
    numeric_id=$(echo "$comment_id" | grep -oE '[0-9]+$')
    local repo
    repo=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)

    if [ -n "$numeric_id" ] && [ -n "$repo" ]; then
      # Build the updated wisp comment body with promoted:true
      local updated_body="## 🪶 Wisp

\`\`\`json
${updated_wisp}
\`\`\`"
      gh api "repos/${repo}/issues/comments/${numeric_id}" \
        -X PATCH -f body="$updated_body" 2>/dev/null || true
    fi
  fi

  return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# Task Log Verification (GitHub-authoritative)
# ═══════════════════════════════════════════════════════════════════════════════

# Verify that a task log with Event JSON was actually posted to GitHub,
# and that the taskUid in the comment is correct. If UID mismatches,
# patches the comment in-place via gh api.
#
# This checks durable GitHub state, NOT Claude's stdout — proving the
# comment was actually posted, not just emitted in model output.
#
# Args:
#   $1 - issue number
#   $2 - task id (e.g., "US-003")
#   $3 - expected task uid (e.g., "tsk_a1b2c3d4e5f6")
#   $4 - optional pre-fetched recent comments (jsonl via @json rows)
#
# Output: the verified/patched Event JSON object (single line), or empty
# Returns: 0 if verified, 1 if no matching task log found on GitHub
verify_task_log_on_github() {
  local issue_number="$1"
  local task_id="$2"
  local expected_uid="$3"
  local recent_comments="${4:-}"

  # Fetch recent comments (last 5 to cover retries)
  if [ -z "$recent_comments" ]; then
    recent_comments=$(gh issue view "$issue_number" --json comments \
      --jq '.comments[-5:][] | @json' 2>/dev/null || echo "")
  fi

  if [ -z "$recent_comments" ]; then
    return 1
  fi

  # Find the most recent comment containing a task log for this task ID.
  # gh yields comments oldest→newest within the slice, so we must iterate
  # ALL matches and keep the last one (= most recent).
  local comment_url=""
  local comment_body=""
  local event_json=""

  while IFS= read -r raw_comment; do
    [ -z "$raw_comment" ] && continue
    local c_url c_body
    c_url=$(echo "$raw_comment" | jq -r '.url // ""' 2>/dev/null)
    c_body=$(echo "$raw_comment" | jq -r '.body // ""' 2>/dev/null)

    # Check if this comment is a task log for our task
    if echo "$c_body" | grep -q "Task Log: ${task_id}"; then
      # Extract Event JSON from this specific comment
      local extracted
      extracted=$(extract_json_events_from_issue_comments "$c_body" 2>/dev/null | head -1)

      if [ -n "$extracted" ]; then
        local parsed_tid
        parsed_tid=$(echo "$extracted" | jq -r '.taskId // ""' 2>/dev/null)
        if [ "$parsed_tid" = "$task_id" ]; then
          comment_url="$c_url"
          comment_body="$c_body"
          event_json="$extracted"
          # Do NOT break — keep iterating to find the newest match
        fi
      fi
    fi
  done <<< "$recent_comments"

  if [ -z "$event_json" ]; then
    return 1
  fi

  # Validate taskUid
  local parsed_uid
  parsed_uid=$(echo "$event_json" | jq -r '.taskUid // ""' 2>/dev/null)

  if [ "$parsed_uid" != "$expected_uid" ] && [ -n "$expected_uid" ]; then
    # UID mismatch — patch the comment on GitHub
    local numeric_id
    numeric_id=$(echo "$comment_url" | grep -oE '[0-9]+$')
    local repo
    repo=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)

    if [ -n "$numeric_id" ] && [ -n "$repo" ]; then
      # Replace the wrong UID in the comment body
      local patched_body
      patched_body=$(echo "$comment_body" | sed "s|\"taskUid\":\"${parsed_uid}\"|\"taskUid\":\"${expected_uid}\"|g")

      if ! gh api "repos/${repo}/issues/comments/${numeric_id}" \
        -X PATCH -f body="$patched_body" 2>/dev/null; then
        # Patch failed — GitHub comment still has wrong UID.
        # Cannot claim durable verification.
        return 1
      fi
    else
      # Could not determine comment ID or repo — cannot patch durably.
      return 1
    fi

    # Patch succeeded — return corrected event
    echo "$event_json" | jq -c --arg uid "$expected_uid" '.taskUid = $uid'
  else
    echo "$event_json"
  fi

  return 0
}

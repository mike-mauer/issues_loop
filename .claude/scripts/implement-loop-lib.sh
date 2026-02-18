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
    jq '.compaction = {"taskLogCountSinceLastSummary": 0, "summaryEveryNTaskLogs": 5}' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi

  # Initialize missing root-level quality field for review lane state
  if jq -e '.quality' "$tmp_file" >/dev/null 2>&1; then
    : # quality exists
  else
    jq '.quality = {
      "reviewMode": "hybrid",
      "reviewPolicy": {
        "autoEnqueueSeverities": ["critical", "high"],
        "approvalRequiredSeverities": ["medium", "low"],
        "minConfidenceForAutoEnqueue": 0.75,
        "maxFindingsPerReview": 5
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
      "autoEnqueueSeverities": ["critical", "high"],
      "approvalRequiredSeverities": ["medium", "low"],
      "minConfidenceForAutoEnqueue": 0.75,
      "maxFindingsPerReview": 5
    }' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi
  if jq -e '.quality.reviewPolicy.autoEnqueueSeverities' "$tmp_file" >/dev/null 2>&1; then :; else
    jq '.quality.reviewPolicy.autoEnqueueSeverities = ["critical", "high"]' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
    needs_update=1
  fi
  if jq -e '.quality.reviewPolicy.approvalRequiredSeverities' "$tmp_file" >/dev/null 2>&1; then :; else
    jq '.quality.reviewPolicy.approvalRequiredSeverities = ["medium", "low"]' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
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
    if echo "$line" | grep -q '### Review Event JSON'; then
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

# Verify that a review log with Review Event JSON was posted to GitHub.
#
# Args:
#   $1 - issue number
#   $2 - review scope label (e.g., US-003 or FINAL)
#   $3 - reviewed commit hash (optional; if provided must match)
#
# Output: verified review event JSON object, or empty
# Returns: 0 if verified, 1 otherwise
verify_review_log_on_github() {
  local issue_number="$1"
  local scope_label="$2"
  local reviewed_commit="$3"

  local recent_comments
  recent_comments=$(gh issue view "$issue_number" --json comments \
    --jq '.comments[-30:][] | @json' 2>/dev/null || echo "")

  if [ -z "$recent_comments" ]; then
    return 1
  fi

  local review_event=""
  while IFS= read -r raw_comment; do
    [ -z "$raw_comment" ] && continue
    local c_body
    c_body=$(echo "$raw_comment" | jq -r '.body // ""' 2>/dev/null)

    if echo "$c_body" | grep -q "## 🔎 Code Review: ${scope_label}"; then
      local extracted
      extracted=$(extract_review_events_from_issue_comments "$c_body" 2>/dev/null | head -1)
      if [ -z "$extracted" ]; then
        continue
      fi

      local extracted_commit
      extracted_commit=$(echo "$extracted" | jq -r '.reviewedCommit // ""' 2>/dev/null)
      if [ -n "$reviewed_commit" ] && [ "$reviewed_commit" != "$extracted_commit" ]; then
        continue
      fi

      review_event="$extracted"
    fi
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
    (.quality.reviewPolicy.autoEnqueueSeverities // ["critical", "high"]) as $autoSev |
    (.quality.reviewPolicy.minConfidenceForAutoEnqueue // 0.75) as $minConf |
    [
      (.quality.findings // [])[] |
      select(.status == "open") |
      select((.severity // "" | ascii_downcase) as $sev | any($autoSev[]; ascii_downcase == $sev)) |
      select((.confidence // 0) >= $minConf) |
      select(.suggestedTask != null and (.suggestedTask.title // "") != "")
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

# Return count of open blocking findings (critical/high severities).
count_open_blocking_review_findings() {
  local prd_file="${1:-prd.json}"
  jq -r '
    (.quality.reviewPolicy.autoEnqueueSeverities // ["critical", "high"]) as $autoSev |
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
# threshold is reached (default: every 5 task logs).
#
# Call this after every successful task log post. It:
#   1. Increments prd.json.compaction.taskLogCountSinceLastSummary
#   2. If count >= summaryEveryNTaskLogs (default 5):
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
  threshold=$(jq '.compaction.summaryEveryNTaskLogs // 5' "$prd_file")

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
#
# Output: one wisp JSON object per line (only active/non-expired wisps)
collect_active_wisps() {
  local issue_number="$1"
  local now_epoch
  now_epoch=$(date +%s)

  # Fetch all wisp comments from the issue
  local wisp_bodies
  wisp_bodies=$(gh issue view "$issue_number" --json comments \
    --jq '.comments[] | select(.body | startswith("## 🪶 Wisp")) | .body' 2>/dev/null || echo "")

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
#
# Output: the verified/patched Event JSON object (single line), or empty
# Returns: 0 if verified, 1 if no matching task log found on GitHub
verify_task_log_on_github() {
  local issue_number="$1"
  local task_id="$2"
  local expected_uid="$3"

  # Fetch recent comments (last 5 to cover retries)
  local recent_comments
  recent_comments=$(gh issue view "$issue_number" --json comments \
    --jq '.comments[-5:][] | @json' 2>/dev/null || echo "")

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

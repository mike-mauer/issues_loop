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
# Handles legacy prd.json files that lack formula, compaction, or per-story
# uid/discoveredFrom/discoverySource fields.
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
#
# Side effects: modifies prd.json in place, commits the change
enqueue_discovered_tasks() {
  local prd_file="${1:-prd.json}"
  local parent_id="$2"
  local parent_uid="$3"
  local parent_priority="$4"
  local discovered_json="$5"
  local issue_number="$6"

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
     "\(.title)\t\(.description)\t(\(.acceptanceCriteria | join(",")))"' "$prd_file" 2>/dev/null || echo "")

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
         "discoverySource": "task_log",
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

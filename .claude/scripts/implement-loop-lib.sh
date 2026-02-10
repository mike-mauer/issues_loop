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

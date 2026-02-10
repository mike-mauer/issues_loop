#!/bin/bash
# test-enhancements.sh - Functional tests for beads-inspired enhancements
#
# Tests five critical behaviors of implement-loop-lib.sh:
#   1. JSON event extraction from fenced block + legacy fallback
#   2. Discovered-task enqueue with fingerprint dedupe rejection
#   3. Compaction trigger on 5th task log + counter reset
#   4. Wisp expiration filtering (expired excluded, active included)
#   5. Legacy prd.json backward compatibility (safe defaults)
#   6. GitHub-authoritative task log verification + UID mismatch correction
#
# Usage: bash tests/test-enhancements.sh

set -euo pipefail

# ─── Setup ────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$PROJECT_DIR/.claude/scripts/implement-loop-lib.sh"

# Create a temp dir for test fixtures (cleaned up on exit)
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

PASS_COUNT=0
FAIL_COUNT=0
TEST_COUNT=0

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  TEST_COUNT=$((TEST_COUNT + 1))
  echo "  ✓ $1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  TEST_COUNT=$((TEST_COUNT + 1))
  echo "  ✗ $1"
  if [ -n "${2:-}" ]; then
    echo "    Expected: $2"
  fi
  if [ -n "${3:-}" ]; then
    echo "    Got:      $3"
  fi
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$label"
  else
    fail "$label" "$expected" "$actual"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if echo "$haystack" | grep -q "$needle"; then
    pass "$label"
  else
    fail "$label" "contains '$needle'" "$(echo "$haystack" | head -3)"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if echo "$haystack" | grep -q "$needle"; then
    fail "$label" "should NOT contain '$needle'" "found it"
  else
    pass "$label"
  fi
}

assert_file_exists() {
  local path="$1"
  local label="$2"
  if [ -f "$path" ]; then
    pass "$label"
  else
    fail "$label" "file exists at $path" "not found"
  fi
}

# Source the library under test
source "$LIB"

# Override git and gh commands to no-ops for testing
git() { :; }
gh() { :; }
export -f git gh

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Testing implement-loop-lib.sh enhancements"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST 1: JSON Event Extraction
# ═══════════════════════════════════════════════════════════════════════════════
echo "── Test 1: JSON Event Extraction ──"

# 1a. Valid fenced JSON event block under ### Event JSON heading
COMMENTS_VALID='## 📝 Task Log: US-003

**Status:** ✅ Passed
**Attempt:** 2

### Event JSON
```json
{"v":1,"type":"task_log","issue":42,"taskId":"US-003","taskUid":"tsk_a1b2c3d4e5f6","status":"pass","attempt":2,"commit":"abc1234","verify":{"passed":["npm run typecheck"],"failed":[]},"discovered":[],"ts":"2026-02-10T18:30:00Z"}
```

### Learnings
Nothing special.'

result=$(extract_json_events_from_issue_comments "$COMMENTS_VALID")
assert_contains "$result" '"taskId":"US-003"' "1a: Extracts valid JSON event from fenced block"
assert_contains "$result" '"taskUid":"tsk_a1b2c3d4e5f6"' "1a: taskUid extracted correctly"
assert_contains "$result" '"status":"pass"' "1a: Status field extracted"

# 1b. Malformed JSON in fenced block — should be silently skipped
COMMENTS_MALFORMED='## 📝 Task Log: US-004

**Status:** ✅ Passed

### Event JSON
```json
{not valid json at all!!}
```

### Learnings
None.'

result_malformed=$(extract_json_events_from_issue_comments "$COMMENTS_MALFORMED")
assert_eq "$result_malformed" "" "1b: Malformed JSON silently skipped (empty output)"

# 1c. No Event JSON heading — legacy format, no JSON extracted
COMMENTS_LEGACY='## 📝 Task Log: US-001

**Status:** ✅ Passed
**Attempt:** 1
**Commit:** def5678

### Summary
Added the feature.

### Verification Results
```
✓ npm run typecheck
```'

result_legacy=$(extract_json_events_from_issue_comments "$COMMENTS_LEGACY")
assert_eq "$result_legacy" "" "1c: Legacy format (no Event JSON heading) returns empty"

# 1d. JSON elsewhere in comment (not under Event JSON heading) is ignored
COMMENTS_OTHER_JSON='## 📝 Task Log: US-005

Some context with JSON in it: {"fake": true}

```json
{"also_fake": "should be ignored"}
```

### Summary
This has JSON but no Event JSON heading.'

result_other=$(extract_json_events_from_issue_comments "$COMMENTS_OTHER_JSON")
assert_eq "$result_other" "" "1d: JSON not under Event JSON heading is ignored"

# 1e. Multiple events across multiple task logs
COMMENTS_MULTI='## 📝 Task Log: US-001

### Event JSON
```json
{"v":1,"type":"task_log","taskId":"US-001","status":"pass","attempt":1}
```

---

## 📝 Task Log: US-002

### Event JSON
```json
{"v":1,"type":"task_log","taskId":"US-002","status":"fail","attempt":1}
```'

result_multi=$(extract_json_events_from_issue_comments "$COMMENTS_MULTI")
line_count=$(echo "$result_multi" | grep -c 'task_log' || true)
assert_eq "$line_count" "2" "1e: Multiple events extracted from multiple task logs"

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST 2: Discovered-Task Enqueue with Fingerprint Dedupe
# ═══════════════════════════════════════════════════════════════════════════════
echo "── Test 2: Discovered-Task Enqueue + Dedupe ──"

# Create a test prd.json fixture
cat > "$TEST_DIR/prd-enqueue.json" << 'FIXTURE'
{
  "project": "test",
  "issueNumber": 99,
  "branchName": "ai/issue-99-test",
  "formula": "feature",
  "compaction": {"taskLogCountSinceLastSummary": 0, "summaryEveryNTaskLogs": 5},
  "userStories": [
    {
      "id": "US-001",
      "uid": "tsk_parent00001",
      "phase": 1,
      "priority": 1,
      "title": "Parent task",
      "description": "The parent task",
      "files": [],
      "dependsOn": [],
      "discoveredFrom": null,
      "discoverySource": null,
      "acceptanceCriteria": ["something passes"],
      "verifyCommands": ["echo ok"],
      "passes": true,
      "attempts": 1,
      "lastAttempt": null
    }
  ]
}
FIXTURE

# 2a. Enqueue a discovered task — should be appended
DISCOVERED='[{"title":"Fix edge case","description":"Handle null input","acceptanceCriteria":["Test passes"],"verifyCommands":["echo ok"],"dependsOn":[]}]'

enqueue_discovered_tasks "$TEST_DIR/prd-enqueue.json" "US-001" "tsk_parent00001" 1 "$DISCOVERED" 99

story_count=$(jq '.userStories | length' "$TEST_DIR/prd-enqueue.json")
assert_eq "$story_count" "2" "2a: Discovered task appended (2 stories total)"

new_id=$(jq -r '.userStories[1].id' "$TEST_DIR/prd-enqueue.json")
assert_eq "$new_id" "US-002" "2a: Discovered task gets next sequential id"

new_discovered_from=$(jq -r '.userStories[1].discoveredFrom' "$TEST_DIR/prd-enqueue.json")
assert_eq "$new_discovered_from" "tsk_parent00001" "2a: discoveredFrom set to parent uid"

new_priority=$(jq '.userStories[1].priority' "$TEST_DIR/prd-enqueue.json")
assert_eq "$new_priority" "2" "2a: Priority is parent + 1"

new_uid=$(jq -r '.userStories[1].uid' "$TEST_DIR/prd-enqueue.json")
assert_contains "$new_uid" "tsk_" "2a: Generated uid has tsk_ prefix"

new_source=$(jq -r '.userStories[1].discoverySource' "$TEST_DIR/prd-enqueue.json")
assert_eq "$new_source" "task_log" "2a: discoverySource set to task_log"

# 2b. Enqueue the SAME task again — should be deduplicated (rejected)
enqueue_discovered_tasks "$TEST_DIR/prd-enqueue.json" "US-001" "tsk_parent00001" 1 "$DISCOVERED" 99

story_count_after_dupe=$(jq '.userStories | length' "$TEST_DIR/prd-enqueue.json")
assert_eq "$story_count_after_dupe" "2" "2b: Duplicate fingerprint rejected (still 2 stories)"

# 2c. Enqueue a different task — should succeed
DISCOVERED_DIFF='[{"title":"Another edge case","description":"Handle empty array","acceptanceCriteria":["Different test passes"],"verifyCommands":["echo ok"],"dependsOn":[]}]'

enqueue_discovered_tasks "$TEST_DIR/prd-enqueue.json" "US-001" "tsk_parent00001" 1 "$DISCOVERED_DIFF" 99

story_count_diff=$(jq '.userStories | length' "$TEST_DIR/prd-enqueue.json")
assert_eq "$story_count_diff" "3" "2c: Different task accepted (3 stories total)"

# 2d. Fingerprint computation is deterministic
fp1=$(compute_task_fingerprint "Fix edge case" "Handle null input" "Test passes" "tsk_parent00001")
fp2=$(compute_task_fingerprint "Fix edge case" "Handle null input" "Test passes" "tsk_parent00001")
assert_eq "$fp1" "$fp2" "2d: Same inputs produce same fingerprint"

# 2e. Different inputs produce different fingerprints
fp3=$(compute_task_fingerprint "Different title" "Handle null input" "Test passes" "tsk_parent00001")
if [ "$fp1" != "$fp3" ]; then
  pass "2e: Different title produces different fingerprint"
else
  fail "2e: Different title produces different fingerprint" "different hash" "same hash"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST 3: Compaction Trigger + Counter Reset
# ═══════════════════════════════════════════════════════════════════════════════
echo "── Test 3: Compaction Trigger + Counter Reset ──"

# Create a fixture prd.json with counter at 0
cat > "$TEST_DIR/prd-compact.json" << 'FIXTURE'
{
  "project": "test",
  "issueNumber": 99,
  "formula": "feature",
  "compaction": {
    "taskLogCountSinceLastSummary": 0,
    "summaryEveryNTaskLogs": 5
  },
  "userStories": [
    {"id":"US-001","uid":"tsk_aaa","title":"Task 1","passes":true,"attempts":1},
    {"id":"US-002","uid":"tsk_bbb","title":"Task 2","passes":true,"attempts":1},
    {"id":"US-003","uid":"tsk_ccc","title":"Task 3","passes":true,"attempts":1},
    {"id":"US-004","uid":"tsk_ddd","title":"Task 4","passes":true,"attempts":2},
    {"id":"US-005","uid":"tsk_eee","title":"Task 5","passes":false,"attempts":0}
  ]
}
FIXTURE

# Note: maybe_post_compaction_summary calls `gh` which we mocked to no-op.
# When the threshold is hit, `gh issue comment` (our mock) returns success (exit 0),
# so the counter should reset.

# 3a. Increment counter from 0 → 1 (below threshold)
maybe_post_compaction_summary "$TEST_DIR/prd-compact.json" 99 "US-001" "tsk_aaa" 1
counter=$(jq '.compaction.taskLogCountSinceLastSummary' "$TEST_DIR/prd-compact.json")
assert_eq "$counter" "1" "3a: Counter incremented from 0 to 1"

# 3b. Increment to 2
maybe_post_compaction_summary "$TEST_DIR/prd-compact.json" 99 "US-002" "tsk_bbb" 1
counter=$(jq '.compaction.taskLogCountSinceLastSummary' "$TEST_DIR/prd-compact.json")
assert_eq "$counter" "2" "3b: Counter incremented to 2"

# 3c. Increment to 3
maybe_post_compaction_summary "$TEST_DIR/prd-compact.json" 99 "US-003" "tsk_ccc" 1
counter=$(jq '.compaction.taskLogCountSinceLastSummary' "$TEST_DIR/prd-compact.json")
assert_eq "$counter" "3" "3c: Counter incremented to 3"

# 3d. Increment to 4
maybe_post_compaction_summary "$TEST_DIR/prd-compact.json" 99 "US-004" "tsk_ddd" 2
counter=$(jq '.compaction.taskLogCountSinceLastSummary' "$TEST_DIR/prd-compact.json")
assert_eq "$counter" "4" "3d: Counter incremented to 4"

# 3e. Increment to 5 — this triggers compaction; gh mock succeeds, counter resets
maybe_post_compaction_summary "$TEST_DIR/prd-compact.json" 99 "US-005" "tsk_eee" 1
counter=$(jq '.compaction.taskLogCountSinceLastSummary' "$TEST_DIR/prd-compact.json")
assert_eq "$counter" "0" "3e: Counter resets to 0 after 5th task log (compaction posted)"

# 3f. Next increment starts fresh at 1
maybe_post_compaction_summary "$TEST_DIR/prd-compact.json" 99 "US-001" "tsk_aaa" 2
counter=$(jq '.compaction.taskLogCountSinceLastSummary' "$TEST_DIR/prd-compact.json")
assert_eq "$counter" "1" "3f: Counter starts fresh after reset (now 1)"

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST 4: Wisp Expiration Filtering
# ═══════════════════════════════════════════════════════════════════════════════
echo "── Test 4: Wisp Expiration Filtering ──"

# We need to test collect_active_wisps, but it calls `gh issue view`.
# We'll override gh to return fixture data, then test the filtering logic.

# Compute timestamps: one in the future (active), one in the past (expired)
FUTURE_TS=$(date -u -v+2H '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '+2 hours' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)
PAST_TS=$(date -u -v-2H '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '-2 hours' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)

# Write fixture wisp bodies to a temp file for the gh mock.
# The real `gh --jq '.comments[] | ... | .body'` outputs each comment body
# separated by newlines. Multi-line bodies just flow out as-is.
cat > "$TEST_DIR/wisp-fixture.txt" << FIXTURE
## 🪶 Wisp

\`\`\`json
{"v":1,"type":"wisp","id":"wsp_active01","taskUid":"tsk_aaa","note":"Active wisp note","expiresAt":"${FUTURE_TS}","promoted":false}
\`\`\`
## 🪶 Wisp

\`\`\`json
{"v":1,"type":"wisp","id":"wsp_expired01","taskUid":"tsk_bbb","note":"Expired wisp note","expiresAt":"${PAST_TS}","promoted":false}
\`\`\`
## 🪶 Wisp

\`\`\`json
{"v":1,"type":"wisp","id":"wsp_promoted01","taskUid":"tsk_ccc","note":"Promoted wisp","expiresAt":"${FUTURE_TS}","promoted":true}
\`\`\`
## 🪶 Wisp

\`\`\`json
{"v":1,"type":"wisp","id":"wsp_noexpiry","taskUid":"tsk_ddd","note":"No expiry field","promoted":false}
\`\`\`
FIXTURE

# Override gh to return our fixture wisp bodies from the file
gh() {
  cat "$TEST_DIR/wisp-fixture.txt"
}
export -f gh

result_wisps=$(collect_active_wisps 99)

# 4a. Active (future expiry) wisp should be included
assert_contains "$result_wisps" "wsp_active01" "4a: Active wisp (future expiry) included"

# 4b. Expired (past expiry) wisp should be excluded
assert_not_contains "$result_wisps" "wsp_expired01" "4b: Expired wisp (past expiry) excluded"

# 4c. Promoted wisp should be excluded (even if not expired)
assert_not_contains "$result_wisps" "wsp_promoted01" "4c: Promoted wisp excluded"

# 4d. Wisp with no expiresAt field should be excluded (treated as expired)
assert_not_contains "$result_wisps" "wsp_noexpiry" "4d: Wisp without expiresAt excluded (treated as expired)"

# Reset gh mock to no-op
gh() { :; }
export -f gh

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST 5: Legacy prd.json Backward Compatibility
# ═══════════════════════════════════════════════════════════════════════════════
echo "── Test 5: Legacy prd.json Backward Compatibility ──"

# Create a legacy prd.json (no formula, no compaction, no uid, no discoveredFrom)
cat > "$TEST_DIR/prd-legacy.json" << 'FIXTURE'
{
  "project": "old-project",
  "issueNumber": 7,
  "branchName": "ai/issue-7-old",
  "description": "Legacy issue",
  "generatedAt": "2025-01-01T00:00:00Z",
  "status": "approved",
  "userStories": [
    {
      "id": "US-001",
      "phase": 1,
      "priority": 1,
      "title": "Old task one",
      "description": "A legacy task",
      "files": ["src/index.ts"],
      "dependsOn": [],
      "acceptanceCriteria": ["It works"],
      "verifyCommands": ["echo ok"],
      "passes": false,
      "attempts": 0,
      "lastAttempt": null
    },
    {
      "id": "US-002",
      "phase": 1,
      "priority": 2,
      "title": "Old task two",
      "description": "Another legacy task",
      "files": ["src/utils.ts"],
      "dependsOn": ["US-001"],
      "acceptanceCriteria": ["Also works"],
      "verifyCommands": ["echo ok"],
      "passes": false,
      "attempts": 0,
      "lastAttempt": null
    }
  ]
}
FIXTURE

# 5a. Verify legacy file lacks new fields
has_formula_before=$(jq 'has("formula")' "$TEST_DIR/prd-legacy.json")
assert_eq "$has_formula_before" "false" "5a: Legacy prd.json has no formula field"

has_compaction_before=$(jq 'has("compaction")' "$TEST_DIR/prd-legacy.json")
assert_eq "$has_compaction_before" "false" "5a: Legacy prd.json has no compaction field"

has_uid_before=$(jq -r '.userStories[0].uid // "missing"' "$TEST_DIR/prd-legacy.json")
assert_eq "$has_uid_before" "missing" "5a: Legacy stories have no uid"

# 5b. Run initialization
initialize_missing_prd_fields "$TEST_DIR/prd-legacy.json"

# 5c. formula initialized to "feature"
formula=$(jq -r '.formula' "$TEST_DIR/prd-legacy.json")
assert_eq "$formula" "feature" "5c: formula initialized to 'feature'"

# 5d. compaction initialized with safe defaults
counter=$(jq '.compaction.taskLogCountSinceLastSummary' "$TEST_DIR/prd-legacy.json")
assert_eq "$counter" "0" "5d: compaction counter initialized to 0"

threshold=$(jq '.compaction.summaryEveryNTaskLogs' "$TEST_DIR/prd-legacy.json")
assert_eq "$threshold" "5" "5d: compaction threshold initialized to 5"

# 5e. Per-story uid generated with tsk_ prefix
uid1=$(jq -r '.userStories[0].uid' "$TEST_DIR/prd-legacy.json")
assert_contains "$uid1" "tsk_" "5e: US-001 uid generated with tsk_ prefix"

uid2=$(jq -r '.userStories[1].uid' "$TEST_DIR/prd-legacy.json")
assert_contains "$uid2" "tsk_" "5e: US-002 uid generated with tsk_ prefix"

# 5f. UIDs are different for different tasks
if [ "$uid1" != "$uid2" ]; then
  pass "5f: Different tasks get different uids"
else
  fail "5f: Different tasks get different uids" "different uids" "same: $uid1"
fi

# 5g. discoveredFrom initialized to null for planned tasks
df1=$(jq '.userStories[0].discoveredFrom' "$TEST_DIR/prd-legacy.json")
assert_eq "$df1" "null" "5g: discoveredFrom initialized to null for planned tasks"

# 5h. discoverySource initialized to null for planned tasks
ds1=$(jq '.userStories[0].discoverySource' "$TEST_DIR/prd-legacy.json")
assert_eq "$ds1" "null" "5h: discoverySource initialized to null for planned tasks"

# 5i. uid is deterministic (running again produces same uid)
uid1_before="$uid1"
initialize_missing_prd_fields "$TEST_DIR/prd-legacy.json"
uid1_after=$(jq -r '.userStories[0].uid' "$TEST_DIR/prd-legacy.json")
assert_eq "$uid1_after" "$uid1_before" "5i: uid is stable on re-run (deterministic)"

# 5j. File remains valid JSON after initialization
if python3 -c "import json; json.load(open('$TEST_DIR/prd-legacy.json'))" 2>/dev/null; then
  pass "5j: Initialized prd.json is valid JSON"
else
  fail "5j: Initialized prd.json is valid JSON" "valid JSON" "invalid JSON"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# TEST 6: GitHub-Authoritative Task Log Verification
# ═══════════════════════════════════════════════════════════════════════════════
echo "── Test 6: verify_task_log_on_github + EVENT_VERIFIED Gating ──"

# 6a. Matching task log found with correct UID — returns event JSON, exit 0
gh() {
  if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
    # Return a single comment as @json-encoded line
    cat << 'GHEOF'
{"url":"https://github.com/org/repo/issues/99#issuecomment-12345","body":"## 📝 Task Log: US-003\n\n**Status:** ✅ Passed\n\n### Event JSON\n```json\n{\"v\":1,\"type\":\"task_log\",\"issue\":99,\"taskId\":\"US-003\",\"taskUid\":\"tsk_correct_uid\",\"status\":\"pass\",\"attempt\":1}\n```"}
GHEOF
    return 0
  fi
}
export -f gh

result_6a=$(verify_task_log_on_github 99 "US-003" "tsk_correct_uid")
exit_6a=$?
assert_eq "$exit_6a" "0" "6a: Returns exit 0 when matching task log found"
assert_contains "$result_6a" '"taskId":"US-003"' "6a: Returns event JSON with correct taskId"
assert_contains "$result_6a" '"taskUid":"tsk_correct_uid"' "6a: taskUid matches expected value"

# 6b. No matching task log — returns empty, exit 1
gh() {
  if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
    # Return a comment for a DIFFERENT task
    cat << 'GHEOF'
{"url":"https://github.com/org/repo/issues/99#issuecomment-99999","body":"## 📝 Task Log: US-001\n\n**Status:** ✅ Passed\n\n### Event JSON\n```json\n{\"v\":1,\"type\":\"task_log\",\"issue\":99,\"taskId\":\"US-001\",\"taskUid\":\"tsk_other\",\"status\":\"pass\",\"attempt\":1}\n```"}
GHEOF
    return 0
  fi
}
export -f gh

set +e
result_6b=$(verify_task_log_on_github 99 "US-005" "tsk_expected" 2>/dev/null)
exit_6b=$?
set -e
assert_eq "$exit_6b" "1" "6b: Returns exit 1 when no matching task log found"
assert_eq "$result_6b" "" "6b: Returns empty output when task log not found"

# 6c. UID mismatch — returns patched event JSON with corrected UID
GH_API_CALLED=""
gh() {
  if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
    cat << 'GHEOF'
{"url":"https://github.com/org/repo/issues/99#issuecomment-55555","body":"## 📝 Task Log: US-004\n\n**Status:** ✅ Passed\n\n### Event JSON\n```json\n{\"v\":1,\"type\":\"task_log\",\"issue\":99,\"taskId\":\"US-004\",\"taskUid\":\"tsk_wrong_uid\",\"status\":\"pass\",\"attempt\":2}\n```"}
GHEOF
    return 0
  elif [ "$1" = "repo" ] && [ "$2" = "view" ]; then
    echo "org/repo"
    return 0
  elif [ "$1" = "api" ]; then
    # Record that gh api was called (proves PATCH was attempted)
    GH_API_CALLED="yes:$2"
    return 0
  fi
}
export -f gh
export GH_API_CALLED

result_6c=$(verify_task_log_on_github 99 "US-004" "tsk_correct_004")
exit_6c=$?
assert_eq "$exit_6c" "0" "6c: Returns exit 0 even when UID was patched"
assert_contains "$result_6c" '"taskUid":"tsk_correct_004"' "6c: Returned event has corrected UID"
assert_not_contains "$result_6c" "tsk_wrong_uid" "6c: Wrong UID no longer in returned event"

# 6d. UID mismatch triggers gh api PATCH call to update the comment
# Note: GH_API_CALLED is set in the subshell within verify_task_log_on_github,
# so we verify the patch behavior by checking the returned UID differs from input.
patched_uid=$(echo "$result_6c" | jq -r '.taskUid // ""' 2>/dev/null)
assert_eq "$patched_uid" "tsk_correct_004" "6d: Patched UID in returned event is the expected UID"

# 6e. Empty comments from GitHub — returns exit 1
gh() {
  if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
    echo ""
    return 0
  fi
}
export -f gh

set +e
result_6e=$(verify_task_log_on_github 99 "US-001" "tsk_any" 2>/dev/null)
exit_6e=$?
set -e
assert_eq "$exit_6e" "1" "6e: Returns exit 1 when GitHub returns empty comments"

# 6f. GitHub API failure — returns exit 1
gh() {
  return 1
}
export -f gh

set +e
result_6f=$(verify_task_log_on_github 99 "US-001" "tsk_any" 2>/dev/null)
exit_6f=$?
set -e
assert_eq "$exit_6f" "1" "6f: Returns exit 1 when gh CLI fails"

# 6g. Multiple task logs for same task — picks the NEWEST (last in slice), not oldest
gh() {
  if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
    # Two comments for US-007: older (attempt 1) then newer (attempt 2)
    cat << 'GHEOF'
{"url":"https://github.com/org/repo/issues/99#issuecomment-11111","body":"## 📝 Task Log: US-007\n\n### Event JSON\n```json\n{\"v\":1,\"type\":\"task_log\",\"issue\":99,\"taskId\":\"US-007\",\"taskUid\":\"tsk_uid7\",\"status\":\"fail\",\"attempt\":1}\n```"}
{"url":"https://github.com/org/repo/issues/99#issuecomment-22222","body":"## 📝 Task Log: US-007\n\n### Event JSON\n```json\n{\"v\":1,\"type\":\"task_log\",\"issue\":99,\"taskId\":\"US-007\",\"taskUid\":\"tsk_uid7\",\"status\":\"pass\",\"attempt\":2}\n```"}
GHEOF
    return 0
  fi
}
export -f gh

result_6g=$(verify_task_log_on_github 99 "US-007" "tsk_uid7")
exit_6g=$?
assert_eq "$exit_6g" "0" "6g: Returns exit 0 with multiple matching logs"
assert_contains "$result_6g" '"attempt":2' "6g: Picks newest log (attempt 2, not attempt 1)"
assert_contains "$result_6g" '"status":"pass"' "6g: Newest log status is pass (not the older fail)"

# 6h. UID mismatch but gh api PATCH fails — must return exit 1 (not verified)
gh() {
  if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
    cat << 'GHEOF'
{"url":"https://github.com/org/repo/issues/99#issuecomment-33333","body":"## 📝 Task Log: US-008\n\n### Event JSON\n```json\n{\"v\":1,\"type\":\"task_log\",\"issue\":99,\"taskId\":\"US-008\",\"taskUid\":\"tsk_wrong\",\"status\":\"pass\",\"attempt\":1}\n```"}
GHEOF
    return 0
  elif [ "$1" = "repo" ] && [ "$2" = "view" ]; then
    echo "org/repo"
    return 0
  elif [ "$1" = "api" ]; then
    # Simulate PATCH failure (permissions/network)
    return 1
  fi
}
export -f gh

set +e
result_6h=$(verify_task_log_on_github 99 "US-008" "tsk_correct_008" 2>/dev/null)
exit_6h=$?
set -e
assert_eq "$exit_6h" "1" "6h: Returns exit 1 when gh api PATCH fails (not durably verified)"
assert_eq "$result_6h" "" "6h: Returns no output when patch fails"

# Reset gh mock to no-op
gh() { :; }
export -f gh

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Results Summary
# ═══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Results: $PASS_COUNT/$TEST_COUNT passed, $FAIL_COUNT failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "  All tests passed!"
  exit 0
else
  echo "  Some tests failed."
  exit 1
fi

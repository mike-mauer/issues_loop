#!/bin/bash
# test-script-parity.sh - Runtime vs skill script parity checks
#
# Usage: bash tests/test-script-parity.sh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

CLAUDE_LOOP="$PROJECT_DIR/.claude/scripts/implement-loop.sh"
SKILL_LOOP="$PROJECT_DIR/.agents/skills/issues-loop/scripts/implement-loop.sh"
CLAUDE_LIB="$PROJECT_DIR/.claude/scripts/implement-loop-lib.sh"
SKILL_LIB="$PROJECT_DIR/.agents/skills/issues-loop/scripts/implement-loop-lib.sh"

pass_count=0
fail_count=0
test_count=0

pass() {
  pass_count=$((pass_count + 1))
  test_count=$((test_count + 1))
  echo "  ✓ $1"
}

fail() {
  fail_count=$((fail_count + 1))
  test_count=$((test_count + 1))
  echo "  ✗ $1"
}

assert_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if rg -q "$pattern" "$file"; then
    pass "$label"
  else
    fail "$label"
  fi
}

assert_equal() {
  local a="$1"
  local b="$2"
  local label="$3"
  if [ "$a" = "$b" ]; then
    pass "$label"
  else
    fail "$label"
  fi
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Testing runtime/skill script parity"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

for file in "$CLAUDE_LOOP" "$SKILL_LOOP" "$CLAUDE_LIB" "$SKILL_LIB"; do
  if [ -f "$file" ]; then
    pass "File exists: $(basename "$file")"
  else
    fail "File exists: $(basename "$file")"
  fi
done

echo ""
echo "── Shell Syntax ──"
bash -n "$CLAUDE_LOOP" && pass "Claude loop script parses"
bash -n "$SKILL_LOOP" && pass "Skill loop script parses"
bash -n "$CLAUDE_LIB" && pass "Claude loop lib parses"
bash -n "$SKILL_LIB" && pass "Skill loop lib parses"

echo ""
echo "── Required Gate Functions ──"
for fn in \
  load_execution_config \
  run_verify_suite \
  update_task_state_authoritative \
  is_task_exhausted \
  validate_search_evidence \
  scan_placeholder_patterns \
  build_issue_context_bundle \
  update_execution_retry_counters \
  should_trigger_stale_plan \
  mark_replan_required; do
  assert_contains "$CLAUDE_LIB" "^${fn}\\(\\)" "Claude lib defines ${fn}"
  assert_contains "$SKILL_LIB" "^${fn}\\(\\)" "Skill lib defines ${fn}"
done

echo ""
echo "── Required Loop Control Paths ──"
for pattern in \
  "run_verify_suite" \
  "validate_search_evidence" \
  "scan_placeholder_patterns" \
  "update_task_state_authoritative" \
  "should_trigger_stale_plan" \
  "replan_required" \
  "AI: Blocked"; do
  assert_contains "$CLAUDE_LOOP" "$pattern" "Claude loop contains $pattern flow"
  assert_contains "$SKILL_LOOP" "$pattern" "Skill loop contains $pattern flow"
done

echo ""
echo "── Function Name Parity ──"
claude_fn_count=$(rg -n "^[a-zA-Z_][a-zA-Z0-9_]*\\(\\) \\{" "$CLAUDE_LIB" | wc -l | tr -d '[:space:]')
skill_fn_count=$(rg -n "^[a-zA-Z_][a-zA-Z0-9_]*\\(\\) \\{" "$SKILL_LIB" | wc -l | tr -d '[:space:]')
assert_equal "$claude_fn_count" "$skill_fn_count" "Library function counts match"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Results: $pass_count/$test_count passed, $fail_count failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$fail_count" -eq 0 ]; then
  echo "  All parity checks passed!"
  exit 0
fi

echo "  Parity checks failed."
exit 1

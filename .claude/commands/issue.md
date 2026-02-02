# /issue - Load, Scope, and Plan GitHub Issue

## Description
Loads a GitHub issue, evaluates completeness, gathers missing requirements via scoping questions, and guides through planning and approval. This is the primary entry point for the workflow - it handles the full journey from issue to approved plan.

## Usage
```
/issue 42             # Load and evaluate issue
/issue #42            # Same, with # prefix
/issue 42 --quick     # Skip scoping, load as-is
```

## Arguments
- `$ARGUMENTS` - Issue number (with or without #), optionally followed by `--quick`

---

## Step 0: Prerequisites

Before proceeding, validate the environment:

```bash
# 1. Check gh CLI is installed
which gh || { echo "❌ GitHub CLI (gh) not found. Install with: brew install gh"; exit 1; }

# 2. Check gh is authenticated
gh auth status || { echo "❌ GitHub CLI not authenticated. Run: gh auth login"; exit 1; }

# 3. Check we're in a git repository
git rev-parse --git-dir > /dev/null 2>&1 || { echo "❌ Not in a git repository"; exit 1; }

# 4. Check we have a GitHub remote
git remote get-url origin 2>/dev/null | grep -q github || { echo "❌ No GitHub remote found"; exit 1; }

# 5. Check jq is installed (for prd.json operations)
which jq || { echo "❌ jq not found. Install with: brew install jq"; exit 1; }
```

If any prerequisite fails, stop and inform the user how to fix it.

---

## Workflow

### Step 1: Parse Issue Reference
Extract the issue number from the provided argument. Check for `--quick` flag.

### Step 2: Fetch Issue Details
```bash
gh issue view $ISSUE_NUMBER --json number,title,body,labels,state,comments,assignees,milestone
```

### Step 3: Evaluate Completeness

**Skip this step if `--quick` flag is present.**

Score the issue on 5 dimensions (0-2 points each, max 10):

| Dimension | 0 Points | 1 Point | 2 Points |
|-----------|----------|---------|----------|
| **What** | Vague ("fix bug") | Partial ("login doesn't work") | Clear ("Login returns 500 when email has +") |
| **Where** | No location | General area ("auth system") | Specific file/path mentioned |
| **Why** | No context | Some context | Clear user impact stated |
| **Scope** | Unbounded | Partially bounded | Clear boundaries |
| **Acceptance** | None stated | Vague criteria | Testable criteria |

#### Evaluation Logic

```
WHAT (0-2):
  - 2 points: Body > 100 chars AND contains action words (should, need, want, add, fix, implement)
  - 1 point: Contains action words but brief
  - 0 points: No clear action described

WHERE (0-2):
  - 2 points: Mentions specific file paths (*.ts, *.js, etc.) or line numbers
  - 1 point: Mentions general area (src/, components/, api/)
  - 0 points: No location context

WHY (0-2):
  - 2 points: Explains user impact or business reason (because, so that, users need)
  - 1 point: Some context but not explicit impact
  - 0 points: No why stated

SCOPE (0-2):
  - 2 points: Explicit scope/out-of-scope or uses "only", "specifically"
  - 1 point: Has structured sections (##, checkboxes)
  - 0 points: Unbounded

ACCEPTANCE (0-2):
  - 2 points: Has checkboxes [ ] or explicit "done when" criteria
  - 1 point: Has "expect" or "should" statements
  - 0 points: No success criteria
```

#### Scoring Thresholds

| Score | Action |
|-------|--------|
| **8-10** | Well-defined → Proceed to Step 4 (state detection) |
| **5-7** | Minor gaps → Ask 1-2 targeted questions |
| **0-4** | Needs scoping → Ask up to 3 questions |

### Step 3b: Scoping Questions (if score < 8)

Use the AskUserQuestion tool with multiple-choice options. Ask only about the gaps identified.

**Principles:**
- Max 3 questions total
- Always provide escape hatch ("Other - I'll describe")
- Use codebase context to suggest relevant files/areas

#### Question: Clarify the What (if gap)

```
Question: "What type of change is this?"
Options:
  1. "Fix a bug" - Something is broken or erroring
  2. "Add a feature" - New functionality needed
  3. "Change behavior" - Works but should work differently
  4. "Other" - I'll describe in detail
```

#### Question: Clarify the Where (if gap)

First, scan codebase for relevant directories:
```bash
# Find likely relevant areas based on issue title keywords
ls -d src/*/ 2>/dev/null | head -5
```

Then ask:
```
Question: "Where should this change happen?"
Options:
  1. "[detected-dir-1]" - [brief description if known]
  2. "[detected-dir-2]" - [brief description if known]
  3. "[detected-dir-3]" - [brief description if known]
  4. "Somewhere else" - I'll specify the location
```

#### Question: Clarify Acceptance (if gap)

```
Question: "How will we know it's done?"
Options:
  1. "Tests pass" - Existing or new automated tests verify it works
  2. "Manual verification" - Specific user action works without error
  3. "Visual check" - UI looks/behaves a certain way
  4. "I'll describe criteria" - Let me specify exactly
```

#### Question: Clarify Scope (if gap, and other gaps filled)

```
Question: "What's the right scope for this change?"
Options:
  1. "Minimal" - Just fix this specific issue, nothing else
  2. "Include edge cases" - Handle related scenarios too
  3. "Refactor if needed" - Do it right even if it means restructuring
```

### Step 3c: Confirm Scoped Requirements

After gathering answers, summarize:

```markdown
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 Issue #{number}: "{title}" - Scoped Requirements
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

**Type:** {bug/feature/change}

**Summary:** {1-2 sentence description combining original + answers}

**Location:** {files/areas identified}

**Acceptance Criteria:**
- [ ] {criterion 1}
- [ ] {criterion 2}

**Scope:** {minimal/moderate/refactor}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Then ask for confirmation:
```
Question: "Does this capture what you need?"
Options:
  1. "Yes, proceed to planning" - Create the implementation plan
  2. "Let me clarify something" - I'll add more detail
```

If user confirms, proceed to **Step 4: Planning Phase**.

### Step 4: Planning Phase

When requirements are confirmed (or issue scored 8+), transition to planning.

#### 4a: Enter Plan Mode

Use the `EnterPlanMode` tool to enter Claude Code's native planning mode. This allows exploration of the codebase and design of the implementation approach.

During plan mode:
1. Analyze the codebase for relevant patterns and conventions
2. Break down the work into small, testable tasks
3. Define acceptance criteria that can be verified with commands
4. **Write the plan following the required format** in `.claude/rules/planning-guide.md` (see "Required Plan Format for Plan Mode" section)

**Important:** The plan must follow the structured format to enable automatic transformation to prd.json.

#### 4b: Post Plan to GitHub

After exiting plan mode, post the implementation plan to the GitHub issue:

```bash
# Post implementation plan as comment
gh issue comment $ISSUE_NUMBER --body "$(cat <<'EOF'
## 📋 Implementation Plan

**Issue:** #$ISSUE_NUMBER - {title}
**Generated:** $(date +%Y-%m-%d)
**Status:** Draft
**Complexity:** {Low/Medium/High} ({N} tasks)

---

{Plan content from plan file - Overview and Tasks sections}

---

*React with 👍 to approve this plan, or comment with requested changes.*
EOF
)"

# Update label to AI: Planning
gh issue edit $ISSUE_NUMBER --add-label "AI: Planning"
```

#### 4c: Plan Review and Approval

Present the plan summary and ask for approval:

```
Question: "Approve this implementation plan?"
Options:
  1. "Yes, generate prd.json" - Approve and create machine-readable task file
  2. "Edit the plan" - Make changes before approving
  3. "Start over" - Discard and re-plan
```

#### 4d: Transform Plan to prd.json (on approval)

Parse the structured plan and generate `prd.json`. Use this field mapping:

| Plan Markdown | prd.json Field |
|---------------|----------------|
| `# Implementation Plan: Issue #N` | `issueNumber: N` |
| `### US-XXX: {title}` | `userStories[].id`, `userStories[].title` |
| `**Priority:** N` | `userStories[].priority` |
| `**Files:** ...` | `userStories[].files` |
| `**Depends On:** ...` | `userStories[].dependsOn` |
| `**Description:**` block | `userStories[].description` |
| `**Acceptance Criteria:**` list | `userStories[].acceptanceCriteria` |
| `**Verify Commands:**` code block | `userStories[].verifyCommands` |

Create `prd.json` in repo root:

```json
{
  "project": "{slug-from-title}",
  "issueNumber": 42,
  "branchName": "ai/issue-42-{slug}",
  "description": "{issue title}",
  "generatedAt": "{ISO timestamp}",
  "status": "approved",
  "userStories": [
    {
      "id": "US-001",
      "phase": 1,
      "priority": 1,
      "title": "Task title",
      "description": "What to implement",
      "files": ["path/to/file.ts"],
      "dependsOn": [],
      "acceptanceCriteria": ["Testable criterion"],
      "verifyCommands": ["npm run test"],
      "passes": false,
      "attempts": 0,
      "lastAttempt": null
    }
  ],
  "globalVerifyCommands": []
}
```

Then commit:
```bash
git add prd.json
git commit -m "chore: add prd.json for issue #$ISSUE_NUMBER"
```

#### 4e: Post Approval Comment

Post approval confirmation to GitHub issue:

```bash
gh issue comment $ISSUE_NUMBER --body "$(cat <<'EOF'
## ✅ Plan Approved

**prd.json generated** with {N} testable tasks.

Implementation ready. Run `/implement` to begin the loop.

### Task Status:
- [ ] US-001: {title}
- [ ] US-002: {title}
...
EOF
)"
```

Update labels:
```bash
gh issue edit $ISSUE_NUMBER --remove-label "AI: Planning" --add-label "AI: Approved"
```

#### 4f: Prompt for Implementation

Ask if user is ready to begin:

```
Question: "Ready to start implementation?"
Options:
  1. "Yes, run /implement" - Begin the implementation loop
  2. "Not yet" - I'll start later
```

### Step 5: Determine Issue State (for returning issues)

**This step is for issues that already have progress.** Skip to here when `--quick` is used or when an existing plan is detected.

Based on labels and comments, determine current state:

| Condition | State | Next Action |
|-----------|-------|-------------|
| Has `AI` label, no plan/prd.json | Needs Planning | Go to Step 4 |
| Has prd.json, no task logs | Ready to Implement | Suggest `/implement` |
| Has prd.json + partial task logs | In Progress | Show progress, suggest `/implement` |
| All tasks passing | Ready for Testing | Suggest `/implement` for testing checkpoint |

### Step 6: Parse Issue Comments

Scan comments for structured content:
- **Implementation Plan**: Comments starting with `## 📋 Implementation Plan`
- **Task Logs**: Comments starting with `## 📝 Task Log:`
- **Discovery Notes**: Comments starting with `## 🔍 Discovery Note`

### Step 7: Display Issue Summary

```markdown
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 Issue #{number}: {title}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

**State:** {state}
**Completeness:** {score}/10 {bar}
**Labels:** {labels}
**Branch:** {branch} ({exists | needs creation})

### Description
{Issue body content}

### Implementation Plan
{Plan content if exists, or "No plan found"}

### Progress
- [x] Task 1.1 - {title} (completed {time ago})
- [ ] Task 1.2 - {title} (next)

### Suggested Next Step
{action based on state}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Step 8: Setup Branch
Check if implementation branch exists:

```bash
git branch --list "ai/issue-$ISSUE_NUMBER-*"
```

If branch exists, offer to check it out. If not, note that `/implement` will create it.

---

## Quick Mode

When `--quick` flag is present:
- Skip evaluation (Step 3)
- Skip scoping questions (Step 3b, 3c)
- Load issue directly and proceed to state detection

Use for:
- Issues you know are well-defined
- Returning to an issue already in progress
- Quick checks on issue status

---

## Error Handling

| Error | Response |
|-------|----------|
| Issue not found | "Issue #{X} not found in this repository" |
| Issue is closed | "Note: This issue is closed. Reopen to continue." |
| No permission | "You don't have access to this repository" |
| gh CLI not authenticated | "Run `gh auth login` first" |

---

## Examples

### Well-Scoped Issue (Score: 9/10)

```
Issue #42: Login fails for emails with + character

Body: Users with emails like "user+test@gmail.com" get 500 error.
Location: src/api/auth.ts line 45
Expected: Login works for any valid email format
```

Flow:
```
📋 Issue #42: Login fails for emails with + character
**Completeness:** ████████░░ 9/10

This issue is well-defined.

→ [AskUserQuestion: "Ready to create implementation plan?"]
→ User: "Yes"
→ [Enters plan mode, creates plan]
→ [AskUserQuestion: "Approve this plan?"]
→ User: "Yes"
→ [Generates prd.json, posts approval comment]
→ [AskUserQuestion: "Ready to start implementation?"]
```

### Vague Issue (Score: 2/10)

```
Issue #15: test
Body: test
```

Flow:
```
📋 Issue #15: test
**Completeness:** ██░░░░░░░░ 2/10

This issue needs more detail. Let me ask a few quick questions...

→ [AskUserQuestion: What type? Where? Acceptance?]
→ User answers
→ [Shows scoped requirements summary]
→ [AskUserQuestion: "Does this capture what you need?"]
→ User: "Yes"
→ [Proceeds to planning phase]
```

### Returning to In-Progress Issue

```bash
/issue 42 --quick
```

Flow:
```
📋 Issue #42: Login fix
**State:** In Progress

### Progress
- [x] US-001: Add email validation util (passed)
- [ ] US-002: Update login form (next)

→ Run `/implement` to continue with US-002
```

---

## Tips

- Use `/issue 42` for new issues or to re-scope
- Use `/issue 42 --quick` when returning to an issue already in progress
- The full flow: scope → plan → approve → implement
- Task logs in comments serve as persistent memory between sessions

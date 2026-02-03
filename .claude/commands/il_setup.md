# /il_setup - Initialize GitHub Issue Workflow

## Description
Sets up the GitHub repository for the AI-assisted issue workflow. Creates labels, verifies prerequisites, and configures the repository for automated planning. Run this utility command before starting the core workflow.

## Usage
```
/il_setup              # Full setup
/il_setup --labels     # Only create labels
/il_setup --verify     # Check setup without making changes
```

## Prerequisites Check

Before running setup, verify these requirements:

### Step 1: Check GitHub CLI
```bash
# Verify gh is installed
gh --version

# If not installed, show:
# "GitHub CLI not found. Install with: brew install gh"
```

### Step 2: Check Authentication
```bash
# Verify authenticated
gh auth status

# If not authenticated, show:
# "Not authenticated. Run: gh auth login"
```

### Step 3: Check Repository
```bash
# Verify we're in a git repo with GitHub remote
git remote get-url origin

# Parse owner/repo from URL
# If not a GitHub repo, show:
# "This doesn't appear to be a GitHub repository"
```

## Setup Steps

### Step 4: Create Labels
```bash
# Create all workflow labels
# Using --force to update if they already exist

gh label create "AI" \
  --color "7057ff" \
  --description "Trigger for AI-assisted planning and implementation" \
  --force

gh label create "AI: Planning" \
  --color "d4c5f9" \
  --description "Implementation plan being generated or revised" \
  --force

gh label create "AI: Approved" \
  --color "0e8a16" \
  --description "Plan approved, ready for implementation" \
  --force

gh label create "AI: In Progress" \
  --color "fbca04" \
  --description "Implementation actively underway" \
  --force

gh label create "AI: Testing" \
  --color "c2e0c6" \
  --description "Implementation complete, awaiting manual testing" \
  --force

gh label create "AI: Blocked" \
  --color "b60205" \
  --description "Blocked, awaiting human input" \
  --force

gh label create "AI: Review" \
  --color "1d76db" \
  --description "Implementation complete, PR ready for review" \
  --force

gh label create "AI: Complete" \
  --color "0e8a16" \
  --description "Issue fully resolved and closed" \
  --force
```

### Step 5: Verify Label Creation
```bash
# List labels to confirm
gh label list --search "AI"
```

### Step 6: Create Issue Template Directory
```bash
# Create .github/ISSUE_TEMPLATE if it doesn't exist
mkdir -p .github/ISSUE_TEMPLATE
```

### Step 7: Create AI Request Issue Template
Create `.github/ISSUE_TEMPLATE/ai_request.md`:

```markdown
---
name: AI Implementation Request
about: Request AI-assisted implementation of a feature or fix
title: ''
labels: ''
assignees: ''
---

## Summary
<!-- One sentence describing what needs to be done -->

## Background
<!-- Why is this needed? What problem does it solve? -->

## Requirements
<!-- List specific requirements or acceptance criteria -->

- [ ] Requirement 1
- [ ] Requirement 2
- [ ] Requirement 3

## Technical Context
<!-- Any technical details, constraints, or relevant files -->

### Relevant Files
- `path/to/file.ts`

### Dependencies
- Related to #XX (if any)

## Out of Scope
<!-- Explicitly state what should NOT be included -->

---
<!-- Add the "AI" label after creating to trigger planning -->
```

### Step 8: Check for Existing CLAUDE.md
```bash
# Check if .claude/rules directory exists
if [ ! -d ".claude/rules" ]; then
  mkdir -p .claude/rules
  echo "Created .claude/rules directory"
fi

# Check if workflow rules exist
if [ ! -f ".claude/rules/github-issue-workflow.md" ]; then
  echo "⚠️  Workflow rules not found at .claude/rules/github-issue-workflow.md"
  echo "   Copy from the workflow package or run the install script"
fi
```

### Step 9: Verify Pipedream Webhook (Optional)
```bash
# This is informational - can't verify programmatically
echo ""
echo "📋 Manual Step Required:"
echo "   Set up Pipedream workflow to trigger on 'AI' label"
echo "   See: pipedream/github-to-claude-plan.md"
```

## Output

### Successful Setup
```
🔧 GitHub Issue Workflow Setup
==============================

Repository: owner/repo

✅ Prerequisites
   • GitHub CLI installed (v2.40.0)
   • Authenticated as @username
   • Repository detected

✅ Labels Created
   • AI
   • AI: Planning
   • AI: Approved
   • AI: In Progress
   • AI: Testing
   • AI: Blocked
   • AI: Review
   • AI: Complete

✅ Issue Template
   • Created .github/ISSUE_TEMPLATE/ai_request.md

✅ Workflow Rules
   • Found at .claude/rules/github-issue-workflow.md

⚠️  Manual Steps Remaining
   1. Set up Pipedream workflow for automated planning
      See: pipedream/github-to-claude-plan.md
   
   2. Add workflow reference to your CLAUDE.md:
      ## GitHub Issue Workflow
      See `.claude/rules/github-issue-workflow.md` for workflow rules.

==============================
Setup complete! Create an issue and add the "AI" label to test.
```

### Verification Mode (--verify)
```
🔍 GitHub Issue Workflow Verification
=====================================

Repository: owner/repo

Prerequisites:
  ✅ GitHub CLI installed (v2.40.0)
  ✅ Authenticated as @username
  ✅ GitHub repository detected

Labels:
  ✅ AI
  ✅ AI: Planning
  ✅ AI: Approved
  ✅ AI: In Progress
  ✅ AI: Testing
  ✅ AI: Blocked
  ✅ AI: Review
  ✅ AI: Complete

Files:
  ✅ .claude/rules/github-issue-workflow.md
  ✅ .claude/commands/issues.md
  ✅ .claude/commands/issue.md
  ✅ .claude/commands/plan.md
  ✅ .claude/commands/implement.md
  ✅ .claude/commands/issue-close.md
  ⚠️  .github/ISSUE_TEMPLATE/ai_request.md (missing - optional)

=====================================
Status: Ready to use (1 optional item missing)
```

## Error Handling

| Error | Response |
|-------|----------|
| gh not installed | Show install instructions for platform |
| Not authenticated | Show `gh auth login` command |
| Not a git repo | "Navigate to a git repository first" |
| Not a GitHub repo | "Remote must be a GitHub repository" |
| Label create fails | Show error, continue with other labels |
| No write access | "You need write access to create labels" |

## Recovery Commands

If setup partially fails, user can run individual fixes:

```bash
# Re-run just labels
/issue setup --labels

# Manual label creation
gh label create "AI" --color "7057ff" --force

# Check what exists
gh label list --search "AI"
```

# /il_validate - Check Workflow Prerequisites

## Description
Performs read-only validation of all workflow prerequisites without making any changes. Use this utility command to diagnose setup issues or verify configuration before starting work.

## Usage
```
/il_validate           # Run all validation checks
```

## Validation Steps

Run these checks **in order**, stopping with clear error message if any fails:

### Step 1: Check Required Tools

Check each tool is installed and capture version:

```bash
# Check gh
gh --version 2>/dev/null | head -1
# Expected: "gh version X.X.X ..."
# If fails: "GitHub CLI not found. Install: brew install gh (macOS) / apt install gh (Linux)"

# Check git
git --version 2>/dev/null
# Expected: "git version X.X.X"
# If fails: "Git not found. Install git before continuing."

# Check jq
jq --version 2>/dev/null
# Expected: "jq-X.X"
# If fails: "jq not found. Install: brew install jq (macOS) / apt install jq (Linux)"
```

### Step 2: Check GitHub CLI Authentication

```bash
# Check authentication status
gh auth status 2>&1

# Parse for username - look for "Logged in to github.com account"
# Extract username from output

# If not authenticated: "GitHub CLI not authenticated. Run: gh auth login"
```

### Step 3: Check Git Repository

```bash
# Verify we're in a git repo
git rev-parse --is-inside-work-tree 2>/dev/null
# If fails: "Not a git repository. Navigate to a git repo first."

# Check for GitHub remote
git remote get-url origin 2>/dev/null
# If fails: "No remote 'origin' configured."
# If not GitHub: "Remote is not a GitHub repository."
```

### Step 4: Check Config File

```bash
# Check if .issueloop.config.json exists
if [ -f ".issueloop.config.json" ]; then
  # Validate JSON syntax
  jq empty .issueloop.config.json 2>/dev/null
  # If fails: "Config file exists but contains invalid JSON"
else
  # File missing: "Config file not found: .issueloop.config.json"
fi
```

### Step 5: Check Required Labels

Check all 8 workflow labels exist on the repository:

```bash
# Get all labels from repo
gh label list --json name --jq '.[].name'

# Check for each required label:
# - AI
# - AI: Planning
# - AI: Approved
# - AI: In Progress
# - AI: Testing
# - AI: Blocked
# - AI: Review
# - AI: Complete
```

For each missing label, report it in the output.

## Output Format

### All Checks Pass
```
🔍 Issue Workflow Validation
============================

Repository: owner/repo

Tools:
  ✅ gh version 2.40.0
  ✅ git version 2.42.0
  ✅ jq-1.7

Authentication:
  ✅ Logged in as @username

Repository:
  ✅ Git repository detected
  ✅ GitHub remote: owner/repo

Configuration:
  ✅ .issueloop.config.json valid

Labels:
  ✅ AI
  ✅ AI: Planning
  ✅ AI: Approved
  ✅ AI: In Progress
  ✅ AI: Testing
  ✅ AI: Blocked
  ✅ AI: Review
  ✅ AI: Complete

============================
✅ All checks passed! Workflow ready.
```

### Some Checks Fail
```
🔍 Issue Workflow Validation
============================

Repository: owner/repo

Tools:
  ✅ gh version 2.40.0
  ✅ git version 2.42.0
  ❌ jq not found
     Install: brew install jq (macOS) / apt install jq (Linux)

Authentication:
  ✅ Logged in as @username

Repository:
  ✅ Git repository detected
  ✅ GitHub remote: owner/repo

Configuration:
  ❌ .issueloop.config.json not found
     Run: /issue setup to create configuration

Labels:
  ✅ AI
  ✅ AI: Planning
  ❌ AI: Approved (missing)
  ✅ AI: In Progress
  ✅ AI: Testing
  ✅ AI: Blocked
  ❌ AI: Review (missing)
  ✅ AI: Complete

============================
❌ 3 issues found. Run /issue setup to fix label issues.
```

## Error Handling

| Check | Error | Suggested Fix |
|-------|-------|---------------|
| gh missing | Tool not installed | `brew install gh` / `apt install gh` |
| git missing | Tool not installed | Install git for your platform |
| jq missing | Tool not installed | `brew install jq` / `apt install jq` |
| gh not authed | Not logged in | `gh auth login` |
| Not a git repo | Wrong directory | Navigate to your project |
| No GitHub remote | Remote not configured | `git remote add origin <url>` |
| Config missing | Not initialized | Run `/issue setup` |
| Config invalid | Bad JSON | Check syntax in config file |
| Labels missing | Not created | Run `/issue setup` |

## Implementation Notes

1. **Read-only**: This command makes NO changes - only reads and reports
2. **Order matters**: Check tools before auth, auth before repo, etc.
3. **Continue on failure**: Report ALL issues, don't stop at first failure
4. **Clear fixes**: Every failure should include actionable fix instructions

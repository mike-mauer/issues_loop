# GitHub Issue-Driven Development Workflow (Ralph Pattern)

A complete workflow for AI-assisted development using GitHub Issues as the coordination point, Pipedream for automation, and Claude Code for implementation.

**Based on the [Ralph Pattern](https://github.com/snarktank/ralph)** - autonomous AI loops with testable tasks, fresh context per iteration, and persistent memory via git and issue comments.

## 🎯 Workflow Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         AUTOMATED FLOW                               │
│                                                                      │
│   1. Create Issue      2. Add "AI" Label    3. Plan Generated       │
│   ────────────────  →  ────────────────  →  ────────────────        │
│   GitHub                Triggers Pipedream   Claude API creates     │
│                                              plan as comment         │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                      LOCAL FLOW (Claude Code)                        │
│                                                                      │
│   4. /il_list          5. /il_1_plan N      6. /il_2_implement      │
│   ────────────────  →  ────────────────  →  ────────────────        │
│   List & select        Scope, plan,         Execute tasks,          │
│   issue                approve              commit each             │
│                                                                      │
│   7. /il_3_close                                                     │
│   ────────────────                                                   │
│   Generate report,                                                   │
│   create PR, archive                                                 │
└─────────────────────────────────────────────────────────────────────┘
```

## System Requirements

| Tool | Required | Version | Installation |
|------|----------|---------|--------------|
| Git | Yes | 2.x+ | Pre-installed on most systems |
| GitHub CLI (gh) | Yes | 2.x+ | `brew install gh` / `apt install gh` |
| jq | Yes | 1.6+ | `brew install jq` / `apt install jq` |
| Bash | Yes | 4.0+ | Pre-installed on macOS/Linux |
| Node.js | Optional | 18+ | Only for Pipedream alternative |

### Platform Notes

| Platform | Support Level | Notes |
|----------|--------------|-------|
| **macOS** | Full | Recommended development environment |
| **Linux** | Full | All features supported |
| **Windows (WSL2)** | Full | Recommended for Windows users |
| **Windows (Git Bash)** | Partial | Background loop may not work correctly |

### Windows Users

This workflow requires **WSL2** for full functionality. The background loop script (`implement-loop.sh`) uses bash-specific features including:
- `flock` for file locking
- Process management with `nohup`
- POSIX-compliant shell features

**To set up WSL2:**
1. Open PowerShell as Administrator
2. Run: `wsl --install`
3. Restart and complete Ubuntu setup
4. Install dependencies: `sudo apt install gh jq`

---

## 📦 Installation

### 1. Copy files to your project

```bash
# Create .claude directory in your project
mkdir -p .claude/commands

# Copy all files
cp -r path/to/this/repo/.claude/* your-project/.claude/
```

### 2. Run Setup Command

After copying files, in Claude Code run:
```
/il_setup
```

This creates all required labels automatically:

| Label | Color | Description |
|-------|-------|-------------|
| `AI` | `#7057ff` | Trigger for AI planning |
| `AI: Planning` | `#d4c5f9` | Plan being generated |
| `AI: Approved` | `#0e8a16` | Plan approved for implementation |
| `AI: In Progress` | `#fbca04` | Implementation in progress |
| `AI: Blocked` | `#b60205` | Blocked, needs human input |
| `AI: Review` | `#1d76db` | Ready for code review |
| `AI: Complete` | `#0e8a16` | Done |

### 3. Setup Pipedream Workflow

1. Create a new workflow in [Pipedream](https://pipedream.com)
2. Follow the steps in `pipedream/github-to-claude-plan.md`
3. Add your API keys:
   - `ANTHROPIC_API_KEY` - Get from [Anthropic Console](https://console.anthropic.com)
   - GitHub OAuth (automatic via Pipedream GitHub app)
4. Deploy the workflow

### 4. Install GitHub CLI

```bash
# macOS
brew install gh

# Login
gh auth login
```

### 5. Verify Setup

```bash
# In your project directory
gh issue list --limit 5
```

## 🚀 Usage

### Creating a New Task

1. **Create an issue** describing what you want to build
2. **Add the "AI" label** - this triggers automatic plan generation
3. **Wait for the plan** to appear as a comment (~30 seconds)
4. **Review the plan** and request changes or approve

### Working on an Issue

```bash
# Start Claude Code in your project
claude

# List all open issues
/il_list

# Load, scope, plan, and approve (guided flow with prompts)
/il_1_plan 42

# Start implementation (creates branch + launches background loop)
/il_2_implement

# Monitor background loop progress (optional)
tail -f .claude/implement-loop.log

# When loop completes, continue with testing
/il_2_implement      # Enters testing checkpoint if all tasks pass

# After user testing verified, generate report and PR
/il_3_close
```

### Commands Reference

| Command | Description |
|---------|-------------|
| `/il_setup` | **Run first!** Creates labels, templates, verifies setup |
| `/il_validate` | Check all prerequisites are configured correctly |
| `/il_list` | List all open GitHub issues |
| `/il_1_plan <number>` | **Step 1:** Load → scope → plan → approve (with inline prompts) |
| `/il_1_plan <number> --quick` | Load issue, skip to status check (for returning to in-progress work) |
| `/il_2_implement` | **Step 2:** Create branch + launch background task loop |
| `/il_2_implement verify` | Re-run verification commands for current task |
| `/il_2_implement interactive-mode` | ⚠️ Escape hatch - execute in conversation (breaks fresh context) |
| `/il_3_close` | **Step 3:** Generate report, create PR, auto-archive if merged |
| `/il_3_close --force` | Skip testing verification |
| `/il_3_close preview` | Preview report without posting |

## 📁 File Structure

```
your-project/
├── .claude/
│   ├── CLAUDE.md              # Your project's main rules (template provided)
│   ├── rules/
│   │   ├── github-issue-workflow.md  # Issue workflow rules (Ralph Pattern)
│   │   ├── planning-guide.md         # Planning methodology reference
│   │   └── custom-planning-protocol.md # 5-phase planning protocol
│   ├── commands/
│   │   ├── il_setup.md        # /il_setup command
│   │   ├── il_validate.md     # /il_validate command
│   │   ├── il_list.md         # /il_list command
│   │   ├── il_1_plan.md       # /il_1_plan command (Step 1: scope + plan + approve)
│   │   ├── il_2_implement.md  # /il_2_implement command (Step 2: Ralph Loop)
│   │   └── il_3_close.md      # /il_3_close command (Step 3: report + PR + archive)
│   └── scripts/
│       └── implement-loop.sh  # Background task loop script
├── prd.json                   # Task state (created during plan approval)
```

### Integration with Existing Projects

If you already have a `CLAUDE.md`, add this section to it:

```markdown
## GitHub Issue Workflow
This project uses GitHub Issues for AI-assisted development.
See `.claude/rules/github-issue-workflow.md` for workflow rules.
```

## 🔍 Issue Scoping

When you load an issue with `/il_1_plan N`, it's automatically evaluated for completeness on 5 dimensions:

| Dimension | What's Checked |
|-----------|----------------|
| **What** | Is the change clearly described? |
| **Where** | Are files/locations specified? |
| **Why** | Is user impact explained? |
| **Scope** | Are boundaries defined? |
| **Acceptance** | Are there testable criteria? |

Each dimension scores 0-2 points (max 10). Based on score:

| Score | Action |
|-------|--------|
| **8-10** | Well-defined → Proceed to planning |
| **5-7** | Minor gaps → Ask 1-2 targeted questions |
| **0-4** | Needs detail → Ask up to 3 questions |

**Questions are multiple-choice** for quick answers, with "Other" option for custom input.

Use `/il_1_plan N --quick` to skip scoping when returning to an issue already in progress.

## 🔄 The Memory System (Ralph Pattern)

This workflow uses the **Ralph Loop** pattern for autonomous implementation. Memory persists via:

### GitHub Issue Comments
| Prefix | Purpose |
|--------|---------|
| `## 📋 Implementation Plan` | The structured plan |
| `## 📝 Task Log: US-XXX` | Task completion log (pass or fail) |
| `## 🔍 Discovery Note` | Patterns/learnings for future iterations |
| `## 🧪 Testing Checkpoint` | Request user testing |
| `## 🔧 Debug Session` | Debug attempt |
| `## ✅ Debug Fix Applied` | Debug fix verified |
| `## 🚫 Debug Blocked` | Debug failed 3x |
| `## 📊 Final Report` | Final summary |

### prd.json (in repo)
After plan approval, `prd.json` tracks testable task state:

```json
{
  "issueNumber": 42,
  "branchName": "ai/issue-42-user-auth",
  "userStories": [
    {
      "id": "US-001",
      "title": "Create user model",
      "acceptanceCriteria": ["Migration creates users table", "npm run typecheck passes"],
      "verifyCommands": ["npm run db:migrate", "npm run typecheck"],
      "passes": false,
      "attempts": 0
    }
  ]
}
```

### Key Concept: Fresh Context Per Iteration
Each `/il_2_implement` execution is a **new session** with no memory. Context comes only from:
1. `prd.json` - Which tasks pass/fail
2. GitHub Issue comments - Task logs and learnings
3. Git history - What code was committed

Task descriptions must be **self-contained** so any iteration can pick up any task.

### Task Size Rule
Each task should complete in one context window. **If you can't describe the change in 2-3 sentences, split it.**

### Acceptance Criteria = The Test
Every criterion must be **automatically verifiable**:
- ✅ "npm run typecheck passes"
- ✅ "npm run test -- auth passes"
- ❌ "Code is clean" (subjective)

## 🧪 Testing Checkpoint

After all tasks pass automated verification, the workflow enters a **Testing Checkpoint** before closing. This ensures human verification of the implementation.

### Flow
```
All tasks pass → Testing Checkpoint → User tests
                                         ↓
                        ┌────────────────┼────────────────┐
                        ↓                ↓                ↓
                    "Works"          "Issue"          "Later"
                        ↓                ↓                ↓
                /il_3_close       Debug Flow         Pause
```

### What Happens
1. **All tasks pass** → Label changes to `AI: Testing`
2. **Checkpoint posted** → Comment requests manual testing
3. **User responds** with one of:
   - **Works** → Proceed to `/il_3_close`
   - **Found issue** → Enter debug flow (3 attempts max)
   - **Need more time** → Pause, resume later with `/il_2_implement`

### Debug Flow
When user reports an issue:
1. **Gather info** via 3 structured questions (type, location, description)
2. **Attempt fix** based on reported issue
3. **Re-test** with user
4. **Loop** until fixed or blocked (max 3 attempts)

If debug fails 3 times → `AI: Blocked` label, awaiting human guidance.

## 🌿 Branch Strategy

- One branch per issue: `ai/issue-{number}-{slug}`
- Commits after each task: `task(X.Y): description (#issue)`
- PR created on completion, auto-closes issue on merge

## 🛠 Troubleshooting

### Plan not generating
- Check Pipedream execution logs
- Verify the "AI" label exists and was just added
- Check API key is valid

### Commands not working
- Ensure you're in a git repository
- Verify `gh` CLI is installed and authenticated
- Check `.claude/` directory exists

### Task blocked
- Review the blocker note in the issue
- Add a comment with guidance
- Run `/il_2_implement` to continue

## 📝 License

MIT

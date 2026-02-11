---
name: issues-loop
description: >
  GitHub Issue workflow system for AI-assisted development.
  Trigger when the user asks to plan, implement, or close GitHub issues
  using the Issues Loop workflow (Ralph Pattern). Also trigger for
  il-setup, il-list, il-validate, il-1-plan, il-2-implement, or il-3-close commands.
  Do NOT trigger for general GitHub issue viewing or unrelated project management.
---

# Issues Loop — GitHub Issue Workflow (Ralph Pattern)

This skill provides a complete workflow for AI-assisted development driven by GitHub Issues.
It breaks work into small, testable tasks, executes each in a fresh context, verifies with
automated tests, and persists learnings for future iterations.

## Quick Start

```
il-setup          # Initialize repo with labels and templates
il-list           # List open issues
il-1-plan 42      # Scope, plan, and approve issue #42
il-2-implement    # Execute the implementation loop
il-3-close        # Generate report, create PR, archive
il-validate       # Check all prerequisites
```

## Commands

### il-setup — Initialize GitHub Issue Workflow

Sets up the repository for the AI-assisted issue workflow. Creates 8 workflow labels,
verifies prerequisites (gh CLI, authentication, git repo), and creates the issue template.

**Usage:**
```
il-setup              # Full setup
il-setup --labels     # Only create labels
il-setup --verify     # Check setup without making changes
```

**What it does:**
1. Checks prerequisites (gh CLI, authentication, GitHub remote)
2. Creates workflow labels: AI, AI: Planning, AI: Approved, AI: In Progress, AI: Testing, AI: Blocked, AI: Review, AI: Complete
3. Creates `.github/ISSUE_TEMPLATE/ai_request.md`
4. Verifies workflow rules are installed

**Full reference:** `references/il-setup.md`

---

### il-list — List Open GitHub Issues

Fetches and displays all open issues from the current repository for selection.

**Usage:**
```
il-list               # List all open issues
il-list --label AI    # Filter by label
```

**What it does:**
1. Detects repository from git remote
2. Fetches open issues via `gh issue list`
3. Displays issues in a table with labels and timestamps
4. User selects an issue to load into `il-1-plan`

**Full reference:** `references/il-list.md`

---

### il-1-plan — Load, Scope, and Plan GitHub Issue

The full planning flow: loads an issue, evaluates completeness, gathers requirements,
and guides through a 5-phase planning process to produce an approved `prd.json`.

**Usage:**
```
il-1-plan 42          # Load and plan issue #42
il-1-plan #42         # Same, with # prefix
il-1-plan 42 --quick  # Skip scoping, jump to status check
```

**What it does:**
1. **Prerequisites** — Validates gh, git, jq, GitHub remote
2. **Fetch** — Loads issue details and existing comments
3. **Formula detection** — Classifies as bugfix, feature, or refactor
4. **Completeness evaluation** — Scores issue 0-10 on What/Where/Why/Scope/Acceptance
5. **Scoping** — If score < 8, asks 1-3 multiple-choice questions
6. **Planning** — 5-phase custom protocol (Exploration → Decomposition → Validation → GitHub Post → prd.json)
7. **State detection** — Checks for existing branch, prd.json, or prior plan
8. **Branch setup** — Creates `ai/issue-{N}-{slug}` branch

**Key outputs:**
- GitHub comment: `## 📋 Implementation Plan` (human-readable)
- File: `prd.json` (machine-readable task state)
- GitHub comment: `## ✅ Plan Approved` (confirmation)

**Full reference:** `references/il-1-plan.md`
**Planning protocol:** `references/custom-planning-protocol.md`
**Plan format:** `references/planning-guide.md`

---

### il-2-implement — Execute Task Loop (Ralph Pattern)

Executes the implementation loop. Launches a background process that autonomously
implements all tasks until complete or blocked. Each task runs in a fresh context.

**Usage:**
```
il-2-implement            # Create branch if needed + launch loop
il-2-implement verify     # Re-run verification for current task
```

**What it does (per task):**
1. Reads `prd.json` for next failing task
2. Assembles context (task details, git history, issue comments, wisps)
3. Implements the task in a fresh context
4. Runs all verify commands
5. Updates `passes` status in `prd.json`
6. Posts task log to GitHub with structured Event JSON
7. Posts Discovery Notes for patterns found
8. Handles discovered task auto-enqueue
9. Compacts summaries every N task logs

**On completion:** Enters Testing Checkpoint — requests manual user testing.
**On failure (3x):** Labels issue `AI: Blocked`, stops loop.

**Key concepts:**
- **Fresh context per task** — Each task starts with zero memory
- **Event JSON** — Structured JSON in task log comments for machine parsing
- **Wisps** — Ephemeral context hints with TTL
- **Discovery Notes** — Persistent learnings for future tasks
- **Compaction** — Periodic summaries to keep context lean

**Full reference:** `references/il-2-implement.md`
**Workflow rules:** `references/github-issue-workflow.md`

---

### il-3-close — Generate Final Report and Create PR

Generates a comprehensive final report, creates a Pull Request, and archives
the implementation after merge.

**Usage:**
```
il-3-close            # Generate report, create PR, auto-archive if merged
il-3-close --force    # Bypass verification requirement
il-3-close preview    # Preview report without posting
```

**What it does:**
1. Validates all tasks pass and testing is verified
2. Generates `## 📊 Final Report` from prd.json and issue comments
3. Creates Pull Request with implementation details
4. Auto-detects PR state (new / open / merged)
5. On merge: archives prd.json + comments, updates labels, closes issue

**Full reference:** `references/il-3-close.md`

---

### il-validate — Check Workflow Prerequisites

Read-only validation of all workflow prerequisites. Use to diagnose setup issues.

**Usage:**
```
il-validate           # Run all checks
```

**What it checks:**
1. Required tools: gh, git, jq
2. GitHub CLI authentication
3. Git repository with GitHub remote
4. Config file `.issueloop.config.json`
5. All 8 workflow labels exist

**Full reference:** `references/il-validate.md`

---

## Workflow Overview

```
┌─────────────┐     ┌─────────────┐     ┌──────────────┐
│  il-setup    │────▶│  il-list     │────▶│  il-1-plan N │
│  (one-time)  │     │  (discover)  │     │  (scope+plan)│
└─────────────┘     └─────────────┘     └──────┬───────┘
                                               │
                                               ▼
┌─────────────┐     ┌─────────────┐     ┌──────────────┐
│  il-3-close  │◀───│   Testing    │◀───│il-2-implement│
│  (PR+archive)│     │  Checkpoint  │     │  (task loop) │
└─────────────┘     └─────────────┘     └──────────────┘
```

### Issue Labels (State Machine)

| Label | Meaning |
|-------|---------|
| `AI` | Trigger for planning |
| `AI: Planning` | Plan being generated/refined |
| `AI: Approved` | Plan approved, prd.json generated |
| `AI: In Progress` | Implementation loop running |
| `AI: Testing` | All tasks pass, awaiting user testing |
| `AI: Blocked` | Task failed 3x or debug blocked |
| `AI: Review` | User verified, PR ready |
| `AI: Complete` | Merged and closed |

## Memory System

The Ralph Pattern uses three persistence layers:

| Source | Contains | Created By |
|--------|----------|------------|
| `prd.json` | Task definitions, pass/fail, verify commands | `il-1-plan` |
| GitHub Comments | Task logs, discovery notes, wisps | `il-2-implement` |
| Git History | Implementation commits | `il-2-implement` |

### GitHub Comment Prefixes

| Prefix | Purpose |
|--------|---------|
| `## 📋 Implementation Plan` | Human-readable plan |
| `## ✅ Plan Approved` | Approval confirmation |
| `## 📝 Task Log: US-XXX` | Per-task execution log |
| `## 🔍 Discovery Note` | Learnings for future tasks |
| `## 🧾 Compacted Summary` | Periodic task log summary |
| `## 🪶 Wisp` | Ephemeral context hint with TTL |
| `## 🧪 Testing Checkpoint` | Request manual testing |
| `## 🔧 Debug Session` | Debug attempt |
| `## ✅ Debug Fix Applied` | Successful debug fix |
| `## 🚫 Debug Blocked` | Debug failed 3x |
| `## 📊 Final Report` | Summary before PR |

## Task Design Rules

Each task must be:
- **One context window** — If description > 3 sentences, split it
- **Self-contained** — Includes all needed context
- **Automatically verifiable** — Acceptance criteria = shell commands

**Good criteria:** `npm run typecheck passes`, `POST /api/users returns 201`
**Bad criteria:** "Code is clean", "Works correctly"

## Branch & Commit Strategy

- **Branch:** `ai/issue-{N}-{slug}` (one per issue)
- **Task commit:** `feat(US-003): description (#42)`
- **State commit:** `chore: update prd.json - US-003 passed (#42)`

## Formula Templates

Three issue formula types guide task topology:
- **bugfix** — reproduce → fix → verify (`references/formulas/bugfix.md`)
- **feature** — scaffold → implement → test (`references/formulas/feature.md`)
- **refactor** — characterize → transform → verify (`references/formulas/refactor.md`)

## Recovery

```bash
# Check task state
cat prd.json | jq '.userStories[] | {id, passes, attempts}'

# Review recent commits
git log --oneline -5

# Resume implementation
il-2-implement
```

## Directory Structure

```
.agents/skills/issues-loop/
├── SKILL.md                          # This file — command dispatcher
├── references/
│   ├── github-issue-workflow.md      # Core Ralph Pattern rules
│   ├── planning-guide.md            # Plan format + prd.json schema
│   ├── custom-planning-protocol.md   # 5-phase planning system
│   ├── il-setup.md                   # Setup command reference
│   ├── il-list.md                    # List command reference
│   ├── il-validate.md               # Validate command reference
│   ├── il-1-plan.md                 # Plan command reference
│   ├── il-2-implement.md            # Implement command reference
│   ├── il-3-close.md               # Close command reference
│   └── formulas/
│       ├── bugfix.md
│       ├── feature.md
│       └── refactor.md
├── scripts/
│   ├── implement-loop.sh            # Background loop orchestrator
│   └── implement-loop-lib.sh        # Shared shell functions
└── assets/
    └── issue-template.md            # GitHub issue template
```

## Prerequisites

- GitHub CLI (`gh`) installed and authenticated
- Git repository with GitHub remote
- `jq` installed (for prd.json operations)
- GitHub repository with issues enabled

Run `il-validate` to check all prerequisites, or `il-setup` to initialize.

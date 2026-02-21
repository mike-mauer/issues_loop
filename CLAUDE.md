# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# GitHub Issue Workflow System (Ralph Pattern)

This is a meta-project that provides a complete workflow system for AI-assisted development using GitHub Issues. It is designed to be copied into other projects to enable autonomous AI implementation loops.

## Project Architecture

### Core Components

1. **Workflow Rules** (`.claude/rules/github-issue-workflow.md`)
   - Defines the Ralph Pattern methodology
   - Documents state transitions and memory system
   - Provides task design guidelines

2. **Command Skills** (`.claude/commands/`)
   - `/il_setup` - Creates GitHub labels and templates
   - `/il_list` - Lists open issues using GitHub CLI
   - `/il_1_plan N` - **Full flow:** loads issue → scopes → plans → approves (with inline prompts)
   - `/il_2_implement` - Executes tasks in a fresh context loop
   - `/il_3_close` - Creates final summary, PR, and archives after merge

3. **State Management**
   - `prd.json` - Machine-readable task state (generated on plan approval)
   - GitHub issue comments - Human-readable logs and learnings
   - Git commits - Implementation history

### The Ralph Pattern

This workflow implements autonomous AI loops with three key principles:

1. **Fresh Context Per Iteration**: Each `/il_2_implement` run starts with zero memory. Context comes only from prd.json, git history, and GitHub comments.

2. **Testable Tasks**: Every task has automated verification commands. Acceptance criteria must be programmatically verifiable (not subjective).

3. **Persistent Learnings**: Discoveries and patterns are written to GitHub issue comments as "Discovery Notes" to inform future iterations.

## Installation

This project is designed to be installed into other repositories. Installation workflow:

1. Run `./install.sh <target-directory>` OR manually copy `.claude/` directory
2. In target project, run `/il_setup` to create labels
3. Configure Pipedream workflow (see `pipedream/github-to-claude-plan.md`)
4. Update target project's CLAUDE.md to reference workflow rules

## Usage Flow

### Automated Planning (via Pipedream)
1. Create GitHub issue describing desired feature
2. Add "AI" label → triggers Pipedream workflow
3. Claude API generates plan as issue comment (~30 seconds)
4. Review and approve plan

### Manual Implementation (via Claude Code)
1. `/il_list` - List open issues
2. `/il_1_plan 42` - **Guided flow:** scope → plan → approve (all with inline prompts)
3. `/il_2_implement start` - Create branch `ai/issue-{number}-{slug}` and begin
4. `/il_2_implement` - Execute next failing task (loops until all pass, then testing checkpoint)
5. `/il_3_close` - Generate final summary, create PR, and archive after merge

### The /il_1_plan Flow
When `/il_1_plan N` is run:
1. **Evaluate** - Score issue 0-10 on completeness (What, Where, Why, Scope, Acceptance)
2. **Scope** - If score < 7, ask up to 3 multiple-choice questions to gather requirements
3. **Plan** - Run custom 5-phase planning protocol with score-adaptive checkpoints
4. **Approve + Start** - High-score issues use a combined approval/start checkpoint
5. **Fallback** - Low-score issues keep full checkpoint flow

Use `/il_1_plan N --quick` to skip to status check for issues already in progress.

## Key Files

- `.claude/rules/github-issue-workflow.md` - Complete Ralph Pattern documentation
- `prd.json` - Generated per issue, tracks task pass/fail status
- `templates/ISSUE_TEMPLATE_ai_request.md` - GitHub issue template for AI requests

## Prerequisites

- GitHub CLI (`gh`) installed and authenticated
- Git repository
- GitHub repository with issues enabled
- (Optional) Pipedream account for automated planning

## Memory System

### State Persistence
| Source | Contains | Created By |
|--------|----------|------------|
| `prd.json` | Task definitions, pass/fail status, verify commands | `/il_1_plan` (on approval) |
| GitHub Comments | Task logs, discovery notes, learnings | `/il_2_implement` |
| Git History | Implementation commits | `/il_2_implement` |

### Comment Prefixes
- `## 📋 Implementation Plan` - Initial plan (human-readable)
- `## ✅ Plan Approved` - Approval confirmation with task checklist
- `## 📝 Task Log: US-XXX` - Per-task execution results
- `## 🔍 Discovery Note` - Patterns discovered during implementation
- `## 🧪 Testing Checkpoint` - Request manual testing
- `## 🔧 Debug Session` - Debug attempt for user-reported issue
- `## ✅ Debug Fix Applied` - Debug fix verified working
- `## 🚫 Debug Blocked` - Debug failed 3x, needs human
- `## 📊 Final Report` - Summary before PR creation

## Task Design Requirements

Each task must be:
- **Completable in one context window** (if description > 3 sentences, split it)
- **Self-contained** (description includes all needed context)
- **Automatically verifiable** (acceptance criteria = shell commands that prove success)

Good acceptance criteria:
- `npm run typecheck passes`
- `curl -X POST /api/users returns 201`
- `File exists: src/lib/jwt.ts`

Bad acceptance criteria:
- "Code is clean" (subjective)
- "Works correctly" (not verifiable)
- "Handles errors properly" (vague)

## Branch and Commit Strategy

- Branch: `ai/issue-{number}-{slug}` (one per issue)
- Task commit: `feat(US-003): description (#42)`
- State commit: `chore: update prd.json - US-003 passed (#42)`

## Error Recovery

If a session ends mid-implementation:
```bash
cat prd.json | jq '.userStories[] | {id, passes, attempts}'  # Check state
git log --oneline -5                                          # Review commits
/il_2_implement                                               # Resume
```

If a task fails 3 times:
- Issue labeled `AI: Blocked`
- Task log explains failure
- Human adds guidance in issue comments
- Run `/il_2_implement` to retry with new context

## This is a Meta-Project

When working in this repository, remember:
- This code is INSTALLED into other projects, not run directly here
- Changes should consider the end-user experience in target projects
- Commands assume they're running in a user's project with existing code
- Test changes by copying to a sample project and running the workflow

<!-- issues-loop:auto-patterns:start -->
- [.agents/skills/issues-loop/scripts] The .agents copy mirrors .claude copy structure; fixes should be applied identically to both (source: #19 US-002)
<!-- issues-loop:auto-patterns:end -->

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
│       ├── implement-loop.sh      # Background task loop orchestrator
│       └── implement-loop-lib.sh  # Sourceable helper functions (uid, events, compaction, wisps)
├── templates/
│   └── formulas/
│       ├── bugfix.md          # Bugfix formula (reproduce → fix → verify)
│       ├── feature.md         # Feature formula (schema → logic → UI → integration)
│       └── refactor.md        # Refactor formula (analyze → extract → migrate → verify)
├── .issueloop.config.json     # Runtime config (comment prefixes, settings)
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
| `## 📝 Task Log: US-XXX` | Task completion log (pass or fail) with JSON event block |
| `## 🔍 Discovery Note` | Patterns/learnings for future iterations |
| `## 🧾 Compacted Summary` | Periodic summary of recent task logs (every 5) |
| `## 🪶 Wisp` | Ephemeral context hint with expiration |
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
  "formula": "feature",
  "compaction": {
    "taskLogCountSinceLastSummary": 0,
    "summaryEveryNTaskLogs": 5
  },
  "userStories": [
    {
      "id": "US-001",
      "uid": "tsk_a1b2c3d4e5f6",
      "title": "Create user model",
      "discoveredFrom": null,
      "discoverySource": null,
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

## 🧬 Formulas (Issue Type Detection)

During planning (`/il_1_plan`), the issue type is auto-detected and stored as a **formula** in `prd.json.formula`. The formula constrains task decomposition to a proven topology for that issue type.

| Formula | Topology | Keyword Triggers |
|---------|----------|-----------------|
| **bugfix** | reproduce → fix → verify | bug, fix, broken, regression |
| **feature** | schema → logic → UI → integration | add, create, implement, new |
| **refactor** | analyze → extract → migrate → verify | refactor, restructure, extract, migrate |

**Detection priority:** Issue labels (highest) → keyword scan of title/body → default to `feature`.

Formula templates are stored in `templates/formulas/` and define default task phases, acceptance criteria patterns, and verify command patterns for each type.

## 📊 Structured Task Log Events (JSON Event Block)

Every `## 📝 Task Log` comment includes a machine-readable `### Event JSON` section containing a fenced JSON code block:

````markdown
### Event JSON
```json
{"v":1,"type":"task_log","issue":42,"taskId":"US-003","taskUid":"tsk_a1b2c3d4e5f6","status":"pass","attempt":2,"commit":"abc1234","verify":{"passed":["npm run typecheck"],"failed":[]},"discovered":[],"ts":"2026-02-10T18:30:00Z"}
```
````

The loop parser uses a **two-phase extraction strategy**:
1. **JSON event extraction (preferred):** Parse the fenced `json` block under `### Event JSON` heading only. All other JSON in the comment is ignored.
2. **Legacy markdown fallback:** If no Event JSON block is found, fall back to parsing the human-readable markdown sections (`**Status:**`, `**Attempt:**`, etc.).

This ensures backward compatibility with task logs written before the JSON event format was introduced.

## 🔍 Discovered-Task Auto-Enqueue

During implementation, tasks may discover additional work needed. These **discovered tasks** are automatically enqueued into `prd.json` within the same issue loop — no human intervention required.

### How It Works
1. A task reports discovered work in its JSON event `discovered` array
2. The loop deduplicates using a **fingerprint hash** of `title + description + acceptanceCriteria + parent uid`
3. New tasks are appended to `prd.json.userStories` with:
   - Generated `uid` (deterministic hash)
   - `discoveredFrom` set to the parent task's `uid`
   - `priority` = parent priority + 1
   - `dependsOn` = [parent task id]
4. `prd.json` is committed before the next task selection

Duplicate discovered tasks (matching fingerprint) are silently skipped and noted in the task log.

## 🧾 Compaction Summaries

As task logs accumulate on an issue, the thread can grow long. **Compaction** automatically posts periodic summaries to keep context lean.

### Cadence
- A `## 🧾 Compacted Summary` is posted every **5 task logs** (configurable via `summaryEveryNTaskLogs` in `.issueloop.config.json`)
- The counter is tracked in `prd.json.compaction.taskLogCountSinceLastSummary`
- After posting, the counter resets to 0

### Summary Contents
- **Covered task UIDs and attempt counts** — which tasks are summarized
- **Canonical decisions and patterns** discovered so far
- **Open risks** identified during implementation
- **Supersedes pointer** — URL of the previous compaction summary (or "none" for the first)

The loop uses the latest compacted summary as primary historical context, reducing the need to re-read all individual task logs.

## 🪶 Wisps (Ephemeral Context Hints)

Wisps are **short-lived** context hints posted as `## 🪶 Wisp` comments on the issue. They carry a time-to-live and are intended for transient observations that may not warrant permanent documentation.

### Format
```json
{"v":1,"type":"wisp","id":"wsp_...","taskUid":"tsk_...","note":"...","expiresAt":"2026-02-10T20:00:00Z","promoted":false}
```

### Lifecycle Rules
1. **Creation:** Posted during task execution when transient context is worth sharing
2. **Expiration:** Each wisp has an `expiresAt` timestamp. Expired wisps are silently ignored during loop context assembly
3. **Promotion (only path to durability):**
   - **To Discovery Note:** Convert the wisp into a `## 🔍 Discovery Note` and mark `promoted: true`
   - **To New Task:** Enqueue the wisp content as a discovered task and mark `promoted: true`
4. **Un-promoted wisps are lost on expiration** — there is no automatic archival or recovery

Default TTL is 90 minutes (configurable via `wispDefaultTtlMinutes` in `.issueloop.config.json`).

## 🔎 Hybrid Review Lane (Findings-Only)

The loop runs a parallel code-review lane designed to improve quality without slowing implementation throughput.

### Lifecycle
1. A task passes and its task log is verified on GitHub.
2. The loop spawns a **read-only** review agent for that task commit.
3. Reviewer posts `## 🔎 Code Review: <scope>` with `### Review Event JSON`.
4. Orchestrator ingests review events and deduplicates findings by `reviewId:findingId`.
5. High-severity findings auto-enqueue follow-up tasks in `prd.json`.

### Review Event Schema
```json
{"v":1,"type":"review_log","issue":42,"reviewId":"rev_20260216_us003","scope":"task","parentTaskId":"US-003","parentTaskUid":"tsk_a1b2c3d4e5f6","reviewedCommit":"abc1234","status":"completed","findings":[{"id":"RF-001","severity":"high","confidence":0.91,"category":"production_readiness","title":"Missing timeout on external call","description":"External call has no timeout and can stall request workers under partial outage.","evidence":[{"file":"src/api/client.ts","line":42}],"suggestedTask":{"title":"Add bounded timeout + retry guard to API client","description":"Add timeout and bounded retry behavior.","acceptanceCriteria":["Client enforces timeout <= 3s","Timeout path returns handled error"],"verifyCommands":["npm run test -- api-client","npm run typecheck"],"dependsOn":[]}}],"ts":"2026-02-16T20:10:00Z"}
```

### Severity Routing
- **Auto-enqueue:** `critical`, `high` findings with confidence ≥ configured threshold.
- **Approval path:** `medium`, `low` findings remain open until approved.
- Review-generated tasks are tagged with `discoverySource: "code_review"`.

### Final Review Gate
- When all implementation tasks pass, the loop runs a consolidated `FINAL` review over `main..HEAD`.
- Testing checkpoint is blocked while open blocking findings remain.
- If blocking findings exist, the loop labels issue `AI: Review` and continues with generated follow-up tasks.

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

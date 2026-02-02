# Planning Guide (Ralph Pattern)

This document provides guidance on creating implementation plans that follow the Ralph pattern. It is used as reference during the planning phase triggered by `/issue N`.

---

## Required Plan Format for Plan Mode

When using Claude Code's native plan mode (via `EnterPlanMode`), the plan **must** follow this format to enable automatic transformation to `prd.json`.

### Plan File Structure

```markdown
# Implementation Plan: Issue #N - {title}

## Overview
{2-3 sentence approach summary explaining the implementation strategy}

## Tasks

### US-001: {Task title}
**Priority:** 1
**Files:** `path/to/file.ts`, `path/to/other.ts`
**Depends On:** None

**Description:**
{What to implement in 2-3 sentences. Include specific details about
what to create/modify and any important context.}

**Acceptance Criteria:**
- [ ] {Verifiable criterion 1 - must be testable}
- [ ] {Verifiable criterion 2 - must be testable}

**Verify Commands:**
```bash
command1
command2
```

---

### US-002: {Next task title}
**Priority:** 2
**Files:** `path/to/file.ts`
**Depends On:** US-001

**Description:**
{Task description}

**Acceptance Criteria:**
- [ ] {Criterion}

**Verify Commands:**
```bash
command
```
```

### Required Fields (per task)

| Field | Required | Description |
|-------|----------|-------------|
| `### US-XXX: {title}` | Yes | Task ID and title |
| `**Priority:**` | Yes | Execution order (1 = first) |
| `**Files:**` | Yes | Files to create/modify |
| `**Depends On:**` | Yes | Task IDs that must pass first, or "None" |
| `**Description:**` | Yes | What to implement (2-3 sentences) |
| `**Acceptance Criteria:**` | Yes | Testable checkboxes |
| `**Verify Commands:**` | Yes | Bash commands to prove success |

### Field Mapping (Plan → prd.json)

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

---

## The Ralph Pattern

### Core Principle: Fresh Context Per Task
Each task execution starts with a **clean context**. The only memory between tasks:
- Git history (commits from previous tasks)
- GitHub issue comments (task logs, learnings)
- `prd.json` (task status: passes true/false)

This prevents context pollution and forces self-contained task definitions.

### Task Size Rule
**If you can't describe the change in 2-3 sentences, it's too big.**

Right-sized tasks:
- Add a database column and migration
- Create a single API endpoint
- Add one UI component to existing page
- Update a function with new logic

Too big (must split):
- "Build the dashboard" → Split into schema, API, UI components
- "Add authentication" → Split into schema, JWT utils, middleware, routes, UI

---

## Planning Methodology

### Phase 1: Context Analysis
Before creating the plan, analyze:

1. **Issue Requirements**
   - Parse explicit requirements from issue body
   - Identify acceptance criteria
   - Note referenced files/systems

2. **Codebase Discovery**
   - Examine relevant existing files
   - Understand patterns and conventions
   - Identify integration points

3. **Complexity Assessment**
   - Break large features into phases
   - Each task = one context window of work
   - Flag tasks needing investigation first

### Phase 2: Task Decomposition

For each task, define:

```yaml
id: "US-001"           # Unique identifier
priority: 1            # Execution priority (1 = highest, determines order)
title: "Short title"    # Action-oriented
description: |
  What to implement, including:
  - Specific files to create/modify
  - Integration points
  - Edge cases to handle
acceptanceCriteria:     # THE TEST - must be verifiable!
  - "Migration creates users table with columns: id, email, password_hash"
  - "npm run typecheck passes"
  - "npm run test passes"
  - "POST /api/users returns 201 with valid payload"
verifyCommands:         # Actual commands to run
  - "npm run typecheck"
  - "npm run test"
  - "curl -X POST localhost:3000/api/users -d '{...}'"
dependsOn: ["US-000"]   # Previous task IDs
passes: false           # Will be set true when criteria met
```

**Priority Rules:**
- Tasks with lower priority numbers execute first
- Priority 1 tasks are critical path / foundation work
- Priority 2+ tasks can often be parallelized
- Dependencies always override priority (a task won't run until its dependencies pass)

### Phase 3: Generate Outputs

#### 3a. GitHub Comment (Human-Readable)
Post to issue as `## 📋 Implementation Plan`:

```markdown
## 📋 Implementation Plan

**Issue:** #42 - Implement user authentication
**Generated:** 2024-01-15
**Status:** Draft | Approved
**Complexity:** Medium (6 tasks across 2 phases)

---

### Overview
[2-3 sentence implementation approach]

---

### Phase 1: Foundation

#### Task US-001: Create user database schema
**Files:** `prisma/schema.prisma`, `prisma/migrations/`
**Depends on:** None

**Steps:**
1. Add User model to Prisma schema
2. Generate and run migration
3. Verify with `npx prisma studio`

**Acceptance Criteria (The Test):**
- [ ] Migration creates users table with: id, email, password_hash, created_at
- [ ] `npm run db:migrate` completes without errors
- [ ] `npx prisma studio` shows empty users table

---

#### Task US-002: Implement JWT utilities
**Files:** `src/lib/jwt.ts`, `src/types/auth.ts`
**Depends on:** US-001

**Steps:**
1. Create JWT sign/verify functions
2. Add TypeScript types for token payload
3. Add unit tests

**Acceptance Criteria (The Test):**
- [ ] `signToken()` returns valid JWT string
- [ ] `verifyToken()` decodes valid tokens
- [ ] `verifyToken()` throws on invalid/expired tokens
- [ ] `npm run test -- jwt` passes

---

[Continue for all tasks...]

---

### Verification Commands
```bash
npm run typecheck
npm run test
npm run build
```

---

*React with 👍 to approve this plan*
```

#### 3b. prd.json (Machine-Readable)
Create in repo root:

```json
{
  "project": "user-authentication",
  "issueNumber": 42,
  "branchName": "ai/issue-42-user-auth",
  "description": "Implement user authentication with JWT",
  "generatedAt": "2024-01-15T10:30:00Z",
  "status": "approved",
  "userStories": [
    {
      "id": "US-001",
      "phase": 1,
      "priority": 1,
      "title": "Create user database schema",
      "description": "Add User model to Prisma schema with id, email, password_hash, created_at fields. Generate and run migration.",
      "files": ["prisma/schema.prisma"],
      "dependsOn": [],
      "acceptanceCriteria": [
        "Migration creates users table with columns: id, email, password_hash, created_at",
        "npm run db:migrate completes without errors",
        "npx prisma studio shows users table"
      ],
      "verifyCommands": [
        "npm run db:migrate",
        "npm run typecheck"
      ],
      "passes": false,
      "attempts": 0,
      "lastAttempt": null
    },
    {
      "id": "US-002",
      "phase": 1,
      "priority": 2,
      "title": "Implement JWT utilities",
      "description": "Create JWT sign/verify functions in src/lib/jwt.ts with proper TypeScript types.",
      "files": ["src/lib/jwt.ts", "src/types/auth.ts"],
      "dependsOn": ["US-001"],
      "acceptanceCriteria": [
        "signToken() returns valid JWT string",
        "verifyToken() decodes valid tokens correctly",
        "verifyToken() throws on invalid/expired tokens",
        "npm run test -- jwt passes"
      ],
      "verifyCommands": [
        "npm run typecheck",
        "npm run test -- jwt"
      ],
      "passes": false,
      "attempts": 0,
      "lastAttempt": null
    }
  ],
  "globalVerifyCommands": [
    "npm run typecheck",
    "npm run test",
    "npm run build"
  ]
}
```

---

## Plan Approval Workflow

### When `/plan approve` is invoked:

1. **Generate prd.json**
   ```bash
   # Create prd.json in repo root
   echo '$PRD_JSON' > prd.json
   git add prd.json
   git commit -m "chore: add prd.json for issue #$ISSUE_NUMBER"
   git push
   ```

2. **Post approval comment**
   ```markdown
   ## ✅ Plan Approved
   
   **prd.json generated** with 6 testable tasks.
   
   Implementation ready. Run `/implement` to begin the loop.
   
   Task Status:
   - [ ] US-001: Create user database schema
   - [ ] US-002: Implement JWT utilities
   - [ ] US-003: Create auth middleware
   - [ ] US-004: Add registration endpoint
   - [ ] US-005: Add login endpoint
   - [ ] US-006: Add protected route example
   ```

3. **Update labels**
   ```bash
   gh issue edit $ISSUE_NUMBER --remove-label "AI: Planning" --add-label "AI: Approved"
   ```

---

## Status Check

When `/plan status` is invoked:

```bash
# Read prd.json and show status
cat prd.json | jq '.userStories[] | {id, title, passes, attempts}'
```

Output:
```
📊 Task Status for Issue #42

| Task | Title | Status | Attempts |
|------|-------|--------|----------|
| US-001 | Create user database schema | ✅ Pass | 1 |
| US-002 | Implement JWT utilities | ✅ Pass | 2 |
| US-003 | Create auth middleware | ⏳ In Progress | 1 |
| US-004 | Add registration endpoint | ⬜ Pending | 0 |
| US-005 | Add login endpoint | ⬜ Pending | 0 |
| US-006 | Add protected route example | ⬜ Pending | 0 |

Progress: 2/6 tasks passing (33%)
```

---

## Writing Good Acceptance Criteria

### The Test: Can This Be Verified Automatically?

**Good criteria (verifiable):**
- "npm run typecheck passes"
- "npm run test passes"
- "POST /api/users with valid data returns 201"
- "File src/lib/jwt.ts exists and exports signToken"
- "Database has users table with email column"

**Bad criteria (subjective):**
- "Code is clean" ❌
- "Works correctly" ❌
- "Properly handles errors" ❌ (what does "properly" mean?)

### Include Verify Commands
Every task should have commands that can prove success:
```json
"verifyCommands": [
  "npm run typecheck",
  "npm run test -- --grep 'jwt'",
  "curl -s -o /dev/null -w '%{http_code}' localhost:3000/api/health"
]
```

---

## Error Handling

| Error | Response |
|-------|----------|
| No issue loaded | "Run `/issue {number}` first" |
| Plan already exists | Show existing, offer to edit |
| Task too large | Suggest splitting with specific guidance |
| No verify commands possible | Flag for manual verification |

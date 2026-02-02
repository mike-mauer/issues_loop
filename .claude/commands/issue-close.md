# /issue close - Generate Final Report and Create PR

## Description
Generates a comprehensive final report from `prd.json` and issue comments, summarizing all implementation work. Creates a Pull Request linking to the issue.

**Important:** This command requires the implementation to have been verified through the testing checkpoint. Use `--force` to bypass this requirement.

## Usage
```
/issue close              # Generate report and create PR (requires verified status)
/issue close --force      # Bypass verification requirement
/issue close preview      # Preview report without posting
/issue close close        # Generate report, create PR, close issue
```

## Prerequisites
- All tasks in prd.json have `passes: true`
- `debugState.status` is `verified` (or use `--force`)
- On implementation branch with all changes pushed
- Issue loaded in context

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

# 5. Check jq is installed
which jq || { echo "❌ jq not found. Install with: brew install jq"; exit 1; }

# 6. Check prd.json exists
[ -f prd.json ] || { echo "❌ prd.json not found. Cannot generate report without task state."; exit 1; }

# 7. Check for uncommitted changes
[ -z "$(git status --porcelain)" ] || { echo "⚠️ Uncommitted changes found. Commit or stash before closing."; }
```

If any prerequisite fails, stop and inform the user how to fix it.

---

## Verification Gate

### Step 0: Check Testing Status

```bash
# Check debugState status
DEBUG_STATUS=$(cat prd.json | jq -r '.debugState.status // "none"')

if [ "$DEBUG_STATUS" != "verified" ] && [ "$FORCE" != "true" ]; then
  echo "⚠️  Testing not complete."
  echo ""
  echo "The implementation must pass the testing checkpoint before closing."
  echo "Current status: $DEBUG_STATUS"
  echo ""
  echo "Options:"
  echo "  1. Run /implement to go through the testing checkpoint"
  echo "  2. Use /issue close --force to bypass (not recommended)"
  exit 1
fi
```

---

## Report Generation

### Step 1: Verify Completion

```bash
# Check all tasks pass
FAILING=$(cat prd.json | jq '[.userStories[] | select(.passes == false)] | length')

if [ "$FAILING" -gt 0 ]; then
  echo "⚠️ $FAILING tasks still failing. Complete implementation first."
  exit 1
fi
```

### Step 2: Gather Data

#### From prd.json:
```bash
PROJECT=$(cat prd.json | jq -r '.project')
ISSUE=$(cat prd.json | jq -r '.issueNumber')
BRANCH=$(cat prd.json | jq -r '.branchName')
TASKS=$(cat prd.json | jq '.userStories')
TOTAL_TASKS=$(cat prd.json | jq '.userStories | length')
TOTAL_ATTEMPTS=$(cat prd.json | jq '[.userStories[].attempts] | add')
DEBUG_ATTEMPTS=$(cat prd.json | jq '.debugState.debugAttempts // 0')
```

#### From Git:
```bash
# Commits on this branch
COMMITS=$(git log main..HEAD --oneline)
COMMIT_COUNT=$(git log main..HEAD --oneline | wc -l)

# Files changed
FILES_CHANGED=$(git diff main --stat)
INSERTIONS=$(git diff main --shortstat | grep -o '[0-9]* insertion' | grep -o '[0-9]*')
DELETIONS=$(git diff main --shortstat | grep -o '[0-9]* deletion' | grep -o '[0-9]*')
```

#### From Issue Comments:
```bash
# Extract learnings from Discovery Notes
LEARNINGS=$(gh issue view $ISSUE --json comments --jq \
  '.comments[].body | select(contains("## 🔍 Discovery Note"))')

# Extract failure analysis from task logs
FAILURES=$(gh issue view $ISSUE --json comments --jq \
  '.comments[].body | select(contains("**Status:** ❌"))')

# Extract debug session info
DEBUG_SESSIONS=$(gh issue view $ISSUE --json comments --jq \
  '.comments[].body | select(contains("## 🔧 Debug Session"))')
```

### Step 3: Generate Report

```markdown
## 📊 Final Implementation Report

**Issue:** #42 - Implement user authentication
**Branch:** ai/issue-42-user-auth
**Completed:** 2024-01-15 16:45 UTC
**Testing Status:** ✅ Verified by user

---

### Executive Summary

Implemented user authentication with JWT tokens across 6 tasks. All acceptance
criteria verified and passing. Total implementation required 8 attempts across
6 tasks (2 tasks required retry). User testing completed with 1 debug fix applied.

---

### Implementation Statistics

| Metric | Value |
|--------|-------|
| Tasks Completed | 6/6 |
| Total Attempts | 8 |
| First-Pass Success | 4/6 (67%) |
| Debug Fixes | 1 |
| Commits | 12 |
| Files Changed | 15 |
| Lines Added | +847 |
| Lines Removed | -23 |

---

### Task Summary

| ID | Task | Attempts | Status |
|----|------|----------|--------|
| US-001 | Create user database schema | 1 | ✅ |
| US-002 | Implement JWT utilities | 1 | ✅ |
| US-003 | Create auth middleware | 2 | ✅ |
| US-004 | Add registration endpoint | 1 | ✅ |
| US-005 | Add login endpoint | 2 | ✅ |
| US-006 | Add protected route example | 1 | ✅ |

---

### Changes by Category

#### New Files (8)
- `src/lib/jwt.ts` - JWT sign/verify utilities
- `src/middleware/auth.ts` - Authentication middleware
- `src/routes/auth.ts` - Auth routes (register, login)
- `src/models/user.ts` - User model and types
- `prisma/migrations/001_users/` - User table migration
- `src/types/auth.ts` - Auth-related TypeScript types
- `src/types/express.d.ts` - Express Request extension
- `tests/auth.test.ts` - Auth endpoint tests

#### Modified Files (7)
- `src/app.ts` - Added auth routes and middleware
- `src/routes/index.ts` - Export auth routes
- `package.json` - Added jsonwebtoken, bcrypt dependencies
- `tsconfig.json` - Added types path
- `.env.example` - Added JWT_SECRET
- `README.md` - Added auth documentation
- `prisma/schema.prisma` - Added User model

---

### Verification Results

All global verify commands passing:
```
✓ npm run typecheck (0 errors, 0 warnings)
✓ npm run test (24 tests passing, 0 failing)
✓ npm run build (compiled successfully)
```

---

### Key Decisions Made

1. **JWT Storage**
   - Decision: Store in httpOnly cookie (not localStorage)
   - Rationale: Better XSS protection

2. **Password Hashing**
   - Decision: bcrypt with cost factor 12
   - Rationale: Balance of security and performance

3. **Token Expiry**
   - Decision: 15 min access token, 7 day refresh token
   - Rationale: Standard security practice

---

### Learnings Captured

From Discovery Notes during implementation:

1. **JWT Error Handling Pattern**
   - `TokenExpiredError` → 401 "Token expired"
   - `JsonWebTokenError` → 401 "Invalid token"
   - Reference: `src/middleware/auth.ts:15-30`

2. **Express Type Extension**
   - Requires `declare global` in .d.ts file
   - Must be included in tsconfig paths
   - Reference: `src/types/express.d.ts`

3. **Test Database Setup**
   - Use separate test database URL
   - Run migrations before test suite
   - Reference: `jest.setup.ts`

---

### Challenges Overcome

**US-003 (attempt 2):** Initial implementation threw 500 for expired tokens.
- Root cause: Didn't catch `TokenExpiredError`
- Fix: Added specific error type handling

**US-005 (attempt 2):** Login returned 500 for invalid password.
- Root cause: bcrypt.compare returns false, not throws
- Fix: Check return value instead of try-catch

---

### Debug Sessions

**Session 1:** User reported login button not responding
- Root cause: Missing onClick handler binding
- Fix: Added arrow function binding in component
- Verified: User confirmed fix works

---

### Test Coverage

```
Auth Middleware:  100% (3/3 tests)
JWT Utilities:    100% (4/4 tests)
Auth Routes:      100% (8/8 tests)
User Model:       100% (5/5 tests)
Integration:      100% (4/4 tests)
```

---

### Follow-up Recommendations

- [ ] Add rate limiting to auth endpoints
- [ ] Implement password reset flow
- [ ] Add OAuth providers (Google, GitHub)
- [ ] Set up token rotation on refresh

---

### Commit History

```
abc1234 feat(US-006): add protected route example (#42)
def5678 feat(US-005): add login endpoint (#42)
ghi9012 feat(US-004): add registration endpoint (#42)
jkl3456 feat(US-003): create auth middleware (#42)
mno7890 feat(US-002): implement JWT utilities (#42)
pqr1234 feat(US-001): create user database schema (#42)
```

---

**Ready for Review** - All 6 tasks passing, user testing verified.
```

### Step 4: Post to Issue

```bash
gh issue comment $ISSUE_NUMBER --body "$REPORT"
```

### Step 5: Create Pull Request

```bash
gh pr create \
  --base main \
  --head "$BRANCH" \
  --title "feat: implement user authentication (#$ISSUE_NUMBER)" \
  --body "## Summary
Implements user authentication with JWT tokens as specified in Issue #$ISSUE_NUMBER.

## Changes
- User registration and login endpoints
- JWT token generation and validation
- Authentication middleware
- Protected route example

## Task Completion
All 6 tasks passing. See [Final Report](#issuecomment-xxx) for details.

## Testing
- [x] All acceptance criteria verified
- [x] Type checking passes
- [x] All tests passing
- [x] Build successful
- [x] User testing completed ✅

## Related
Closes #$ISSUE_NUMBER

---
*Generated by Claude Code from prd.json*"
```

### Step 6: Update Labels

```bash
gh issue edit $ISSUE_NUMBER \
  --remove-label "AI: Testing" \
  --remove-label "AI: In Progress" \
  --add-label "AI: Review"
```

### Step 7: Link PR to Issue

```bash
PR_NUMBER=$(gh pr view --json number -q .number)
gh issue comment $ISSUE_NUMBER --body "Pull Request created: #$PR_NUMBER"
```

---

## Close Flow

When `/issue close close` is invoked (after PR merge):

### Step 8: Archive Implementation Record

Create a comprehensive archive of the implementation for future reference:

```bash
# Create archive directory with date and feature slug
PROJECT_SLUG=$(cat prd.json | jq -r '.project // "unknown"' | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
ARCHIVE_DIR="archive/$(date +%Y-%m-%d)-issue-$ISSUE_NUMBER-$PROJECT_SLUG"
mkdir -p "$ARCHIVE_DIR"

# Archive prd.json
cp prd.json "$ARCHIVE_DIR/prd.json"

# Export GitHub comments to file for offline reference
gh issue view $ISSUE_NUMBER --json comments --jq '.comments[].body' > "$ARCHIVE_DIR/issue-comments.md"

# Create summary file
TOTAL_TASKS=$(cat prd.json | jq '.userStories | length')
TOTAL_ATTEMPTS=$(cat prd.json | jq '[.userStories[].attempts] | add')
cat > "$ARCHIVE_DIR/SUMMARY.md" << EOF
# Issue #$ISSUE_NUMBER: $PROJECT_SLUG

**Completed:** $(date +%Y-%m-%d)
**Branch:** $BRANCH
**Tasks:** $TOTAL_TASKS
**Total Attempts:** $TOTAL_ATTEMPTS

## Task Summary
$(cat prd.json | jq -r '.userStories[] | "- [\(.id)] \(.title) - \(.attempts) attempt(s)"')

## Files Modified
$(git diff main --name-only | head -50)
EOF

# Commit archive
git add "$ARCHIVE_DIR"
git commit -m "chore: archive issue #$ISSUE_NUMBER implementation"

# Clean up prd.json from repo root
rm prd.json
git add -A
git commit -m "chore: remove prd.json after archiving (#$ISSUE_NUMBER)"
git push
```

### Step 9: Close Issue

```bash
# Close issue
gh issue close $ISSUE_NUMBER --comment "✅ Completed via PR #$PR_NUMBER

All $TOTAL_TASKS tasks implemented and verified. See Final Report above for details.

Implementation archived to: $ARCHIVE_DIR"

# Update labels
gh issue edit $ISSUE_NUMBER \
  --remove-label "AI: Review" \
  --add-label "AI: Complete"
```

---

## Preview Mode

When `/issue close preview`:
- Generate full report
- Display in terminal
- Do NOT post to GitHub
- Do NOT create PR

```
📋 Report Preview
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[Full report content]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
This is a preview. Run /issue close to post and create PR.
```

---

## Force Mode

When `/issue close --force`:
- Skip the verification gate check
- Proceed directly to report generation
- Useful when testing was done manually or outside the workflow

```
⚠️  Force mode: Bypassing testing verification
Proceeding with report generation...
```

---

## Error Handling

| Error | Response |
|-------|----------|
| Testing not verified | "Testing not complete. Run /implement or use --force" |
| Tasks still failing | "Complete implementation first. X tasks failing." |
| Not on feature branch | "Checkout the implementation branch first." |
| Uncommitted changes | "Commit or stash changes first." |
| PR already exists | Show existing PR, offer to update description |

---

## Output

```
✅ Final Report Generated

Report: https://github.com/owner/repo/issues/42#issuecomment-xxx
PR: https://github.com/owner/repo/pull/57

Issue #42 ready for human review.

Next steps:
1. Review PR in GitHub
2. Request changes or approve
3. Merge when ready
4. Run /issue close close to finalize
```

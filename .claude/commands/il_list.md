# /il_list - List Open GitHub Issues

## Description
Fetches and displays all open GitHub issues from the current repository, allowing you to select one for implementation. This is a utility command to discover available issues.

## Usage
```
/il_list
/il_list --label AI
/il_list --assignee @me
```

## Workflow

### Step 1: Detect Repository
First, determine the GitHub repository from the current git remote:

```bash
git remote get-url origin
```

Parse the owner and repo name from the URL.

### Step 2: Fetch Open Issues
Use the GitHub CLI to fetch all open issues:

```bash
gh issue list --state open --limit 50 --json number,title,labels,assignees,createdAt,updatedAt
```

### Step 3: Display Issues
Present issues in a numbered list format:

```
## Open Issues

| # | Issue | Labels | Created | Updated |
|---|-------|--------|---------|---------|
| 1 | #42 - Implement user auth | AI, backend | 2 days ago | 1 hour ago |
| 2 | #38 - Fix dashboard layout | AI, frontend | 5 days ago | 3 days ago |
| 3 | #35 - Add export feature | enhancement | 1 week ago | 1 week ago |

Enter issue number to load (e.g., "1" for #42), or "q" to cancel:
```

### Step 4: Load Selected Issue
When user selects an issue, automatically invoke `/il_1_plan {number}` to load it.

## Output Format
- Show issue number, title, labels, and relative timestamps
- Highlight issues with "AI" label
- Show assignee if present
- Sort by most recently updated

## Error Handling
- If not in a git repository: "Error: Not in a git repository. Navigate to your project first."
- If gh CLI not installed: "Error: GitHub CLI (gh) not found. Install it with: brew install gh"
- If not authenticated: "Error: Not authenticated with GitHub. Run: gh auth login"

## After Selection
Once an issue is selected, the `/il_1_plan` command will:
1. Load the full issue details
2. Check for existing implementation plan in comments
3. Display plan status and next steps

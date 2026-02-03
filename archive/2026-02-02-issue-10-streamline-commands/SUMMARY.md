# Issue #10: streamline-commands

**Completed:** 2026-02-02
**Branch:** ai/issue-10-streamline-commands
**PR:** #11
**Tasks:** 5
**Total Attempts:** 5

## Summary

Streamlined the command system by renaming all commands with the `il_` prefix and adding sequential numbering for the core workflow (1, 2, 3).

## New Command Names

| Old | New |
|-----|-----|
| `/issue N` | `/il_1_plan N` |
| `/implement` | `/il_2_implement` |
| `/issue close` | `/il_3_close` |
| `/issues` | `/il_list` |
| `/issue setup` | `/il_setup` |
| `/issue validate` | `/il_validate` |

## Task Summary
- [US-001] Rename command files with il_ prefix - 1 attempt(s)
- [US-002] Update command headers and descriptions - 1 attempt(s)
- [US-003] Consolidate close close into il_3_close - 1 attempt(s)
- [US-004] Update all documentation references - 1 attempt(s)
- [US-005] Update cross-references between commands - 1 attempt(s)

## Key Improvements

- Sequential numbering for core workflow (1, 2, 3)
- Unified `il_` prefix for easy discovery
- Consolidated close command with auto PR merge detection

## Files Modified
- .claude/commands/il_1_plan.md (renamed from issue.md)
- .claude/commands/il_2_implement.md (renamed from implement.md)
- .claude/commands/il_3_close.md (renamed from issue-close.md)
- .claude/commands/il_list.md (renamed from issues.md)
- .claude/commands/il_setup.md (renamed from issue-setup.md)
- .claude/commands/il_validate.md (renamed from issue-validate.md)
- CLAUDE.md
- .claude/CLAUDE.md
- .claude/rules/github-issue-workflow.md
- .claude/rules/planning-guide.md

# CLAUDE.md Template

> **This is a TEMPLATE.** Copy the relevant sections into your project's existing CLAUDE.md,
> or use this as a starting point if you don't have one yet.

---

# [Your Project Name]

## Project Overview
<!-- Add your project-specific context here -->

## Tech Stack
<!-- List your technologies, frameworks, etc. -->

## Code Standards
<!-- Your project's coding conventions -->

---

## GitHub Issue Workflow

This project uses GitHub Issues for AI-assisted development. When working on issues:

1. **Load the workflow rules**: Read `.claude/rules/github-issue-workflow.md`
2. **Use the commands**: `/il_list`, `/il_1_plan N`, `/il_2_implement`, `/il_3_close`
3. **The `/il_1_plan N` command handles**: scope → plan → approve (guided flow)
4. **Follow the memory system**: All task logs go to GitHub issue comments
5. **Testing checkpoint**: User verifies before closing (debug flow if issues)
6. **Branch per issue**: `ai/issue-{number}-{slug}`
7. **Commit per task**: `task(X.Y): description (#issue)`

See `.claude/rules/github-issue-workflow.md` for complete workflow documentation.

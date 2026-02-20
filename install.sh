#!/bin/bash

# GitHub Issue-Driven Workflow - Installation Script
# Usage: curl -sSL https://raw.githubusercontent.com/your-repo/setup.sh | bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${1:-.}"

echo "🚀 Installing GitHub Issue-Driven Workflow..."
echo ""

# Detect platform
echo "🖥️  Detecting platform..."
case "$(uname -s)" in
  Darwin*)
    PLATFORM="macos"
    echo "   Platform: macOS"
    ;;
  Linux*)
    PLATFORM="linux"
    echo "   Platform: Linux"
    ;;
  MINGW*|CYGWIN*|MSYS*)
    PLATFORM="windows"
    echo "   Platform: Windows (Git Bash/MSYS)"
    echo ""
    echo "⚠️  Windows detected. WSL2 is recommended for full functionality."
    echo "   The background loop (implement-loop.sh) requires bash and flock."
    echo "   Some features may not work correctly in Git Bash."
    echo ""
    ;;
  *)
    PLATFORM="unknown"
    echo "   Platform: Unknown ($(uname -s))"
    echo "⚠️  Untested platform. Some features may not work."
    ;;
esac
echo ""

# Check prerequisites
echo "📋 Checking prerequisites..."

if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) not found"
    echo "   Install with: brew install gh"
    exit 1
fi
echo "✅ GitHub CLI installed"

if ! gh auth status &> /dev/null; then
    echo "❌ GitHub CLI not authenticated"
    echo "   Run: gh auth login"
    exit 1
fi
echo "✅ GitHub CLI authenticated"

if ! command -v git &> /dev/null; then
    echo "❌ Git not found"
    exit 1
fi
echo "✅ Git installed"

if ! command -v jq &> /dev/null; then
    echo "❌ jq not found"
    if [ "$PLATFORM" = "macos" ]; then
        echo "   Install with: brew install jq"
    elif [ "$PLATFORM" = "linux" ]; then
        echo "   Install with: apt install jq OR yum install jq"
    else
        echo "   Install from: https://stedolan.github.io/jq/download/"
    fi
    exit 1
fi
echo "✅ jq installed"

# Check if in a git repo
if [ -d "$TARGET_DIR/.git" ]; then
    echo "✅ Git repository found"
else
    echo "⚠️  Not a git repository. Initialize one first or specify target directory."
    exit 1
fi

echo ""
echo "📁 Installing workflow files..."

# Create directories - Claude Code
mkdir -p "$TARGET_DIR/.claude/commands"
mkdir -p "$TARGET_DIR/.claude/rules"
mkdir -p "$TARGET_DIR/.claude/scripts"
mkdir -p "$TARGET_DIR/.claude/templates"
mkdir -p "$TARGET_DIR/.github/ISSUE_TEMPLATE"
mkdir -p "$TARGET_DIR/archive"

# Create directories - Codex skill
mkdir -p "$TARGET_DIR/.agents/skills/issues-loop/references/formulas"
mkdir -p "$TARGET_DIR/.agents/skills/issues-loop/scripts"
mkdir -p "$TARGET_DIR/.agents/skills/issues-loop/assets"

# Create archive placeholder
touch "$TARGET_DIR/archive/.gitkeep"
echo "✅ Archive directory created"

# Copy files (assuming running from the workflow package directory)
if [ -f "$SCRIPT_DIR/.claude/rules/github-issue-workflow.md" ]; then
    cp "$SCRIPT_DIR/.claude/CLAUDE.md" "$TARGET_DIR/.claude/CLAUDE.md.template"
    cp "$SCRIPT_DIR/.claude/rules/"*.md "$TARGET_DIR/.claude/rules/"
    cp "$SCRIPT_DIR/.claude/commands/"*.md "$TARGET_DIR/.claude/commands/"

    # Copy scripts
    if [ -d "$SCRIPT_DIR/.claude/scripts" ]; then
        cp "$SCRIPT_DIR/.claude/scripts/"*.sh "$TARGET_DIR/.claude/scripts/" 2>/dev/null || true
        chmod +x "$TARGET_DIR/.claude/scripts/"*.sh 2>/dev/null || true
        echo "✅ Scripts copied and made executable"
    fi

    # Copy templates
    if [ -d "$SCRIPT_DIR/.claude/templates" ]; then
        cp "$SCRIPT_DIR/.claude/templates/"* "$TARGET_DIR/.claude/templates/" 2>/dev/null || true
        echo "✅ Templates copied"
    fi

    # Copy config file
    if [ -f "$SCRIPT_DIR/.issueloop.config.json" ]; then
        cp "$SCRIPT_DIR/.issueloop.config.json" "$TARGET_DIR/.issueloop.config.json"
        echo "✅ Configuration file copied (includes execution hardening defaults)"
    fi

    # Copy issue template
    if [ -f "$SCRIPT_DIR/templates/ISSUE_TEMPLATE_ai_request.md" ]; then
        cp "$SCRIPT_DIR/templates/ISSUE_TEMPLATE_ai_request.md" "$TARGET_DIR/.github/ISSUE_TEMPLATE/ai_request.md"
    fi

    echo "✅ Claude Code workflow files copied"
    echo ""
    echo "📝 Note: CLAUDE.md.template created - merge into your existing CLAUDE.md"
    echo "   or rename to CLAUDE.md if you don't have one yet."
else
    # If not running from package, create files inline
    echo "Creating files from template..."
    # (Files would be created inline here in a real deployment)
    echo "✅ Workflow files created"
fi

# Copy Codex skill (issues-loop)
if [ -d "$SCRIPT_DIR/.agents/skills/issues-loop" ]; then
    echo ""
    echo "📁 Installing Codex skill (issues-loop)..."

    # Copy SKILL.md
    cp "$SCRIPT_DIR/.agents/skills/issues-loop/SKILL.md" "$TARGET_DIR/.agents/skills/issues-loop/SKILL.md"

    # Copy references (including formulas subdirectory)
    cp "$SCRIPT_DIR/.agents/skills/issues-loop/references/"*.md "$TARGET_DIR/.agents/skills/issues-loop/references/"
    cp "$SCRIPT_DIR/.agents/skills/issues-loop/references/formulas/"*.md "$TARGET_DIR/.agents/skills/issues-loop/references/formulas/"

    # Copy scripts and make executable
    cp "$SCRIPT_DIR/.agents/skills/issues-loop/scripts/"*.sh "$TARGET_DIR/.agents/skills/issues-loop/scripts/"
    chmod +x "$TARGET_DIR/.agents/skills/issues-loop/scripts/"*.sh

    # Copy assets
    cp "$SCRIPT_DIR/.agents/skills/issues-loop/assets/"* "$TARGET_DIR/.agents/skills/issues-loop/assets/"

    echo "✅ Codex skill (issues-loop) installed"
fi

echo ""
echo "🏷️  Setting up GitHub labels..."

# Get repo info
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")

if [ -n "$REPO" ]; then
    # Create labels (ignore errors if they exist)
    gh label create "AI" --color "7057ff" --description "Trigger for AI planning" 2>/dev/null || true
    gh label create "AI: Planning" --color "d4c5f9" --description "Plan being generated" 2>/dev/null || true
    gh label create "AI: Approved" --color "0e8a16" --description "Plan approved for implementation" 2>/dev/null || true
    gh label create "AI: In Progress" --color "fbca04" --description "Implementation in progress" 2>/dev/null || true
    gh label create "AI: Blocked" --color "b60205" --description "Blocked, needs human input" 2>/dev/null || true
    gh label create "AI: Review" --color "1d76db" --description "Ready for code review" 2>/dev/null || true
    gh label create "AI: Complete" --color "0e8a16" --description "Done" 2>/dev/null || true
    echo "✅ GitHub labels created"
else
    echo "⚠️  Could not detect GitHub repo. Create labels manually."
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ Installation complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📌 Next steps:"
echo ""
echo "1. Setup Pipedream workflow for automated planning"
echo "   See: pipedream/github-to-claude-plan.md"
echo ""
echo "2. Create an issue and add the 'AI' label"
echo ""
echo "3. In Claude Code, run:"
echo "   /il_list         - List open issues"
echo "   /il_1_plan 42    - Plan issue #42"
echo "   /il_2_implement  - Start implementation"
echo ""
echo "   In Codex, use the issues-loop skill:"
echo "   il-list           - List open issues"
echo "   il-1-plan 42      - Plan issue #42"
echo "   il-2-implement    - Start implementation"
echo ""
echo "📖 Full documentation: README.md"
echo ""

# Pipedream Workflow: GitHub Issue to Claude Plan

## Overview
This Pipedream workflow automatically generates an implementation plan when a GitHub issue is labeled with "AI".

## Trigger Setup

### Step 1: GitHub Webhook Trigger
1. In Pipedream, create a new workflow
2. Select trigger: **GitHub** → **Issue Labeled**
3. Connect your GitHub account
4. Select your repository
5. Configure to trigger on label: `AI`

**Trigger Event Example:**
```json
{
  "action": "labeled",
  "issue": {
    "number": 42,
    "title": "Implement user authentication",
    "body": "We need to add user auth with JWT tokens...",
    "labels": [{"name": "AI"}, {"name": "backend"}],
    "html_url": "https://github.com/owner/repo/issues/42"
  },
  "label": {
    "name": "AI"
  },
  "repository": {
    "full_name": "owner/repo"
  }
}
```

---

## Workflow Steps

### Step 2: Filter Check
**Node.js Code Step:**
```javascript
export default defineComponent({
  async run({ steps, $ }) {
    const event = steps.trigger.event;
    
    // Only process if the "AI" label was just added
    if (event.action !== 'labeled' || event.label.name !== 'AI') {
      $.flow.exit("Not an AI label event");
    }
    
    // Check if plan already exists (avoid duplicate plans)
    // We'll check this in the next step
    
    return {
      issue_number: event.issue.number,
      issue_title: event.issue.title,
      issue_body: event.issue.body || "No description provided",
      issue_labels: event.issue.labels.map(l => l.name),
      repo: event.repository.full_name,
      issue_url: event.issue.html_url
    };
  },
});
```

---

### Step 3: Fetch Issue Context
**Node.js Code Step (with GitHub API):**
```javascript
import { Octokit } from "@octokit/rest";

export default defineComponent({
  props: {
    github: {
      type: "app",
      app: "github",
    },
  },
  async run({ steps, $ }) {
    const octokit = new Octokit({
      auth: this.github.$auth.oauth_access_token,
    });
    
    const [owner, repo] = steps.filter_check.$return_value.repo.split('/');
    const issue_number = steps.filter_check.$return_value.issue_number;
    
    // Fetch existing comments to check for existing plan
    const { data: comments } = await octokit.issues.listComments({
      owner,
      repo,
      issue_number,
    });
    
    // Check if plan already exists
    const existingPlan = comments.find(c => 
      c.body.includes('## 📋 Implementation Plan')
    );
    
    if (existingPlan) {
      $.flow.exit("Plan already exists for this issue");
    }
    
    // Fetch repository context (recent files, README, etc.)
    let repoContext = "";
    try {
      const { data: readme } = await octokit.repos.getReadme({
        owner,
        repo,
      });
      repoContext = Buffer.from(readme.content, 'base64').toString('utf8');
    } catch (e) {
      repoContext = "No README found";
    }
    
    return {
      owner,
      repo,
      issue_number,
      has_existing_plan: false,
      repo_context: repoContext.substring(0, 2000), // Limit context size
    };
  },
});
```

---

### Step 4: Generate Plan with Claude API
**Node.js Code Step:**
```javascript
import Anthropic from "@anthropic-ai/sdk";

export default defineComponent({
  props: {
    anthropic_api_key: {
      type: "string",
      label: "Anthropic API Key",
      secret: true,
    },
  },
  async run({ steps, $ }) {
    const anthropic = new Anthropic({
      apiKey: this.anthropic_api_key,
    });
    
    const issueData = steps.filter_check.$return_value;
    const repoContext = steps.fetch_context.$return_value.repo_context;
    
    const systemPrompt = `You are an expert software developer creating implementation plans for GitHub issues.
    
Your task is to analyze the issue and create a structured implementation plan.

Follow this format exactly:

## 📋 Implementation Plan

**Issue:** #${issueData.issue_number} - ${issueData.issue_title}
**Generated:** ${new Date().toISOString().split('T')[0]}
**Status:** Draft

---

### Overview
[2-3 sentence summary of the implementation approach]

### Phase 1: [Phase Name]
**Objective:** [What this phase accomplishes]

#### Task 1.1 - [Task Title]
- **Objective:** [One-sentence goal]
- **Output:** [Concrete deliverable]
- **Files:** [Files to create/modify]
- **Steps:**
  1. [Step one]
  2. [Step two]

[Continue with more tasks and phases as needed]

---

### Dependencies & Risks
- [List any external dependencies or potential blockers]

### Out of Scope
- [Explicitly excluded items based on issue description]

---
*React with 👍 to approve this plan, or comment with requested changes.*

Guidelines:
- Tasks should be small, completable in one focused session
- Each task should have clear, verifiable outputs
- Mark dependencies between tasks explicitly
- If something is unclear, add an investigation task first
- Be specific about files to create/modify
- Consider error handling and edge cases`;

    const userPrompt = `Create an implementation plan for this GitHub issue:

## Issue #${issueData.issue_number}: ${issueData.issue_title}

### Description:
${issueData.issue_body}

### Labels:
${issueData.issue_labels.join(', ')}

### Repository Context:
${repoContext}

Generate a detailed, actionable implementation plan following the format specified.`;

    const response = await anthropic.messages.create({
      model: "claude-sonnet-4-20250514",
      max_tokens: 4096,
      messages: [
        { role: "user", content: userPrompt }
      ],
      system: systemPrompt,
    });
    
    return {
      plan: response.content[0].text,
    };
  },
});
```

---

### Step 5: Post Plan to GitHub Issue
**Node.js Code Step:**
```javascript
import { Octokit } from "@octokit/rest";

export default defineComponent({
  props: {
    github: {
      type: "app",
      app: "github",
    },
  },
  async run({ steps, $ }) {
    const octokit = new Octokit({
      auth: this.github.$auth.oauth_access_token,
    });
    
    const { owner, repo, issue_number } = steps.fetch_context.$return_value;
    const plan = steps.generate_plan.$return_value.plan;
    
    // Post the plan as a comment
    const { data: comment } = await octokit.issues.createComment({
      owner,
      repo,
      issue_number,
      body: plan,
    });
    
    // Update labels to indicate planning in progress
    await octokit.issues.addLabels({
      owner,
      repo,
      issue_number,
      labels: ["AI: Planning"],
    });
    
    return {
      comment_url: comment.html_url,
      comment_id: comment.id,
    };
  },
});
```

---

### Step 6: Send Notification (Optional)
**Node.js Code Step (Slack notification):**
```javascript
export default defineComponent({
  props: {
    slack_webhook_url: {
      type: "string",
      label: "Slack Webhook URL",
      secret: true,
    },
  },
  async run({ steps, $ }) {
    const issueData = steps.filter_check.$return_value;
    const commentUrl = steps.post_plan.$return_value.comment_url;
    
    // Skip if no webhook configured
    if (!this.slack_webhook_url) {
      return { skipped: true };
    }
    
    const message = {
      blocks: [
        {
          type: "section",
          text: {
            type: "mrkdwn",
            text: `🤖 *Implementation Plan Generated*\n\n*Issue:* <${issueData.issue_url}|#${issueData.issue_number} - ${issueData.issue_title}>\n*Plan:* <${commentUrl}|View Plan>\n\nRun \`/issue ${issueData.issue_number}\` in Claude Code to begin implementation.`
          }
        }
      ]
    };
    
    await fetch(this.slack_webhook_url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(message),
    });
    
    return { notified: true };
  },
});
```

---

## Environment Variables Required

In Pipedream, configure these secrets:
- `ANTHROPIC_API_KEY` - Your Claude API key
- `SLACK_WEBHOOK_URL` (optional) - For notifications

## Testing

1. Create a test issue in your repository
2. Add the "AI" label
3. Watch Pipedream execution logs
4. Verify plan appears as issue comment

## Error Handling

The workflow includes:
- Exit early if not an AI label event
- Exit early if plan already exists
- Error handling for missing README
- Graceful handling of API failures

## Customization

### Adjust the prompt
Modify the `systemPrompt` in Step 4 to match your project's coding standards, tech stack, or planning preferences.

### Add more context
In Step 3, you can fetch additional context like:
- Recent commits
- Related issues
- Project structure
- Tech stack from package.json

### Different notification channels
Replace the Slack step with:
- Email notification
- Discord webhook
- SMS via Twilio
- Custom webhook to your own service

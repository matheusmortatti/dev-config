---
allowed-tools: Task(*), Read(*), TodoWrite(*), Bash(*)
argument-hint: <PR-URL-or-ID>
description: Orchestrates Azure DevOps pull request review using specialized sub-agents
---

Review Azure DevOps (ADO) Pull Request. 

# Basic Information

- Org: https://dev.azure.com/msazure
- Project: CloudNativeCompute
- Default repo: aks-rp

# Step 1: Fetch PR

Parse the PR URL or ID to extract repo and PR ID. For example:
- URL: `https://msazure.visualstudio.com/CloudNativeCompute/_git/aks-rp/pullrequest/13386625`
- Extract: repo=`aks-rp`, PR ID=`13386625`

Run: `~/.claude/scripts/ado_pr.sh fetch <repo> <pr-id>`

This will create:
- PR metadata: `~/aiplayground/ado-pr-fetcher/pr-data/{repo}-{pr-id}/metadata.md`
- Diff patch: `~/aiplayground/ado-pr-fetcher/pr-data/{repo}-{pr-id}/diff.patch`
- Worktree: `~/aiplayground/ado-pr-fetcher/pr-data/{repo}-{pr-id}/worktree/`

No need to read the directories and files above since they might be very large, and they are prepaired for next step.

# Step 2: Review

Use code-reviewer sub agent to do the first round review, provide detailed context like the PR data directory, the diff file, and the worktree.
At the same time, use golang-code-reviewer to do the second round review if any golang code been updated in the PR, also provide detailed context.

Write the review report into file `~/aiplayground/output/ado-pr-review/pr-{pr-id}/review_report.md`. Rules:
- DO NOT summarize what the PR does.
- DO NOT provide general commentary.
- DO NOT provide general conclusion.

The report should have structure like this:
```
## Issue 1: xxx (Severity: Critical|High|Medium)

Location: `putagentpoolasync_machines.go:214-251`

### Issue

<Describe the issue, explaination>

### Recommendation

<Some recommendations>

## Issue 2: xxx (Severity: Critical|High|Medium)

Location: `putagentpoolasync_machines.go:214-251`

### Issue

<Describe the issue.>

### Recommendation

<Some recommendations>

## Issue 3: xxx (Severity: Critical|High|Medium)
...
```

Ignore Low severity issues.
Merge same issues.
Explain in detail for the critical issues.
If no issues found, just say LGTM.

# Step 3: Clean Up

Confirm with user whether further review needed, if not, run `~/.claude/scripts/ado_pr.sh cleanup <repo> <pr-id>`.
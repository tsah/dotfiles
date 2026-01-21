---
description: Address PR issues - comments, ci, or all
agent: build
---

Address PR issues on the current branch based on the mode: **$1**

- `comments` - only address review comments
- `ci` - only fix CI failures
- `all` or empty - address both

---

## Mode: comments

Use when `$1` is "comments".

### 1. Gather comments

Invoke the **@pr-comments-gatherer** subagent using the Task tool to gather and analyze all PR review comments.

### 2. Clarify ambiguities

Review the analysis. For any comments that require clarification, ask the user before proceeding.

### 3. Address each comment

For each actionable comment:
- Navigate to the file and location mentioned
- Understand the context and what change is requested
- Make the appropriate code change
- If unclear or you disagree, ask the user how to proceed

### 4. Commit and push

- Create a commit with message: `address pr review feedback`
- Push to remote

### 5. Mark comments as resolved

For each addressed comment, resolve the thread:

```bash
gh api graphql -f query='
  mutation {
    resolveReviewThread(input: {threadId: "THREAD_ID"}) {
      thread { isResolved }
    }
  }
'
```

---

## Mode: ci

Use when `$1` is "ci".

### 1. Analyze CI failures

Invoke the **@pr-ci-analyzer** subagent using the Task tool to gather and analyze all CI check failures.

### 2. Fix each failure

For each CI failure:
- Navigate to the relevant file/test
- Understand the error from the logs
- Fix the issue

### 3. Verify locally

Run the suggested verification commands to confirm fixes:
- For test failures: run the specific failing tests
- For lint errors: run the linter
- For type errors: run type checking
- For build errors: run the build

### 4. Commit and push

- Create a commit with message: `fix ci failures`
- Push to remote

---

## Mode: all (default)

Use when `$1` is "all" or empty.

### 1. Gather information (parallel)

Invoke BOTH subagents using the Task tool:
- **@pr-ci-analyzer** - for CI failures
- **@pr-comments-gatherer** - for review comments

### 2. Fix CI failures FIRST

CI failures often block merging. Address them first following the "ci" workflow above.

### 3. Address review comments

Follow the "comments" workflow above.

### 4. Final commit and push

- Run the full test suite to ensure nothing is broken
- Create a commit summarizing all changes
- Push to remote
- Mark comment threads as resolved

---

## Summary

After completing, provide:
- CI failures fixed and how
- Review comments addressed and how
- Any items skipped and why
- Any remaining discussions or follow-ups

**IMPORTANT**: If you encounter any ambiguity, STOP and ask the user for guidance.

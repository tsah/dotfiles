---
description: Fix CI failures, address PR comments, commit, push, and resolve threads
agent: build
---

Address PR review comments and CI failures on the current branch, commit changes, push, and mark comments as resolved.

## Workflow

### 1. Gather information

FIRST - Use the @pr-comments-analyzer subagent to gather and analyze all PR review comments AND CI failures:
- Invoke the pr-comments-analyzer agent using the Task tool
- Wait for it to return the structured analysis of comments and CI status

### 2. Review and clarify

Review the analysis and for any items that require clarification or have ambiguity, ask the user before proceeding.

### 3. Fix CI failures FIRST

CI failures often block merging, so address them first:

For each CI failure identified:
- Navigate to the relevant file/test
- Understand the error from the logs
- Fix the issue (test failure, lint error, type error, build error, etc.)

Run the relevant checks locally to verify fixes:
- For test failures: run the specific failing tests
- For lint errors: run the linter
- For type errors: run type checking
- For build errors: run the build

### 4. Address review comments

For each actionable comment:
- Navigate to the file and location mentioned
- Understand the context and what change is requested
- Make the appropriate code change
- If a comment is unclear or you disagree with it, ask the user how to proceed

### 5. Commit and push

After addressing all issues:
1. Run the full test suite or relevant tests to ensure nothing is broken
2. Create a commit with a message summarizing:
   - CI fixes made
   - PR feedback addressed
3. Push the changes to the remote branch

### 6. Mark comments as resolved

For each comment that was addressed, use `gh api` to mark the review thread as resolved:

```bash
gh api --method PUT repos/{owner}/{repo}/pulls/{pr_number}/comments/{comment_id}/replies -f body="Addressed"
```

Or resolve the thread via GraphQL:
```bash
gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "THREAD_ID"}) { thread { isResolved } } }'
```

Note: You may need to find thread IDs using `gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews`

### 7. Provide summary

Report back with:
- CI failures fixed and how
- Review comments addressed and how
- Any items skipped and why
- Any follow-up items or remaining discussions

---

**IMPORTANT**: If you encounter any ambiguity about how to address a CI failure or comment, STOP and ask the user for guidance.

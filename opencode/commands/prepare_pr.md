---
description: Commit changes, review branch code, fix issues, run tests
agent: build
---

Prepare current branch for PR with comprehensive review and fixes.

## Lint and test
Make sure lint passes and run relevant tests

## Commit uncommitted changes

- Check `git status` to see uncommitted changes
- Create a logical commit with a descriptive message for any uncommitted work

## Review ALL changes on the branch

Run these commands to see all changes since diverging from main/master:
- `git diff main...HEAD` (or `git diff master...HEAD`)
- `git log main..HEAD` (or `git log master..HEAD`)

Fire up 2 code-review agents to review changes on current branch

Triage all issues found, fix if relevant.

Finally, make sure everything is commited and pushed to the remote branch

---

**IMPORTANT**: If you encounter any dilemma or ambiguity during the review (e.g., uncertain if code is redundant, unclear if a refactoring would break something, unsure about business logic), PAUSE and ask the user for guidance before proceeding.

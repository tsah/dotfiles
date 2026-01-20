---
description: Rebase on latest master
agent: build
---

Rebase the current branch on latest master.

## Steps

1. **Create a backup branch** - in case something goes wrong
2. **Fetch latest changes** - run `git fetch`
3. **Rebase on master** - run `git rebase origin/master`
4. **Resolve conflicts** - if there are any conflicts, solve them logically according to the changes on the branch

## Reporting

If there were conflicts, give a summary of:
- The conflicts encountered
- Your decisions and reasoning for each resolution

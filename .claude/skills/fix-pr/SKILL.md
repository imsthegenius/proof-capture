---
name: fix-pr
description: "Fix a rejected PR — reads Codex feedback from Linear comments and GitHub PR reviews, implements fixes (using agent teams for complex work), commits, pushes, and sets Linear back to In Review. Use when user says 'fix-pr', 'fix the pr', 'fix review feedback', 'address review comments', 'pr was rejected', or 'fix codex feedback'."
---

# Fix PR — Address Review Feedback

Reads rejection feedback from both Linear and GitHub, fixes every issue, self-reviews, commits, pushes, and updates Linear back to In Review. One command to unblock a rejected PR.

## Inputs

- `fix-pr` — auto-detect the current branch's open PR
- `fix-pr #7` or `fix-pr TWO-99` — specify the PR number or Linear ticket

## Step 1: Gather Feedback

Find the PR and its associated Linear ticket:

1. **Find the PR** — if not specified, detect from current branch:
   ```bash
   gh pr view --json number,url,title,headRefName,reviewDecision
   ```
2. **Find the Linear ticket** — extract from PR body (`Linear: TWO-XXX`), branch name (`two-XXX`), or commit messages
3. **Read ALL feedback sources:**

   **GitHub PR reviews** (code-level feedback):
   ```bash
   gh api repos/<OWNER>/<REPO>/pulls/<PR_NUM>/reviews -q '.[-1].body'
   ```

   **GitHub PR inline comments** (file/line-specific):
   ```bash
   gh api repos/<OWNER>/<REPO>/pulls/<PR_NUM>/comments -q '.[] | "\(.path):\(.line) — \(.body)"'
   ```

   **Linear ticket comments** (acceptance-criteria-level feedback):
   Read the latest comments on the Linear ticket — Codex posts rejection details here with checklist results, failed acceptance criteria, and file references.

4. **Compile a fix list** — every issue mentioned across all sources. Group by:
   - Build/test failures
   - Code quality issues (specific file + line)
   - Acceptance criteria not met
   - Convention violations

Print the fix list before starting work so you know the full scope.

## Step 2: Fix

**Assess complexity first:**
- If 1-3 small fixes in 1-2 files → fix directly
- If 4+ fixes across multiple files, or fixes that touch different layers (frontend + backend, types + implementation) → use an agent team:
  - Spawn one executor per independent fix group
  - Each executor gets the specific feedback items relevant to its files
  - Use the project's skills where relevant (e.g., `systematic-debugging` for bugs, `verification-before-completion` before claiming done)

**Fix every issue.** Don't skip items you disagree with — if Codex flagged it, fix it. The goal is to pass review, not to debate.

## Step 3: Self-Review

Before pushing, review the aggregate diff:

1. `git diff main..HEAD` — read every changed file
2. Check the fix list from Step 1 — is every item addressed?
3. Run the project's build command (from CLAUDE.md) — must pass
4. Check for new issues introduced by the fixes (unused imports, debug code, etc.)

## Step 4: Commit and Push

1. Stage only changed files — never `git add .`
2. Commit with a clear message:
   ```
   fix: address codex review feedback (TWO-<number>)
   ```
3. Push to the same branch — the PR updates automatically:
   ```bash
   git push
   ```
   Do NOT create a new PR.

## Step 5: Update Linear

1. Add a comment on the Linear ticket:
   ```
   Review feedback addressed. Fixes pushed.

   Changes made:
   - <issue 1>: <what was fixed>
   - <issue 2>: <what was fixed>

   Build: Passed
   Ready for re-review.
   ```
2. Ensure status is `In Review` (set it if Codex changed it)

## Output

```
## Fix PR Summary

**PR:** #7 — <title>
**Ticket:** TWO-99
**Issues fixed:** 4/4
**Build:** Passed
**Status:** Pushed, Linear set to In Review
```

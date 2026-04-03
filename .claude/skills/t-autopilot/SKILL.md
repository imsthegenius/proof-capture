---
name: t-autopilot
description: "Terminal autopilot: same as /autopilot but creates its own git worktree for isolation. Use from a normal terminal (not Conductor). Supports parallel tasks — each invocation gets its own worktree. Use when user says 't-autopilot', 'terminal autopilot', or runs autopilot outside Conductor."
---

# Terminal Autopilot — Worktree-Isolated Implement, Review, Merge

Same as `/autopilot` but designed for normal terminal use. Creates its own git worktree so you can run multiple instances in parallel without conflicts. Each task gets an isolated worktree branched from `origin/main`.

**Use `/autopilot` in Conductor workspaces. Use `/t-autopilot` in normal terminals.**

## Prerequisites

Before starting, verify:
1. **Codex MCP** — call the `codex` tool with a test prompt if unsure. If missing, stop: "Add codex to .mcp.json: `{\"codex\": {\"command\": \"codex\", \"args\": [\"mcp-server\"]}}`"
2. **Linear MCP** — Linear tools must be available for ticket management
3. **GitHub CLI** — run `gh auth status` to confirm
4. **CLAUDE.md** — must contain `LINEAR_PROJECT` for ticket scoping
5. **Build command** — must be documented in CLAUDE.md or discoverable

If any prerequisite is missing, stop and tell the user exactly what's needed.

## Inputs

- `t-autopilot TWO-215` — work on a specific task
- `t-autopilot` — auto-pick the next unblocked Todo task

## Phase 0: Worktree Setup (Terminal-Only)

**This phase is what makes t-autopilot different from autopilot.**

Before any implementation, create an isolated worktree:

1. **Ensure you're in the project root** (where `.git/` lives, not inside an existing worktree)
2. **Fetch latest main:**
   ```bash
   git fetch origin main
   ```
3. **Create the worktree** once you know the task ID (after Phase 1 selection):
   ```bash
   git worktree add .claude/worktrees/two-<number>-<slug> origin/main
   ```
4. **cd into the worktree** — ALL subsequent work happens here:
   ```bash
   cd .claude/worktrees/two-<number>-<slug>
   ```
5. **Provision the worktree** — link env files:
   ```bash
   for f in .env .env.local; do [ -f "$PROJECT_ROOT/$f" ] && ln -sf "$PROJECT_ROOT/$f" "$f"; done
   [ -f "$PROJECT_ROOT/.claude/settings.local.json" ] && ln -sf "$PROJECT_ROOT/.claude/settings.local.json" .claude/settings.local.json
   ```
6. **Install deps** if needed:
   ```bash
   [ -f package.json ] && npm install --prefer-offline --no-audit
   ```

**Save `PROJECT_ROOT`** (the original project directory) — you need it for cleanup.

Now proceed to Phase 2 (Implementation) in the worktree.

---

## Phase 1: Task Selection

### If a task ID was provided:
Fetch it from Linear and proceed directly to Phase 0 step 3 (create worktree with the task slug).

### If auto-picking:

**IMPORTANT: The Linear MCP `linear_search_issues` tool has these constraints:**
- `query` and `states` CANNOT be combined — using both causes a GraphQL error
- There is NO `projectId` filter parameter
- You must filter by project client-side using the `project.name` field in results

Follow this exact sequence:

1. **Read CLAUDE.md** to get the `LINEAR_PROJECT` value (e.g., "Mission Control — Content Orchestration")

2. **Fetch Backlog tasks** — call `linear_search_issues` with ONLY the `states` parameter:
   ```
   linear_search_issues(states: ["Backlog"], first: 50)
   ```
   Do NOT pass `query` at the same time — it will error.

3. **Filter by project** — from the results, keep only tasks where `project.name` matches `LINEAR_PROJECT`. Discard everything else.

4. **If no Backlog tasks found**, also try `Todo` and `Unstarted`:
   ```
   linear_search_issues(states: ["Todo"], first: 50)
   linear_search_issues(states: ["Unstarted"], first: 50)
   ```
   Filter by project name again.

5. **For EACH matching task**, check its `blockedBy` relations (fetch each blocker's status):
   - If ANY blocker is NOT `Done` or `Cancelled`, the task is **blocked** — skip it

6. **From the remaining unblocked tasks**, check which ones are **blockers for other tasks** (have `blocks` relations). These are higher priority because completing them unblocks more work.

7. **Pick using this priority order:**
   - First: unblocked tasks that BLOCK the most other tasks (unblock the pipeline)
   - Then: highest Linear priority (P1 > P2 > P3 > P4)
   - Then: oldest task (created first)

8. If NO unblocked tasks exist, report "No unblocked tasks found — all remaining tasks have incomplete blockers" and list what's blocking what, then stop.

### Critical rule:
**If task A blocks task B, ALWAYS do A before B.** Never pick a downstream task when its blocker is available. The whole point of the dependency graph is execution order — respect it.

**Save for the entire loop:** task ID, title, full description, acceptance criteria, parent issue context (if any).

Then proceed to Phase 0 step 3 (create worktree).

---

## Phase 2: Implementation

1. **Update Linear** → `In Progress`
2. **Rename the branch** in the worktree to follow convention:
   ```bash
   git checkout -b feature/two-<number>-<slug>
   ```
3. **Read the full ticket** — parent issues, specs, linked tickets, acceptance criteria
4. **Implement** the changes as described. If the task is large enough to benefit from subagents, use the agent team pipeline (planner → executor(s) → verifier).
5. **Run build/verify** — use the project's build command from CLAUDE.md. Must pass zero errors.

---

## Phase 3: Self-Review (Internal Quality Gate)

**Before pushing, review your own work.** This catches obvious issues before spending Codex credits.

1. Run `git diff main..HEAD` and review every changed file
2. Check for:
   - Unused imports or variables
   - Debug code (`console.log`, `print`, `debugPrint`)
   - Hardcoded secrets or credentials
   - Empty catch blocks or swallowed errors
   - Convention violations (check CLAUDE.md rules)
   - Code that doesn't match what the ticket asked for
   - Over-engineering or unnecessary abstractions
3. Re-read the acceptance criteria — does every criterion have a corresponding change?
4. Run the build again if you made fixes
5. Fix any issues found — do NOT push code you know has problems

**If using subagents:** this self-review step is especially important. Different agents may have made inconsistent changes. Review the aggregate diff as a whole.

---

## Phase 4: Commit, Push, PR

1. **Stage** only the files you changed — never `git add .` or `git add -A`
2. **Commit** with the ticket ID: `feat: <summary> (TWO-<number>)`
3. **Push** the branch: `git push -u origin <branch-name>`
4. **Create PR** via `gh pr create` with:
   - Title matching the Linear ticket title
   - Body containing: summary of changes, `Linear: TWO-<number>`, what was verified, build output confirmation
5. Save the **PR URL** and **PR number**

---

## Phase 5: Update Linear

1. **Set status** → `In Review`
2. **Add a comment** on the Linear ticket with the handoff context:

```
Implementation complete. PR ready for Codex merge-safety-review.

**PR:** <PR_URL>
**Branch:** <branch-name>
**Build:** Passed (command: <build command>)
**Self-review:** Completed — no issues found

Acceptance criteria addressed:
- <criterion 1>: <how it was implemented>
- <criterion 2>: <how it was implemented>
```

---

## Phase 6: Notify Codex for Review

**Do NOT use the `/codex` skill or `codex review`. Use `codex exec` via Bash.**

Codex receives the full review request and is responsible for ALL review actions: running checks, posting results to GitHub and Linear, and merging on pass.

```bash
codex exec \
  --dangerously-bypass-approvals-and-sandbox \
  -C "<worktree or project directory>" \
  -o /tmp/codex-review-output.txt \
  "Use the merge-safety-review skill to review PR #<PR_NUMBER> in <REPO_SLUG>. PR URL: <PR_URL>. Base branch: main. Build command: <build command>. Linear ticket: <TASK_ID>.

Run the full merge-safety-review checklist: build, tests, lint, diff review, acceptance criteria, convention compliance, changed-file coverage.

ON PASS:
- Post a PR comment with the full checklist results and 'CODEX VERDICT: PASS'
- Merge the PR (squash merge, delete branch)
- Update the Linear ticket status to Done
- Add a Linear comment: 'Codex merge-safety-review passed. PR merged.'

ON FAIL:
- Post a PR comment with the full checklist results and 'CODEX VERDICT: FAIL'
- Request changes on the GitHub PR with specific file/line feedback
- Update the Linear ticket with a rejection comment listing every failed check
- Do NOT merge"
```

**Key flag:** `--dangerously-bypass-approvals-and-sandbox` — NO sandbox, NO approval prompts. Codex gets full network access to post to GitHub, merge PRs, and update Linear. This is what makes Codex able to own the write actions.

After the command completes, read the output:
```bash
cat /tmp/codex-review-output.txt
```

---

## Phase 7: Read Codex Response and Act

Read `/tmp/codex-review-output.txt` for the verdict.

**Check what Codex did:**

1. Check if the PR was merged: `gh pr view <PR_NUM> --json state -q .state`
2. Check Linear ticket status (via Linear MCP)
3. Check for PR comments with the verdict: `gh api repos/<OWNER>/<REPO>/issues/<PR_NUM>/comments -q '.[].body' | grep "CODEX VERDICT"`

### If Codex merged (PR state = MERGED, Linear = Done):

Codex handled everything. Just:
1. Clean up the worktree
2. Output the success summary
3. **Stop.** The task is complete.

### If Codex couldn't merge/post (sandbox limitation):

If Codex's output says PASS but the PR isn't merged (sandbox blocked writes):
1. **Post PR comment** with Codex's review summary: `gh pr comment <PR_NUM> --body "<codex summary>"`
2. **Merge the PR:** `gh pr merge <PR_URL> --squash --delete-branch`
3. **Update Linear to Done** (via Linear MCP)
4. Clean up worktree
5. **Stop.**

### If Codex rejected (VERDICT: FAIL):

Continue to Phase 8.

### If Codex output is empty or errored:

**STOP. Escalate to user.** Do NOT merge.

---

## Phase 8: Fix Feedback (On Rejection)

**Read feedback from BOTH Linear and Git:**

1. **Linear comments** — Codex posts rejection details on the ticket. Read the latest comment.
2. **GitHub PR reviews** — Codex requests changes on the PR:
   ```bash
   gh api repos/<OWNER>/<REPO>/pulls/<PR_NUM>/reviews -q '.[-1].body'
   ```
3. **GitHub PR comments** — Codex may leave inline code comments:
   ```bash
   gh api repos/<OWNER>/<REPO>/pulls/<PR_NUM>/comments -q '.[].body'
   ```

**If Codex couldn't post to Linear/Git** (sandbox limitation), read the feedback from `/tmp/codex-review-output.txt` instead.

**Fix every issue identified.** Address both acceptance criteria failures and code quality issues.

**Then go back to Phase 3 (Self-Review):**
- Self-review the fixes
- Commit: `fix: address codex review feedback (iteration N) (TWO-<number>)`
- Push to the same branch (PR updates automatically — do NOT create a new PR)
- Update Linear: add a comment noting fixes were pushed
- Re-run `codex exec` (same command as Phase 6 with `--dangerously-bypass-approvals-and-sandbox`, fresh process)

**Then go back to Phase 7** to read the new response.

---

## Phase 9: Escalation

If the review loop runs **5 iterations** without passing:

1. **Stop trying** — the issues may be fundamental or the ticket may be underspecified
2. **Update Linear** with a comment:
   "Automated review loop exhausted after 5 iterations. Last Codex feedback: <summary of remaining issues>. Needs human review."
3. **Keep status** as `In Review`
4. **Keep the PR open** and the worktree intact
5. **Report to the user:**

```
## Autopilot Escalated

**Task:** TWO-215 — <title>
**Status:** Needs human review
**PR:** <PR_URL>
**Review iterations:** 5 (max reached)
**Remaining issues:** <brief summary from last Codex review>
**Linear:** In Review (escalated)
**Worktree:** <path> (kept for inspection)
```

---

## Guardrails

- **Claude Code never marks its own work as Done** — only Codex sets Done
- **Claude Code never merges the PR** — Codex merges on approval. Claude only merges as fallback if Codex passed but sandbox blocked the merge.
- **Never skip self-review** — this catches obvious issues cheaply
- **Never push code that doesn't build** — fix build errors before pushing
- **Never create a new PR for fixes** — push to the same branch
- **Never delete the worktree until Codex confirms merge** — you may need it for fixes
- **One task per invocation** — for parallel tasks, the user runs multiple sessions

## Error Handling

| Error | Action |
|-------|--------|
| Linear MCP not available | Stop. Tell user Linear MCP must be configured |
| `gh` not authenticated | Stop. Tell user to run `gh auth login` |
| Build fails before PR | Fix the build. Do not push broken code |
| PR has merge conflicts | `git fetch origin main && git rebase origin/main`, resolve, force-push, re-trigger Codex |
| Codex times out or empty response | Retry once. If fails again, escalate to user |
| Codex passed but sandbox blocked merge | Claude merges as fallback (see Phase 7) |

## Output

On completion, always output:

```
## Autopilot Summary

**Task:** TWO-215 — <title>
**Status:** Merged | Needs human review
**PR:** <url>
**Review iterations:** N
**Linear:** Done | In Review (escalated)
```

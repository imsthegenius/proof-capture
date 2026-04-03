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

**IMPORTANT: Do NOT use the Codex MCP tool, the `/codex` skill, or `codex review`. Use `codex exec` via Bash only.**

The Codex MCP tool hangs because its server process caches stale config and has timeout issues on long reviews. `codex exec` runs a fresh process every time and is reliable.

Run this via the Bash tool:

```bash
codex exec \
  --full-auto \
  -p danger \
  -C "<worktree or project directory>" \
  -o /tmp/codex-review-output.txt \
  "Use the merge-safety-review skill to review PR #<PR_NUMBER> in <REPO_SLUG>. PR URL: <PR_URL>. Base branch: main. Build command: <build command>. Linear ticket: <TASK_ID>. IMPORTANT: Do NOT use the GitHub review-approve endpoint (it fails for same-user PRs). Instead: ON PASS: post a PR comment (not a review approval) with the full checklist and the exact text 'CODEX VERDICT: PASS', then merge the PR (squash, delete branch), update Linear to Done, add Linear comment 'Codex merge-safety-review passed. PR merged.' ON FAIL: post a PR comment with the full checklist and the exact text 'CODEX VERDICT: FAIL', request changes on the PR with specific file/line feedback, update Linear with rejection details. Do NOT merge on fail."
```

**Key flags:**
- `--full-auto` — no approval prompts, full sandbox access
- `-p danger` — uses the danger profile (full disk + network access)
- `-C` — sets the working directory to the worktree
- `-o` — writes Codex's final message to a file for reliable parsing

After the command completes, read the output:
```bash
cat /tmp/codex-review-output.txt
```

**NEVER use `codex review` with a prompt — that syntax is invalid.**
**NEVER use the `mcp__codex__codex` MCP tool — it hangs on long reviews.**

---

## Phase 7: Verify Codex Actually Reviewed

<HARD-GATE>
NEVER merge a PR without VERIFIED evidence that Codex reviewed it.
If the Codex MCP call returned empty, errored, or you're unsure — DO NOT MERGE.
Escalate to the user instead.
</HARD-GATE>

**Step 1: Check if Codex responded at all.**

If the `codex` MCP tool call or `codex exec` bash command:
- Returned empty content → **STOP. Codex did not review. Escalate to user.**
- Returned an error → **STOP. Codex did not review. Escalate to user.**
- Timed out → **STOP. Codex did not review. Escalate to user.**

**Step 2: Verify Codex posted its verdict on the PR.**

Check for a PR comment containing the verdict marker:
```bash
gh api repos/<OWNER>/<REPO>/issues/<PR_NUM>/comments -q '.[].body' | grep -c "CODEX VERDICT"
```
- If count is `0` → **STOP. Codex did not post a verdict. Do NOT merge.**
- If found, check which verdict:
```bash
gh api repos/<OWNER>/<REPO>/issues/<PR_NUM>/comments -q '.[].body' | grep "CODEX VERDICT"
```
- `CODEX VERDICT: PASS` → Codex approved. Proceed to merge.
- `CODEX VERDICT: FAIL` → Codex rejected. Proceed to Phase 8 (fix).
- Neither → **STOP. Ambiguous. Escalate to user.**

**Step 3: Only merge if BOTH conditions are true:**
1. Codex response content indicates pass (contains `CODEX VERDICT: PASS` or `Approval decision: approved`)
2. A PR comment exists on GitHub containing `CODEX VERDICT: PASS`

If either condition is false, DO NOT MERGE.

### If both conditions confirm approval:

1. Merge the PR: `gh pr merge <PR_URL> --squash --delete-branch`
2. Update Linear ticket to `Done`
3. **cd back to the project root:** `cd <PROJECT_ROOT>`
4. **Remove the worktree:** `git worktree remove .claude/worktrees/two-<number>-<slug> --force`
5. Output the success summary
6. **Stop.** The task is complete.

### If Codex Rejected:

Continue to Phase 8.

---

## Phase 8: Fix Feedback (On Rejection)

**Read feedback from BOTH Linear and Git:**

1. **Linear comments** — Codex posts rejection details on the ticket. Read the latest comment on the Linear ticket. This has acceptance-criteria-level feedback.
2. **GitHub PR reviews** — Codex requests changes on the PR. Read the review:
   ```bash
   gh api repos/<OWNER>/<REPO>/pulls/<PR_NUM>/reviews -q '.[-1].body'
   ```
3. **GitHub PR comments** — Codex may leave inline code comments:
   ```bash
   gh api repos/<OWNER>/<REPO>/pulls/<PR_NUM>/comments -q '.[].body'
   ```

**Fix every issue identified.** Address both the Linear-level feedback (acceptance criteria, missing functionality) and the Git-level feedback (code quality, specific file issues).

**Then go back to Phase 3 (Self-Review):**
- Self-review the fixes
- Commit: `fix: address codex review feedback (iteration N) (TWO-<number>)`
- Push to the same branch (PR updates automatically — do NOT create a new PR)
- Update Linear: add a comment noting fixes were pushed
- Call `codex-reply` MCP tool with the saved `threadId`:

```
Tool: codex-reply
Parameters:
  threadId: "<saved threadId>"
  prompt: |
    Fixes pushed for iteration N. Please re-review PR #<NUMBER>.

    Changes made:
    - <what was fixed, referencing the specific issues Codex flagged>

    Re-run the full merge-safety-review checklist.
    Check that each specific issue you flagged is now resolved.

    Same rules apply:
    - ON PASS: approve, merge, update Linear to Done
    - ON FAIL: request changes, update Linear with what's still wrong
```

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
## Terminal Autopilot Escalated

**Task:** TWO-215 — <title>
**Status:** Needs human review
**PR:** <PR_URL>
**Review iterations:** 5 (max reached)
**Remaining issues:** <brief summary from last Codex review>
**Linear:** In Review (escalated)
**Worktree:** .claude/worktrees/two-<number>-<slug> (kept for inspection)
```

---

## Guardrails

- **Claude Code never marks its own work as Done** — only a successful Codex merge triggers Done
- **Claude Code never merges the PR** — Codex handles merge on approval
- **Never skip self-review** — this catches obvious issues cheaply
- **Never push code that doesn't build** — fix build errors before pushing
- **Never create a new PR for fixes** — push to the same branch
- **Never delete the worktree until Codex confirms merge** — you may need it for fixes
- **Never work directly on main** — always in a worktree
- **One task per invocation** — for parallel tasks, run multiple terminal sessions each calling `/t-autopilot`

## Parallel Usage

To run 3 tasks simultaneously from terminal:

```bash
# Terminal 1
cd ~/Desktop/mission-control && claude -p "/t-autopilot TWO-99" --permission-mode bypassPermissions

# Terminal 2
cd ~/Desktop/mission-control && claude -p "/t-autopilot TWO-164" --permission-mode bypassPermissions

# Terminal 3
cd ~/Desktop/mission-control && claude -p "/t-autopilot" --permission-mode bypassPermissions
```

Each creates its own worktree under `.claude/worktrees/` — no conflicts.

## Error Handling

| Error | Action |
|-------|--------|
| Already inside a worktree | Stop. Tell user to cd to the project root first |
| Codex MCP tool not available | Stop. Tell user to check `.mcp.json` |
| Linear MCP not available | Stop. Tell user Linear MCP must be configured |
| `gh` not authenticated | Stop. Tell user to run `gh auth login` |
| Build fails before PR | Fix the build. Do not push broken code |
| PR has merge conflicts | `git fetch origin main && git rebase origin/main`, resolve, force-push, re-trigger Codex |
| Codex times out or empty response | Retry once. If fails again, escalate to user |
| Codex merged but Linear not updated | Update Linear to Done manually |

## Output

On completion, always output:

```
## Terminal Autopilot Summary

**Task:** TWO-215 — <title>
**Status:** Merged | Needs human review
**PR:** <url>
**Review iterations:** N
**Linear:** Done | In Review (escalated)
**Worktree:** removed | kept at .claude/worktrees/...
```

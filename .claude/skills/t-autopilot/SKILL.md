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
Follow this exact sequence — do NOT skip steps:

1. **Fetch ALL tasks** in this project's Linear project (`LINEAR_PROJECT` from CLAUDE.md) that are in `Todo` status
2. **For EACH task**, check its `blockedBy` relations:
   - Fetch every blocker ticket's status
   - If ANY blocker is NOT `Done` or `Cancelled`, the task is **blocked** — skip it
3. **From the remaining unblocked tasks**, check which ones are **blockers for other tasks** (have `blocks` relations). These are higher priority because completing them unblocks more work.
4. **Pick using this priority order:**
   - First: unblocked tasks that BLOCK the most other tasks (unblock the pipeline)
   - Then: highest Linear priority (P1 > P2 > P3 > P4)
   - Then: oldest task (created first)
5. If NO unblocked tasks exist, report "No unblocked tasks found — all remaining tasks have incomplete blockers" and list what's blocking what, then stop.

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

## Phase 6: Notify Codex (MCP Tool Call)

Call the `codex` MCP tool. This is a direct tool call — Codex receives the request immediately, no polling.

```
Tool: codex
Parameters:
  prompt: |
    Use the merge-safety-review skill.

    Check BOTH Linear and Git for full context:

    **Linear ticket:** <TASK_ID>
    - Read the ticket description and acceptance criteria from Linear
    - Check parent issue context if one exists

    **GitHub PR:** #<PR_NUMBER> in <REPO_SLUG>
    - PR URL: <PR_URL>
    - Base branch: main

    **Build command:** <from CLAUDE.md>

    Run the full merge-safety-review checklist:
    1. Build — run the build command, must pass zero errors
    2. Tests — run if they exist
    3. Lint — run if configured
    4. Diff review — git diff main..HEAD against the base branch
    5. Acceptance criteria — verify EACH one from the Linear ticket with evidence
    6. Convention compliance — check against CLAUDE.md / AGENTS.md
    7. Changed-file coverage — every changed file must be justified by the ticket

    ON PASS:
    - Approve the PR on GitHub
    - Merge the PR (squash merge, delete branch)
    - Update the Linear ticket status to Done
    - Add a Linear comment: "Codex merge-safety-review passed. PR merged."

    ON FAIL:
    - Request changes on the GitHub PR with specific file/line feedback
    - Update the Linear ticket with a rejection comment listing every failed check, file references, and what needs fixing — enough context that the implementing agent can fix from Linear alone
    - Do NOT change the Linear status (keep it In Review)

  cwd: "<worktree directory>"
  sandbox: "danger-full-access"
  approval-policy: "never"
  config:
    shell_environment_policy:
      inherit: "all"
```

**Save the `threadId`** from the response — you need it for follow-up reviews.

---

## Phase 7: Read Codex Response

The `codex` tool returns `{threadId, content}`.

**Determine the outcome by checking both the response AND the actual state:**

1. Read the `content` for Codex's verdict (`Approval decision: approved` or `not approved`)
2. Verify against GitHub: `gh pr view <PR_NUM> --json reviewDecision,state -q '{reviewDecision, state}'`
   - `reviewDecision: "APPROVED"` AND `state: "MERGED"` → Codex approved and merged
   - `reviewDecision: "CHANGES_REQUESTED"` → Codex rejected
3. Check Linear ticket status — if Codex set it to `Done`, it merged successfully

### If Codex Merged Successfully:

1. **cd back to the project root:** `cd <PROJECT_ROOT>`
2. **Remove the worktree:** `git worktree remove .claude/worktrees/two-<number>-<slug> --force`
3. Output the success summary
4. **Stop.** The task is complete.

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

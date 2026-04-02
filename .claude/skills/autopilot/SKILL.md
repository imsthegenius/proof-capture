---
name: autopilot
description: "Fully automated Linear task loop: pick task, implement, self-review, PR, Codex review via MCP, fix feedback, merge. Fire-and-forget. Use when user says 'autopilot', 'run the loop', 'pick a task and finish it', 'implement and review', 'fire and forget', or 'autopilot [task-id]'. Requires codex MCP server and Linear MCP configured."
---

# Autopilot — Implement, Review, Merge

Fully automated loop. Claude Code picks a Linear task, implements it, self-reviews, pushes a PR, updates Linear, then hands off to Codex via MCP for merge-safety-review. Codex checks both Linear and Git, approves or rejects with context on both platforms. On rejection, Claude Code reads feedback from both Linear and Git, fixes, and re-triggers Codex. Loop continues until Codex merges or escalation.

## Prerequisites

Before starting, verify:
1. **Codex MCP** — call the `codex` tool with a test prompt if unsure. If missing, stop: "Add codex to .mcp.json: `{\"codex\": {\"command\": \"codex\", \"args\": [\"mcp-server\"]}}`"
2. **Linear MCP** — Linear tools must be available for ticket management
3. **GitHub CLI** — run `gh auth status` to confirm
4. **CLAUDE.md** — must contain `LINEAR_PROJECT` for ticket scoping
5. **Build command** — must be documented in CLAUDE.md or discoverable

If any prerequisite is missing, stop and tell the user exactly what's needed.

## Inputs

- `autopilot TWO-215` — work on a specific task
- `autopilot` — auto-pick the next unblocked Todo task

## The Loop

```
                    ┌──────────────────────────────────────────┐
                    │                                          │
PICK TASK ► IMPLEMENT ► SELF-REVIEW ► COMMIT+PUSH+PR ► UPDATE LINEAR
                                                          │
                                          NOTIFY CODEX (MCP tool call)
                                                          │
                                    Codex checks Linear + Git
                                    Runs merge-safety-review
                                                          │
                                       ┌──────────────────┴──────────────┐
                                    APPROVED                          REJECTED
                                       │                                 │
                              Codex merges PR                  Codex updates Linear
                              Codex updates Linear→Done        Codex updates Git PR
                              Codex tells Claude: "merged"     Codex tells Claude: "failed"
                                       │                                 │
                              Claude exits worktree           Claude reads Linear + Git
                                                              Claude fixes issues
                                                              Claude self-reviews ──────┘
                                                                        (max 5 iterations)
```

---

## Phase 1: Task Selection

### If a task ID was provided:
Fetch it from Linear and proceed directly to Phase 2.

### If auto-picking:
Follow this exact sequence — do NOT skip steps:

1. **Fetch ALL tasks** in this project's Linear project (`LINEAR_PROJECT` from CLAUDE.md) that are in `Todo`, `Backlog`, or `Unstarted` status (any status that means "not yet started" — different Linear workspaces use different names)
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

---

## Phase 2: Implementation

1. **Update Linear** → `In Progress`
2. **Create a feature branch** — never work on `main`. Use `feature/two-<number>-<slug>` or `fix/two-<number>-<slug>` convention.
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

**IMPORTANT: Do NOT use the `/codex` skill or run `codex review` via Bash. Those are wrong.**

There are two ways to call Codex. Try them in order:

### Option A: Codex MCP tool (preferred)

If the `mcp__codex__codex` tool is available (check via ToolSearch for "codex"), call it directly:

```json
{
  "prompt": "Use the merge-safety-review skill.\n\nLinear ticket: <TASK_ID>\nGitHub PR: #<PR_NUMBER> in <REPO_SLUG>\nPR URL: <PR_URL>\nBase branch: main\nBuild command: <from CLAUDE.md>\n\nRun the full merge-safety-review checklist: build, tests, lint, diff review, acceptance criteria, convention compliance, changed-file coverage.\n\nON PASS: approve the PR on GitHub, merge it (squash, delete branch), update Linear to Done, add comment 'Codex merge-safety-review passed. PR merged.'\n\nON FAIL: request changes on the GitHub PR with specific file/line feedback, update Linear with a rejection comment listing every failed check with file references.",
  "cwd": "<worktree or project directory>",
  "sandbox": "danger-full-access",
  "approval-policy": "never"
}
```

Save the `threadId` from the response for follow-up reviews.

### Option B: Codex CLI fallback (if MCP not available)

If the Codex MCP tool is not available, run Codex via Bash using `codex exec` (NOT `codex review`):

```bash
codex exec \
  --full-auto \
  -C "<worktree or project directory>" \
  "Use the merge-safety-review skill to review PR #<PR_NUMBER> in <REPO_SLUG>. PR URL: <PR_URL>. Base branch: main. Build command: <build command>. Linear ticket: <TASK_ID>. ON PASS: approve and merge the PR, update Linear to Done. ON FAIL: request changes on the PR, post rejection to Linear."
```

**NEVER use `codex review` with a prompt — that syntax is invalid.** `codex review` only accepts `--base <branch>` without a prompt, or a prompt without `--base`. Use `codex exec` for prompted reviews.

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

**Step 2: Verify a review exists on GitHub.**

Run this command and check the output:
```bash
gh api repos/<OWNER>/<REPO>/pulls/<PR_NUM>/reviews -q 'length'
```
- If the count is `0` → **STOP. No review exists. Codex did not review. Do NOT merge.**
- If the count is > 0, check the latest review state:
```bash
gh api repos/<OWNER>/<REPO>/pulls/<PR_NUM>/reviews -q '.[-1].state'
```
- `APPROVED` → Codex approved. Proceed to merge.
- `CHANGES_REQUESTED` → Codex rejected. Proceed to Phase 8 (fix).
- Anything else → **STOP. Ambiguous state. Escalate to user.**

**Step 3: Only merge if BOTH conditions are true:**
1. Codex response content contains `Approval decision: approved`
2. GitHub shows at least one review with state `APPROVED`

If either condition is false, DO NOT MERGE.

### If both conditions confirm approval:

1. Merge the PR: `gh pr merge <PR_URL> --squash --delete-branch`
2. Update Linear ticket to `Done`
3. Clean up the worktree
4. Output the success summary
5. **Stop.** The task is complete.

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

- **Claude Code never marks its own work as Done** — only a successful Codex merge triggers Done
- **Claude Code never merges the PR** — Codex handles merge on approval
- **Never skip self-review** — this catches obvious issues cheaply
- **Never push code that doesn't build** — fix build errors before pushing
- **Never create a new PR for fixes** — push to the same branch
- **Never delete the worktree until Codex confirms merge** — you may need it for fixes
- **One task per invocation** — for parallel tasks, the user runs multiple sessions

## Error Handling

| Error | Action |
|-------|--------|
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
## Autopilot Summary

**Task:** TWO-215 — <title>
**Status:** Merged | Needs human review
**PR:** <url>
**Review iterations:** N
**Linear:** Done | In Review (escalated)
```

---
name: autopilot
description: "Fully automated Linear task loop: pick task, implement, PR, Codex review via MCP, fix feedback, merge. Fire-and-forget. Use when user says 'autopilot', 'run the loop', 'pick a task and finish it', 'implement and review', 'fire and forget', or 'autopilot [task-id]'. Requires codex MCP server and Linear MCP configured."
---

# Autopilot — Implement, Review, Merge

Fully automated loop that picks a Linear task, implements it, gets Codex to review via MCP tool call, fixes any feedback, and merges when approved. No human involvement needed after launch.

## Prerequisites

Before starting, verify these are available:
1. **Codex MCP** — `codex` tool must be callable (from `.mcp.json` codex mcp-server)
2. **Linear MCP** — Linear tools must be available for ticket management
3. **GitHub CLI** — `gh` must be authenticated
4. **CLAUDE.md** — must contain `LINEAR_PROJECT` for ticket scoping

If any prerequisite is missing, stop and tell the user what's needed.

## Inputs

The user provides one of:
- A specific task ID: `autopilot TWO-215`
- Nothing: `autopilot` — pick the next unblocked Todo task automatically

## The Loop

```
PICK TASK ──► IMPLEMENT ──► PR ──► CODEX REVIEW ──►─┐
                                       │             │
                                   APPROVED?         │
                                   ┌───┴───┐         │
                                  YES      NO        │
                                   │       │         │
                               MERGE    FIX ─────────┘
                                   │    (max 5 iterations)
                               LINEAR→DONE
```

### Phase 1: Task Selection

1. If a task ID was provided, fetch it from Linear
2. Otherwise, query Linear for unblocked Todo tasks in this project (`LINEAR_PROJECT` from CLAUDE.md)
3. Pick the highest priority task that has no `blockedBy` dependencies on incomplete work
4. If no tasks available, report "No unblocked tasks found" and stop

Record the task ID, title, description, and acceptance criteria. You need these throughout.

### Phase 2: Implementation

Follow the `linear-workflow-rule` exactly. The key steps:

1. **Update Linear** status to `In Progress`
2. **Create a worktree** or work on a feature branch — never implement on `main`
3. **Read the full ticket** context — parent issues, specs, acceptance criteria
4. **Implement** the changes as described
5. **Run build/verify** — check CLAUDE.md for the project's build command. Must pass.
6. **Self-review** — `git diff main..HEAD`. Fix: unused imports, debug code, hardcoded secrets, empty catch blocks, convention violations
7. **Commit** with the ticket ID in the message (e.g., `feat: add auth flow (TWO-215)`)
8. **Push** the branch to origin
9. **Create PR** via `gh pr create` with:
   - Title matching the ticket title
   - Body with: summary, changes list, `Linear: TWO-<number>`, verification section
10. **Update Linear** status to `In Review`

Capture the PR URL and PR number — you need them for Phase 3.

### Phase 3: Codex Review

Call the Codex MCP tool directly. This is the core innovation — no polling, no bash scripts, no stdout parsing. Claude talks to Codex as a tool call.

**Call the `codex` MCP tool with:**

```
prompt: "Use the merge-safety-review skill to review PR #<NUMBER>.

Context:
- PR URL: <PR_URL>
- Repo: <REPO_SLUG> (get from `gh repo view --json nameWithOwner -q .nameWithOwner`)
- Base branch: main
- Linear ticket: <TASK_ID>
- Acceptance criteria: <paste from the ticket>
- Build command: <from CLAUDE.md>

Run the FULL merge-safety-review checklist:
1. Build — run the build command, must pass zero errors
2. Tests — run if they exist
3. Lint — run if configured
4. Diff review — git diff main..HEAD
5. Acceptance criteria — verify EACH one with evidence
6. Convention compliance — check against CLAUDE.md / AGENTS.md
7. Changed-file coverage — every changed file must be justified

If ALL pass: approve the PR on GitHub via the GitHub plugin.
If ANY fail: request changes on the PR with specific feedback. Post a rejection comment on the Linear ticket with file references and failing commands."

cwd: "<worktree or project directory>"
sandbox: "workspace-write"
approval-policy: "never"
```

**Parse the Codex response:**

The `codex` tool returns `{threadId, content}`. Save the `threadId` for follow-up reviews.

Read the `content` to determine the verdict:
- Look for `Approval decision: approved` → APPROVED
- Look for `Approval decision: not approved` → REJECTED
- Also check: `gh pr view <PR_NUM> --json reviewDecision -q .reviewDecision` for `APPROVED`

### Phase 4: Decision

**If APPROVED:**
1. Merge the PR: `gh pr merge <PR_URL> --squash --delete-branch`
2. Update Linear ticket to `Done`
3. Add Linear comment: "Codex merge-safety-review passed. PR merged."
4. Clean up worktree if one was created
5. Report success to the user

**If REJECTED:**
1. Read the review feedback from Codex's response content
2. Also read: `gh api repos/<OWNER>/<REPO>/pulls/<PR_NUM>/reviews -q '.[-1].body'`
3. Also check the Linear ticket for Codex's rejection comment (it posts there too)
4. Fix every issue identified
5. Commit: `fix: address codex review feedback (iteration N)`
6. Push to the same branch (PR updates automatically — do NOT create a new PR)
7. Call `codex-reply` MCP tool with the saved `threadId`:

```
threadId: "<saved threadId from Phase 3>"
prompt: "Fixes pushed for the issues you identified. Please re-review PR #<NUMBER>.
Run the full merge-safety-review checklist again. Check that the specific issues you flagged are resolved."
```

8. Parse the new response and go back to Phase 4 (Decision)

### Phase 5: Escalation

If the review loop runs **5 iterations** without passing:

1. Do NOT keep trying — the issues may be fundamental
2. Update Linear ticket with a comment:
   "Automated review loop exhausted after 5 iterations. Last review feedback: <summary>. Needs human review."
3. Keep status as `In Review`
4. Keep the PR open and the worktree intact
5. Report to the user: "Task <ID> needs manual review. PR: <URL>"

## Guardrails

- **Never mark your own work as Done** — only Codex approval triggers Done
- **Never merge without Codex approval** — the PR must have an approved review
- **Never skip the build step** — if build fails, fix before pushing
- **Never create a new PR for fixes** — push to the same branch
- **Never delete the worktree on failure** — keep it for human inspection
- **Budget awareness** — if the loop is burning excessive tokens, escalate earlier
- **One task at a time** — this skill handles one task per invocation. For parallel tasks, the user runs multiple sessions.

## Error Handling

- **Codex MCP tool not available**: Stop. Tell user to add codex to `.mcp.json`: `{"codex": {"command": "codex", "args": ["mcp-server"]}}`
- **Linear MCP not available**: Stop. Tell user Linear MCP must be configured.
- **`gh` not authenticated**: Stop. Tell user to run `gh auth login`.
- **Build fails before PR**: Fix the build. Do not push broken code.
- **PR has merge conflicts**: `git fetch origin main && git rebase origin/main`, resolve conflicts, force-push, then re-request Codex review.
- **Codex times out or returns empty**: Retry once. If it fails again, escalate to user.

## Output

After completion (success or escalation), output a summary:

```
## Autopilot Summary

**Task:** TWO-215 — Add authentication flow
**Status:** Merged (or: Needs human review)
**PR:** https://github.com/owner/repo/pull/42
**Review iterations:** 2
**Linear:** Done (or: In Review — escalated)
```

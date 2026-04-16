# Checkd — Audit Fixes Plan

**Date:** 2026-04-16
**Status:** Proposed
**Linear project:** Proof — Transformation Photo Engine
**Source audit:** handoff context + systematic review of uncommitted `main`

## Purpose

Resolve the seven concerns surfaced by the capture-flow audit while cleaning up
the 38-file uncommitted blast radius currently sitting on `main`. Every concern
ships as its own Linear ticket, each in its own worktree, each reviewed by
Codex — per the workflow rule in `CLAUDE.md`.

The plan has two phases. Phase 0 triages the dirty main into reviewable PRs.
Phase 1 lands the actual fixes on top of that cleaned base. You cannot start
Phase 1 tickets until the relevant Phase 0 PR has merged, because every fix
depends on the refactored state machine.

---

## Phase 0 — Triage the dirty main

The current `main` has commingled changes across four concerns. Ship each as a
separate PR so Codex can review them independently.

Before starting, confirm which modified files predate the handoff pass. The
handoff noted ambiguity on `HomeView.swift`, `HistoryView.swift`,
`ComparisonView.swift`, `Theme.swift`, and `ContentView.swift`. A triage step
runs `git diff HEAD -- <file>` on each and decides: ship with Phase 0, or
defer to a separate "misc design changes" PR.

### PR-0a — Capture state machine refactor

**Scope:** the core Checkd flow change — new phases, burst-review sheet, edge
overlay, audio hook.

**Files (cherry-pick hunks only):**
- [ProofCapture/ViewModels/SessionViewModel.swift](ProofCapture/ViewModels/SessionViewModel.swift)
  — new `SessionPhase` cases (`locked`, `poseHold`), `beginLockSequence`,
  `confirmBurstSelection`, `redoBurst`, `captureEdgeState` (single `.noBody`
  case only — **fold `.lensBlocked` out during salvage**, not as a follow-up)
- [ProofCapture/Views/SessionView.swift](ProofCapture/Views/SessionView.swift)
  — locked/poseHold overlays, `BurstReviewSheet`, alert bindings
- [ProofCapture/Views/CaptureView.swift](ProofCapture/Views/CaptureView.swift)
  — edge-case overlay (single state), border-glow lock pulse
- [ProofCapture/Managers/AudioGuide.swift](ProofCapture/Managers/AudioGuide.swift)
  — `speakLockAchieved`, placeholder `speakEdgeState`
- [ProofCapture/Managers/PoseDetector.swift](ProofCapture/Managers/PoseDetector.swift)
  — TWO-515 ankle-confidence gate, TWO-517 hip-width signal, any calibration
  comments that reference `scripts/edge-cases/`

**Excluded (defer to later PRs):**
- `.lensBlocked` case — collapsed into a single `.noBody` state during salvage.
  See D2 rationale in the plan intro.
- Calibration scripts — ship in PR-0b
- Copy changes for Checkd rename — ship in PR-0c

**Known ship-with-bugs:** this PR ships the 6.8s commit window without
revalidation. That is TICKET-1's job, not PR-0a's. Shipping the refactor and
fixing the bug in separate PRs keeps each change small and reviewable.

**Verify:**
```bash
xcodebuild -project ProofCapture.xcodeproj -scheme ProofCapture \
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

**Manual smoke test:**
- Start a session, stand in frame, confirm green border → lock sound → 3s
  poseHold overlay → 3-2-1 countdown → burst → review sheet appears.
- Tap "Use this shot" → next pose. Tap "Redo" → returns to positioning.

### PR-0b — Calibration tooling

**Scope:** offline scoring harness and album audit workflow.

**Files:**
- [scripts/analyze-photo.swift](scripts/analyze-photo.swift) — existing
  improvements (structured output formats)
- [scripts/audit-calibration-album.swift](scripts/audit-calibration-album.swift)
  — **extended here, not in a follow-up**, to always emit seeded
  `suggested_*` columns by invoking the same scoring pipeline used by the CLI.
  The "reconciliation-only" version never ships; going straight to seeded is
  D3's decision.
- [scripts/calibration-manifest.template.csv](scripts/calibration-manifest.template.csv)
- [scripts/README.md](scripts/README.md)
- `scripts/edge-cases/` — renamed from `scripts/test-images/` with the same
  eleven files
- [.gitignore](.gitignore) — ignore `**/*.checkd-manifest.local.csv`
- [docs/engineering/checkd-lock-scoring-report.md](docs/engineering/checkd-lock-scoring-report.md)

**Verify:**
```bash
swift scripts/analyze-photo.swift --format csv scripts/edge-cases/*.jpg
swift scripts/audit-calibration-album.swift '/Users/imraan/Downloads/Client Pictures'
ls '/Users/imraan/Downloads/Client Pictures.checkd-manifest.local.csv'
```

Confirm the manifest has non-empty `suggested_pose`, `suggested_lockable`, and
`suggested_lighting_quality` columns on included rows.

### PR-0c — Proof → Checkd copy scrub

**Scope:** user-facing string rename only. No behavioural changes.

**Files (hunks only — copy changes, not logic):**
- [ProofCapture/Views/AuthView.swift](ProofCapture/Views/AuthView.swift)
- [ProofCapture/Views/ReviewView.swift](ProofCapture/Views/ReviewView.swift)
  (e.g. "Saved in Checkd" string at line 52)
- [ProofCapture/Views/Onboarding/WelcomeStep.swift](ProofCapture/Views/Onboarding/WelcomeStep.swift)
- [ProofCapture/Views/Onboarding/SetupGuideStep.swift](ProofCapture/Views/Onboarding/SetupGuideStep.swift)
- [ProofCapture/Views/Onboarding/PermissionStep.swift](ProofCapture/Views/Onboarding/PermissionStep.swift)
- [ProofCapture/Views/SettingsView.swift](ProofCapture/Views/SettingsView.swift)
- Any other view with a hard-coded "Proof" user-facing string

**Excluded:** bundle ID, module name, Xcode project name — those are a
separate, larger rename that needs explicit scoping.

**Verify:**
```bash
grep -rni "proof" ProofCapture/Views/ --include='*.swift' | grep -vi "ProofTheme"
```
Expect zero user-facing "Proof" strings remaining (ProofTheme design-token
references are fine).

### PR-0d (conditional) — Misc design changes

Any modified files that predate the handoff pass and don't belong to PR-0a/b/c.
Inventory during triage; create this PR only if there's > 0 hunks to ship. If
everything fits into 0a/b/c, skip this PR.

---

## Phase 1 — Fix tickets

Each ticket is a separate Linear issue, filed to the **Proof — Transformation
Photo Engine** project, implemented in its own worktree, reviewed by Codex
per the workflow rule.

### TICKET-1 — Revalidate environment during lock-to-burst sequence

**Priority:** Urgent
**Blocked by:** PR-0a merged
**Labels:** bug

**What:** The current flow commits to a ~6.8 second lock-to-burst window
(800ms lock + 3s poseHold + 3s countdown) without checking whether the
environment still supports a usable capture. User can step out of frame,
cover the lens, or the lighting can change, and the burst still fires.

**Files:**
- [ProofCapture/ViewModels/SessionViewModel.swift](ProofCapture/ViewModels/SessionViewModel.swift:236-270)

**Changes:**
1. Introduce a helper `environmentStillViable() -> Bool` that returns true
   iff: `poseDetector.bodyDetected && lightingAnalyzer.quality != .poor &&
   captureStatusMessage == nil`.
2. In `beginLockSequence`, replace the two bare `Task.sleep` calls with a
   polling loop that checks `environmentStillViable()` every 250ms across the
   800ms lock hold and the 3s poseHold. On failure, fall back with
   `phase = .positioning`, clear `captureEdgeState`, and fire an audio prompt
   ("Let's try that again — step back in").
3. In `beginCountdown`, add `environmentStillViable()` check at the top of
   each stride iteration. On failure, abort countdown, return to
   `.positioning`.
4. Allow a 500ms grace window for `bodyDetected == false` flicker — don't
   abort on single-frame Vision drops. Track `viabilityFailureStreak` and
   abort when it exceeds 2 consecutive checks.
5. Do NOT gate on `poseMatchesExpected` or `armsRelaxed` during poseHold —
   the user is actively changing pose.

**Acceptance criteria:**
- [ ] Build passes with `xcodebuild ... build CODE_SIGNING_ALLOWED=NO`
- [ ] Manual: start session, reach poseHold, step completely out of frame —
      session returns to `.positioning` within 1s, not at burst capture
- [ ] Manual: reach countdown, cover lens with finger — countdown aborts,
      returns to `.positioning`
- [ ] Manual: single-frame Vision drop (wave hand fast) does NOT abort —
      grace window absorbs it
- [ ] Regression: normal happy path still completes burst in ~6.8s end-to-end

**Verify:** build command plus the four manual scenarios above.

### TICKET-2 — Audio prompt for no-body edge state

**Priority:** High
**Blocked by:** PR-0a merged
**Labels:** feature

**What:** The no-body overlay at [CaptureView.swift:162-206](ProofCapture/Views/CaptureView.swift:162)
is screen-only, but the user is posed 2 meters from the phone and not looking
at the screen. Need audio parity.

**Files:**
- [ProofCapture/Managers/AudioGuide.swift](ProofCapture/Managers/AudioGuide.swift)
- [ProofCapture/ViewModels/SessionViewModel.swift](ProofCapture/ViewModels/SessionViewModel.swift:167-234)

**Changes:**
1. Add `AudioGuide.speakNoBodyEdge()` — plays a bundled clip. If a clip
   doesn't exist yet for the new copy, file an asset ticket; do not ship
   with `AVSpeechSynthesizer` because TWO-676 (commit fbc2fb3) removed it.
   Interim: use an existing "step back into frame" clip if present in
   `AudioGuide`'s bundled assets, else defer until the asset lands.
2. In `monitorReadiness`, fire the prompt once on entry to
   `captureEdgeState == .noBody` and repeat every 8 seconds while the state
   holds. Reset the repeat timer when `bodyDetected` becomes true.
3. Gate against overlap with `speakPositionGuidance` — if the edge state is
   active, position guidance is suppressed (already half-implemented via
   the `captureEdgeState != .lensBlocked` check at line 218; extend to cover
   the collapsed single state).

**Acceptance criteria:**
- [ ] Build passes
- [ ] Manual: cover camera for 10s → audio prompt fires within 8s, not
      concurrent with position guidance
- [ ] Manual: step back into frame → prompt stops, position guidance
      resumes on normal cadence
- [ ] No `AVSpeechSynthesizer` added (would regress TWO-676)

**Verify:** build command plus the two manual scenarios. Check asset
availability before starting — if no suitable clip exists, this ticket
blocks on an asset-creation sub-ticket.

### TICKET-3 — Script / app scoring parity test

**Priority:** Medium
**Blocked by:** PR-0b merged
**Labels:** test

**What:** [scripts/analyze-photo.swift](scripts/analyze-photo.swift) is a
665-line Swift file that duplicates the scoring logic from `LightingAnalyzer`
and `PoseDetector`. Any threshold change in the app must be manually
duplicated in the script. There is no parity check. This ticket adds one.

**Decision context:** the proper architectural fix is extracting scoring
into a shared Swift Package consumed by both app and CLI (D4 option A).
That is a larger refactor that blocks on the state-machine fixes
stabilising. This ticket is the interim: catch drift, don't prevent it.

**Files:**
- `scripts/parity-test.swift` (new)
- `scripts/README.md` — add parity-test section

**Changes:**
1. New `scripts/parity-test.swift` that:
   - Loads the 11 images from `scripts/edge-cases/`
   - Runs them through `scripts/analyze-photo.swift`'s `--format json` mode
   - Builds a lightweight equivalent of the app's analysis loop
     (`VNGeneratePersonSegmentationRequest` + `VNDetectHumanBodyPoseRequest`)
     by re-using the same helpers from the CLI
   - Diffs the two outputs per image across: brightness, downlight gradient,
     shadow contrast, backlit flag, orientation, joint count
   - Exits non-zero if any delta exceeds tolerance (e.g. brightness > 0.02,
     categorical fields must match exactly)
2. README.md: document how to run and what counts as a parity failure.

**Acceptance criteria:**
- [ ] `swift scripts/parity-test.swift` exits zero on the current edge-case
      set
- [ ] Artificially introduce a threshold change in `analyze-photo.swift`
      (e.g. brightness bound) → parity test fails with clear diff output
- [ ] Revert the change → test passes again

**Note:** because both pipelines are in Swift files that import the same
frameworks, the parity test is structural (do they agree on the same inputs)
rather than cross-language. The ideal — a shared module — is deferred as a
separate ticket once priorities settle.

**Verify:**
```bash
swift scripts/parity-test.swift
```

### TICKET-4 — Delete `ReviewView.onRetake` dead parameter

**Priority:** Low
**Blocked by:** PR-0c merged (avoid conflict with copy PR)
**Labels:** cleanup

**What:** `ReviewView` accepts an `onRetake` closure at
[ReviewView.swift:15, 24-30](ProofCapture/Views/ReviewView.swift:15) that is
stored as a private property and never invoked. SessionView.completeView
already handles retake-from-fresh-session via a separate path
([SessionView.swift:300-326](ProofCapture/Views/SessionView.swift:300)). The
parameter is cruft.

**Files:**
- [ProofCapture/Views/ReviewView.swift](ProofCapture/Views/ReviewView.swift)
- Any caller passing `onRetake` (grep first to confirm there are none)

**Changes:**
1. Remove the `onRetake` parameter from the first `init`.
2. Remove the stored `private let onRetake` property.
3. If any caller passes `onRetake:`, remove that argument.

**Acceptance criteria:**
- [ ] Build passes
- [ ] `grep -rn "onRetake" ProofCapture/` returns zero matches
- [ ] ReviewView opened from HistoryView still renders correctly
- [ ] Session-complete retake flow unchanged

**Verify:**
```bash
xcodebuild ... build CODE_SIGNING_ALLOWED=NO
grep -rn "onRetake" ProofCapture/
```

### TICKET-5 — Restore `countdownValue` user preference

**Priority:** Low
**Blocked by:** PR-0a merged
**Labels:** bug

**What:** The handoff pass hard-coded
[SessionViewModel.swift:28](ProofCapture/ViewModels/SessionViewModel.swift:28)
to `countdownValue = 3`, removing the previous `UserPreferences.countdownSeconds`
read. Users who configured a longer countdown in settings lost that preference
silently. Restore it.

**Files:**
- [ProofCapture/ViewModels/SessionViewModel.swift](ProofCapture/ViewModels/SessionViewModel.swift:256-270)
- Any `UserPreferences` declaration that needs reinstating (check git log for
  the removed definition)

**Changes:**
1. Restore `countdownValue = UserPreferences.countdownSeconds` at the top of
   `beginCountdown`.
2. Ensure `UserPreferences.countdownSeconds` has a sensible default (3s) so
   the new flow's default still matches what the refactor assumed.
3. If SettingsView had UI for this preference before the handoff, confirm
   it's still reachable; add a ticket for restoring the UI if not.

**Acceptance criteria:**
- [ ] Build passes
- [ ] Set `UserPreferences.countdownSeconds = 5` in SettingsView → countdown
      shows 5, 4, 3, 2, 1
- [ ] Default (no user change) → countdown shows 3, 2, 1

**Verify:** build command plus the two settings scenarios.

### TICKET-6 (optional) — Monitoring resume smoke test

**Priority:** Low
**Blocked by:** PR-0a merged
**Labels:** test

**What:** After `pauseSessionForRecovery` fires (background/inactive scene
phase), `phase` resets to `.positioning`. The `.task(id:)` at
[SessionView.swift:218-222](ProofCapture/Views/SessionView.swift:218) restarts
`monitorReadiness` when the `(pose, phase)` key changes. This should work but
has not been tested post-refactor.

**This is a manual verification, not necessarily a code change.**

**Test plan:**
1. Start session, reach `locked` or `poseHold`.
2. Background the app (press home).
3. Foreground the app.
4. Confirm: camera resumes, monitoring runs, lock is re-achieved when ready.

If step 4 fails, file a follow-up bug with repro steps. If it passes, this
ticket is closed with a note in the ticket body.

**Acceptance criteria:**
- [ ] Manual test performed on a physical device (not simulator — scene
      phase transitions behave differently)
- [ ] Result documented in the Linear ticket comment

---

## Out of scope

These surfaced during the audit but are not in this plan:

- **Bundle ID / module / Xcode project rename** from Proof to Checkd. This
  is a larger, separate renaming exercise that affects signing, TestFlight,
  App Store Connect, and the Supabase config. Needs its own plan.
- **Shared Swift Package for scoring logic** (D4 option A). Revisit after
  Phase 1 tickets land and the capture flow is stable. Worth its own design
  doc then.
- **`currentBurst` memory pressure** (7 UIImages held while user stalls on
  burst review sheet). Monitor in practice; only fix if users report lag on
  older hardware.
- **Album audit on-device** (run the analyzer inside the iOS app against the
  user's photo library rather than via a Mac CLI). Interesting but out of
  scope.

---

## Sequencing diagram

```
Phase 0 (parallel where files don't overlap):
  PR-0a ─┐
  PR-0b ─┼─> main
  PR-0c ─┘

Phase 1 (each fix after its Phase 0 dep):
  PR-0a ─> TICKET-1 (commit-window revalidation)
  PR-0a ─> TICKET-2 (audio edge prompt)
  PR-0a ─> TICKET-5 (countdownValue restore)
  PR-0a ─> TICKET-6 (monitoring smoke test)
  PR-0b ─> TICKET-3 (parity test)
  PR-0c ─> TICKET-4 (onRetake cleanup)
```

PR-0a, 0b, 0c can land in parallel. Their files don't overlap meaningfully.
Phase 1 tickets are mostly independent of each other and can run in parallel
agent teams if desired — the workflow rule supports this.

## Next step

If this plan is approved, the next action is to open the Phase 0 triage
worktrees (one per PR-0x) and begin cherry-picking hunks from the dirty
`main` into each. No fix work starts until Phase 0 merges.

The handoff's own uncommitted changes will be preserved — we are not
discarding work, just unbundling it.

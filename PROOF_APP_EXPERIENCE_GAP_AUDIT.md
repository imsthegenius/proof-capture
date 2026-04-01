# Proof App Experience Gap Audit

Date: 2026-03-31

Scope: static audit of the current `ProofCapture` checkout against the shipped code, the existing design specs in `docs/design`, and the bar of a premium, trustworthy, beautifully designed guided capture app.

## Bottom Line

The app is not failing because it lacks a few polish passes. It is failing because the current product is still built around mechanical completion instead of human confidence.

The checkout proves that the team has implemented a deterministic capture workflow, but it does not yet deliver a convincing product experience. The app currently feels like:

- a camera utility with premium-dark styling
- a workflow that optimizes for "three poses captured"
- a thin wrapper over heuristics, status chips, and list screens

It does not yet feel like:

- a private, premium weekly ritual
- a coach-like guided experience
- a trustworthy artifact the user would genuinely want to repeat every week

That is the core gap.

## Audit Method

This audit reviewed the current managed checkout in:

- `ProofCapture/ContentView.swift`
- `ProofCapture/Theme/Theme.swift`
- `ProofCapture/Views/Onboarding/*`
- `ProofCapture/Views/AuthView.swift`
- `ProofCapture/Views/HomeView.swift`
- `ProofCapture/Views/SessionView.swift`
- `ProofCapture/Views/CaptureView.swift`
- `ProofCapture/Views/PoseGuideOverlay.swift`
- `ProofCapture/Views/ReviewView.swift`
- `ProofCapture/Views/HistoryView.swift`
- `ProofCapture/Views/ComparisonView.swift`
- `ProofCapture/Views/SettingsView.swift`
- `ProofCapture/Managers/PoseDetector.swift`
- `ProofCapture/Managers/LightingAnalyzer.swift`
- `ProofCapture/Managers/AudioGuide.swift`
- `ProofCapture/Models/CaptureTrustRules.swift`

This audit also checked the current design intent in:

- `docs/design/checkd-v1-acceptance-criteria.md`
- `docs/design/checkd-v1-onboarding-voice-account-spec.md`
- `docs/design/checkd-first-run-account-ui-motion-package.md`

## North Star

A beautifully designed version of this app should feel like a calm, high-trust studio ritual. The product should reduce embarrassment, uncertainty, and setup friction. It should make the user feel guided, protected, and visually rewarded, not monitored by a brittle rules engine.

That requires four things at the same time:

1. A strong product promise
2. A live capture experience that feels intelligent and humane
3. A visual system with real identity and emotional range
4. A progress model that turns saved sessions into something meaningful

The current app is weak on all four.

## P0 Gaps Blocking A Beautiful App

### 1. The app still optimizes for workflow correctness, not product quality

The current implementation is very focused on the logic of progressing from onboarding to auth to home to session to save. That is visible in `ProofCapture/ContentView.swift`, `ProofCapture/Views/SessionView.swift`, and `ProofCapture/Models/CaptureTrustRules.swift`.

What is missing:

- no explicit product-quality gate in the UI itself
- no concept of "is this capture actually flattering, useful, and confidence-building?"
- no distinction between "the pose classifier accepted this" and "this is a good weekly record"
- no product artifact that makes the saved result feel valuable

Why this matters:

The app can be internally coherent and still feel bad. Right now the codebase is much better at deciding whether a capture is valid than whether the experience is good.

### 2. The live capture experience is too thin to earn trust

`ProofCapture/Views/CaptureView.swift` and `ProofCapture/Views/PoseGuideOverlay.swift` reduce live guidance to:

- a full-screen camera feed
- a border glow
- a live feedback chip
- a thin body-outline rectangle
- a pose label

This is not enough.

What is missing:

- no strong silhouette target for each pose
- no obvious "you are here vs target" framing system
- no visual explanation of why the app is rejecting the current stance
- no escalation from low confidence to higher-touch guidance
- no premium transition from positioning to lock to capture
- no sense of ceremony or reassurance at the moment of exposure

Why this matters:

The user is being asked to trust an invisible judging system. The interface does not do enough to explain or soften that judgment.

### 3. The pose and lighting logic are still too brittle to be the backbone of the experience

The heuristics in `ProofCapture/Managers/PoseDetector.swift` and `ProofCapture/Managers/LightingAnalyzer.swift` are clear and deterministic, but they are still simplistic for something this trust-sensitive.

Observed examples:

- position quality is still mostly body height and horizontal centering
- orientation is inferred from a small set of joints and torso widths
- arm relaxation is inferred from hard wrist and elbow thresholds
- lighting quality is still threshold-driven despite the more advanced pipeline
- `CaptureTrustRules` remains intentionally minimal

What is missing:

- confidence bands that translate into UI states the user can understand
- pose-specific tolerance tuning grounded in real capture samples
- a stronger separation between "acceptable for automation" and "beautiful enough to keep"
- a recovery model for ambiguous frames beyond generic correction text

Why this matters:

If the heuristics are borderline, the UI has to absorb that uncertainty with great guidance. Right now both sides are too thin at once.

### 4. The home and post-capture surfaces are underdesigned and emotionally flat

`ProofCapture/Views/HomeView.swift`, `ProofCapture/Views/ReviewView.swift`, `ProofCapture/Views/HistoryView.swift`, and `ProofCapture/Views/ComparisonView.swift` are clean, but they are too bare and too utility-oriented.

The current product after first run gives the user:

- a minimal home with a count, a draft summary, or a setup tip
- a history list
- a compare mode
- a basic final review grid

What is missing:

- no compelling dashboard or weekly ritual anchor
- no sense of momentum, streak, cadence, or progress story
- no "why should I care?" framing after a session is saved
- no beautifully presented result artifact
- no trend interpretation, summary, or reflection layer
- no visual distinction between "storage screen" and "meaningful progress archive"

Why this matters:

If the saved output feels emotionally empty, the product never graduates from "camera workflow" to "habit-forming experience."

## P1 Product And UX Gaps

### 5. Onboarding explains mechanics, but not enough confidence

The onboarding flow in `ProofCapture/Views/Onboarding/WelcomeStep.swift`, `SetupGuideStep.swift`, and `PermissionStep.swift` follows the documented wizard contract well enough, but it still feels like a checklist rather than a premium initiation experience.

What is missing:

- no clear before/after understanding of what a great result looks like
- no proof that the guided system can be trusted
- no visual preview of the target framing quality
- no reassurance for vulnerable moments like partial undress, room mess, or self-consciousness
- no explanation of why this ritual matters week to week beyond "weekly check-in"

Why this matters:

The onboarding should make the user feel safe and prepared. Right now it mostly makes them feel instructed.

### 6. Auth and Account are coherent, but still too generic

`ProofCapture/Views/AuthView.swift` and `ProofCapture/Views/SettingsView.swift` meet the narrower v1 product contract, but they are still not beautiful surfaces.

What is missing:

- auth still reads as a sign-in wall more than an activation moment
- account still reads like settings cards with status text
- backup trust is explained, but not elegantly
- there is no account identity warmth, privacy confidence, or ownership feeling
- no strong summary card that tells the user what this product is doing for them

Why this matters:

High-trust products do not just inform. They reassure. The current surfaces explain backup state, but they do not create real peace of mind.

### 7. Text-only mode is supported, but not truly designed

The guidance split in `ProofCapture/Views/GuideModeSelector.swift`, `PermissionStep.swift`, `SettingsView.swift`, and `AudioGuide.swift` is functional, but the app still feels optimized for the voice path with text as fallback.

What is missing:

- no deliberately designed text-first live experience
- no richer visual guidance when voice is off
- no alternate pacing or larger instructional surfaces for silent capture
- no difference in the capture UI hierarchy when text becomes the primary guide

Why this matters:

If text-only is a first-class mode, it needs its own product design, not just fewer sounds.

## P1 Visual Design Gaps

### 8. The visual system is too narrow and repetitive

The theme in `ProofCapture/Theme/Theme.swift` is disciplined, but it is not enough by itself to create a memorable product.

Current visual language:

- warm near-black background
- warm white accent
- thin SF typography
- rounded dark cards
- capsule buttons

What is missing:

- no signature typographic moment beyond ultra-light system text
- no strong art direction
- no hierarchy of surfaces beyond dark rectangle vs darker rectangle
- no meaningful use of scale, glow, depth, framing, or imagery
- no distinctive iconography or illustration system
- no premium result presentation that rewards the user after effort

Why this matters:

The app has a palette, but not a real visual identity. It looks restrained, not resolved.

### 9. Motion exists, but it does not yet create one coherent product rhythm

The motion constants in `ProofCapture/Theme/Theme.swift` are helpful, and the code already uses them across onboarding, auth, and session flow. But the experience still reads as a collection of local transitions, which matches the warning in `docs/design/checkd-first-run-account-ui-motion-package.md`.

What is missing:

- no single emotional rhythm across first run, live guidance, save completion, and history review
- no meaningful "handoff" moments between states
- no strong arrival or completion scenes
- save completion still reads as a UI state change, not an earned moment

Why this matters:

In a beautiful app, motion clarifies intention and trust. Here it mostly softens state changes.

## P1 Information Architecture Gaps

### 10. The product has no strong central object beyond "a session"

The app architecture revolves around `PhotoSession`, which is useful technically. But as a product concept, "session" is too internal.

User-facing surfaces still revolve around:

- start or resume check-in
- save check-in
- view history
- compare sessions

What is missing:

- no stronger central object like a weekly record, progress entry, or check-in artifact
- no narrative relationship between current week and prior weeks
- no sense of continuity or accumulation

Why this matters:

Beautiful products usually make the core artifact legible. This app still makes the workflow more legible than the artifact.

## P2 Specific Surface Notes

### Home

`ProofCapture/Views/HomeView.swift`

Strengths:

- simple
- calm
- draft resume logic is clear

Gaps:

- too much dead space without emotional purpose
- no hero message that changes based on account, streak, or latest progress
- no visual storytelling around the last saved record
- "History" is presented like a utility destination, not a meaningful archive

### Session

`ProofCapture/Views/SessionView.swift`

Strengths:

- deterministic automatic flow
- draft resume behavior is better than before

Gaps:

- too many trust-critical states are invisible or under-explained
- completion still ends in a mechanical save action
- retake is available, but final review is still a functional grid instead of a crafted decision surface

### Review

`ProofCapture/Views/ReviewView.swift`

Gaps:

- no strong summary of what was captured
- no quality explanation
- no product language around "this is your weekly record"
- delete affordance is more emotionally explicit than the value of keeping the session

### History and Compare

`ProofCapture/Views/HistoryView.swift`
`ProofCapture/Views/ComparisonView.swift`

Gaps:

- archive is list-first, not insight-first
- compare is useful, but visually raw
- no trend cues, highlight framing, or reason to revisit old sessions beyond manual comparison

### Account

`ProofCapture/Views/SettingsView.swift`

Gaps:

- correct scope, weak presentation
- no premium account summary
- no deeply reassuring privacy explanation
- no stronger distinction between local draft behavior and cloud-backed completed records

## Mismatch Against Existing Design Intent

The app is not just below a subjective beauty bar. It is still below the repo's own intended direction.

Key mismatches against `docs/design/checkd-first-run-account-ui-motion-package.md`:

- onboarding still feels screen-by-screen instead of like one wizard shell
- permission recovery is still an inline status block, but not yet a truly designed blocked state
- auth still feels like a context jump instead of a polished handoff
- save completion still lacks a convincing reveal-and-hold confirmation moment

Key weaknesses relative to `docs/design/checkd-v1-acceptance-criteria.md`:

- the app is good at preserving deterministic trust rules, but not at making the user feel that trust
- the first-time capture clarity checklist is only partially achieved because the experience still relies heavily on terse corrective copy and invisible heuristics

## What A Beautiful Version Would Need

### Product

- reframe the product around a valuable weekly record, not just a completed session
- define the emotional job: calm setup, coached capture, confident save, meaningful archive
- separate "capture readiness" from "worthy to keep"

### Live Guidance

- replace the thin bounding box with pose-aware target framing
- add richer visual coaching for distance, angle, and body alignment
- design explicit confidence states for low, medium, and high certainty
- make capture lock feel unmistakable and rewarding

### Visual System

- strengthen typography beyond default ultra-light SF usage
- introduce a more distinctive component system
- design a premium result card / saved record presentation
- reduce repeated dark-card sameness

### Post-Capture Product

- turn saved output into a meaningful artifact
- redesign history as a progress archive, not a storage list
- make compare mode editorial and intentional instead of side-by-side raw images only

### Trust

- explain what the app is checking and why
- design better failure recovery when confidence is low
- avoid pretending the heuristic engine is more certain than it is

## Recommended Execution Order

### Phase 1: Product and experience reset

- define the core artifact and the emotional promise
- write the quality bar for "beautiful enough to save"
- redesign the home, live capture, and final save journey before adding more QA churn

### Phase 2: Live capture redesign

- pose-aware framing overlays
- better confidence model
- clearer corrective guidance
- stronger capture-lock and save-completion moments

### Phase 3: Archive and value layer

- redesign history and compare
- add narrative progress framing
- create a result surface the user actually wants to revisit

### Phase 4: Visual system refinement

- typography
- component system
- image presentation
- motion cohesion

## Final Assessment

The current app is an implementable v1 workflow, not a beautifully designed product.

Its biggest weakness is not that the code is messy. Its biggest weakness is that it treats successful capture as the end of the job. For this category, successful capture is only the beginning. The real job is making the user feel guided, flattering, safe, and proud of the result.

That job is still largely unfulfilled in the current checkout.

# ORB-15 Source Audit

Source-based audit and P0 fix pass for Checkd's guided capture flow.

## Scope

- Repo: `ProofCapture`
- Canonical flow: live positioning -> readiness lock -> automatic countdown -> burst capture -> 2 second auto-preview -> next pose
- Locked decisions applied here: front/side/back sequence, left-facing side pose, final-review retakes, local draft resume, iOS 17 floor, iPhone 12+ QA floor

## Findings And Fixes

### 1. Countdown timing and readiness lock were wrong

- `ProofCapture/Views/SessionView.swift`
- `ProofCapture/Managers/AudioGuide.swift`
- The old flow waited far longer than the intended 300ms readiness lock and ran countdown audio before the visual countdown, so the screen and sound were not synchronized.
- The shipped fix moves countdown timing into `SessionView`, uses a 300ms readiness lock, and drives the visible number plus countdown tone in the same loop.

### 2. Completed sessions were not marked complete and drafts did not exist

- `ProofCapture/Models/PhotoSession.swift`
- `ProofCapture/Views/SessionView.swift`
- `ProofCapture/Views/HomeView.swift`
- `ProofCapture/Views/HistoryView.swift`
- `ProofCapture/Services/SyncManager.swift`
- The old flow only created a `PhotoSession` when "Save to Camera Roll" was tapped, left `isComplete` false, discarded in-progress work on exit, and mixed incomplete work into history/sync behavior.
- The shipped fix persists the session state during capture, stores the resume pose, marks finished sessions complete, keeps drafts local, exposes resume from Home, filters History to completed sessions, and only syncs completed sessions.

### 3. Default camera behavior did not match the mirror-first guided capture model

- `ProofCapture/Managers/CameraManager.swift`
- `ProofCapture/Views/CameraPreview.swift`
- `ProofCapture/Views/CaptureView.swift`
- The old camera manager defaulted to the back camera and never configured preview mirroring or portrait rotation for the live guided flow.
- The shipped fix defaults to the front camera, mirrors the live preview, keeps the analysis stream unmirrored, and aligns photo/video connections for portrait capture.

### 4. Session interruption and permission recovery were missing

- `ProofCapture/Managers/CameraManager.swift`
- `ProofCapture/Views/SessionView.swift`
- The old capture path assumed camera access and uninterrupted execution. Backgrounding, camera conflicts, runtime errors, and permission revocation had no recovery path.
- The shipped fix adds authorization checks, interruption observers, retry and Settings recovery UI, background pause/resume handling, and draft persistence across recovery states.

### 5. Lighting analysis still drifted toward whole-frame exposure shortcuts

- `ProofCapture/Managers/LightingAnalyzer.swift`
- The old implementation segmented the person but still measured exposure from whole-frame averages and let masked black background skew body-region brightness.
- The shipped fix normalizes masked brightness by person-mask coverage so exposure, downlighting, shadow contrast, and backlighting are body-focused.

## Verification

- Build verified with:
  - `xcodebuild -project ProofCapture.xcodeproj -scheme ProofCapture -destination 'id=59443530-7762-430A-8B80-7E371A2928E3' build`
- Result: `BUILD SUCCEEDED`

## Remaining External Gates

- No remaining product or design blockers were found for this P0 pass.
- QA still needs the ORB-11 matrix run on the locked release floor: iPhone 12 or newer, with physical-device coverage for permissions, interruptions, burst capture, retakes, save path, and weekly repeat use.

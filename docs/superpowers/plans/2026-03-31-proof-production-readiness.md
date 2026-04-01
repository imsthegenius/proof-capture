# Proof Capture — Production Readiness Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Take Proof Capture from "working prototype" to "premium, production-quality iOS app" — fixing all bugs, implementing missing spec features, elevating the design, and adding micro-animations that make the capture ritual feel guided, safe, and rewarding.

**Architecture:** The app follows a flat SwiftUI architecture — views own state machines via `@State`, managers are `@Observable` classes. No MVVM, no coordinators. We preserve this pattern but extract SessionView's 707-line monolith into a proper ViewModel, and add missing UI layers (text guidance overlay, capture flash, pose transitions, completion ceremony). The camera pipeline (CameraManager → SampleBufferMultiplexer → PoseDetector + LightingAnalyzer) is solid and stays as-is.

**Tech Stack:** Swift 5.9, SwiftUI (iOS 17+), AVFoundation, Vision, SwiftData, Supabase (supabase-swift 2.x), StoreKit 2

---

## Phase 1: Critical Bugs (ship-blockers)

These are functional bugs that produce incorrect behavior right now.

---

### Task 1: Fix PoseGuideOverlay Y-axis flip

The body outline renders at the wrong vertical position. Vision uses 0,0 = bottom-left, but the overlay maps directly to UIKit's 0,0 = top-left coordinate space without flipping Y.

**Files:**
- Modify: `ProofCapture/Views/PoseGuideOverlay.swift:40-47`

- [ ] **Step 1: Fix the Y-axis inversion in `normalizedToView`**

```swift
// In PoseGuideOverlay.swift, replace the normalizedToView method:

private func normalizedToView(_ normalized: CGRect, in size: CGSize) -> CGRect {
    CGRect(
        x: normalized.origin.x * size.width,
        y: (1.0 - normalized.origin.y - normalized.height) * size.height,
        width: normalized.width * size.width,
        height: normalized.height * size.height
    )
}
```

The key change: `y: (1.0 - normalized.origin.y - normalized.height) * size.height` flips the Vision coordinate space to UIKit's coordinate space. `1.0 - origin.y` flips the point, and subtracting `height` accounts for the rect's anchor at its top-left in UIKit vs bottom-left in Vision.

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project ProofCapture.xcodeproj -scheme ProofCapture -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add ProofCapture/Views/PoseGuideOverlay.swift
git commit -m "fix: flip Y-axis in PoseGuideOverlay — Vision coords to UIKit"
```

---

### Task 2: Fix dead `UserPreferences.genderRaw` key mismatch

`UserPreferences` defines the key as `"genderRaw"`, but `AudioGuide`, `SettingsView`, and `PermissionStep` all read/write `"userGender"`. The `UserPreferences.genderRaw` accessor is dead code writing to a key nobody reads.

**Files:**
- Modify: `ProofCapture/Models/UserPreferences.swift`

- [ ] **Step 1: Read the current UserPreferences file**

Read `ProofCapture/Models/UserPreferences.swift` to confirm the key mismatch.

- [ ] **Step 2: Align the key to `"userGender"`**

In `UserPreferences.swift`, change the `genderRaw` static property to read/write the `"userGender"` key that the rest of the app uses:

```swift
static var genderRaw: Int {
    get { UserDefaults.standard.integer(forKey: "userGender") }
    set { UserDefaults.standard.set(newValue, forKey: "userGender") }
}
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -project ProofCapture.xcodeproj -scheme ProofCapture -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add ProofCapture/Models/UserPreferences.swift
git commit -m "fix: align UserPreferences.genderRaw to 'userGender' key used by AudioGuide/Settings"
```

---

### Task 3: Wire Supabase credentials through xcconfig → Info.plist

The anon key is hardcoded as a string literal in `SupabaseClient.swift`. The project already has a `Supabase.xcconfig` (gitignored) and `Info.plist` — just not wired.

**Files:**
- Modify: `ProofCapture/Services/SupabaseClient.swift`
- Modify: `ProofCapture/Info.plist` (add SUPABASE_URL and SUPABASE_ANON_KEY keys)
- Verify: `Supabase.xcconfig` exists and is gitignored

- [ ] **Step 1: Check xcconfig and gitignore**

```bash
cat ProofCapture/Supabase.xcconfig 2>/dev/null || echo "NOT FOUND"
grep -n "xcconfig" .gitignore
```

- [ ] **Step 2: Add keys to Info.plist if missing**

Add these keys to `Info.plist` (under the dict root):

```xml
<key>SUPABASE_URL</key>
<string>$(SUPABASE_URL)</string>
<key>SUPABASE_ANON_KEY</key>
<string>$(SUPABASE_ANON_KEY)</string>
```

- [ ] **Step 3: Ensure xcconfig has the values**

Create or update `Supabase.xcconfig`:

```
SUPABASE_URL = https://pbntloqfayegjamsvmpy.supabase.co
SUPABASE_ANON_KEY = eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBibnRsb3FmYXllZ2phbXN2bXB5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ2MTQ2NjQsImV4cCI6MjA5MDE5MDY2NH0.QxStEweDTRIefAl8bWxlaRzo8QXOIUMwrlIJgcjBPTE
```

- [ ] **Step 4: Rewrite SupabaseClient.swift to read from Info.plist**

```swift
import Supabase
import Foundation

enum AppSupabase {
    static let client: SupabaseClient = {
        guard let urlString = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String,
              let url = URL(string: urlString),
              let key = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String else {
            fatalError("Missing SUPABASE_URL or SUPABASE_ANON_KEY in Info.plist. Check Supabase.xcconfig.")
        }

        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: .init(
                    redirectToURL: URL(string: "com.proof.capture://auth-callback"),
                    flowType: .pkce
                )
            )
        )
    }()
}
```

- [ ] **Step 5: Build and verify**

Run: `xcodebuild -project ProofCapture.xcodeproj -scheme ProofCapture -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add ProofCapture/Services/SupabaseClient.swift ProofCapture/Info.plist
git commit -m "fix: wire Supabase credentials through xcconfig/Info.plist instead of hardcoding"
```

---

### Task 4: Fix ComparisonView TabView/picker desync

When the user swipes the TabView, `selectedPose` updates via the `$selectedPose` binding — but the picker buttons also set `selectedPose` with `withAnimation`. The issue: swiping updates `selectedPose` AFTER the page settles, but the picker underline animates immediately. Add `.onChange(of: selectedPose)` synchronization to keep both in lockstep.

**Files:**
- Modify: `ProofCapture/Views/ComparisonView.swift:22-29`

- [ ] **Step 1: Remove the animation modifier from the TabView that fights the binding**

In `ComparisonView.swift`, the `.animation(.easeInOut(duration: 0.3), value: selectedPose)` on the TabView fights with the TabView's internal page-change animation. Remove it:

```swift
// Replace the TabView block (lines 22-29) with:
TabView(selection: $selectedPose) {
    ForEach(Pose.allCases) { pose in
        comparisonColumns(pose: pose)
            .tag(pose)
    }
}
.tabViewStyle(.page(indexDisplayMode: .never))
```

The picker buttons' `withAnimation` already handles the picker-initiated transitions. The TabView handles swipe transitions internally. Adding `.animation` on the TabView causes double-animation conflicts.

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project ProofCapture.xcodeproj -scheme ProofCapture -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add ProofCapture/Views/ComparisonView.swift
git commit -m "fix: remove conflicting animation modifier from ComparisonView TabView"
```

---

### Task 5: Replace print statements with structured logging

`SyncManager` and `AuthManager` use `print()` for error logging. Replace with `os.Logger` for proper production logging.

**Files:**
- Modify: `ProofCapture/Services/SyncManager.swift:68,122`
- Modify: `ProofCapture/Services/AuthManager.swift` (find print statements)

- [ ] **Step 1: Read AuthManager to find print statements**

Read `ProofCapture/Services/AuthManager.swift` and note line numbers of `print(` calls.

- [ ] **Step 2: Add os.Logger to SyncManager**

At the top of `SyncManager.swift`, add:

```swift
import os

private let logger = Logger(subsystem: "com.proof.capture", category: "SyncManager")
```

Replace `print("Restore failed: \(error)")` with:

```swift
logger.error("Restore failed: \(error.localizedDescription)")
```

Replace `print("Upload failed: \(error)")` with:

```swift
logger.error("Upload failed: \(error.localizedDescription)")
```

- [ ] **Step 3: Add os.Logger to AuthManager**

Same pattern — add `import os` and a `Logger`, replace `print()` calls with `logger.error()`.

- [ ] **Step 4: Build and verify**

Run: `xcodebuild -project ProofCapture.xcodeproj -scheme ProofCapture -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add ProofCapture/Services/SyncManager.swift ProofCapture/Services/AuthManager.swift
git commit -m "fix: replace print() with os.Logger for production-safe logging"
```

---

## Phase 2: Missing Spec Features

Features documented in CLAUDE.md or PRD that have no implementation.

---

### Task 6: Add pose-transition and session-complete audio cues

The audio guide speaks the initial pose prompt but is silent during pose advances and session completion. The PRD says audio is the primary UX — app must work when user can't see screen.

**Files:**
- Modify: `ProofCapture/Managers/AudioGuide.swift` (add new methods)
- Modify: `ProofCapture/Views/SessionView.swift` (wire transition calls)

- [ ] **Step 1: Add transition and completion methods to AudioGuide**

In `AudioGuide.swift`, add after the `speakPositionGuidance` method:

```swift
/// Speaks a transition cue when advancing to the next pose.
func speakPoseTransition(from completed: Pose, to next: Pose) async {
    guard mode == .voice else { return }
    let text: String
    switch next {
    case .front:
        text = "Now turn to face the camera."
    case .side:
        text = "Great. Now turn to show your left side."
    case .back:
        text = "Good. Now turn away from the camera."
    }
    await speak(text)
}

/// Speaks the session completion cue.
func speakSessionComplete() async {
    guard mode == .voice else { return }
    await speak("All three poses captured. You're done.")
}
```

- [ ] **Step 2: Wire transition cue into SessionView.autoAdvanceAfterPreview**

In `SessionView.swift`, in the `autoAdvanceAfterPreview()` method, replace the `if let next = currentPose.next` block (around line 577):

```swift
if let next = currentPose.next {
    let completed = currentPose
    currentPose = next
    poseDetector.targetPose = next
    phase = .positioning
    await audioGuide.speakPoseTransition(from: completed, to: next)
} else {
    phase = .complete
    persistSessionState()
    await audioGuide.speakSessionComplete()
}
```

This replaces the previous `await audioGuide.speak(currentPose.audioPrompt)` with the richer transition cue.

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -project ProofCapture.xcodeproj -scheme ProofCapture -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add ProofCapture/Managers/AudioGuide.swift ProofCapture/Views/SessionView.swift
git commit -m "feat: add pose-transition and session-complete audio cues"
```

---

### Task 7: Add on-screen text guidance overlay for text-only / deaf users

When `guidanceMode == 1` (text-only), the capture view shows no positioning text beyond "Step into frame." The `PoseDetector.feedback` string already has rich guidance ("Turn to face the camera", "Move closer", "Relax your arms") but it's never displayed. Add a persistent text overlay in CaptureView that shows `poseDetector.feedback` and `lightingAnalyzer.feedback`.

**Files:**
- Modify: `ProofCapture/Views/CaptureView.swift` (add text guidance overlay)

- [ ] **Step 1: Add a guidance mode check and feedback overlay**

In `CaptureView.swift`, add `@AppStorage("guidanceMode") private var guidanceMode = 0` at the top of the struct (after the existing properties).

Then, inside the `body` ZStack, after the "Step into frame" text block and before the pose label VStack, add:

```swift
// On-screen text guidance — always visible in text-only mode,
// or when body is detected (replaces "Step into frame")
if guidanceMode == 1 && poseDetector.bodyDetected {
    VStack(spacing: ProofTheme.spacingSM) {
        Text(poseDetector.feedback)
            .font(.system(size: 20, weight: .light))
            .foregroundStyle(ProofTheme.overlayText)
            .multilineTextAlignment(.center)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.3), value: poseDetector.feedback)

        if lightingAnalyzer.quality != .good {
            Text(lightingAnalyzer.feedback)
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(ProofTheme.overlayText.opacity(0.7))
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: lightingAnalyzer.feedback)
        }
    }
    .padding(.horizontal, ProofTheme.spacingLG)
    .padding(.vertical, ProofTheme.spacingMD)
    .background(ProofTheme.overlayPill)
    .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusMD))
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project ProofCapture.xcodeproj -scheme ProofCapture -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add ProofCapture/Views/CaptureView.swift
git commit -m "feat: add on-screen text guidance overlay for text-only/deaf users"
```

---

### Task 8: Add capture flash animation

When burst capture starts, there's a plain "Hold still" overlay with no visual ceremony. Add a white flash effect at the moment of capture — a brief opacity pulse that simulates a camera flash, making the capture moment feel intentional.

**Files:**
- Modify: `ProofCapture/Views/SessionView.swift` (add flash state + overlay)

- [ ] **Step 1: Add flash state variable**

In `SessionView.swift`, add to the `@State` block (around line 28):

```swift
@State private var showCaptureFlash = false
```

- [ ] **Step 2: Replace the capturingOverlay with a flash-enabled version**

Replace the `capturingOverlay` computed property:

```swift
private var capturingOverlay: some View {
    ZStack {
        // White flash — fades in fast, fades out slower
        Color.white
            .opacity(showCaptureFlash ? 0.6 : 0)
            .ignoresSafeArea()
            .animation(.easeOut(duration: 0.15), value: showCaptureFlash)

        // Semi-transparent overlay after flash
        Color.black.opacity(showCaptureFlash ? 0 : 0.4)
            .ignoresSafeArea()
            .animation(.easeIn(duration: 0.2).delay(0.15), value: showCaptureFlash)

        Text("Hold still")
            .font(.system(size: 20, weight: .light))
            .foregroundStyle(ProofTheme.overlayText)
            .opacity(showCaptureFlash ? 0 : 1)
            .animation(.easeIn(duration: 0.2).delay(0.15), value: showCaptureFlash)
    }
    .task {
        showCaptureFlash = true
        try? await Task.sleep(for: .milliseconds(150))
        showCaptureFlash = false
    }
}
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -project ProofCapture.xcodeproj -scheme ProofCapture -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add ProofCapture/Views/SessionView.swift
git commit -m "feat: add white flash animation at moment of capture"
```

---

### Task 9: Add session-complete entrance animations

The complete view appears with no fanfare — photos just pop in. Add a staggered scale+fade entrance for each photo, and a drawing animation for "Session Complete" text.

**Files:**
- Modify: `ProofCapture/Views/SessionView.swift` (completeView section)

- [ ] **Step 1: Add animation state variables**

Add to the `@State` block:

```swift
@State private var completeTitleVisible = false
@State private var completePhotosVisible: [Pose: Bool] = [:]
```

- [ ] **Step 2: Update the completeView with staggered animations**

Replace the `completeView` computed property:

```swift
private var completeView: some View {
    VStack(spacing: ProofTheme.spacingLG) {
        Text("Session Complete")
            .font(.system(size: 24, weight: .light))
            .foregroundStyle(ProofTheme.textPrimary)
            .opacity(completeTitleVisible ? 1 : 0)
            .offset(y: completeTitleVisible ? 0 : 8)

        HStack(spacing: ProofTheme.spacingMD) {
            ForEach(Array(Pose.allCases.enumerated()), id: \.element) { index, pose in
                VStack(spacing: ProofTheme.spacingSM) {
                    if let image = capturedImages[pose] {
                        Button {
                            retakePose = pose
                        } label: {
                            ZStack(alignment: .bottom) {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusMD))

                                Text("Tap to retake")
                                    .font(.system(size: 11, weight: .light))
                                    .foregroundStyle(ProofTheme.overlayText.opacity(0.6))
                                    .padding(.vertical, ProofTheme.spacingXS)
                                    .frame(maxWidth: .infinity)
                                    .background(.black.opacity(0.4))
                                    .clipShape(UnevenRoundedRectangle(
                                        bottomLeadingRadius: ProofTheme.radiusMD,
                                        bottomTrailingRadius: ProofTheme.radiusMD
                                    ))
                            }
                        }
                        .accessibilityLabel("Retake \(pose.title) photo")
                        .opacity(completePhotosVisible[pose] == true ? 1 : 0)
                        .scaleEffect(completePhotosVisible[pose] == true ? 1.0 : 0.92)
                    } else {
                        RoundedRectangle(cornerRadius: ProofTheme.radiusMD)
                            .fill(ProofTheme.surface)
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                    }

                    Text(pose.title)
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(ProofTheme.textTertiary)
                        .opacity(completePhotosVisible[pose] == true ? 1 : 0)
                }
            }
        }
        .padding(.horizontal, ProofTheme.spacingMD)
    }
    .task {
        // Staggered entrance: title first, then photos one by one
        withAnimation(.easeOut(duration: 0.5)) {
            completeTitleVisible = true
        }
        for (index, pose) in Pose.allCases.enumerated() {
            try? await Task.sleep(for: .milliseconds(150 + index * 120))
            withAnimation(.easeOut(duration: 0.4)) {
                completePhotosVisible[pose] = true
            }
        }
    }
    .alert("Retake \(retakePose?.title ?? "") photo?", isPresented: Binding(
        get: { retakePose != nil },
        set: { if !$0 { retakePose = nil } }
    )) {
        Button("Cancel", role: .cancel) { retakePose = nil }
        Button("Retake") {
            if let pose = retakePose {
                Task { await retakeFromComplete(pose) }
            }
        }
    } message: {
        Text("The camera will reopen for this pose only.")
    }
}
```

- [ ] **Step 3: Reset animation state when re-entering complete view from retake**

In `retakeFromComplete(_:)`, add at the top of the method:

```swift
completeTitleVisible = false
completePhotosVisible = [:]
```

- [ ] **Step 4: Build and verify**

Run: `xcodebuild -project ProofCapture.xcodeproj -scheme ProofCapture -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add ProofCapture/Views/SessionView.swift
git commit -m "feat: staggered entrance animations for session-complete photos"
```

---

## Phase 3: Extract SessionView ViewModel

SessionView is 707 lines mixing UI, state machine logic, persistence, and audio coordination. Extract business logic into a dedicated ViewModel.

---

### Task 10: Create SessionViewModel — extract state machine + capture logic

**Files:**
- Create: `ProofCapture/ViewModels/SessionViewModel.swift`
- Modify: `ProofCapture/Views/SessionView.swift`

- [ ] **Step 1: Create the ViewModels directory**

```bash
mkdir -p ProofCapture/ViewModels
```

- [ ] **Step 2: Create SessionViewModel.swift**

Extract all non-UI state and logic from SessionView into an `@Observable` class:

```swift
import SwiftUI
import SwiftData
import AVFoundation

@Observable @MainActor
final class SessionViewModel {

    // MARK: - Published state

    var currentPose: Pose = .front
    var phase: SessionPhase = .positioning
    var capturedImages: [Pose: UIImage] = [:]
    var countdownValue: Int = 5
    var showAbortConfirmation = false
    var retakePose: Pose?
    var isRetaking = false
    var checkmarkProgress: CGFloat = 0
    var photoScale: CGFloat = 1.03
    var showCaptureFlash = false
    var completeTitleVisible = false
    var completePhotosVisible: [Pose: Bool] = [:]

    let cameraManager = CameraManager()
    let poseDetector = PoseDetector()
    let lightingAnalyzer = LightingAnalyzer()
    let audioGuide = AudioGuide()

    // MARK: - Internal state

    private var hasBootstrappedSession = false
    private(set) var activeSession: PhotoSession?
    private var modelContext: ModelContext?

    // MARK: - Computed

    var hasSavedProgress: Bool {
        !capturedImages.isEmpty || activeSession != nil
    }

    var allRequiredPhotosCaptured: Bool {
        Pose.allCases.allSatisfy { capturedImages[$0] != nil }
    }

    var abortTitle: String {
        hasSavedProgress ? "Save draft and exit?" : "End session?"
    }

    var abortMessage: String {
        if hasSavedProgress {
            return "Your progress is saved locally and will resume at the \(resumePoseForDraft.title.lowercased()) pose."
        }
        return "No photos have been captured yet."
    }

    var captureStatusMessage: String? {
        cameraManager.statusMessage
    }

    var resumePoseForDraft: Pose {
        if allRequiredPhotosCaptured {
            return currentPose
        }
        if phase == .preview, !isRetaking, let nextPose = currentPose.next {
            return nextPose
        }
        return currentPose
    }

    // MARK: - Lifecycle

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func startSession() async {
        guard !hasBootstrappedSession else { return }
        hasBootstrappedSession = true

        restoreDraftIfNeeded()
        poseDetector.targetPose = currentPose
        cameraManager.setSampleBufferDelegates([poseDetector, lightingAnalyzer])

        if allRequiredPhotosCaptured {
            phase = .complete
            return
        }

        phase = .positioning
        await resumeCapturePipeline(playPrompt: true)
    }

    func resumeCapturePipeline(playPrompt: Bool) async {
        cameraManager.refreshAuthorizationStatus()
        let resumed = await cameraManager.resumeSessionIfPossible()
        guard resumed else { return }
        poseDetector.targetPose = currentPose
        if playPrompt {
            await audioGuide.speak(currentPose.audioPrompt)
        }
    }

    func handleScenePhaseChange(_ newPhase: ScenePhase) {
        guard hasBootstrappedSession else { return }
        switch newPhase {
        case .active:
            if phase != .complete {
                Task { await resumeCapturePipeline(playPrompt: false) }
            }
        case .inactive, .background:
            pauseSessionForRecovery()
        @unknown default:
            break
        }
    }

    func handleViewExit(syncManager: SyncManager) {
        audioGuide.stop()
        cameraManager.stopSession()
        persistSessionState()
        if activeSession?.isComplete == true {
            Task { await syncManager.syncPendingSessions() }
        }
    }

    func endSession() {
        persistSessionState()
    }

    // MARK: - Capture Flow

    func monitorReadiness() async {
        var readyDuration: TimeInterval = 0
        var timeSinceLastGuidance: TimeInterval = 0
        let checkInterval: TimeInterval = 0.25
        let requiredDuration: TimeInterval = 0.3
        let guidanceInterval: TimeInterval = 4.0

        while !Task.isCancelled && phase == .positioning {
            if captureStatusMessage != nil || !cameraManager.isRunning {
                readyDuration = 0
                try? await Task.sleep(for: .milliseconds(Int(checkInterval * 1000)))
                continue
            }

            if poseDetector.isReady && lightingAnalyzer.quality != .poor {
                readyDuration += checkInterval
                if readyDuration >= requiredDuration {
                    await beginCountdown()
                    return
                }
            } else {
                readyDuration = 0
                timeSinceLastGuidance += checkInterval
                if timeSinceLastGuidance >= guidanceInterval {
                    timeSinceLastGuidance = 0
                    await audioGuide.speakPositionGuidance(
                        bodyDetected: poseDetector.bodyDetected,
                        positionQuality: poseDetector.positionQuality,
                        poseMatches: poseDetector.poseMatchesExpected,
                        armsRelaxed: poseDetector.armsRelaxed,
                        targetPose: currentPose,
                        detectedOrientation: poseDetector.detectedOrientation
                    )
                }
            }

            try? await Task.sleep(for: .milliseconds(Int(checkInterval * 1000)))
        }
    }

    func beginCountdown() async {
        guard phase == .positioning, captureStatusMessage == nil else { return }
        audioGuide.stop()
        phase = .countdown
        countdownValue = UserPreferences.countdownSeconds

        for value in stride(from: countdownValue, through: 1, by: -1) {
            guard phase == .countdown else { return }
            countdownValue = value
            audioGuide.playCountdownTick(isFinal: value == 1)
            try? await Task.sleep(for: .seconds(1))
        }

        guard phase == .countdown else { return }
        await captureCurrentPose()
    }

    func captureCurrentPose() async {
        phase = .capturing

        let burst = await cameraManager.captureBurst(count: 7)
        if let best = BurstSelector.selectBest(from: burst, pose: currentPose) {
            capturedImages[currentPose] = best
        } else if let first = burst.first {
            capturedImages[currentPose] = first
        }

        guard capturedImages[currentPose] != nil else {
            phase = .positioning
            return
        }

        let resumePose = allRequiredPhotosCaptured ? currentPose : (currentPose.next ?? currentPose)

        ProofTheme.hapticSuccess()
        checkmarkProgress = 0
        photoScale = 1.03
        phase = .preview
        persistSessionState(resumePose: resumePose)

        if allRequiredPhotosCaptured {
            cameraManager.stopSession()
        }
    }

    func autoAdvanceAfterPreview() async {
        try? await Task.sleep(for: .seconds(2))
        guard phase == .preview else { return }

        if isRetaking {
            isRetaking = false
            phase = .complete
            persistSessionState()
            return
        }

        if let next = currentPose.next {
            let completed = currentPose
            currentPose = next
            poseDetector.targetPose = next
            phase = .positioning
            await audioGuide.speakPoseTransition(from: completed, to: next)
        } else {
            phase = .complete
            persistSessionState()
            await audioGuide.speakSessionComplete()
        }
    }

    func retakeFromComplete(_ pose: Pose) async {
        completeTitleVisible = false
        completePhotosVisible = [:]
        isRetaking = true
        capturedImages[pose] = nil
        currentPose = pose
        poseDetector.targetPose = pose
        phase = .positioning
        persistSessionState(resumePose: pose)
        await resumeCapturePipeline(playPrompt: true)
    }

    func saveAndFinish() async {
        for pose in Pose.allCases {
            if let image = capturedImages[pose] {
                _ = await cameraManager.saveToPhotoLibrary(image)
            }
        }
    }

    // MARK: - Persistence

    func restoreDraftIfNeeded() {
        guard let modelContext, let draft = fetchLatestDraft() else { return }

        activeSession = draft
        var restoredImages: [Pose: UIImage] = [:]
        for pose in Pose.allCases {
            if let image = draft.photo(for: pose) {
                restoredImages[pose] = image
            }
        }
        capturedImages = restoredImages

        let storedPose = draft.currentPose
        if draft.isComplete {
            currentPose = storedPose
            phase = .complete
        } else if draft.photoData(for: storedPose) == nil {
            currentPose = storedPose
        } else {
            currentPose = draft.nextPendingPose
        }
    }

    private func fetchLatestDraft() -> PhotoSession? {
        guard let modelContext else { return nil }
        let descriptor = FetchDescriptor<PhotoSession>(
            predicate: #Predicate { $0.isComplete == false },
            sortBy: [SortDescriptor(\PhotoSession.date, order: .reverse)]
        )
        return try? modelContext.fetch(descriptor).first
    }

    func persistSessionState(resumePose: Pose? = nil) {
        guard let modelContext, hasSavedProgress else { return }

        let session = activeSession ?? PhotoSession(date: .now, currentPose: resumePose ?? resumePoseForDraft)
        if activeSession == nil {
            modelContext.insert(session)
            activeSession = session
        }

        session.currentPose = resumePose ?? resumePoseForDraft
        session.isComplete = allRequiredPhotosCaptured
        session.syncStatus = .pending

        for pose in Pose.allCases {
            let data = capturedImages[pose]?.jpegData(compressionQuality: 0.9)
            session.setPhotoData(data, for: pose)
        }

        try? modelContext.save()
    }

    private func pauseSessionForRecovery() {
        audioGuide.stop()
        cameraManager.stopSession()
        if phase != .complete {
            phase = .positioning
        }
        persistSessionState()
    }
}
```

- [ ] **Step 3: Make SessionPhase visible to ViewModel**

Move `SessionPhase` from SessionView.swift's private scope to a shared location. Either:
- Move it inside the ViewModel file, or
- Make it a top-level `enum SessionPhase` in a Models file

Put it at the top of `SessionViewModel.swift`:

```swift
enum SessionPhase {
    case positioning
    case countdown
    case capturing
    case preview
    case complete
}
```

- [ ] **Step 4: Rewrite SessionView to use the ViewModel**

Replace the entire `SessionView.swift` with a thin view layer that reads from the ViewModel. The view should only contain:
- `@State private var viewModel = SessionViewModel()`
- The body with all the visual compositions
- References to `viewModel.*` for all state and actions

Remove all `@State` properties that moved to the ViewModel. Keep only `@Environment` properties.

The view becomes ~300 lines of pure layout code. All `monitorReadiness`, `beginCountdown`, `captureCurrentPose`, `persistSessionState`, etc. are now `viewModel.methodName()`.

- [ ] **Step 5: Build and verify**

Run: `xcodebuild -project ProofCapture.xcodeproj -scheme ProofCapture -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add ProofCapture/ViewModels/SessionViewModel.swift ProofCapture/Views/SessionView.swift
git commit -m "refactor: extract SessionViewModel from 707-line SessionView"
```

---

## Phase 4: Design Elevation — Camera & Capture Experience

The audit's biggest UX critique: the live capture experience is too thin to earn trust. The body outline is a faint rectangle, there's no explanation of what's failing, and the capture-lock moment has no ceremony.

---

### Task 11: Enhance PoseGuideOverlay with confidence-aware body outline

Replace the thin rounded rectangle with a more informative body outline that shows which checks are passing/failing via segmented feedback.

**Files:**
- Modify: `ProofCapture/Views/PoseGuideOverlay.swift`

- [ ] **Step 1: Redesign the overlay with segmented feedback**

Replace the entire `PoseGuideOverlay.swift`:

```swift
import SwiftUI

struct PoseGuideOverlay: View {
    let poseDetector: PoseDetector
    let overallStatus: QualityLevel

    var body: some View {
        GeometryReader { geometry in
            if poseDetector.bodyDetected {
                bodyOutline(in: geometry.size)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Body Outline

    private func bodyOutline(in size: CGSize) -> some View {
        let rect = normalizedToView(poseDetector.bodyRect, in: size)

        return ZStack {
            // Main body outline — rounded rect, colored by composite state
            RoundedRectangle(cornerRadius: ProofTheme.radiusMD)
                .stroke(outlineColor, lineWidth: outlineWidth)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            // Feedback pill — shown below the body rect when not ready
            if overallStatus != .good {
                feedbackPill
                    .position(
                        x: rect.midX,
                        y: min(rect.maxY + 32, size.height - 60)
                    )
            }
        }
        .animation(.easeInOut(duration: 0.3), value: overallStatus)
        .animation(.easeInOut(duration: 0.25), value: poseDetector.bodyRect)
    }

    private var feedbackPill: some View {
        Text(poseDetector.feedback)
            .font(.system(size: 13, weight: .light))
            .foregroundStyle(ProofTheme.overlayText)
            .padding(.horizontal, ProofTheme.spacingMD)
            .padding(.vertical, ProofTheme.spacingSM)
            .background(ProofTheme.overlayPill)
            .clipShape(Capsule())
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .animation(.easeInOut(duration: 0.25), value: poseDetector.feedback)
    }

    private var outlineColor: Color {
        switch overallStatus {
        case .good: ProofTheme.borderReady
        case .fair: ProofTheme.borderAlmost
        case .poor: ProofTheme.borderNeutral
        }
    }

    private var outlineWidth: CGFloat {
        switch overallStatus {
        case .good: 3
        case .fair: 2.5
        case .poor: 1.5
        }
    }

    // MARK: - Coordinate Conversion

    private func normalizedToView(_ normalized: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: normalized.origin.x * size.width,
            y: (1.0 - normalized.origin.y - normalized.height) * size.height,
            width: normalized.width * size.width,
            height: normalized.height * size.height
        )
    }
}
```

Key changes:
- Y-axis flip (from Task 1) already included
- Outline width varies by state (thicker = more confident)
- Feedback pill below body shows `poseDetector.feedback` when not ready
- Smooth animations on rect position, status, and feedback text changes

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project ProofCapture.xcodeproj -scheme ProofCapture -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add ProofCapture/Views/PoseGuideOverlay.swift
git commit -m "feat: enhanced body outline with feedback pill and confidence-aware width"
```

---

### Task 12: Add countdown "readiness lock" haptic + border glow pulse

When all checks pass and countdown begins, the border glow should pulse green briefly (a visual "lock" confirming readiness) with a medium haptic. Currently the transition from amber to green is subtle.

**Files:**
- Modify: `ProofCapture/Views/CaptureView.swift`

- [ ] **Step 1: Add a readiness-lock pulse state**

Add to CaptureView:

```swift
@State private var readinessLocked = false
```

- [ ] **Step 2: Add a readiness-lock trigger**

After the existing `onChange(of: overallStatus)` block, add:

```swift
.onChange(of: overallStatus) { oldValue, newValue in
    if oldValue == .fair && newValue == .good {
        ProofTheme.hapticLight()
    }
    // Readiness lock pulse when going from non-good to good
    if newValue == .good && !readinessLocked {
        readinessLocked = true
        ProofTheme.hapticMedium()
        // Pulse resets after 0.6s to allow re-lock if user moves
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            readinessLocked = false
        }
    }
    if newValue != .good {
        readinessLocked = false
    }
}
```

- [ ] **Step 3: Enhance the border glow for locked state**

Update `borderWidth` to pulse wider when locked:

```swift
private var borderWidth: CGFloat {
    switch overallStatus {
    case .good: readinessLocked ? 6 : ProofTheme.borderWidthReady
    case .fair: ProofTheme.borderWidthAlmost
    case .poor: ProofTheme.borderWidthNeutral
    }
}
```

This creates a visible "breathe" — the border briefly goes from 4pt to 6pt when locking, then settles to 4pt.

- [ ] **Step 4: Build and verify**

Run: `xcodebuild -project ProofCapture.xcodeproj -scheme ProofCapture -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add ProofCapture/Views/CaptureView.swift
git commit -m "feat: readiness-lock border pulse + medium haptic when all checks pass"
```

---

## Phase 5: Design Elevation — Home, History, Completion

Elevate the non-camera surfaces from utility screens to premium product surfaces.

---

### Task 13: Redesign HomeView — weekly ritual anchor with progress storytelling

The home screen is too bare. Add: hero message that changes based on session count, streak indicator, and a larger last-session preview.

**Files:**
- Modify: `ProofCapture/Views/HomeView.swift`

- [ ] **Step 1: Add streak and contextual messaging logic**

Add computed properties to HomeView:

```swift
private var daysSinceLastSession: Int? {
    guard let last = lastSession else { return nil }
    return Calendar.current.dateComponents([.day], from: last.date, to: .now).day
}

private var heroMessage: String {
    guard let days = daysSinceLastSession else {
        return "Your first check-in"
    }
    if days == 0 { return "Check-in complete" }
    if days <= 7 { return "Week \(sessions.count + 1)" }
    if days <= 14 { return "Time for a check-in" }
    return "Welcome back"
}

private var heroSubtitle: String? {
    guard let days = daysSinceLastSession else {
        return "Start building your progress record"
    }
    if days == 0 { return "Nice work. See you next week." }
    if days <= 7 { return "\(sessions.count) sessions recorded" }
    if days <= 14 { return "\(days) days since your last session" }
    return "\(days) days since your last session"
}
```

- [ ] **Step 2: Redesign the center content area**

Replace the center content in `body` (the `if let draft` / `if let last` / `else` block) with a more compelling layout:

For the `lastSession` case, replace with:

```swift
} else if let last = lastSession {
    VStack(spacing: ProofTheme.spacingMD) {
        // Hero message — changes weekly
        Text(heroMessage)
            .font(.system(size: 28, weight: .ultraLight))
            .foregroundStyle(ProofTheme.accent)

        if let subtitle = heroSubtitle {
            Text(subtitle)
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(ProofTheme.textTertiary)
        }

        // Last session strip — wider than before
        if let front = last.photo(for: .front),
           let side = last.photo(for: .side),
           let back = last.photo(for: .back) {
            HStack(spacing: 2) {
                Image(uiImage: front)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 100)
                    .clipped()

                Image(uiImage: side)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 100)
                    .clipped()

                Image(uiImage: back)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 100)
                    .clipped()
            }
            .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusSM))
            .padding(.horizontal, ProofTheme.spacingXL)
            .padding(.top, ProofTheme.spacingSM)
            .accessibilityLabel("Last session photos")
        }

        Text(last.date, style: .relative)
            .font(.system(size: 13, weight: .light))
            .foregroundStyle(ProofTheme.textTertiary)
            + Text(" ago")
            .font(.system(size: 13, weight: .light))
            .foregroundStyle(ProofTheme.textTertiary)
    }
    .accessibilityElement(children: .combine)
```

This shows all 3 photos as a strip instead of just the front thumbnail.

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -project ProofCapture.xcodeproj -scheme ProofCapture -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add ProofCapture/Views/HomeView.swift
git commit -m "feat: redesign home with contextual hero message and 3-photo strip"
```

---

### Task 14: Redesign HistoryView session rows with larger photos and progress framing

Shift history from a list of dates to a visual progress archive.

**Files:**
- Modify: `ProofCapture/Views/HistoryView.swift`

- [ ] **Step 1: Add week numbering to session rows**

Replace the `sessionRow` method:

```swift
private func sessionRow(_ session: PhotoSession) -> some View {
    let weekNumber = weekIndex(for: session)

    return VStack(alignment: .leading, spacing: ProofTheme.spacingSM) {
        HStack {
            Text("Week \(weekNumber)")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(ProofTheme.textPrimary)
            Spacer()
            Text(session.date.formatted(.dateTime.month(.abbreviated).day()))
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(ProofTheme.textTertiary)
        }

        HStack(spacing: 2) {
            ForEach(Pose.allCases) { pose in
                if let image = session.photo(for: pose) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 140)
                        .clipped()
                        .accessibilityLabel("\(pose.title) photo")
                } else {
                    Rectangle()
                        .fill(ProofTheme.surface)
                        .frame(height: 140)
                        .accessibilityLabel("\(pose.title) photo missing")
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusSM))
    }
    .padding(.vertical, ProofTheme.spacingSM)
}

private func weekIndex(for session: PhotoSession) -> Int {
    guard let firstSession = sessions.last else { return 1 }
    let weeks = Calendar.current.dateComponents(
        [.weekOfYear], from: firstSession.date, to: session.date
    ).weekOfYear ?? 0
    return weeks + 1
}
```

Key changes:
- "Week N" label instead of full date+time (progress framing)
- Taller photos (140pt instead of 120pt)
- Shorter date format

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project ProofCapture.xcodeproj -scheme ProofCapture -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add ProofCapture/Views/HistoryView.swift
git commit -m "feat: redesign history rows with week numbering and taller photos"
```

---

### Task 15: Elevate ComparisonView with week labels and pose transition animations

**Files:**
- Modify: `ProofCapture/Views/ComparisonView.swift`

- [ ] **Step 1: Add week labels and entrance animation**

Add week calculation and entrance state:

```swift
@State private var columnsVisible = false

private var earlierWeek: Int {
    weeksBetween(from: earlierSession, to: recentSession) > 0
        ? 1 : 1
}

private var weekDifference: Int {
    let weeks = Calendar.current.dateComponents(
        [.weekOfYear], from: earlierSession.date, to: recentSession.date
    ).weekOfYear ?? 0
    return max(weeks, 1)
}
```

- [ ] **Step 2: Update date labels to show week difference**

Replace the `dateLabels` view:

```swift
private var dateLabels: some View {
    HStack {
        VStack(spacing: 2) {
            Text(earlierSession.date.formatted(.dateTime.month(.abbreviated).day()))
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(ProofTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)

        VStack(spacing: 2) {
            Text("\(weekDifference) week\(weekDifference == 1 ? "" : "s") later")
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(ProofTheme.textTertiary)
        }

        VStack(spacing: 2) {
            Text(recentSession.date.formatted(.dateTime.month(.abbreviated).day()))
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(ProofTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
    .padding(.vertical, ProofTheme.spacingSM)
}
```

- [ ] **Step 3: Add entrance animation**

Add `.onAppear` to the body:

```swift
.onAppear {
    withAnimation(.easeOut(duration: 0.4)) {
        columnsVisible = true
    }
}
```

Apply to the TabView:

```swift
.opacity(columnsVisible ? 1 : 0)
.scaleEffect(columnsVisible ? 1.0 : 0.96)
```

- [ ] **Step 4: Build and verify**

Run: `xcodebuild -project ProofCapture.xcodeproj -scheme ProofCapture -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add ProofCapture/Views/ComparisonView.swift
git commit -m "feat: elevate comparison with week difference labels and entrance animation"
```

---

## Phase 6: Design Elevation — Auth, Onboarding, Settings

---

### Task 16: Elevate AuthView with entrance animation and warmer framing

The auth screen reads as a sign-in wall. Add staggered entrance animations (matching WelcomeStep pattern) and warmer copy.

**Files:**
- Modify: `ProofCapture/Views/AuthView.swift`

- [ ] **Step 1: Add staggered animation state**

Add to AuthView:

```swift
@State private var titleVisible = false
@State private var featuresVisible = false
@State private var buttonVisible = false
```

- [ ] **Step 2: Apply staggered fade-in to body content**

Wrap the PROOF title:

```swift
Text("PROOF")
    .font(.system(size: 60, weight: .ultraLight))
    .tracking(12)
    .foregroundStyle(ProofTheme.textPrimary)
    .opacity(titleVisible ? 1 : 0)
    .offset(y: titleVisible ? 0 : 8)
    .accessibilityAddTraits(.isHeader)
```

Wrap the feature rows VStack:

```swift
.opacity(featuresVisible ? 1 : 0)
.offset(y: featuresVisible ? 0 : 12)
```

Wrap the SignInWithAppleButton + subtitle:

```swift
.opacity(buttonVisible ? 1 : 0)
.offset(y: buttonVisible ? 0 : 8)
```

Add `.onAppear`:

```swift
.onAppear {
    withAnimation(.easeOut(duration: 0.6)) {
        titleVisible = true
    }
    withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
        featuresVisible = true
    }
    withAnimation(.easeOut(duration: 0.5).delay(0.4)) {
        buttonVisible = true
    }
}
```

- [ ] **Step 3: Update the sign-in subtitle to warmer copy**

Change from:

```swift
Text("Sign in to back up your progress photos")
```

To:

```swift
Text("Your photos stay private and backed up")
```

- [ ] **Step 4: Build and verify**

Run: `xcodebuild -project ProofCapture.xcodeproj -scheme ProofCapture -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add ProofCapture/Views/AuthView.swift
git commit -m "feat: staggered entrance animation and warmer copy for AuthView"
```

---

### Task 17: Add privacy reassurance section to SettingsView

The audit identifies Settings as lacking a "deeply reassuring privacy explanation." Add a privacy section explaining what the app does and doesn't do with photos.

**Files:**
- Modify: `ProofCapture/Views/SettingsView.swift`

- [ ] **Step 1: Add a privacy section between Capture and Sign out sections**

After the `CAPTURE` section and before the sign-out section, add:

```swift
Section {
    VStack(alignment: .leading, spacing: ProofTheme.spacingSM) {
        Label {
            Text("Photos stored on-device only")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(ProofTheme.textSecondary)
        } icon: {
            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(ProofTheme.statusGood)
        }

        Label {
            Text("Cloud backup encrypted to your Apple ID")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(ProofTheme.textSecondary)
        } icon: {
            Image(systemName: "icloud.fill")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(ProofTheme.statusGood)
        }

        Label {
            Text("No sharing, no analytics on photo content")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(ProofTheme.textSecondary)
        } icon: {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(ProofTheme.statusGood)
        }
    }
    .padding(.vertical, ProofTheme.spacingXS)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Privacy: Photos stored on device, cloud backup encrypted to your Apple ID, no sharing or analytics on photo content")
} header: {
    Text("PRIVACY")
        .font(.system(size: 12, weight: .light))
        .foregroundStyle(ProofTheme.textTertiary)
}
.listRowBackground(ProofTheme.surface)
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project ProofCapture.xcodeproj -scheme ProofCapture -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add ProofCapture/Views/SettingsView.swift
git commit -m "feat: add privacy reassurance section to Settings"
```

---

### Task 18: Add animation timing tokens to ProofTheme

Durations are scattered across files as magic numbers. Centralize them.

**Files:**
- Modify: `ProofCapture/Theme/Theme.swift`

- [ ] **Step 1: Add animation constants to ProofTheme**

After the `radiusLG` line, add:

```swift
// MARK: - Animation Timing
static let animationFast: Double = 0.15
static let animationDefault: Double = 0.3
static let animationSlow: Double = 0.5
static let animationEntrance: Double = 0.6

// Stagger delays
static let staggerShort: Double = 0.05
static let staggerDefault: Double = 0.12
static let staggerLong: Double = 0.2
```

- [ ] **Step 2: Update existing hardcoded durations across views**

Grep for hardcoded animation durations and replace with theme tokens where appropriate. Priority files:
- `WelcomeStep.swift`: `.easeOut(duration: 0.6)` → `.easeOut(duration: ProofTheme.animationEntrance)`
- `HistoryView.swift`: `0.25` → `ProofTheme.animationDefault`
- `CaptureView.swift`: `0.5` → `ProofTheme.animationSlow`, `0.3` → `ProofTheme.animationDefault`

Don't update every single duration — focus on the ones that define the product's rhythm (entrance animations, state transitions).

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -project ProofCapture.xcodeproj -scheme ProofCapture -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add ProofCapture/Theme/Theme.swift ProofCapture/Views/Onboarding/WelcomeStep.swift ProofCapture/Views/HistoryView.swift ProofCapture/Views/CaptureView.swift
git commit -m "feat: centralize animation timing tokens in ProofTheme"
```

---

## Phase 7: ReviewView Elevation + Save-Completion Ceremony

---

### Task 19: Elevate ReviewView with session summary and save haptic

The review screen is flat — no product language, no quality summary, no ceremony around saving.

**Files:**
- Modify: `ProofCapture/Views/ReviewView.swift`

- [ ] **Step 1: Add entrance animations and a save-success haptic**

Add state:

```swift
@State private var photosVisible: [Pose: Bool] = [:]
```

Add entrance stagger in `photoGrid` — wrap each photo in opacity/scale modifiers like the complete view pattern, with `.onAppear` triggering staggered visibility.

- [ ] **Step 2: Add success haptic after save**

In `saveToCamera()`, after `savedSuccessfully = true`, add:

```swift
ProofTheme.hapticSuccess()
```

- [ ] **Step 3: Improve the "Saved" state visual**

After saving, show a green checkmark instead of just the text "Saved":

```swift
} else if savedSuccessfully {
    HStack(spacing: ProofTheme.spacingSM) {
        Image(systemName: "checkmark")
            .font(.system(size: 13, weight: .light))
            .foregroundStyle(ProofTheme.statusGood)
        Text("Saved to Camera Roll")
            .foregroundStyle(ProofTheme.statusGood)
    }
}
```

- [ ] **Step 4: Build and verify**

Run: `xcodebuild -project ProofCapture.xcodeproj -scheme ProofCapture -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add ProofCapture/Views/ReviewView.swift
git commit -m "feat: elevate ReviewView with entrance animations and save-success ceremony"
```

---

## Phase 8: Production Readiness

---

### Task 20: Add save-completion haptic to SessionView

When all 3 poses are captured and the session auto-completes, there's no completion haptic — only the per-pose success haptic. Add a distinct completion haptic.

**Files:**
- Modify: `ProofCapture/Views/SessionView.swift` (or `SessionViewModel.swift` after Task 10)

- [ ] **Step 1: Add completion haptic in autoAdvanceAfterPreview**

In the `else` branch (session complete), add before `phase = .complete`:

```swift
// Double haptic for session completion — distinct from per-pose single haptic
ProofTheme.hapticSuccess()
try? await Task.sleep(for: .milliseconds(200))
ProofTheme.hapticSuccess()
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project ProofCapture.xcodeproj -scheme ProofCapture -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add ProofCapture/Views/SessionView.swift
git commit -m "feat: double haptic on session completion — distinct from per-pose haptic"
```

---

### Task 21: Countdown tick audible in text mode for deaf/HoH users

The countdown ticks are silent in text-only mode. But countdown is a safety-critical timing cue — deaf/HoH users using text mode still need to know when capture is about to happen. Make ticks always play (they're system sounds, not speech).

**Files:**
- Modify: `ProofCapture/Managers/AudioGuide.swift:106-109`

- [ ] **Step 1: Remove the `guard mode == .voice` from playCountdownTick**

```swift
func playCountdownTick(isFinal: Bool) {
    // Always play ticks regardless of guidance mode — countdown is
    // a safety-critical timing cue, not speech guidance
    let soundID: SystemSoundID = isFinal ? 1117 : 1057
    AudioServicesPlaySystemSound(soundID)
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project ProofCapture.xcodeproj -scheme ProofCapture -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add ProofCapture/Managers/AudioGuide.swift
git commit -m "fix: always play countdown ticks — safety-critical for text-mode/deaf users"
```

---

### Task 22: Add save confirmation haptic to HomeView capture button

When tapping the hero capture button, there's a `simultaneousGesture(TapGesture)` for haptic — but it fires the light haptic. For the primary CTA, use a medium haptic.

**Files:**
- Modify: `ProofCapture/Views/HomeView.swift:140`

- [ ] **Step 1: Upgrade to medium haptic**

```swift
.simultaneousGesture(TapGesture().onEnded { ProofTheme.hapticMedium() })
```

- [ ] **Step 2: Build and verify, commit**

```bash
git add ProofCapture/Views/HomeView.swift
git commit -m "fix: upgrade home capture button to medium haptic"
```

---

## Phase 9: Future / Post-MVP (tracked but not implemented now)

These are identified gaps that should be tracked as Linear tickets but are not part of this plan's implementation scope:

1. **StoreKit 2 subscription** (~GBP 9.99/month) — requires App Store Connect setup, paywall UI, receipt validation
2. **Pose-specific silhouette targets** — semi-transparent body silhouette overlay showing ideal positioning per pose
3. **Text-first capture redesign** — when text mode is primary, larger instructional surfaces, different pacing
4. **Progress trend interpretation** — narrative layer on history showing week-over-week observations
5. **iOS 26 Liquid Glass deep integration** — beyond current `#available` gating, full material system
6. **Offline-first sync queue** — proper retry/backoff for Supabase upload failures
7. **Image presentation cards** — "weekly record" artifact card that coaches could screenshot/share
8. **Accessibility audit** — VoiceOver full-flow testing, Dynamic Type verification
9. **App Store metadata** — screenshots, description, keywords, preview video
10. **Widget** — iOS widget showing days since last session / streak

---

## Summary

| Phase | Tasks | Focus |
|-------|-------|-------|
| 1 | 1-5 | Critical bugs (Y-axis flip, key mismatch, hardcoded secrets, logging) |
| 2 | 6-9 | Missing spec features (audio cues, text guidance, flash, entrance animations) |
| 3 | 10 | Architecture (extract SessionViewModel) |
| 4 | 11-12 | Camera UX (enhanced overlay, readiness lock) |
| 5 | 13-15 | Home, History, Comparison elevation |
| 6 | 16-18 | Auth, Settings, Theme tokens |
| 7 | 19 | ReviewView elevation |
| 8 | 20-22 | Production haptics and audio fixes |
| 9 | — | Future backlog (StoreKit, silhouettes, trends) |

**Total: 22 implementation tasks across 8 active phases + 10 backlog items.**

Each phase is independently deployable — Phases 1-2 are ship-blockers, Phases 3-8 are quality elevation.

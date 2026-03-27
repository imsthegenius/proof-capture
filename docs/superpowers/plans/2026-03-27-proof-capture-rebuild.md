# Proof Capture Full Rebuild Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild Proof Capture into a functional, polished guided progress photo app with onboarding, gendered voice guidance, proper camera controls, readable UI overlays, pose reference silhouettes, and session comparison.

**Architecture:** SwiftUI views backed by @Observable managers. Camera uses AVFoundation with front/back switching. Voice uses AVSpeechSynthesizer with gender-specific voice selection. Local-first with SwiftData, background sync to Supabase. Onboarding stored in UserDefaults via @AppStorage.

**Tech Stack:** Swift/SwiftUI (iOS 17+), AVFoundation, Vision framework, AVSpeechSynthesizer, SwiftData, Supabase (supabase-swift 2.x)

---

## File Map

### New Files
- `ProofCapture/Models/UserPreferences.swift` — Gender enum, onboarding state, voice/timer prefs
- `ProofCapture/Views/Onboarding/OnboardingView.swift` — Multi-step onboarding container
- `ProofCapture/Views/Onboarding/WelcomeStep.swift` — Value prop + hero screen
- `ProofCapture/Views/Onboarding/GenderStep.swift` — Gender selection for voice
- `ProofCapture/Views/Onboarding/SetupGuideStep.swift` — How to prop phone, distance, lighting tips
- `ProofCapture/Views/Onboarding/PermissionStep.swift` — Camera permission request with context
- `ProofCapture/Views/ComparisonView.swift` — Side-by-side session comparison
- `ProofCapture/Views/FullPhotoView.swift` — Full-screen photo viewer (tap from review/history)
- `ProofCapture/Views/SettingsView.swift` — Profile, voice gender, timer, sign out

### Modified Files
- `ProofCapture/Theme/Theme.swift` — Refined palette, add haptic helpers
- `ProofCapture/ContentView.swift` — Add onboarding gate before auth
- `ProofCapture/Views/HomeView.swift` — Full redesign: last session preview, setup reminder, settings access
- `ProofCapture/Views/AuthView.swift` — Add value proposition, skip option
- `ProofCapture/Views/SessionView.swift` — Readable overlays, auto-ready, timer config, pose reference
- `ProofCapture/Views/CaptureView.swift` — Dark pill backgrounds on all text, camera flip button, torch toggle
- `ProofCapture/Views/PoseGuideOverlay.swift` — Silhouette guide instead of rectangle, distance indicator
- `ProofCapture/Views/ReviewView.swift` — Larger photos, full-screen tap, comparison with previous
- `ProofCapture/Views/HistoryView.swift` — Timeline layout, larger thumbnails, comparison entry point
- `ProofCapture/Managers/CameraManager.swift` — Front/back camera switch, torch control, exposure lock
- `ProofCapture/Managers/AudioGuide.swift` — Gender-specific voice selection, respect preferences
- `ProofCapture/Models/Pose.swift` — Add pose-specific silhouette asset names

---

## Task 1: User Preferences Model

**Files:**
- Create: `ProofCapture/Models/UserPreferences.swift`

- [ ] **Step 1: Create UserPreferences with gender, onboarding state, voice/timer prefs**

```swift
import Foundation

enum UserGender: Int {
    case male = 0
    case female = 1
}

enum UserPreferences {
    @AppStorageKey("hasCompletedOnboarding") static var hasCompletedOnboarding = false
    @AppStorageKey("userGender") static var genderRaw = 0
    @AppStorageKey("guidanceMode") static var guidanceModeRaw = 0
    @AppStorageKey("countdownSeconds") static var countdownSeconds = 5

    static var gender: UserGender {
        get { UserGender(rawValue: genderRaw) ?? .male }
        set { genderRaw = newValue.rawValue }
    }

    static var guidanceMode: GuidanceMode {
        get { GuidanceMode(rawValue: guidanceModeRaw) ?? .voice }
        set { guidanceModeRaw = newValue.rawValue }
    }
}

// Thin wrapper so we can use static computed properties backed by UserDefaults
@propertyWrapper
struct AppStorageKey<Value> {
    let key: String
    let defaultValue: Value

    init(wrappedValue: Value, _ key: String) {
        self.key = key
        self.defaultValue = wrappedValue
    }

    var wrappedValue: Value {
        get {
            UserDefaults.standard.object(forKey: key) as? Value ?? defaultValue
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project ProofCapture.xcodeproj -scheme ProofCapture -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "(error:|BUILD)"`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add ProofCapture/Models/UserPreferences.swift
git commit -m "feat: add UserPreferences model for onboarding and voice gender"
```

---

## Task 2: Refined Design Tokens

**Files:**
- Modify: `ProofCapture/Theme/Theme.swift`

The current palette has issues: `#0B0B0B` is too cold, `#E8C547` gold accent feels cheap on pure dark. Refine to warmer near-black with a more sophisticated accent.

- [ ] **Step 1: Update Theme.swift with refined palette and haptic helpers**

```swift
import SwiftUI
import UIKit

enum ProofTheme {
    // MARK: - Colors (warm near-black base)
    static let background = Color(red: 12/255, green: 11/255, blue: 9/255)        // #0C0B09
    static let surface = Color(red: 28/255, green: 27/255, blue: 25/255)          // #1C1B19
    static let elevated = Color(red: 46/255, green: 44/255, blue: 42/255)         // #2E2C2A
    static let separator = Color(red: 28/255, green: 27/255, blue: 25/255)        // #1C1B19

    static let textPrimary = Color(red: 245/255, green: 242/255, blue: 237/255)   // #F5F2ED
    static let textSecondary = Color(red: 142/255, green: 138/255, blue: 130/255) // #8E8A82
    static let textTertiary = Color(red: 82/255, green: 78/255, blue: 72/255)     // #524E48

    static let accent = Color(red: 218/255, green: 195/255, blue: 130/255)        // #DAC382 (warmer, softer gold)

    // Camera overlays — need high contrast
    static let overlayPill = Color.black.opacity(0.65)
    static let overlayText = Color.white

    // Status indicators
    static let statusGood = Color(red: 106/255, green: 190/255, blue: 110/255)    // #6ABE6E (softer green)
    static let statusFair = Color(red: 230/255, green: 180/255, blue: 80/255)     // #E6B450
    static let statusPoor = Color(red: 210/255, green: 90/255, blue: 85/255)      // #D25A55

    // MARK: - Spacing (4pt grid)
    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 16
    static let spacingLG: CGFloat = 24
    static let spacingXL: CGFloat = 32
    static let spacingXXL: CGFloat = 48

    // MARK: - Corner Radius
    static let radiusSM: CGFloat = 8
    static let radiusMD: CGFloat = 12
    static let radiusLG: CGFloat = 20

    // MARK: - Haptics
    static func hapticLight() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func hapticMedium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func hapticSuccess() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
```

- [ ] **Step 2: Build and verify no color references break**

Run: `xcodebuild ... build CODE_SIGNING_ALLOWED=NO`
Expected: BUILD SUCCEEDED (all existing views use `ProofTheme.*` so they pick up new colors automatically)

- [ ] **Step 3: Commit**

```bash
git add ProofCapture/Theme/Theme.swift
git commit -m "feat: refine design tokens — warmer palette, softer accent, haptic helpers"
```

---

## Task 3: Camera System — Front/Back Switch + Torch

**Files:**
- Modify: `ProofCapture/Managers/CameraManager.swift`

- [ ] **Step 1: Add camera position switching, torch control, and exposure lock**

Add to CameraManager:

```swift
// New properties
private(set) var currentPosition: AVCaptureDevice.Position = .back
private(set) var isTorchOn = false

// Switch camera between front and back
func switchCamera() {
    sessionQueue.async { [self] in
        let newPosition: AVCaptureDevice.Position = currentPosition == .back ? .front : .back

        session.beginConfiguration()

        // Remove existing input
        if let currentInput = session.inputs.first as? AVCaptureDeviceInput {
            session.removeInput(currentInput)
        }

        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: newPosition
        ),
        let input = try? AVCaptureDeviceInput(device: camera),
        session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }

        session.addInput(input)
        session.commitConfiguration()

        Task { @MainActor in
            self.currentPosition = newPosition
        }
    }
}

// Toggle torch (only works with back camera)
func toggleTorch() {
    sessionQueue.async { [self] in
        guard let device = (session.inputs.first as? AVCaptureDeviceInput)?.device,
              device.hasTorch else { return }

        do {
            try device.lockForConfiguration()
            let newState = !device.isTorchActive
            device.torchMode = newState ? .on : .off
            device.unlockForConfiguration()
            Task { @MainActor in self.isTorchOn = newState }
        } catch {}
    }
}
```

Also update `configure()` to use `currentPosition` instead of hardcoded `.back`.

- [ ] **Step 2: Build and verify**
- [ ] **Step 3: Commit**

```bash
git commit -m "feat: camera front/back switch + torch control"
```

---

## Task 4: Gender-Specific Voice

**Files:**
- Modify: `ProofCapture/Managers/AudioGuide.swift`

- [ ] **Step 1: Update voice selection based on gender preference**

Replace the voice selection logic in `speak()`:

```swift
func speak(_ text: String) async {
    guard mode == .voice else { return }

    synthesizer.stopSpeaking(at: .immediate)

    let utterance = AVSpeechUtterance(string: text)
    utterance.rate = 0.46
    utterance.pitchMultiplier = 1.0
    utterance.preUtteranceDelay = 0.1
    utterance.voice = preferredVoice()

    await withCheckedContinuation { continuation in
        speechContinuation = continuation
        synthesizer.speak(utterance)
    }
}

private func preferredVoice() -> AVSpeechSynthesisVoice? {
    let gender = UserPreferences.gender

    // Voice preference cascade: premium > enhanced > compact
    let candidates: [(String, String)] = switch gender {
    case .male:
        [
            ("com.apple.voice.premium.en-GB.Malcolm", "premium"),
            ("com.apple.voice.enhanced.en-GB.Daniel", "enhanced"),
            ("com.apple.voice.compact.en-GB.Daniel", "compact"),
        ]
    case .female:
        [
            ("com.apple.voice.premium.en-GB.Serena", "premium"),
            ("com.apple.voice.enhanced.en-GB.Stephanie", "enhanced"),
            ("com.apple.voice.compact.en-GB.Stephanie", "compact"),
        ]
    }

    for (identifier, _) in candidates {
        if let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            return voice
        }
    }

    // Final fallback
    return AVSpeechSynthesisVoice(language: "en-GB")
}
```

- [ ] **Step 2: Build and verify**
- [ ] **Step 3: Commit**

```bash
git commit -m "feat: gender-specific voice selection with premium cascade"
```

---

## Task 5: Onboarding Flow

**Files:**
- Create: `ProofCapture/Views/Onboarding/OnboardingView.swift`
- Create: `ProofCapture/Views/Onboarding/WelcomeStep.swift`
- Create: `ProofCapture/Views/Onboarding/GenderStep.swift`
- Create: `ProofCapture/Views/Onboarding/SetupGuideStep.swift`
- Create: `ProofCapture/Views/Onboarding/PermissionStep.swift`
- Modify: `ProofCapture/ContentView.swift`

This is the most critical missing piece. 4 steps:
1. **Welcome** — What the app does, single sentence value prop
2. **Gender** — "Choose your guide voice" with male/female selection
3. **Setup Guide** — How to prop phone (surface height, 4-6ft distance, overhead light), visual diagram using SF Symbols
4. **Camera Permission** — Contextual request with explanation

- [ ] **Step 1: Create OnboardingView container**

```swift
import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentStep = 0

    var body: some View {
        ZStack {
            ProofTheme.background.ignoresSafeArea()

            TabView(selection: $currentStep) {
                WelcomeStep(onNext: { currentStep = 1 })
                    .tag(0)

                GenderStep(onNext: { currentStep = 2 })
                    .tag(1)

                SetupGuideStep(onNext: { currentStep = 3 })
                    .tag(2)

                PermissionStep(onComplete: { hasCompletedOnboarding = true })
                    .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentStep)

            // Step indicator at bottom
            VStack {
                Spacer()
                HStack(spacing: ProofTheme.spacingSM) {
                    ForEach(0..<4, id: \.self) { step in
                        Circle()
                            .fill(step == currentStep ? ProofTheme.textPrimary : ProofTheme.textTertiary)
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.bottom, ProofTheme.spacingLG)
            }
        }
    }
}
```

- [ ] **Step 2: Create WelcomeStep**

```swift
import SwiftUI

struct WelcomeStep: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("PROOF")
                .font(.system(size: 48, weight: .thin))
                .tracking(8)
                .foregroundStyle(ProofTheme.textPrimary)

            Text("Consistent progress photos\nguided by your phone.")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(ProofTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, ProofTheme.spacingMD)
                .lineSpacing(4)

            Spacer()

            Text("Three poses. Timed capture.\nSame framing every session.")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(ProofTheme.textTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()

            Button(action: {
                ProofTheme.hapticLight()
                onNext()
            }) {
                Text("Get started")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(ProofTheme.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(ProofTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusSM))
            }
            .padding(.horizontal, ProofTheme.spacingXL)
            .padding(.bottom, ProofTheme.spacingXXL)
        }
    }
}
```

- [ ] **Step 3: Create GenderStep**

```swift
import SwiftUI

struct GenderStep: View {
    @AppStorage("userGender") private var genderRaw = 0
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: ProofTheme.spacingXXL * 2)

            Text("Choose your guide voice")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(ProofTheme.textPrimary)

            Text("Audio prompts will talk you through each pose.")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(ProofTheme.textSecondary)
                .padding(.top, ProofTheme.spacingSM)

            Spacer()

            HStack(spacing: ProofTheme.spacingMD) {
                genderButton(label: "Male", value: 0)
                genderButton(label: "Female", value: 1)
            }
            .padding(.horizontal, ProofTheme.spacingXL)

            Spacer()

            Button(action: {
                ProofTheme.hapticLight()
                onNext()
            }) {
                Text("Continue")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(ProofTheme.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(ProofTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusSM))
            }
            .padding(.horizontal, ProofTheme.spacingXL)
            .padding(.bottom, ProofTheme.spacingXXL)
        }
    }

    private func genderButton(label: String, value: Int) -> some View {
        Button {
            ProofTheme.hapticLight()
            genderRaw = value
        } label: {
            Text(label)
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(genderRaw == value ? ProofTheme.background : ProofTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(genderRaw == value ? ProofTheme.accent : ProofTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusSM))
        }
    }
}
```

- [ ] **Step 4: Create SetupGuideStep**

```swift
import SwiftUI

struct SetupGuideStep: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: ProofTheme.spacingXXL * 2)

            Text("How it works")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(ProofTheme.textPrimary)

            Spacer()
                .frame(height: ProofTheme.spacingXXL)

            VStack(alignment: .leading, spacing: ProofTheme.spacingLG) {
                guideRow(
                    number: "1",
                    title: "Prop your phone up",
                    detail: "Lean it against a wall or shelf at waist height, 5-6 feet away."
                )
                guideRow(
                    number: "2",
                    title: "Stand under overhead light",
                    detail: "A single light above you creates shadows that show definition."
                )
                guideRow(
                    number: "3",
                    title: "Follow the audio guide",
                    detail: "Front, side, back. The app talks you through each pose and captures automatically."
                )
            }
            .padding(.horizontal, ProofTheme.spacingXL)

            Spacer()

            Button(action: {
                ProofTheme.hapticLight()
                onNext()
            }) {
                Text("Continue")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(ProofTheme.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(ProofTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusSM))
            }
            .padding(.horizontal, ProofTheme.spacingXL)
            .padding(.bottom, ProofTheme.spacingXXL)
        }
    }

    private func guideRow(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: ProofTheme.spacingMD) {
            Text(number)
                .font(.system(size: 28, weight: .thin))
                .foregroundStyle(ProofTheme.accent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: ProofTheme.spacingXS) {
                Text(title)
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(ProofTheme.textPrimary)

                Text(detail)
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(ProofTheme.textSecondary)
                    .lineSpacing(2)
            }
        }
    }
}
```

- [ ] **Step 5: Create PermissionStep**

```swift
import SwiftUI
import AVFoundation

struct PermissionStep: View {
    let onComplete: () -> Void
    @State private var cameraGranted = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: ProofTheme.spacingXXL * 2)

            Text("Camera access")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(ProofTheme.textPrimary)

            Text("Proof needs your camera to capture\nprogress photos. Photos stay on your device\nand are backed up to your private cloud.")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(ProofTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.top, ProofTheme.spacingMD)

            Spacer()

            Button(action: {
                Task {
                    let status = AVCaptureDevice.authorizationStatus(for: .video)
                    if status == .notDetermined {
                        let granted = await AVCaptureDevice.requestAccess(for: .video)
                        cameraGranted = granted
                    } else {
                        cameraGranted = status == .authorized
                    }
                    ProofTheme.hapticSuccess()
                    onComplete()
                }
            }) {
                Text("Allow camera")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(ProofTheme.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(ProofTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusSM))
            }
            .padding(.horizontal, ProofTheme.spacingXL)
            .padding(.bottom, ProofTheme.spacingXXL)
        }
    }
}
```

- [ ] **Step 6: Update ContentView to gate on onboarding**

```swift
import SwiftUI

struct ContentView: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    #if DEBUG
    @State private var skipAuth = false
    #endif

    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingView()
            } else {
                #if DEBUG
                if authManager.isAuthenticated || skipAuth {
                    NavigationStack { HomeView() }
                } else {
                    AuthView()
                        .onTapGesture(count: 3) { skipAuth = true }
                }
                #else
                if authManager.isAuthenticated {
                    NavigationStack { HomeView() }
                } else {
                    AuthView()
                }
                #endif
            }
        }
        .animation(.easeInOut(duration: 0.3), value: hasCompletedOnboarding)
        .animation(.easeInOut(duration: 0.3), value: authManager.isAuthenticated)
    }
}
```

- [ ] **Step 7: Build and verify**
- [ ] **Step 8: Commit**

```bash
git add ProofCapture/Views/Onboarding/ ProofCapture/ContentView.swift
git commit -m "feat: add 4-step onboarding — welcome, gender, setup guide, camera permission"
```

---

## Task 6: Capture View — Readable Overlays + Camera Controls

**Files:**
- Modify: `ProofCapture/Views/CaptureView.swift`
- Modify: `ProofCapture/Views/SessionView.swift`
- Modify: `ProofCapture/Views/PoseGuideOverlay.swift`

The camera UI has text that's invisible on the camera feed. All text on camera must sit on dark pills. Add camera flip button and torch toggle.

- [ ] **Step 1: Rewrite CaptureView with dark pill overlays and camera controls**

```swift
import SwiftUI
import AVFoundation

struct CaptureView: View {
    let cameraManager: CameraManager
    let poseDetector: PoseDetector
    let lightingAnalyzer: LightingAnalyzer
    let currentPose: Pose

    var body: some View {
        ZStack {
            CameraPreview(session: cameraManager.session)
                .ignoresSafeArea()

            PoseGuideOverlay(poseDetector: poseDetector, currentPose: currentPose)

            // Top controls — camera flip + torch
            VStack {
                HStack {
                    Spacer()

                    Button {
                        ProofTheme.hapticLight()
                        cameraManager.switchCamera()
                    } label: {
                        Image(systemName: "camera.rotate")
                            .font(.system(size: 15, weight: .light))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(ProofTheme.overlayPill)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Switch camera")

                    if cameraManager.currentPosition == .back {
                        Button {
                            ProofTheme.hapticLight()
                            cameraManager.toggleTorch()
                        } label: {
                            Image(systemName: cameraManager.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                .font(.system(size: 15, weight: .light))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(ProofTheme.overlayPill)
                                .clipShape(Circle())
                        }
                        .accessibilityLabel(cameraManager.isTorchOn ? "Turn off torch" : "Turn on torch")
                    }
                }
                .padding(.horizontal, ProofTheme.spacingMD)
                .padding(.top, ProofTheme.spacingSM)

                Spacer()

                // Status indicators on dark pills
                statusBar
                    .padding(.horizontal, ProofTheme.spacingMD)
                    .padding(.bottom, ProofTheme.spacingSM)

                // Instruction on dark pill
                Text(currentPose.instruction)
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, ProofTheme.spacingMD)
                    .padding(.vertical, ProofTheme.spacingSM)
                    .background(ProofTheme.overlayPill)
                    .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusSM))
                    .padding(.horizontal, ProofTheme.spacingLG)
                    .padding(.bottom, ProofTheme.spacingMD)
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: ProofTheme.spacingMD) {
            statusIndicator(
                quality: lightingAnalyzer.quality,
                label: lightingAnalyzer.feedback
            )

            Spacer()

            statusIndicator(
                quality: poseDetector.positionQuality,
                label: poseDetector.feedback
            )
        }
        .padding(.horizontal, ProofTheme.spacingMD)
        .padding(.vertical, ProofTheme.spacingSM)
        .background(ProofTheme.overlayPill)
        .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusSM))
    }

    private func statusIndicator(quality: QualityLevel, label: String) -> some View {
        HStack(spacing: ProofTheme.spacingXS) {
            Circle()
                .fill(colorForQuality(quality))
                .frame(width: 8, height: 8)

            Text(label)
                .font(.system(size: 12, weight: .light))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
        }
    }

    private func colorForQuality(_ quality: QualityLevel) -> Color {
        switch quality {
        case .good: ProofTheme.statusGood
        case .fair: ProofTheme.statusFair
        case .poor: ProofTheme.statusPoor
        }
    }
}
```

- [ ] **Step 2: Update PoseGuideOverlay with silhouette-style guide**

Add `currentPose` parameter to PoseGuideOverlay. Show a dashed body outline at the target position instead of just tracking the detected body. When no body is detected, show a centered silhouette outline as a "stand here" target.

```swift
import SwiftUI

struct PoseGuideOverlay: View {
    let poseDetector: PoseDetector
    let currentPose: Pose

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Target zone — always visible
                targetSilhouette(in: geometry.size)

                if poseDetector.bodyDetected {
                    bodyOutline(in: geometry.size)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func targetSilhouette(in size: CGSize) -> some View {
        // Centered dashed rectangle showing where to stand
        let targetWidth = size.width * 0.4
        let targetHeight = size.height * 0.75
        let targetX = size.width / 2
        let targetY = size.height / 2

        return RoundedRectangle(cornerRadius: ProofTheme.radiusMD)
            .stroke(ProofTheme.textTertiary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [8, 6]))
            .frame(width: targetWidth, height: targetHeight)
            .position(x: targetX, y: targetY)
    }

    private func bodyOutline(in size: CGSize) -> some View {
        let rect = normalizedToView(poseDetector.bodyRect, in: size)

        return RoundedRectangle(cornerRadius: ProofTheme.radiusMD)
            .stroke(outlineColor, lineWidth: 2)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    private var outlineColor: Color {
        switch poseDetector.positionQuality {
        case .good: ProofTheme.statusGood
        case .fair: ProofTheme.statusFair
        case .poor: ProofTheme.statusPoor
        }
    }

    private func normalizedToView(_ normalized: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: normalized.origin.x * size.width,
            y: normalized.origin.y * size.height,
            width: normalized.width * size.width,
            height: normalized.height * size.height
        )
    }
}
```

- [ ] **Step 3: Update SessionView — configurable countdown, haptics, auto-positioning feedback**

Update `countdownValue` to use `UserPreferences.countdownSeconds`. Add haptic on capture. Ensure countdown overlay text is on a dark circle for readability.

Key changes to SessionView:
- `countdownValue` initialized from `UserPreferences.countdownSeconds`
- Add `ProofTheme.hapticMedium()` when capture completes
- Countdown number rendered inside a dark circle for contrast
- "Hold still" text on dark pill

- [ ] **Step 4: Build and verify**
- [ ] **Step 5: Commit**

```bash
git commit -m "feat: readable camera overlays, camera flip/torch, pose silhouette guide"
```

---

## Task 7: Home Screen Redesign

**Files:**
- Modify: `ProofCapture/Views/HomeView.swift`
- Create: `ProofCapture/Views/SettingsView.swift`

Redesign HomeView: show last session date, settings gear, guidance mode, cleaner layout. Add SettingsView with gender, voice mode, timer, sign out.

- [ ] **Step 1: Rewrite HomeView**

Remove the massive empty spacers. Add last session info, settings access. Tighter layout.

```swift
import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \PhotoSession.date, order: .reverse) private var sessions: [PhotoSession]
    @AppStorage("guidanceMode") private var guidanceMode: Int = 0

    private var lastSession: PhotoSession? { sessions.first }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Text("PROOF")
                    .font(.system(size: 17, weight: .light))
                    .tracking(4)
                    .foregroundStyle(ProofTheme.textTertiary)

                Spacer()

                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .light))
                        .foregroundStyle(ProofTheme.textTertiary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, ProofTheme.spacingMD)
            .padding(.top, ProofTheme.spacingSM)

            Spacer()

            // Last session info
            if let last = lastSession {
                Text("Last session")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(ProofTheme.textTertiary)
                Text(last.date, style: .relative)
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(ProofTheme.textSecondary)
                    .padding(.top, ProofTheme.spacingXS)
            }

            Spacer()
                .frame(height: ProofTheme.spacingXL)

            // Capture button
            NavigationLink(destination: SessionView()) {
                VStack(spacing: ProofTheme.spacingSM) {
                    ZStack {
                        Circle()
                            .fill(ProofTheme.accent)
                            .frame(width: 80, height: 80)

                        Image(systemName: "camera.fill")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(ProofTheme.background)
                            .accessibilityHidden(true)
                    }

                    Text("Start Session")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(ProofTheme.textSecondary)
                }
            }
            .accessibilityLabel("Start photo session")

            Spacer()

            // Bottom links
            VStack(spacing: ProofTheme.spacingMD) {
                NavigationLink(destination: HistoryView()) {
                    Text("History")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(ProofTheme.textTertiary)
                        .frame(minHeight: 44)
                }
            }
            .padding(.bottom, ProofTheme.spacingXL)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ProofTheme.background)
        .toolbar(.hidden, for: .navigationBar)
    }
}
```

- [ ] **Step 2: Create SettingsView**

```swift
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    @AppStorage("userGender") private var genderRaw = 0
    @AppStorage("guidanceMode") private var guidanceMode = 0
    @AppStorage("countdownSeconds") private var countdownSeconds = 5

    var body: some View {
        List {
            Section {
                Picker("Guide voice", selection: $genderRaw) {
                    Text("Male").tag(0)
                    Text("Female").tag(1)
                }

                Picker("Guidance mode", selection: $guidanceMode) {
                    Text("Voice").tag(0)
                    Text("Text only").tag(1)
                }

                Picker("Countdown", selection: $countdownSeconds) {
                    Text("3 seconds").tag(3)
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                }
            } header: {
                Text("CAPTURE")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(ProofTheme.textTertiary)
            }
            .listRowBackground(ProofTheme.surface)

            Section {
                Button("Sign out") {
                    Task {
                        await authManager.signOut()
                        dismiss()
                    }
                }
                .foregroundStyle(ProofTheme.statusPoor)
            }
            .listRowBackground(ProofTheme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(ProofTheme.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

- [ ] **Step 3: Build and verify**
- [ ] **Step 4: Commit**

```bash
git commit -m "feat: redesign home screen + add settings view"
```

---

## Task 8: History + Full Photo Viewer + Comparison

**Files:**
- Modify: `ProofCapture/Views/HistoryView.swift`
- Modify: `ProofCapture/Views/ReviewView.swift`
- Create: `ProofCapture/Views/FullPhotoView.swift`
- Create: `ProofCapture/Views/ComparisonView.swift`

- [ ] **Step 1: Create FullPhotoView — tap to see full-screen photo**

```swift
import SwiftUI

struct FullPhotoView: View {
    let image: UIImage
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .accessibilityLabel(title)
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(ProofTheme.overlayPill)
                    .clipShape(Circle())
            }
            .padding(.leading, ProofTheme.spacingMD)
            .padding(.top, ProofTheme.spacingSM)
            .accessibilityLabel("Close")
        }
    }
}
```

- [ ] **Step 2: Create ComparisonView — side-by-side two sessions**

```swift
import SwiftUI

struct ComparisonView: View {
    let sessionA: PhotoSession
    let sessionB: PhotoSession
    @State private var selectedPose: Pose = .front

    var body: some View {
        VStack(spacing: 0) {
            // Pose picker
            HStack(spacing: 0) {
                ForEach(Pose.allCases) { pose in
                    Button {
                        selectedPose = pose
                        ProofTheme.hapticLight()
                    } label: {
                        Text(pose.title)
                            .font(.system(size: 13, weight: .light))
                            .foregroundStyle(selectedPose == pose ? ProofTheme.textPrimary : ProofTheme.textTertiary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                }
            }
            .padding(.horizontal, ProofTheme.spacingMD)

            // Side by side
            HStack(spacing: 2) {
                photoColumn(session: sessionA, pose: selectedPose)
                photoColumn(session: sessionB, pose: selectedPose)
            }
            .frame(maxHeight: .infinity)

            // Date labels
            HStack {
                Text(sessionA.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(ProofTheme.textTertiary)
                    .frame(maxWidth: .infinity)

                Text(sessionB.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(ProofTheme.textTertiary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, ProofTheme.spacingSM)
        }
        .background(ProofTheme.background)
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func photoColumn(session: PhotoSession, pose: Pose) -> some View {
        Group {
            if let image = session.photo(for: pose) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else {
                Rectangle()
                    .fill(ProofTheme.surface)
                    .overlay(
                        Text("No photo")
                            .font(.system(size: 13, weight: .light))
                            .foregroundStyle(ProofTheme.textTertiary)
                    )
            }
        }
    }
}
```

- [ ] **Step 3: Update HistoryView — larger thumbnails, comparison entry**

Replace the 40x40 circular thumbnails with larger rectangular thumbnails. Add "Compare" button when 2+ sessions exist. Make rows tappable to full review.

- [ ] **Step 4: Update ReviewView — larger photos, tap for full-screen**

Make the 110x160 photos much larger (fill available width / 3 with padding). Add NavigationLink/sheet to FullPhotoView on tap. Add "Compare with previous" button if previous session exists.

- [ ] **Step 5: Build and verify**
- [ ] **Step 6: Commit**

```bash
git commit -m "feat: full photo viewer, comparison view, improved history"
```

---

## Task 9: Final Polish + xcodegen + Build Verify

**Files:**
- Modify: `ProofCapture/ProofCaptureApp.swift` — ensure all environment objects are injected
- Run: `xcodegen generate` to pick up new files
- Full build verification

- [ ] **Step 1: Regenerate Xcode project**

```bash
cd /Users/imraan/Desktop/proof-capture
xcodegen generate
```

- [ ] **Step 2: Full build**

```bash
xcodebuild -project ProofCapture.xcodeproj -scheme ProofCapture -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
```

- [ ] **Step 3: Run ios-design-audit skill on the rebuilt codebase**
- [ ] **Step 4: Fix any audit findings**
- [ ] **Step 5: Final commit**

```bash
git commit -m "feat: complete rebuild — onboarding, camera controls, design, comparison"
```

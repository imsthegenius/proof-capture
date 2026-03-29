import SwiftUI
import AVFoundation
import SwiftData

private enum SessionPhase {
    case positioning
    case countdown
    case capturing
    case preview    // 2-second auto-advance showing captured photo
    case complete
}

struct SessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncManager.self) private var syncManager

    @State private var currentPose: Pose = .front
    @State private var phase: SessionPhase = .positioning
    @State private var capturedImages: [Pose: UIImage] = [:]
    @State private var countdownValue: Int = 5
    @State private var showAbortConfirmation = false
    @State private var retakePose: Pose?
    @State private var isRetaking = false
    @State private var checkmarkProgress: CGFloat = 0
    @State private var photoScale: CGFloat = 1.03

    @State private var cameraManager = CameraManager()
    @State private var poseDetector = PoseDetector()
    @State private var lightingAnalyzer = LightingAnalyzer()
    @State private var audioGuide = AudioGuide()

    var body: some View {
        ZStack {
            ProofTheme.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, ProofTheme.spacingMD)
                    .padding(.top, ProofTheme.spacingSM)

                Spacer()
                    .frame(height: ProofTheme.spacingSM)

                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                bottomControls
                    .padding(.horizontal, ProofTheme.spacingMD)
                    .padding(.bottom, ProofTheme.spacingLG)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("End Session?", isPresented: $showAbortConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("End", role: .destructive) {
                audioGuide.stop()
                cameraManager.stopSession()
                dismiss()
            }
        } message: {
            Text("Your captured photos will be lost.")
        }
        .task {
            await startSession()
        }
        .onDisappear {
            cameraManager.stopSession()
            audioGuide.stop()
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                showAbortConfirmation = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(ProofTheme.textSecondary)
            }
            .accessibilityLabel("End session")

            Spacer()

            poseStepIndicator

            Spacer()

            Color.clear
                .frame(width: 17, height: 17)
        }
    }

    private var poseStepIndicator: some View {
        HStack(spacing: ProofTheme.spacingSM) {
            ForEach(Pose.allCases) { pose in
                Circle()
                    .fill(stepDotColor(for: pose))
                    .frame(width: 6, height: 6)
            }

            Text("\(currentPose.stepNumber) of 3 — \(currentPose.title)")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(ProofTheme.textSecondary)
        }
    }

    private func stepDotColor(for pose: Pose) -> Color {
        if capturedImages[pose] != nil {
            return ProofTheme.accent
        } else if pose == currentPose {
            return ProofTheme.textPrimary
        } else {
            return ProofTheme.textTertiary
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        switch phase {
        case .positioning, .countdown, .capturing:
            ZStack {
                CaptureView(
                    cameraManager: cameraManager,
                    poseDetector: poseDetector,
                    lightingAnalyzer: lightingAnalyzer,
                    currentPose: currentPose
                )

                if phase == .countdown {
                    countdownOverlay
                }

                if phase == .capturing {
                    capturingOverlay
                }
            }
            .task(id: currentPose) {
                await monitorReadiness()
            }

        case .preview:
            previewView

        case .complete:
            completeView
        }
    }

    // MARK: - Countdown Overlay

    private var countdownOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: ProofTheme.spacingMD) {
                Text(currentPose.title.uppercased())
                    .font(.system(size: 15, weight: .light))
                    .tracking(4)
                    .foregroundStyle(ProofTheme.overlayText.opacity(0.6))

                Text("\(countdownValue)")
                    .font(.system(size: 120, weight: .ultraLight))
                    .foregroundStyle(ProofTheme.accent)
                    .id(countdownValue)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 1.1).combined(with: .opacity),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    ))
            }
            .animation(.easeOut(duration: 0.3), value: countdownValue)
        }
    }

    // MARK: - Capturing Overlay

    private var capturingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            Text("Hold still")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(ProofTheme.overlayText)
        }
    }

    // MARK: - Preview (2-second auto-advance)

    private var previewView: some View {
        ZStack {
            if let image = capturedImages[currentPose] {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusMD))
                    .padding(.horizontal, ProofTheme.spacingMD)
                    .scaleEffect(photoScale)
                    .accessibilityLabel("\(currentPose.title) photo captured")
            }

            // Self-drawing green checkmark overlay
            VStack {
                Spacer()

                Circle()
                    .fill(ProofTheme.statusGood.opacity(0.15))
                    .frame(width: 64, height: 64)
                    .overlay(
                        CheckmarkShape()
                            .trim(from: 0, to: checkmarkProgress)
                            .stroke(ProofTheme.statusGood, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                            .frame(width: 32, height: 32)
                    )

                Spacer()
                    .frame(height: ProofTheme.spacingXL)
            }
        }
        .transition(.opacity)
        .task {
            withAnimation(.easeOut(duration: 0.4)) {
                checkmarkProgress = 1.0
            }
            withAnimation(.easeOut(duration: 0.3)) {
                photoScale = 1.0
            }
            await autoAdvanceAfterPreview()
        }
    }

    // MARK: - Complete View

    private var completeView: some View {
        VStack(spacing: ProofTheme.spacingLG) {
            Text("Session Complete")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(ProofTheme.textPrimary)

            HStack(spacing: ProofTheme.spacingMD) {
                ForEach(Pose.allCases) { pose in
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

                                    // Subtle retake hint
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
                        } else {
                            RoundedRectangle(cornerRadius: ProofTheme.radiusMD)
                                .fill(ProofTheme.surface)
                                .frame(maxWidth: .infinity)
                                .frame(height: 200)
                        }

                        Text(pose.title)
                            .font(.system(size: 12, weight: .light))
                            .foregroundStyle(ProofTheme.textTertiary)
                    }
                }
            }
            .padding(.horizontal, ProofTheme.spacingMD)
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

    private func retakeFromComplete(_ pose: Pose) async {
        isRetaking = true
        capturedImages[pose] = nil
        currentPose = pose
        poseDetector.targetPose = pose
        cameraManager.startSession()
        phase = .positioning
        await audioGuide.speak(pose.audioPrompt)
    }

    // MARK: - Bottom Controls

    @ViewBuilder
    private var bottomControls: some View {
        switch phase {
        case .positioning:
            // Subtle manual capture fallback
            Button {
                Task { await beginCountdown() }
            } label: {
                Text("capture")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(ProofTheme.textTertiary)
            }
            .accessibilityLabel("Manual capture")

        case .countdown, .capturing, .preview:
            EmptyView()

        case .complete:
            VStack(spacing: ProofTheme.spacingSM) {
                Button {
                    Task { await saveAndFinish() }
                } label: {
                    Text("Save to Camera Roll")
                }
                .buttonStyle(ProofTheme.ProofButtonStyle())

                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(ProofTheme.textSecondary)
                }
                .padding(.top, ProofTheme.spacingSM)
            }
        }
    }

    // MARK: - Session Flow

    private func startSession() async {
        poseDetector.targetPose = currentPose
        cameraManager.setSampleBufferDelegates([poseDetector, lightingAnalyzer])
        cameraManager.configure()
        cameraManager.startSession()

        // Go straight to positioning — no preparing delay
        phase = .positioning
        await audioGuide.speak(currentPose.audioPrompt)
    }

    // MARK: - Auto-Capture Readiness Monitor

    private func monitorReadiness() async {
        var readyDuration: TimeInterval = 0
        var timeSinceLastGuidance: TimeInterval = 0
        let checkInterval: TimeInterval = 0.25
        let requiredDuration: TimeInterval = 1.5
        let guidanceInterval: TimeInterval = 4.0

        while !Task.isCancelled && phase == .positioning {
            if poseDetector.isReady && lightingAnalyzer.quality != .poor {
                readyDuration += checkInterval
                if readyDuration >= requiredDuration {
                    try? await Task.sleep(for: .milliseconds(300))
                    await audioGuide.speakAutoReady()
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

    // MARK: - Countdown

    private func beginCountdown() async {
        guard phase == .positioning else { return }
        phase = .countdown
        let seconds = UserDefaults.standard.integer(forKey: "countdownSeconds")
        let countdownDuration = seconds > 0 ? seconds : 5
        countdownValue = countdownDuration

        await audioGuide.playCountdown(seconds: countdownDuration)

        for i in stride(from: countdownDuration, through: 1, by: -1) {
            countdownValue = i
            try? await Task.sleep(for: .seconds(1))
        }

        await captureCurrentPose()
    }

    // MARK: - Capture

    private func captureCurrentPose() async {
        phase = .capturing

        let burst = await cameraManager.captureBurst(count: 7)
        if let best = BurstSelector.selectBest(from: burst, pose: currentPose) {
            capturedImages[currentPose] = best
        } else if let first = burst.first {
            capturedImages[currentPose] = first
        }

        ProofTheme.hapticSuccess()
        checkmarkProgress = 0
        photoScale = 1.03
        phase = .preview
    }

    // MARK: - Preview Auto-Advance

    private func autoAdvanceAfterPreview() async {
        try? await Task.sleep(for: .seconds(2))
        guard phase == .preview else { return }

        // After a retake, always return to complete — don't advance the sequence
        if isRetaking {
            isRetaking = false
            cameraManager.stopSession()
            phase = .complete
            return
        }

        if let next = currentPose.next {
            currentPose = next
            poseDetector.targetPose = next
            phase = .positioning
            await audioGuide.speak(currentPose.audioPrompt)
        } else {
            cameraManager.stopSession()
            phase = .complete
        }
    }

    // MARK: - Save

    private func saveAndFinish() async {
        let session = PhotoSession()

        for pose in Pose.allCases {
            if let image = capturedImages[pose] {
                session.setPhoto(image, for: pose)
                _ = await cameraManager.saveToPhotoLibrary(image)
            }
        }

        modelContext.insert(session)
        try? modelContext.save()
        Task { await syncManager.syncPendingSessions() }
        dismiss()
    }
}

// MARK: - Checkmark Shape

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.2, y: h * 0.5))
        path.addLine(to: CGPoint(x: w * 0.4, y: h * 0.7))
        path.addLine(to: CGPoint(x: w * 0.8, y: h * 0.3))
        return path
    }
}

#Preview {
    SessionView()
        .preferredColorScheme(.dark)
}

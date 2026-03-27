import SwiftUI
import AVFoundation
import SwiftData

private enum SessionPhase {
    case preparing
    case positioning
    case countdown
    case capturing
    case reviewing
    case complete
}

struct SessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncManager.self) private var syncManager

    @State private var currentPose: Pose = .front
    @State private var phase: SessionPhase = .preparing
    @State private var capturedImages: [Pose: UIImage] = [:]
    @State private var countdownValue: Int = 5
    @State private var showAbortConfirmation = false

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
        case .preparing:
            preparingView

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

        case .reviewing:
            reviewingView

        case .complete:
            completeView
        }
    }

    private var preparingView: some View {
        VStack(spacing: ProofTheme.spacingMD) {
            Text("Setting up camera")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(ProofTheme.textPrimary)

            ProgressView()
                .tint(ProofTheme.textSecondary)
        }
    }

    private var countdownOverlay: some View {
        ZStack {
            ProofTheme.overlayPill
                .ignoresSafeArea()

            ZStack {
                Circle()
                    .fill(ProofTheme.overlayPill)
                    .frame(width: 120, height: 120)

                Text("\(countdownValue)")
                    .font(.system(size: 88, weight: .thin))
                    .foregroundStyle(ProofTheme.accent)
                    .contentTransition(.numericText())
            }
        }
    }

    private var capturingOverlay: some View {
        ZStack {
            ProofTheme.overlayPill
                .ignoresSafeArea()

            Text("Hold still")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.white)
        }
    }

    private var reviewingView: some View {
        VStack(spacing: ProofTheme.spacingMD) {
            if let image = capturedImages[currentPose] {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusMD))
                    .padding(.horizontal, ProofTheme.spacingMD)
                    .accessibilityLabel("\(currentPose.title) photo preview")
            }
        }
    }

    private var completeView: some View {
        VStack(spacing: ProofTheme.spacingLG) {
            Text("Session Complete")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(ProofTheme.textPrimary)

            HStack(spacing: ProofTheme.spacingMD) {
                ForEach(Pose.allCases) { pose in
                    VStack(spacing: ProofTheme.spacingSM) {
                        if let image = capturedImages[pose] {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 100, height: 140)
                                .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusMD))
                                .accessibilityLabel("\(pose.title) photo")
                        } else {
                            RoundedRectangle(cornerRadius: ProofTheme.radiusMD)
                                .fill(ProofTheme.surface)
                                .frame(width: 100, height: 140)
                        }

                        Text(pose.title)
                            .font(.system(size: 12, weight: .light))
                            .foregroundStyle(ProofTheme.textTertiary)
                    }
                }
            }
        }
    }

    // MARK: - Bottom Controls

    @ViewBuilder
    private var bottomControls: some View {
        switch phase {
        case .preparing:
            EmptyView()

        case .positioning:
            Button {
                Task { await beginCountdown() }
            } label: {
                Text("Capture now")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(ProofTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(ProofTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusSM))
            }

        case .countdown, .capturing:
            EmptyView()

        case .reviewing:
            HStack(spacing: ProofTheme.spacingMD) {
                Button {
                    Task { await retakeCurrentPose() }
                } label: {
                    Text("Retake")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(ProofTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(ProofTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusSM))
                }

                Button {
                    Task { await acceptAndAdvance() }
                } label: {
                    Text(currentPose.next != nil ? "Next" : "Finish")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(ProofTheme.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(ProofTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusSM))
                }
            }

        case .complete:
            VStack(spacing: ProofTheme.spacingSM) {
                Button {
                    Task { await saveAndFinish() }
                } label: {
                    Text("Save to Camera Roll")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(ProofTheme.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(ProofTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusSM))
                }

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

        try? await Task.sleep(for: .milliseconds(500))
        phase = .positioning

        await audioGuide.speak(currentPose.audioPrompt)
    }

    // MARK: - Auto-Capture Readiness Monitor

    private func monitorReadiness() async {
        var readyDuration: TimeInterval = 0
        let checkInterval: TimeInterval = 0.25
        let requiredDuration: TimeInterval = 1.5

        while !Task.isCancelled && phase == .positioning {
            if poseDetector.isReady && lightingAnalyzer.quality != .poor {
                readyDuration += checkInterval
                if readyDuration >= requiredDuration {
                    await audioGuide.speakAutoReady()
                    await beginCountdown()
                    return
                }
            } else {
                readyDuration = 0
            }
            try? await Task.sleep(for: .milliseconds(Int(checkInterval * 1000)))
        }
    }

    private func beginCountdown() async {
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

    private func captureCurrentPose() async {
        phase = .capturing

        let burst = await cameraManager.captureBurst(count: 7)
        if let best = BurstSelector.selectBest(from: burst) {
            capturedImages[currentPose] = best
        } else if let first = burst.first {
            capturedImages[currentPose] = first
        }

        ProofTheme.hapticSuccess()
        phase = .reviewing
    }

    private func retakeCurrentPose() async {
        capturedImages[currentPose] = nil
        phase = .positioning
        await audioGuide.speak(currentPose.audioPrompt)
    }

    private func acceptAndAdvance() async {
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

#Preview {
    SessionView()
        .preferredColorScheme(.dark)
}

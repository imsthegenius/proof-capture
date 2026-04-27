import SwiftData
import SwiftUI
import UIKit

struct SessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SyncManager.self) private var syncManager

    @State private var viewModel = SessionViewModel()

    var body: some View {
        ZStack {
            if viewModel.phase == .preCaptureInstruction {
                PreCaptureInstructionView(
                    progress: 0.33,
                    onContinue: {
                        Task { @MainActor in
                            await viewModel.continueFromPreCaptureInstruction()
                        }
                    },
                    onCancel: {
                        viewModel.endSession(modelContext: modelContext)
                        dismiss()
                    }
                )
            } else if isCameraPhase {
                captureStage
                    .ignoresSafeArea()
            } else {
                sessionChrome
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert(viewModel.abortTitle, isPresented: abortConfirmationBinding) {
            Button("Cancel", role: .cancel) {}
            Button(viewModel.hasSavedProgress ? "Save Draft" : "End") {
                viewModel.endSession(modelContext: modelContext)
                dismiss()
            }
        } message: {
            Text(viewModel.abortMessage)
        }
        .task {
            await viewModel.startSession(modelContext: modelContext)
        }
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.handleScenePhaseChange(newPhase, modelContext: modelContext)
        }
        .onDisappear {
            viewModel.handleViewExit(modelContext: modelContext, syncManager: syncManager)
        }
        .alert("Retake \(viewModel.retakePose?.title ?? "") photo?", isPresented: retakeAlertBinding) {
            Button("Cancel", role: .cancel) {
                viewModel.retakePose = nil
            }
            Button("Retake") {
                guard let pose = viewModel.retakePose else { return }
                Task { @MainActor in
                    await viewModel.retakeFromComplete(pose, modelContext: modelContext)
                }
            }
        } message: {
            Text("The camera will reopen for this pose only.")
        }
    }

    private var isCameraPhase: Bool {
        switch viewModel.phase {
        case .positioning, .countdown, .capturing:
            return true
        case .preCaptureInstruction, .preview, .complete:
            return false
        }
    }

    private var sessionChrome: some View {
        ZStack {
            (viewModel.phase == .complete ? ProofTheme.paperHi : ProofTheme.background)
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
    }

    private var abortConfirmationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showAbortConfirmation },
            set: { viewModel.showAbortConfirmation = $0 }
        )
    }

    private var retakeAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.retakePose != nil },
            set: { if !$0 { viewModel.retakePose = nil } }
        )
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                viewModel.showAbortConfirmation = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(viewModel.phase == .complete ? ProofTheme.inkSoft : ProofTheme.textSecondary)
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

            Text("\(viewModel.currentPose.stepNumber) of 3 — \(viewModel.currentPose.title)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(viewModel.phase == .complete ? ProofTheme.inkSoft : ProofTheme.textSecondary)
        }
    }

    private func stepDotColor(for pose: Pose) -> Color {
        let isPaperSurface = viewModel.phase == .complete

        if viewModel.capturedImages[pose] != nil {
            return isPaperSurface ? ProofTheme.inkPrimary : ProofTheme.accent
        } else if pose == viewModel.currentPose {
            return isPaperSurface ? ProofTheme.inkPrimary : ProofTheme.textPrimary
        } else {
            return isPaperSurface ? ProofTheme.inkSoft.opacity(0.35) : ProofTheme.textTertiary
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        switch viewModel.phase {
        case .preCaptureInstruction:
            EmptyView()
        case .positioning, .countdown, .capturing:
            captureStage
        case .preview:
            previewView
        case .complete:
            completeView
        }
    }

    private var captureStage: some View {
        ZStack {
            CaptureView(
                cameraManager: viewModel.cameraManager,
                poseDetector: viewModel.poseDetector,
                lightingAnalyzer: viewModel.lightingAnalyzer,
                currentPose: viewModel.currentPose,
                manualCaptureDisabled: viewModel.captureStatusMessage != nil,
                onManualCapture: {
                    Task { @MainActor in
                        await viewModel.beginCountdown()
                    }
                }
            )

            if viewModel.phase == .countdown {
                countdownOverlay
            }

            if viewModel.phase == .capturing {
                capturingOverlay
            }

            if viewModel.captureFlashOpacity > 0 {
                ProofTheme.overlayText
                    .opacity(viewModel.captureFlashOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            if let message = viewModel.captureStatusMessage {
                recoveryOverlay(message: message)
            }
        }
        .task(id: viewModel.currentPose) {
            await viewModel.monitorReadiness()
        }
    }

    // MARK: - Countdown Overlay

    private var countdownOverlay: some View {
        ZStack {
            VStack(spacing: 24) {
                Text(viewModel.currentPose.title.uppercased())
                    .font(.system(size: 15, weight: .medium))
                    .tracking(4)
                    .foregroundStyle(ProofTheme.paperHi.opacity(0.7))

                CountdownNumeral(value: viewModel.countdownValue)
            }
            .animation(.easeOut(duration: 0.3), value: viewModel.countdownValue)
        }
    }

    // MARK: - Capturing Overlay

    private var capturingOverlay: some View {
        ZStack {
            ProofTheme.overlayScrimLight
                .ignoresSafeArea()

            if viewModel.captureFlashOpacity < 0.2 {
                Text("Hold still")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(ProofTheme.overlayText)
            }
        }
    }

    // MARK: - Preview

    private var previewView: some View {
        ZStack {
            if let image = viewModel.capturedImages[viewModel.currentPose] {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusMD))
                    .padding(.horizontal, ProofTheme.spacingMD)
                    .scaleEffect(viewModel.photoScale)
                    .accessibilityLabel("\(viewModel.currentPose.title) photo captured")
            }

            VStack {
                Spacer()

                Circle()
                    .fill(ProofTheme.statusGood.opacity(0.15))
                    .frame(width: 64, height: 64)
                    .overlay(
                        CheckmarkShape()
                            .trim(from: 0, to: viewModel.checkmarkProgress)
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
                viewModel.checkmarkProgress = 1.0
            }

            withAnimation(.easeOut(duration: 0.3)) {
                viewModel.photoScale = 1.0
            }

            await viewModel.autoAdvanceAfterPreview()
        }
    }

    // MARK: - Complete View

    private var completeView: some View {
        VStack(spacing: ProofTheme.spacingLG) {
            Text("Session Complete")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(ProofTheme.inkPrimary)
                .opacity(viewModel.showCompleteContent ? 1 : 0)
                .offset(y: viewModel.showCompleteContent ? 0 : 18)
                .scaleEffect(viewModel.showCompleteContent ? 1 : 0.98)

            HStack(spacing: ProofTheme.spacingMD) {
                ForEach(Array(Pose.allCases.enumerated()), id: \.offset) { index, pose in
                    VStack(spacing: ProofTheme.spacingSM) {
                        if let image = viewModel.capturedImages[pose] {
                            Button {
                                viewModel.retakePose = pose
                            } label: {
                                ZStack(alignment: .bottom) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 200)
                                        .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusMD))

                                    Text("Tap to retake")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(ProofTheme.overlayText.opacity(0.6))
                                        .padding(.vertical, ProofTheme.spacingXS)
                                        .frame(maxWidth: .infinity)
                                        .background(ProofTheme.overlayPill.opacity(0.7))
                                        .clipShape(UnevenRoundedRectangle(
                                            bottomLeadingRadius: ProofTheme.radiusMD,
                                            bottomTrailingRadius: ProofTheme.radiusMD
                                        ))
                                }
                            }
                            .accessibilityLabel("Retake \(pose.title) photo")
                        } else {
                            RoundedRectangle(cornerRadius: ProofTheme.radiusMD)
                                .fill(ProofTheme.paperLo)
                                .frame(maxWidth: .infinity)
                                .frame(height: 200)
                        }

                        Text(pose.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ProofTheme.inkSoft)
                    }
                    .opacity(viewModel.showCompleteContent ? 1 : 0)
                    .offset(y: viewModel.showCompleteContent ? 0 : 20)
                    .scaleEffect(viewModel.showCompleteContent ? 1 : 0.96)
                    .animation(
                        .easeOut(duration: 0.45).delay(0.08 * Double(index)),
                        value: viewModel.showCompleteContent
                    )
                }
            }
            .padding(.horizontal, ProofTheme.spacingMD)
            .opacity(viewModel.showCompleteContent ? 1 : 0)
            .offset(y: viewModel.showCompleteContent ? 0 : 18)
            .animation(.easeOut(duration: 0.45).delay(0.08), value: viewModel.showCompleteContent)

            if viewModel.showCompleteContent, !qualityWarningIssues.isEmpty {
                qualityWarningView
                    .padding(.horizontal, ProofTheme.spacingMD)
                    .padding(.top, ProofTheme.spacingSM)
                    .transition(.opacity)
            }

            Spacer()
        }
        .padding(.horizontal, ProofTheme.spacingMD)
        .padding(.top, ProofTheme.spacingXL)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var qualityWarningIssues: [(id: String, pose: Pose, issue: String)] {
        Pose.allCases.flatMap { pose in
            (viewModel.qualityReports[pose]?.issues ?? []).map {
                (id: "\(pose.title)-\($0)", pose: pose, issue: $0)
            }
        }
    }

    private var qualityWarningView: some View {
        VStack(alignment: .leading, spacing: ProofTheme.spacingSM) {
            HStack(spacing: ProofTheme.spacingSM) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ProofTheme.statusFair)

                Text("Some photos may be hard to compare")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ProofTheme.inkPrimary)
            }

            ForEach(qualityWarningIssues, id: \.id) { item in
                HStack(spacing: ProofTheme.spacingSM) {
                    Text("\(item.pose.title):")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ProofTheme.inkSoft)

                    Text(item.issue)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(ProofTheme.statusFair)
                }
            }
        }
        .padding(ProofTheme.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ProofTheme.paperLo)
        .overlay(
            RoundedRectangle(cornerRadius: ProofTheme.radiusMD)
                .stroke(ProofTheme.statusFair.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusMD))
        .accessibilityLabel("Quality warning: some photos may be difficult to compare")
    }

    // MARK: - Bottom Controls

    @ViewBuilder
    private var bottomControls: some View {
        switch viewModel.phase {
        case .preCaptureInstruction, .positioning, .countdown, .capturing, .preview:
            EmptyView()

        case .complete:
            VStack(spacing: ProofTheme.spacingSM) {
                LiquidGlassButton(variant: .paperLight, action: {
                    Task { @MainActor in
                        await viewModel.saveAndFinish(modelContext: modelContext)
                        dismiss()
                    }
                }) {
                    Text("Save to Camera Roll")
                }

                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(ProofTheme.inkSoft)
                }
                .padding(.top, ProofTheme.spacingSM)
            }
            .opacity(viewModel.showCompleteContent ? 1 : 0)
            .offset(y: viewModel.showCompleteContent ? 0 : 18)
            .animation(.easeOut(duration: 0.45).delay(0.16), value: viewModel.showCompleteContent)
        }
    }

    // MARK: - Recovery UI

    private func recoveryOverlay(message: String) -> some View {
        VStack(spacing: ProofTheme.spacingMD) {
            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ProofTheme.overlayText)
                .multilineTextAlignment(.center)

            if viewModel.cameraManager.needsPermissionRecovery {
                LiquidGlassButton(action: {
                    openSettings()
                }) {
                    Text("Open Settings")
                }
            } else {
                LiquidGlassButton(action: {
                    Task { @MainActor in
                        await viewModel.resumeCapturePipeline(playPrompt: false)
                    }
                }) {
                    Text("Retry")
                }
            }
        }
        .padding(ProofTheme.spacingLG)
        .background(ProofTheme.overlayPill)
        .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusLG))
        .padding(.horizontal, ProofTheme.spacingMD)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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
}

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

            Text("\(viewModel.currentPose.stepNumber) of 3 — \(viewModel.currentPose.title)")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(ProofTheme.textSecondary)
        }
    }

    private func stepDotColor(for pose: Pose) -> Color {
        if viewModel.capturedImages[pose] != nil {
            return ProofTheme.accent
        } else if pose == viewModel.currentPose {
            return ProofTheme.textPrimary
        } else {
            return ProofTheme.textTertiary
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        switch viewModel.phase {
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
                liveAssessment: viewModel.liveAssessment
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
            ProofTheme.overlayScrim
                .ignoresSafeArea()

            VStack(spacing: ProofTheme.spacingMD) {
                Text(viewModel.currentPose.title.uppercased())
                    .font(.system(size: 15, weight: .light))
                    .tracking(4)
                    .foregroundStyle(ProofTheme.overlayText.opacity(0.6))

                Text("\(viewModel.countdownValue)")
                    .font(.system(size: 120, weight: .ultraLight))
                    .foregroundStyle(ProofTheme.accent)
                    .id(viewModel.countdownValue)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 1.1).combined(with: .opacity),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    ))
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
                    .font(.system(size: 20, weight: .light))
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
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(ProofTheme.textPrimary)
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

            if viewModel.showCompleteContent, !qualityWarningItems.isEmpty {
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

    /// Only surface catastrophic/burst-local failures — lighting/framing/neutrality
    /// should have been solved by the live gate, not "discovered" post-capture.
    private var qualityWarningItems: [(id: String, pose: Pose, verdict: CheckInVisualAssessment.ReviewVerdict, reason: String)] {
        Pose.allCases.compactMap { pose -> (id: String, pose: Pose, verdict: CheckInVisualAssessment.ReviewVerdict, reason: String)? in
            guard let assessment = viewModel.capturedAssessments[pose] else { return nil }
            switch assessment.reviewVerdict {
            case .keep:
                return nil
            case .warn:
                return (id: "\(pose.title)-warn", pose: pose, verdict: .warn, reason: assessment.primaryReason)
            case .retakeRecommended:
                return (id: "\(pose.title)-retake", pose: pose, verdict: .retakeRecommended, reason: assessment.primaryReason)
            }
        }
    }

    private var qualityWarningView: some View {
        let hasRetake = qualityWarningItems.contains { $0.verdict == .retakeRecommended }

        return VStack(alignment: .leading, spacing: ProofTheme.spacingSM) {
            HStack(spacing: ProofTheme.spacingSM) {
                Image(systemName: hasRetake ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(hasRetake ? ProofTheme.statusPoor : ProofTheme.statusFair)

                Text(hasRetake ? "Some photos should be retaken" : "Some photos may be hard to compare")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(ProofTheme.textPrimary)
            }

            ForEach(qualityWarningItems, id: \.id) { item in
                HStack(spacing: ProofTheme.spacingSM) {
                    Text("\(item.pose.title):")
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(ProofTheme.textSecondary)

                    Text(item.reason)
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(item.verdict == .retakeRecommended ? ProofTheme.statusPoor : ProofTheme.statusFair)
                }
            }
        }
        .padding(ProofTheme.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ProofTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: ProofTheme.radiusMD)
                .stroke((hasRetake ? ProofTheme.statusPoor : ProofTheme.statusFair).opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusMD))
        .accessibilityLabel(hasRetake ? "Quality warning: some photos should be retaken" : "Quality warning: some photos may be difficult to compare")
    }

    // MARK: - Bottom Controls

    @ViewBuilder
    private var bottomControls: some View {
        switch viewModel.phase {
        case .positioning:
            Button {
                Task { @MainActor in
                    await viewModel.beginCountdown()
                }
            } label: {
                Text("capture")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(ProofTheme.textTertiary)
            }
            .accessibilityLabel("Manual capture")
            .disabled(viewModel.captureStatusMessage != nil)

        case .countdown, .capturing, .preview:
            EmptyView()

        case .complete:
            VStack(spacing: ProofTheme.spacingSM) {
                Button {
                    Task { @MainActor in
                        await viewModel.saveAndFinish(modelContext: modelContext)
                        dismiss()
                    }
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
            .opacity(viewModel.showCompleteContent ? 1 : 0)
            .offset(y: viewModel.showCompleteContent ? 0 : 18)
            .animation(.easeOut(duration: 0.45).delay(0.16), value: viewModel.showCompleteContent)
        }
    }

    // MARK: - Recovery UI

    private func recoveryOverlay(message: String) -> some View {
        VStack(spacing: ProofTheme.spacingMD) {
            Text(message)
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(ProofTheme.overlayText)
                .multilineTextAlignment(.center)

            if viewModel.cameraManager.needsPermissionRecovery {
                Button("Open Settings") {
                    openSettings()
                }
                .buttonStyle(ProofTheme.ProofButtonStyle())
            } else {
                Button("Retry") {
                    Task { @MainActor in
                        await viewModel.resumeCapturePipeline(playPrompt: false)
                    }
                }
                .buttonStyle(ProofTheme.ProofButtonStyle())
            }
        }
        .padding(ProofTheme.spacingLG)
        .background(.black.opacity(0.72))
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
        .preferredColorScheme(.dark)
}

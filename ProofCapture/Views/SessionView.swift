import SwiftData
import SwiftUI
import UIKit

struct SessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SyncManager.self) private var syncManager
    @AppStorage("guidanceMode") private var guidanceModeRawValue = GuidanceMode.voice.rawValue

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
        .sheet(isPresented: burstReviewBinding) {
            BurstReviewSheet(
                burst: viewModel.currentBurst,
                selectedIndex: burstSelectionBinding,
                pose: viewModel.currentPose,
                onConfirm: {
                    Task { @MainActor in
                        await viewModel.confirmBurstSelection()
                    }
                },
                onRedo: {
                    viewModel.redoBurst()
                }
            )
            .interactiveDismissDisabled()
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

    private var burstReviewBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showBurstReview },
            set: { viewModel.showBurstReview = $0 }
        )
    }

    private var burstSelectionBinding: Binding<Int> {
        Binding(
            get: { viewModel.selectedBurstIndex },
            set: { viewModel.selectedBurstIndex = $0 }
        )
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                viewModel.showAbortConfirmation = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .regular))
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
                .font(.system(size: 13, weight: .regular))
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
        case .positioning, .locked, .poseHold, .countdown, .capturing, .preview:
            // .preview keeps the camera visible — the iOS26 burst review sheet overlays it.
            captureStage
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
                sessionPhase: viewModel.phase,
                captureEdgeState: viewModel.captureEdgeState
            )

            if viewModel.phase == .locked {
                phaseMirrorOverlay(
                    title: "LOCKED",
                    body: guidanceMode == .text ? "Lighting looks good. Take your pose." : nil
                )
            }

            if viewModel.phase == .poseHold {
                phaseMirrorOverlay(
                    title: guidanceMode == .text ? "TAKE YOUR POSE" : "HOLD STILL",
                    body: guidanceMode == .text ? "Hold your pose. Countdown is next." : nil
                )
            }

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
        .task(id: "\(viewModel.currentPose.rawValue)-\(String(describing: viewModel.phase))") {
            if viewModel.phase == .positioning {
                await viewModel.monitorReadiness()
            }
        }
    }

    private var guidanceMode: GuidanceMode {
        GuidanceMode(rawValue: guidanceModeRawValue) ?? .voice
    }

    private func phaseMirrorOverlay(title: String, body: String?) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 40, weight: .medium))
                .tracking(3)
                .foregroundStyle(ProofTheme.paperHi)
                .multilineTextAlignment(.center)

            if let body {
                Text(body)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(ProofTheme.paperHi.opacity(0.84))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .background(.black.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .padding(.horizontal, 28)
        .allowsHitTesting(false)
    }

    // MARK: - Countdown Overlay

    // Per Figma 390:2790/2807/2823 — no scrim, just a giant centered numeral on the live camera.
    // Figma spec: 200pt SF Pro Bold, paperHi cream, tracking 2.
    // swiftlint:disable:next no_bold_weight
    private var countdownOverlay: some View {
        Text("\(viewModel.countdownValue)")
            .font(.system(size: 200, weight: .bold))
            .tracking(2)
            .foregroundStyle(ProofTheme.paperHi)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(viewModel.countdownValue)
            .transition(.asymmetric(
                insertion: .scale(scale: 1.1).combined(with: .opacity),
                removal: .scale(scale: 0.9).combined(with: .opacity)
            ))
            .animation(.easeOut(duration: 0.3), value: viewModel.countdownValue)
            .allowsHitTesting(false)
    }

    // MARK: - Capturing Overlay

    private var capturingOverlay: some View {
        ZStack {
            ProofTheme.overlayScrimLight
                .ignoresSafeArea()

            if viewModel.captureFlashOpacity < 0.2 {
                Text("Hold still")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(ProofTheme.overlayText)
            }
        }
    }

    // MARK: - Complete View

    private var completeView: some View {
        VStack(spacing: ProofTheme.spacingLG) {
            Text("Session Complete")
                .font(.system(size: 24, weight: .regular))
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
                                        .font(.system(size: 11, weight: .regular))
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
                            .font(.system(size: 12, weight: .regular))
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
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(ProofTheme.statusFair)

                Text("Some photos may be hard to compare")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(ProofTheme.textPrimary)
            }

            ForEach(qualityWarningIssues, id: \.id) { item in
                HStack(spacing: ProofTheme.spacingSM) {
                    Text("\(item.pose.title):")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(ProofTheme.textSecondary)

                    Text(item.issue)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(ProofTheme.statusFair)
                }
            }
        }
        .padding(ProofTheme.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ProofTheme.surface)
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
        case .positioning, .locked, .poseHold, .countdown, .capturing, .preview:
            EmptyView()

        case .complete:
            VStack(spacing: ProofTheme.spacingSM) {
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                }
                .buttonStyle(ProofTheme.ProofButtonStyle())

                Button {
                    Task { @MainActor in
                        await viewModel.saveAndFinish(modelContext: modelContext)
                    }
                } label: {
                    Text("Save to Photos")
                        .font(.system(size: 15, weight: .regular))
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
                .font(.system(size: 15, weight: .regular))
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

// MARK: - Burst Review Sheet (iOS26 slide-up)
//
// Shown immediately after a burst capture, before advancing to the next pose.
// Lets the user swipe through every frame in the burst, pick one, and confirm —
// or redo the capture entirely.
struct BurstReviewSheet: View {
    let burst: [UIImage]
    @Binding var selectedIndex: Int
    let pose: Pose
    let onConfirm: () -> Void
    let onRedo: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header

            if burst.isEmpty {
                Spacer()
                Text("No frames captured")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(ProofTheme.textSecondary)
                Spacer()
            } else {
                burstCarousel
                frameIndicator
            }

            Spacer(minLength: 0)

            actions
                .padding(.horizontal, ProofTheme.spacingMD)
                .padding(.bottom, ProofTheme.spacingLG)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(sheetBackground)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
    }

    @ViewBuilder
    private var sheetBackground: some View {
        if #available(iOS 26, *) {
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: .rect)
                .ignoresSafeArea()
        } else {
            ProofTheme.background
                .ignoresSafeArea()
        }
    }

    private var header: some View {
        VStack(spacing: ProofTheme.spacingXS) {
            Text(pose.title.uppercased())
                .font(.system(size: 11, weight: .medium))
                .tracking(2)
                .foregroundStyle(ProofTheme.textTertiary)

            Text("Pick your shot")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(ProofTheme.textPrimary)
        }
        .padding(.top, ProofTheme.spacingMD)
        .padding(.bottom, ProofTheme.spacingMD)
        .accessibilityAddTraits(.isHeader)
    }

    private var burstCarousel: some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(burst.enumerated()), id: \.offset) { index, image in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusLG))
                    .padding(.horizontal, ProofTheme.spacingMD)
                    .tag(index)
                    .accessibilityLabel("Frame \(index + 1) of \(burst.count)")
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxHeight: .infinity)
    }

    private var frameIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<burst.count, id: \.self) { index in
                Circle()
                    .fill(ProofTheme.accent.opacity(index == selectedIndex ? 1.0 : 0.25))
                    .frame(width: 6, height: 6)
                    .animation(.easeOut(duration: ProofTheme.animationFast), value: selectedIndex)
            }
        }
        .padding(.vertical, ProofTheme.spacingMD)
        .accessibilityLabel("Frame \(selectedIndex + 1) of \(burst.count)")
    }

    private var actions: some View {
        HStack(spacing: ProofTheme.spacingSM) {
            Button {
                ProofTheme.hapticLight()
                onRedo()
            } label: {
                Text("Redo")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ProofTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .modifier(ProofTheme.SecondaryButtonBackground())
            }
            .accessibilityLabel("Redo capture for \(pose.title)")

            Button {
                ProofTheme.hapticMedium()
                onConfirm()
            } label: {
                Text("Use this shot")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ProofTheme.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .modifier(ProofTheme.PrimaryButtonBackground())
            }
            .accessibilityLabel("Use selected frame for \(pose.title)")
        }
    }
}

#Preview {
    SessionView()
        .preferredColorScheme(.dark)
}

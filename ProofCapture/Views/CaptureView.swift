import SwiftUI
import AVFoundation

struct CaptureView: View {
    let cameraManager: CameraManager
    let poseDetector: PoseDetector
    let lightingAnalyzer: LightingAnalyzer
    let currentPose: Pose

    @AppStorage("guidanceMode") private var guidanceModeRawValue = GuidanceMode.voice.rawValue

    /// Composite readiness level drives the border glow state.
    var overallStatus: QualityLevel {
        if !poseDetector.bodyDetected { return .poor }
        if lightingAnalyzer.quality == .poor && poseDetector.positionQuality == .poor { return .poor }
        if poseDetector.isReady && lightingAnalyzer.quality != .poor { return .good }
        if poseDetector.positionQuality == .good || poseDetector.poseMatchesExpected { return .fair }
        return .poor
    }

    private var guidanceMode: GuidanceMode {
        GuidanceMode(rawValue: guidanceModeRawValue) ?? .voice
    }

    private var isTextGuidanceMode: Bool {
        guidanceMode == .text
    }

    // MARK: - Border glow properties

    private var borderColor: Color {
        switch overallStatus {
        case .good:
            return ProofTheme.borderReady
        case .fair:
            return ProofTheme.borderAlmost
        case .poor:
            return poseDetector.bodyDetected ? ProofTheme.borderNeutral : .clear
        }
    }

    private var borderWidth: CGFloat {
        if readinessLocked && overallStatus == .good {
            return 6
        }

        switch overallStatus {
        case .good:
            return ProofTheme.borderWidthReady
        case .fair:
            return ProofTheme.borderWidthAlmost
        case .poor:
            return ProofTheme.borderWidthNeutral
        }
    }

    @State private var amberPulseActive = false
    @State private var readinessLocked = false

    private var borderOpacity: Double {
        switch overallStatus {
        case .good:
            return 1.0
        case .fair:
            return amberPulseActive ? 1.0 : 0.6
        case .poor:
            return 1.0
        }
    }

    var body: some View {
        ZStack {
            CameraPreview(
                session: cameraManager.session,
                isMirrored: cameraManager.currentPosition == .front
            )
            .ignoresSafeArea()

            PoseGuideOverlay(
                poseDetector: poseDetector,
                overallStatus: overallStatus
            )

            if !poseDetector.bodyDetected {
                Text("Step into frame")
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundStyle(ProofTheme.overlayText.opacity(0.8))
                    .transition(.opacity)
            }

            if isTextGuidanceMode && poseDetector.bodyDetected {
                feedbackPills
            }

            VStack {
                Spacer()

                Text(currentPose.title.uppercased())
                    .font(.system(size: 12, weight: .regular))
                    .tracking(4)
                    .foregroundStyle(ProofTheme.overlayText.opacity(0.4))
                    .padding(.bottom, ProofTheme.spacingXL)
                    .id(currentPose)
                    .transition(.asymmetric(
                        insertion: .offset(y: 8).combined(with: .opacity),
                        removal: .offset(y: -8).combined(with: .opacity)
                    ))
                    .animation(.easeOut(duration: ProofTheme.animationDefault), value: currentPose)
            }

            VStack {
                HStack {
                    Spacer()

                    Button {
                        ProofTheme.hapticLight()
                        cameraManager.switchCamera()
                    } label: {
                        Image(systemName: "camera.rotate")
                            .font(.system(size: 17, weight: .light))
                            .foregroundStyle(ProofTheme.overlayText)
                            .frame(width: 52, height: 52)
                            .modifier(GlassCircle())
                    }
                    .accessibilityLabel("Switch camera")
                }
                .padding(.horizontal, ProofTheme.spacingMD)
                .padding(.top, ProofTheme.spacingSM)

                Spacer()
            }

            RoundedRectangle(cornerRadius: ProofTheme.radiusMD)
                .stroke(borderColor.opacity(borderOpacity), lineWidth: borderWidth)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: ProofTheme.animationSlow), value: overallStatus)
                .animation(.easeInOut(duration: ProofTheme.animationDefault), value: readinessLocked)
                .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: ProofTheme.animationEntrance), value: poseDetector.bodyDetected)
        .onChange(of: overallStatus) { oldValue, newValue in
            if oldValue != .good && newValue == .good {
                ProofTheme.hapticMedium()
                triggerReadinessLock()
            } else if oldValue == .good && newValue != .good {
                readinessLocked = false
            }
        }
        .onAppear { startAmberPulse() }
    }

    // MARK: - Amber Pulse Animation

    private func startAmberPulse() {
        withAnimation(
            .timingCurve(0.37, 0.0, 0.63, 1.0, duration: 1.2)
                .repeatForever(autoreverses: true)
        ) {
            amberPulseActive = true
        }
    }

    private func triggerReadinessLock() {
        Task { @MainActor in
            readinessLocked = true
            try? await Task.sleep(for: .milliseconds(600))
            if overallStatus == .good {
                readinessLocked = false
            }
        }
    }

    private var feedbackPills: some View {
        VStack {
            Spacer()

            VStack(spacing: ProofTheme.spacingSM) {
                if let positionText = positioningFeedbackText {
                    feedbackPill(text: positionText, accent: positioningFeedbackAccent)
                }

                if let lightingText = lightingFeedbackText {
                    feedbackPill(text: lightingText, accent: lightingFeedbackAccent)
                }
            }
            .padding(.horizontal, ProofTheme.spacingMD)
            .padding(.bottom, ProofTheme.spacingXL + 40)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeInOut(duration: ProofTheme.animationFast), value: positioningFeedbackText)
        .animation(.easeInOut(duration: ProofTheme.animationFast), value: lightingFeedbackText)
        .allowsHitTesting(false)
    }

    private var positioningFeedbackText: String? {
        guard poseDetector.bodyDetected else { return nil }
        guard !poseDetector.isReady else { return nil }
        return poseDetector.feedback
    }

    private var lightingFeedbackText: String? {
        guard poseDetector.bodyDetected else { return nil }
        guard lightingAnalyzer.quality != .good else { return nil }
        return lightingAnalyzer.feedback
    }

    private var positioningFeedbackAccent: Color {
        switch poseDetector.positionQuality {
        case .good:
            return ProofTheme.statusGood
        case .fair:
            return ProofTheme.statusFair
        case .poor:
            return ProofTheme.statusPoor
        }
    }

    private var lightingFeedbackAccent: Color {
        switch lightingAnalyzer.quality {
        case .good:
            return ProofTheme.statusGood
        case .fair:
            return ProofTheme.statusFair
        case .poor:
            return ProofTheme.statusPoor
        }
    }

    private func feedbackPill(text: String, accent: Color) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .light))
            .multilineTextAlignment(.center)
            .foregroundStyle(ProofTheme.overlayText)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(maxWidth: 320)
            .background(ProofTheme.overlayPill)
            .overlay(
                Capsule()
                    .stroke(accent.opacity(0.35), lineWidth: 1)
            )
            .clipShape(Capsule())
    }
}

// MARK: - Glass Circle Modifier

private struct GlassCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: .circle)
        } else {
            content
                .background(ProofTheme.overlayScrim)
                .clipShape(Circle())
        }
    }
}

import SwiftUI
import AVFoundation

struct CaptureView: View {
    let cameraManager: CameraManager
    let poseDetector: PoseDetector
    let lightingAnalyzer: LightingAnalyzer
    let currentPose: Pose

    /// Composite readiness level drives the border glow state.
    var overallStatus: QualityLevel {
        if !poseDetector.bodyDetected { return .poor }
        if lightingAnalyzer.quality == .poor && poseDetector.positionQuality == .poor { return .poor }
        if poseDetector.isReady && lightingAnalyzer.quality != .poor { return .good }
        if poseDetector.positionQuality == .good || poseDetector.poseMatchesExpected { return .fair }
        return .poor
    }

    // MARK: - Border glow properties

    private var borderColor: Color {
        switch overallStatus {
        case .good: ProofTheme.borderReady
        case .fair: ProofTheme.borderAlmost
        case .poor:
            poseDetector.bodyDetected ? ProofTheme.borderNeutral : .clear
        }
    }

    private var borderWidth: CGFloat {
        switch overallStatus {
        case .good: ProofTheme.borderWidthReady
        case .fair: ProofTheme.borderWidthAlmost
        case .poor: ProofTheme.borderWidthNeutral
        }
    }

    // Amber state pulses between 0.6 and 1.0 opacity
    @State private var amberPulseActive = false

    private var borderOpacity: Double {
        switch overallStatus {
        case .good: 1.0
        case .fair: amberPulseActive ? 1.0 : 0.6
        case .poor: 1.0 // neutral is already 30% via the color definition
        }
    }

    var body: some View {
        ZStack {
            // Full-screen camera feed
            CameraPreview(session: cameraManager.session)
                .ignoresSafeArea()

            // Body outline overlay (colored to match border state)
            PoseGuideOverlay(
                poseDetector: poseDetector,
                overallStatus: overallStatus
            )

            // "Step into frame" text when no body detected
            if !poseDetector.bodyDetected {
                Text("Step into frame")
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundStyle(ProofTheme.overlayText.opacity(0.8))
                    .transition(.opacity)
            }

            // Pose label at bottom
            VStack {
                Spacer()

                Text(currentPose.title.uppercased())
                    .font(.system(size: 12, weight: .regular))
                    .tracking(4)
                    .foregroundStyle(ProofTheme.overlayText.opacity(0.4))
                    .padding(.bottom, ProofTheme.spacingXL)
            }

            // Camera flip button — top right
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

            // Full-screen border glow overlay
            RoundedRectangle(cornerRadius: ProofTheme.radiusMD)
                .stroke(borderColor.opacity(borderOpacity), lineWidth: borderWidth)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: overallStatus)
                .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.4), value: poseDetector.bodyDetected)
        .onChange(of: overallStatus) { oldValue, newValue in
            // Haptic feedback when transitioning from amber to green
            if oldValue == .fair && newValue == .good {
                ProofTheme.hapticLight()
            }
        }
        .onAppear { startAmberPulse() }
    }

    // MARK: - Amber Pulse Animation

    private func startAmberPulse() {
        withAnimation(
            .easeInOut(duration: 1.2)
            .repeatForever(autoreverses: true)
        ) {
            amberPulseActive = true
        }
    }
}

// MARK: - Glass Circle Modifier

private struct GlassCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: .circle)
        } else {
            content
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
    }
}

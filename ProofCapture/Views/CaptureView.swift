import SwiftUI
import AVFoundation

struct CaptureView: View {
    let cameraManager: CameraManager
    let poseDetector: PoseDetector
    let lightingAnalyzer: LightingAnalyzer
    let currentPose: Pose

    private var overallStatus: QualityLevel {
        if !poseDetector.bodyDetected { return .poor }
        if lightingAnalyzer.quality == .poor && poseDetector.positionQuality == .poor { return .poor }
        if poseDetector.isReady && lightingAnalyzer.quality != .poor { return .good }
        if poseDetector.positionQuality == .good || poseDetector.poseMatchesExpected { return .fair }
        return .poor
    }

    private var statusWord: String {
        switch overallStatus {
        case .good: "READY"
        case .fair: "ALMOST"
        case .poor: poseDetector.bodyDetected ? "ADJUST" : "STEP IN"
        }
    }

    private var statusColor: Color {
        switch overallStatus {
        case .good: ProofTheme.statusGood
        case .fair: ProofTheme.statusFair
        case .poor: ProofTheme.statusPoor
        }
    }

    var body: some View {
        ZStack {
            CameraPreview(session: cameraManager.session)
                .ignoresSafeArea()

            PoseGuideOverlay(poseDetector: poseDetector)

            // Central status ring — readable from 2 meters
            VStack(spacing: ProofTheme.spacingSM) {
                ZStack {
                    Circle()
                        .stroke(statusColor.opacity(0.6), lineWidth: 3)
                        .frame(width: 140, height: 140)

                    Text(statusWord)
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(statusColor)
                }

                // Pose label — small but useful if close enough
                Text(currentPose.title.uppercased())
                    .font(.system(size: 13, weight: .light))
                    .tracking(4)
                    .foregroundStyle(.white.opacity(0.5))
            }

            // Camera flip — top right, larger touch target
            VStack {
                HStack {
                    Spacer()

                    Button {
                        ProofTheme.hapticLight()
                        cameraManager.switchCamera()
                    } label: {
                        Image(systemName: "camera.rotate")
                            .font(.system(size: 17, weight: .light))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .modifier(GlassCircle())
                    }
                    .accessibilityLabel("Switch camera")
                }
                .padding(.horizontal, ProofTheme.spacingMD)
                .padding(.top, ProofTheme.spacingSM)

                Spacer()
            }
        }
    }
}

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

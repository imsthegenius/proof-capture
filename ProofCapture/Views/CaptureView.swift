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

            PoseGuideOverlay(poseDetector: poseDetector)

            VStack {
                // Top controls — camera flip + torch
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
                            .modifier(GlassCircle())
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
                                .modifier(GlassCircle())
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

                // Instruction on glass pill
                Text(currentPose.instruction)
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, ProofTheme.spacingMD)
                    .padding(.vertical, ProofTheme.spacingSM)
                    .modifier(GlassCapsule())
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
        .modifier(GlassCapsule())
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

private struct GlassCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: .circle)
        } else {
            content
                .background(Color.black.opacity(0.65))
                .clipShape(Circle())
        }
    }
}

private struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content
                .background(Color.black.opacity(0.65))
                .clipShape(.capsule)
        }
    }
}

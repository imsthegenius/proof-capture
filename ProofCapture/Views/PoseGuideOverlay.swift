import SwiftUI

struct PoseGuideOverlay: View {
    let poseDetector: PoseDetector
    let overallStatus: QualityLevel

    var body: some View {
        GeometryReader { geometry in
            if poseDetector.bodyDetected {
                bodyOutline(in: geometry.size)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Body Outline

    /// Thin rounded rect around the detected body, colored to match the border glow state.
    private func bodyOutline(in size: CGSize) -> some View {
        let rect = normalizedToView(poseDetector.bodyRect, in: size)

        return RoundedRectangle(cornerRadius: ProofTheme.radiusMD)
            .stroke(outlineColor, lineWidth: 2)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .animation(.easeInOut(duration: 0.3), value: overallStatus)
    }

    /// Colors the outline to match the border glow — unified visual language.
    private var outlineColor: Color {
        switch overallStatus {
        case .good: ProofTheme.borderReady
        case .fair: ProofTheme.borderAlmost
        case .poor: ProofTheme.borderNeutral
        }
    }

    // MARK: - Coordinate Conversion

    private func normalizedToView(_ normalized: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: normalized.origin.x * size.width,
            y: normalized.origin.y * size.height,
            width: normalized.width * size.width,
            height: normalized.height * size.height
        )
    }
}

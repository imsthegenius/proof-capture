import SwiftUI

struct PoseGuideOverlay: View {
    let poseDetector: PoseDetector

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Target zone — dashed outline showing where to stand
                targetSilhouette(in: geometry.size)

                if poseDetector.bodyDetected {
                    bodyOutline(in: geometry.size)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func targetSilhouette(in size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: ProofTheme.radiusMD)
            .stroke(
                ProofTheme.textTertiary.opacity(0.4),
                style: StrokeStyle(lineWidth: 1, dash: [8, 6])
            )
            .frame(width: size.width * 0.4, height: size.height * 0.75)
            .position(x: size.width / 2, y: size.height / 2)
    }

    private func bodyOutline(in size: CGSize) -> some View {
        let rect = normalizedToView(poseDetector.bodyRect, in: size)

        return RoundedRectangle(cornerRadius: ProofTheme.radiusMD)
            .stroke(outlineColor, lineWidth: 2)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    private var outlineColor: Color {
        switch poseDetector.positionQuality {
        case .good: ProofTheme.statusGood
        case .fair: ProofTheme.statusFair
        case .poor: ProofTheme.statusPoor
        }
    }

    private func normalizedToView(_ normalized: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: normalized.origin.x * size.width,
            y: normalized.origin.y * size.height,
            width: normalized.width * size.width,
            height: normalized.height * size.height
        )
    }
}

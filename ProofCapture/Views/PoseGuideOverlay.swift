import SwiftUI

struct PoseGuideOverlay: View {
    let poseDetector: PoseDetector
    let overallStatus: QualityLevel

    var body: some View {
        GeometryReader { geometry in
            let bodyRect = normalizedToView(poseDetector.bodyRect, in: geometry.size)

            ZStack {
                if poseDetector.bodyDetected {
                    bodyOutline(for: bodyRect)
                }

                feedbackPill(for: bodyRect, in: geometry.size)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Body Outline

    /// Thin rounded rect around the detected body, colored to match the border glow state.
    private func bodyOutline(for rect: CGRect) -> some View {
        return RoundedRectangle(cornerRadius: ProofTheme.radiusMD)
            .stroke(outlineColor, lineWidth: outlineLineWidth)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .animation(.easeInOut(duration: 0.3), value: overallStatus)
            .animation(.easeInOut(duration: 0.3), value: poseDetector.bodyRect)
    }

    /// Colors the outline to match the border glow — unified visual language.
    private var outlineColor: Color {
        switch overallStatus {
        case .good:
            return ProofTheme.borderReady
        case .fair:
            return ProofTheme.borderAlmost
        case .poor:
            return ProofTheme.borderNeutral
        }
    }

    private var outlineLineWidth: CGFloat {
        switch overallStatus {
        case .good:
            return 3
        case .fair:
            return 2.5
        case .poor:
            return 1.5
        }
    }

    @ViewBuilder
    private func feedbackPill(for rect: CGRect, in size: CGSize) -> some View {
        if poseDetector.bodyDetected, overallStatus != .good {
            let pillWidth = min(size.width - (ProofTheme.spacingMD * 2), 280)
            let x = min(max(rect.midX, pillWidth / 2 + ProofTheme.spacingMD), size.width - pillWidth / 2 - ProofTheme.spacingMD)
            let y = min(rect.maxY + 28, size.height - 28)

            Text(poseDetector.feedback)
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(ProofTheme.overlayText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, ProofTheme.spacingMD)
                .padding(.vertical, ProofTheme.spacingSM)
                .frame(width: pillWidth)
                .background(ProofTheme.overlayPill)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(feedbackTone.opacity(0.22), lineWidth: 1)
                )
                .position(x: x, y: y)
                .animation(.easeInOut(duration: 0.2), value: poseDetector.feedback)
                .animation(.easeInOut(duration: 0.3), value: poseDetector.bodyRect)
                .animation(.easeInOut(duration: 0.3), value: overallStatus)
        }
    }

    private var feedbackTone: Color {
        switch overallStatus {
        case .good:
            return ProofTheme.statusGood
        case .fair:
            return ProofTheme.statusFair
        case .poor:
            return ProofTheme.statusPoor
        }
    }

    // MARK: - Coordinate Conversion

    private func normalizedToView(_ normalized: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: normalized.origin.x * size.width,
            y: (1 - normalized.origin.y - normalized.height) * size.height,
            width: normalized.width * size.width,
            height: normalized.height * size.height
        )
    }
}

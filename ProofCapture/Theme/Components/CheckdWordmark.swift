import SwiftUI

// Brand wordmark. Splash frame 336:236 uses lowercase "checkd" at 50pt
// Medium. Optional eyebrow below (11pt tracking-3 uppercase).

struct CheckdWordmark: View {
    var text: String = "checkd"
    var size: CGFloat = 50
    var tracking: CGFloat = 1
    var color: Color = ProofTheme.paperHi
    var eyebrow: String? = nil

    var body: some View {
        VStack(spacing: ProofTheme.spacingMD) {
            Text(text)
                .font(.system(size: size, weight: .medium))
                .tracking(tracking)
                .foregroundStyle(color)
                .accessibilityAddTraits(.isHeader)

            if let eyebrow {
                Text(eyebrow)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(3)
                    .textCase(.uppercase)
                    .foregroundStyle(color.opacity(0.55))
            }
        }
    }
}

#Preview("On dark") {
    ZStack {
        Color.black.ignoresSafeArea()
        CheckdWordmark(eyebrow: "Guided check-ins")
    }
}

#Preview("On paper") {
    ZStack {
        ProofTheme.paperHi.ignoresSafeArea()
        CheckdWordmark(color: ProofTheme.inkPrimary)
    }
}

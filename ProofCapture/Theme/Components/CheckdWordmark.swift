import SwiftUI

struct CheckdWordmark: View {
    let text: String
    let size: CGFloat
    let tracking: CGFloat
    let onDark: Bool
    let subtitle: String?

    init(
        text: String = "checkd",
        size: CGFloat = 50,
        tracking: CGFloat = -1.5,
        onDark: Bool = true,
        subtitle: String? = nil
    ) {
        self.text = text
        self.size = size
        self.tracking = tracking
        self.onDark = onDark
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(text)
                .font(.system(size: size, weight: .medium))
                .tracking(tracking)
                .foregroundStyle(onDark ? ProofTheme.paperHi : ProofTheme.inkPrimary)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(3)
                    .textCase(.uppercase)
                    .foregroundStyle(onDark ? ProofTheme.paperHi.opacity(0.64) : ProofTheme.inkSoft)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

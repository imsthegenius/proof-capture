import SwiftUI

// The ONLY allowed use of SF Pro .bold in the codebase. 200pt numeral
// centered inside the CameraFrame during countdown. Matches frames
// 406:751 / 406:769 / 406:786. See .claude/rules/design-system-v12.md.

struct CountdownNumeral: View {
    let value: Int

    var body: some View {
        Text("\(value)")
            // swiftlint:disable:next no_bold_weight
            .font(.system(size: 200, weight: .bold))
            .tracking(2)
            .foregroundStyle(ProofTheme.paperHi)
            .id(value)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 1.2)),
                removal: .opacity.combined(with: .scale(scale: 0.6))
            ))
            .accessibilityLabel("\(value) seconds remaining")
    }
}

#Preview {
    ZStack {
        Color.gray.ignoresSafeArea()
        CountdownNumeral(value: 3)
    }
}

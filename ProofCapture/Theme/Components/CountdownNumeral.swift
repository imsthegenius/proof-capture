import SwiftUI

struct CountdownNumeral: View {
    let value: Int

    var body: some View {
        Text("\(value)")
            .font(.system(size: 200, weight: .bold))
            .tracking(2)
            .foregroundStyle(ProofTheme.paperHi)
            .id(value)
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
            .accessibilityLabel("\(value)")
    }
}

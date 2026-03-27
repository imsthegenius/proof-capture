import SwiftUI

struct WelcomeStep: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("PROOF")
                .font(.system(size: 48, weight: .thin))
                .tracking(8)
                .foregroundStyle(ProofTheme.textPrimary)

            Text("Consistent progress photos\nguided by your phone.")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(ProofTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, ProofTheme.spacingMD)
                .lineSpacing(4)

            Spacer()

            Text("Three poses. Timed capture.\nSame framing every session.")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(ProofTheme.textTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()

            Button(action: {
                ProofTheme.hapticLight()
                onNext()
            }) {
                Text("Get started")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(ProofTheme.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(ProofTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusSM))
            }
            .padding(.horizontal, ProofTheme.spacingXL)
            .padding(.bottom, ProofTheme.spacingXXL)
        }
    }
}

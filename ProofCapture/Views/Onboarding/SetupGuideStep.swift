import SwiftUI

struct SetupGuideStep: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: ProofTheme.spacingXXL * 2)

            Text("How it works")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(ProofTheme.textPrimary)

            Spacer()
                .frame(height: ProofTheme.spacingXXL)

            VStack(alignment: .leading, spacing: ProofTheme.spacingLG) {
                guideRow(
                    number: "1",
                    title: "Prop your phone up",
                    detail: "Lean it against a wall or shelf at waist height, 5\u{2013}6 feet away."
                )
                guideRow(
                    number: "2",
                    title: "Stand under overhead light",
                    detail: "A single light above you creates shadows that show definition."
                )
                guideRow(
                    number: "3",
                    title: "Follow the audio guide",
                    detail: "Front, side, back. The app talks you through each pose and captures automatically."
                )
            }
            .padding(.horizontal, ProofTheme.spacingXL)

            Spacer()

            Button(action: {
                ProofTheme.hapticLight()
                onNext()
            }) {
                Text("Continue")
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

    private func guideRow(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: ProofTheme.spacingMD) {
            Text(number)
                .font(.system(size: 28, weight: .thin))
                .foregroundStyle(ProofTheme.accent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: ProofTheme.spacingXS) {
                Text(title)
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(ProofTheme.textPrimary)

                Text(detail)
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(ProofTheme.textSecondary)
                    .lineSpacing(2)
            }
        }
    }
}

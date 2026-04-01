import SwiftUI

struct SetupGuideStep: View {
    let onNext: () -> Void

    @State private var visibleRows: Set<Int> = []

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: ProofTheme.spacingXXL * 2)

            Text("Setup")
                .proofFont(24, weight: .light, relativeTo: .title2)
                .foregroundStyle(ProofTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer()
                .frame(height: ProofTheme.spacingXXL)

            VStack(alignment: .leading, spacing: ProofTheme.spacingXL) {
                guideRow(
                    index: 0,
                    number: "1",
                    title: "Prop your phone up",
                    detail: "Lean it against a wall or shelf at waist height, 5\u{2013}6 feet away."
                )
                guideRow(
                    index: 1,
                    number: "2",
                    title: "Stand under overhead light",
                    detail: "A single light above you creates shadows that show definition."
                )
                guideRow(
                    index: 2,
                    number: "3",
                    title: "Follow the audio guide",
                    detail: "Front, side, back. The app talks you through each pose and captures automatically."
                )
            }
            .padding(.horizontal, ProofTheme.spacingXL)

            Text("Your photos stay completely private. Only you can see them.")
                .proofFont(13, weight: .light, relativeTo: .footnote)
                .foregroundStyle(ProofTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, ProofTheme.spacingXL)
                .padding(.top, ProofTheme.spacingLG)

            Spacer()

            Button(action: {
                ProofTheme.hapticLight()
                onNext()
            }) {
                Text("Continue")
            }
            .buttonStyle(ProofTheme.ProofButtonStyle())
            .padding(.horizontal, ProofTheme.spacingXL)
            .padding(.bottom, ProofTheme.spacingXXL)
            .accessibilityLabel("Continue to permissions")
        }
        .proofDynamicType()
        .onAppear {
            for i in 0..<3 {
                withAnimation(.easeOut(duration: 0.4).delay(Double(i) * 0.15)) {
                    visibleRows.insert(i)
                }
            }
        }
    }

    private func guideRow(index: Int, number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: ProofTheme.spacingMD) {
            Text(number)
                .proofFont(34, weight: .ultraLight, relativeTo: .largeTitle)
                .foregroundStyle(ProofTheme.accent)
                .frame(width: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: ProofTheme.spacingXS) {
                Text(title)
                    .proofFont(17, weight: .light, relativeTo: .body)
                    .foregroundStyle(ProofTheme.textPrimary)

                Text(detail)
                    .proofFont(13, weight: .light, relativeTo: .footnote)
                    .foregroundStyle(ProofTheme.textSecondary)
                    .lineSpacing(4)
            }
        }
        .opacity(visibleRows.contains(index) ? 1 : 0)
        .offset(y: visibleRows.contains(index) ? 0 : 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(title). \(detail)")
    }
}

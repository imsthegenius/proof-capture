import SwiftUI

struct SetupGuideStep: View {
    let onNext: () -> Void

    @State private var visibleRows: Set<Int> = []

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: ProofTheme.spacingXXL * 2)

            Text("How it works")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(ProofTheme.textPrimary)

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
        }
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
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundStyle(ProofTheme.accent)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: ProofTheme.spacingXS) {
                Text(title)
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(ProofTheme.textPrimary)

                Text(detail)
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(ProofTheme.textSecondary)
                    .lineSpacing(4)
            }
        }
        .opacity(visibleRows.contains(index) ? 1 : 0)
        .offset(y: visibleRows.contains(index) ? 0 : 12)
    }
}

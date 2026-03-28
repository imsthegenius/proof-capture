import SwiftUI

struct WelcomeStep: View {
    let onNext: () -> Void

    @State private var titleVisible = false
    @State private var subtitleVisible = false
    @State private var middleVisible = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("PROOF")
                .font(.system(size: 60, weight: .ultraLight))
                .tracking(12)
                .foregroundStyle(ProofTheme.textPrimary)
                .opacity(titleVisible ? 1 : 0)
                .offset(y: titleVisible ? 0 : 8)

            Text("Consistent progress photos\nguided by your phone.")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(ProofTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .padding(.top, ProofTheme.spacingMD)
                .opacity(subtitleVisible ? 1 : 0)
                .offset(y: subtitleVisible ? 0 : 8)

            Spacer()
                .frame(height: ProofTheme.spacingXXL)

            Text("Three poses. Timed capture.\nSame framing every session.")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(ProofTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(6)

            Spacer()

            Button(action: {
                ProofTheme.hapticLight()
                onNext()
            }) {
                Text("Get started")
            }
            .buttonStyle(ProofTheme.ProofButtonStyle())
            .padding(.horizontal, ProofTheme.spacingXL)
            .padding(.bottom, ProofTheme.spacingXXL)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                titleVisible = true
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
                subtitleVisible = true
            }
        }
    }
}

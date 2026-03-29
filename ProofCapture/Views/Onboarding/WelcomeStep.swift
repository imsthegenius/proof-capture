import SwiftUI

struct WelcomeStep: View {
    let onNext: () -> Void

    @State private var titleVisible = false
    @State private var iconVisible = false
    @State private var subtitleVisible = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("PROOF")
                .font(.system(size: 60, weight: .ultraLight))
                .tracking(12)
                .foregroundStyle(ProofTheme.textPrimary)
                .opacity(titleVisible ? 1 : 0)
                .offset(y: titleVisible ? 0 : 8)
                .accessibilityAddTraits(.isHeader)

            Image(systemName: "camera.viewfinder")
                .font(.system(size: 28, weight: .ultraLight))
                .foregroundStyle(ProofTheme.textTertiary)
                .padding(.top, ProofTheme.spacingLG)
                .opacity(iconVisible ? 1 : 0)
                .offset(y: iconVisible ? 0 : 6)
                .accessibilityHidden(true)

            Text("Your phone guides you through\nperfect progress photos.")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(ProofTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .padding(.top, ProofTheme.spacingMD)
                .opacity(subtitleVisible ? 1 : 0)
                .offset(y: subtitleVisible ? 0 : 8)

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
            .accessibilityLabel("Get started with onboarding")
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                titleVisible = true
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.15)) {
                iconVisible = true
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                subtitleVisible = true
            }
        }
    }
}

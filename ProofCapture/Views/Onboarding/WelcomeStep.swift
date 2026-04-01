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
                .proofFont(60, weight: .ultraLight, relativeTo: .largeTitle, maximumScaleFactor: 1.25)
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

            VStack(spacing: ProofTheme.spacingSM) {
                Text("Private. Guided. Consistent.")
                    .proofFont(13, weight: .light, relativeTo: .footnote)
                    .foregroundStyle(ProofTheme.textTertiary)

                Text("Your phone guides you through\nperfect progress photos.")
                    .proofFont(17, weight: .light, relativeTo: .body)
                    .foregroundStyle(ProofTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
            }
            .padding(.top, ProofTheme.spacingMD)
            .opacity(subtitleVisible ? 1 : 0)
            .offset(y: subtitleVisible ? 0 : 8)

            Spacer()

            Button(action: {
                ProofTheme.hapticLight()
                onNext()
            }) {
                Text("Begin setup")
            }
            .buttonStyle(ProofTheme.ProofButtonStyle())
            .padding(.horizontal, ProofTheme.spacingXL)
            .padding(.bottom, ProofTheme.spacingXXL)
            .accessibilityLabel("Get started with onboarding")
        }
        .proofDynamicType()
        .onAppear {
            withAnimation(.easeOut(duration: ProofTheme.animationEntrance)) {
                titleVisible = true
            }
            withAnimation(.easeOut(duration: ProofTheme.animationEntrance).delay(ProofTheme.staggerShort)) {
                iconVisible = true
            }
            withAnimation(.easeOut(duration: ProofTheme.animationEntrance).delay(ProofTheme.staggerDefault)) {
                subtitleVisible = true
            }
        }
    }
}

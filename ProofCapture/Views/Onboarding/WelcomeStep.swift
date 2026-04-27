import SwiftUI

struct WelcomeStep: View {
    let onNext: () -> Void

    @State private var titleVisible = false
    @State private var iconVisible = false
    @State private var subtitleVisible = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("checkd")
                .proofFont(58, weight: .medium, relativeTo: .largeTitle, maximumScaleFactor: 1.15)
                .tracking(-1.5)
                .foregroundStyle(ProofTheme.inkPrimary)
                .opacity(titleVisible ? 1 : 0)
                .offset(y: titleVisible ? 0 : 8)
                .accessibilityAddTraits(.isHeader)

            Image(systemName: "camera.viewfinder")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(ProofTheme.inkSoft)
                .padding(.top, ProofTheme.spacingLG)
                .opacity(iconVisible ? 1 : 0)
                .offset(y: iconVisible ? 0 : 6)
                .accessibilityHidden(true)

            VStack(spacing: ProofTheme.spacingSM) {
                Text("Private. Guided. Consistent.")
                    .proofFont(13, weight: .medium, relativeTo: .footnote)
                    .foregroundStyle(ProofTheme.inkSoft)

                Text("Your phone guides you through\nperfect progress photos.")
                    .proofFont(17, weight: .regular, relativeTo: .body)
                    .foregroundStyle(ProofTheme.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
            }
            .padding(.top, ProofTheme.spacingMD)
            .opacity(subtitleVisible ? 1 : 0)
            .offset(y: subtitleVisible ? 0 : 8)

            Spacer()

            LiquidGlassButton(variant: .paperLight, action: {
                ProofTheme.hapticLight()
                onNext()
            }) {
                Text("Begin setup")
            }
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

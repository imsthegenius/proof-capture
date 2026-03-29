import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentStep = 0

    var body: some View {
        ZStack {
            ProofTheme.background.ignoresSafeArea()

            TabView(selection: $currentStep) {
                WelcomeStep(onNext: { currentStep = 1 })
                    .tag(0)

                SetupGuideStep(onNext: { currentStep = 2 })
                    .tag(1)

                PermissionStep(onComplete: { hasCompletedOnboarding = true })
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentStep)

            VStack {
                Spacer()
                HStack(spacing: ProofTheme.spacingSM) {
                    ForEach(0..<3, id: \.self) { step in
                        Circle()
                            .fill(step == currentStep ? ProofTheme.textPrimary : ProofTheme.textTertiary)
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.bottom, ProofTheme.spacingLG)
            }
        }
    }
}

import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentStep = 0

    var body: some View {
        ZStack {
            ProofTheme.paperHi.ignoresSafeArea()

            Group {
                switch currentStep {
                case 1:
                    SetupGuideStep(onNext: { currentStep = 2 })
                case 2:
                    PermissionStep(onComplete: { hasCompletedOnboarding = true })
                default:
                    WelcomeStep(onNext: { currentStep = 1 })
                }
            }
            .id(currentStep)
            .transition(.push(from: .trailing))

            VStack {
                Spacer()
                HStack(spacing: ProofTheme.spacingSM) {
                    ForEach(0..<3, id: \.self) { step in
                        Circle()
                            .fill(step == currentStep ? ProofTheme.inkPrimary : ProofTheme.inkSoft.opacity(0.35))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.bottom, ProofTheme.spacingLG)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentStep)
    }
}

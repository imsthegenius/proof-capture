import SwiftUI

/// Onboarding step 1 — dark world. Hero Checkd wordmark, brief value prop, primary CTA.
/// Mirrors the AuthView entry treatment but with a single forward action.
struct WelcomeStep: View {
    let onNext: () -> Void

    @State private var visible = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: ProofTheme.spacingMD) {
                Text("checkd")
                    .font(.system(size: 58, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(ProofTheme.paperHi)
                    .accessibilityAddTraits(.isHeader)

                Text("CONSISTENT · PRIVATE · GUIDED")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(3)
                    .foregroundStyle(ProofTheme.textTertiary)
            }
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 12)

            Spacer()

            Text("A simple way to see\nhow you’re changing")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(ProofTheme.paperHi.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .padding(.horizontal, ProofTheme.spacingLG)
                .opacity(visible ? 1 : 0)
                .offset(y: visible ? 0 : 16)

            Spacer()

            Button {
                ProofTheme.hapticLight()
                onNext()
            } label: {
                Text("Get started")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ProofTheme.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .modifier(ProofTheme.PrimaryButtonBackground())
            }
            .padding(.horizontal, ProofTheme.spacingLG)
            .padding(.bottom, ProofTheme.spacingXXL)
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 16)
            .accessibilityLabel("Get started")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ProofTheme.background)
        .proofDynamicType()
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) {
                visible = true
            }
        }
    }
}

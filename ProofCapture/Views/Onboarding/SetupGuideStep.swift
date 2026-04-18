import SwiftUI

/// Onboarding step 2 — dark world. Three numbered setup cards in glass capsules.
/// Numbers are large display medium type (mirroring the camera-flow hero typography).
struct SetupGuideStep: View {
    let onNext: () -> Void

    @State private var visibleSteps: Set<Int> = []

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: ProofTheme.spacingXXL * 2)

            VStack(spacing: ProofTheme.spacingSM) {
                Text("SETUP")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(3)
                    .foregroundStyle(ProofTheme.textTertiary)

                Text("Three things")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(ProofTheme.paperHi)
                    .accessibilityAddTraits(.isHeader)
            }

            Spacer()
                .frame(height: ProofTheme.spacingXL)

            VStack(spacing: 12) {
                guideCard(index: 0, number: "1", title: "Place your phone down", detail: "Lean it against a wall or shelf, around waist height.")
                guideCard(index: 1, number: "2", title: "Step two metres back", detail: "Stand far enough away that your full body fits in the frame.")
                guideCard(index: 2, number: "3", title: "Try to be under a light", detail: "A single overhead light helps show shape and definition.")
            }
            .padding(.horizontal, ProofTheme.spacingLG)

            Spacer()

            Button {
                ProofTheme.hapticLight()
                onNext()
            } label: {
                Text("How it works")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ProofTheme.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .modifier(ProofTheme.PrimaryButtonBackground())
            }
            .padding(.horizontal, ProofTheme.spacingLG)
            .padding(.bottom, ProofTheme.spacingXXL)
            .accessibilityLabel("Continue to permissions")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ProofTheme.background)
        .proofDynamicType()
        .onAppear {
            for i in 0..<3 {
                withAnimation(.easeOut(duration: 0.45).delay(Double(i) * 0.12)) {
                    _ = visibleSteps.insert(i)
                }
            }
        }
    }

    private func guideCard(index: Int, number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Text(number)
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(ProofTheme.paperHi)
                .frame(width: 40)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ProofTheme.paperHi)

                Text(detail)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(ProofTheme.textSecondary)
                    .lineSpacing(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(cardBackground)
        .opacity(visibleSteps.contains(index) ? 1 : 0)
        .offset(y: visibleSteps.contains(index) ? 0 : 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(title). \(detail)")
    }

    @ViewBuilder
    private var cardBackground: some View {
        if #available(iOS 26, *) {
            RoundedRectangle(cornerRadius: ProofTheme.radiusLG)
                .fill(.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: ProofTheme.radiusLG))
        } else {
            RoundedRectangle(cornerRadius: ProofTheme.radiusLG)
                .fill(ProofTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: ProofTheme.radiusLG)
                        .stroke(ProofTheme.paperHi.opacity(0.08), lineWidth: 1)
                )
        }
    }
}

import SwiftUI

struct PreCaptureInstructionView: View {
    let progress: Double
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.96), Color.black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(ProofTheme.paperHi.opacity(0.72))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("End session")
                    Spacer()
                }
                .padding(.horizontal, ProofTheme.spacingMD)
                .padding(.top, ProofTheme.spacingSM)

                Spacer()

                InstructionHero(lines: [
                    "PLACE YOUR PHONE DOWN",
                    "STAND 2M BACK",
                    "TRY AND BE UNDER A LIGHT"
                ])

                Spacer()

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(ProofTheme.paperHi)
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                }
                .liquidGlassCapsule(.paperDark)
                .padding(.horizontal, ProofTheme.spacingMD)
                .padding(.bottom, ProofTheme.spacingMD)

                ProofProgressBar(progress: progress)
                    .padding(.bottom, 32)
            }
        }
        .accessibilityAction(named: "Continue") { onContinue() }
    }
}

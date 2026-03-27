import SwiftUI

struct GenderStep: View {
    @AppStorage("userGender") private var genderRaw = 0
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: ProofTheme.spacingXXL * 2)

            Text("Choose your guide voice")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(ProofTheme.textPrimary)

            Text("Audio prompts will talk you through each pose.")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(ProofTheme.textSecondary)
                .padding(.top, ProofTheme.spacingSM)

            Spacer()

            HStack(spacing: ProofTheme.spacingMD) {
                genderButton(label: "Male", value: 0)
                genderButton(label: "Female", value: 1)
            }
            .padding(.horizontal, ProofTheme.spacingXL)

            Spacer()

            Button(action: {
                ProofTheme.hapticLight()
                onNext()
            }) {
                Text("Continue")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(ProofTheme.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(ProofTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusSM))
            }
            .padding(.horizontal, ProofTheme.spacingXL)
            .padding(.bottom, ProofTheme.spacingXXL)
        }
    }

    private func genderButton(label: String, value: Int) -> some View {
        Button {
            ProofTheme.hapticLight()
            genderRaw = value
        } label: {
            Text(label)
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(genderRaw == value ? ProofTheme.background : ProofTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(genderRaw == value ? ProofTheme.accent : ProofTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusSM))
        }
    }
}

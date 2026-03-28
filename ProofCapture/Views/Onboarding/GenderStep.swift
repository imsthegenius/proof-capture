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
                    .clipShape(.capsule)
            }
            .padding(.horizontal, ProofTheme.spacingXL)
            .padding(.bottom, ProofTheme.spacingXXL)
        }
    }

    private func genderButton(label: String, value: Int) -> some View {
        let isSelected = genderRaw == value
        return Button {
            ProofTheme.hapticLight()
            withAnimation(.easeInOut(duration: 0.2)) {
                genderRaw = value
            }
        } label: {
            HStack(spacing: ProofTheme.spacingSM) {
                Text(label)
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(isSelected ? ProofTheme.background : ProofTheme.textPrimary)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(ProofTheme.background)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(isSelected ? ProofTheme.accent : ProofTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: ProofTheme.radiusMD)
                    .strokeBorder(isSelected ? Color.clear : ProofTheme.separator, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusMD))
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
    }
}

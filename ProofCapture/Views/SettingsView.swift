import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    @AppStorage("userGender") private var genderRaw = 0
    @AppStorage("guidanceMode") private var guidanceMode = 0
    @AppStorage("countdownSeconds") private var countdownSeconds = 5

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        List {
            // Capture settings
            Section {
                // Guide voice
                VStack(alignment: .leading, spacing: ProofTheme.spacingSM) {
                    Text("Guide voice")
                        .proofFont(13, weight: .medium, relativeTo: .footnote)
                        .foregroundStyle(ProofTheme.inkSoft)

                    HStack(spacing: ProofTheme.spacingSM) {
                        settingOption(label: "Male", isSelected: genderRaw == 0) { genderRaw = 0 }
                        settingOption(label: "Female", isSelected: genderRaw == 1) { genderRaw = 1 }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Voice guide gender")
                .padding(.vertical, ProofTheme.spacingXS)

                // Guidance mode
                VStack(alignment: .leading, spacing: ProofTheme.spacingSM) {
                    Text("Guidance mode")
                        .proofFont(13, weight: .medium, relativeTo: .footnote)
                        .foregroundStyle(ProofTheme.inkSoft)

                    HStack(spacing: ProofTheme.spacingSM) {
                        settingOption(label: "Voice", isSelected: guidanceMode == 0) { guidanceMode = 0 }
                        settingOption(label: "Text only", isSelected: guidanceMode == 1) { guidanceMode = 1 }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Guidance mode selection")
                .padding(.vertical, ProofTheme.spacingXS)

                // Countdown
                VStack(alignment: .leading, spacing: ProofTheme.spacingSM) {
                    Text("Countdown")
                        .proofFont(13, weight: .medium, relativeTo: .footnote)
                        .foregroundStyle(ProofTheme.inkSoft)

                    HStack(spacing: ProofTheme.spacingSM) {
                        settingOption(label: "3s", isSelected: countdownSeconds == 3) { countdownSeconds = 3 }
                        settingOption(label: "5s", isSelected: countdownSeconds == 5) { countdownSeconds = 5 }
                        settingOption(label: "10s", isSelected: countdownSeconds == 10) { countdownSeconds = 10 }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Countdown timer duration")
                .padding(.vertical, ProofTheme.spacingXS)
            } header: {
                Text("CAPTURE")
                    .proofFont(12, weight: .medium, relativeTo: .caption1)
                    .foregroundStyle(ProofTheme.inkSoft)
            }
            .listRowBackground(ProofTheme.paperLo.opacity(0.72))

            // Privacy reassurance
            Section {
                privacyRow(text: "Photos stored on-device only")
                privacyRow(text: "Cloud backup encrypted to your Apple ID")
                privacyRow(text: "No sharing, no analytics on photo content")
            } header: {
                Text("PRIVACY")
                    .proofFont(12, weight: .medium, relativeTo: .caption1)
                    .foregroundStyle(ProofTheme.inkSoft)
            }
            .listRowBackground(ProofTheme.paperLo.opacity(0.72))

            // Sign out
            Section {
                Button("Sign out") {
                    Task {
                        await authManager.signOut()
                        dismiss()
                    }
                }
                .foregroundStyle(ProofTheme.statusPoor)
                .accessibilityLabel("Sign out of your account")
            }
            .listRowBackground(ProofTheme.paperLo.opacity(0.72))

            // About
            Section {
                VStack(spacing: ProofTheme.spacingSM) {
                    Text("Proof Capture")
                        .proofFont(15, weight: .medium, relativeTo: .body)
                        .foregroundStyle(ProofTheme.inkSoft)

                    Text("v\(appVersion)")
                        .proofFont(13, weight: .regular, relativeTo: .footnote)
                        .foregroundStyle(ProofTheme.inkSoft)

                    Text("Made for fitness coaches and their clients")
                        .proofFont(13, weight: .regular, relativeTo: .footnote)
                        .foregroundStyle(ProofTheme.inkSoft)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, ProofTheme.spacingSM)
                .listRowBackground(Color.clear)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Proof Capture version \(appVersion). Made for fitness coaches and their clients.")
            }
        }
        .scrollContentBackground(.hidden)
        .proofDynamicType()
        .background(ProofTheme.paperHi)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func settingOption(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            ProofTheme.hapticLight()
            withAnimation(.easeInOut(duration: 0.2)) {
                action()
            }
        } label: {
            HStack(spacing: ProofTheme.spacingSM) {
                Text(label)
                    .proofFont(15, weight: .medium, relativeTo: .body)
                    .foregroundStyle(isSelected ? ProofTheme.paperHi : ProofTheme.inkPrimary)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ProofTheme.paperHi)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .background(isSelected ? ProofTheme.inkPrimary : ProofTheme.paperLo)
            .overlay(
                RoundedRectangle(cornerRadius: ProofTheme.radiusSM)
                    .strokeBorder(isSelected ? Color.clear : ProofTheme.inkSoft.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: ProofTheme.radiusSM))
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func privacyRow(text: String) -> some View {
        Label {
            Text(text)
                .proofFont(15, weight: .regular, relativeTo: .body)
                .foregroundStyle(ProofTheme.inkPrimary)
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(ProofTheme.statusGood)
        }
        .padding(.vertical, ProofTheme.spacingXS)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

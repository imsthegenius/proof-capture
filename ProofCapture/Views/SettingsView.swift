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
                Picker("Guide voice", selection: $genderRaw) {
                    Text("Male").tag(0)
                    Text("Female").tag(1)
                }
                .accessibilityLabel("Voice guide gender")

                Picker("Guidance mode", selection: $guidanceMode) {
                    Text("Voice").tag(0)
                    Text("Text only").tag(1)
                }
                .accessibilityLabel("Guidance mode selection")

                Picker("Countdown", selection: $countdownSeconds) {
                    Text("3 seconds").tag(3)
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                }
                .accessibilityLabel("Countdown timer duration")
            } header: {
                Text("CAPTURE")
                    .proofFont(12, weight: .light, relativeTo: .caption1)
                    .foregroundStyle(ProofTheme.textTertiary)
            }
            .listRowBackground(ProofTheme.surface)

            // Privacy reassurance
            Section {
                privacyRow(text: "Photos stored on-device only")
                privacyRow(text: "Cloud backup encrypted to your Apple ID")
                privacyRow(text: "No sharing, no analytics on photo content")
            } header: {
                Text("PRIVACY")
                    .proofFont(12, weight: .light, relativeTo: .caption1)
                    .foregroundStyle(ProofTheme.textTertiary)
            }
            .listRowBackground(ProofTheme.surface)

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
            .listRowBackground(ProofTheme.surface)

            // About
            Section {
                VStack(spacing: ProofTheme.spacingSM) {
                    Text("Proof Capture")
                        .proofFont(15, weight: .light, relativeTo: .body)
                        .foregroundStyle(ProofTheme.textTertiary)

                    Text("v\(appVersion)")
                        .proofFont(13, weight: .ultraLight, relativeTo: .footnote)
                        .foregroundStyle(ProofTheme.textTertiary)

                    Text("Made for fitness coaches and their clients")
                        .proofFont(13, weight: .light, relativeTo: .footnote)
                        .foregroundStyle(ProofTheme.textTertiary)
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
        .background(ProofTheme.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func privacyRow(text: String) -> some View {
        Label {
            Text(text)
                .proofFont(15, weight: .light, relativeTo: .body)
                .foregroundStyle(ProofTheme.textSecondary)
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

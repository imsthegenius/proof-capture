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
                    .font(.system(size: 12, weight: .light))
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
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(ProofTheme.textTertiary)

                    Text("v\(appVersion)")
                        .font(.system(size: 13, weight: .ultraLight))
                        .foregroundStyle(ProofTheme.textTertiary)

                    Text("Made for fitness coaches and their clients")
                        .font(.system(size: 13, weight: .light))
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
        .background(ProofTheme.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

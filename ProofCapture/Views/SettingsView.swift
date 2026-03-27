import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    @AppStorage("userGender") private var genderRaw = 0
    @AppStorage("guidanceMode") private var guidanceMode = 0
    @AppStorage("countdownSeconds") private var countdownSeconds = 5

    var body: some View {
        List {
            Section {
                Picker("Guide voice", selection: $genderRaw) {
                    Text("Male").tag(0)
                    Text("Female").tag(1)
                }

                Picker("Guidance mode", selection: $guidanceMode) {
                    Text("Voice").tag(0)
                    Text("Text only").tag(1)
                }

                Picker("Countdown", selection: $countdownSeconds) {
                    Text("3 seconds").tag(3)
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                }
            } header: {
                Text("CAPTURE")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(ProofTheme.textTertiary)
            }
            .listRowBackground(ProofTheme.surface)

            Section {
                Button("Sign out") {
                    Task {
                        await authManager.signOut()
                        dismiss()
                    }
                }
                .foregroundStyle(ProofTheme.statusPoor)
            }
            .listRowBackground(ProofTheme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(ProofTheme.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

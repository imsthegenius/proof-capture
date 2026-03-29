import AuthenticationServices
import SwiftUI

struct AuthView: View {
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: ProofTheme.spacingXXL * 2)

            Text("PROOF")
                .font(.system(size: 60, weight: .ultraLight))
                .tracking(12)
                .foregroundStyle(ProofTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Text("Guided progress photos")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(ProofTheme.textSecondary)
                .padding(.top, ProofTheme.spacingSM)

            Spacer()
                .frame(height: ProofTheme.spacingXXL)

            VStack(spacing: ProofTheme.spacingXL) {
                featureRow(icon: "camera.viewfinder", text: "Guided front, side, back poses")
                featureRow(icon: "waveform", text: "Voice coaching \u{2014} hands-free capture")
                featureRow(icon: "icloud.and.arrow.up", text: "Private cloud backup")
            }
            .padding(.horizontal, ProofTheme.spacingXL)

            Spacer()

            SignInWithAppleButton(.signIn) { request in
                authManager.prepareRequest(request)
            } onCompletion: { result in
                Task { await authManager.handleAppleSignIn(result: result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 48)
            .clipShape(.capsule)
            .padding(.horizontal, ProofTheme.spacingXL)
            .accessibilityLabel("Sign in with Apple")

            Text("Sign in to back up your progress photos")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(ProofTheme.textSecondary)
                .padding(.top, ProofTheme.spacingMD)

            Spacer()
                .frame(height: ProofTheme.spacingXXL * 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ProofTheme.background)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: ProofTheme.spacingMD) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(ProofTheme.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(ProofTheme.textSecondary)
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

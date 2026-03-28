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

            Text("Progress photos, done right.")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(ProofTheme.textSecondary)
                .padding(.top, ProofTheme.spacingSM)

            Spacer()

            VStack(spacing: ProofTheme.spacingXL) {
                featureRow(icon: "camera.viewfinder", text: "Guided front, side, back poses")
                featureRow(icon: "waveform", text: "Voice coaching — hands-free capture")
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
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(ProofTheme.accent)
                .frame(width: 28)
            Text(text)
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(ProofTheme.textSecondary)
            Spacer()
        }
    }
}

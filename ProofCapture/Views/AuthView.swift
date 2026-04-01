import AuthenticationServices
import SwiftUI

struct AuthView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var titleVisible = false
    @State private var featuresVisible = false
    @State private var buttonVisible = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: ProofTheme.spacingXXL * 2)

            VStack(spacing: ProofTheme.spacingSM) {
                Text("PROOF")
                    .proofFont(60, weight: .ultraLight, relativeTo: .largeTitle, maximumScaleFactor: 1.25)
                    .tracking(12)
                    .foregroundStyle(ProofTheme.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text("Guided progress photos")
                    .proofFont(15, weight: .light, relativeTo: .body)
                    .foregroundStyle(ProofTheme.textSecondary)
            }
            .opacity(titleVisible ? 1 : 0)
            .offset(y: titleVisible ? 0 : 8)

            Spacer()
                .frame(height: ProofTheme.spacingXXL)

            VStack(spacing: ProofTheme.spacingXL) {
                featureRow(icon: "camera.viewfinder", text: "Guided front, side, back poses")
                featureRow(icon: "waveform", text: "Voice coaching \u{2014} hands-free capture")
                featureRow(icon: "icloud.and.arrow.up", text: "Private cloud backup")
            }
            .padding(.horizontal, ProofTheme.spacingXL)
            .opacity(featuresVisible ? 1 : 0)
            .offset(y: featuresVisible ? 0 : 12)

            Spacer()

            VStack(spacing: ProofTheme.spacingMD) {
                SignInWithAppleButton(.signIn) { request in
                    authManager.prepareRequest(request)
                } onCompletion: { result in
                    Task { await authManager.handleAppleSignIn(result: result) }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 48)
                .clipShape(.capsule)
                .accessibilityLabel("Sign in with Apple")

                Text("Your photos stay private and backed up")
                    .proofFont(13, weight: .light, relativeTo: .footnote)
                    .foregroundStyle(ProofTheme.textSecondary)
            }
            .padding(.horizontal, ProofTheme.spacingXL)
            .opacity(buttonVisible ? 1 : 0)
            .offset(y: buttonVisible ? 0 : 12)

            Spacer()
                .frame(height: ProofTheme.spacingXXL * 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .proofDynamicType()
        .background(ProofTheme.background)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                titleVisible = true
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
                featuresVisible = true
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.4)) {
                buttonVisible = true
            }
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: ProofTheme.spacingMD) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(ProofTheme.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(text)
                .proofFont(15, weight: .light, relativeTo: .body)
                .foregroundStyle(ProofTheme.textSecondary)
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

import AuthenticationServices
import SwiftUI

struct AuthView: View {
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        ZStack {
            AuthBackdrop()

            VStack {
                Spacer()
                    .frame(height: 124)

                VStack(spacing: 10) {
                    CheckdMark()
                        .frame(width: 100, height: 100)
                        .foregroundStyle(ProofTheme.paperHi)
                        .accessibilityHidden(true)

                    CheckdWordmark(text: "checkd", size: 50, tracking: -1.5, onDark: true)
                }

                Spacer()

                appleSignInButton
                    .padding(.horizontal, 13)

                Spacer()
                    .frame(height: 48)
            }
        }
        .proofDynamicType()
        .alert(
            "Sign In Failed",
            isPresented: Binding(
                get: { authManager.authError != nil },
                set: { if !$0 { authManager.authError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(authManager.authError ?? "")
        }
    }

    private var appleSignInButton: some View {
        ZStack {
            HStack(spacing: ProofTheme.spacingSM) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 19, weight: .medium))
                Text(authManager.isAuthenticating ? "Signing In" : "Sign In With Apple")
                    .font(.system(size: 17, weight: .medium))
            }
            .foregroundStyle(ProofTheme.paperHi)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .liquidGlassCapsule(.paperDark)

            SignInWithAppleButton(.signIn) { request in
                authManager.prepareRequest(request)
            } onCompletion: { result in
                Task { await authManager.handleAppleSignIn(result: result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 64)
            .clipShape(.capsule)
            .opacity(0.02)
            .disabled(authManager.isAuthenticating)

            if authManager.isAuthenticating {
                ProgressView()
                    .tint(ProofTheme.paperHi)
                    .offset(x: -82)
            }
        }
        .accessibilityLabel("Sign in with Apple")
    }
}

private struct AuthBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.045, blue: 0.04),
                    Color(red: 0.16, green: 0.13, blue: 0.10),
                    Color(red: 0.03, green: 0.028, blue: 0.024)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 0) {
                Rectangle()
                    .fill(ProofTheme.paperHi.opacity(0.10))
                    .frame(height: 220)
                    .rotationEffect(.degrees(-16))
                    .offset(x: -90, y: 40)
                Spacer()
            }
            .blur(radius: 36)

            LinearGradient(
                colors: [Color.black.opacity(0.16), Color.black.opacity(0.70)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

private struct CheckdMark: View {
    var body: some View {
        ZStack {
            Circle()
                .frame(width: 42, height: 42)
                .offset(x: -20, y: -20)
            Circle()
                .frame(width: 42, height: 42)
                .offset(x: 20, y: -20)
            Circle()
                .frame(width: 42, height: 42)
                .offset(x: -20, y: 20)
            Circle()
                .frame(width: 42, height: 42)
                .offset(x: 20, y: 20)
        }
    }
}

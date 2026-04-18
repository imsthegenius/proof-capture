import AuthenticationServices
import SwiftUI

/// Entry screen — dark world. Hero "checkd" wordmark in semibold (matching the
/// Figma camera-flow display typography), three feature pills in glass capsules
/// (matching the tab bar pattern), Sign in with Apple at the bottom.
struct AuthView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var visible = false

    var body: some View {
        ZStack {
            ProofTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: ProofTheme.spacingMD) {
                    Text("checkd")
                        .font(.system(size: 58, weight: .medium))
                        .tracking(1)
                        .foregroundStyle(ProofTheme.paperHi)
                        .accessibilityAddTraits(.isHeader)

                    Text("GUIDED CHECK-INS")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(3)
                        .foregroundStyle(ProofTheme.textTertiary)
                }
                .opacity(visible ? 1 : 0)
                .offset(y: visible ? 0 : 12)

                Spacer()

                VStack(spacing: 12) {
                    featurePill(icon: "camera.viewfinder", text: "Front, side, back")
                    featurePill(icon: "waveform", text: "Step back. The voice guides you.")
                    featurePill(icon: "sparkles", text: "Consistent photos you can compare.")
                }
                .padding(.horizontal, ProofTheme.spacingLG)
                .opacity(visible ? 1 : 0)
                .offset(y: visible ? 0 : 16)

                Spacer()

                VStack(spacing: ProofTheme.spacingMD) {
                    ZStack {
                        SignInWithAppleButton(.signIn) { request in
                            authManager.prepareRequest(request)
                        } onCompletion: { result in
                            Task { await authManager.handleAppleSignIn(result: result) }
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 56)
                        .clipShape(.capsule)
                        .accessibilityLabel("Sign in with Apple")
                        .disabled(authManager.isAuthenticating)
                        .opacity(authManager.isAuthenticating ? 0.4 : 1)

                        if authManager.isAuthenticating {
                            ProgressView().tint(ProofTheme.paperHi)
                        }
                    }

                    Text("Photos stay private to you")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(ProofTheme.textTertiary)
                }
                .padding(.horizontal, ProofTheme.spacingLG)
                .padding(.bottom, ProofTheme.spacingXXL)
                .opacity(visible ? 1 : 0)
                .offset(y: visible ? 0 : 16)
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
            Button("OK", role: .cancel) {}
        } message: {
            Text(authManager.authError ?? "")
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) {
                visible = true
            }
        }
    }

    private func featurePill(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ProofTheme.paperHi)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ProofTheme.paperHi.opacity(0.9))

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(featurePillBackground)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var featurePillBackground: some View {
        if #available(iOS 26, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular, in: .capsule)
        } else {
            Capsule()
                .fill(ProofTheme.surface)
                .overlay(
                    Capsule().stroke(ProofTheme.paperHi.opacity(0.08), lineWidth: 1)
                )
        }
    }
}

import AuthenticationServices
import CryptoKit
import Supabase
import SwiftUI

@Observable
final class AuthManager {
    var isAuthenticated = false
    var userId: String?

    private var currentNonce: String?

    init() {
        Task { await restoreSession() }
    }

    private func restoreSession() async {
        do {
            let session = try await AppSupabase.client.auth.session
            userId = session.user.id.uuidString
            isAuthenticated = true
        } catch {
            isAuthenticated = false
        }
    }

    func handleAppleSignIn(result: Result<ASAuthorization, any Error>) async {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityToken = credential.identityToken,
                  let idTokenString = String(data: identityToken, encoding: .utf8),
                  let nonce = currentNonce else { return }

            do {
                let session = try await AppSupabase.client.auth.signInWithIdToken(
                    credentials: OpenIDConnectCredentials(
                        provider: .apple,
                        idToken: idTokenString,
                        nonce: nonce
                    )
                )
                userId = session.user.id.uuidString
                isAuthenticated = true
            } catch {
                print("Supabase auth failed: \(error)")
            }

        case .failure(let error):
            print("Apple sign in failed: \(error)")
        }
    }

    func prepareRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.email]
        request.nonce = sha256(nonce)
    }

    func signOut() async {
        try? await AppSupabase.client.auth.signOut()
        isAuthenticated = false
        userId = nil
    }

    // MARK: - Nonce helpers

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

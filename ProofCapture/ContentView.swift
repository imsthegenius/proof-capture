import SwiftUI

struct ContentView: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    #if DEBUG
    @State private var skipAuth = false
    #endif

    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingView()
            } else {
                #if DEBUG
                if authManager.isAuthenticated || skipAuth {
                    NavigationStack { HomeView() }
                } else {
                    AuthView()
                        .onTapGesture(count: 3) { skipAuth = true }
                }
                #else
                if authManager.isAuthenticated {
                    NavigationStack { HomeView() }
                } else {
                    AuthView()
                }
                #endif
            }
        }
        .animation(.easeInOut(duration: 0.3), value: hasCompletedOnboarding)
        .animation(.easeInOut(duration: 0.3), value: authManager.isAuthenticated)
    }
}

import SwiftUI

struct ContentView: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var tabSelection: LiquidGlassTab = .album
    @State private var showCamera = false

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
                    authenticatedRoot
                } else {
                    AuthView()
                        .onTapGesture(count: 3) { skipAuth = true }
                }
                #else
                if authManager.isAuthenticated {
                    authenticatedRoot
                } else {
                    AuthView()
                }
                #endif
            }
        }
        .animation(.easeInOut(duration: 0.3), value: hasCompletedOnboarding)
        .animation(.easeInOut(duration: 0.3), value: authManager.isAuthenticated)
    }

    private var authenticatedRoot: some View {
        NavigationStack {
            AlbumsView(tabSelection: $tabSelection)
        }
        .onChange(of: tabSelection) { _, newValue in
            if newValue == .camera {
                showCamera = true
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            NavigationStack {
                SessionView()
            }
            .onDisappear {
                tabSelection = .album
            }
        }
    }
}

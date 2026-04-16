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
                    RootTabView()
                } else {
                    AuthView()
                        .onTapGesture(count: 3) { skipAuth = true }
                }
                #else
                if authManager.isAuthenticated {
                    RootTabView()
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

// MARK: - Root Tab Shell

enum RootTab: Hashable {
    case camera
    case album
}

struct RootTabView: View {
    @State private var selectedTab: RootTab = .camera

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .camera:
                    NavigationStack { HomeView() }
                case .album:
                    NavigationStack { AlbumsView() }
                }
            }

            ProofTabBar(selectedTab: $selectedTab)
                .padding(.bottom, ProofTheme.spacingSM)
        }
        .ignoresSafeArea(.keyboard)
    }
}

struct ProofTabBar: View {
    @Binding var selectedTab: RootTab

    var body: some View {
        HStack(spacing: 0) {
            tabButton(tab: .camera, systemImage: "circle.inset.filled", label: "Camera")
            tabButton(tab: .album, systemImage: "square.grid.3x3.fill", label: "Album")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(tabBarBackground)
    }

    @ViewBuilder
    private var tabBarBackground: some View {
        if #available(iOS 26, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular, in: .capsule)
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(ProofTheme.textPrimary.opacity(0.08), lineWidth: 1)
                )
        }
    }

    private func tabButton(tab: RootTab, systemImage: String, label: String) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            ProofTheme.hapticLight()
            selectedTab = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))

                Text(label)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(isSelected ? ProofTheme.paperHi : ProofTheme.inkSoft)
            .frame(width: 102, height: 52)
            .background(selectionBackground(isSelected: isSelected))
            .animation(.easeInOut(duration: ProofTheme.animationFast), value: isSelected)
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func selectionBackground(isSelected: Bool) -> some View {
        if isSelected {
            Capsule().fill(ProofTheme.inkPrimary)
        } else {
            Capsule().fill(.clear)
        }
    }
}

import OSLog
import SwiftUI
import SwiftData

@main
struct ProofCaptureApp: App {
    @State private var authManager = AuthManager()
    @State private var syncManager = SyncManager()
    @State private var containerResult: Result<ModelContainer, Error> = Self.createContainer()

    private static let logger = Logger(subsystem: "com.proof.capture", category: "App")

    private static func createContainer() -> Result<ModelContainer, Error> {
        do {
            return .success(try ModelContainer(for: PhotoSession.self))
        } catch {
            return .failure(error)
        }
    }

    var body: some Scene {
        WindowGroup {
            switch containerResult {
            case .success(let container):
                SyncBootstrapView(syncManager: syncManager, authManager: authManager)
                    .preferredColorScheme(.dark)
                    .environment(\.legibilityWeight, .regular)
                    .environment(authManager)
                    .environment(syncManager)
                    .modelContainer(container)
            case .failure(let error):
                DataErrorView(error: error) {
                    containerResult = Self.createContainer()
                }
                .preferredColorScheme(.dark)
            }
        }
    }
}

/// Injects the SwiftUI-provided ModelContext into SyncManager once the environment is ready.
/// This avoids creating a second ModelContainer — one source of truth for SwiftData.
private struct SyncBootstrapView: View {
    let syncManager: SyncManager
    let authManager: AuthManager
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ContentView()
            .onAppear {
                syncManager.configure(modelContext: modelContext)
            }
            .onChange(of: authManager.isAuthenticated) { _, isAuth in
                if isAuth {
                    Task {
                        if let userId = authManager.userId {
                            await syncManager.restoreFromCloud(userId: userId)
                        }
                        await syncManager.syncPendingSessions()
                    }
                }
            }
    }
}

/// Full-screen error view shown when SwiftData ModelContainer fails to initialize.
private struct DataErrorView: View {
    let error: Error
    let retryAction: () -> Void
    private static let logger = Logger(subsystem: "com.proof.capture", category: "App")

    var body: some View {
        VStack(spacing: 24) {
            Text("Data Error")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(ProofTheme.textPrimary)

            Text("Unable to initialize local storage. Please restart the app or reinstall if the problem persists.")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(ProofTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(action: retryAction) {
                Text("Try Again")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(ProofTheme.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(ProofTheme.accent)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ProofTheme.background)
        .onAppear {
            Self.logger.error("ModelContainer failed: \(String(describing: error), privacy: .public)")
        }
    }
}

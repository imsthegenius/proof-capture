import SwiftUI
import SwiftData

@main
struct ProofCaptureApp: App {
    @State private var authManager = AuthManager()
    @State private var syncManager = SyncManager()

    private let container: ModelContainer = {
        do {
            return try ModelContainer(for: PhotoSession.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            SyncBootstrapView(syncManager: syncManager, authManager: authManager)
                .preferredColorScheme(.dark)
                .environment(authManager)
                .environment(syncManager)
        }
        .modelContainer(container)
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

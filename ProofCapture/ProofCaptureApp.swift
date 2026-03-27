import SwiftUI
import SwiftData

@main
struct ProofCaptureApp: App {
    @State private var authManager = AuthManager()
    @State private var syncManager = SyncManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .environment(authManager)
                .environment(syncManager)
                .task {
                    guard let container = try? ModelContainer(for: PhotoSession.self) else { return }
                    let context = ModelContext(container)
                    syncManager.configure(modelContext: context)
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
        .modelContainer(for: PhotoSession.self)
    }
}

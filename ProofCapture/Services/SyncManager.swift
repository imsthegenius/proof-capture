import Foundation
import Supabase
import SwiftData
import UIKit

@Observable
final class SyncManager {
    var isSyncing = false

    private let client = AppSupabase.client
    private var modelContext: ModelContext?

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func syncPendingSessions() async {
        guard let modelContext, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let descriptor = FetchDescriptor<PhotoSession>(
            predicate: #Predicate { $0.syncStatusRaw == 0 || $0.syncStatusRaw == 3 }
        )

        guard let sessions = try? modelContext.fetch(descriptor) else { return }

        for session in sessions {
            await uploadSession(session)
        }
    }

    func restoreFromCloud(userId: String) async {
        guard let modelContext else { return }

        do {
            let remoteSessions: [RemotePhotoSession] = try await client
                .from("photo_sessions")
                .select()
                .eq("user_id", value: userId)
                .execute()
                .value

            let existingDescriptor = FetchDescriptor<PhotoSession>()
            let existingIds = Set((try? modelContext.fetch(existingDescriptor))?.map(\.id) ?? [])

            for remote in remoteSessions {
                guard !existingIds.contains(remote.id) else { continue }

                let session = PhotoSession(date: remote.date)
                session.id = remote.id
                session.isComplete = remote.isComplete
                session.syncStatusRaw = SyncStatus.synced.rawValue

                for (pose, path) in [(Pose.front, remote.frontPhotoPath),
                                     (Pose.side, remote.sidePhotoPath),
                                     (Pose.back, remote.backPhotoPath)] {
                    guard let path else { continue }
                    if let data = try? await client.storage.from("progress-photos").download(path: path) {
                        session.setPhotoData(data, for: pose)
                    }
                }

                modelContext.insert(session)
            }
            try? modelContext.save()
        } catch {
            print("Restore failed: \(error)")
        }
    }

    // MARK: - Private

    private func uploadSession(_ session: PhotoSession) async {
        guard let userId = try? await client.auth.session.user.id.uuidString else { return }

        session.syncStatusRaw = SyncStatus.uploading.rawValue
        try? modelContext?.save()

        do {
            var frontPath: String?
            var sidePath: String?
            var backPath: String?

            for pose in Pose.allCases {
                guard let data = session.photoData(for: pose) else { continue }
                let path = "\(userId)/\(session.id.uuidString)/\(pose.title.lowercased()).jpg"

                _ = try await client.storage
                    .from("progress-photos")
                    .upload(
                        path,
                        data: data,
                        options: FileOptions(contentType: "image/jpeg", upsert: true)
                    )

                switch pose {
                case .front: frontPath = path
                case .side: sidePath = path
                case .back: backPath = path
                }
            }

            try await client
                .from("photo_sessions")
                .upsert(
                    RemotePhotoSession(
                        id: session.id,
                        userId: UUID(uuidString: userId)!,
                        date: session.date,
                        frontPhotoPath: frontPath,
                        sidePhotoPath: sidePath,
                        backPhotoPath: backPath,
                        isComplete: session.isComplete
                    )
                )
                .execute()

            session.syncStatusRaw = SyncStatus.synced.rawValue
            try? modelContext?.save()
        } catch {
            print("Upload failed: \(error)")
            session.syncStatusRaw = SyncStatus.failed.rawValue
            try? modelContext?.save()
        }
    }
}

// MARK: - Remote DTO

struct RemotePhotoSession: Codable {
    let id: UUID
    let userId: UUID
    let date: Date
    let frontPhotoPath: String?
    let sidePhotoPath: String?
    let backPhotoPath: String?
    let isComplete: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case frontPhotoPath = "front_photo_path"
        case sidePhotoPath = "side_photo_path"
        case backPhotoPath = "back_photo_path"
        case isComplete = "is_complete"
    }
}

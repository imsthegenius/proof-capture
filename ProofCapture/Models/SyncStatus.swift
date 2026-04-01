import Foundation

enum SyncStatus: Int, Codable {
    case pending = 0
    case uploading = 1
    case synced = 2
    case failed = 3
}

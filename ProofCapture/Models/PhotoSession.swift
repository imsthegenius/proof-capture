import SwiftData
import Foundation
import UIKit

@Model
final class PhotoSession {
    var id: UUID
    var date: Date
    @Attribute(.externalStorage) var frontPhoto: Data?
    @Attribute(.externalStorage) var sidePhoto: Data?
    @Attribute(.externalStorage) var backPhoto: Data?
    var isComplete: Bool
    var currentPoseRaw: Int
    var syncStatusRaw: Int

    init(date: Date = .now, currentPose: Pose = .front) {
        self.id = UUID()
        self.date = date
        self.isComplete = false
        self.currentPoseRaw = currentPose.rawValue
        self.syncStatusRaw = SyncStatus.pending.rawValue
    }

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }

    var currentPose: Pose {
        get { Pose(rawValue: currentPoseRaw) ?? nextPendingPose }
        set { currentPoseRaw = newValue.rawValue }
    }

    func setPhoto(_ image: UIImage, for pose: Pose) {
        let data = image.jpegData(compressionQuality: 0.9)
        setPhotoData(data, for: pose)
    }

    func setPhotoData(_ data: Data?, for pose: Pose) {
        switch pose {
        case .front: frontPhoto = data
        case .side: sidePhoto = data
        case .back: backPhoto = data
        }
    }

    func photo(for pose: Pose) -> UIImage? {
        guard let data = photoData(for: pose) else { return nil }
        return UIImage(data: data)
    }

    func photoData(for pose: Pose) -> Data? {
        switch pose {
        case .front: frontPhoto
        case .side: sidePhoto
        case .back: backPhoto
        }
    }

    var completedPoseCount: Int {
        [frontPhoto, sidePhoto, backPhoto].compactMap { $0 }.count
    }

    var hasAnyPhotos: Bool {
        completedPoseCount > 0
    }

    var nextPendingPose: Pose {
        for pose in Pose.allCases where photoData(for: pose) == nil {
            return pose
        }
        return .back
    }
}

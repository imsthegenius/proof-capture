import Observation
import SwiftData
import SwiftUI
import UIKit

enum SessionPhase {
    case positioning
    case locked
    case poseHold
    case countdown
    case capturing
    case preview
    case complete
}

enum CaptureEdgeState: Equatable {
    case noBody
}

@Observable
@MainActor
final class SessionViewModel {
    var currentPose: Pose = .front
    var phase: SessionPhase = .positioning
    var capturedImages: [Pose: UIImage] = [:]
    var qualityReports: [Pose: PhotoQualityGate.Report] = [:]
    var countdownValue: Int = 3
    var showAbortConfirmation = false
    var retakePose: Pose?
    var isRetaking = false
    var checkmarkProgress: CGFloat = 0
    var photoScale: CGFloat = 1.03
    var captureFlashOpacity: Double = 0
    var showCompleteContent = false
    var hasBootstrappedSession = false
    var activeSession: PhotoSession?

    // Burst review (iOS26 slide-up sheet shown after capture, before next pose).
    var currentBurst: [UIImage] = []
    var selectedBurstIndex: Int = 0
    var showBurstReview: Bool = false
    var captureEdgeState: CaptureEdgeState?

    var cameraManager = CameraManager()
    var poseDetector = PoseDetector()
    var lightingAnalyzer = LightingAnalyzer()
    var audioGuide = AudioGuide()
    private var modelContext: ModelContext?

    var hasSavedProgress: Bool {
        !capturedImages.isEmpty || activeSession != nil
    }

    var allRequiredPhotosCaptured: Bool {
        Pose.allCases.allSatisfy { capturedImages[$0] != nil }
    }

    var abortTitle: String {
        hasSavedProgress ? "Save draft and exit?" : "End session?"
    }

    var abortMessage: String {
        if hasSavedProgress {
            return "Your progress is saved locally and will resume at the \(resumePoseForDraft.title.lowercased()) pose."
        }

        return "No photos have been captured yet."
    }

    var captureStatusMessage: String? {
        cameraManager.statusMessage
    }

    var resumePoseForDraft: Pose {
        if allRequiredPhotosCaptured {
            return currentPose
        }

        if phase == .preview, !isRetaking, let nextPose = currentPose.next {
            return nextPose
        }

        return currentPose
    }

    func startSession(modelContext: ModelContext) async {
        self.modelContext = modelContext
        guard !hasBootstrappedSession else { return }
        hasBootstrappedSession = true
        showCompleteContent = false
        captureFlashOpacity = 0
        captureEdgeState = nil

        restoreDraftIfNeeded(modelContext: modelContext)
        poseDetector.targetPose = currentPose
        cameraManager.setSampleBufferDelegates([poseDetector, lightingAnalyzer])

        if allRequiredPhotosCaptured {
            phase = .complete
            showCompleteContent = true
            return
        }

        phase = .positioning
        await resumeCapturePipeline(playPrompt: true)
    }

    func resumeCapturePipeline(playPrompt: Bool) async {
        cameraManager.refreshAuthorizationStatus()

        let resumed = await cameraManager.resumeSessionIfPossible()
        guard resumed else { return }

        poseDetector.targetPose = currentPose

        if playPrompt {
            await audioGuide.speak(currentPose.audioPrompt)
        }
    }

    func handleScenePhaseChange(_ newPhase: ScenePhase, modelContext: ModelContext) {
        self.modelContext = modelContext
        guard hasBootstrappedSession else { return }

        switch newPhase {
        case .active:
            if phase != .complete {
                Task { await resumeCapturePipeline(playPrompt: false) }
            }
        case .inactive, .background:
            pauseSessionForRecovery(modelContext: modelContext)
        @unknown default:
            break
        }
    }

    func handleViewExit(modelContext: ModelContext, syncManager: SyncManager) {
        self.modelContext = modelContext
        audioGuide.stop()
        cameraManager.stopSession()
        persistSessionState()

        if activeSession?.isComplete == true {
            Task { await syncManager.syncPendingSessions() }
        }
    }

    func endSession(modelContext: ModelContext) {
        self.modelContext = modelContext
        persistSessionState()
    }

    func pauseSessionForRecovery(modelContext: ModelContext) {
        self.modelContext = modelContext
        audioGuide.stop()
        cameraManager.stopSession()

        if phase != .complete {
            phase = .positioning
        }
        captureEdgeState = nil

        persistSessionState()
    }

    func monitorReadiness() async {
        var readyDuration: TimeInterval = 0
        var timeSinceLastGuidance: TimeInterval = 0
        var noBodyDuration: TimeInterval = 0
        let checkInterval: TimeInterval = 0.25
        let requiredDuration: TimeInterval = 0.3
        let guidanceInterval: TimeInterval = 4.0
        let noBodyThreshold: TimeInterval = 8.0

        while !Task.isCancelled && phase == .positioning {
            if captureStatusMessage != nil || !cameraManager.isRunning {
                readyDuration = 0
                noBodyDuration = 0
                captureEdgeState = nil
                try? await Task.sleep(for: .milliseconds(Int(checkInterval * 1000)))
                continue
            }

            if poseDetector.bodyDetected {
                noBodyDuration = 0
                captureEdgeState = nil
            } else {
                noBodyDuration += checkInterval
                captureEdgeState = noBodyDuration >= noBodyThreshold ? .noBody : nil
            }

            if poseDetector.isReady && lightingAnalyzer.quality != .poor {
                readyDuration += checkInterval
                if readyDuration >= requiredDuration {
                    captureEdgeState = nil
                    await beginLockSequence()
                    return
                }
            } else {
                readyDuration = 0

                timeSinceLastGuidance += checkInterval
                if timeSinceLastGuidance >= guidanceInterval {
                    timeSinceLastGuidance = 0
                    await audioGuide.speakPositionGuidance(
                        bodyDetected: poseDetector.bodyDetected,
                        positionQuality: poseDetector.positionQuality,
                        poseMatches: poseDetector.poseMatchesExpected,
                        armsRelaxed: poseDetector.armsRelaxed,
                        lightingQuality: lightingAnalyzer.quality,
                        targetPose: currentPose,
                        detectedOrientation: poseDetector.detectedOrientation
                    )
                }
            }

            try? await Task.sleep(for: .milliseconds(Int(checkInterval * 1000)))
        }
    }

    func beginLockSequence() async {
        guard phase == .positioning, captureStatusMessage == nil else { return }
        audioGuide.stop()
        captureEdgeState = nil
        phase = .locked

        Task {
            await audioGuide.speakLockAchieved()
        }

        try? await Task.sleep(for: .milliseconds(800))
        guard phase == .locked else { return }

        phase = .poseHold
        try? await Task.sleep(for: .seconds(3))
        guard phase == .poseHold else { return }

        await beginCountdown()
    }

    func beginCountdown() async {
        guard phase == .poseHold, captureStatusMessage == nil else { return }
        phase = .countdown
        countdownValue = 3

        for value in stride(from: countdownValue, through: 1, by: -1) {
            guard phase == .countdown else { return }
            countdownValue = value
            audioGuide.playCountdownTick(isFinal: value == 1)
            try? await Task.sleep(for: .seconds(1))
        }

        guard phase == .countdown else { return }
        await captureCurrentPose()
    }

    func captureCurrentPose() async {
        phase = .capturing
        let flashTask = Task { await triggerCaptureFlash() }

        let burst = await cameraManager.captureBurst(count: 7)
        let pose = currentPose

        // Retain the full burst for the iOS26 slide-up review sheet.
        currentBurst = burst
        selectedBurstIndex = 0

        if let best = await BurstSelector.selectBest(from: burst, pose: pose),
           let bestIndex = burst.firstIndex(where: { $0 === best }) {
            selectedBurstIndex = bestIndex
        }

        await flashTask.value

        guard !burst.isEmpty else {
            phase = .positioning
            currentBurst = []
            captureEdgeState = .noBody
            return
        }

        ProofTheme.hapticSuccess()
        phase = .preview
        showBurstReview = true
    }

    /// Called from the burst review sheet when the user taps "Use this shot".
    /// Commits the selected burst frame, persists, and advances to the next pose.
    func confirmBurstSelection() async {
        guard !currentBurst.isEmpty else { return }
        let pose = currentPose
        let chosen = currentBurst[selectedBurstIndex]
        capturedImages[pose] = chosen

        // Quality gate runs in background — never blocks the user.
        Task {
            let report = await PhotoQualityGate.assess(image: chosen, pose: pose)
            self.qualityReports[pose] = report
        }

        let resumePose = allRequiredPhotosCaptured ? pose : (pose.next ?? pose)
        persistSessionState(resumePose: resumePose)

        if allRequiredPhotosCaptured {
            cameraManager.stopSession()
        }

        showBurstReview = false
        currentBurst = []
        selectedBurstIndex = 0

        if isRetaking {
            isRetaking = false
            await enterCompletePhase(playAnnouncement: false)
            persistSessionState()
            return
        }

        if let next = pose.next {
            currentPose = next
            poseDetector.targetPose = next
            phase = .positioning
            captureEdgeState = nil
            await audioGuide.speakPoseTransition(from: pose, to: next)
        } else {
            await enterCompletePhase(playAnnouncement: true)
            persistSessionState()
        }
    }

    /// Called from the burst review sheet when the user taps "Redo".
    /// Discards the burst and returns to positioning for the same pose.
    func redoBurst() {
        showBurstReview = false
        currentBurst = []
        selectedBurstIndex = 0
        phase = .positioning
        captureEdgeState = nil
    }

    func triggerCaptureFlash() async {
        withAnimation(.easeOut(duration: 0.06)) {
            captureFlashOpacity = 0.85
        }

        try? await Task.sleep(for: .milliseconds(90))

        withAnimation(.easeOut(duration: 0.22)) {
            captureFlashOpacity = 0
        }
    }

    func enterCompletePhase(playAnnouncement: Bool) async {
        cameraManager.stopSession()
        showCompleteContent = false

        withAnimation(.easeOut(duration: 0.35)) {
            phase = .complete
        }

        if playAnnouncement {
            await audioGuide.speakSessionComplete()
            ProofTheme.hapticSuccess()
            try? await Task.sleep(for: .milliseconds(200))
            ProofTheme.hapticSuccess()
        }

        try? await Task.sleep(for: .milliseconds(120))
        withAnimation(.easeOut(duration: 0.45)) {
            showCompleteContent = true
        }
    }

    func saveAndFinish(modelContext: ModelContext) async {
        self.modelContext = modelContext
        for pose in Pose.allCases {
            if let image = capturedImages[pose] {
                _ = await cameraManager.saveToPhotoLibrary(image)
            }
        }
    }

    func retakeFromComplete(_ pose: Pose, modelContext: ModelContext) async {
        self.modelContext = modelContext
        isRetaking = true
        showCompleteContent = false
        capturedImages[pose] = nil
        qualityReports[pose] = nil
        currentPose = pose
        poseDetector.targetPose = pose
        phase = .positioning
        captureEdgeState = nil
        persistSessionState(resumePose: pose)
        await resumeCapturePipeline(playPrompt: true)
    }

    private func restoreDraftIfNeeded(modelContext: ModelContext) {
        guard let draft = fetchLatestDraft(modelContext: modelContext) else { return }

        activeSession = draft

        var restoredImages: [Pose: UIImage] = [:]
        for pose in Pose.allCases {
            if let image = draft.photo(for: pose) {
                restoredImages[pose] = image
            }
        }
        capturedImages = restoredImages

        let storedPose = draft.currentPose
        if draft.isComplete {
            currentPose = storedPose
            phase = .complete
        } else if draft.photoData(for: storedPose) == nil {
            currentPose = storedPose
        } else {
            currentPose = draft.nextPendingPose
        }
    }

    private func fetchLatestDraft(modelContext: ModelContext) -> PhotoSession? {
        let descriptor = FetchDescriptor<PhotoSession>(
            predicate: #Predicate { $0.isComplete == false },
            sortBy: [SortDescriptor(\PhotoSession.date, order: .reverse)]
        )

        return try? modelContext.fetch(descriptor).first
    }

    private func persistSessionState(resumePose: Pose? = nil) {
        guard hasSavedProgress else { return }

        let session = activeSession ?? PhotoSession(date: .now, currentPose: resumePose ?? resumePoseForDraft)
        if activeSession == nil {
            modelContext?.insert(session)
            activeSession = session
        }

        session.currentPose = resumePose ?? resumePoseForDraft
        session.isComplete = allRequiredPhotosCaptured
        session.syncStatus = .pending

        for pose in Pose.allCases {
            let data = capturedImages[pose]?.jpegData(compressionQuality: 0.9)
            session.setPhotoData(data, for: pose)
        }

        try? modelContext?.save()
    }
}

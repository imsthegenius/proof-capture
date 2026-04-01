import UIKit
import AVFoundation
import Photos

@Observable
final class CameraManager: NSObject {

    let session = AVCaptureSession()
    private(set) var isRunning = false
    private(set) var currentPosition: AVCaptureDevice.Position = .front
    private(set) var isTorchOn = false
    private(set) var authorizationStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    private(set) var interruptionMessage: String?

    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private let videoOutputQueue = DispatchQueue(label: "camera.videoOutput")

    private var photoContinuation: CheckedContinuation<UIImage?, Never>?
    private var multiplexer: SampleBufferMultiplexer?
    private var isConfigured = false
    private var hasInstalledObservers = false

    var needsPermissionRecovery: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    var statusMessage: String? {
        if needsPermissionRecovery {
            return Self.permissionRecoveryMessage(for: authorizationStatus)
        }
        return interruptionMessage
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Registers multiple frame delegates (e.g. PoseDetector + LightingAnalyzer).
    /// Each delegate receives every frame and can throttle independently.
    func setSampleBufferDelegates(_ delegates: [AVCaptureVideoDataOutputSampleBufferDelegate]) {
        multiplexer = SampleBufferMultiplexer(delegates: delegates)
        videoOutput.setSampleBufferDelegate(multiplexer, queue: videoOutputQueue)
    }

    // MARK: - Authorization

    func refreshAuthorizationStatus() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        Task { @MainActor in
            authorizationStatus = status
        }
    }

    func ensureCameraAccess() async -> Bool {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)

        switch currentStatus {
        case .authorized:
            Task { @MainActor in
                authorizationStatus = currentStatus
            }
            return true

        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            let resolvedStatus = AVCaptureDevice.authorizationStatus(for: .video)
            Task { @MainActor in
                authorizationStatus = resolvedStatus
            }
            return granted

        case .denied, .restricted:
            Task { @MainActor in
                authorizationStatus = currentStatus
            }
            return false

        @unknown default:
            Task { @MainActor in
                authorizationStatus = currentStatus
            }
            return false
        }
    }

    func resumeSessionIfPossible() async -> Bool {
        let hasAccess = await ensureCameraAccess()
        guard hasAccess else {
            stopSession()
            return false
        }

        configure()
        startSession()
        return true
    }

    // MARK: - Configuration

    func configure() {
        installObserversIfNeeded()

        sessionQueue.async { [self] in
            guard !isConfigured else {
                updateCaptureConnections()
                return
            }

            session.beginConfiguration()
            session.sessionPreset = .photo

            defer {
                session.commitConfiguration()
            }

            guard let input = makeInput(position: currentPosition),
                  session.canAddInput(input) else {
                return
            }

            session.addInput(input)

            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            }

            videoOutput.alwaysDiscardsLateVideoFrames = true
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }

            updateCaptureConnections()
            isConfigured = true
        }
    }

    // MARK: - Camera position & torch

    func switchCamera() {
        sessionQueue.async { [self] in
            let newPosition: AVCaptureDevice.Position = currentPosition == .front ? .back : .front

            session.beginConfiguration()

            if let currentInput = session.inputs.first as? AVCaptureDeviceInput {
                session.removeInput(currentInput)
            }

            guard let input = makeInput(position: newPosition),
                  session.canAddInput(input) else {
                session.commitConfiguration()
                return
            }

            session.addInput(input)
            updateCaptureConnections()
            session.commitConfiguration()

            Task { @MainActor in
                currentPosition = newPosition
                if newPosition == .front {
                    isTorchOn = false
                }
            }
        }
    }

    func toggleTorch() {
        sessionQueue.async { [self] in
            guard let device = (session.inputs.first as? AVCaptureDeviceInput)?.device,
                  device.hasTorch else { return }

            do {
                try device.lockForConfiguration()
                let newState = !device.isTorchActive
                device.torchMode = newState ? .on : .off
                device.unlockForConfiguration()
                Task { @MainActor in
                    isTorchOn = newState
                }
            } catch {}
        }
    }

    // MARK: - Session control

    func startSession() {
        sessionQueue.async { [self] in
            guard !session.isRunning else { return }
            session.startRunning()
            Task { @MainActor in
                isRunning = true
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [self] in
            guard session.isRunning else { return }
            session.stopRunning()
            Task { @MainActor in
                isRunning = false
            }
        }
    }

    // MARK: - Burst capture

    func captureBurst(count: Int) async -> [UIImage] {
        var images: [UIImage] = []

        for i in 0..<count {
            if i > 0 {
                try? await Task.sleep(for: .milliseconds(150))
            }

            if let image = await captureOnePhoto() {
                images.append(image)
            }
        }

        return images
    }

    private func captureOnePhoto() async -> UIImage? {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                if let pending = photoContinuation {
                    pending.resume(returning: nil)
                    photoContinuation = nil
                }

                updateCaptureConnections()

                photoContinuation = continuation
                photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    // MARK: - Save to photo library

    func saveToPhotoLibrary(_ image: UIImage) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Private helpers

    private func makeInput(position: AVCaptureDevice.Position) -> AVCaptureDeviceInput? {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            return nil
        }

        return try? AVCaptureDeviceInput(device: camera)
    }

    private func updateCaptureConnections() {
        configure(connection: photoOutput.connection(with: .video), mirrored: currentPosition == .front)
        configure(connection: videoOutput.connection(with: .video), mirrored: false)
    }

    private func configure(connection: AVCaptureConnection?, mirrored: Bool) {
        guard let connection else { return }

        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }

        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }

    private func installObserversIfNeeded() {
        guard !hasInstalledObservers else { return }
        hasInstalledObservers = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionInterrupted(_:)),
            name: AVCaptureSession.wasInterruptedNotification,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionInterruptionEnded(_:)),
            name: AVCaptureSession.interruptionEndedNotification,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRuntimeError(_:)),
            name: AVCaptureSession.runtimeErrorNotification,
            object: session
        )
    }

    @objc
    private func handleSessionInterrupted(_ notification: Notification) {
        let rawReason = (notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)?.intValue
        let reason = rawReason.flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))
        let message = Self.interruptionMessage(for: reason)

        Task { @MainActor in
            interruptionMessage = message
            isRunning = false
        }
    }

    @objc
    private func handleSessionInterruptionEnded(_: Notification) {
        Task { @MainActor in
            interruptionMessage = nil
        }
    }

    @objc
    private func handleRuntimeError(_ notification: Notification) {
        let message: String
        if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError {
            message = "Camera error: \(error.localizedDescription)"
        } else {
            message = "Camera paused. Reopen the session to continue."
        }

        Task { @MainActor in
            interruptionMessage = message
            isRunning = false
        }
    }

    private static func permissionRecoveryMessage(for status: AVAuthorizationStatus) -> String {
        switch status {
        case .denied:
            return "Camera access is off. Enable it in Settings to resume this session."
        case .restricted:
            return "Camera access is restricted on this device."
        case .notDetermined:
            return "Camera access is required to continue."
        case .authorized:
            return ""
        @unknown default:
            return "Camera access is unavailable right now."
        }
    }

    private static func interruptionMessage(for reason: AVCaptureSession.InterruptionReason?) -> String {
        switch reason {
        case .audioDeviceInUseByAnotherClient, .videoDeviceInUseByAnotherClient:
            return "Camera is in use by another app. Return when it is free."
        case .videoDeviceNotAvailableWithMultipleForegroundApps:
            return "Camera is unavailable while another app is active on screen."
        case .videoDeviceNotAvailableDueToSystemPressure:
            return "Camera paused because the device is under heavy load. Give it a moment."
        default:
            return "Camera interrupted. Return when ready to continue."
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraManager: AVCapturePhotoCaptureDelegate {

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let image: UIImage?
        if let data = photo.fileDataRepresentation() {
            image = UIImage(data: data)
        } else {
            image = nil
        }

        photoContinuation?.resume(returning: image)
        photoContinuation = nil
    }
}

// MARK: - Sample buffer multiplexer

/// Forwards each video frame to multiple delegates so PoseDetector
/// and LightingAnalyzer can both process frames independently.
final class SampleBufferMultiplexer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let delegates: [AVCaptureVideoDataOutputSampleBufferDelegate]

    init(delegates: [AVCaptureVideoDataOutputSampleBufferDelegate]) {
        self.delegates = delegates
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        for delegate in delegates {
            delegate.captureOutput?(output, didOutput: sampleBuffer, from: connection)
        }
    }
}

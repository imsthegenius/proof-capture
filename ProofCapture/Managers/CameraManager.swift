import UIKit
import AVFoundation
import Photos

@Observable
final class CameraManager: NSObject {

    let session = AVCaptureSession()
    private(set) var isRunning = false
    private(set) var currentPosition: AVCaptureDevice.Position = .back
    private(set) var isTorchOn = false

    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private let videoOutputQueue = DispatchQueue(label: "camera.videoOutput")

    private var photoContinuation: CheckedContinuation<UIImage?, Never>?
    private var multiplexer: SampleBufferMultiplexer?

    /// Registers multiple frame delegates (e.g. PoseDetector + LightingAnalyzer).
    /// Each delegate receives every frame and can throttle independently.
    func setSampleBufferDelegates(_ delegates: [AVCaptureVideoDataOutputSampleBufferDelegate]) {
        multiplexer = SampleBufferMultiplexer(delegates: delegates)
        videoOutput.setSampleBufferDelegate(multiplexer, queue: videoOutputQueue)
    }

    // MARK: - Configuration

    func configure() {
        sessionQueue.async { [self] in
            session.beginConfiguration()
            session.sessionPreset = .photo

            // Camera input
            guard let camera = AVCaptureDevice.default(
                .builtInWideAngleCamera, for: .video, position: currentPosition
            ),
            let input = try? AVCaptureDeviceInput(device: camera),
            session.canAddInput(input) else {
                session.commitConfiguration()
                return
            }
            session.addInput(input)

            // Photo output
            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            }

            // Video data output for live frame analysis
            videoOutput.alwaysDiscardsLateVideoFrames = true
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }

            session.commitConfiguration()
        }
    }

    // MARK: - Camera position & torch

    func switchCamera() {
        sessionQueue.async { [self] in
            let newPosition: AVCaptureDevice.Position = currentPosition == .back ? .front : .back

            session.beginConfiguration()

            // Remove existing input
            if let currentInput = session.inputs.first as? AVCaptureDeviceInput {
                session.removeInput(currentInput)
            }

            guard let camera = AVCaptureDevice.default(
                .builtInWideAngleCamera, for: .video, position: newPosition
            ),
            let input = try? AVCaptureDeviceInput(device: camera),
            session.canAddInput(input) else {
                session.commitConfiguration()
                return
            }

            session.addInput(input)
            session.commitConfiguration()

            Task { @MainActor in
                self.currentPosition = newPosition
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
                Task { @MainActor in self.isTorchOn = newState }
            } catch {}
        }
    }

    // MARK: - Session control

    func startSession() {
        sessionQueue.async { [self] in
            guard !session.isRunning else { return }
            session.startRunning()
            Task { @MainActor in isRunning = true }
        }
    }

    func stopSession() {
        sessionQueue.async { [self] in
            guard session.isRunning else { return }
            session.stopRunning()
            Task { @MainActor in isRunning = false }
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
                // Guard against stomping a pending continuation from the previous burst frame
                if let pending = photoContinuation {
                    pending.resume(returning: nil)
                    photoContinuation = nil
                }

                photoContinuation = continuation

                let settings = AVCapturePhotoSettings()
                photoOutput.capturePhoto(with: settings, delegate: self)
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

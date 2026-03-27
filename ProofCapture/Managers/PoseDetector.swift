import Vision
import AVFoundation
import UIKit

@Observable
final class PoseDetector: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    var bodyDetected = false
    var positionQuality: QualityLevel = .poor
    var feedback = "Stand in front of the camera"
    var bodyRect: CGRect = .zero

    private var lastAnalysisTime: CFAbsoluteTime = 0
    private let analysisInterval: CFAbsoluteTime = 0.1 // ~10fps throttle

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastAnalysisTime >= analysisInterval else { return }
        lastAnalysisTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)

        do {
            try handler.perform([request])
        } catch {
            updateState(detected: false, quality: .poor, feedback: "Stand in front of the camera", rect: .zero)
            return
        }

        guard let observation = request.results?.first else {
            updateState(detected: false, quality: .poor, feedback: "Stand in front of the camera", rect: .zero)
            return
        }

        analyzeBodyPose(observation)
    }

    // MARK: - Analysis

    private func analyzeBodyPose(_ observation: VNHumanBodyPoseObservation) {
        let jointNames: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .neck,
            .leftShoulder, .rightShoulder,
            .leftHip, .rightHip,
            .leftAnkle, .rightAnkle
        ]

        var points: [CGPoint] = []
        for joint in jointNames {
            if let point = try? observation.recognizedPoint(joint), point.confidence > 0.1 {
                points.append(point.location)
            }
        }

        guard points.count >= 3 else {
            updateState(detected: true, quality: .poor, feedback: "Can't see your full body — step back", rect: .zero)
            return
        }

        // Calculate bounding box from detected joints
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min()!
        let maxX = xs.max()!
        let minY = ys.min()!
        let maxY = ys.max()!

        let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        let centerX = rect.midX
        let height = rect.height

        // Evaluate positioning
        var issues: [String] = []

        if height > 0.85 {
            issues.append("Step back a bit")
        } else if height < 0.4 {
            issues.append("Move closer")
        }

        if centerX < 0.35 {
            issues.append("Move to center")
        } else if centerX > 0.65 {
            issues.append("Move to center")
        }

        let quality: QualityLevel
        let feedbackText: String

        switch issues.count {
        case 0:
            quality = .good
            feedbackText = "Good position"
        case 1:
            quality = .fair
            feedbackText = issues[0]
        default:
            quality = .poor
            feedbackText = issues.joined(separator: " · ")
        }

        updateState(detected: true, quality: quality, feedback: feedbackText, rect: rect)
    }

    private func updateState(detected: Bool, quality: QualityLevel, feedback: String, rect: CGRect) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.bodyDetected = detected
            self.positionQuality = quality
            self.feedback = feedback
            self.bodyRect = rect
        }
    }
}

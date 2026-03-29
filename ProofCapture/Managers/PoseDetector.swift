import Vision
import AVFoundation
import UIKit

@Observable @MainActor
final class PoseDetector: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    // MARK: - Public State

    var bodyDetected = false
    var positionQuality: QualityLevel = .poor
    var feedback = "Step into the frame"
    var bodyRect: CGRect = .zero

    var targetPose: Pose = .front {
        didSet { _targetPoseCache = targetPose }
    }
    var detectedOrientation: Pose? = nil
    var poseMatchesExpected = false
    var isReady = false
    var armsRelaxed = false

    // MARK: - Private

    nonisolated(unsafe) private var lastAnalysisTime: CFAbsoluteTime = 0
    nonisolated(unsafe) private var _targetPoseCache: Pose = .front
    private let analysisInterval: CFAbsoluteTime = 0.1 // ~10fps — sufficient for positioning guidance

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    nonisolated func captureOutput(
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
            publish(detected: false, quality: .poor, feedback: "Step into the frame",
                    rect: .zero, orientation: nil, poseMatch: false, arms: false, ready: false)
            return
        }

        guard let observation = request.results?.first else {
            publish(detected: false, quality: .poor, feedback: "Step into the frame",
                    rect: .zero, orientation: nil, poseMatch: false, arms: false, ready: false)
            return
        }

        analyze(observation)
    }

    // MARK: - Analysis Pipeline

    nonisolated private func analyze(_ observation: VNHumanBodyPoseObservation) {
        // 1. Collect visible joints for bounding box
        let trackingJoints: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .neck, .leftShoulder, .rightShoulder,
            .leftHip, .rightHip, .leftAnkle, .rightAnkle
        ]

        var points: [CGPoint] = []
        for joint in trackingJoints {
            if let point = try? observation.recognizedPoint(joint), point.confidence > 0.3 {
                points.append(point.location)
            }
        }

        guard points.count >= 3 else {
            publish(detected: true, quality: .poor, feedback: "Can't see your full body — step back",
                    rect: .zero, orientation: nil, poseMatch: false, arms: false, ready: false)
            return
        }

        // 2. Bounding box (Vision coords: 0,0 = bottom-left)
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let rect = CGRect(x: xs.min()!, y: ys.min()!,
                          width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)

        // 3. Position assessment
        let positionResult = assessPosition(rect: rect)

        // 4. Orientation detection
        let orientation = detectOrientation(from: observation)

        // 5. Pose match (read from cache to avoid main actor hop)
        let poseMatch = (orientation == _targetPoseCache)

        // 6. Arms check
        let arms = checkArmsRelaxed(from: observation)

        // 7. Composite readiness
        let ready = positionResult.quality == .good && poseMatch && arms

        // 8. Build feedback string (priority order)
        let feedbackText: String
        if positionResult.quality == .poor {
            feedbackText = positionResult.feedback
        } else if !poseMatch, let orientation {
            feedbackText = orientationFeedback(target: _targetPoseCache, detected: orientation)
        } else if !arms {
            feedbackText = "Relax your arms at your sides"
        } else if positionResult.quality == .fair {
            feedbackText = positionResult.feedback
        } else if ready {
            feedbackText = "Perfect — hold still"
        } else {
            feedbackText = "Adjusting..."
        }

        publish(detected: true, quality: positionResult.quality, feedback: feedbackText,
                rect: rect, orientation: orientation, poseMatch: poseMatch, arms: arms, ready: ready)
    }

    // MARK: - Position Assessment

    private struct PositionResult {
        let quality: QualityLevel
        let feedback: String
    }

    nonisolated private func assessPosition(rect: CGRect) -> PositionResult {
        let centerX = rect.midX
        let bodyHeight = rect.height
        var issues: [String] = []

        // Distance (body height in normalized coords)
        if bodyHeight > 0.80 {
            issues.append("Step back")
        } else if bodyHeight < 0.35 {
            issues.append("Move closer")
        }

        // Centering (Vision coords: 0.5 = center)
        if centerX < 0.35 {
            issues.append("Move right")
        } else if centerX > 0.65 {
            issues.append("Move left")
        }

        switch issues.count {
        case 0:
            return PositionResult(quality: .good, feedback: "Good position")
        case 1:
            return PositionResult(quality: .fair, feedback: issues[0])
        default:
            return PositionResult(quality: .poor, feedback: issues.joined(separator: " · "))
        }
    }

    // MARK: - Orientation Detection

    nonisolated private func detectOrientation(from observation: VNHumanBodyPoseObservation) -> Pose? {
        let nose = try? observation.recognizedPoint(.nose)
        let leftEar = try? observation.recognizedPoint(.leftEar)
        let rightEar = try? observation.recognizedPoint(.rightEar)
        let leftShoulder = try? observation.recognizedPoint(.leftShoulder)
        let rightShoulder = try? observation.recognizedPoint(.rightShoulder)

        let noseConf = nose?.confidence ?? 0
        let leftEarConf = leftEar?.confidence ?? 0
        let rightEarConf = rightEar?.confidence ?? 0
        let leftShoulderConf = leftShoulder?.confidence ?? 0
        let rightShoulderConf = rightShoulder?.confidence ?? 0

        // Shoulder width (normalized x-distance)
        let shoulderWidth: CGFloat = {
            guard leftShoulderConf > 0.3, rightShoulderConf > 0.3,
                  let ls = leftShoulder, let rs = rightShoulder else { return 0 }
            return abs(ls.location.x - rs.location.x)
        }()

        // BACK: nose not visible at all
        if noseConf < 0.1 {
            return .back
        }

        // SIDE: ear asymmetry + compressed shoulder width
        let earAsymmetry = abs(leftEarConf - rightEarConf)
        if earAsymmetry > 0.3 && shoulderWidth < 0.15 {
            return .side
        }

        // Also SIDE: only one shoulder visible with confidence
        if (leftShoulderConf > 0.3) != (rightShoulderConf > 0.3) {
            return .side
        }

        // FRONT: nose visible + shoulders spread
        if noseConf > 0.3 && shoulderWidth > 0.12 {
            return .front
        }

        return nil
    }

    nonisolated private func orientationFeedback(target: Pose, detected: Pose) -> String {
        switch (target, detected) {
        case (.front, .side): "Turn to face the camera"
        case (.front, .back): "Turn around to face the camera"
        case (.side, .front): "Turn to your left side"
        case (.side, .back): "Turn a bit more to show your profile"
        case (.back, .front): "Turn away from the camera"
        case (.back, .side): "Turn a bit more, face the wall"
        default: "Adjust your position"
        }
    }

    // MARK: - Arms Relaxed Check

    nonisolated private func checkArmsRelaxed(from observation: VNHumanBodyPoseObservation) -> Bool {
        guard let leftWrist = try? observation.recognizedPoint(.leftWrist),
              let rightWrist = try? observation.recognizedPoint(.rightWrist),
              let leftHip = try? observation.recognizedPoint(.leftHip),
              let rightHip = try? observation.recognizedPoint(.rightHip),
              leftWrist.confidence > 0.3, rightWrist.confidence > 0.3,
              leftHip.confidence > 0.3, rightHip.confidence > 0.3 else {
            // Can't see wrists = probably back pose, assume OK
            return true
        }

        // Wrist near hip height (Y within 8% of frame)
        let leftYOK = abs(leftWrist.location.y - leftHip.location.y) < 0.08
        let rightYOK = abs(rightWrist.location.y - rightHip.location.y) < 0.08

        // Wrist horizontally near hip (X within 6% of frame)
        let leftXOK = abs(leftWrist.location.x - leftHip.location.x) < 0.06
        let rightXOK = abs(rightWrist.location.x - rightHip.location.x) < 0.06

        // Elbow angle check — arms at sides should be ~160-180 degrees
        if let leftElbow = try? observation.recognizedPoint(.leftElbow),
           let leftShoulder = try? observation.recognizedPoint(.leftShoulder),
           leftElbow.confidence > 0.3, leftShoulder.confidence > 0.3 {
            let angle = angleBetween(
                p1: leftShoulder.location, vertex: leftElbow.location, p2: leftWrist.location
            )
            if angle < 150 { return false }
        }

        return leftYOK && rightYOK && leftXOK && rightXOK
    }

    nonisolated private func angleBetween(p1: CGPoint, vertex: CGPoint, p2: CGPoint) -> CGFloat {
        let v1 = CGPoint(x: p1.x - vertex.x, y: p1.y - vertex.y)
        let v2 = CGPoint(x: p2.x - vertex.x, y: p2.y - vertex.y)
        let dot = v1.x * v2.x + v1.y * v2.y
        let mag1 = sqrt(v1.x * v1.x + v1.y * v1.y)
        let mag2 = sqrt(v2.x * v2.x + v2.y * v2.y)
        guard mag1 > 0, mag2 > 0 else { return 180 }
        let cosAngle = dot / (mag1 * mag2)
        return acos(min(max(cosAngle, -1), 1)) * 180 / .pi
    }

    // MARK: - State Publishing

    nonisolated private func publish(
        detected: Bool, quality: QualityLevel, feedback: String, rect: CGRect,
        orientation: Pose?, poseMatch: Bool, arms: Bool, ready: Bool
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.bodyDetected = detected
            self.positionQuality = quality
            self.feedback = feedback
            self.bodyRect = rect
            self.detectedOrientation = orientation
            self.poseMatchesExpected = poseMatch
            self.armsRelaxed = arms
            self.isReady = ready
        }
    }
}

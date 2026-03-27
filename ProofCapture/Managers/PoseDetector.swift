import Vision
import AVFoundation
import UIKit

@Observable
final class PoseDetector: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    // MARK: - Existing Public Properties (preserved for compatibility)

    var bodyDetected = false
    var positionQuality: QualityLevel = .poor
    var feedback = "Stand in front of the camera"
    var bodyRect: CGRect = .zero

    // MARK: - New Public Properties

    /// Set by SessionView before each pose to indicate which orientation we expect.
    var targetPose: Pose = .front

    /// The orientation Vision actually detects from joint visibility.
    var detectedOrientation: Pose? = nil

    /// True when detectedOrientation matches targetPose.
    var poseMatchesExpected: Bool = false

    /// True when position is good AND pose matches AND arms are relaxed.
    var isReady: Bool = false

    /// True when wrists are near hip level (arms hanging at sides).
    var armsRelaxed: Bool = false

    // MARK: - Private

    private var lastAnalysisTime: CFAbsoluteTime = 0
    private let analysisInterval: CFAbsoluteTime = 0.1 // ~10fps throttle

    /// Ideal body height ratio in frame (60-80% of frame height).
    private let idealHeightMin: CGFloat = 0.50
    private let idealHeightMax: CGFloat = 0.80

    /// Acceptable horizontal center band.
    private let centerBandMin: CGFloat = 0.35
    private let centerBandMax: CGFloat = 0.65

    /// Confidence threshold for a joint to be considered "visible".
    private let jointConfidence: Float = 0.3

    /// Confidence threshold for wrist/hip (lower because extremities are harder to detect).
    private let extremityConfidence: Float = 0.2

    /// Max vertical distance between wrist and hip (normalized) for arms to be "relaxed".
    private let armsRelaxedThreshold: CGFloat = 0.15

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
            updateState(
                detected: false,
                quality: .poor,
                feedback: "Stand in front of the camera",
                rect: .zero,
                orientation: nil,
                poseMatch: false,
                arms: false
            )
            return
        }

        guard let observation = request.results?.first else {
            updateState(
                detected: false,
                quality: .poor,
                feedback: "Stand in front of the camera",
                rect: .zero,
                orientation: nil,
                poseMatch: false,
                arms: false
            )
            return
        }

        analyzeBodyPose(observation)
    }

    // MARK: - Analysis

    private func analyzeBodyPose(_ observation: VNHumanBodyPoseObservation) {
        // Collect key joint positions
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
            updateState(
                detected: true,
                quality: .poor,
                feedback: "Can't see your full body -- step back",
                rect: .zero,
                orientation: nil,
                poseMatch: false,
                arms: false
            )
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

        // -- Orientation detection --
        let orientation = detectOrientation(from: observation)

        // -- Arms check --
        let arms = checkArmsRelaxed(from: observation)

        // -- Position evaluation --
        var issues: [String] = []

        // Distance scoring with granular feedback
        if height > 0.90 {
            issues.append("Step back 3 feet")
        } else if height > idealHeightMax {
            issues.append("Step back 2 feet")
        } else if height < 0.35 {
            issues.append("Move 3 feet closer")
        } else if height < idealHeightMin {
            issues.append("Move 1 foot closer")
        }

        // Centering
        if centerX < centerBandMin {
            issues.append("Move to center")
        } else if centerX > centerBandMax {
            issues.append("Move to center")
        }

        // Pose mismatch feedback (only if position is otherwise OK)
        let poseMatch = (orientation == targetPose)
        if !poseMatch && orientation != nil && issues.isEmpty {
            let orientationName = orientation?.title ?? "unknown"
            issues.append("Turn to \(targetPose.title) (seeing \(orientationName))")
        }

        // Arms feedback (only when pose and position are OK)
        if !arms && issues.isEmpty && poseMatch {
            issues.append("Relax arms at your sides")
        }

        // Determine overall quality and feedback
        let quality: QualityLevel
        let feedbackText: String

        let positionGood = (height >= idealHeightMin && height <= idealHeightMax
                            && centerX >= centerBandMin && centerX <= centerBandMax)

        if positionGood && poseMatch && arms {
            quality = .good
            feedbackText = "Perfect -- hold still"
        } else if positionGood && poseMatch {
            quality = .fair
            feedbackText = issues.isEmpty ? "Good position" : issues[0]
        } else if positionGood {
            quality = .fair
            feedbackText = issues.isEmpty ? "Good position" : issues[0]
        } else {
            switch issues.count {
            case 0:
                quality = .good
                feedbackText = "Perfect distance"
            case 1:
                quality = .fair
                feedbackText = issues[0]
            default:
                quality = .poor
                feedbackText = issues.joined(separator: " -- ")
            }
        }

        updateState(
            detected: true,
            quality: quality,
            feedback: feedbackText,
            rect: rect,
            orientation: orientation,
            poseMatch: poseMatch,
            arms: arms
        )
    }

    // MARK: - Orientation Detection

    /// Determines whether the user is facing front, side, or back based on joint visibility.
    private func detectOrientation(from observation: VNHumanBodyPoseObservation) -> Pose? {
        let nose = try? observation.recognizedPoint(.nose)
        let leftShoulder = try? observation.recognizedPoint(.leftShoulder)
        let rightShoulder = try? observation.recognizedPoint(.rightShoulder)
        let leftHip = try? observation.recognizedPoint(.leftHip)
        let rightHip = try? observation.recognizedPoint(.rightHip)
        let leftEye = try? observation.recognizedPoint(.leftEye)
        let rightEye = try? observation.recognizedPoint(.rightEye)

        let noseVisible = (nose?.confidence ?? 0) > jointConfidence
        let leftShoulderVisible = (leftShoulder?.confidence ?? 0) > jointConfidence
        let rightShoulderVisible = (rightShoulder?.confidence ?? 0) > jointConfidence
        let leftHipVisible = (leftHip?.confidence ?? 0) > jointConfidence
        let rightHipVisible = (rightHip?.confidence ?? 0) > jointConfidence
        let leftEyeVisible = (leftEye?.confidence ?? 0) > jointConfidence
        let rightEyeVisible = (rightEye?.confidence ?? 0) > jointConfidence

        // Front: nose + both shoulders visible with reasonable symmetry
        if noseVisible && leftShoulderVisible && rightShoulderVisible {
            if let n = nose, let ls = leftShoulder, let rs = rightShoulder,
               n.confidence > jointConfidence,
               ls.confidence > jointConfidence,
               rs.confidence > jointConfidence {
                let leftDist = abs(n.location.x - ls.location.x)
                let rightDist = abs(n.location.x - rs.location.x)
                let maxDist = max(leftDist, rightDist)
                if maxDist > 0 {
                    let symmetryRatio = min(leftDist, rightDist) / maxDist
                    if symmetryRatio > 0.5 {
                        return .front
                    }
                    // Asymmetric shoulders with nose visible = turning to side
                    return .side
                }
            }
            return .front
        }

        // Back: no nose and no eyes visible, but shoulders or hips visible
        let faceVisible = noseVisible || leftEyeVisible || rightEyeVisible
        let bodyVisible = (leftShoulderVisible || rightShoulderVisible)
                        && (leftHipVisible || rightHipVisible)
        if !faceVisible && bodyVisible {
            return .back
        }

        // Side: only one shoulder visible (other occluded by torso)
        if leftShoulderVisible != rightShoulderVisible {
            return .side
        }

        // Nose visible but shoulders not clearly seen = ambiguous, lean toward side
        if noseVisible && !leftShoulderVisible && !rightShoulderVisible {
            return .side
        }

        return nil
    }

    // MARK: - Arms-at-Sides Check

    /// Returns true when wrists are near hip level, indicating arms are relaxed at sides.
    /// If wrists can't be detected (common in back pose), returns true by default.
    private func checkArmsRelaxed(from observation: VNHumanBodyPoseObservation) -> Bool {
        guard let leftWrist = try? observation.recognizedPoint(.leftWrist),
              let rightWrist = try? observation.recognizedPoint(.rightWrist),
              let leftHip = try? observation.recognizedPoint(.leftHip),
              let rightHip = try? observation.recognizedPoint(.rightHip),
              leftWrist.confidence > extremityConfidence,
              rightWrist.confidence > extremityConfidence,
              leftHip.confidence > extremityConfidence,
              rightHip.confidence > extremityConfidence else {
            // Can't see wrists = probably fine (back pose or occluded)
            return true
        }

        // Wrists should be near hip level (within threshold of body height)
        let leftOK = abs(leftWrist.location.y - leftHip.location.y) < armsRelaxedThreshold
        let rightOK = abs(rightWrist.location.y - rightHip.location.y) < armsRelaxedThreshold
        return leftOK && rightOK
    }

    // MARK: - State Update

    private func updateState(
        detected: Bool,
        quality: QualityLevel,
        feedback: String,
        rect: CGRect,
        orientation: Pose?,
        poseMatch: Bool,
        arms: Bool
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.bodyDetected = detected
            self.positionQuality = quality
            self.feedback = feedback
            self.bodyRect = rect
            self.detectedOrientation = orientation
            self.poseMatchesExpected = poseMatch
            self.armsRelaxed = arms
            self.isReady = (quality == .good && poseMatch && arms)
        }
    }
}

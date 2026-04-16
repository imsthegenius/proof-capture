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

        // 3. Ankle confidence gate (TWO-515): when ankles are not detected,
        //    skeleton height covers head-to-hips only (~55% of standing height).
        //    Inflate the assessment rect to estimate full body height so the
        //    distance thresholds don't produce false "Move closer" feedback.
        let leftAnkleConf = (try? observation.recognizedPoint(.leftAnkle))?.confidence ?? 0
        let rightAnkleConf = (try? observation.recognizedPoint(.rightAnkle))?.confidence ?? 0
        let anklesDetected = leftAnkleConf > 0.3 || rightAnkleConf > 0.3

        let assessmentRect: CGRect
        if !anklesDetected && rect.height > 0 {
            let estimatedFullHeight = min(rect.height / 0.55, 1.0)
            assessmentRect = CGRect(
                x: rect.origin.x,
                y: max(0, rect.origin.y - (estimatedFullHeight - rect.height)),
                width: rect.width,
                height: estimatedFullHeight
            )
        } else {
            assessmentRect = rect
        }

        // 4. Position assessment
        let positionResult = assessPosition(rect: assessmentRect)

        // 5. Orientation detection
        let orientation = detectOrientation(from: observation)

        // 6. Pose match (read from cache to avoid main actor hop)
        let poseMatch = (orientation == _targetPoseCache)

        // 7. Arms check
        let arms = checkArmsRelaxed(from: observation)

        // 8. Composite readiness
        let ready = positionResult.quality == .good && poseMatch && arms

        // 9. Build feedback string (priority order)
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
    //
    // CALIBRATION NOTES (2026-04-04, TWO-478 TWO-515)
    // ─────────────────────────────────────────────────────────
    // Baseline distance heuristics originally came from the legacy static suite,
    // now tracked as validation-only edge cases in scripts/edge-cases/.
    // Target setup: phone propped at waist-to-chest height, user 6-8 ft away.
    //
    // Observed body heights (Vision normalized skeleton span):
    //   Correctly framed at 6 ft: 0.45–0.65
    //   Correctly framed at 8 ft: 0.35–0.50
    //   Distant / partial detection: 0.10–0.28
    //   Too close (< 4 ft): 0.80+
    //
    // Threshold changes:
    //   "Too close" raised 0.80 → 0.85 — at 0.80 a shorter person at 5 ft
    //   is incorrectly flagged.
    //   "Too far" lowered 0.35 → 0.25 — the old 0.35 false-triggered on
    //   correctly-framed users when ankle confidence was low.
    //   Added tip range 0.25–0.40 → FAIR "Step a bit closer" instead of
    //   hard POOR cutoff (TWO-478).
    //
    // Ankle confidence gate (applied upstream in analyze()):
    //   When ankles are not detected (conf < 0.3), skeleton height only
    //   covers head-to-hips (~55% of standing height). analyze() inflates
    //   the rect before passing it here. Prevents false "Move closer"
    //   when feet are occluded or low-confidence (TWO-515).
    // ─────────────────────────────────────────────────────────

    private struct PositionResult {
        let quality: QualityLevel
        let feedback: String
    }

    nonisolated private func assessPosition(rect: CGRect) -> PositionResult {
        let centerX = rect.midX
        let bodyHeight = rect.height
        var issues: [String] = []

        // Distance (body height in normalized coords)
        if bodyHeight > 0.85 {
            issues.append("Step back")
        } else if bodyHeight < 0.25 {
            issues.append("Move closer")
        } else if bodyHeight < 0.40 {
            issues.append("Step a bit closer for best framing")
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
    //
    // CALIBRATION NOTES (2026-04-04, TWO-476 TWO-517)
    // ─────────────────────────────────────────────────────────
    // Baseline orientation heuristics originally came from the legacy static
    // suite, now tracked as validation-only edge cases in scripts/edge-cases/.
    //
    // Front detection:
    //   noseConf threshold lowered 0.30 → 0.15 for primary path.
    //   Low-light fallback: noseConf ≥ 0.10 defaults to front when no
    //   side/back signals are present. Fixes TWO-476 (05_very_dim.jpg
    //   and dramatic-side.jpg had noseConf ~0.2 → fell through to unknown).
    //   In a guided photo booth the user is overwhelmingly likely facing
    //   the camera; without positive side/back evidence, front is safest.
    //   Hip-width fallback added for when shoulder confidence < 0.4.
    //
    // Side detection:
    //   Hip-width added as parallel confirmation signal (TWO-517).
    //   Shoulder-width side threshold raised 0.15 → 0.20 when combined
    //   with ear asymmetry or hip compression.
    //   Shoulder confidence floor kept at 0.3 — raising to 0.4 caused
    //   side_stage_good.jpg regression (shoulderWidth collapsed to 0).
    //
    // Back detection:
    //   noseConf < 0.10 unchanged — working correctly across test set.
    //
    // Observed values (normalized x-distance at 6-8 ft):
    //   Shoulder width, front: 0.25–0.42
    //   Shoulder width, side:  0.04–0.15
    //   Hip width tracks ~0.80× shoulder in the same orientation.
    // ─────────────────────────────────────────────────────────

    nonisolated private func detectOrientation(from observation: VNHumanBodyPoseObservation) -> Pose? {
        let nose = try? observation.recognizedPoint(.nose)
        let leftEar = try? observation.recognizedPoint(.leftEar)
        let rightEar = try? observation.recognizedPoint(.rightEar)
        let leftShoulder = try? observation.recognizedPoint(.leftShoulder)
        let rightShoulder = try? observation.recognizedPoint(.rightShoulder)
        let leftHip = try? observation.recognizedPoint(.leftHip)
        let rightHip = try? observation.recognizedPoint(.rightHip)

        let noseConf = nose?.confidence ?? 0
        let leftEarConf = leftEar?.confidence ?? 0
        let rightEarConf = rightEar?.confidence ?? 0
        let leftShoulderConf = leftShoulder?.confidence ?? 0
        let rightShoulderConf = rightShoulder?.confidence ?? 0
        let leftHipConf = leftHip?.confidence ?? 0
        let rightHipConf = rightHip?.confidence ?? 0

        // Shoulder width — both shoulders must be detected with confidence
        let shoulderWidth: CGFloat = {
            guard leftShoulderConf > 0.3, rightShoulderConf > 0.3,
                  let ls = leftShoulder, let rs = rightShoulder else { return 0 }
            return abs(ls.location.x - rs.location.x)
        }()

        // Hip width — parallel signal for side detection (TWO-517)
        let hipWidth: CGFloat = {
            guard leftHipConf > 0.3, rightHipConf > 0.3,
                  let lh = leftHip, let rh = rightHip else { return 0 }
            return abs(lh.location.x - rh.location.x)
        }()

        // BACK: nose not visible at all
        if noseConf < 0.1 {
            return .back
        }

        // SIDE: multiple signals — any one sufficient
        let earAsymmetry = abs(leftEarConf - rightEarConf)

        // Ear asymmetry + compressed shoulders (threshold 0.20, was 0.15)
        if earAsymmetry > 0.3 && shoulderWidth > 0 && shoulderWidth < 0.20 {
            return .side
        }

        // Both shoulders AND hips compressed (no ear signal needed)
        if shoulderWidth > 0 && shoulderWidth < 0.20 && hipWidth > 0 && hipWidth < 0.12 {
            return .side
        }

        // Only one shoulder visible with confidence
        if (leftShoulderConf > 0.3) != (rightShoulderConf > 0.3) {
            return .side
        }

        // FRONT: nose visible + shoulders spread (primary path)
        if noseConf > 0.15 && shoulderWidth > 0.10 {
            return .front
        }

        // FRONT: nose visible + hips spread (fallback when shoulders not measurable)
        if noseConf > 0.15 && hipWidth > 0.10 {
            return .front
        }

        // LOW-LIGHT FALLBACK (TWO-476): nose partially visible (≥ 0.1), no side
        // or back signals detected. In a guided photo booth, default to front.
        if noseConf >= 0.1 {
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

        // Wrist below hip but not at knee level (Y within 20% of frame).
        // Natural hanging arms place wrists around mid-thigh; wider deltas
        // usually indicate raised, crossed, or braced arms.
        let leftYOK = abs(leftWrist.location.y - leftHip.location.y) < 0.20
        let rightYOK = abs(rightWrist.location.y - rightHip.location.y) < 0.20

        // Wrist horizontally near hip (X within 18% of frame). Larger offsets
        // usually indicate hands on hips or outward arm tension.
        let leftXOK = abs(leftWrist.location.x - leftHip.location.x) < 0.18
        let rightXOK = abs(rightWrist.location.x - rightHip.location.x) < 0.18

        // Elbow angle — relaxed arms are 130-180°, flexed arms are 80-110°.
        // Old 150° floor failed natural slight bends (130-150° is common).
        // 120° catches true flexion while passing natural stance.
        if let leftElbow = try? observation.recognizedPoint(.leftElbow),
           let leftShoulder = try? observation.recognizedPoint(.leftShoulder),
           leftElbow.confidence > 0.3, leftShoulder.confidence > 0.3 {
            let angle = angleBetween(
                p1: leftShoulder.location, vertex: leftElbow.location, p2: leftWrist.location
            )
            if angle < 120 { return false }
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

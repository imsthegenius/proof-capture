#if canImport(UIKit)
import UIKit
#endif
import CoreImage
import Vision

/// Unified scorer that produces a `CheckInVisualAssessment` for both
/// live camera frames and captured images. Uses the same pose/orientation/
/// lighting heuristics in both modes; only sharpness differs.
enum CheckInScorer {

    // MARK: - Live assessment (from PoseDetector + LightingAnalyzer state)

    struct LiveInputs: Sendable {
        let bodyDetected: Bool
        let positionQuality: QualityLevel
        let poseMatchesExpected: Bool
        let armsRelaxed: Bool
        let detectedOrientation: Pose?
        let targetPose: Pose
        let bodyHeight: Double          // Normalized skeleton height [0, 1]
        let bodyCenterX: Double         // Normalized center X [0, 1]

        // Lighting measurements (from LightingAnalyzer pipeline)
        let lightingQuality: QualityLevel
        let brightness: Double
        let directionalityGradient: Double
        let definitionContrast: Double
        let isBacklit: Bool
    }

    static func assessLive(_ inputs: LiveInputs) -> CheckInVisualAssessment {
        var tags: [CheckInVisualAssessment.ReasonTag] = []
        var primaryReason = "Hold still"

        // --- Body detection ---
        guard inputs.bodyDetected else {
            return CheckInVisualAssessment.compute(
                subScores: .init(definitionLighting: 0, framing: 0, poseAccuracy: 0, poseNeutrality: 0, sharpness: nil),
                reasonTags: [.bodyNotDetected],
                mode: .live,
                primaryReason: "Step into the frame"
            )
        }

        // --- Lighting sub-score (definition-first) ---
        let lightingScore = computeDefinitionLightingScore(
            brightness: inputs.brightness,
            gradient: inputs.directionalityGradient,
            contrast: inputs.definitionContrast,
            isBacklit: inputs.isBacklit,
            tags: &tags
        )

        // --- Framing sub-score ---
        let framingScore = computeLiveFramingScore(
            bodyHeight: inputs.bodyHeight,
            bodyCenterX: inputs.bodyCenterX,
            positionQuality: inputs.positionQuality,
            tags: &tags
        )

        // --- Pose accuracy sub-score ---
        let poseAccuracyScore = computePoseAccuracyScore(
            poseMatches: inputs.poseMatchesExpected,
            detected: inputs.detectedOrientation,
            target: inputs.targetPose,
            tags: &tags
        )

        // --- Pose neutrality sub-score ---
        let poseNeutralityScore = computePoseNeutralityScore(
            armsRelaxed: inputs.armsRelaxed,
            tags: &tags
        )

        // --- Primary reason (top failing reason) ---
        primaryReason = pickPrimaryReason(tags: tags, fallback: "Perfect — hold still")

        let subScores = CheckInVisualAssessment.SubScores(
            definitionLighting: lightingScore,
            framing: framingScore,
            poseAccuracy: poseAccuracyScore,
            poseNeutrality: poseNeutralityScore,
            sharpness: nil
        )

        return CheckInVisualAssessment.compute(
            subScores: subScores,
            reasonTags: tags,
            mode: .live,
            primaryReason: primaryReason
        )
    }

    // MARK: - Captured assessment

    #if canImport(UIKit)
    /// Convenience entry point for the iOS app (UIImage → CGImage extraction).
    static func assessCaptured(image: UIImage, pose: Pose) async -> CheckInVisualAssessment {
        guard let cgImage = image.cgImage else {
            return CheckInVisualAssessment.compute(
                subScores: .init(definitionLighting: 0, framing: 0, poseAccuracy: 0, poseNeutrality: 0, sharpness: 0),
                reasonTags: [.bodyNotDetected],
                mode: .captured,
                primaryReason: "Could not read image"
            )
        }
        return await assessCaptured(cgImage: cgImage, pose: pose)
    }
    #endif

    /// Core captured assessment — works on any platform with Vision + CoreImage.
    static func assessCaptured(cgImage: CGImage, pose: Pose) async -> CheckInVisualAssessment {
        var tags: [CheckInVisualAssessment.ReasonTag] = []

        let ciImage = CIImage(cgImage: cgImage)
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])

        // --- Body pose analysis ---
        let bodyAnalysis = await analyzeBody(cgImage: cgImage, pose: pose, tags: &tags)

        // --- Lighting analysis (person-segmented) ---
        let lightingResult = await analyzeCapturedLighting(
            cgImage: cgImage,
            ciImage: ciImage,
            ciContext: ciContext,
            tags: &tags
        )

        // --- Sharpness ---
        let sharpnessScore = computeSharpnessScore(cgImage: cgImage, tags: &tags)

        let primaryReason = pickPrimaryReason(tags: tags, fallback: "Good check-in photo")

        let subScores = CheckInVisualAssessment.SubScores(
            definitionLighting: lightingResult,
            framing: bodyAnalysis.framingScore,
            poseAccuracy: bodyAnalysis.poseScore,
            poseNeutrality: bodyAnalysis.neutralityScore,
            sharpness: sharpnessScore
        )

        return CheckInVisualAssessment.compute(
            subScores: subScores,
            reasonTags: tags,
            mode: .captured,
            primaryReason: primaryReason
        )
    }

    // MARK: - Shared sub-score: Definition Lighting

    private static func computeDefinitionLightingScore(
        brightness: Double,
        gradient: Double,
        contrast: Double,
        isBacklit: Bool,
        tags: inout [CheckInVisualAssessment.ReasonTag]
    ) -> Double {
        // Catastrophic: severe backlight
        if isBacklit {
            tags.append(.severeBacklight)
            return 0.0
        }

        // Exposure bands
        var exposureScore: Double
        if brightness < 0.10 {
            tags.append(.tooDark)
            exposureScore = 0.0
        } else if brightness < 0.15 {
            tags.append(.tooDark)
            exposureScore = 0.2
        } else if brightness > 0.82 {
            tags.append(.tooBright)
            exposureScore = 0.1
        } else if brightness > 0.72 {
            exposureScore = 0.7
        } else if brightness < 0.25 {
            exposureScore = 0.5
        } else {
            exposureScore = 1.0
        }

        // Definition (shadow contrast) — this is the primary signal.
        // TWO-946 pass 3 (2026-04-23): shadow-contrast band tightened from (0.05 → 0.35) to
        // (0.02 → 0.20). Empirical distribution on the 63-row tuning-holdout has most coach-
        // accepted frames at contrast 0.05–0.20, with very few above 0.25. The wider band
        // floored most real-world frames at def_lighting ≤ 0.3 (→ overall < 0.75 → verdict=warn)
        // even when the coach marked `keep`. Constants-only change; `flatLighting` / `weakDefinition`
        // tag thresholds unchanged (informational tags, not verdict inputs).
        let definitionNormalized = clamp((contrast - 0.02) / (0.20 - 0.02))
        if contrast < 0.08 {
            tags.append(.flatLighting)
        } else if contrast < 0.18 {
            tags.append(.weakDefinition)
        }

        // Directionality (downlighting gradient)
        let directionalityNormalized = clamp((gradient - 0.01) / (0.08 - 0.01))

        // Backlight penalty (mild)
        // Note: severe backlight already handled above via isBacklit flag

        // Composite: definition is king, then directionality, then exposure
        // Weight: 50% definition, 25% directionality, 25% exposure
        let score = 0.50 * definitionNormalized + 0.25 * directionalityNormalized + 0.25 * exposureScore
        return clamp(score)
    }

    // MARK: - Live framing sub-score

    private static func computeLiveFramingScore(
        bodyHeight: Double,
        bodyCenterX: Double,
        positionQuality: QualityLevel,
        tags: inout [CheckInVisualAssessment.ReasonTag]
    ) -> Double {
        var score: Double = 1.0

        // Distance
        if bodyHeight > 0.85 {
            tags.append(.tooClose)
            score -= 0.5
        } else if bodyHeight < 0.25 {
            tags.append(.tooFar)
            score -= 0.5
        } else if bodyHeight < 0.40 {
            score -= 0.15  // Marginal — step closer
        }

        // Centering
        if bodyCenterX < 0.35 || bodyCenterX > 0.65 {
            tags.append(.offCenter)
            score -= 0.3
        } else if bodyCenterX < 0.40 || bodyCenterX > 0.60 {
            score -= 0.1  // Slight offset
        }

        return clamp(score)
    }

    // MARK: - Pose accuracy sub-score

    private static func computePoseAccuracyScore(
        poseMatches: Bool,
        detected: Pose?,
        target: Pose,
        tags: inout [CheckInVisualAssessment.ReasonTag]
    ) -> Double {
        if poseMatches {
            return 1.0
        }

        if let detected, detected != target {
            tags.append(.wrongPose)
            return 0.0
        }

        // Orientation unclear
        tags.append(.poseUnclear)
        return 0.35
    }

    // MARK: - Pose neutrality sub-score

    private static func computePoseNeutralityScore(
        armsRelaxed: Bool,
        tags: inout [CheckInVisualAssessment.ReasonTag]
    ) -> Double {
        if armsRelaxed {
            return 1.0
        }
        tags.append(.stagedPose)
        return 0.4
    }

    // MARK: - Captured body analysis

    private struct BodyAnalysis {
        let framingScore: Double
        let poseScore: Double
        let neutralityScore: Double
    }

    private static func analyzeBody(
        cgImage: CGImage,
        pose: Pose,
        tags: inout [CheckInVisualAssessment.ReasonTag]
    ) async -> BodyAnalysis {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)

        do {
            try handler.perform([request])
        } catch {
            tags.append(.bodyNotDetected)
            return BodyAnalysis(framingScore: 0, poseScore: 0, neutralityScore: 0.5)
        }

        guard let body = request.results?.first else {
            tags.append(.bodyNotDetected)
            return BodyAnalysis(framingScore: 0, poseScore: 0, neutralityScore: 0.5)
        }

        // --- Framing ---
        var framingScore: Double = 1.0

        let noseConf = (try? body.recognizedPoint(.nose))?.confidence ?? 0
        let neckConf = (try? body.recognizedPoint(.neck))?.confidence ?? 0
        let leftEarConf = (try? body.recognizedPoint(.leftEar))?.confidence ?? 0
        let rightEarConf = (try? body.recognizedPoint(.rightEar))?.confidence ?? 0
        let leftAnkleConf = (try? body.recognizedPoint(.leftAnkle))?.confidence ?? 0
        let rightAnkleConf = (try? body.recognizedPoint(.rightAnkle))?.confidence ?? 0

        // For back pose, nose is expected to be invisible — use neck/ears as head proxy
        let hasHead: Bool
        if pose == .back {
            hasHead = neckConf > 0.1 || leftEarConf > 0.1 || rightEarConf > 0.1
        } else {
            hasHead = noseConf > 0.1
        }
        let hasFeet = leftAnkleConf > 0.1 || rightAnkleConf > 0.1

        if !hasHead && !hasFeet {
            tags.append(.severeCrop)
            framingScore = 0.0
        } else if !hasHead {
            tags.append(.headMissing)
            framingScore -= 0.4
        } else if !hasFeet {
            tags.append(.feetMissing)
            framingScore -= 0.3
        }

        // Centering and distance from visible joints
        let trackingJoints: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .neck, .leftShoulder, .rightShoulder,
            .leftHip, .rightHip, .leftAnkle, .rightAnkle
        ]
        var points: [CGPoint] = []
        for joint in trackingJoints {
            if let pt = try? body.recognizedPoint(joint), pt.confidence > 0.3 {
                points.append(pt.location)
            }
        }

        if points.count >= 3 {
            let xs = points.map(\.x)
            let ys = points.map(\.y)
            let bodyHeight = (ys.max()! - ys.min()!)
            let centerX = (xs.min()! + xs.max()!) / 2.0

            if bodyHeight > 0.85 {
                tags.append(.tooClose)
                framingScore -= 0.2
            } else if bodyHeight < 0.25 {
                tags.append(.tooFar)
                framingScore -= 0.3
            }

            if centerX < 0.35 || centerX > 0.65 {
                tags.append(.offCenter)
                framingScore -= 0.2
            }
        }

        // --- Pose accuracy ---
        let orientation = detectCapturedOrientation(body: body)
        var poseScore: Double
        if orientation == pose {
            poseScore = 1.0
        } else if orientation == nil {
            tags.append(.poseUnclear)
            poseScore = 0.35
        } else {
            tags.append(.wrongPose)
            poseScore = 0.0
        }

        // --- Neutrality (staged pose detection) ---
        var neutralityScore: Double = 1.0
        let armsRelaxed = checkCapturedArmsRelaxed(body: body)
        if !armsRelaxed {
            tags.append(.stagedPose)
            neutralityScore = 0.4
        }

        return BodyAnalysis(
            framingScore: clamp(framingScore),
            poseScore: poseScore,
            neutralityScore: neutralityScore
        )
    }

    // MARK: - Captured lighting analysis

    private static func analyzeCapturedLighting(
        cgImage: CGImage,
        ciImage: CIImage,
        ciContext: CIContext,
        tags: inout [CheckInVisualAssessment.ReasonTag]
    ) async -> Double {
        let extent = ciImage.extent

        // Person segmentation
        let segRequest = VNGeneratePersonSegmentationRequest()
        segRequest.qualityLevel = .balanced
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)

        do {
            try handler.perform([segRequest])
        } catch {
            return 0.5 // Fallback
        }

        guard let segResult = segRequest.results?.first else {
            return 0.5
        }

        let maskImage = CIImage(cvPixelBuffer: segResult.pixelBuffer)
        let scaledMask = maskImage.transformed(by: CGAffineTransform(
            scaleX: extent.width / maskImage.extent.width,
            y: extent.height / maskImage.extent.height
        ))

        let black = CIImage(color: .black).cropped(to: extent)
        let personImage = ciImage.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: black,
            kCIInputMaskImageKey: scaledMask
        ])

        // Person brightness
        let coverage = rawBrightness(of: scaledMask, in: extent, context: ciContext)
        guard coverage > 0.02 else { return 0.5 }
        let personBrightness = min(rawBrightness(of: personImage, in: extent, context: ciContext) / coverage, 1.0)

        // Background brightness (backlight detection)
        let invertedMask = scaledMask.applyingFilter("CIColorInvert")
        let bgImage = ciImage.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: black,
            kCIInputMaskImageKey: invertedMask
        ])
        let bgBrightness = rawBrightness(of: bgImage, in: extent, context: ciContext)
        let bgCoverage = rawBrightness(of: invertedMask, in: extent, context: ciContext)
        let normalizedBgBrightness = bgCoverage > 0.02 ? min(bgBrightness / bgCoverage, 1.0) : 0.5
        // TWO-946 pass 2 (2026-04-23): raised catastrophic-backlight delta from 0.25 → 0.40.
        // At 0.25 the gate fired on 5 of 7 post-pass-1 catastrophic rejects where the coach
        // marked the frame `keep`. `severeBacklight` is an `isCatastrophicCaptured` tag, so
        // a single false trigger forces `retakeRecommended` regardless of the weighted score.
        // Constants-only change: the `+0.40` is the brightness-delta cutoff, not a category shift.
        let isBacklit = normalizedBgBrightness > personBrightness + 0.40

        // Downlighting gradient (upper half vs lower half of person)
        let midY = extent.midY
        let upperRect = CGRect(x: 0, y: midY, width: extent.width, height: extent.height - midY)
        let lowerRect = CGRect(x: 0, y: 0, width: extent.width, height: midY)

        let upperCov = rawBrightness(of: scaledMask, in: upperRect, context: ciContext)
        let lowerCov = rawBrightness(of: scaledMask, in: lowerRect, context: ciContext)
        var gradient: Double = 0
        if upperCov > 0.02, lowerCov > 0.02 {
            let upperBright = min(rawBrightness(of: personImage, in: upperRect, context: ciContext) / upperCov, 1.0)
            let lowerBright = min(rawBrightness(of: personImage, in: lowerRect, context: ciContext) / lowerCov, 1.0)
            gradient = upperBright - lowerBright
        }

        // Shadow contrast (quadrant variance)
        let midX = extent.midX
        let quadrants = [
            CGRect(x: 0, y: midY, width: midX, height: extent.height - midY),
            CGRect(x: midX, y: midY, width: extent.width - midX, height: extent.height - midY),
            CGRect(x: 0, y: 0, width: midX, height: midY),
            CGRect(x: midX, y: 0, width: extent.width - midX, height: midY)
        ]

        let values = quadrants.compactMap { rect -> Double? in
            let cov = rawBrightness(of: scaledMask, in: rect, context: ciContext)
            guard cov > 0.04 else { return nil }
            return min(rawBrightness(of: personImage, in: rect, context: ciContext) / cov, 1.0)
        }

        var contrast: Double = 0
        if values.count >= 3 {
            let mean = values.reduce(0, +) / Double(values.count)
            let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
            contrast = min(variance / 0.02, 1.0)
        }

        return computeDefinitionLightingScore(
            brightness: personBrightness,
            gradient: gradient,
            contrast: contrast,
            isBacklit: isBacklit,
            tags: &tags
        )
    }

    // MARK: - Sharpness sub-score

    private static func computeSharpnessScore(
        cgImage: CGImage,
        tags: inout [CheckInVisualAssessment.ReasonTag]
    ) -> Double {
        let ciImage = CIImage(cgImage: cgImage)

        let context = CIContext(options: [.useSoftwareRenderer: false])

        // Analyze center 60% of the image
        let extent = ciImage.extent
        let insetX = extent.width * 0.2
        let insetY = extent.height * 0.2
        let centerRect = extent.insetBy(dx: insetX, dy: insetY)
        let cropped = ciImage.cropped(to: centerRect)

        let weights: [CGFloat] = [-1, -1, -1, -1, 8, -1, -1, -1, -1]
        let weightVector = CIVector(values: weights, count: 9)

        guard let convolution = CIFilter(
            name: "CIConvolution3X3",
            parameters: [
                kCIInputImageKey: cropped,
                "inputWeights": weightVector,
                "inputBias": 0.0
            ]
        ),
        let outputImage = convolution.outputImage else {
            return 0
        }

        let outputExtent = outputImage.extent
        guard let avgFilter = CIFilter(
            name: "CIAreaAverage",
            parameters: [
                kCIInputImageKey: outputImage,
                kCIInputExtentKey: CIVector(
                    x: outputExtent.origin.x,
                    y: outputExtent.origin.y,
                    z: outputExtent.size.width,
                    w: outputExtent.size.height
                )
            ]
        ),
        let avgOutput = avgFilter.outputImage else {
            return 0
        }

        var pixel = [Float](repeating: 0, count: 4)
        context.render(
            avgOutput,
            toBitmap: &pixel,
            rowBytes: 16,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBAf,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let rawVariance = Double(abs(0.299 * pixel[0] + 0.587 * pixel[1] + 0.114 * pixel[2]))

        // Normalize: 0.03 maps to 1.0
        let normalized = clamp(rawVariance / 0.03)

        // TWO-946 pass 1 (2026-04-23): severeBlur disabled via `-1` sentinel.
        // Root cause: Laplacian kernel [-1,-1,-1,-1,8,-1,-1,-1,-1] sums to 0; CIAreaAverage
        // of a zero-sum convolution is ≈0 by construction. `rawVariance` here is actually the
        // mean of the Laplacian output, not variance — so it's ≈0 on every image regardless of
        // sharpness, and the 0.008 cutoff triggered severeBlur on 100% of real-world frames.
        // Threshold moved to a sentinel that cannot fire; mildBlur left alone (informational only,
        // not catastrophic). Algorithmic fix (real variance computation) tracked separately.
        if rawVariance < -1 {
            tags.append(.severeBlur)
        } else if rawVariance < 0.015 {
            tags.append(.mildBlur)
        }

        return normalized
    }

    // MARK: - Captured orientation detection (mirrors PoseDetector logic)

    private static func detectCapturedOrientation(body: VNHumanBodyPoseObservation) -> Pose? {
        let nose = try? body.recognizedPoint(.nose)
        let leftEar = try? body.recognizedPoint(.leftEar)
        let rightEar = try? body.recognizedPoint(.rightEar)
        let leftShoulder = try? body.recognizedPoint(.leftShoulder)
        let rightShoulder = try? body.recognizedPoint(.rightShoulder)
        let leftHip = try? body.recognizedPoint(.leftHip)
        let rightHip = try? body.recognizedPoint(.rightHip)

        let noseConf = nose?.confidence ?? 0
        let leftEarConf = leftEar?.confidence ?? 0
        let rightEarConf = rightEar?.confidence ?? 0
        let leftShoulderConf = leftShoulder?.confidence ?? 0
        let rightShoulderConf = rightShoulder?.confidence ?? 0
        let leftHipConf = leftHip?.confidence ?? 0
        let rightHipConf = rightHip?.confidence ?? 0

        let shoulderWidth: CGFloat = {
            guard leftShoulderConf > 0.3, rightShoulderConf > 0.3,
                  let ls = leftShoulder, let rs = rightShoulder else { return 0 }
            return abs(ls.location.x - rs.location.x)
        }()

        let hipWidth: CGFloat = {
            guard leftHipConf > 0.3, rightHipConf > 0.3,
                  let lh = leftHip, let rh = rightHip else { return 0 }
            return abs(lh.location.x - rh.location.x)
        }()

        if noseConf < 0.1 { return .back }

        let earAsymmetry = abs(leftEarConf - rightEarConf)
        if earAsymmetry > 0.3 && shoulderWidth > 0 && shoulderWidth < 0.20 { return .side }
        if shoulderWidth > 0 && shoulderWidth < 0.20 && hipWidth > 0 && hipWidth < 0.12 { return .side }
        if (leftShoulderConf > 0.3) != (rightShoulderConf > 0.3) { return .side }
        if noseConf > 0.15 && shoulderWidth > 0.10 { return .front }
        if noseConf > 0.15 && hipWidth > 0.10 { return .front }
        if noseConf >= 0.1 { return .front }

        return nil
    }

    // MARK: - Captured arms relaxed check (mirrors PoseDetector logic)

    private static func checkCapturedArmsRelaxed(body: VNHumanBodyPoseObservation) -> Bool {
        guard let leftWrist = try? body.recognizedPoint(.leftWrist),
              let rightWrist = try? body.recognizedPoint(.rightWrist),
              let leftHip = try? body.recognizedPoint(.leftHip),
              let rightHip = try? body.recognizedPoint(.rightHip),
              leftWrist.confidence > 0.3, rightWrist.confidence > 0.3,
              leftHip.confidence > 0.3, rightHip.confidence > 0.3 else {
            return true  // Can't see wrists = probably back pose
        }

        let leftYOK = abs(leftWrist.location.y - leftHip.location.y) < 0.08
        let rightYOK = abs(rightWrist.location.y - rightHip.location.y) < 0.08
        let leftXOK = abs(leftWrist.location.x - leftHip.location.x) < 0.06
        let rightXOK = abs(rightWrist.location.x - rightHip.location.x) < 0.06

        if let leftElbow = try? body.recognizedPoint(.leftElbow),
           let leftShoulder = try? body.recognizedPoint(.leftShoulder),
           leftElbow.confidence > 0.3, leftShoulder.confidence > 0.3 {
            let v1 = CGPoint(x: leftShoulder.location.x - leftElbow.location.x,
                             y: leftShoulder.location.y - leftElbow.location.y)
            let v2 = CGPoint(x: leftWrist.location.x - leftElbow.location.x,
                             y: leftWrist.location.y - leftElbow.location.y)
            let dot = v1.x * v2.x + v1.y * v2.y
            let mag1 = sqrt(v1.x * v1.x + v1.y * v1.y)
            let mag2 = sqrt(v2.x * v2.x + v2.y * v2.y)
            if mag1 > 0, mag2 > 0 {
                let angle = acos(min(max(dot / (mag1 * mag2), -1), 1)) * 180 / .pi
                if angle < 150 { return false }
            }
        }

        return leftYOK && rightYOK && leftXOK && rightXOK
    }

    // MARK: - Primary reason selection

    /// Severity priority — catastrophic tags always win over medium/low tags,
    /// regardless of the order they were appended during analysis.
    private static let severityOrder: [CheckInVisualAssessment.ReasonTag] = [
        // Catastrophic
        .bodyNotDetected, .wrongPose, .severeCrop, .severeBacklight, .severeBlur,
        // High
        .tooDark, .tooBright, .headMissing, .feetMissing,
        // Medium
        .tooClose, .tooFar, .offCenter,
        .flatLighting, .weakDefinition, .mildBacklight,
        .stagedPose, .poseUnclear,
        // Low
        .mildBlur,
    ]

    private static func pickPrimaryReason(
        tags: [CheckInVisualAssessment.ReasonTag],
        fallback: String
    ) -> String {
        guard let top = severityOrder.first(where: { tags.contains($0) }) else {
            return fallback
        }

        switch top {
        case .bodyNotDetected: return "Step into the frame"
        case .wrongPose: return "Wrong pose — check your position"
        case .severeCrop: return "Head and feet not visible"
        case .severeBacklight: return "Strong light behind you — try a different angle"
        case .severeBlur: return "Too blurry — hold still"
        case .headMissing: return "Head not in frame"
        case .feetMissing: return "Feet not in frame"
        case .tooClose: return "Step back"
        case .tooFar: return "Move closer"
        case .offCenter: return "Center yourself in frame"
        case .flatLighting: return "Flat lighting — stand under an overhead light"
        case .weakDefinition: return "Try standing directly under an overhead light"
        case .mildBacklight: return "Mild backlight — adjust your angle"
        case .tooDark: return "Too dark — turn on more lights"
        case .tooBright: return "Too bright — move away from the light"
        case .stagedPose: return "Relax your arms at your sides"
        case .poseUnclear: return "Adjust your position"
        case .mildBlur: return "Slight blur detected"
        }
    }

    // MARK: - Core Image helper

    private static func rawBrightness(of image: CIImage, in rect: CGRect, context: CIContext) -> Double {
        let cropped = image.cropped(to: rect)
        guard let avgFilter = CIFilter(
            name: "CIAreaAverage",
            parameters: [
                kCIInputImageKey: cropped,
                kCIInputExtentKey: CIVector(
                    x: rect.origin.x,
                    y: rect.origin.y,
                    z: rect.size.width,
                    w: rect.size.height
                )
            ]
        ),
        let output = avgFilter.outputImage else {
            return 0.5
        }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let r = Double(pixel[0]) / 255.0
        let g = Double(pixel[1]) / 255.0
        let b = Double(pixel[2]) / 255.0
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

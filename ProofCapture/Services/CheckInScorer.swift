#if canImport(UIKit)
import UIKit
#endif
import CoreGraphics
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
        let sharpnessAnalysis = computeSharpnessScore(cgImage: cgImage, tags: &tags)

        let primaryReason = pickCapturedPrimaryReason(tags: tags, fallback: "Good check-in photo")

        let subScores = CheckInVisualAssessment.SubScores(
            definitionLighting: lightingResult,
            framing: bodyAnalysis.framingScore,
            poseAccuracy: bodyAnalysis.poseScore,
            poseNeutrality: bodyAnalysis.neutralityScore,
            sharpness: sharpnessAnalysis.score
        )

        return CheckInVisualAssessment.compute(
            subScores: subScores,
            reasonTags: tags,
            mode: .captured,
            primaryReason: primaryReason,
            diagnostics: .init(
                rawSharpnessVariance: sharpnessAnalysis.rawVariance,
                orientationConfidence: bodyAnalysis.orientationConfidence,
                orientationMargin: bodyAnalysis.orientationMargin
            )
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
        // TWO-970 retune (2026-04-24): shadow-contrast band tightened to contrast / 0.08.
        // Empirical distribution on the 63-row tuning-holdout has most coach-
        // accepted frames at contrast 0.05–0.20, with very few above 0.25. The wider band
        // floored most real-world frames at def_lighting ≤ 0.3 (→ overall < 0.75 → verdict=warn)
        // even when the coach marked `keep`. Constants-only change; `flatLighting` / `weakDefinition`
        // tag thresholds unchanged (informational tags, not verdict inputs).
        let definitionNormalized = clamp(contrast / 0.08)
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
        let orientationConfidence: Double?
        let orientationMargin: Double?
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
            return BodyAnalysis(
                framingScore: 0,
                poseScore: 0,
                neutralityScore: 0.5,
                orientationConfidence: nil,
                orientationMargin: nil
            )
        }

        guard let body = request.results?.first else {
            tags.append(.bodyNotDetected)
            return BodyAnalysis(
                framingScore: 0,
                poseScore: 0,
                neutralityScore: 0.5,
                orientationConfidence: nil,
                orientationMargin: nil
            )
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
        let poseScore = computeCapturedPoseAccuracyScore(
            expected: pose,
            orientation: orientation,
            tags: &tags
        )

        // --- Neutrality (staged pose detection) ---
        let armsRelaxed = checkCapturedArmsRelaxed(body: body)
        let neutralityScore = computeCapturedNeutralityScore(armsRelaxed: armsRelaxed, tags: &tags)

        return BodyAnalysis(
            framingScore: clamp(framingScore),
            poseScore: poseScore,
            neutralityScore: neutralityScore,
            orientationConfidence: orientation.confidence,
            orientationMargin: orientation.margin
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
        // TWO-970 retune (2026-04-24): raised catastrophic-backlight delta to 0.45.
        // At 0.25 the gate fired on 5 of 7 post-pass-1 catastrophic rejects where the coach
        // marked the frame `keep`. `severeBacklight` is an `isCatastrophicCaptured` tag, so
        // a single false trigger forces `retakeRecommended` regardless of the weighted score.
        // Constants-only change: the `+0.45` is the brightness-delta cutoff, not a category shift.
        let isBacklit = normalizedBgBrightness > personBrightness + 0.45

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

    struct SharpnessAnalysis: Sendable {
        let rawVariance: Double
        let score: Double
    }

    private static let sharpnessCropFraction: Double = 0.60
    private static let sharpnessMaxDimension: Int = 512
    private static let sharpnessNormalizationCeiling: Double = 3_000
    private static let severeBlurVarianceThreshold: Double = 12
    private static let mildBlurVarianceThreshold: Double = 150

    static func computeSharpnessScore(
        cgImage: CGImage,
        tags: inout [CheckInVisualAssessment.ReasonTag]
    ) -> SharpnessAnalysis {
        let rawVariance = rawSharpnessVariance(cgImage: cgImage)
        let score = clamp(rawVariance / sharpnessNormalizationCeiling)

        if rawVariance < severeBlurVarianceThreshold {
            tags.append(.severeBlur)
        } else if rawVariance < mildBlurVarianceThreshold {
            tags.append(.mildBlur)
        }

        return SharpnessAnalysis(rawVariance: rawVariance, score: score)
    }

    private static func rawSharpnessVariance(cgImage: CGImage) -> Double {
        let width = cgImage.width
        let height = cgImage.height
        guard width >= 3, height >= 3 else { return 0 }

        let cropWidth = max(3, Int(Double(width) * sharpnessCropFraction))
        let cropHeight = max(3, Int(Double(height) * sharpnessCropFraction))
        let cropX = max(0, (width - cropWidth) / 2)
        let cropY = max(0, (height - cropHeight) / 2)
        let cropRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)

        guard let cropped = cgImage.cropping(to: cropRect) else { return 0 }

        let longestSide = max(cropWidth, cropHeight)
        let scale = min(1.0, Double(sharpnessMaxDimension) / Double(longestSide))
        let sampleWidth = max(3, Int(Double(cropWidth) * scale))
        let sampleHeight = max(3, Int(Double(cropHeight) * scale))
        let bytesPerRow = sampleWidth
        let colorSpace = CGColorSpaceCreateDeviceGray()

        guard let context = CGContext(
            data: nil,
            width: sampleWidth,
            height: sampleHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ),
        let data = context.data else {
            return 0
        }

        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

        let pixels = data.assumingMemoryBound(to: UInt8.self)
        var sum: Double = 0
        var sumSquares: Double = 0
        var count: Double = 0

        for y in 1..<(sampleHeight - 1) {
            let row = y * bytesPerRow
            let previousRow = (y - 1) * bytesPerRow
            let nextRow = (y + 1) * bytesPerRow

            for x in 1..<(sampleWidth - 1) {
                let center = Int(pixels[row + x]) * 8
                let response = center
                    - Int(pixels[previousRow + x - 1])
                    - Int(pixels[previousRow + x])
                    - Int(pixels[previousRow + x + 1])
                    - Int(pixels[row + x - 1])
                    - Int(pixels[row + x + 1])
                    - Int(pixels[nextRow + x - 1])
                    - Int(pixels[nextRow + x])
                    - Int(pixels[nextRow + x + 1])
                let value = Double(response)
                sum += value
                sumSquares += value * value
                count += 1
            }
        }

        guard count > 0 else { return 0 }
        let mean = sum / count
        return max((sumSquares / count) - (mean * mean), 0)
    }

    // MARK: - Captured orientation detection (mirrors PoseDetector logic)

    struct OrientationResult: Sendable {
        let pose: Pose?
        let confidence: Double
        let margin: Double
    }

    static let orientationConfidenceThreshold: Double = 0.6
    static let orientationMarginThreshold: Double = 0.2
    // TWO-947 detector tuning (2026-04-26): high-confidence escape. Orientation
    // scores >= 0.80 are produced only when the strong shape rules pass
    // (front: noseConf > 0.15 && shoulderWidth > 0.10 → 0.85; back: noseConf
    // < 0.10 → 0.85), so a tight margin against the runner-up is Vision noise
    // on the secondary score, not genuine ambiguity. Conjunctive gate without
    // this escape failed Mehul/IMG_8945.JPG (front, conf=0.85, margin=0.10).
    static let orientationConfidenceHighEscape: Double = 0.80

    static func computeCapturedPoseAccuracyScore(
        expected: Pose,
        orientation: OrientationResult,
        tags: inout [CheckInVisualAssessment.ReasonTag]
    ) -> Double {
        let highConfidence = orientation.confidence >= orientationConfidenceHighEscape
        let normalConfirm = orientation.confidence >= orientationConfidenceThreshold
                         && orientation.margin >= orientationMarginThreshold

        if orientation.pose == expected, highConfidence || normalConfirm {
            return 1.0
        }

        if orientation.pose != nil, highConfidence || normalConfirm {
            tags.append(.wrongPose)
            return 0.0
        }

        tags.append(.poseUnclear)
        return 0.5
    }

    /// Returns the most likely captured body orientation with a confidence score for
    /// the top hypothesis and a margin against the second-best hypothesis.
    private static func detectCapturedOrientation(body: VNHumanBodyPoseObservation) -> OrientationResult {
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

        var scores: [(pose: Pose, score: Double)] = [
            (.front, 0),
            (.side, 0),
            (.back, 0),
        ]
        func assign(_ pose: Pose, _ score: Double) {
            guard let index = scores.firstIndex(where: { $0.pose == pose }) else { return }
            scores[index].score = max(scores[index].score, score)
        }

        if noseConf < 0.1 { assign(.back, 0.85) }
        if noseConf < 0.15 { assign(.back, 0.45) }

        if noseConf >= 0.1 { assign(.front, 0.45) }
        if noseConf > 0.15 && shoulderWidth > 0.10 { assign(.front, 0.85) }
        if noseConf > 0.15 && hipWidth > 0.10 { assign(.front, 0.75) }

        let earAsymmetry = abs(leftEarConf - rightEarConf)
        if shoulderWidth > 0 && shoulderWidth < 0.20 { assign(.side, 0.45) }
        if earAsymmetry > 0.3 && shoulderWidth > 0 && shoulderWidth < 0.20 { assign(.side, 0.80) }
        if shoulderWidth > 0 && shoulderWidth < 0.20 && hipWidth > 0 && hipWidth < 0.12 { assign(.side, 0.75) }
        if (leftShoulderConf > 0.3) != (rightShoulderConf > 0.3) { assign(.side, 0.55) }

        let sorted = scores.sorted { $0.score > $1.score }
        guard let best = sorted.first else {
            return OrientationResult(pose: nil, confidence: 0, margin: 0)
        }
        let second = sorted.dropFirst().first?.score ?? 0
        let confidence = clamp(best.score)
        let margin = clamp(best.score - second)
        let pose = confidence >= 0.35 ? best.pose : nil

        return OrientationResult(pose: pose, confidence: confidence, margin: margin)
    }

    // MARK: - Captured arms relaxed check (mirrors PoseDetector logic)

    static func computeCapturedNeutralityScore(
        armsRelaxed: Bool,
        tags: inout [CheckInVisualAssessment.ReasonTag]
    ) -> Double {
        if !armsRelaxed {
            tags.append(.stagedPose)
        }
        return 1.0
    }

    private static func checkCapturedArmsRelaxed(body: VNHumanBodyPoseObservation) -> Bool {
        guard let leftWrist = try? body.recognizedPoint(.leftWrist),
              let rightWrist = try? body.recognizedPoint(.rightWrist),
              let leftHip = try? body.recognizedPoint(.leftHip),
              let rightHip = try? body.recognizedPoint(.rightHip),
              leftWrist.confidence > 0.3, rightWrist.confidence > 0.3,
              leftHip.confidence > 0.3, rightHip.confidence > 0.3 else {
            return true  // Can't see wrists = probably back pose
        }

        // TWO-947 detector tuning (2026-04-26): widened wrist-X tolerance from
        // 0.06 → 0.12 and softened conjunction from "all 4 axes must hold" to
        // "≤ 1 axis can fail". Blind-holdout run showed stagedPose mis-firing
        // on 7 of 9 natural front shots; muscular men's arms hang outboard of
        // hip-X by more than 6% of frame width.
        let leftYOK = abs(leftWrist.location.y - leftHip.location.y) < 0.08
        let rightYOK = abs(rightWrist.location.y - rightHip.location.y) < 0.08
        let leftXOK = abs(leftWrist.location.x - leftHip.location.x) < 0.12
        let rightXOK = abs(rightWrist.location.x - rightHip.location.x) < 0.12

        let axisFailures = [leftYOK, rightYOK, leftXOK, rightXOK].filter { !$0 }.count
        if axisFailures >= 2 {
            return false
        }

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

        return true
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

    static func pickCapturedPrimaryReason(
        tags: [CheckInVisualAssessment.ReasonTag],
        fallback: String
    ) -> String {
        pickPrimaryReason(tags: tags.filter { $0 != .stagedPose }, fallback: fallback)
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

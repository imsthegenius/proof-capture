import Foundation

/// Canonical scoring contract for check-in photos.
/// Used by both the live readiness gate and post-capture quality assessment.
/// One type, one weighting scheme, two modes.
struct CheckInVisualAssessment: Codable, Sendable {

    // MARK: - Modes

    enum Mode: String, Codable, Sendable {
        case live      // No sharpness; optimized for real-time readiness
        case captured  // Full assessment including sharpness
    }

    // MARK: - Live readiness state (drives border glow + auto-capture)

    enum LiveState: String, Codable, Sendable {
        case blocked   // Catastrophic issue; cannot proceed
        case guiding   // Actionable feedback; not yet ready
        case ready     // All checks pass; stable for capture
    }

    // MARK: - Review verdict (post-capture only)

    enum ReviewVerdict: String, Codable, Sendable {
        case keep                // >= 0.75 and no catastrophic tag
        case warn                // 0.50 ..< 0.75
        case retakeRecommended   // < 0.50 or catastrophic override
    }

    // MARK: - Standardized failure reasons

    enum ReasonTag: String, Codable, Sendable, CaseIterable {
        // Catastrophic (force retakeRecommended + blocked)
        case bodyNotDetected
        case wrongPose
        case severeCrop          // Head + feet missing
        case severeBacklight

        // High (captured-only catastrophic)
        case severeBlur

        // Medium (degrade score, may produce warn)
        case headMissing
        case feetMissing
        case tooClose
        case tooFar
        case offCenter
        case flatLighting
        case weakDefinition
        case mildBacklight
        case tooDark
        case tooBright
        case stagedPose
        case poseUnclear

        // Low (informational)
        case mildBlur

        var isCatastrophicLive: Bool {
            switch self {
            case .bodyNotDetected, .wrongPose, .severeCrop, .severeBacklight:
                return true
            default:
                return false
            }
        }

        var isCatastrophicCaptured: Bool {
            switch self {
            case .bodyNotDetected, .wrongPose, .severeCrop, .severeBacklight, .severeBlur:
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Sub-scores (all 0...1, higher is better)

    struct SubScores: Codable, Sendable {
        var definitionLighting: Double   // 0.45 weight
        var framing: Double              // 0.20 weight
        var poseAccuracy: Double         // 0.15 weight
        var poseNeutrality: Double       // 0.10 weight
        var sharpness: Double?           // 0.10 weight (captured only; nil in live)
    }

    struct Diagnostics: Codable, Sendable {
        var rawSharpnessVariance: Double?
        var orientationConfidence: Double?
        var orientationMargin: Double?

        init(
            rawSharpnessVariance: Double? = nil,
            orientationConfidence: Double? = nil,
            orientationMargin: Double? = nil
        ) {
            self.rawSharpnessVariance = rawSharpnessVariance
            self.orientationConfidence = orientationConfidence
            self.orientationMargin = orientationMargin
        }
    }

    // MARK: - Assessment fields

    let mode: Mode
    let overallScore: Double                 // [0, 1]
    let liveState: LiveState
    let reviewVerdict: ReviewVerdict
    let primaryReason: String                // Top blocking/guidance reason for UX
    let reasonTags: [ReasonTag]              // Ordered by severity
    let subScores: SubScores
    let diagnostics: Diagnostics

    // MARK: - Canonical weights

    static let weightDefinitionLighting: Double = 0.45
    static let weightFraming: Double = 0.20
    static let weightPoseAccuracy: Double = 0.15
    static let weightPoseNeutrality: Double = 0.10
    static let weightSharpness: Double = 0.10  // Captured mode only

    // MARK: - Thresholds

    static let liveReadyThreshold: Double = 0.78
    static let liveStableDuration: TimeInterval = 0.5

    static let capturedKeepThreshold: Double = 0.75
    static let capturedWarnThreshold: Double = 0.50

    // MARK: - Computation

    static func compute(
        subScores: SubScores,
        reasonTags: [ReasonTag],
        mode: Mode,
        primaryReason: String,
        diagnostics: Diagnostics = Diagnostics()
    ) -> CheckInVisualAssessment {
        // Calculate weighted overall score
        let overall: Double
        if mode == .captured, let sharpness = subScores.sharpness {
            overall = clamp(
                weightDefinitionLighting * subScores.definitionLighting +
                weightFraming * subScores.framing +
                weightPoseAccuracy * subScores.poseAccuracy +
                weightPoseNeutrality * subScores.poseNeutrality +
                weightSharpness * sharpness
            )
        } else {
            // Live mode: redistribute sharpness weight proportionally
            let liveTotal = weightDefinitionLighting + weightFraming + weightPoseAccuracy + weightPoseNeutrality
            overall = clamp(
                (weightDefinitionLighting / liveTotal) * subScores.definitionLighting +
                (weightFraming / liveTotal) * subScores.framing +
                (weightPoseAccuracy / liveTotal) * subScores.poseAccuracy +
                (weightPoseNeutrality / liveTotal) * subScores.poseNeutrality
            )
        }

        // Determine live state
        let hasCatastrophicLive = reasonTags.contains { $0.isCatastrophicLive }
        let liveState: LiveState
        if hasCatastrophicLive {
            liveState = .blocked
        } else if overall >= liveReadyThreshold {
            liveState = .ready
        } else {
            liveState = .guiding
        }

        // Determine review verdict
        let hasCatastrophicCaptured = reasonTags.contains { $0.isCatastrophicCaptured }
        let hasAmbiguousCapturedPose = mode == .captured && reasonTags.contains(.poseUnclear)
        let reviewVerdict: ReviewVerdict
        if hasCatastrophicCaptured || overall < capturedWarnThreshold {
            reviewVerdict = .retakeRecommended
        } else if hasAmbiguousCapturedPose || overall < capturedKeepThreshold {
            reviewVerdict = .warn
        } else {
            reviewVerdict = .keep
        }

        return CheckInVisualAssessment(
            mode: mode,
            overallScore: overall,
            liveState: liveState,
            reviewVerdict: reviewVerdict,
            primaryReason: primaryReason,
            reasonTags: reasonTags,
            subScores: subScores,
            diagnostics: diagnostics
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

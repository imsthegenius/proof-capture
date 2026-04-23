import XCTest

@testable import ProofCapture

final class CheckInScorerBodyAnalysisTests: XCTestCase {
    func testCapturedStagedPoseIsDiagnosticOnly() {
        var tags: [CheckInVisualAssessment.ReasonTag] = []
        let neutrality = CheckInScorer.computeCapturedNeutralityScore(
            armsRelaxed: false,
            tags: &tags
        )
        let primaryReason = CheckInScorer.pickCapturedPrimaryReason(
            tags: tags,
            fallback: "Good check-in photo"
        )

        let assessment = CheckInVisualAssessment.compute(
            subScores: .init(
                definitionLighting: 0.85,
                framing: 1.0,
                poseAccuracy: 1.0,
                poseNeutrality: neutrality,
                sharpness: 1.0
            ),
            reasonTags: tags,
            mode: .captured,
            primaryReason: primaryReason
        )

        XCTAssertEqual(neutrality, 1.0)
        XCTAssertEqual(assessment.reviewVerdict, .keep)
        XCTAssertEqual(assessment.subScores.poseNeutrality, 1.0)
        XCTAssertTrue(assessment.reasonTags.contains(.stagedPose))
        XCTAssertEqual(assessment.primaryReason, "Good check-in photo")
    }

    func testLiveArmsNotRelaxedStillGuides() {
        let assessment = CheckInScorer.assessLive(
            .init(
                bodyDetected: true,
                positionQuality: .good,
                poseMatchesExpected: true,
                armsRelaxed: false,
                detectedOrientation: .front,
                targetPose: .front,
                bodyHeight: 0.55,
                bodyCenterX: 0.5,
                lightingQuality: .good,
                brightness: 0.45,
                directionalityGradient: 0.04,
                definitionContrast: 0.12,
                isBacklit: false
            )
        )

        XCTAssertEqual(assessment.liveState, .guiding)
        XCTAssertEqual(assessment.subScores.poseNeutrality, 0.4)
        XCTAssertTrue(assessment.reasonTags.contains(.stagedPose))
    }

    func testHighConfidenceCapturedPoseMismatchIsWrongPose() {
        var tags: [CheckInVisualAssessment.ReasonTag] = []
        let poseScore = CheckInScorer.computeCapturedPoseAccuracyScore(
            expected: .front,
            orientation: .init(pose: .back, confidence: 0.8, margin: 0.3),
            tags: &tags
        )

        let assessment = CheckInVisualAssessment.compute(
            subScores: .init(
                definitionLighting: 1.0,
                framing: 1.0,
                poseAccuracy: poseScore,
                poseNeutrality: 1.0,
                sharpness: 1.0
            ),
            reasonTags: tags,
            mode: .captured,
            primaryReason: "Wrong pose — check your position"
        )

        XCTAssertEqual(poseScore, 0.0)
        XCTAssertTrue(tags.contains(.wrongPose))
        XCTAssertEqual(assessment.reviewVerdict, .retakeRecommended)
    }

    func testLowConfidenceCapturedPoseMismatchIsPoseUnclearWarning() {
        var tags: [CheckInVisualAssessment.ReasonTag] = []
        let poseScore = CheckInScorer.computeCapturedPoseAccuracyScore(
            expected: .front,
            orientation: .init(pose: .side, confidence: 0.55, margin: 0.1),
            tags: &tags
        )

        let assessment = CheckInVisualAssessment.compute(
            subScores: .init(
                definitionLighting: 0.45,
                framing: 0.8,
                poseAccuracy: poseScore,
                poseNeutrality: 1.0,
                sharpness: 1.0
            ),
            reasonTags: tags,
            mode: .captured,
            primaryReason: "Adjust your position"
        )

        XCTAssertEqual(poseScore, 0.5)
        XCTAssertTrue(tags.contains(.poseUnclear))
        XCTAssertFalse(tags.contains(.wrongPose))
        XCTAssertEqual(assessment.reviewVerdict, .warn)
    }

    func testLowMarginCapturedPoseMatchIsPoseUnclear() {
        var tags: [CheckInVisualAssessment.ReasonTag] = []
        let poseScore = CheckInScorer.computeCapturedPoseAccuracyScore(
            expected: .front,
            orientation: .init(pose: .front, confidence: 0.85, margin: 0.1),
            tags: &tags
        )

        XCTAssertEqual(poseScore, 0.5)
        XCTAssertTrue(tags.contains(.poseUnclear))
        XCTAssertFalse(tags.contains(.wrongPose))
    }

    func testMatchingCapturedOrientationWithHighConfidenceIsKeep() {
        var tags: [CheckInVisualAssessment.ReasonTag] = []
        let poseScore = CheckInScorer.computeCapturedPoseAccuracyScore(
            expected: .front,
            orientation: .init(pose: .front, confidence: 0.9, margin: 0.4),
            tags: &tags
        )

        let assessment = CheckInVisualAssessment.compute(
            subScores: .init(
                definitionLighting: 1.0,
                framing: 1.0,
                poseAccuracy: poseScore,
                poseNeutrality: 1.0,
                sharpness: 1.0
            ),
            reasonTags: tags,
            mode: .captured,
            primaryReason: "Good check-in photo"
        )

        XCTAssertEqual(poseScore, 1.0)
        XCTAssertTrue(tags.isEmpty)
        XCTAssertEqual(assessment.reviewVerdict, .keep)
    }
}

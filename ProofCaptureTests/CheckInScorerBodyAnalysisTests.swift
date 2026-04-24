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
}

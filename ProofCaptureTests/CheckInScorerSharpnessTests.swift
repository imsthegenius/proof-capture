import CoreImage
import UIKit
import XCTest

@testable import ProofCapture

final class CheckInScorerSharpnessTests: XCTestCase {
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    func testSharpnessScoreDecreasesMonotonicallyAcrossSyntheticBlurLadder() throws {
        let radii: [Double] = [0.0, 1.0, 2.5, 5.0, 10.0, 20.0]
        let analyses = try radii.map { radius in
            var tags: [CheckInVisualAssessment.ReasonTag] = []
            let image = try fixtureImage(blurRadius: radius)
            let analysis = CheckInScorer.computeSharpnessScore(cgImage: image, tags: &tags)
            return (radius: radius, analysis: analysis)
        }

        for index in analyses.indices.dropLast() {
            XCTAssertGreaterThan(
                analyses[index].analysis.score,
                analyses[index + 1].analysis.score,
                "Expected radius \(analyses[index].radius) score \(analyses[index].analysis.score) " +
                    "> radius \(analyses[index + 1].radius) score \(analyses[index + 1].analysis.score); " +
                    "raw variances \(analyses[index].analysis.rawVariance) and \(analyses[index + 1].analysis.rawVariance)"
            )
        }
    }

    func testSevereBlurFiresOnHeaviestBlurButNotSharpFixture() throws {
        var sharpTags: [CheckInVisualAssessment.ReasonTag] = []
        let sharp = CheckInScorer.computeSharpnessScore(
            cgImage: try fixtureImage(blurRadius: 0),
            tags: &sharpTags
        )

        var blurredTags: [CheckInVisualAssessment.ReasonTag] = []
        let blurred = CheckInScorer.computeSharpnessScore(
            cgImage: try fixtureImage(blurRadius: 20),
            tags: &blurredTags
        )

        XCTAssertFalse(sharpTags.contains(.severeBlur))
        XCTAssertTrue(blurredTags.contains(.severeBlur))
        XCTAssertLessThan(blurred.score, sharp.score)
    }

    func testMildBlurFiresBeforeSevereBlur() throws {
        var tags: [CheckInVisualAssessment.ReasonTag] = []
        _ = CheckInScorer.computeSharpnessScore(
            cgImage: try fixtureImage(blurRadius: 2.5),
            tags: &tags
        )

        XCTAssertTrue(tags.contains(.mildBlur))
        XCTAssertFalse(tags.contains(.severeBlur))
    }

    private func fixtureImage(blurRadius: Double) throws -> CGImage {
        let url = repoRoot()
            .appendingPathComponent("scripts")
            .appendingPathComponent("test-images")
            .appendingPathComponent("front_directional_good.jpg")

        guard let image = UIImage(contentsOfFile: url.path), let cgImage = image.cgImage else {
            XCTFail("Could not load fixture at \(url.path)")
            throw TestError.fixtureMissing
        }

        guard blurRadius > 0 else { return cgImage }

        let base = CIImage(cgImage: cgImage)
        let blurred = base
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius])
            .cropped(to: base.extent)

        guard let output = context.createCGImage(blurred, from: base.extent) else {
            XCTFail("Could not render blurred fixture at radius \(blurRadius)")
            throw TestError.blurRenderFailed
        }

        return output
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private enum TestError: Error {
        case fixtureMissing
        case blurRenderFailed
    }
}

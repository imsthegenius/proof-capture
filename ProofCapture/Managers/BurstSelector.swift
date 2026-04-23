import UIKit
import CoreImage
import Vision

struct BurstSelector {

    /// Returns the best image from a burst using the canonical captured assessment.
    ///
    /// Phase 1: Eliminate obviously blurry frames (sharpness < 0.01).
    /// Phase 2: Score each remaining frame with `CheckInScorer.assessCaptured`.
    /// Phase 3: Among frames with the same verdict tier, prefer highest sharpness.
    ///
    /// Sharpness is the main differentiator among already-acceptable frames,
    /// matching the body-over-face scoring philosophy.
    static func selectBest(from images: [UIImage], pose: Pose = .front) async -> UIImage? {
        guard !images.isEmpty else { return nil }
        if images.count == 1 { return images.first }

        // Phase 1: compute sharpness for all frames and eliminate the obviously blurry
        let scored = images.map { image in
            (image, sharpnessScore(for: image))
        }

        let minimumSharpness: Float = 0.01
        let viable = scored.filter { $0.1 >= minimumSharpness }
        let candidates = viable.isEmpty ? scored : viable

        // Phase 2: score each candidate with the canonical captured scorer
        var bestImage: UIImage?
        var bestOverall: Double = -1
        var bestSharpness: Float = -1

        for (image, sharpness) in candidates {
            let assessment = await CheckInScorer.assessCaptured(image: image, pose: pose)

            // Tie-break: overall score first, then sharpness
            if assessment.overallScore > bestOverall ||
               (assessment.overallScore == bestOverall && sharpness > bestSharpness) {
                bestOverall = assessment.overallScore
                bestSharpness = sharpness
                bestImage = image
            }
        }

        return bestImage ?? candidates.max(by: { $0.1 < $1.1 })?.0
    }

    // MARK: - Sharpness (Laplacian edge detection)

    static func sharpnessScore(for image: UIImage) -> Float {
        guard let ciImage = CIImage(image: image) else { return 0 }

        let context = CIContext(options: [.useSoftwareRenderer: false])

        let weights: [CGFloat] = [-1, -1, -1, -1, 8, -1, -1, -1, -1]
        let weightVector = CIVector(values: weights, count: 9)

        guard let convolution = CIFilter(
            name: "CIConvolution3X3",
            parameters: [
                kCIInputImageKey: ciImage,
                "inputWeights": weightVector,
                "inputBias": 0.0
            ]
        ),
        let outputImage = convolution.outputImage else {
            return 0
        }

        let extent = outputImage.extent
        guard let avgFilter = CIFilter(
            name: "CIAreaAverage",
            parameters: [
                kCIInputImageKey: outputImage,
                kCIInputExtentKey: CIVector(
                    x: extent.origin.x,
                    y: extent.origin.y,
                    z: extent.size.width,
                    w: extent.size.height
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

        let score = 0.299 * pixel[0] + 0.587 * pixel[1] + 0.114 * pixel[2]
        return abs(score)
    }
}

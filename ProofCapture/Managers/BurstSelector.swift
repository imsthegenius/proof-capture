import UIKit
import CoreImage
import Vision

struct BurstSelector {

    /// Returns the best image from a burst using composite quality scoring.
    ///
    /// On iOS 18+, integrates `VNCalculateImageAestheticsScoresRequest` for
    /// scientifically-grounded frame selection (blur, exposure, composition).
    /// Falls back to sharpness + face quality on iOS 17.
    ///
    /// Sharpness remains the primary disqualifier — very blurry frames
    /// (sharpness < 0.01) are eliminated before aesthetics scoring.
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

        // Phase 2: score each candidate with the full composite
        var bestImage: UIImage?
        var bestScore: Float = -1

        for (image, sharpness) in candidates {
            let aesthetics = await aestheticsScore(for: image)
            let faceQuality: Float = (pose == .front) ? faceQualityScore(for: image) : 0

            // Disqualify frames Apple's model flags as screenshots/documents
            if aesthetics.isUtility { continue }

            let score: Float = switch pose {
            case .front:
                sharpness * 0.50 + aesthetics.normalized * 0.35 + faceQuality * 0.15
            case .side:
                sharpness * 0.65 + aesthetics.normalized * 0.35
            case .back:
                sharpness * 0.60 + aesthetics.normalized * 0.40
            }

            if score > bestScore {
                bestScore = score
                bestImage = image
            }
        }

        // If every candidate was disqualified (all isUtility), fall back to sharpest
        return bestImage ?? candidates.max(by: { $0.1 < $1.1 })?.0
    }

    // MARK: - Aesthetics (iOS 18+ Vision framework)

    private struct AestheticsResult {
        let normalized: Float
        let isUtility: Bool

        static let unavailable = AestheticsResult(normalized: 0, isUtility: false)
    }

    private static func aestheticsScore(for image: UIImage) async -> AestheticsResult {
        if #available(iOS 18.0, *) {
            return await aestheticsScoreIOS18(for: image)
        } else {
            return .unavailable
        }
    }

    @available(iOS 18.0, *)
    private static func aestheticsScoreIOS18(for image: UIImage) async -> AestheticsResult {
        guard let cgImage = image.cgImage else { return .unavailable }

        let request = VNCalculateImageAestheticsScoresRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)

        do {
            try handler.perform([request])
        } catch {
            return .unavailable
        }

        guard let result = request.results?.first else {
            return .unavailable
        }

        let normalized = (result.overallScore + 1.0) / 2.0
        return AestheticsResult(
            normalized: normalized,
            isUtility: result.isUtility
        )
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

    // MARK: - Face Quality (Vision framework)

    private static func faceQualityScore(for image: UIImage) -> Float {
        guard let cgImage = image.cgImage else { return 0 }

        let request = VNDetectFaceCaptureQualityRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)

        do {
            try handler.perform([request])
        } catch {
            return 0
        }

        guard let result = request.results?.first,
              let quality = result.faceCaptureQuality else {
            return 0
        }

        return quality
    }
}

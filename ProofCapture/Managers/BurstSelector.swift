import UIKit
import CoreImage
import Vision

struct BurstSelector {

    /// Returns the best image from a burst using composite quality scoring.
    /// Sharpness dominates for all poses — this is a body photo app.
    /// Face quality is a minor tiebreaker for front shots only.
    static func selectBest(from images: [UIImage], pose: Pose = .front) -> UIImage? {
        guard !images.isEmpty else { return nil }
        if images.count == 1 { return images.first }

        var bestImage: UIImage?
        var bestScore: Float = -1

        for image in images {
            let sharpness = sharpnessScore(for: image)
            let faceQuality: Float = (pose == .front) ? faceQualityScore(for: image) : 0

            // Body-focused: sharpness is king. Face quality is a minor tiebreaker
            // for front shots (avoids selecting frames with eyes closed/blurred face)
            let score: Float = switch pose {
            case .front:
                sharpness * 0.75 + faceQuality * 0.25
            case .side:
                sharpness * 0.9 + faceQuality * 0.1
            case .back:
                sharpness
            }

            if score > bestScore {
                bestScore = score
                bestImage = image
            }
        }

        return bestImage
    }

    // MARK: - Sharpness (Laplacian edge detection)

    private static func sharpnessScore(for image: UIImage) -> Float {
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

        // Return the quality of the first (best) face detected
        guard let result = request.results?.first,
              let quality = result.faceCaptureQuality else {
            return 0
        }

        return quality
    }
}

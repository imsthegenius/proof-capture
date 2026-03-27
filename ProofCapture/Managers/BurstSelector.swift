import UIKit
import CoreImage

struct BurstSelector {

    /// Returns the sharpest image from a burst by measuring edge intensity via Laplacian convolution.
    static func selectBest(from images: [UIImage]) -> UIImage? {
        guard !images.isEmpty else { return nil }
        if images.count == 1 { return images.first }

        var bestImage: UIImage?
        var bestScore: Float = -1

        for image in images {
            let score = sharpnessScore(for: image)
            if score > bestScore {
                bestScore = score
                bestImage = image
            }
        }

        return bestImage
    }

    // MARK: - Sharpness measurement

    /// Applies a 3x3 Laplacian kernel and returns the mean pixel intensity of the result.
    /// Higher mean = more edges = sharper image.
    private static func sharpnessScore(for image: UIImage) -> Float {
        guard let ciImage = CIImage(image: image) else { return 0 }

        let context = CIContext(options: [.useSoftwareRenderer: false])

        // Laplacian kernel: [-1,-1,-1, -1,8,-1, -1,-1,-1]
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

        // Compute the average pixel value of the edge-detected image
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

        // Read the single-pixel result
        var pixel = [Float](repeating: 0, count: 4)
        context.render(
            avgOutput,
            toBitmap: &pixel,
            rowBytes: 16,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBAf,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        // Use luminance-weighted average of RGB channels
        let score = 0.299 * pixel[0] + 0.587 * pixel[1] + 0.114 * pixel[2]
        return abs(score)
    }
}

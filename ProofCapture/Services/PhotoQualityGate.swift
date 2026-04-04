import UIKit
import CoreImage
import Vision

/// Post-capture quality assessment for saved progress photos.
/// Runs on the actual saved UIImage after burst selection to verify
/// the frame is comparison-ready (sharp, well-exposed, fully framed).
///
/// This is non-blocking metadata — it never prevents saving. It signals
/// when a capture may not produce useful comparison data.
struct PhotoQualityGate {

    struct Report {
        let issues: [String]
        var isAcceptable: Bool { issues.isEmpty }
        var shouldWarn: Bool { !issues.isEmpty }
    }

    /// Assess a saved image for comparison readiness.
    /// Runs sharpness, framing, and exposure checks concurrently.
    static func assess(image: UIImage, pose: Pose) async -> Report {
        async let sharpnessIssue = checkSharpness(image: image)
        async let framingIssue = checkFraming(image: image)
        async let exposureIssue = checkExposure(image: image)

        let results = await [sharpnessIssue, framingIssue, exposureIssue]
        let issues = results.compactMap { $0 }
        return Report(issues: issues)
    }

    // MARK: - Sharpness (Laplacian variance on center 60%)

    private static func checkSharpness(image: UIImage) async -> String? {
        guard let ciImage = CIImage(image: image) else { return nil }

        let extent = ciImage.extent
        let insetX = extent.width * 0.2
        let insetY = extent.height * 0.2
        let centerRect = extent.insetBy(dx: insetX, dy: insetY)
        let cropped = ciImage.cropped(to: centerRect)

        let context = CIContext(options: [.useSoftwareRenderer: false])

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
            return nil
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
            return nil
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

        let variance = 0.299 * pixel[0] + 0.587 * pixel[1] + 0.114 * pixel[2]

        if abs(variance) < 0.008 {
            return "Too blurry for comparison"
        }
        return nil
    }

    // MARK: - Full-body framing (head + feet in frame)

    private static func checkFraming(image: UIImage) async -> String? {
        guard let cgImage = image.cgImage else { return nil }

        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let body = request.results?.first else {
            return "Body not detected in frame"
        }

        let hasHead: Bool
        let hasFeet: Bool

        do {
            let nose = try body.recognizedPoint(.nose)
            hasHead = nose.confidence > 0.1
        } catch {
            hasHead = false
        }

        do {
            let leftAnkle = try body.recognizedPoint(.leftAnkle)
            let rightAnkle = try body.recognizedPoint(.rightAnkle)
            hasFeet = leftAnkle.confidence > 0.1 || rightAnkle.confidence > 0.1
        } catch {
            hasFeet = false
        }

        if !hasHead && !hasFeet {
            return "Head and feet not in frame"
        } else if !hasHead {
            return "Head not in frame"
        } else if !hasFeet {
            return "Feet not in frame"
        }
        return nil
    }

    // MARK: - Exposure (person-masked brightness via segmentation + CIAreaAverage)

    private static func checkExposure(image: UIImage) async -> String? {
        guard let cgImage = image.cgImage else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent
        let context = CIContext(options: [.useSoftwareRenderer: false])

        // Segment person to measure exposure on the body, not the background
        let segRequest = VNGeneratePersonSegmentationRequest()
        segRequest.qualityLevel = .balanced
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)

        do {
            try handler.perform([segRequest])
        } catch {
            return nil
        }

        guard let segResult = segRequest.results?.first else {
            // No person detected — skip exposure check
            return nil
        }

        let maskImage = CIImage(cvPixelBuffer: segResult.pixelBuffer)
        let scaledMask = maskImage.transformed(by: CGAffineTransform(
            scaleX: extent.width / maskImage.extent.width,
            y: extent.height / maskImage.extent.height
        ))

        // Measure mask coverage (average of mask = fraction of frame occupied by person)
        let coverage = averageBrightness(of: scaledMask, in: extent, context: context)
        guard coverage > 0.02 else { return nil }

        // Measure person-masked brightness and normalize by coverage
        let black = CIImage(color: .black).cropped(to: extent)
        let personImage = ciImage.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: black,
            kCIInputMaskImageKey: scaledMask
        ])

        let rawBrightness = averageBrightness(of: personImage, in: extent, context: context)
        let brightness = min(rawBrightness / coverage, 1.0)

        if brightness < 0.12 {
            return "Too dark for comparison"
        } else if brightness > 0.85 {
            return "Overexposed — too bright"
        }
        return nil
    }

    private static func averageBrightness(of image: CIImage, in rect: CGRect, context: CIContext) -> Double {
        guard let avgFilter = CIFilter(
            name: "CIAreaAverage",
            parameters: [
                kCIInputImageKey: image,
                kCIInputExtentKey: CIVector(
                    x: rect.origin.x,
                    y: rect.origin.y,
                    z: rect.size.width,
                    w: rect.size.height
                )
            ]
        ),
        let avgOutput = avgFilter.outputImage else {
            return 0.5
        }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            avgOutput,
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
}

import AVFoundation
import CoreImage
import Vision
import UIKit

/// Multi-layered lighting analysis using person segmentation, regional brightness,
/// shadow contrast, and backlighting detection. Designed to assess whether lighting
/// will produce good muscle definition in progress photos (directional downlighting).
@Observable
final class LightingAnalyzer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    // MARK: - Public state

    var quality: QualityLevel = .fair
    var feedback: String = "Analyzing lighting\u{2026}"
    var brightness: Double = 0.5

    // MARK: - Private

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var lastAnalysisTime: Date = .distantPast
    private let analysisInterval: TimeInterval = 0.33 // ~3fps — heavier analysis than before

    // MARK: - Internal result types

    private struct ExposureResult {
        let brightness: Double
        var isTooLight: Bool { brightness > 0.82 }
        var isTooDark: Bool { brightness < 0.15 }
        var isMarginDark: Bool { brightness < 0.25 }
        var isMarginBright: Bool { brightness > 0.72 }
    }

    private struct DownlightResult {
        let isPresent: Bool
        let gradient: Double // positive = top brighter than bottom
    }

    private struct ShadowResult {
        let contrast: Double // 0-1, higher = more directional shadows
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = Date()
        guard now.timeIntervalSince(lastAnalysisTime) >= analysisInterval else { return }
        lastAnalysisTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        analyze(pixelBuffer: pixelBuffer)
    }

    // MARK: - Multi-layered analysis pipeline

    private func analyze(pixelBuffer: CVPixelBuffer) {
        let frame = CIImage(cvPixelBuffer: pixelBuffer)

        // Batch Vision requests: person segmentation + face quality
        let segRequest = VNGeneratePersonSegmentationRequest()
        segRequest.qualityLevel = .balanced // good quality, real-time capable

        // Body-focused analysis — no face quality (we care about muscle definition, not face lighting)

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        do {
            try handler.perform([segRequest])
        } catch {
            publishResult(quality: .fair, feedback: "Analyzing lighting\u{2026}", brightness: 0.5)
            return
        }

        // If no person detected, fall back to basic brightness analysis
        guard let segResult = segRequest.results?.first else {
            let basic = analyzeOverallExposure(frame: frame)
            let feedback = basic.isTooDark ? "Too dark \u{2014} turn on more lights"
                : basic.isTooLight ? "Too bright \u{2014} move away from light"
                : "Step into frame"
            publishResult(quality: .fair, feedback: feedback, brightness: basic.brightness)
            return
        }

        // Build person mask
        let maskImage = CIImage(cvPixelBuffer: segResult.pixelBuffer)
        let frameExtent = frame.extent
        let scaledMask = maskImage.transformed(by: CGAffineTransform(
            scaleX: frameExtent.width / maskImage.extent.width,
            y: frameExtent.height / maskImage.extent.height
        ))

        // Create person-isolated image (person pixels + black background)
        let black = CIImage(color: .black).cropped(to: frameExtent)
        let personImage = frame.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: black,
            kCIInputMaskImageKey: scaledMask
        ])

        // Run all analysis layers
        let exposure = analyzeOverallExposure(frame: frame)
        let downlight = analyzeDownlighting(personImage: personImage, extent: frameExtent)
        let shadows = analyzeShadowContrast(personImage: personImage, extent: frameExtent)
        let backlit = analyzeBacklighting(
            frame: frame, mask: scaledMask, personImage: personImage, extent: frameExtent
        )
        // Composite assessment — body-focused (downlighting + shadow contrast = muscle definition)
        let result = compositeAssessment(
            exposure: exposure,
            downlight: downlight,
            shadows: shadows,
            isBacklit: backlit
        )

        publishResult(quality: result.quality, feedback: result.feedback, brightness: exposure.brightness)
    }

    // MARK: - Layer 1: Overall exposure

    private func analyzeOverallExposure(frame: CIImage) -> ExposureResult {
        let b = regionBrightness(of: frame, in: frame.extent)
        return ExposureResult(brightness: b)
    }

    // MARK: - Layer 2: Downlighting gradient

    /// Splits the person into top and bottom halves. If the top half is brighter,
    /// overhead light is casting shadows downward — ideal for muscle definition.
    private func analyzeDownlighting(personImage: CIImage, extent: CGRect) -> DownlightResult {
        let midY = extent.midY

        // CIImage coordinate space: Y=0 at bottom
        // "upper body" = top of frame = higher Y values
        let upperRect = CGRect(x: 0, y: midY, width: extent.width, height: extent.height - midY)
        let lowerRect = CGRect(x: 0, y: 0, width: extent.width, height: midY)

        let upperBrightness = regionBrightness(of: personImage, in: upperRect)
        let lowerBrightness = regionBrightness(of: personImage, in: lowerRect)

        let gradient = upperBrightness - lowerBrightness
        // Positive gradient means top is brighter = downlighting
        // Threshold: > 0.03 is detectable overhead light
        return DownlightResult(isPresent: gradient > 0.03, gradient: gradient)
    }

    // MARK: - Layer 3: Shadow contrast (directional light quality)

    /// Samples 4 quadrants of the person image and measures variance.
    /// High variance = strong directional light = deep shadows = visible muscle definition.
    /// Low variance = flat/diffused light = everything looks the same.
    private func analyzeShadowContrast(personImage: CIImage, extent: CGRect) -> ShadowResult {
        let midX = extent.midX
        let midY = extent.midY

        let quadrants = [
            CGRect(x: 0, y: midY, width: midX, height: extent.height - midY),     // top-left
            CGRect(x: midX, y: midY, width: extent.width - midX, height: extent.height - midY), // top-right
            CGRect(x: 0, y: 0, width: midX, height: midY),                         // bottom-left
            CGRect(x: midX, y: 0, width: extent.width - midX, height: midY)        // bottom-right
        ]

        let values = quadrants.map { regionBrightness(of: personImage, in: $0) }
            .filter { $0 > 0.01 } // exclude quadrants with no person pixels

        guard values.count >= 3 else {
            return ShadowResult(contrast: 0)
        }

        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)

        // Map variance to 0-1 quality score
        // variance > 0.003 = strong directional shadows (good)
        // variance < 0.001 = flat lighting (bad)
        let contrast = min(variance / 0.003, 1.0)

        return ShadowResult(contrast: contrast)
    }

    // MARK: - Layer 4: Backlighting detection

    /// Compares average brightness of person vs background.
    /// If background is significantly brighter, the person is silhouetted.
    private func analyzeBacklighting(
        frame: CIImage,
        mask: CIImage,
        personImage: CIImage,
        extent: CGRect
    ) -> Bool {
        // Person brightness (from already-masked image)
        let personBrightness = regionBrightness(of: personImage, in: extent)

        // Background: invert mask and apply to frame
        let invertedMask = mask.applyingFilter("CIColorInvert")
        let black = CIImage(color: .black).cropped(to: extent)
        let bgImage = frame.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: black,
            kCIInputMaskImageKey: invertedMask
        ])
        let bgBrightness = regionBrightness(of: bgImage, in: extent)

        // Backlit if background is substantially brighter than the person
        return bgBrightness > personBrightness + 0.25
    }

    // MARK: - Composite assessment

    private struct Assessment {
        let quality: QualityLevel
        let feedback: String
    }

    private func compositeAssessment(
        exposure: ExposureResult,
        downlight: DownlightResult,
        shadows: ShadowResult,
        isBacklit: Bool
    ) -> Assessment {
        // Priority: critical problems first, then body-specific quality assessment.
        // Good progress photos need: visible muscle definition from directional shadows,
        // not just "well lit". A bright flat room is worse than a dimmer room with one overhead.

        if isBacklit {
            return Assessment(quality: .poor, feedback: "Strong light behind you \u{2014} try a different angle")
        }

        if exposure.isTooDark {
            return Assessment(quality: .poor, feedback: "Too dark \u{2014} turn on more lights")
        }

        if exposure.isTooLight {
            return Assessment(quality: .poor, feedback: "Too bright \u{2014} move away from the light source")
        }

        // Ideal: overhead light + strong shadows on the body
        // This is what makes muscle definition visible in progress photos
        if downlight.isPresent && shadows.contrast > 0.5 {
            return Assessment(quality: .good, feedback: "Great light \u{2014} shadows will show definition")
        }

        if downlight.isPresent && shadows.contrast > 0.25 {
            return Assessment(quality: .good, feedback: "Good overhead light")
        }

        // Directional light without clear downlighting (side window, lamp)
        // Still produces shadow contrast on the body — acceptable
        if shadows.contrast > 0.3 {
            return Assessment(quality: .good, feedback: "Good directional light")
        }

        // Decent exposure but flat lighting — body will look washed out
        if shadows.contrast < 0.15 {
            return Assessment(quality: .fair, feedback: "Flat lighting \u{2014} stand under a single overhead light")
        }

        if exposure.isMarginDark {
            return Assessment(quality: .fair, feedback: "A bit dark \u{2014} find more light")
        }

        if exposure.isMarginBright {
            return Assessment(quality: .fair, feedback: "Slightly bright \u{2014} adjust your position")
        }

        return Assessment(quality: .fair, feedback: "Try standing directly under an overhead light")
    }

    // MARK: - Core Image helpers

    private func regionBrightness(of image: CIImage, in rect: CGRect) -> Double {
        let cropped = image.cropped(to: rect)
        guard let avgFilter = CIFilter(
            name: "CIAreaAverage",
            parameters: [
                kCIInputImageKey: cropped,
                kCIInputExtentKey: CIVector(
                    x: rect.origin.x, y: rect.origin.y,
                    z: rect.size.width, w: rect.size.height
                )
            ]
        ),
        let output = avgFilter.outputImage else {
            return 0.5
        }

        var pixel = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        // BT.601 perceptual luminance
        let r = Double(pixel[0]) / 255.0
        let g = Double(pixel[1]) / 255.0
        let b = Double(pixel[2]) / 255.0
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    // MARK: - State publishing

    private func publishResult(quality: QualityLevel, feedback: String, brightness: Double) {
        Task { @MainActor in
            self.quality = quality
            self.feedback = feedback
            self.brightness = brightness
        }
    }
}

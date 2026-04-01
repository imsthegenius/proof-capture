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
    var feedback: String = "Analyzing lighting…"
    var brightness: Double = 0.5

    // MARK: - Private

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var lastAnalysisTime: Date = .distantPast
    private let analysisInterval: TimeInterval = 0.33

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
        let gradient: Double
    }

    private struct ShadowResult {
        let contrast: Double
    }

    private struct MaskedBrightnessResult {
        let brightness: Double
        let coverage: Double
    }

    private struct Assessment {
        let quality: QualityLevel
        let feedback: String
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

        let segRequest = VNGeneratePersonSegmentationRequest()
        segRequest.qualityLevel = .balanced

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        do {
            try handler.perform([segRequest])
        } catch {
            publishResult(quality: .fair, feedback: "Analyzing lighting…", brightness: 0.5)
            return
        }

        guard let segResult = segRequest.results?.first else {
            let basic = analyzeOverallExposure(frame: frame)
            let feedback = basic.isTooDark ? "Too dark — turn on more lights"
                : basic.isTooLight ? "Too bright — move away from light"
                : "Step into frame"
            publishResult(quality: .fair, feedback: feedback, brightness: basic.brightness)
            return
        }

        let maskImage = CIImage(cvPixelBuffer: segResult.pixelBuffer)
        let frameExtent = frame.extent
        let scaledMask = maskImage.transformed(by: CGAffineTransform(
            scaleX: frameExtent.width / maskImage.extent.width,
            y: frameExtent.height / maskImage.extent.height
        ))

        let black = CIImage(color: .black).cropped(to: frameExtent)
        let personImage = frame.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: black,
            kCIInputMaskImageKey: scaledMask
        ])

        let exposure = analyzePersonExposure(personImage: personImage, mask: scaledMask, extent: frameExtent)
        let downlight = analyzeDownlighting(personImage: personImage, mask: scaledMask, extent: frameExtent)
        let shadows = analyzeShadowContrast(personImage: personImage, mask: scaledMask, extent: frameExtent)
        let backlit = analyzeBacklighting(
            frame: frame,
            mask: scaledMask,
            personImage: personImage,
            extent: frameExtent
        )

        let result = compositeAssessment(
            exposure: exposure,
            downlight: downlight,
            shadows: shadows,
            isBacklit: backlit
        )

        publishResult(quality: result.quality, feedback: result.feedback, brightness: exposure.brightness)
    }

    // MARK: - Layer 1: Exposure

    private func analyzeOverallExposure(frame: CIImage) -> ExposureResult {
        let measuredBrightness = rawBrightness(of: frame, in: frame.extent)
        return ExposureResult(brightness: measuredBrightness)
    }

    private func analyzePersonExposure(personImage: CIImage, mask: CIImage, extent: CGRect) -> ExposureResult {
        let measuredBrightness = maskedBrightness(of: personImage, with: mask, in: extent)?.brightness
            ?? rawBrightness(of: personImage, in: extent)
        return ExposureResult(brightness: measuredBrightness)
    }

    // MARK: - Layer 2: Downlighting gradient

    private func analyzeDownlighting(personImage: CIImage, mask: CIImage, extent: CGRect) -> DownlightResult {
        let midY = extent.midY
        let upperRect = CGRect(x: 0, y: midY, width: extent.width, height: extent.height - midY)
        let lowerRect = CGRect(x: 0, y: 0, width: extent.width, height: midY)

        guard let upper = maskedBrightness(of: personImage, with: mask, in: upperRect),
              let lower = maskedBrightness(of: personImage, with: mask, in: lowerRect) else {
            return DownlightResult(isPresent: false, gradient: 0)
        }

        let gradient = upper.brightness - lower.brightness
        return DownlightResult(isPresent: gradient > 0.03, gradient: gradient)
    }

    // MARK: - Layer 3: Shadow contrast

    private func analyzeShadowContrast(personImage: CIImage, mask: CIImage, extent: CGRect) -> ShadowResult {
        let midX = extent.midX
        let midY = extent.midY

        let quadrants = [
            CGRect(x: 0, y: midY, width: midX, height: extent.height - midY),
            CGRect(x: midX, y: midY, width: extent.width - midX, height: extent.height - midY),
            CGRect(x: 0, y: 0, width: midX, height: midY),
            CGRect(x: midX, y: 0, width: extent.width - midX, height: midY)
        ]

        let values = quadrants.compactMap {
            maskedBrightness(of: personImage, with: mask, in: $0)
        }
        .filter { $0.coverage > 0.04 }
        .map(\.brightness)

        guard values.count >= 3 else {
            return ShadowResult(contrast: 0)
        }

        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        let contrast = min(variance / 0.02, 1.0)

        return ShadowResult(contrast: contrast)
    }

    // MARK: - Layer 4: Backlighting detection

    private func analyzeBacklighting(
        frame: CIImage,
        mask: CIImage,
        personImage: CIImage,
        extent: CGRect
    ) -> Bool {
        guard let person = maskedBrightness(of: personImage, with: mask, in: extent) else {
            return false
        }

        let invertedMask = mask.applyingFilter("CIColorInvert")
        let black = CIImage(color: .black).cropped(to: extent)
        let bgImage = frame.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: black,
            kCIInputMaskImageKey: invertedMask
        ])

        let background = maskedBrightness(of: bgImage, with: invertedMask, in: extent)?.brightness
            ?? rawBrightness(of: bgImage, in: extent)

        return background > person.brightness + 0.25
    }

    // MARK: - Composite assessment

    private func compositeAssessment(
        exposure: ExposureResult,
        downlight: DownlightResult,
        shadows: ShadowResult,
        isBacklit: Bool
    ) -> Assessment {
        if isBacklit {
            return Assessment(quality: .poor, feedback: "Strong light behind you — try a different angle")
        }

        if exposure.isTooDark {
            // Rescue: strong directional light with definition can save borderline darkness
            if shadows.contrast > 0.35 && downlight.isPresent {
                return Assessment(quality: .fair, feedback: "Dark but good directional light — more light would help")
            }
            // Also rescue for high contrast without downlight (e.g. dramatic side lighting)
            if shadows.contrast > 0.2 {
                return Assessment(quality: .fair, feedback: "Dark but defined shadows — try adding more light")
            }
            return Assessment(quality: .poor, feedback: "Too dark — turn on more lights")
        }

        if exposure.isTooLight {
            return Assessment(quality: .poor, feedback: "Too bright — move away from the light source")
        }

        if downlight.isPresent && shadows.contrast > 0.35 {
            return Assessment(quality: .good, feedback: "Great light — shadows will show definition")
        }

        if downlight.isPresent && shadows.contrast > 0.18 {
            return Assessment(quality: .good, feedback: "Good overhead light")
        }

        if shadows.contrast > 0.22 {
            return Assessment(quality: .good, feedback: "Good directional light")
        }

        if shadows.contrast < 0.08 {
            return Assessment(quality: .fair, feedback: "Flat lighting — stand under a single overhead light")
        }

        if exposure.isMarginDark {
            return Assessment(quality: .fair, feedback: "A bit dark — find more light")
        }

        if exposure.isMarginBright {
            return Assessment(quality: .fair, feedback: "Slightly bright — adjust your position")
        }

        return Assessment(quality: .fair, feedback: "Try standing directly under an overhead light")
    }

    // MARK: - Core Image helpers

    private func maskedBrightness(of image: CIImage, with mask: CIImage, in rect: CGRect) -> MaskedBrightnessResult? {
        let croppedRect = rect.intersection(image.extent).intersection(mask.extent)
        guard !croppedRect.isNull, !croppedRect.isEmpty else { return nil }

        let coverage = rawBrightness(of: mask, in: croppedRect)
        guard coverage > 0.02 else { return nil }

        let measuredBrightness = min(rawBrightness(of: image, in: croppedRect) / coverage, 1.0)
        return MaskedBrightnessResult(brightness: measuredBrightness, coverage: coverage)
    }

    private func rawBrightness(of image: CIImage, in rect: CGRect) -> Double {
        let cropped = image.cropped(to: rect)
        guard let avgFilter = CIFilter(
            name: "CIAreaAverage",
            parameters: [
                kCIInputImageKey: cropped,
                kCIInputExtentKey: CIVector(
                    x: rect.origin.x,
                    y: rect.origin.y,
                    z: rect.size.width,
                    w: rect.size.height
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

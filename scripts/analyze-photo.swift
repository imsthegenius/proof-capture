#!/usr/bin/env swift
//
// analyze-photo.swift
// Runs the exact same LightingAnalyzer + PoseDetector logic from Proof Capture
// against static image files. Outputs detailed per-layer scores.
//
// Usage: swift scripts/analyze-photo.swift <image1.jpg> [image2.jpg] ...
//

import Foundation
import CoreImage
import Vision
import CoreGraphics
import AppKit

// MARK: - Types (mirrored from app)

enum QualityLevel: String {
    case good, fair, poor
}

enum Pose: String {
    case front, side, back
}

// MARK: - Lighting Analysis (exact copy of LightingAnalyzer logic)

struct LightingReport {
    let overallQuality: QualityLevel
    let overallFeedback: String
    let exposure: Double
    let isTooDark: Bool
    let isTooLight: Bool
    let downlightPresent: Bool
    let downlightGradient: Double
    let shadowContrast: Double
    let isBacklit: Bool
    let personDetected: Bool
}

func analyzeLighting(cgImage: CGImage) -> LightingReport {
    let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    let frame = CIImage(cgImage: cgImage)
    let extent = frame.extent

    // Person segmentation
    let segRequest = VNGeneratePersonSegmentationRequest()
    segRequest.qualityLevel = .balanced

    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
    do {
        try handler.perform([segRequest])
    } catch {
        let brightness = rawBrightness(of: frame, in: extent, context: ciContext)
        return LightingReport(
            overallQuality: .fair, overallFeedback: "Segmentation failed — fallback",
            exposure: brightness, isTooDark: brightness < 0.15, isTooLight: brightness > 0.82,
            downlightPresent: false, downlightGradient: 0, shadowContrast: 0,
            isBacklit: false, personDetected: false
        )
    }

    guard let segResult = segRequest.results?.first else {
        let brightness = rawBrightness(of: frame, in: extent, context: ciContext)
        return LightingReport(
            overallQuality: .fair, overallFeedback: "No person detected",
            exposure: brightness, isTooDark: brightness < 0.15, isTooLight: brightness > 0.82,
            downlightPresent: false, downlightGradient: 0, shadowContrast: 0,
            isBacklit: false, personDetected: false
        )
    }

    let maskImage = CIImage(cvPixelBuffer: segResult.pixelBuffer)
    let scaledMask = maskImage.transformed(by: CGAffineTransform(
        scaleX: extent.width / maskImage.extent.width,
        y: extent.height / maskImage.extent.height
    ))

    let black = CIImage(color: .black).cropped(to: extent)
    let personImage = frame.applyingFilter("CIBlendWithMask", parameters: [
        kCIInputBackgroundImageKey: black,
        kCIInputMaskImageKey: scaledMask
    ])

    // Layer 1: Exposure
    let personBrightness = maskedBrightness(of: personImage, with: scaledMask, in: extent, context: ciContext)?.brightness
        ?? rawBrightness(of: personImage, in: extent, context: ciContext)
    let isTooDark = personBrightness < 0.15
    let isTooLight = personBrightness > 0.82
    let isMarginDark = personBrightness < 0.25
    let isMarginBright = personBrightness > 0.72

    // Layer 2: Downlighting gradient
    let midY = extent.midY
    let upperRect = CGRect(x: 0, y: midY, width: extent.width, height: extent.height - midY)
    let lowerRect = CGRect(x: 0, y: 0, width: extent.width, height: midY)
    let upper = maskedBrightness(of: personImage, with: scaledMask, in: upperRect, context: ciContext)
    let lower = maskedBrightness(of: personImage, with: scaledMask, in: lowerRect, context: ciContext)
    let gradient: Double
    let downlightPresent: Bool
    if let u = upper, let l = lower {
        gradient = u.brightness - l.brightness
        downlightPresent = gradient > 0.03
    } else {
        gradient = 0
        downlightPresent = false
    }

    // Layer 3: Shadow contrast
    let midX = extent.midX
    let quadrants = [
        CGRect(x: 0, y: midY, width: midX, height: extent.height - midY),
        CGRect(x: midX, y: midY, width: extent.width - midX, height: extent.height - midY),
        CGRect(x: 0, y: 0, width: midX, height: midY),
        CGRect(x: midX, y: 0, width: extent.width - midX, height: midY)
    ]
    let quadValues = quadrants.compactMap {
        maskedBrightness(of: personImage, with: scaledMask, in: $0, context: ciContext)
    }
    .filter { $0.coverage > 0.04 }
    .map(\.brightness)

    let shadowContrast: Double
    if quadValues.count >= 3 {
        let mean = quadValues.reduce(0, +) / Double(quadValues.count)
        let variance = quadValues.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(quadValues.count)
        shadowContrast = min(variance / 0.02, 1.0)
    } else {
        shadowContrast = 0
    }

    // Layer 4: Backlighting
    let personCoverage = maskedBrightness(of: personImage, with: scaledMask, in: extent, context: ciContext)
    let invertedMask = scaledMask.applyingFilter("CIColorInvert")
    let bgImage = frame.applyingFilter("CIBlendWithMask", parameters: [
        kCIInputBackgroundImageKey: black,
        kCIInputMaskImageKey: invertedMask
    ])
    let bgBrightness = maskedBrightness(of: bgImage, with: invertedMask, in: extent, context: ciContext)?.brightness
        ?? rawBrightness(of: bgImage, in: extent, context: ciContext)
    let isBacklit = personCoverage != nil && bgBrightness > (personCoverage!.brightness + 0.25)

    // Composite assessment (exact same logic as LightingAnalyzer.compositeAssessment)
    let quality: QualityLevel
    let feedback: String

    if isBacklit {
        quality = .poor; feedback = "Strong light behind you — try a different angle"
    } else if isTooDark {
        if shadowContrast > 0.35 && downlightPresent {
            quality = .fair; feedback = "Dark but good directional light — more light would help"
        } else if shadowContrast > 0.2 && personBrightness >= 0.10 {
            quality = .fair; feedback = "Dark but defined shadows — try adding more light"
        } else {
            quality = .poor; feedback = "Too dark — turn on more lights"
        }
    } else if isTooLight {
        quality = .poor; feedback = "Too bright — move away from the light source"
    } else if downlightPresent && shadowContrast > 0.35 {
        quality = .good; feedback = "Great light — shadows will show definition"
    } else if downlightPresent && shadowContrast > 0.18 {
        quality = .good; feedback = "Good overhead light"
    } else if shadowContrast > 0.22 {
        quality = .good; feedback = "Good directional light"
    } else if shadowContrast < 0.08 {
        quality = .fair; feedback = "Flat lighting — stand under a single overhead light"
    } else if isMarginDark {
        quality = .fair; feedback = "A bit dark — find more light"
    } else if isMarginBright {
        quality = .fair; feedback = "Slightly bright — adjust your position"
    } else {
        quality = .fair; feedback = "Try standing directly under an overhead light"
    }

    return LightingReport(
        overallQuality: quality, overallFeedback: feedback,
        exposure: personBrightness, isTooDark: isTooDark, isTooLight: isTooLight,
        downlightPresent: downlightPresent, downlightGradient: gradient,
        shadowContrast: shadowContrast, isBacklit: isBacklit, personDetected: true
    )
}

// MARK: - Pose Analysis (extracted from PoseDetector)

struct PoseReport {
    let bodyDetected: Bool
    let jointCount: Int
    let positionQuality: QualityLevel
    let positionFeedback: String
    let detectedOrientation: Pose?
    let armsRelaxed: Bool
    let bodyRect: CGRect
}

func analyzePose(cgImage: CGImage) -> PoseReport {
    let request = VNDetectHumanBodyPoseRequest()
    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)

    do {
        try handler.perform([request])
    } catch {
        return PoseReport(bodyDetected: false, jointCount: 0, positionQuality: .poor,
                          positionFeedback: "Vision error", detectedOrientation: nil,
                          armsRelaxed: false, bodyRect: .zero)
    }

    guard let observation = request.results?.first else {
        return PoseReport(bodyDetected: false, jointCount: 0, positionQuality: .poor,
                          positionFeedback: "No body detected", detectedOrientation: nil,
                          armsRelaxed: false, bodyRect: .zero)
    }

    // Collect joints
    let trackingJoints: [VNHumanBodyPoseObservation.JointName] = [
        .nose, .neck, .leftShoulder, .rightShoulder,
        .leftHip, .rightHip, .leftAnkle, .rightAnkle
    ]

    var points: [CGPoint] = []
    for joint in trackingJoints {
        if let point = try? observation.recognizedPoint(joint), point.confidence > 0.3 {
            points.append(point.location)
        }
    }

    guard points.count >= 3 else {
        return PoseReport(bodyDetected: true, jointCount: points.count, positionQuality: .poor,
                          positionFeedback: "Can't see full body — \(points.count) joints visible",
                          detectedOrientation: nil, armsRelaxed: false, bodyRect: .zero)
    }

    // Bounding box
    let xs = points.map(\.x)
    let ys = points.map(\.y)
    let rect = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)

    // Ankle confidence gate (TWO-515)
    let leftAnkleConf = (try? observation.recognizedPoint(.leftAnkle))?.confidence ?? 0
    let rightAnkleConf = (try? observation.recognizedPoint(.rightAnkle))?.confidence ?? 0
    let anklesDetected = leftAnkleConf > 0.3 || rightAnkleConf > 0.3

    let assessmentRect: CGRect
    if !anklesDetected && rect.height > 0 {
        let estimatedFullHeight = min(rect.height / 0.55, 1.0)
        assessmentRect = CGRect(
            x: rect.origin.x,
            y: max(0, rect.origin.y - (estimatedFullHeight - rect.height)),
            width: rect.width,
            height: estimatedFullHeight
        )
    } else {
        assessmentRect = rect
    }

    // Position assessment (using assessmentRect for distance, rect for display)
    let centerX = assessmentRect.midX
    let bodyHeight = assessmentRect.height
    var issues: [String] = []
    if bodyHeight > 0.85 { issues.append("Too close (height \(String(format: "%.2f", bodyHeight)))") }
    else if bodyHeight < 0.25 { issues.append("Too far (height \(String(format: "%.2f", bodyHeight)))") }
    else if bodyHeight < 0.40 { issues.append("Tip: step closer (height \(String(format: "%.2f", bodyHeight)))") }
    if centerX < 0.35 { issues.append("Off-center left (x \(String(format: "%.2f", centerX)))") }
    else if centerX > 0.65 { issues.append("Off-center right (x \(String(format: "%.2f", centerX)))") }

    let posQuality: QualityLevel = issues.isEmpty ? .good : (issues.count == 1 ? .fair : .poor)
    let posFeedback = issues.isEmpty ? "Good position" : issues.joined(separator: " · ")

    // Orientation detection (matches PoseDetector.detectOrientation)
    let nose = try? observation.recognizedPoint(.nose)
    let leftEar = try? observation.recognizedPoint(.leftEar)
    let rightEar = try? observation.recognizedPoint(.rightEar)
    let leftShoulder = try? observation.recognizedPoint(.leftShoulder)
    let rightShoulder = try? observation.recognizedPoint(.rightShoulder)
    let leftHip = try? observation.recognizedPoint(.leftHip)
    let rightHip = try? observation.recognizedPoint(.rightHip)

    let noseConf = nose?.confidence ?? 0
    let leftEarConf = leftEar?.confidence ?? 0
    let rightEarConf = rightEar?.confidence ?? 0
    let leftShoulderConf = leftShoulder?.confidence ?? 0
    let rightShoulderConf = rightShoulder?.confidence ?? 0
    let leftHipConf = leftHip?.confidence ?? 0
    let rightHipConf = rightHip?.confidence ?? 0

    let shoulderWidth: CGFloat = {
        guard leftShoulderConf > 0.3, rightShoulderConf > 0.3,
              let ls = leftShoulder, let rs = rightShoulder else { return 0 }
        return abs(ls.location.x - rs.location.x)
    }()

    let hipWidth: CGFloat = {
        guard leftHipConf > 0.3, rightHipConf > 0.3,
              let lh = leftHip, let rh = rightHip else { return 0 }
        return abs(lh.location.x - rh.location.x)
    }()

    let earAsymmetry = abs(leftEarConf - rightEarConf)

    let orientation: Pose?
    if noseConf < 0.1 {
        orientation = .back
    } else if earAsymmetry > 0.3 && shoulderWidth > 0 && shoulderWidth < 0.20 {
        orientation = .side
    } else if shoulderWidth > 0 && shoulderWidth < 0.20 && hipWidth > 0 && hipWidth < 0.12 {
        orientation = .side
    } else if (leftShoulderConf > 0.3) != (rightShoulderConf > 0.3) {
        orientation = .side
    } else if noseConf > 0.15 && shoulderWidth > 0.10 {
        orientation = .front
    } else if noseConf > 0.15 && hipWidth > 0.10 {
        orientation = .front
    } else if noseConf >= 0.1 {
        orientation = .front  // low-light fallback
    } else {
        orientation = nil
    }

    // Arms check
    let armsRelaxed: Bool = {
        guard let lw = try? observation.recognizedPoint(.leftWrist),
              let rw = try? observation.recognizedPoint(.rightWrist),
              let lh = try? observation.recognizedPoint(.leftHip),
              let rh = try? observation.recognizedPoint(.rightHip),
              lw.confidence > 0.3, rw.confidence > 0.3,
              lh.confidence > 0.3, rh.confidence > 0.3 else {
            return true // Can't see wrists = probably back pose
        }
        let leftYOK = abs(lw.location.y - lh.location.y) < 0.08
        let rightYOK = abs(rw.location.y - rh.location.y) < 0.08
        let leftXOK = abs(lw.location.x - lh.location.x) < 0.06
        let rightXOK = abs(rw.location.x - rh.location.x) < 0.06
        return leftYOK && rightYOK && leftXOK && rightXOK
    }()

    return PoseReport(
        bodyDetected: true, jointCount: points.count, positionQuality: posQuality,
        positionFeedback: posFeedback, detectedOrientation: orientation,
        armsRelaxed: armsRelaxed, bodyRect: rect
    )
}

// MARK: - Core Image Helpers (exact copies from LightingAnalyzer)

struct MaskedBrightnessResult {
    let brightness: Double
    let coverage: Double
}

func maskedBrightness(of image: CIImage, with mask: CIImage, in rect: CGRect, context: CIContext) -> MaskedBrightnessResult? {
    let croppedRect = rect.intersection(image.extent).intersection(mask.extent)
    guard !croppedRect.isNull, !croppedRect.isEmpty else { return nil }

    let coverage = rawBrightness(of: mask, in: croppedRect, context: context)
    guard coverage > 0.02 else { return nil }

    let measured = min(rawBrightness(of: image, in: croppedRect, context: context) / coverage, 1.0)
    return MaskedBrightnessResult(brightness: measured, coverage: coverage)
}

func rawBrightness(of image: CIImage, in rect: CGRect, context: CIContext) -> Double {
    let cropped = image.cropped(to: rect)
    guard let avgFilter = CIFilter(
        name: "CIAreaAverage",
        parameters: [
            kCIInputImageKey: cropped,
            kCIInputExtentKey: CIVector(x: rect.origin.x, y: rect.origin.y, z: rect.size.width, w: rect.size.height)
        ]
    ),
    let output = avgFilter.outputImage else { return 0.5 }

    var pixel = [UInt8](repeating: 0, count: 4)
    context.render(output, toBitmap: &pixel, rowBytes: 4,
                   bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                   format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())

    let r = Double(pixel[0]) / 255.0
    let g = Double(pixel[1]) / 255.0
    let b = Double(pixel[2]) / 255.0
    return 0.299 * r + 0.587 * g + 0.114 * b
}

// MARK: - Main

func analyzeImage(path: String) {
    guard let nsImage = NSImage(contentsOfFile: path) else {
        print("  ERROR: Could not load image at \(path)")
        return
    }

    guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("  ERROR: Could not convert to CGImage")
        return
    }

    let filename = (path as NSString).lastPathComponent
    let dims = "\(cgImage.width)x\(cgImage.height)"

    print("=" .padding(toLength: 72, withPad: "=", startingAt: 0))
    print("  \(filename) (\(dims))")
    print("=" .padding(toLength: 72, withPad: "=", startingAt: 0))

    // Lighting analysis
    print("\n  LIGHTING ANALYSIS")
    print("  -----------------")
    let lighting = analyzeLighting(cgImage: cgImage)
    print("  Person detected:    \(lighting.personDetected)")
    print("  Overall:            \(lighting.overallQuality.rawValue.uppercased()) — \"\(lighting.overallFeedback)\"")
    print("")
    print("  Layer 1 — Exposure")
    print("    Person brightness: \(String(format: "%.3f", lighting.exposure))")
    print("    Too dark (<0.15):  \(lighting.isTooDark)")
    print("    Too light (>0.82): \(lighting.isTooLight)")
    print("")
    print("  Layer 2 — Downlighting")
    print("    Gradient (upper-lower): \(String(format: "%+.4f", lighting.downlightGradient))")
    print("    Downlight present (>0.03): \(lighting.downlightPresent)")
    print("")
    print("  Layer 3 — Shadow Contrast")
    print("    Contrast score: \(String(format: "%.4f", lighting.shadowContrast))")
    print("    Good (>0.25): \(lighting.shadowContrast > 0.25)")
    print("    Great (>0.5): \(lighting.shadowContrast > 0.5)")
    print("    Flat (<0.15): \(lighting.shadowContrast < 0.15)")
    print("")
    print("  Layer 4 — Backlighting")
    print("    Backlit: \(lighting.isBacklit)")

    // Pose analysis
    print("\n  POSE ANALYSIS")
    print("  -------------")
    let pose = analyzePose(cgImage: cgImage)
    print("  Body detected:      \(pose.bodyDetected)")
    print("  Joints visible:     \(pose.jointCount)/8")
    print("  Position:           \(pose.positionQuality.rawValue.uppercased()) — \"\(pose.positionFeedback)\"")
    print("  Orientation:        \(pose.detectedOrientation?.rawValue ?? "unknown")")
    print("  Arms relaxed:       \(pose.armsRelaxed)")
    if pose.bodyDetected {
        print("  Body rect:          x=\(String(format: "%.2f", pose.bodyRect.origin.x)) y=\(String(format: "%.2f", pose.bodyRect.origin.y)) w=\(String(format: "%.2f", pose.bodyRect.width)) h=\(String(format: "%.2f", pose.bodyRect.height))")
    }
    print("")
}

// Run
let args = CommandLine.arguments.dropFirst()
if args.isEmpty {
    print("Usage: swift scripts/analyze-photo.swift <image1.jpg> [image2.jpg] ...")
    print("")
    print("Runs the exact Proof Capture lighting + pose analysis pipeline")
    print("against static images. Outputs per-layer scores.")
    exit(1)
}

for path in args {
    let resolvedPath = (path as NSString).expandingTildeInPath
    let fullPath = resolvedPath.hasPrefix("/") ? resolvedPath : FileManager.default.currentDirectoryPath + "/" + resolvedPath
    analyzeImage(path: fullPath)
}

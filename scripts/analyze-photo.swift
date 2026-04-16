#!/usr/bin/env swift
//
// analyze-photo.swift
// Runs the Checkd live lock scoring pipeline against static image files.
//

import AppKit
import CoreGraphics
import CoreImage
import Foundation
import Vision

enum QualityLevel: String, Codable {
    case good
    case fair
    case poor
}

enum Pose: String, Codable {
    case front
    case side
    case back
}

enum OutputFormat: String {
    case human
    case json
    case csv
}

struct CLIOptions {
    var format: OutputFormat = .human
    var paths: [String] = []
}

struct LightingReport: Codable {
    let overallQuality: QualityLevel
    let overallFeedback: String
    let exposure: Double
    let isTooDark: Bool
    let isTooLight: Bool
    let isMarginDark: Bool
    let isMarginBright: Bool
    let downlightPresent: Bool
    let downlightGradient: Double
    let shadowContrast: Double
    let isBacklit: Bool
    let personDetected: Bool
}

struct PoseReport: Codable {
    let bodyDetected: Bool
    let jointCount: Int
    let positionQuality: QualityLevel
    let positionFeedback: String
    let detectedOrientation: Pose?
    let armsRelaxed: Bool
    let bodyRectX: Double
    let bodyRectY: Double
    let bodyRectWidth: Double
    let bodyRectHeight: Double
    let bodyHeight: Double
    let centerX: Double
}

struct AnalysisRecord: Codable {
    let path: String
    let filename: String
    let expectedPose: Pose?
    let poseMatchesExpected: Bool?
    let lockable: Bool
    let lighting: LightingReport
    let pose: PoseReport
}

struct MaskedBrightnessResult {
    let brightness: Double
    let coverage: Double
}

private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

func parseOptions(arguments: [String]) -> CLIOptions {
    var options = CLIOptions()
    var index = 0

    while index < arguments.count {
        let argument = arguments[index]
        if argument == "--format" {
            guard index + 1 < arguments.count,
                  let format = OutputFormat(rawValue: arguments[index + 1]) else {
                fputs("Invalid or missing value for --format. Use human, json, or csv.\n", stderr)
                exit(1)
            }
            options.format = format
            index += 2
            continue
        }

        options.paths.append(argument)
        index += 1
    }

    return options
}

func inferExpectedPose(from filename: String) -> Pose? {
    let stem = ((filename as NSString).deletingPathExtension as NSString).lowercased
    if stem.hasPrefix("front_") { return .front }
    if stem.hasPrefix("side_") { return .side }
    if stem.hasPrefix("back_") { return .back }
    return nil
}

func analyzeLighting(cgImage: CGImage) -> LightingReport {
    let frame = CIImage(cgImage: cgImage)
    let extent = frame.extent

    let segRequest = VNGeneratePersonSegmentationRequest()
    segRequest.qualityLevel = .balanced

    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
    do {
        try handler.perform([segRequest])
    } catch {
        let brightness = rawBrightness(of: frame, in: extent, context: ciContext)
        return LightingReport(
            overallQuality: .fair,
            overallFeedback: "Segmentation failed — fallback",
            exposure: brightness,
            isTooDark: brightness < 0.15,
            isTooLight: brightness > 0.82,
            isMarginDark: brightness < 0.25,
            isMarginBright: brightness > 0.72,
            downlightPresent: false,
            downlightGradient: 0,
            shadowContrast: 0,
            isBacklit: false,
            personDetected: false
        )
    }

    guard let segResult = segRequest.results?.first else {
        let brightness = rawBrightness(of: frame, in: extent, context: ciContext)
        return LightingReport(
            overallQuality: .fair,
            overallFeedback: "No person detected",
            exposure: brightness,
            isTooDark: brightness < 0.15,
            isTooLight: brightness > 0.82,
            isMarginDark: brightness < 0.25,
            isMarginBright: brightness > 0.72,
            downlightPresent: false,
            downlightGradient: 0,
            shadowContrast: 0,
            isBacklit: false,
            personDetected: false
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

    let personBrightness = maskedBrightness(
        of: personImage,
        with: scaledMask,
        in: extent,
        context: ciContext
    )?.brightness ?? rawBrightness(of: personImage, in: extent, context: ciContext)

    let isTooDark = personBrightness < 0.15
    let isTooLight = personBrightness > 0.82
    let isMarginDark = personBrightness < 0.25
    let isMarginBright = personBrightness > 0.72

    let midY = extent.midY
    let upperRect = CGRect(x: 0, y: midY, width: extent.width, height: extent.height - midY)
    let lowerRect = CGRect(x: 0, y: 0, width: extent.width, height: midY)
    let upper = maskedBrightness(of: personImage, with: scaledMask, in: upperRect, context: ciContext)
    let lower = maskedBrightness(of: personImage, with: scaledMask, in: lowerRect, context: ciContext)
    let downlightGradient: Double
    let downlightPresent: Bool
    if let upper, let lower {
        downlightGradient = upper.brightness - lower.brightness
        downlightPresent = downlightGradient > 0.03
    } else {
        downlightGradient = 0
        downlightPresent = false
    }

    let midX = extent.midX
    let quadrants = [
        CGRect(x: 0, y: midY, width: midX, height: extent.height - midY),
        CGRect(x: midX, y: midY, width: extent.width - midX, height: extent.height - midY),
        CGRect(x: 0, y: 0, width: midX, height: midY),
        CGRect(x: midX, y: 0, width: extent.width - midX, height: midY)
    ]
    let values = quadrants.compactMap {
        maskedBrightness(of: personImage, with: scaledMask, in: $0, context: ciContext)
    }
    .filter { $0.coverage > 0.04 }
    .map(\.brightness)

    let shadowContrast: Double
    if values.count >= 3 {
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        shadowContrast = min(variance / 0.02, 1.0)
    } else {
        shadowContrast = 0
    }

    let personCoverage = maskedBrightness(of: personImage, with: scaledMask, in: extent, context: ciContext)
    let invertedMask = scaledMask.applyingFilter("CIColorInvert")
    let bgImage = frame.applyingFilter("CIBlendWithMask", parameters: [
        kCIInputBackgroundImageKey: black,
        kCIInputMaskImageKey: invertedMask
    ])
    let backgroundBrightness = maskedBrightness(of: bgImage, with: invertedMask, in: extent, context: ciContext)?.brightness
        ?? rawBrightness(of: bgImage, in: extent, context: ciContext)
    let isBacklit = personCoverage != nil &&
        personCoverage!.brightness < 0.20 &&
        backgroundBrightness > (personCoverage!.brightness + 0.25)

    let overallQuality: QualityLevel
    let overallFeedback: String

    if isBacklit {
        overallQuality = .poor
        overallFeedback = "Strong light behind you — try a different angle"
    } else if isTooDark {
        if shadowContrast > 0.35 && downlightPresent {
            overallQuality = .fair
            overallFeedback = "Dark but good directional light — more light would help"
        } else if shadowContrast > 0.2 && personBrightness >= 0.10 {
            overallQuality = .fair
            overallFeedback = "Dark but defined shadows — try adding more light"
        } else {
            overallQuality = .poor
            overallFeedback = "Too dark — turn on more lights"
        }
    } else if isTooLight {
        overallQuality = .poor
        overallFeedback = "Too bright — move away from the light source"
    } else if downlightPresent && shadowContrast > 0.35 {
        overallQuality = .good
        overallFeedback = "Great light — shadows will show definition"
    } else if downlightPresent && shadowContrast > 0.18 {
        overallQuality = .good
        overallFeedback = "Good overhead light"
    } else if shadowContrast > 0.22 {
        overallQuality = .good
        overallFeedback = "Good directional light"
    } else if shadowContrast < 0.08 {
        overallQuality = .fair
        overallFeedback = "Flat lighting — stand under a single overhead light"
    } else if isMarginDark {
        overallQuality = .fair
        overallFeedback = "A bit dark — find more light"
    } else if isMarginBright {
        overallQuality = .fair
        overallFeedback = "Slightly bright — adjust your position"
    } else {
        overallQuality = .fair
        overallFeedback = "Try standing directly under an overhead light"
    }

    return LightingReport(
        overallQuality: overallQuality,
        overallFeedback: overallFeedback,
        exposure: personBrightness,
        isTooDark: isTooDark,
        isTooLight: isTooLight,
        isMarginDark: isMarginDark,
        isMarginBright: isMarginBright,
        downlightPresent: downlightPresent,
        downlightGradient: downlightGradient,
        shadowContrast: shadowContrast,
        isBacklit: isBacklit,
        personDetected: true
    )
}

func analyzePose(cgImage: CGImage) -> PoseReport {
    let request = VNDetectHumanBodyPoseRequest()
    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)

    do {
        try handler.perform([request])
    } catch {
        return PoseReport(
            bodyDetected: false,
            jointCount: 0,
            positionQuality: .poor,
            positionFeedback: "Vision error",
            detectedOrientation: nil,
            armsRelaxed: false,
            bodyRectX: 0,
            bodyRectY: 0,
            bodyRectWidth: 0,
            bodyRectHeight: 0,
            bodyHeight: 0,
            centerX: 0
        )
    }

    guard let observation = request.results?.first else {
        return PoseReport(
            bodyDetected: false,
            jointCount: 0,
            positionQuality: .poor,
            positionFeedback: "No body detected",
            detectedOrientation: nil,
            armsRelaxed: false,
            bodyRectX: 0,
            bodyRectY: 0,
            bodyRectWidth: 0,
            bodyRectHeight: 0,
            bodyHeight: 0,
            centerX: 0
        )
    }

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
        return PoseReport(
            bodyDetected: true,
            jointCount: points.count,
            positionQuality: .poor,
            positionFeedback: "Can't see full body",
            detectedOrientation: nil,
            armsRelaxed: false,
            bodyRectX: 0,
            bodyRectY: 0,
            bodyRectWidth: 0,
            bodyRectHeight: 0,
            bodyHeight: 0,
            centerX: 0
        )
    }

    let xs = points.map(\.x)
    let ys = points.map(\.y)
    let rect = CGRect(
        x: xs.min() ?? 0,
        y: ys.min() ?? 0,
        width: (xs.max() ?? 0) - (xs.min() ?? 0),
        height: (ys.max() ?? 0) - (ys.min() ?? 0)
    )

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

    let centerX = assessmentRect.midX
    let bodyHeight = assessmentRect.height
    var issues: [String] = []
    if bodyHeight > 0.85 {
        issues.append("Step back")
    } else if bodyHeight < 0.25 {
        issues.append("Move closer")
    } else if bodyHeight < 0.40 {
        issues.append("Step a bit closer for best framing")
    }
    if centerX < 0.35 {
        issues.append("Move right")
    } else if centerX > 0.65 {
        issues.append("Move left")
    }

    let positionQuality: QualityLevel
    let positionFeedback: String
    switch issues.count {
    case 0:
        positionQuality = .good
        positionFeedback = "Good position"
    case 1:
        positionQuality = .fair
        positionFeedback = issues[0]
    default:
        positionQuality = .poor
        positionFeedback = issues.joined(separator: " · ")
    }

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
              let leftShoulder, let rightShoulder else { return 0 }
        return abs(leftShoulder.location.x - rightShoulder.location.x)
    }()

    let hipWidth: CGFloat = {
        guard leftHipConf > 0.3, rightHipConf > 0.3,
              let leftHip, let rightHip else { return 0 }
        return abs(leftHip.location.x - rightHip.location.x)
    }()

    let earAsymmetry = abs(leftEarConf - rightEarConf)

    let detectedOrientation: Pose?
    if noseConf < 0.1 {
        detectedOrientation = .back
    } else if earAsymmetry > 0.3 && shoulderWidth > 0 && shoulderWidth < 0.20 {
        detectedOrientation = .side
    } else if shoulderWidth > 0 && shoulderWidth < 0.20 && hipWidth > 0 && hipWidth < 0.12 {
        detectedOrientation = .side
    } else if (leftShoulderConf > 0.3) != (rightShoulderConf > 0.3) {
        detectedOrientation = .side
    } else if noseConf > 0.15 && shoulderWidth > 0.10 {
        detectedOrientation = .front
    } else if noseConf > 0.15 && hipWidth > 0.10 {
        detectedOrientation = .front
    } else if noseConf >= 0.1 {
        detectedOrientation = .front
    } else {
        detectedOrientation = nil
    }

    let armsRelaxed = checkArmsRelaxed(observation: observation)

    return PoseReport(
        bodyDetected: true,
        jointCount: points.count,
        positionQuality: positionQuality,
        positionFeedback: positionFeedback,
        detectedOrientation: detectedOrientation,
        armsRelaxed: armsRelaxed,
        bodyRectX: rect.origin.x,
        bodyRectY: rect.origin.y,
        bodyRectWidth: rect.width,
        bodyRectHeight: rect.height,
        bodyHeight: bodyHeight,
        centerX: centerX
    )
}

func checkArmsRelaxed(observation: VNHumanBodyPoseObservation) -> Bool {
    guard let leftWrist = try? observation.recognizedPoint(.leftWrist),
          let rightWrist = try? observation.recognizedPoint(.rightWrist),
          let leftHip = try? observation.recognizedPoint(.leftHip),
          let rightHip = try? observation.recognizedPoint(.rightHip),
          leftWrist.confidence > 0.3,
          rightWrist.confidence > 0.3,
          leftHip.confidence > 0.3,
          rightHip.confidence > 0.3 else {
        return true
    }

    let leftYOK = abs(leftWrist.location.y - leftHip.location.y) < 0.20
    let rightYOK = abs(rightWrist.location.y - rightHip.location.y) < 0.20
    let leftXOK = abs(leftWrist.location.x - leftHip.location.x) < 0.18
    let rightXOK = abs(rightWrist.location.x - rightHip.location.x) < 0.18

    if let leftElbow = try? observation.recognizedPoint(.leftElbow),
       let leftShoulder = try? observation.recognizedPoint(.leftShoulder),
       leftElbow.confidence > 0.3,
       leftShoulder.confidence > 0.3 {
        let angle = angleBetween(
            p1: leftShoulder.location,
            vertex: leftElbow.location,
            p2: leftWrist.location
        )
        if angle < 120 {
            return false
        }
    }

    return leftYOK && rightYOK && leftXOK && rightXOK
}

func angleBetween(p1: CGPoint, vertex: CGPoint, p2: CGPoint) -> CGFloat {
    let vector1 = CGPoint(x: p1.x - vertex.x, y: p1.y - vertex.y)
    let vector2 = CGPoint(x: p2.x - vertex.x, y: p2.y - vertex.y)
    let dot = vector1.x * vector2.x + vector1.y * vector2.y
    let magnitude1 = sqrt(vector1.x * vector1.x + vector1.y * vector1.y)
    let magnitude2 = sqrt(vector2.x * vector2.x + vector2.y * vector2.y)
    guard magnitude1 > 0, magnitude2 > 0 else { return 180 }
    let cosAngle = dot / (magnitude1 * magnitude2)
    return acos(min(max(cosAngle, -1), 1)) * 180 / .pi
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
    context.render(
        output,
        toBitmap: &pixel,
        rowBytes: 4,
        bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
        format: .RGBA8,
        colorSpace: CGColorSpaceCreateDeviceRGB()
    )

    let red = Double(pixel[0]) / 255.0
    let green = Double(pixel[1]) / 255.0
    let blue = Double(pixel[2]) / 255.0
    return 0.299 * red + 0.587 * green + 0.114 * blue
}

func analyzeImage(path: String) -> AnalysisRecord? {
    guard let nsImage = NSImage(contentsOfFile: path),
          let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fputs("Could not load image at \(path)\n", stderr)
        return nil
    }

    let filename = (path as NSString).lastPathComponent
    let expectedPose = inferExpectedPose(from: filename)
    let lighting = analyzeLighting(cgImage: cgImage)
    let pose = analyzePose(cgImage: cgImage)
    let poseMatchesExpected = expectedPose.map { $0 == pose.detectedOrientation }
    let lockable = pose.bodyDetected &&
        pose.positionQuality == .good &&
        pose.armsRelaxed &&
        lighting.overallQuality != .poor &&
        (poseMatchesExpected ?? (pose.detectedOrientation != nil))

    return AnalysisRecord(
        path: path,
        filename: filename,
        expectedPose: expectedPose,
        poseMatchesExpected: poseMatchesExpected,
        lockable: lockable,
        lighting: lighting,
        pose: pose
    )
}

func printHuman(record: AnalysisRecord) {
    print(String(repeating: "=", count: 72))
    print("  \(record.filename)")
    print(String(repeating: "=", count: 72))
    print("")
    print("  LOCK")
    print("  ----")
    print("  Expected pose:       \(record.expectedPose?.rawValue ?? "unknown")")
    print("  Pose matches:        \(record.poseMatchesExpected.map(String.init(describing:)) ?? "n/a")")
    print("  Lockable:            \(record.lockable)")
    print("")
    print("  LIGHTING")
    print("  --------")
    print("  Overall:             \(record.lighting.overallQuality.rawValue.uppercased()) — \"\(record.lighting.overallFeedback)\"")
    print("  Exposure:            \(String(format: "%.3f", record.lighting.exposure))")
    print("  Too dark / light:    \(record.lighting.isTooDark) / \(record.lighting.isTooLight)")
    print("  Margin dark / light: \(record.lighting.isMarginDark) / \(record.lighting.isMarginBright)")
    print("  Downlight gradient:  \(String(format: "%+.4f", record.lighting.downlightGradient))")
    print("  Downlight present:   \(record.lighting.downlightPresent)")
    print("  Shadow contrast:     \(String(format: "%.4f", record.lighting.shadowContrast))")
    print("  Backlit:             \(record.lighting.isBacklit)")
    print("")
    print("  POSE")
    print("  ----")
    print("  Body detected:       \(record.pose.bodyDetected)")
    print("  Joints visible:      \(record.pose.jointCount)/8")
    print("  Position:            \(record.pose.positionQuality.rawValue.uppercased()) — \"\(record.pose.positionFeedback)\"")
    print("  Orientation:         \(record.pose.detectedOrientation?.rawValue ?? "unknown")")
    print("  Arms relaxed:        \(record.pose.armsRelaxed)")
    print("  Body height:         \(String(format: "%.3f", record.pose.bodyHeight))")
    print("  Body center x:       \(String(format: "%.3f", record.pose.centerX))")
    print("  Body rect:           x=\(String(format: "%.3f", record.pose.bodyRectX)) y=\(String(format: "%.3f", record.pose.bodyRectY)) w=\(String(format: "%.3f", record.pose.bodyRectWidth)) h=\(String(format: "%.3f", record.pose.bodyRectHeight))")
    print("")
}

func csvEscape(_ value: String) -> String {
    if value.contains(",") || value.contains("\"") || value.contains("\n") {
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    return value
}

func printCSV(records: [AnalysisRecord]) {
    let headers = [
        "path", "filename", "expected_pose", "pose_matches_expected", "lockable",
        "lighting_quality", "lighting_feedback", "exposure", "is_too_dark", "is_too_light",
        "is_margin_dark", "is_margin_bright", "downlight_present", "downlight_gradient",
        "shadow_contrast", "is_backlit", "person_detected",
        "body_detected", "joint_count", "position_quality", "position_feedback",
        "detected_orientation", "arms_relaxed", "body_height", "center_x",
        "body_rect_x", "body_rect_y", "body_rect_width", "body_rect_height"
    ]
    print(headers.joined(separator: ","))

    for record in records {
        let row = [
            record.path,
            record.filename,
            record.expectedPose?.rawValue ?? "",
            record.poseMatchesExpected.map(String.init(describing:)) ?? "",
            String(record.lockable),
            record.lighting.overallQuality.rawValue,
            record.lighting.overallFeedback,
            String(record.lighting.exposure),
            String(record.lighting.isTooDark),
            String(record.lighting.isTooLight),
            String(record.lighting.isMarginDark),
            String(record.lighting.isMarginBright),
            String(record.lighting.downlightPresent),
            String(record.lighting.downlightGradient),
            String(record.lighting.shadowContrast),
            String(record.lighting.isBacklit),
            String(record.lighting.personDetected),
            String(record.pose.bodyDetected),
            String(record.pose.jointCount),
            record.pose.positionQuality.rawValue,
            record.pose.positionFeedback,
            record.pose.detectedOrientation?.rawValue ?? "",
            String(record.pose.armsRelaxed),
            String(record.pose.bodyHeight),
            String(record.pose.centerX),
            String(record.pose.bodyRectX),
            String(record.pose.bodyRectY),
            String(record.pose.bodyRectWidth),
            String(record.pose.bodyRectHeight)
        ]
        print(row.map(csvEscape).joined(separator: ","))
    }
}

let options = parseOptions(arguments: Array(CommandLine.arguments.dropFirst()))
guard !options.paths.isEmpty else {
    print("Usage: swift scripts/analyze-photo.swift [--format human|json|csv] <image1> [image2] ...")
    exit(1)
}

let records = options.paths.compactMap { rawPath -> AnalysisRecord? in
    let expanded = (rawPath as NSString).expandingTildeInPath
    let fullPath = expanded.hasPrefix("/") ? expanded : FileManager.default.currentDirectoryPath + "/" + expanded
    return analyzeImage(path: fullPath)
}

switch options.format {
case .human:
    for record in records {
        printHuman(record: record)
    }
case .json:
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(records),
       let string = String(data: data, encoding: .utf8) {
        print(string)
    } else {
        fputs("Failed to encode JSON output.\n", stderr)
        exit(1)
    }
case .csv:
    printCSV(records: records)
}

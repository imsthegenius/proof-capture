// evaluate-scorer-main.swift
// Gold-set evaluation harness that calls the real CheckInScorer.
// Compiled alongside the actual app source files by scripts/evaluate-scorer.
//
// Usage: scripts/evaluate-scorer [manifest.csv]
//

import Foundation
import AppKit
import CoreGraphics

// MARK: - Gold label

struct GoldLabel {
    let filename: String
    let expectedPose: Pose
    let goldVerdict: String   // "keep", "warn", "retakeRecommended"
    let notes: String
}

func parseManifest(_ path: String) -> [GoldLabel] {
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("ERROR: Cannot read manifest at \(path)")
        exit(1)
    }
    let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
    guard lines.count > 1 else { print("ERROR: Empty manifest"); exit(1) }

    return lines.dropFirst().compactMap { line in
        let cols = line.components(separatedBy: ",")
        guard cols.count >= 3 else { return nil }
        let poseStr = cols[1].trimmingCharacters(in: .whitespaces)
        let pose: Pose
        switch poseStr {
        case "front": pose = .front
        case "side": pose = .side
        case "back": pose = .back
        default: return nil
        }
        return GoldLabel(
            filename: cols[0].trimmingCharacters(in: .whitespaces),
            expectedPose: pose,
            goldVerdict: cols[2].trimmingCharacters(in: .whitespaces),
            notes: cols.count > 8 ? cols[8].trimmingCharacters(in: .whitespaces) : ""
        )
    }
}

// MARK: - Main

func runEvaluation() async {
    let args = CommandLine.arguments.dropFirst()
    let baseDir = FileManager.default.currentDirectoryPath

    let manifestPath: String
    if let first = args.first {
        manifestPath = first.hasPrefix("/") ? first : baseDir + "/" + first
    } else {
        manifestPath = baseDir + "/scripts/gold-set-manifest.csv"
    }

    let imagesDir = baseDir + "/scripts/test-images"
    let labels = parseManifest(manifestPath)
    guard !labels.isEmpty else { print("No valid gold labels found."); exit(1) }

    print(String(repeating: "=", count: 80))
    print("  CANONICAL SCORER EVALUATION REPORT")
    print("  Source: CheckInScorer.assessCaptured (compiled from app source)")
    print("  Manifest: \((manifestPath as NSString).lastPathComponent)")
    print("  Images:   \(labels.count)")
    print(String(repeating: "=", count: 80))
    print("")

    var verdictMatches = 0
    var falseAccepts = 0
    var falseRejects = 0
    var total = 0

    for label in labels {
        let imagePath = imagesDir + "/" + label.filename
        guard let nsImage = NSImage(contentsOfFile: imagePath),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("  SKIP: \(label.filename) — file not found")
            continue
        }

        total += 1
        let result = await CheckInScorer.assessCaptured(cgImage: cgImage, pose: label.expectedPose)

        let scorerVerdict = result.reviewVerdict.rawValue
        let match = scorerVerdict == label.goldVerdict
        if match { verdictMatches += 1 }

        let isFA = (label.goldVerdict == "retakeRecommended" || label.goldVerdict == "warn") && scorerVerdict == "keep"
        let isFR = label.goldVerdict == "keep" && (scorerVerdict == "retakeRecommended" || scorerVerdict == "warn")
        if isFA { falseAccepts += 1 }
        if isFR { falseRejects += 1 }

        let statusIcon = match ? "OK" : "MISMATCH"
        let fafrTag = isFA ? " [FALSE ACCEPT]" : (isFR ? " [FALSE REJECT]" : "")

        print("  \(label.filename)")
        print("    Gold:    \(label.goldVerdict.padding(toLength: 20, withPad: " ", startingAt: 0)) Scorer: \(scorerVerdict)  \(statusIcon)\(fafrTag)")
        print("    Score:   \(String(format: "%.3f", result.overallScore))  |  def=\(String(format: "%.2f", result.subScores.definitionLighting)) frm=\(String(format: "%.2f", result.subScores.framing)) pose=\(String(format: "%.2f", result.subScores.poseAccuracy)) neut=\(String(format: "%.2f", result.subScores.poseNeutrality)) shrp=\(String(format: "%.2f", result.subScores.sharpness ?? 0))")
        print("    Reason:  \(result.primaryReason)")
        print("    Tags:    \(result.reasonTags.map(\.rawValue).joined(separator: ", "))")
        print("")
    }

    print(String(repeating: "=", count: 80))
    print("  SUMMARY")
    print(String(repeating: "=", count: 80))
    print("  Total images:       \(total)")
    print("  Verdict matches:    \(verdictMatches)/\(total) (\(total > 0 ? String(format: "%.0f", Double(verdictMatches) / Double(total) * 100) : "0")%)")
    print("  False accepts:      \(falseAccepts)")
    print("  False rejects:      \(falseRejects)")
    print("  Disagreements:      \(total - verdictMatches)")
    print("")

    if total > 0 && verdictMatches == total {
        print("  RESULT: ALL VERDICTS MATCH GOLD LABELS")
    } else if falseAccepts > 0 {
        print("  WARNING: \(falseAccepts) false accept(s) — scorer is too lenient")
    } else if falseRejects > 0 {
        print("  WARNING: \(falseRejects) false reject(s) — scorer is too strict")
    }
    print("")
}

// Entry point
@main
struct EvaluateScorer {
    static func main() async {
        await runEvaluation()
    }
}

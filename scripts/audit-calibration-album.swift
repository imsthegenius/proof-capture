#!/usr/bin/env swift

import Foundation

// MARK: - Row model

struct AlbumRow {
    let sourcePath: String
    let status: String
    let duplicateOf: String
    let exclusionReason: String
    let validationBucket: String
    var suggestedPose: String
    var suggestedLockable: String
    var suggestedLightingQuality: String
    let labelPose: String
    let labelLockable: String
    let labelCoachUsable: String
    let labelReasonTags: String
    let notes: String
}

// MARK: - JSON schema (mirrors analyze-photo.swift)
//
// Keep these types in lockstep with analyze-photo.swift's AnalysisRecord /
// LightingReport / PoseReport. A drift here silently breaks seeded manifests.
// TICKET-3 (parity test) is the long-term guard against this drift.

enum SeededQualityLevel: String, Codable {
    case good, fair, poor
}

enum SeededPose: String, Codable {
    case front, side, back
}

struct SeededLightingReport: Codable {
    let overallQuality: SeededQualityLevel
}

struct SeededPoseReport: Codable {
    let bodyDetected: Bool
    let detectedOrientation: SeededPose?
}

struct SeededAnalysisRecord: Codable {
    let path: String
    let lockable: Bool
    let lighting: SeededLightingReport
    let pose: SeededPoseReport
}

// MARK: - Helpers

let supportedExtensions = Set(["jpg", "jpeg", "png", "heic", "heif"])

func csvEscape(_ value: String) -> String {
    if value.contains(",") || value.contains("\"") || value.contains("\n") {
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    return value
}

func canonicalStem(for url: URL) -> String {
    let stem = url.deletingPathExtension().lastPathComponent.lowercased()
    return stem.replacingOccurrences(
        of: #"\(\d+\)$"#,
        with: "",
        options: .regularExpression
    )
}

func exclusionReason(for url: URL) -> String? {
    let normalized = url.path.lowercased()
    let ext = url.pathExtension.lowercased()

    if ext == "png" {
        return "png-or-composite"
    }

    let flaggedTokens = [
        "before-after",
        "beforeafter",
        "collage",
        "compare",
        "comparison",
        "screenshot",
        "screen shot"
    ]

    if flaggedTokens.contains(where: { normalized.contains($0) }) {
        return "comparison-or-collage"
    }

    return nil
}

func makeOutputURL(for albumURL: URL) -> URL {
    let parent = albumURL.deletingLastPathComponent()
    let safeName = albumURL.lastPathComponent.replacingOccurrences(of: "/", with: "-")
    return parent.appendingPathComponent("\(safeName).checkd-manifest.local.csv")
}

/// Resolves scripts/analyze-photo.swift relative to this script. Enables
/// running this tool from any CWD.
func locateAnalyzerScript() -> URL? {
    let scriptPath = CommandLine.arguments[0]
    let scriptURL = URL(fileURLWithPath: scriptPath).standardized
    let analyzer = scriptURL.deletingLastPathComponent()
        .appendingPathComponent("analyze-photo.swift")
    return FileManager.default.fileExists(atPath: analyzer.path) ? analyzer : nil
}

/// Spawns `swift scripts/analyze-photo.swift --format json <paths>` and
/// decodes the resulting JSON array. Returns nil if the analyzer is missing,
/// the subprocess fails, or the output cannot be decoded — the caller ships
/// the manifest with empty seeds in that case.
func runAnalyzer(on imageURLs: [URL]) -> [SeededAnalysisRecord]? {
    guard let analyzerURL = locateAnalyzerScript(), !imageURLs.isEmpty else {
        return nil
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    var arguments = ["swift", analyzerURL.path, "--format", "json"]
    arguments.append(contentsOf: imageURLs.map(\.path))
    process.arguments = arguments

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    do {
        try process.run()
    } catch {
        fputs("Analyzer subprocess failed to start: \(error.localizedDescription)\n", stderr)
        return nil
    }

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        let stderrText = String(data: stderrData, encoding: .utf8) ?? "<no stderr>"
        fputs("Analyzer exited with status \(process.terminationStatus):\n\(stderrText)\n", stderr)
        return nil
    }

    do {
        return try JSONDecoder().decode([SeededAnalysisRecord].self, from: stdoutData)
    } catch {
        fputs("Failed to decode analyzer output: \(error.localizedDescription)\n", stderr)
        return nil
    }
}

// MARK: - Entry point

guard CommandLine.arguments.count >= 2 else {
    print("Usage: swift scripts/audit-calibration-album.swift <album-directory>")
    exit(1)
}

let albumPath = (CommandLine.arguments[1] as NSString).expandingTildeInPath
let albumURL = URL(fileURLWithPath: albumPath)
let canonicalAlbumPath = albumURL.resolvingSymlinksInPath().path
let fileManager = FileManager.default

var isDirectory: ObjCBool = false
guard fileManager.fileExists(atPath: albumURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
    fputs("Album directory not found: \(albumURL.path)\n", stderr)
    exit(1)
}

let outputURL = makeOutputURL(for: albumURL)

let enumerator = fileManager.enumerator(
    at: albumURL,
    includingPropertiesForKeys: [.isRegularFileKey],
    options: [.skipsHiddenFiles]
)

var imageURLs: [URL] = []
while let item = enumerator?.nextObject() as? URL {
    let resolvedItem = item.resolvingSymlinksInPath()
    guard supportedExtensions.contains(resolvedItem.pathExtension.lowercased()) else { continue }
    let values = try? resolvedItem.resourceValues(forKeys: [.isRegularFileKey])
    guard values?.isRegularFile == true else { continue }
    imageURLs.append(resolvedItem)
}

imageURLs.sort { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }

var firstSeenByCanonicalStem: [String: String] = [:]
var rows: [AlbumRow] = []
var includedURLs: [URL] = []
var indexByPath: [String: Int] = [:]

for url in imageURLs {
    let relativePath = url.path.replacingOccurrences(of: canonicalAlbumPath + "/", with: "")
    let canonical = canonicalStem(for: url)

    if let reason = exclusionReason(for: url) {
        rows.append(
            AlbumRow(
                sourcePath: relativePath,
                status: "excluded",
                duplicateOf: "",
                exclusionReason: reason,
                validationBucket: "",
                suggestedPose: "",
                suggestedLockable: "",
                suggestedLightingQuality: "",
                labelPose: "",
                labelLockable: "",
                labelCoachUsable: "",
                labelReasonTags: "",
                notes: ""
            )
        )
        continue
    }

    if let original = firstSeenByCanonicalStem[canonical] {
        rows.append(
            AlbumRow(
                sourcePath: relativePath,
                status: "duplicate",
                duplicateOf: original,
                exclusionReason: "duplicate-basename",
                validationBucket: "",
                suggestedPose: "",
                suggestedLockable: "",
                suggestedLightingQuality: "",
                labelPose: "",
                labelLockable: "",
                labelCoachUsable: "",
                labelReasonTags: "",
                notes: ""
            )
        )
        continue
    }

    firstSeenByCanonicalStem[canonical] = relativePath
    indexByPath[url.path] = rows.count
    includedURLs.append(url)
    rows.append(
        AlbumRow(
            sourcePath: relativePath,
            status: "included",
            duplicateOf: "",
            exclusionReason: "",
            validationBucket: "calibration",
            suggestedPose: "",
            suggestedLockable: "",
            suggestedLightingQuality: "",
            labelPose: "",
            labelLockable: "",
            labelCoachUsable: "",
            labelReasonTags: "",
            notes: ""
        )
    )
}

// MARK: - Seed suggestions via analyze-photo.swift

let includedCount = includedURLs.count
let excludedCount = rows.filter { $0.status == "excluded" }.count
let duplicateCount = rows.filter { $0.status == "duplicate" }.count
var seededCount = 0
var analyzerSkipped = false

if includedCount == 0 {
    print("No included images to seed — skipping analyzer.")
} else {
    print("Seeding suggestions via analyze-photo.swift for \(includedCount) images (may take a moment)...")
    if let records = runAnalyzer(on: includedURLs) {
        for record in records {
            guard let index = indexByPath[record.path] else { continue }
            rows[index].suggestedPose = record.pose.detectedOrientation?.rawValue ?? ""
            rows[index].suggestedLockable = record.lockable ? "true" : "false"
            rows[index].suggestedLightingQuality = record.lighting.overallQuality.rawValue
            seededCount += 1
        }
    } else {
        analyzerSkipped = true
        fputs("Analyzer unavailable or failed — manifest will ship with empty suggestions.\n", stderr)
    }
}

// MARK: - Write CSV

let header = "source_path,status,duplicate_of,exclusion_reason,validation_bucket,suggested_pose,suggested_lockable,suggested_lighting_quality,label_pose,label_lockable,label_coach_usable,label_reason_tags,notes"
let lines = rows.map { row in
    [
        row.sourcePath,
        row.status,
        row.duplicateOf,
        row.exclusionReason,
        row.validationBucket,
        row.suggestedPose,
        row.suggestedLockable,
        row.suggestedLightingQuality,
        row.labelPose,
        row.labelLockable,
        row.labelCoachUsable,
        row.labelReasonTags,
        row.notes
    ]
    .map(csvEscape)
    .joined(separator: ",")
}

let content = ([header] + lines).joined(separator: "\n") + "\n"

do {
    try content.write(to: outputURL, atomically: true, encoding: .utf8)
} catch {
    fputs("Failed to write manifest: \(error.localizedDescription)\n", stderr)
    exit(1)
}

print("Album: \(albumURL.path)")
print("Manifest: \(outputURL.path)")
print("Total image files: \(imageURLs.count)")
print("Included: \(includedCount)")
print("Excluded: \(excludedCount)")
print("Duplicates: \(duplicateCount)")
print("Seeded: \(seededCount)")
if analyzerSkipped {
    print("Note: analyzer was skipped — suggested_* columns left blank.")
}

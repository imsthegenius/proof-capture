#!/usr/bin/env swift

import Foundation

struct AlbumRow {
    let sourcePath: String
    let status: String
    let duplicateOf: String
    let exclusionReason: String
    let validationBucket: String
    let suggestedPose: String
    let suggestedLockable: String
    let suggestedLightingQuality: String
    let labelPose: String
    let labelLockable: String
    let labelCoachUsable: String
    let labelReasonTags: String
    let notes: String
}

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

guard CommandLine.arguments.count >= 2 else {
    print("Usage: swift scripts/audit-calibration-album.swift <album-directory>")
    exit(1)
}

let albumPath = (CommandLine.arguments[1] as NSString).expandingTildeInPath
let albumURL = URL(fileURLWithPath: albumPath)
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
    guard supportedExtensions.contains(item.pathExtension.lowercased()) else { continue }
    let values = try? item.resourceValues(forKeys: [.isRegularFileKey])
    guard values?.isRegularFile == true else { continue }
    imageURLs.append(item)
}

imageURLs.sort { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }

var firstSeenByCanonicalStem: [String: String] = [:]
var rows: [AlbumRow] = []
var includedCount = 0
var excludedCount = 0
var duplicateCount = 0

for url in imageURLs {
    let relativePath = url.path.replacingOccurrences(of: albumURL.path + "/", with: "")
    let canonical = canonicalStem(for: url)

    if let reason = exclusionReason(for: url) {
        excludedCount += 1
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
        duplicateCount += 1
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
    includedCount += 1
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

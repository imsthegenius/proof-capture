#!/usr/bin/env swift

import Foundation

private let templateColumns: [String] = [
    "source_path",
    "status",
    "duplicate_of",
    "exclusion_reason",
    "validation_bucket",
    "suggested_pose",
    "suggested_lockable",
    "suggested_lighting_quality",
    "label_pose",
    "label_lockable",
    "label_coach_usable",
    "label_reason_tags",
    "notes",
]

private enum ManifestError: Error, CustomStringConvertible {
    case usage
    case unreadable(URL)
    case malformedHeader

    var description: String {
        switch self {
        case .usage:
            return "Usage: swift scripts/prepare-captured-photo-manifest.swift <manifest.csv>"
        case .unreadable(let url):
            return "Unable to read manifest at \(url.path)"
        case .malformedHeader:
            return "Manifest is missing a CSV header."
        }
    }
}

private func splitCSVLine(_ line: String) -> [String] {
    var fields: [String] = []
    var field = ""
    var inQuotes = false

    var index = line.startIndex
    while index < line.endIndex {
        let character = line[index]
        if inQuotes {
            if character == "\"" {
                let nextIndex = line.index(after: index)
                if nextIndex < line.endIndex, line[nextIndex] == "\"" {
                    field.append("\"")
                    index = nextIndex
                } else {
                    inQuotes = false
                }
            } else {
                field.append(character)
            }
        } else {
            switch character {
            case "\"":
                inQuotes = true
            case ",":
                fields.append(field)
                field = ""
            default:
                field.append(character)
            }
        }
        index = line.index(after: index)
    }

    fields.append(field)
    return fields
}

private func parseCSV(_ text: String) -> [[String]] {
    text
        .split(whereSeparator: \.isNewline)
        .map { splitCSVLine(String($0)) }
        .filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
}

private func csvEscape(_ value: String) -> String {
    if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    return value
}

private func normalized(_ value: String?) -> String {
    (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
}

private func folderKey(for sourcePath: String) -> String {
    let trimmed = normalized(sourcePath)
    guard !trimmed.isEmpty else { return "" }
    let url = URL(fileURLWithPath: trimmed)
    let parent = url.deletingLastPathComponent().path
    return parent.isEmpty ? trimmed : parent
}

private func bucket(for key: String) -> String {
    var hash: UInt64 = 1469598103934665603
    for byte in key.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1099511628211
    }

    switch Int(hash % 100) {
    case 0..<70:
        return "train_tune"
    case 70..<85:
        return "threshold_check"
    default:
        return "final_validation"
    }
}

private func value(for column: String, in row: [String], headerIndex: [String: Int]) -> String {
    guard let index = headerIndex[column], index < row.count else { return "" }
    return normalized(row[index])
}

private func updateManifest(at url: URL, templateURL: URL) throws {
    let template = try String(contentsOf: templateURL, encoding: .utf8)
    guard let templateHeader = parseCSV(template).first else {
        throw ManifestError.malformedHeader
    }

    let existingContent = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    var existingRows = existingContent.isEmpty ? [] : parseCSV(existingContent)

    if existingRows.isEmpty {
        let header = templateHeader.joined(separator: ",")
        try (header + "\n").write(to: url, atomically: true, encoding: .utf8)
        print("Seeded new manifest at \(url.path)")
        return
    }

    let originalHeader = existingRows.removeFirst()
    guard !originalHeader.isEmpty else { throw ManifestError.malformedHeader }

    var finalHeader = originalHeader
    for column in templateHeader where !finalHeader.contains(column) {
        finalHeader.append(column)
    }

    let headerIndex = Dictionary(uniqueKeysWithValues: finalHeader.enumerated().map { ($1, $0) })
    guard headerIndex["source_path"] != nil else { throw ManifestError.malformedHeader }

    var outputRows: [[String]] = [finalHeader]
    var splitCounts: [String: Int] = [
        "train_tune": 0,
        "threshold_check": 0,
        "final_validation": 0,
    ]
    var excludedCount = 0

    for row in existingRows {
        var expandedRow = row
        if expandedRow.count < finalHeader.count {
            expandedRow.append(contentsOf: Array(repeating: "", count: finalHeader.count - expandedRow.count))
        }

        let sourcePath = value(for: "source_path", in: expandedRow, headerIndex: headerIndex)
        let status = value(for: "status", in: expandedRow, headerIndex: headerIndex).lowercased()
        let duplicateOf = value(for: "duplicate_of", in: expandedRow, headerIndex: headerIndex)
        let exclusionReason = value(for: "exclusion_reason", in: expandedRow, headerIndex: headerIndex)
        let bucketIndex = headerIndex["validation_bucket"]

        let isExcluded = status == "excluded" || status == "duplicate" || !duplicateOf.isEmpty || !exclusionReason.isEmpty

        if let bucketIndex, bucketIndex < expandedRow.count {
            if isExcluded {
                expandedRow[bucketIndex] = ""
                excludedCount += 1
            } else if expandedRow[bucketIndex].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let assignedBucket = bucket(for: folderKey(for: sourcePath))
                expandedRow[bucketIndex] = assignedBucket
                splitCounts[assignedBucket, default: 0] += 1
            }
        }

        outputRows.append(expandedRow)
    }

    let rendered = outputRows.map { $0.map(csvEscape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    try rendered.write(to: url, atomically: true, encoding: .utf8)

    let totalIncluded = splitCounts.values.reduce(0, +)
    print("Updated \(url.lastPathComponent): \(totalIncluded) split rows, \(excludedCount) excluded rows")
    print("  train_tune: \(splitCounts["train_tune", default: 0])")
    print("  threshold_check: \(splitCounts["threshold_check", default: 0])")
    print("  final_validation: \(splitCounts["final_validation", default: 0])")
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count == 1 else { throw ManifestError.usage }

    let manifestURL = URL(fileURLWithPath: args[0])
    let templateURL = URL(fileURLWithPath: "scripts/calibration-manifest.template.csv")
    if !FileManager.default.fileExists(atPath: templateURL.path) {
        throw ManifestError.unreadable(templateURL)
    }

    try updateManifest(at: manifestURL, templateURL: templateURL)
} catch let error as ManifestError {
    fputs(error.description + "\n", stderr)
    if case .usage = error {
        exit(1)
    } else {
        exit(2)
    }
} catch {
    fputs("Unexpected error: \(error)\n", stderr)
    exit(3)
}

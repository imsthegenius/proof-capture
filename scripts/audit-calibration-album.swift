#!/usr/bin/env swift

import Foundation

struct AnalysisRecord: Decodable {
    struct Lighting: Decodable {
        let overallQuality: String
    }

    struct Pose: Decodable {
        let detectedOrientation: String?
    }

    let path: String
    let lockable: Bool
    let lighting: Lighting
    let pose: Pose
}

let supportedExtensions = Set(["jpg", "jpeg", "png", "heic", "heif"])
let defaultColumns = [
    "source_path",
    "status",
    "duplicate_of",
    "exclusion_reason",
    "validation_bucket",
    "split",
    "suggested_pose",
    "suggested_lockable",
    "suggested_lighting_quality",
    "label_pose",
    "label_lockable",
    "label_keep_verdict",
    "label_coach_usable",
    "label_definition_visibility",
    "label_directionality",
    "label_body_exposure",
    "label_backlight",
    "label_sharpness",
    "label_framing",
    "label_reason_tags",
    "notes"
]

struct CSVRow {
    var values: [String: String]
}

guard CommandLine.arguments.count >= 2 else {
    print("Usage: swift scripts/audit-calibration-album.swift <album-directory> [--manifest path]")
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
let albumPath = resolvePath(arguments[0])
let albumURL = URL(fileURLWithPath: albumPath)

var manifestURL = defaultManifestURL(for: albumURL)
if let manifestFlagIndex = arguments.firstIndex(of: "--manifest") {
    guard manifestFlagIndex + 1 < arguments.count else {
        fputs("Missing value for --manifest\n", stderr)
        exit(1)
    }
    manifestURL = URL(fileURLWithPath: resolvePath(arguments[manifestFlagIndex + 1]))
}

var isDirectory: ObjCBool = false
guard FileManager.default.fileExists(atPath: albumURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
    fputs("Album directory not found: \(albumURL.path)\n", stderr)
    exit(1)
}

var existingRowsByPath: [String: CSVRow] = [:]
var columns = defaultColumns
if FileManager.default.fileExists(atPath: manifestURL.path),
   let existingCSV = try? String(contentsOf: manifestURL, encoding: .utf8) {
    let parsed = parseCSV(existingCSV)
    if let header = parsed.first, !header.isEmpty {
        columns = header
        for column in defaultColumns where !columns.contains(column) {
            columns.append(column)
        }
        for raw in parsed.dropFirst() {
            var values: [String: String] = [:]
            for (index, column) in header.enumerated() where index < raw.count {
                values[column] = raw[index]
            }
            if let path = values["source_path"], !path.isEmpty {
                existingRowsByPath[path] = CSVRow(values: values)
            }
        }
    }
}

let imageURLs = collectImageURLs(in: albumURL)
let analyzerResults = runAnalyzer(on: imageURLs) ?? []
let analyzerByPath = Dictionary(uniqueKeysWithValues: analyzerResults.map { ($0.path, $0) })

var firstSeenByStem: [String: String] = [:]
var rows: [CSVRow] = []

for url in imageURLs {
    let relativePath = url.path.replacingOccurrences(of: albumURL.path + "/", with: "")
    let existing = existingRowsByPath[relativePath]
    var values = existing?.values ?? [:]

    values["source_path"] = relativePath

    if let exclusion = exclusionReason(for: url) {
        values["status"] = "excluded"
        values["duplicate_of"] = existing?.values["duplicate_of"] ?? ""
        values["exclusion_reason"] = exclusion
        values["validation_bucket"] = ""
        values["split"] = "excluded"
        clearSuggestedFields(in: &values)
        rows.append(CSVRow(values: values))
        continue
    }

    let stem = canonicalStem(for: url)
    if let original = firstSeenByStem[stem] {
        values["status"] = "duplicate"
        values["duplicate_of"] = original
        values["exclusion_reason"] = "duplicate-basename"
        values["validation_bucket"] = ""
        values["split"] = "duplicate"
        clearSuggestedFields(in: &values)
        rows.append(CSVRow(values: values))
        continue
    }

    firstSeenByStem[stem] = relativePath
    values["status"] = "included"
    values["duplicate_of"] = ""
    values["exclusion_reason"] = ""
    values["validation_bucket"] = "calibration"

    if let result = analyzerByPath[url.path] {
        values["suggested_pose"] = result.pose.detectedOrientation ?? ""
        values["suggested_lockable"] = result.lockable ? "yes" : "no"
        values["suggested_lighting_quality"] = result.lighting.overallQuality
    }

    rows.append(CSVRow(values: values))
}

applyDeterministicSplits(to: &rows)

let rendered = renderCSV(columns: columns, rows: rows)
try rendered.write(to: manifestURL, atomically: true, encoding: .utf8)

let statusSummary = summary(for: rows, key: "status")
let splitSummary = summary(for: rows, key: "split")
print("Updated manifest: \(manifestURL.path)")
print("Status summary — \(statusSummary)")
print("Split summary — \(splitSummary)")

func resolvePath(_ rawPath: String) -> String {
    let expanded = (rawPath as NSString).expandingTildeInPath
    if expanded.hasPrefix("/") {
        return expanded
    }
    return FileManager.default.currentDirectoryPath + "/" + expanded
}

func defaultManifestURL(for albumURL: URL) -> URL {
    let parent = albumURL.deletingLastPathComponent()
    return parent.appendingPathComponent("\(albumURL.lastPathComponent).checkd-manifest.local.csv")
}

func collectImageURLs(in root: URL) -> [URL] {
    let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    )

    var urls: [URL] = []
    while let item = enumerator?.nextObject() as? URL {
        guard supportedExtensions.contains(item.pathExtension.lowercased()) else { continue }
        guard (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
        urls.append(item)
    }

    return urls.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
}

func canonicalStem(for url: URL) -> String {
    let stem = url.deletingPathExtension().lastPathComponent.lowercased()
    return stem.replacingOccurrences(of: #"\(\d+\)$"#, with: "", options: .regularExpression)
}

func exclusionReason(for url: URL) -> String? {
    let lowerPath = url.path.lowercased()
    let ext = url.pathExtension.lowercased()

    if lowerPath.contains("/before-after/") {
        return ext == "png" ? "png-or-composite" : "comparison-or-collage"
    }
    if url.lastPathComponent.lowercased() == "background.png" {
        return "non-photo-asset"
    }
    if ext == "png" {
        return "png-or-composite"
    }

    let flaggedTokens = ["before-after", "beforeafter", "collage", "compare", "comparison", "screenshot", "screen shot"]
    if flaggedTokens.contains(where: { lowerPath.contains($0) }) {
        return "comparison-or-collage"
    }

    return nil
}

func clearSuggestedFields(in values: inout [String: String]) {
    values["suggested_pose"] = ""
    values["suggested_lockable"] = ""
    values["suggested_lighting_quality"] = ""
}

func applyDeterministicSplits(to rows: inout [CSVRow]) {
    let calibrationClients = rows.compactMap { row -> String? in
        guard row.values["status"] == "included",
              row.values["validation_bucket"] == "calibration",
              let sourcePath = row.values["source_path"],
              !sourcePath.isEmpty else { return nil }
        return sourcePath.split(separator: "/").first.map(String.init)
    }

    let uniqueClients = Array(Set(calibrationClients)).sorted()
    let assignments = assignSplits(to: uniqueClients)

    for index in rows.indices {
        switch rows[index].values["status"] {
        case "included":
            let client = rows[index].values["source_path"]?.split(separator: "/").first.map(String.init)
            rows[index].values["split"] = client.flatMap { assignments[$0] } ?? "train_tune"
        case "duplicate":
            rows[index].values["split"] = "duplicate"
        case "excluded":
            rows[index].values["split"] = "excluded"
        default:
            break
        }
    }
}

func assignSplits(to clients: [String]) -> [String: String] {
    guard !clients.isEmpty else { return [:] }

    let total = clients.count
    var trainCount = max(1, Int(floor(Double(total) * 0.70)))
    var thresholdCount = Int(floor(Double(total) * 0.15))
    var validationCount = total - trainCount - thresholdCount

    if total >= 3 {
        if thresholdCount == 0 {
            thresholdCount = 1
            trainCount = max(1, trainCount - 1)
        }
        if validationCount == 0 {
            validationCount = 1
            trainCount = max(1, trainCount - 1)
        }
    } else if total == 2 {
        trainCount = 1
        thresholdCount = 0
        validationCount = 1
    } else {
        trainCount = 1
        thresholdCount = 0
        validationCount = 0
    }

    var assignments: [String: String] = [:]
    for (index, client) in clients.enumerated() {
        if index < trainCount {
            assignments[client] = "train_tune"
        } else if index < trainCount + thresholdCount {
            assignments[client] = "threshold_check"
        } else {
            assignments[client] = "final_validation"
        }
    }
    return assignments
}

func runAnalyzer(on imageURLs: [URL]) -> [AnalysisRecord]? {
    guard let analyzerURL = locateAnalyzerScript(), !imageURLs.isEmpty else {
        return nil
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swift", analyzerURL.path, "--format", "json"] + imageURLs.map(\.path)
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    do {
        try process.run()
    } catch {
        fputs("Failed to start analyzer: \(error.localizedDescription)\n", stderr)
        return nil
    }

    let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        let errorText = String(data: errorData, encoding: .utf8) ?? "<no stderr>"
        fputs("Analyzer failed with status \(process.terminationStatus):\n\(errorText)\n", stderr)
        return nil
    }

    do {
        return try JSONDecoder().decode([AnalysisRecord].self, from: outputData)
    } catch {
        fputs("Failed to decode analyzer JSON: \(error.localizedDescription)\n", stderr)
        return nil
    }
}

func locateAnalyzerScript() -> URL? {
    let scriptURL = URL(fileURLWithPath: resolvePath(CommandLine.arguments[0]))
    let analyzerURL = scriptURL.deletingLastPathComponent().appendingPathComponent("analyze-photo.swift")
    return FileManager.default.fileExists(atPath: analyzerURL.path) ? analyzerURL : nil
}

func summary(for rows: [CSVRow], key: String) -> String {
    let counts = rows.reduce(into: [String: Int]()) { partial, row in
        let value = row.values[key, default: ""]
        partial[value, default: 0] += 1
    }
    return counts.keys.sorted().map { "\($0.isEmpty ? "<blank>" : $0): \(counts[$0] ?? 0)" }.joined(separator: ", ")
}

func parseCSV(_ source: String) -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var isInsideQuotes = false
    var iterator = source.makeIterator()

    while let character = iterator.next() {
        switch character {
        case "\"":
            if isInsideQuotes {
                if let next = iterator.next() {
                    if next == "\"" {
                        field.append("\"")
                    } else {
                        isInsideQuotes = false
                        switch next {
                        case ",":
                            row.append(field)
                            field = ""
                        case "\n":
                            row.append(field)
                            rows.append(row)
                            row = []
                            field = ""
                        case "\r":
                            row.append(field)
                            if let maybeNewline = iterator.next(), maybeNewline != "\n" {
                                field.append(maybeNewline)
                            }
                            rows.append(row)
                            row = []
                            field = ""
                        default:
                            field.append(next)
                        }
                    }
                } else {
                    isInsideQuotes = false
                }
            } else {
                isInsideQuotes = true
            }
        case "," where !isInsideQuotes:
            row.append(field)
            field = ""
        case "\n" where !isInsideQuotes:
            row.append(field)
            rows.append(row)
            row = []
            field = ""
        case "\r" where !isInsideQuotes:
            row.append(field)
            rows.append(row)
            row = []
            field = ""
        default:
            field.append(character)
        }
    }

    if !field.isEmpty || !row.isEmpty {
        row.append(field)
        rows.append(row)
    }

    return rows
}

func renderCSV(columns: [String], rows: [CSVRow]) -> String {
    let lines = [columns] + rows.map { row in
        columns.map { escapeCSV(row.values[$0, default: ""]) }
    }
    return lines.map { $0.joined(separator: ",") }.joined(separator: "\n") + "\n"
}

func escapeCSV(_ value: String) -> String {
    if value.contains(",") || value.contains("\"") || value.contains("\n") {
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    return value
}

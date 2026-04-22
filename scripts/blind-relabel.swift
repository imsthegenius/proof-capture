#!/usr/bin/env swift
//
// blind-relabel.swift
//
// Blind re-labeling harness for the Proof Capture captured-scorer validation
// wave (TWO-942 under parent TWO-941).
//
// Contract (locked in TWO-942 schema + addendum comments):
//   - source manifest:  /Users/imraan/Downloads/Client Pictures.checkd-manifest.local.csv
//   - image root:       /Users/imraan/Downloads/Client Pictures
//   - holdout rows:     split IN {threshold_check, final_validation} → 83 rows
//   - reviewed output:  scripts/reviewed-holdout.csv (append-only during first pass)
//   - disputes output:  scripts/reviewed-holdout-disputes.csv (after first pass completes)
//   - metadata:         scripts/relabel-metadata.json (manifest SHA, row count, started_at)
//   - freeze marker:    scripts/reviewed-holdout.csv.frozen (written by TWO-943)
//
// Blind protocol: --next emits only source_path + absolute path for the next
// unlabeled holdout row. Never emits any auto-seeded label field. Auto labels
// are only read in --disputes mode, which is gated behind "83 rows committed".
//
// Subcommands:
//   swift scripts/blind-relabel.swift --status
//   swift scripts/blind-relabel.swift --next
//   swift scripts/blind-relabel.swift --commit <source_path> <verdict> <tags> <pose> <framing>
//   swift scripts/blind-relabel.swift --disputes
//   swift scripts/blind-relabel.swift --dry-run
//
// See scripts/README.md "Blind re-label protocol" for full usage.
//

import Foundation
import CryptoKit

// MARK: - Paths

let MANIFEST_PATH = "/Users/imraan/Downloads/Client Pictures.checkd-manifest.local.csv"
let IMAGES_ROOT   = "/Users/imraan/Downloads/Client Pictures"
let REVIEWED_CSV  = "scripts/reviewed-holdout.csv"
let DISPUTES_CSV  = "scripts/reviewed-holdout-disputes.csv"
let METADATA_JSON = "scripts/relabel-metadata.json"
let FROZEN_MARKER = "scripts/reviewed-holdout.csv.frozen"

let HOLDOUT_SPLITS: Set<String> = ["threshold_check", "final_validation"]
let HOLDOUT_ROW_COUNT = 83
let SCHEMA_VERSION = 1
let REVIEWER_FIRST_PASS = "claude-blind-pass"

// Label vocabularies (locked in schema comment)
let VERDICT_VALUES: Set<String> = ["keep", "warn", "retakeRecommended"]
let POSE_VALUES: Set<String> = ["front", "side", "back", "unclear"]
let FRAMING_VALUES: Set<String> = ["ideal", "ok", "tooClose", "tooFar", "partial"]
let REASON_TAG_VOCAB: Set<String> = [
    "arms", "not-lockable", "framing", "tooClose", "tooFar",
    "backlight", "dark", "blurry", "wrong-pose", "partial-body",
    "face-only", "mirror-selfie", "collage", "stage-lighting",
    "flash", "low-contrast", "other"
]

// Tier bucketing for verdict dispute classification (no silent mapping).
let TIER_NEGATIVE: Set<String> = ["drop", "retakeRecommended"]
let TIER_MIDDLE:   Set<String> = ["warn"]
let TIER_POSITIVE: Set<String> = ["keep"]

// Reviewed CSV header (v1). Column order is part of the contract.
let REVIEWED_HEADER = [
    "source_path",
    "split",
    "manifest_row_index",
    "label_keep_verdict",
    "label_reason_tags",
    "label_pose",
    "label_framing",
    "reviewer",
    "reviewed_at",
    "harness_sha",
    "schema_version",
]

// Disputes CSV header (v1).
let DISPUTES_HEADER = [
    "source_path",
    "field",
    "blind_value",
    "auto_value",
    "legacy_seed_verdict",
    "delta_type",
    "adjudicated_value",
    "adjudicator",
    "adjudicated_at",
    "notes",
]

// MARK: - Utilities

func die(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data(("ERROR: " + message + "\n").utf8))
    exit(code)
}

func iso8601UTCNow() -> String {
    let fmt = ISO8601DateFormatter()
    fmt.formatOptions = [.withInternetDateTime]
    return fmt.string(from: Date())
}

func sha256Hex(_ data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}

func shortGitSHA() -> String {
    let task = Process()
    task.launchPath = "/usr/bin/env"
    task.arguments = ["git", "rev-parse", "--short", "HEAD"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()
    do {
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return "unknown" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
    } catch {
        return "unknown"
    }
}

func frozenMarkerExists() -> Bool {
    FileManager.default.fileExists(atPath: FROZEN_MARKER)
}

// MARK: - CSV parser (handles quoted commas; sufficient for the source manifest)

struct CSVRow {
    let fields: [String]
    subscript(index: Int) -> String {
        index < fields.count ? fields[index] : ""
    }
}

func parseCSV(_ text: String) -> [[String]] {
    // Iterate over Unicode scalars so \r\n is two scalars, not one grapheme cluster.
    let scalars = Array(text.unicodeScalars)
    var rows: [[String]] = []
    var current: [String] = []
    var field = ""
    var inQuotes = false
    var i = 0
    let n = scalars.count
    let QUOTE: Unicode.Scalar = "\""
    let COMMA: Unicode.Scalar = ","
    let LF: Unicode.Scalar = "\n"
    let CR: Unicode.Scalar = "\r"

    while i < n {
        let s = scalars[i]
        if inQuotes {
            if s == QUOTE {
                if i + 1 < n && scalars[i + 1] == QUOTE {
                    field.append("\"")
                    i += 2
                } else {
                    inQuotes = false
                    i += 1
                }
            } else {
                field.unicodeScalars.append(s)
                i += 1
            }
        } else {
            if s == QUOTE {
                inQuotes = true
                i += 1
            } else if s == COMMA {
                current.append(field)
                field = ""
                i += 1
            } else if s == LF || s == CR {
                current.append(field)
                field = ""
                if !current.allSatisfy({ $0.isEmpty }) {
                    rows.append(current)
                }
                current = []
                if s == CR && i + 1 < n && scalars[i + 1] == LF {
                    i += 2
                } else {
                    i += 1
                }
            } else {
                field.unicodeScalars.append(s)
                i += 1
            }
        }
    }
    if !(field.isEmpty && current.isEmpty) {
        current.append(field)
        if !current.allSatisfy({ $0.isEmpty }) {
            rows.append(current)
        }
    }
    return rows
}

// MARK: - CSV writer (minimal quoting)

func csvEscape(_ field: String) -> String {
    if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    return field
}

func csvLine(_ fields: [String]) -> String {
    fields.map(csvEscape).joined(separator: ",") + "\n"
}

// MARK: - Manifest row (minimal view — the harness exposes only what each command needs)

struct ManifestRow {
    let sourcePath: String
    let split: String
    let manifestRowIndex: Int
    // Seeded fields — NEVER surfaced by --next / --commit / --status.
    let seedVerdict: String
    let seedPose: String
    let seedFraming: String
    let seedReasonTags: String  // raw, may be comma-separated
}

struct ManifestSnapshot {
    let rows: [ManifestRow]                 // all data rows from the manifest
    let holdoutRowsSorted: [ManifestRow]    // only split IN HOLDOUT_SPLITS, sorted ASCII by sourcePath
    let sha256: String
    let byteCount: Int
}

func loadManifest() -> ManifestSnapshot {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: MANIFEST_PATH)) else {
        die("cannot read manifest at \(MANIFEST_PATH)")
    }
    let sha = sha256Hex(data)
    guard let text = String(data: data, encoding: .utf8) else {
        die("manifest is not valid UTF-8")
    }
    let parsed = parseCSV(text)
    guard let header = parsed.first else { die("manifest has no header") }

    func col(_ name: String) -> Int? {
        header.firstIndex(of: name)
    }
    guard let iSource = col("source_path"),
          let iSplit = col("split") else {
        die("manifest missing required columns (source_path, split)")
    }
    let iLabelVerdict = col("label_keep_verdict") ?? -1
    let iLabelPose = col("label_pose") ?? -1
    let iLabelFraming = col("label_framing") ?? -1
    let iLabelTags = col("label_reason_tags") ?? -1

    var rows: [ManifestRow] = []
    for (offset, record) in parsed.dropFirst().enumerated() {
        func field(_ idx: Int) -> String {
            (idx >= 0 && idx < record.count) ? record[idx] : ""
        }
        let r = ManifestRow(
            sourcePath: field(iSource),
            split: field(iSplit),
            manifestRowIndex: offset,
            seedVerdict: field(iLabelVerdict),
            seedPose: field(iLabelPose),
            seedFraming: field(iLabelFraming),
            seedReasonTags: field(iLabelTags)
        )
        rows.append(r)
    }

    let holdout = rows.filter { HOLDOUT_SPLITS.contains($0.split) }
        .sorted { $0.sourcePath < $1.sourcePath }

    if holdout.count != HOLDOUT_ROW_COUNT {
        var byBucket: [String: Int] = [:]
        for r in rows { byBucket[r.split, default: 0] += 1 }
        let breakdown = byBucket.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
        die("""
            expected \(HOLDOUT_ROW_COUNT) holdout rows, found \(holdout.count)
              total parsed rows: \(rows.count)
              header columns: \(header.count)
              split column index: \(iSplit)
              source_path column index: \(iSource)
              split buckets: \(breakdown)
            """)
    }

    return ManifestSnapshot(
        rows: rows,
        holdoutRowsSorted: holdout,
        sha256: sha,
        byteCount: data.count
    )
}

// MARK: - Metadata (drift guard)

struct Metadata: Codable {
    var manifestSha256: String
    var manifestByteCount: Int
    var holdoutRowCount: Int
    var harnessSha: String
    var startedAt: String
    var schemaVersion: Int
}

func loadOrInitMetadata(_ snapshot: ManifestSnapshot) -> Metadata {
    let url = URL(fileURLWithPath: METADATA_JSON)
    if let data = try? Data(contentsOf: url),
       let existing = try? JSONDecoder().decode(Metadata.self, from: data) {
        if existing.manifestSha256 != snapshot.sha256 {
            die("""
                manifest drift detected
                  stored sha: \(existing.manifestSha256)
                  current sha: \(snapshot.sha256)
                the source manifest changed since first-pass started.
                delete \(METADATA_JSON) and re-label if this is intentional.
                """)
        }
        if existing.holdoutRowCount != snapshot.holdoutRowsSorted.count {
            die("holdout row count changed: stored \(existing.holdoutRowCount), current \(snapshot.holdoutRowsSorted.count)")
        }
        return existing
    }
    let fresh = Metadata(
        manifestSha256: snapshot.sha256,
        manifestByteCount: snapshot.byteCount,
        holdoutRowCount: snapshot.holdoutRowsSorted.count,
        harnessSha: shortGitSHA(),
        startedAt: iso8601UTCNow(),
        schemaVersion: SCHEMA_VERSION
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
        try encoder.encode(fresh).write(to: url, options: .atomic)
    } catch {
        die("failed to write \(METADATA_JSON): \(error)")
    }
    return fresh
}

// MARK: - Reviewed store

struct ReviewedRow {
    let sourcePath: String
    let split: String
    let manifestRowIndex: Int
    let verdict: String
    let reasonTags: String  // already normalized (pipe-joined, ASCII-sorted)
    let pose: String
    let framing: String
    let reviewer: String
    let reviewedAt: String
    let harnessSha: String
    let schemaVersion: Int
}

func loadReviewed() -> [ReviewedRow] {
    let url = URL(fileURLWithPath: REVIEWED_CSV)
    guard FileManager.default.fileExists(atPath: REVIEWED_CSV),
          let data = try? Data(contentsOf: url),
          let text = String(data: data, encoding: .utf8) else {
        return []
    }
    let parsed = parseCSV(text)
    guard let header = parsed.first else { return [] }
    func col(_ name: String) -> Int? { header.firstIndex(of: name) }
    guard let iSource = col("source_path"),
          let iSplit = col("split"),
          let iIdx = col("manifest_row_index"),
          let iVerdict = col("label_keep_verdict"),
          let iTags = col("label_reason_tags"),
          let iPose = col("label_pose"),
          let iFraming = col("label_framing"),
          let iReviewer = col("reviewer"),
          let iAt = col("reviewed_at"),
          let iSha = col("harness_sha"),
          let iSchema = col("schema_version") else {
        die("\(REVIEWED_CSV) header does not match v1 schema")
    }
    var out: [ReviewedRow] = []
    for record in parsed.dropFirst() {
        func f(_ idx: Int) -> String { idx < record.count ? record[idx] : "" }
        out.append(ReviewedRow(
            sourcePath: f(iSource),
            split: f(iSplit),
            manifestRowIndex: Int(f(iIdx)) ?? -1,
            verdict: f(iVerdict),
            reasonTags: f(iTags),
            pose: f(iPose),
            framing: f(iFraming),
            reviewer: f(iReviewer),
            reviewedAt: f(iAt),
            harnessSha: f(iSha),
            schemaVersion: Int(f(iSchema)) ?? -1
        ))
    }
    return out
}

func ensureReviewedHeader() throws {
    if FileManager.default.fileExists(atPath: REVIEWED_CSV) { return }
    try csvLine(REVIEWED_HEADER).write(toFile: REVIEWED_CSV, atomically: true, encoding: .utf8)
}

func appendReviewed(_ row: ReviewedRow) throws {
    try ensureReviewedHeader()
    let line = csvLine([
        row.sourcePath,
        row.split,
        String(row.manifestRowIndex),
        row.verdict,
        row.reasonTags,
        row.pose,
        row.framing,
        row.reviewer,
        row.reviewedAt,
        row.harnessSha,
        String(row.schemaVersion),
    ])
    let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: REVIEWED_CSV))
    defer { try? handle.close() }
    try handle.seekToEnd()
    handle.write(Data(line.utf8))
}

// MARK: - Tag normalization

func normalizeReasonTags(_ raw: String) -> String {
    // Accepts either comma or pipe-separated input; emits pipe-joined, ASCII-sorted.
    let split = raw.split(whereSeparator: { $0 == "," || $0 == "|" })
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    let unique = Array(Set(split)).sorted()
    return unique.joined(separator: "|")
}

func validateReasonTags(_ tags: [String]) -> [String] {
    // Returns list of tags not in vocabulary.
    tags.filter { !REASON_TAG_VOCAB.contains($0) }
}

// MARK: - Commands

func cmdStatus(_ snapshot: ManifestSnapshot, _ metadata: Metadata) {
    let reviewed = loadReviewed()
    let done = Set(reviewed.map(\.sourcePath))
    let target = snapshot.holdoutRowsSorted.count
    let remaining = target - done.count
    print("blind-relabel status")
    print("  manifest sha:        \(snapshot.sha256.prefix(12))")
    print("  holdout rows:        \(target)")
    print("  labeled:             \(done.count)")
    print("  remaining:           \(remaining)")
    print("  frozen:              \(frozenMarkerExists())")
    print("  harness sha (start): \(metadata.harnessSha)")
}

func nextUnlabeledIndex(snapshot: ManifestSnapshot, reviewed: [ReviewedRow]) -> Int? {
    let done = Set(reviewed.map(\.sourcePath))
    for (idx, row) in snapshot.holdoutRowsSorted.enumerated() {
        if !done.contains(row.sourcePath) {
            return idx
        }
    }
    return nil
}

func cmdNext(_ snapshot: ManifestSnapshot) {
    let reviewed = loadReviewed()
    guard let idx = nextUnlabeledIndex(snapshot: snapshot, reviewed: reviewed) else {
        print("# all \(snapshot.holdoutRowsSorted.count) holdout rows labeled")
        exit(0)
    }
    let row = snapshot.holdoutRowsSorted[idx]
    // BLIND: only source_path + absolute path. No seed labels.
    print("index: \(idx + 1)/\(snapshot.holdoutRowsSorted.count)")
    print("source_path: \(row.sourcePath)")
    print("absolute: \(IMAGES_ROOT)/\(row.sourcePath)")
    print("split: \(row.split)")
    print("manifest_row_index: \(row.manifestRowIndex)")
}

func cmdCommit(_ args: [String], _ snapshot: ManifestSnapshot, _ metadata: Metadata) {
    if frozenMarkerExists() {
        die("\(FROZEN_MARKER) exists — reviewed CSV is frozen and cannot be appended to")
    }
    guard args.count == 5 else {
        die("usage: --commit <source_path> <verdict> <tags> <pose> <framing>")
    }
    let sourcePath = args[0]
    let verdict = args[1]
    let tagsRaw = args[2]
    let pose = args[3]
    let framing = args[4]

    guard VERDICT_VALUES.contains(verdict) else {
        die("invalid verdict '\(verdict)'. allowed: \(VERDICT_VALUES.sorted().joined(separator: ", "))")
    }
    guard POSE_VALUES.contains(pose) else {
        die("invalid pose '\(pose)'. allowed: \(POSE_VALUES.sorted().joined(separator: ", "))")
    }
    guard FRAMING_VALUES.contains(framing) else {
        die("invalid framing '\(framing)'. allowed: \(FRAMING_VALUES.sorted().joined(separator: ", "))")
    }

    // Tag: "none" / "-" / "" all mean "no tags"; otherwise validate.
    let normTags: String
    if tagsRaw.isEmpty || tagsRaw == "none" || tagsRaw == "-" {
        normTags = ""
    } else {
        let split = tagsRaw.split(whereSeparator: { $0 == "," || $0 == "|" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let unknown = validateReasonTags(split)
        if !unknown.isEmpty {
            die("unknown reason tags: \(unknown.joined(separator: ", ")). vocab: \(REASON_TAG_VOCAB.sorted().joined(separator: ", "))")
        }
        normTags = Array(Set(split)).sorted().joined(separator: "|")
    }

    guard let manifestRow = snapshot.holdoutRowsSorted.first(where: { $0.sourcePath == sourcePath }) else {
        die("source_path '\(sourcePath)' is not in the holdout (split IN \(HOLDOUT_SPLITS.sorted()))")
    }

    let reviewed = loadReviewed()
    if reviewed.contains(where: { $0.sourcePath == sourcePath }) {
        die("source_path '\(sourcePath)' already labeled. delete from \(REVIEWED_CSV) to redo.")
    }

    let row = ReviewedRow(
        sourcePath: manifestRow.sourcePath,
        split: manifestRow.split,
        manifestRowIndex: manifestRow.manifestRowIndex,
        verdict: verdict,
        reasonTags: normTags,
        pose: pose,
        framing: framing,
        reviewer: REVIEWER_FIRST_PASS,
        reviewedAt: iso8601UTCNow(),
        harnessSha: shortGitSHA(),
        schemaVersion: SCHEMA_VERSION
    )
    do {
        try appendReviewed(row)
    } catch {
        die("failed to append to \(REVIEWED_CSV): \(error)")
    }

    let labeled = reviewed.count + 1
    let target = snapshot.holdoutRowsSorted.count
    print("committed \(labeled)/\(target): \(sourcePath) → \(verdict) [\(normTags)] \(pose)/\(framing)")
}

// MARK: - Disputes

func cmdDisputes(_ snapshot: ManifestSnapshot) {
    let reviewed = loadReviewed()
    if reviewed.count < snapshot.holdoutRowsSorted.count {
        die("disputes can only run after all \(snapshot.holdoutRowsSorted.count) rows are labeled (currently \(reviewed.count))")
    }

    // Index manifest holdout by source_path for lookup.
    var manifestBySource: [String: ManifestRow] = [:]
    for r in snapshot.holdoutRowsSorted { manifestBySource[r.sourcePath] = r }

    var disputeLines: [[String]] = []

    // Sort reviewed rows ASCII on source_path for deterministic output order.
    let reviewedSorted = reviewed.sorted { $0.sourcePath < $1.sourcePath }

    for r in reviewedSorted {
        guard let seed = manifestBySource[r.sourcePath] else {
            die("reviewed row has unknown source_path: \(r.sourcePath)")
        }

        // --- label_keep_verdict ---
        if r.verdict != seed.seedVerdict {
            let delta = verdictDeltaType(blind: r.verdict, auto: seed.seedVerdict)
            disputeLines.append([
                r.sourcePath, "label_keep_verdict",
                r.verdict, seed.seedVerdict, seed.seedVerdict, delta,
                "", "", "", ""
            ])
        }

        // --- label_pose ---
        if !seed.seedPose.isEmpty && r.pose != seed.seedPose {
            disputeLines.append([
                r.sourcePath, "label_pose",
                r.pose, seed.seedPose, "", "pose-correction",
                "", "", "", ""
            ])
        }

        // --- label_framing ---
        if !seed.seedFraming.isEmpty && r.framing != seed.seedFraming {
            disputeLines.append([
                r.sourcePath, "label_framing",
                r.framing, seed.seedFraming, "", "framing-correction",
                "", "", "", ""
            ])
        }

        // --- label_reason_tags ---
        let blindTags = Set(r.reasonTags.split(separator: "|").map(String.init))
        let seedTags = Set(
            seed.seedReasonTags
                .split(whereSeparator: { $0 == "," || $0 == "|" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
        if blindTags != seedTags {
            let added = !blindTags.subtracting(seedTags).isEmpty
            let removed = !seedTags.subtracting(blindTags).isEmpty
            let delta: String
            if added && removed {
                delta = "tag-swap"
            } else if added {
                delta = "tag-added"
            } else {
                delta = "tag-removed"
            }
            let seedEcho = seedTags.sorted().joined(separator: "|")
            disputeLines.append([
                r.sourcePath, "label_reason_tags",
                r.reasonTags, seedEcho, "", delta,
                "", "", "", ""
            ])
        }
    }

    // Write disputes CSV
    var out = csvLine(DISPUTES_HEADER)
    for line in disputeLines {
        out.append(csvLine(line))
    }
    do {
        try out.write(toFile: DISPUTES_CSV, atomically: true, encoding: .utf8)
    } catch {
        die("failed to write \(DISPUTES_CSV): \(error)")
    }
    print("wrote \(disputeLines.count) dispute rows to \(DISPUTES_CSV)")
}

func verdictDeltaType(blind: String, auto: String) -> String {
    let blindInN = TIER_NEGATIVE.contains(blind)
    let blindInM = TIER_MIDDLE.contains(blind)
    let blindInP = TIER_POSITIVE.contains(blind)
    let autoInN = TIER_NEGATIVE.contains(auto)
    let autoInM = TIER_MIDDLE.contains(auto)
    let autoInP = TIER_POSITIVE.contains(auto)

    if (blindInP || blindInM) && autoInN { return "verdict-upgrade" }
    if blindInN && (autoInP || autoInM) { return "verdict-downgrade" }
    if (blindInP && autoInM) || (blindInM && autoInP) { return "verdict-severity-shift" }
    return "verdict-other"
}

// MARK: - Dry run

func cmdDryRun(_ snapshot: ManifestSnapshot, _ metadata: Metadata) {
    let reviewed = loadReviewed()
    let done = Set(reviewed.map(\.sourcePath))
    let remaining = snapshot.holdoutRowsSorted.filter { !done.contains($0.sourcePath) }
    print("dry-run")
    print("  manifest:      \(MANIFEST_PATH)")
    print("  sha256:        \(snapshot.sha256)")
    print("  holdout rows:  \(snapshot.holdoutRowsSorted.count)")
    print("  already done:  \(done.count)")
    print("  remaining:     \(remaining.count)")
    print("  next source:   \(remaining.first?.sourcePath ?? "<none — complete>")")
    print("  frozen:        \(frozenMarkerExists())")
    print("  metadata file: \(METADATA_JSON)")
    print("  started_at:    \(metadata.startedAt)")
}

// MARK: - Main

func main() {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let cmd = args.first else {
        print("""
        usage:
          swift scripts/blind-relabel.swift --status
          swift scripts/blind-relabel.swift --next
          swift scripts/blind-relabel.swift --commit <source_path> <verdict> <tags> <pose> <framing>
          swift scripts/blind-relabel.swift --disputes
          swift scripts/blind-relabel.swift --dry-run
        """)
        exit(1)
    }
    let snapshot = loadManifest()
    let metadata = loadOrInitMetadata(snapshot)
    _ = metadata

    switch cmd {
    case "--status":
        cmdStatus(snapshot, metadata)
    case "--next":
        cmdNext(snapshot)
    case "--commit":
        cmdCommit(Array(args.dropFirst()), snapshot, metadata)
    case "--disputes":
        cmdDisputes(snapshot)
    case "--dry-run":
        cmdDryRun(snapshot, metadata)
    case "--test-classifier":
        cmdTestClassifier()
    default:
        die("unknown subcommand: \(cmd)")
    }
}

// MARK: - Classifier smoke test

func cmdTestClassifier() {
    var failures: [String] = []

    func expect(_ name: String, _ actual: String, _ want: String) {
        if actual != want {
            failures.append("\(name): expected \(want), got \(actual)")
        }
    }

    // verdictDeltaType matrix — covers both vocabs ('drop' seeded, 'retakeRecommended' runtime).
    expect("keep<->keep",         verdictDeltaType(blind: "keep",              auto: "keep"),              "verdict-other") // equals — caller should filter
    expect("keep<->drop",         verdictDeltaType(blind: "keep",              auto: "drop"),              "verdict-upgrade")
    expect("keep<->retake",       verdictDeltaType(blind: "keep",              auto: "retakeRecommended"), "verdict-upgrade")
    expect("warn<->drop",         verdictDeltaType(blind: "warn",              auto: "drop"),              "verdict-upgrade")
    expect("warn<->retake",       verdictDeltaType(blind: "warn",              auto: "retakeRecommended"), "verdict-upgrade")
    expect("retake<->keep",       verdictDeltaType(blind: "retakeRecommended", auto: "keep"),              "verdict-downgrade")
    expect("retake<->warn",       verdictDeltaType(blind: "retakeRecommended", auto: "warn"),              "verdict-downgrade")
    expect("keep<->warn",         verdictDeltaType(blind: "keep",              auto: "warn"),              "verdict-severity-shift")
    expect("warn<->keep",         verdictDeltaType(blind: "warn",              auto: "keep"),              "verdict-severity-shift")
    expect("retake<->drop",       verdictDeltaType(blind: "retakeRecommended", auto: "drop"),              "verdict-other") // both negative but non-equal; caller filters equals, these are raw-string-different

    // Tag diff — check the three delta types via the inline logic used in cmdDisputes.
    func tagDelta(blind: [String], seed: [String]) -> String {
        let b = Set(blind)
        let s = Set(seed)
        if b == s { return "equal" }
        let added = !b.subtracting(s).isEmpty
        let removed = !s.subtracting(b).isEmpty
        if added && removed { return "tag-swap" }
        if added { return "tag-added" }
        return "tag-removed"
    }
    expect("tag-equal",   tagDelta(blind: ["arms"],       seed: ["arms"]),          "equal")
    expect("tag-added",   tagDelta(blind: ["arms","dark"], seed: ["arms"]),          "tag-added")
    expect("tag-removed", tagDelta(blind: ["arms"],       seed: ["arms","dark"]),    "tag-removed")
    expect("tag-swap",    tagDelta(blind: ["arms","blurry"], seed: ["arms","dark"]), "tag-swap")
    expect("tag-empty-vs-full", tagDelta(blind: [],       seed: ["dark"]),          "tag-removed")
    expect("tag-full-vs-empty", tagDelta(blind: ["dark"], seed: []),                "tag-added")

    // Tag normalization
    expect("norm-pipe",  normalizeReasonTags("arms|dark"),        "arms|dark")
    expect("norm-comma", normalizeReasonTags("dark,arms"),        "arms|dark")
    expect("norm-dups",  normalizeReasonTags("arms,arms,dark"),   "arms|dark")
    expect("norm-space", normalizeReasonTags(" arms , dark "),    "arms|dark")
    expect("norm-empty", normalizeReasonTags(""),                 "")

    if failures.isEmpty {
        print("classifier tests: PASS (16 cases)")
        exit(0)
    } else {
        print("classifier tests: FAIL")
        for f in failures { print("  \(f)") }
        exit(1)
    }
}

main()

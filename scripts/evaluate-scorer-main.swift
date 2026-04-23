// evaluate-scorer-main.swift
//
// Decision-grade evaluator for the unified CheckInScorer (TWO-944 under TWO-941).
//
// Compiles alongside the runtime scorer sources (see scripts/evaluate-scorer
// shell wrapper) so the evaluator never re-implements scorer logic — it calls
// CheckInScorer.assessCaptured directly.
//
// Supports two manifest schemas:
//   - gold-set: 11-image regression floor at scripts/test-images/<filename>
//     header: filename,expected_pose,gold_verdict,...
//   - reviewed-holdout: 83-image blind-labeled holdout from TWO-942
//     header: source_path,split,manifest_row_index,label_keep_verdict,
//             label_reason_tags,label_pose,label_framing,...
//     images resolved via --images-root (default /Users/imraan/Downloads/Client Pictures)
//
// Outputs:
//   - stdout: provenance banner + human-readable summary
//   - scripts/reports/<UTC>_<shortSHA>/summary.txt (human report, includes banner)
//   - scripts/reports/<UTC>_<shortSHA>/rows.csv    (per-image detail)
//
// Provenance banner is fail-hard: missing git SHA, dirty-tree check, or scorer
// source file triggers `exit 2`. TWO-944 contract.
//
// Does NOT modify scorer constants. Plumbing-only ticket.
//

import Foundation
import AppKit
import CoreGraphics
import CryptoKit

// MARK: - Types

enum ManifestSchema: String {
    case gold
    case holdout
}

struct EvalRow {
    let sourcePath: String          // manifest primary key (filename or source_path)
    let imagePath: String           // absolute path on disk
    let expectedPose: Pose?         // nil when manifest says unclear
    let goldVerdictRaw: String      // raw manifest value (keep/warn/retakeRecommended/drop/...)
    let notes: String
}

struct EvalResult {
    let row: EvalRow
    let scorerVerdict: String       // keep/warn/retakeRecommended
    let overallScore: Double
    let subScores: CheckInVisualAssessment.SubScores
    let reasonTags: [String]
    let primaryReason: String
    let match: Bool                 // scorer verdict == gold verdict (using tier mapping)
    let isFalseAccept: Bool
    let isFalseReject: Bool
    let isCatastrophicReject: Bool  // gold=keep, scorer=retakeRecommended
}

// MARK: - Tier bucketing (matches the blind-relabel harness; no silent drop→retake mapping)
// Positive={keep}  Middle={warn}  Negative={drop, retakeRecommended}

enum Tier: String {
    case positive, middle, negative
}

func tier(_ verdict: String) -> Tier? {
    switch verdict {
    case "keep": return .positive
    case "warn": return .middle
    case "drop", "retakeRecommended": return .negative
    default: return nil
    }
}

func verdictsAgree(_ a: String, _ b: String) -> Bool {
    // Equal by tier (so gold='drop' and scorer='retakeRecommended' count as agreement).
    guard let ta = tier(a), let tb = tier(b) else { return false }
    return ta == tb
}

// MARK: - CSV parser (unicode-scalar aware; matches blind-relabel.swift)

func parseCSV(_ text: String) -> [[String]] {
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

func csvEscape(_ field: String) -> String {
    if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    return field
}

func csvLine(_ fields: [String]) -> String {
    fields.map(csvEscape).joined(separator: ",") + "\n"
}

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

func runGit(_ args: [String]) -> (output: String, status: Int32) {
    let task = Process()
    task.launchPath = "/usr/bin/env"
    task.arguments = ["git"] + args
    let pipe = Pipe()
    let err = Pipe()
    task.standardOutput = pipe
    task.standardError = err
    do {
        try task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let s = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (s, task.terminationStatus)
    } catch {
        return ("", -1)
    }
}

func sha256HexPrefix(of path: String, bytes: Int = 16) -> String? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
    let digest = SHA256.hash(data: data)
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return String(hex.prefix(bytes * 2))
}

func padLeft(_ s: String, _ width: Int) -> String {
    if s.count >= width { return s }
    return String(repeating: " ", count: width - s.count) + s
}

func padRight(_ s: String, _ width: Int) -> String {
    if s.count >= width { return s }
    return s + String(repeating: " ", count: width - s.count)
}

// MARK: - CLI

struct CLIArgs {
    var manifestPath: String
    var imagesRoot: String?         // nil → auto (test-images for gold, client pictures for holdout)
    var comparePrior: String?
}

func parseArgs() -> CLIArgs {
    let raw = Array(CommandLine.arguments.dropFirst())
    var manifest: String?
    var imagesRoot: String?
    var comparePrior: String?
    var i = 0
    while i < raw.count {
        let a = raw[i]
        switch a {
        case "--images-root":
            guard i + 1 < raw.count else { die("--images-root requires a path") }
            imagesRoot = raw[i + 1]; i += 2
        case "--compare":
            guard i + 1 < raw.count else { die("--compare requires a prior-run directory") }
            comparePrior = raw[i + 1]; i += 2
        case "--help", "-h":
            print("""
            usage: scripts/evaluate-scorer [manifest.csv] [--images-root <path>] [--compare <prior_run_dir>]

              manifest.csv       gold-set-manifest.csv (default) or a reviewed-holdout.csv
              --images-root      override image root (default: scripts/test-images for gold,
                                 /Users/imraan/Downloads/Client Pictures for holdout)
              --compare <dir>    after running, print a delta vs the given prior run directory
                                 (expects <dir>/rows.csv and <dir>/summary.txt)
            """)
            exit(0)
        default:
            if a.hasPrefix("--") { die("unknown flag: \(a)") }
            if manifest == nil { manifest = a } else { die("unexpected positional arg: \(a)") }
            i += 1
        }
    }
    let defaultManifest = FileManager.default.currentDirectoryPath + "/scripts/gold-set-manifest.csv"
    return CLIArgs(
        manifestPath: manifest ?? defaultManifest,
        imagesRoot: imagesRoot,
        comparePrior: comparePrior
    )
}

// MARK: - Manifest loading

func loadManifest(path: String, imagesRootOverride: String?) -> (schema: ManifestSchema, rows: [EvalRow], imagesRoot: String) {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        die("cannot read manifest at \(path)")
    }
    let parsed = parseCSV(text)
    guard let header = parsed.first else { die("manifest is empty") }

    let schema: ManifestSchema
    if header.contains("filename") {
        schema = .gold
    } else if header.contains("source_path") {
        schema = .holdout
    } else {
        die("manifest header does not match gold or holdout schema: \(header)")
    }

    let root: String = {
        if let override = imagesRootOverride { return override }
        switch schema {
        case .gold:    return FileManager.default.currentDirectoryPath + "/scripts/test-images"
        case .holdout: return "/Users/imraan/Downloads/Client Pictures"
        }
    }()

    func col(_ name: String) -> Int? { header.firstIndex(of: name) }

    var rows: [EvalRow] = []
    switch schema {
    case .gold:
        guard let iName = col("filename"),
              let iPose = col("expected_pose"),
              let iVerdict = col("gold_verdict") else {
            die("gold manifest missing required columns")
        }
        let iNotes = col("notes") ?? -1
        for record in parsed.dropFirst() {
            func f(_ idx: Int) -> String { (idx >= 0 && idx < record.count) ? record[idx] : "" }
            let name = f(iName)
            if name.isEmpty { continue }
            let pose = parsePose(f(iPose))
            rows.append(EvalRow(
                sourcePath: name,
                imagePath: root + "/" + name,
                expectedPose: pose,
                goldVerdictRaw: f(iVerdict),
                notes: f(iNotes)
            ))
        }
    case .holdout:
        guard let iSource = col("source_path"),
              let iPose = col("label_pose"),
              let iVerdict = col("label_keep_verdict") else {
            die("holdout manifest missing required columns")
        }
        for record in parsed.dropFirst() {
            func f(_ idx: Int) -> String { (idx >= 0 && idx < record.count) ? record[idx] : "" }
            let src = f(iSource)
            if src.isEmpty { continue }
            let poseStr = f(iPose)
            let pose = poseStr == "unclear" ? nil : parsePose(poseStr)
            rows.append(EvalRow(
                sourcePath: src,
                imagePath: root + "/" + src,
                expectedPose: pose,
                goldVerdictRaw: f(iVerdict),
                notes: ""
            ))
        }
    }
    return (schema, rows, root)
}

func parsePose(_ s: String) -> Pose? {
    switch s.lowercased() {
    case "front": return .front
    case "side":  return .side
    case "back":  return .back
    default:      return nil
    }
}

// MARK: - Provenance banner (fail-hard)

struct Provenance {
    let utcTimestamp: String
    let gitShortSHA: String
    let gitDirty: Bool
    let scorerSource: String          // resolved absolute path
    let scorerSha256Prefix: String
    let manifestPath: String
    let manifestSha256Prefix: String
    let imagesRoot: String
    let cwd: String
}

func buildProvenance(manifestPath: String, imagesRoot: String) -> Provenance {
    let utc = iso8601UTCNow()

    let (sha, shaStatus) = runGit(["rev-parse", "--short", "HEAD"])
    if shaStatus != 0 || sha.isEmpty {
        die("git rev-parse failed — evaluator must run inside a git repo")
    }

    let (porcelain, statusCode) = runGit(["status", "--porcelain"])
    if statusCode != 0 {
        die("git status failed — evaluator cannot determine dirty-tree flag")
    }
    let dirty = !porcelain.isEmpty

    let cwd = FileManager.default.currentDirectoryPath
    let scorerAbs = cwd + "/ProofCapture/Services/CheckInScorer.swift"
    guard let scorerHash = sha256HexPrefix(of: scorerAbs) else {
        die("cannot hash scorer source at \(scorerAbs)")
    }
    guard let manifestHash = sha256HexPrefix(of: manifestPath) else {
        die("cannot hash manifest at \(manifestPath)")
    }

    return Provenance(
        utcTimestamp: utc,
        gitShortSHA: sha,
        gitDirty: dirty,
        scorerSource: scorerAbs,
        scorerSha256Prefix: scorerHash,
        manifestPath: manifestPath,
        manifestSha256Prefix: manifestHash,
        imagesRoot: imagesRoot,
        cwd: cwd
    )
}

func bannerLines(_ p: Provenance, _ schema: ManifestSchema, _ rowCount: Int) -> [String] {
    [
        String(repeating: "=", count: 80),
        "  CheckInScorer evaluator — decision-grade metrics (TWO-944)",
        "  Manifest schema:   \(schema.rawValue)  (\(rowCount) rows)",
        "  Manifest:          \(p.manifestPath)",
        "  Manifest sha256:   \(p.manifestSha256Prefix)…",
        "  Images root:       \(p.imagesRoot)",
        "  Scorer source:     \(p.scorerSource)",
        "  Scorer sha256:     \(p.scorerSha256Prefix)…",
        "  Git SHA:           \(p.gitShortSHA)\(p.gitDirty ? " (dirty tree — not reproducible)" : "")",
        "  CWD:               \(p.cwd)",
        "  UTC timestamp:     \(p.utcTimestamp)",
        String(repeating: "=", count: 80),
        "",
    ]
}

// MARK: - Evaluation (calls runtime CheckInScorer)

func evaluateRow(_ row: EvalRow) async -> EvalResult? {
    guard let pose = row.expectedPose else {
        // label_pose=unclear — not scorable by CheckInScorer (Pose enum has no unclear).
        return nil
    }
    guard let nsImage = NSImage(contentsOfFile: row.imagePath) else {
        FileHandle.standardError.write(Data("  SKIP (file missing): \(row.sourcePath)\n".utf8))
        return nil
    }
    guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        FileHandle.standardError.write(Data("  SKIP (cgImage extraction failed): \(row.sourcePath)\n".utf8))
        return nil
    }
    let a = await CheckInScorer.assessCaptured(cgImage: cgImage, pose: pose)
    let scorer = a.reviewVerdict.rawValue
    let gold = row.goldVerdictRaw
    let agree = verdictsAgree(scorer, gold)
    let isFA = (tier(gold) == .negative) && (tier(scorer) == .positive || tier(scorer) == .middle)
    let isFR = (tier(gold) == .positive) && (tier(scorer) == .middle || tier(scorer) == .negative)
    let cat = (tier(gold) == .positive) && (tier(scorer) == .negative)

    return EvalResult(
        row: row,
        scorerVerdict: scorer,
        overallScore: a.overallScore,
        subScores: a.subScores,
        reasonTags: a.reasonTags.map(\.rawValue),
        primaryReason: a.primaryReason,
        match: agree,
        isFalseAccept: isFA,
        isFalseReject: isFR,
        isCatastrophicReject: cat
    )
}

// MARK: - Metrics

struct Metrics {
    var total: Int = 0
    var skipped: Int = 0
    var matches: Int = 0

    // Per-pose — only rows with a definite pose.
    var perPoseTotal: [Pose: Int] = [.front: 0, .side: 0, .back: 0]
    var perPoseMatches: [Pose: Int] = [.front: 0, .side: 0, .back: 0]

    // FR: gold=keep → scorer not-keep.  FA: gold=negative → scorer positive-or-middle.
    var keepRows: Int = 0           // denominator for FRR
    var negativeRows: Int = 0       // denominator for FAR
    var falseRejects: Int = 0
    var falseAccepts: Int = 0
    var catastrophicRejects: Int = 0

    // 3×3 confusion. gold tier → scorer tier (raw runtime vocab for scorer).
    // Gold negative covers {drop, retakeRecommended}; we row-bucket by tier but print labels.
    var confusion: [String: [String: Int]] = [:]  // [goldTier][scorerTier]

    // Reason-tag frequency on mismatched rows (diagnostic for calibration).
    var mismatchTagCounts: [String: Int] = [:]

    mutating func add(_ r: EvalResult) {
        total += 1
        if r.match { matches += 1 }
        if let p = r.row.expectedPose {
            perPoseTotal[p]! += 1
            if r.match { perPoseMatches[p]! += 1 }
        }
        if let gt = tier(r.row.goldVerdictRaw) {
            let st = tier(r.scorerVerdict) ?? .negative
            let goldKey = gt.rawValue
            let scorerKey = st.rawValue
            confusion[goldKey, default: [:]][scorerKey, default: 0] += 1
            if gt == .positive { keepRows += 1 }
            if gt == .negative { negativeRows += 1 }
        }
        if r.isFalseAccept { falseAccepts += 1 }
        if r.isFalseReject { falseRejects += 1 }
        if r.isCatastrophicReject { catastrophicRejects += 1 }
        if !r.match {
            for t in r.reasonTags {
                mismatchTagCounts[t, default: 0] += 1
            }
        }
    }

    var agreementPct: Double { total == 0 ? 0 : Double(matches) / Double(total) * 100 }
    var frrPct: Double { keepRows == 0 ? 0 : Double(falseRejects) / Double(keepRows) * 100 }
    var farPct: Double { negativeRows == 0 ? 0 : Double(falseAccepts) / Double(negativeRows) * 100 }

    func perPosePct(_ p: Pose) -> Double {
        let total = perPoseTotal[p] ?? 0
        let matches = perPoseMatches[p] ?? 0
        return total == 0 ? 0 : Double(matches) / Double(total) * 100
    }
}

func summaryLines(_ m: Metrics) -> [String] {
    var lines: [String] = []
    lines.append("AGGREGATE")
    lines.append("  Total scored:        \(m.total)  (skipped \(m.skipped))")
    lines.append("  Agreement:           \(String(format: "%.1f", m.agreementPct))%  (\(m.matches)/\(m.total))")
    lines.append("")
    lines.append("PER-POSE AGREEMENT")
    for p in [Pose.front, .side, .back] {
        let total = m.perPoseTotal[p] ?? 0
        let matches = m.perPoseMatches[p] ?? 0
        lines.append("  \(padRight(p.title.lowercased(), 20)) \(String(format: "%.1f", m.perPosePct(p)))%  (\(matches)/\(total))")
    }
    lines.append("")
    lines.append("FALSE REJECT / FALSE ACCEPT")
    lines.append("  FRR (gold=keep → scorer not-keep):          \(String(format: "%.1f", m.frrPct))%  (\(m.falseRejects)/\(m.keepRows))")
    lines.append("  FAR (gold=drop|retake → scorer keep|warn):  \(String(format: "%.1f", m.farPct))%  (\(m.falseAccepts)/\(m.negativeRows))")
    lines.append("  Catastrophic (keep → retakeRecommended):    \(m.catastrophicRejects)")
    lines.append("")
    lines.append("CONFUSION MATRIX (rows=gold tier, cols=scorer tier)")
    let tiers = ["positive", "middle", "negative"]
    let colHead = "              " + tiers.map { padLeft($0, 10) }.joined()
    lines.append(colHead)
    for g in tiers {
        let row = tiers.map { s -> String in
            let n = m.confusion[g]?[s] ?? 0
            return padLeft(String(n), 10)
        }.joined()
        lines.append("  " + padRight(g, 12) + row)
    }
    lines.append("  (positive = keep | middle = warn | negative = drop + retakeRecommended)")
    lines.append("")
    lines.append("TOP MISMATCH REASON TAGS (scorer's tags on rows where verdict disagreed)")
    let top = m.mismatchTagCounts.sorted {
        $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
    }.prefix(10)
    if top.isEmpty {
        lines.append("  (none — all rows agreed)")
    } else {
        for (tag, count) in top {
            lines.append("  \(padLeft(String(count), 4))  \(tag)")
        }
    }
    return lines
}

// MARK: - Per-row CSV output

let ROWS_HEADER = [
    "source_path",
    "expected_pose",
    "gold_verdict_raw",
    "scorer_verdict",
    "overall_score",
    "def_lighting",
    "framing",
    "pose_accuracy",
    "pose_neutrality",
    "sharpness",
    "reason_tags",
    "primary_reason",
    "match",
    "false_accept",
    "false_reject",
    "catastrophic_reject",
]

func rowCSVLine(_ r: EvalResult) -> String {
    func f(_ d: Double) -> String { String(format: "%.3f", d) }
    let poseStr = r.row.expectedPose.map { $0.title.lowercased() } ?? ""
    return csvLine([
        r.row.sourcePath,
        poseStr,
        r.row.goldVerdictRaw,
        r.scorerVerdict,
        f(r.overallScore),
        f(r.subScores.definitionLighting),
        f(r.subScores.framing),
        f(r.subScores.poseAccuracy),
        f(r.subScores.poseNeutrality),
        r.subScores.sharpness.map(f) ?? "",
        r.reasonTags.joined(separator: "|"),
        r.primaryReason,
        r.match ? "1" : "0",
        r.isFalseAccept ? "1" : "0",
        r.isFalseReject ? "1" : "0",
        r.isCatastrophicReject ? "1" : "0",
    ])
}

// MARK: - Artifact writing

func writeArtifacts(reportDir: String, bannerLines banner: [String], summaryLines summary: [String], results: [EvalResult], skippedRows: [EvalRow]) {
    let fm = FileManager.default
    do {
        try fm.createDirectory(atPath: reportDir, withIntermediateDirectories: true)
    } catch {
        die("cannot create report dir \(reportDir): \(error)")
    }
    // summary.txt
    let summaryText = (banner + summary + [
        "",
        "SKIPPED ROWS (\(skippedRows.count))",
    ] + skippedRows.map { "  \($0.sourcePath)  \($0.notes.isEmpty ? "(no pose / missing file / cgImage failure)" : $0.notes)" }
    + [""]).joined(separator: "\n")
    do {
        try summaryText.write(toFile: reportDir + "/summary.txt", atomically: true, encoding: .utf8)
    } catch {
        die("cannot write summary.txt: \(error)")
    }
    // rows.csv
    var rowsCSV = csvLine(ROWS_HEADER)
    for r in results { rowsCSV.append(rowCSVLine(r)) }
    do {
        try rowsCSV.write(toFile: reportDir + "/rows.csv", atomically: true, encoding: .utf8)
    } catch {
        die("cannot write rows.csv: \(error)")
    }
}

// MARK: - Compare mode

struct PriorRun {
    let summaryText: String
    let rows: [[String: String]]
    let agreementPct: Double
    let frrPct: Double
    let farPct: Double
    let perPose: [String: Double]   // "front"/"side"/"back" → %
    let topTags: [String]
}

func parsePct(_ s: String) -> Double? {
    let cleaned = s.trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "%", with: "")
    return Double(cleaned)
}

func loadPriorRun(_ dir: String) -> PriorRun {
    let summaryPath = dir + "/summary.txt"
    let rowsPath = dir + "/rows.csv"
    guard let summary = try? String(contentsOfFile: summaryPath, encoding: .utf8) else {
        die("cannot read prior summary at \(summaryPath)")
    }
    guard let rowsText = try? String(contentsOfFile: rowsPath, encoding: .utf8) else {
        die("cannot read prior rows at \(rowsPath)")
    }

    // Extract known lines.
    var agreement: Double = 0
    var frr: Double = 0
    var far: Double = 0
    var perPose: [String: Double] = [:]
    var topTags: [String] = []

    // Grab the first "X%" token after a colon; robust against variable whitespace.
    func firstPctAfterColon(_ line: String) -> Double? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let after = String(line[line.index(after: colon)...])
        let tokens = after.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        for tok in tokens {
            if tok.contains("%"), let v = parsePct(tok) { return v }
        }
        return nil
    }

    var inTags = false
    for line in summary.components(separatedBy: "\n") {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("Agreement:") {
            if let v = firstPctAfterColon(t) { agreement = v }
        } else if t.hasPrefix("FRR ") {
            if let v = firstPctAfterColon(t) { frr = v }
        } else if t.hasPrefix("FAR ") {
            if let v = firstPctAfterColon(t) { far = v }
        } else if t.hasPrefix("front ") || t.hasPrefix("side ") || t.hasPrefix("back ") {
            let parts = t.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if parts.count >= 2, let v = parsePct(parts[1]) {
                perPose[parts[0]] = v
            }
        } else if t.hasPrefix("TOP MISMATCH REASON TAGS") {
            inTags = true
        } else if inTags {
            if t.isEmpty { inTags = false } else {
                let parts = t.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 2 { topTags.append(parts.last!) }
            }
        }
    }

    // Parse rows.csv for detailed diff.
    let parsed = parseCSV(rowsText)
    var rowDicts: [[String: String]] = []
    if let header = parsed.first {
        for rec in parsed.dropFirst() {
            var d: [String: String] = [:]
            for (i, k) in header.enumerated() {
                d[k] = i < rec.count ? rec[i] : ""
            }
            rowDicts.append(d)
        }
    }

    return PriorRun(
        summaryText: summary,
        rows: rowDicts,
        agreementPct: agreement,
        frrPct: frr,
        farPct: far,
        perPose: perPose,
        topTags: topTags
    )
}

func compareLines(current: Metrics, prior: PriorRun) -> [String] {
    func delta(_ now: Double, _ was: Double) -> String {
        let d = now - was
        let sign = d >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", d)) pp"
    }
    var lines: [String] = []
    lines.append("")
    lines.append("COMPARE vs prior run")
    lines.append("  Agreement:   \(String(format: "%.1f", current.agreementPct))%  (was \(String(format: "%.1f", prior.agreementPct))%, \(delta(current.agreementPct, prior.agreementPct)))")
    lines.append("  FRR:         \(String(format: "%.1f", current.frrPct))%  (was \(String(format: "%.1f", prior.frrPct))%, \(delta(current.frrPct, prior.frrPct)))")
    lines.append("  FAR:         \(String(format: "%.1f", current.farPct))%  (was \(String(format: "%.1f", prior.farPct))%, \(delta(current.farPct, prior.farPct)))")
    lines.append("  Per-pose:")
    for p in [Pose.front, .side, .back] {
        let key = p.title.lowercased()
        let now = current.perPosePct(p)
        let was = prior.perPose[key] ?? 0
        lines.append("    \(padRight(key, 10)) \(String(format: "%.1f", now))%  (was \(String(format: "%.1f", was))%, \(delta(now, was)))")
    }
    // Reason-tag churn: new top tags vs prior, vanished tags.
    let currentTop = current.mismatchTagCounts.sorted {
        $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
    }.prefix(10).map { $0.key }
    let priorTop = Set(prior.topTags)
    let currentSet = Set(currentTop)
    let newTags = currentTop.filter { !priorTop.contains($0) }
    let vanishedTags = prior.topTags.filter { !currentSet.contains($0) }
    lines.append("  Reason-tag churn:")
    lines.append("    new in top-10:      \(newTags.isEmpty ? "(none)" : newTags.joined(separator: ", "))")
    lines.append("    vanished from top:  \(vanishedTags.isEmpty ? "(none)" : vanishedTags.joined(separator: ", "))")
    return lines
}

// MARK: - Main

func runEvaluation() async {
    let cli = parseArgs()
    let (schema, rows, imagesRoot) = loadManifest(path: cli.manifestPath, imagesRootOverride: cli.imagesRoot)
    if rows.isEmpty { die("manifest loaded but contained 0 data rows") }

    let provenance = buildProvenance(manifestPath: cli.manifestPath, imagesRoot: imagesRoot)
    let banner = bannerLines(provenance, schema, rows.count)
    for line in banner { print(line) }

    var metrics = Metrics()
    var results: [EvalResult] = []
    var skipped: [EvalRow] = []

    for (idx, row) in rows.enumerated() {
        print("  [\(idx + 1)/\(rows.count)] \(row.sourcePath)")
        if let r = await evaluateRow(row) {
            metrics.add(r)
            results.append(r)
        } else {
            metrics.skipped += 1
            skipped.append(row)
        }
    }

    print("")
    let summary = summaryLines(metrics)
    for line in summary { print(line) }

    let reportDir = "scripts/reports/\(provenance.utcTimestamp.replacingOccurrences(of: ":", with: ""))_\(provenance.gitShortSHA)\(provenance.gitDirty ? "-dirty" : "")"
    writeArtifacts(reportDir: reportDir, bannerLines: banner, summaryLines: summary, results: results, skippedRows: skipped)
    print("")
    print("  Report written to: \(reportDir)/")

    if let priorDir = cli.comparePrior {
        let prior = loadPriorRun(priorDir)
        let compareLs = compareLines(current: metrics, prior: prior)
        for line in compareLs { print(line) }
        // Append compare section to summary.txt too.
        let appendix = "\n" + compareLs.joined(separator: "\n") + "\n"
        let summaryPath = reportDir + "/summary.txt"
        if let current = try? String(contentsOfFile: summaryPath, encoding: .utf8) {
            try? (current + appendix).write(toFile: summaryPath, atomically: true, encoding: .utf8)
        }
    }
}

@main
struct EvaluateScorer {
    static func main() async {
        await runEvaluation()
    }
}

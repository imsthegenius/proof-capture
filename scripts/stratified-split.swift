#!/usr/bin/env swift
//
// stratified-split.swift
//
// Deterministic 63/20 stratified split of the frozen reviewed-holdout (TWO-945
// under TWO-941). Consumes the frozen reviewed-holdout.csv from TWO-942 and
// emits `scripts/tuning-holdout.csv` (63 rows) + `scripts/blind-holdout.csv`
// (20 rows), both gitignored (carry client-folder source_path values).
//
// Scope boundary: this script splits the reviewed set. It does NOT modify the
// scorer, scorer constants, the reviewed manifest, or the dispute CSV. TWO-946
// is responsible for calibration.
//
// Stratification:
//   - Strata = (label_pose × label_keep_verdict). Poses: front/side/back.
//     Rows with pose=unclear are included in aggregate counts but kept in
//     the tuning set (they cannot be used for per-pose metrics anyway).
//   - Blind quota per stratum: largest-remainder rounding of
//     (20 × n_stratum / total_scorable).
//   - Back-pose floor: blind contains >= 4 back rows; tuning >= 12. When the
//     initial allocation misses the floor, rows are moved from the largest
//     non-back blind stratum into the back stratum with the most remaining
//     capacity, deterministically.
//
// Determinism:
//   - Input file must match the SHA-256 recorded in scripts/split-metadata.json
//     on the second + subsequent invocations (drift guard, like blind-relabel).
//   - Within a stratum, rows are ordered by SHA-256("<seed>:<source_path>"), so
//     a fixed seed reproduces the split byte-for-byte.
//   - Default seed is 0.
//
// Usage:
//   swift scripts/stratified-split.swift [--seed N] [--input <path>]
//                                        [--frozen-marker <path>]
//                                        [--out-dir <dir>]
//                                        [--stdout blind|tuning]
//

import Foundation
import CryptoKit

// MARK: - Defaults (TWO-942 worktree is the canonical frozen data home)

let DEFAULT_INPUT = "/Users/imraan/Desktop/proof-capture/.claude/worktrees/two-942-blind-relabel-harness/scripts/reviewed-holdout.csv"
let DEFAULT_FROZEN = "/Users/imraan/Desktop/proof-capture/.claude/worktrees/two-942-blind-relabel-harness/scripts/reviewed-holdout.csv.frozen"
let DEFAULT_OUT_DIR = "scripts"

let TARGET_BLIND = 20
let TARGET_TUNING = 63
let BLIND_BACK_MIN = 4
let TUNING_BACK_MIN = 12
let SCHEMA_VERSION = 1

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
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func sha256HexString(_ s: String) -> String {
    sha256Hex(Data(s.utf8))
}

func shortGitSHA() -> String {
    let t = Process()
    t.launchPath = "/usr/bin/env"
    t.arguments = ["git", "rev-parse", "--short", "HEAD"]
    let pipe = Pipe()
    t.standardOutput = pipe
    t.standardError = Pipe()
    do {
        try t.run(); t.waitUntilExit()
        guard t.terminationStatus == 0 else { return "unknown" }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
    } catch { return "unknown" }
}

func gitDirty() -> Bool {
    let t = Process()
    t.launchPath = "/usr/bin/env"
    t.arguments = ["git", "status", "--porcelain"]
    let pipe = Pipe()
    t.standardOutput = pipe
    t.standardError = Pipe()
    do {
        try t.run(); t.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    } catch { return true }
}

// MARK: - CSV parser (unicode-scalar aware; same as blind-relabel.swift)

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
                    field.append("\""); i += 2
                } else {
                    inQuotes = false; i += 1
                }
            } else {
                field.unicodeScalars.append(s); i += 1
            }
        } else {
            if s == QUOTE { inQuotes = true; i += 1 }
            else if s == COMMA { current.append(field); field = ""; i += 1 }
            else if s == LF || s == CR {
                current.append(field); field = ""
                if !current.allSatisfy({ $0.isEmpty }) { rows.append(current) }
                current = []
                if s == CR && i + 1 < n && scalars[i + 1] == LF { i += 2 } else { i += 1 }
            } else {
                field.unicodeScalars.append(s); i += 1
            }
        }
    }
    if !(field.isEmpty && current.isEmpty) {
        current.append(field)
        if !current.allSatisfy({ $0.isEmpty }) { rows.append(current) }
    }
    return rows
}

func csvEscape(_ f: String) -> String {
    if f.contains(",") || f.contains("\"") || f.contains("\n") || f.contains("\r") {
        return "\"" + f.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    return f
}

func csvLine(_ fields: [String]) -> String {
    fields.map(csvEscape).joined(separator: ",") + "\n"
}

// MARK: - Row

struct Row {
    let raw: [String: String]    // full reviewed row
    let pose: String
    let verdict: String
    let sourcePath: String

    func serialize() -> String {
        csvLine(REVIEWED_HEADER.map { raw[$0] ?? "" })
    }
}

// MARK: - CLI

struct Args {
    var seed: Int = 0
    var input: String = DEFAULT_INPUT
    var frozenMarker: String = DEFAULT_FROZEN
    var outDir: String = DEFAULT_OUT_DIR
    var stdoutSet: String? = nil    // "blind" | "tuning" | nil
}

func parseArgs() -> Args {
    let argv = Array(CommandLine.arguments.dropFirst())
    var a = Args()
    var i = 0
    while i < argv.count {
        let x = argv[i]
        switch x {
        case "--seed":
            guard i + 1 < argv.count, let v = Int(argv[i + 1]) else { die("--seed requires an int") }
            a.seed = v; i += 2
        case "--input":
            guard i + 1 < argv.count else { die("--input requires a path") }
            a.input = argv[i + 1]; i += 2
        case "--frozen-marker":
            guard i + 1 < argv.count else { die("--frozen-marker requires a path") }
            a.frozenMarker = argv[i + 1]; i += 2
        case "--out-dir":
            guard i + 1 < argv.count else { die("--out-dir requires a path") }
            a.outDir = argv[i + 1]; i += 2
        case "--stdout":
            guard i + 1 < argv.count else { die("--stdout requires 'blind' or 'tuning'") }
            let v = argv[i + 1]
            guard v == "blind" || v == "tuning" else { die("--stdout value must be blind or tuning") }
            a.stdoutSet = v; i += 2
        case "--help", "-h":
            print("""
            usage: swift scripts/stratified-split.swift [--seed N] [--input <path>]
                                                        [--frozen-marker <path>]
                                                        [--out-dir <dir>]
                                                        [--stdout blind|tuning]
            """)
            exit(0)
        default:
            die("unknown arg: \(x)")
        }
    }
    return a
}

// MARK: - Load

func loadRows(inputPath: String, frozenPath: String) -> (rows: [Row], inputSha: String) {
    if !FileManager.default.fileExists(atPath: frozenPath) {
        die("frozen marker missing at \(frozenPath) — reviewed-holdout is not committed for split")
    }
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: inputPath)) else {
        die("cannot read input at \(inputPath)")
    }
    let sha = sha256Hex(data)
    guard let text = String(data: data, encoding: .utf8) else { die("input is not valid UTF-8") }
    let parsed = parseCSV(text)
    guard let header = parsed.first else { die("input has no header") }
    for col in REVIEWED_HEADER {
        if !header.contains(col) { die("input header missing required column: \(col)") }
    }
    var rows: [Row] = []
    for rec in parsed.dropFirst() {
        var dict: [String: String] = [:]
        for (idx, key) in header.enumerated() {
            dict[key] = idx < rec.count ? rec[idx] : ""
        }
        rows.append(Row(
            raw: dict,
            pose: dict["label_pose"] ?? "",
            verdict: dict["label_keep_verdict"] ?? "",
            sourcePath: dict["source_path"] ?? ""
        ))
    }
    return (rows, sha)
}

// MARK: - Stratified allocation

struct StratumKey: Hashable, Comparable {
    let pose: String
    let verdict: String
    var label: String { "\(pose)/\(verdict)" }

    static func < (l: StratumKey, r: StratumKey) -> Bool {
        if l.pose != r.pose { return l.pose < r.pose }
        return l.verdict < r.verdict
    }
}

func allocateQuotas(strata: [StratumKey: [Row]], targetBlind: Int) -> [StratumKey: Int] {
    let total = strata.values.reduce(0) { $0 + $1.count }
    var quota: [StratumKey: Int] = [:]
    var remainder: [(StratumKey, Double)] = []

    for (key, rows) in strata {
        let ideal = Double(targetBlind) * Double(rows.count) / Double(total)
        let floored = Int(ideal.rounded(.down))
        quota[key] = floored
        remainder.append((key, ideal - Double(floored)))
    }

    var deficit = targetBlind - quota.values.reduce(0, +)
    // Sort remainders desc, tiebreak by stratum key for determinism.
    remainder.sort { (a, b) in
        if a.1 != b.1 { return a.1 > b.1 }
        return a.0 < b.0
    }
    var r = 0
    while deficit > 0 && r < remainder.count {
        let key = remainder[r].0
        if (quota[key] ?? 0) < (strata[key]?.count ?? 0) {
            quota[key]! += 1
            deficit -= 1
        }
        r += 1
    }
    // If still deficit (unlikely), cycle once more adding to any stratum with capacity.
    while deficit > 0 {
        var moved = false
        for key in strata.keys.sorted() {
            if (quota[key] ?? 0) < (strata[key]?.count ?? 0) {
                quota[key]! += 1
                deficit -= 1
                moved = true
                if deficit == 0 { break }
            }
        }
        if !moved { break }
    }
    return quota
}

func enforceBackFloor(
    strata: [StratumKey: [Row]],
    quota: inout [StratumKey: Int],
    minBack: Int
) {
    func sumBack() -> Int {
        strata.keys.filter { $0.pose == "back" }.reduce(0) { $0 + (quota[$1] ?? 0) }
    }
    while sumBack() < minBack {
        // Pick the back stratum with the most remaining capacity (count - quota). Tiebreak by key.
        let backKeys = strata.keys.filter { $0.pose == "back" }
            .sorted { (a, b) in
                let capA = (strata[a]?.count ?? 0) - (quota[a] ?? 0)
                let capB = (strata[b]?.count ?? 0) - (quota[b] ?? 0)
                if capA != capB { return capA > capB }
                return a < b
            }
        guard let backRecipient = backKeys.first,
              (strata[backRecipient]?.count ?? 0) - (quota[backRecipient] ?? 0) > 0 else {
            die("cannot satisfy back-pose blind floor: not enough back rows in corpus")
        }
        // Pick the non-back stratum with the largest current quota (donor). Tiebreak by key.
        let donorKeys = strata.keys.filter { $0.pose != "back" }
            .sorted { (a, b) in
                let qa = quota[a] ?? 0
                let qb = quota[b] ?? 0
                if qa != qb { return qa > qb }
                return a < b
            }
        guard let donor = donorKeys.first(where: { (quota[$0] ?? 0) > 0 }) else {
            die("cannot satisfy back-pose blind floor: no non-back donor available")
        }
        quota[donor]! -= 1
        quota[backRecipient]! += 1
    }
}

func enforceTuningBackFloor(
    strata: [StratumKey: [Row]],
    quota: inout [StratumKey: Int],
    minTuningBack: Int
) {
    let totalBack = strata.keys.filter { $0.pose == "back" }
        .reduce(0) { $0 + (strata[$1]?.count ?? 0) }
    func blindBack() -> Int {
        strata.keys.filter { $0.pose == "back" }.reduce(0) { $0 + (quota[$1] ?? 0) }
    }
    while totalBack - blindBack() < minTuningBack {
        // Move a back row OUT of blind (reduce a back stratum quota) in favour of a non-back donor recipient.
        let backDonors = strata.keys.filter { $0.pose == "back" && (quota[$0] ?? 0) > 0 }
            .sorted { (a, b) in
                let qa = quota[a] ?? 0
                let qb = quota[b] ?? 0
                if qa != qb { return qa > qb }
                return a < b
            }
        guard let donor = backDonors.first else {
            die("cannot satisfy tuning back-pose floor: blind already has zero back rows")
        }
        let nonBack = strata.keys.filter { $0.pose != "back" }
            .sorted { (a, b) in
                let capA = (strata[a]?.count ?? 0) - (quota[a] ?? 0)
                let capB = (strata[b]?.count ?? 0) - (quota[b] ?? 0)
                if capA != capB { return capA > capB }
                return a < b
            }
        guard let recipient = nonBack.first,
              (strata[recipient]?.count ?? 0) - (quota[recipient] ?? 0) > 0 else {
            die("cannot satisfy tuning back-pose floor: no non-back recipient has capacity")
        }
        quota[donor]! -= 1
        quota[recipient]! += 1
    }
}

// MARK: - Split

func runSplit(_ args: Args) {
    let (allRows, inputSha) = loadRows(inputPath: args.input, frozenPath: args.frozenMarker)

    // Exclude pose=unclear from strata; those rows go straight to tuning.
    let scorable = allRows.filter { $0.pose != "unclear" && !$0.pose.isEmpty }
    let unclear = allRows.filter { $0.pose == "unclear" || $0.pose.isEmpty }

    // Build strata.
    var strata: [StratumKey: [Row]] = [:]
    for row in scorable {
        let key = StratumKey(pose: row.pose, verdict: row.verdict)
        strata[key, default: []].append(row)
    }

    // Allocate blind quotas (target is still TARGET_BLIND even though unclear rows sit out of strata;
    // we take all 20 from scorable since unclear contributes to tuning only).
    var quota = allocateQuotas(strata: strata, targetBlind: TARGET_BLIND)

    // Back-pose floors.
    enforceBackFloor(strata: strata, quota: &quota, minBack: BLIND_BACK_MIN)
    enforceTuningBackFloor(strata: strata, quota: &quota, minTuningBack: TUNING_BACK_MIN)

    // Deterministic selection within each stratum.
    var blindRows: [Row] = []
    var tuningRows: [Row] = []
    for key in strata.keys.sorted() {
        let rowsHere = strata[key]!
        let ordered = rowsHere.sorted { (a, b) in
            let ha = sha256HexString("\(args.seed):\(a.sourcePath)")
            let hb = sha256HexString("\(args.seed):\(b.sourcePath)")
            return ha < hb
        }
        let q = quota[key] ?? 0
        blindRows.append(contentsOf: ordered.prefix(q))
        tuningRows.append(contentsOf: ordered.dropFirst(q))
    }
    tuningRows.append(contentsOf: unclear)

    // Sort both outputs by source_path ASCII for diff-stable files.
    blindRows.sort { $0.sourcePath < $1.sourcePath }
    tuningRows.sort { $0.sourcePath < $1.sourcePath }

    // Guard invariants.
    if blindRows.count != TARGET_BLIND {
        die("invariant failed: blind count \(blindRows.count) != \(TARGET_BLIND)")
    }
    if tuningRows.count != TARGET_TUNING {
        die("invariant failed: tuning count \(tuningRows.count) != \(TARGET_TUNING)")
    }
    let blindBack = blindRows.filter { $0.pose == "back" }.count
    let tuningBack = tuningRows.filter { $0.pose == "back" }.count
    if blindBack < BLIND_BACK_MIN { die("invariant failed: blind back \(blindBack) < \(BLIND_BACK_MIN)") }
    if tuningBack < TUNING_BACK_MIN { die("invariant failed: tuning back \(tuningBack) < \(TUNING_BACK_MIN)") }

    // stdout mode.
    if let set = args.stdoutSet {
        let chosen = set == "blind" ? blindRows : tuningRows
        var out = csvLine(REVIEWED_HEADER)
        for r in chosen { out.append(r.serialize()) }
        FileHandle.standardOutput.write(Data(out.utf8))
        return
    }

    // File outputs.
    let blindPath = args.outDir + "/blind-holdout.csv"
    let tuningPath = args.outDir + "/tuning-holdout.csv"
    var blindOut = csvLine(REVIEWED_HEADER)
    for r in blindRows { blindOut.append(r.serialize()) }
    var tuningOut = csvLine(REVIEWED_HEADER)
    for r in tuningRows { tuningOut.append(r.serialize()) }

    do {
        try blindOut.write(toFile: blindPath, atomically: true, encoding: .utf8)
        try tuningOut.write(toFile: tuningPath, atomically: true, encoding: .utf8)
    } catch {
        die("cannot write output csvs: \(error)")
    }

    // Manifest (no source_paths — safe to commit).
    let manifestPath = args.outDir + "/split-manifest.md"
    let poses = ["front", "side", "back", "unclear"]
    let verdicts = ["keep", "warn", "retakeRecommended"]

    func countBy(rows: [Row], pose: String, verdict: String) -> Int {
        rows.filter { $0.pose == pose && $0.verdict == verdict }.count
    }
    func totalByPose(rows: [Row], pose: String) -> Int {
        rows.filter { $0.pose == pose }.count
    }
    func totalByVerdict(rows: [Row], verdict: String) -> Int {
        rows.filter { $0.verdict == verdict }.count
    }

    var md = ""
    md += "# Stratified Split Manifest — TWO-945\n\n"
    md += "Run timestamp: \(iso8601UTCNow())\n"
    md += "Git SHA: \(shortGitSHA())\(gitDirty() ? " (dirty tree — not reproducible)" : "")\n"
    md += "Seed: \(args.seed)\n"
    md += "Schema version: \(SCHEMA_VERSION)\n"
    md += "Input: \(args.input)\n"
    md += "Input sha256: \(inputSha)\n"
    md += "Frozen marker: \(args.frozenMarker)\n\n"
    md += "## Row counts\n\n"
    md += "- Reviewed total: \(allRows.count)\n"
    md += "- Blind: \(blindRows.count) (target \(TARGET_BLIND))\n"
    md += "- Tuning: \(tuningRows.count) (target \(TARGET_TUNING))\n\n"
    md += "## Back-pose floor\n\n"
    md += "- Blind back: \(blindBack) (floor \(BLIND_BACK_MIN)) — \(blindBack >= BLIND_BACK_MIN ? "PASS" : "FAIL")\n"
    md += "- Tuning back: \(tuningBack) (floor \(TUNING_BACK_MIN)) — \(tuningBack >= TUNING_BACK_MIN ? "PASS" : "FAIL")\n\n"

    md += "## Pose × verdict — BLIND set\n\n"
    md += "| pose | keep | warn | retakeRecommended | total |\n"
    md += "|---|---|---|---|---|\n"
    for p in poses {
        let t = totalByPose(rows: blindRows, pose: p)
        if t == 0 { continue }
        let ks = verdicts.map { countBy(rows: blindRows, pose: p, verdict: $0) }
        md += "| \(p) | \(ks[0]) | \(ks[1]) | \(ks[2]) | \(t) |\n"
    }
    md += "| **TOTAL** | \(totalByVerdict(rows: blindRows, verdict: "keep")) | \(totalByVerdict(rows: blindRows, verdict: "warn")) | \(totalByVerdict(rows: blindRows, verdict: "retakeRecommended")) | \(blindRows.count) |\n\n"

    md += "## Pose × verdict — TUNING set\n\n"
    md += "| pose | keep | warn | retakeRecommended | total |\n"
    md += "|---|---|---|---|---|\n"
    for p in poses {
        let t = totalByPose(rows: tuningRows, pose: p)
        if t == 0 { continue }
        let ks = verdicts.map { countBy(rows: tuningRows, pose: p, verdict: $0) }
        md += "| \(p) | \(ks[0]) | \(ks[1]) | \(ks[2]) | \(t) |\n"
    }
    md += "| **TOTAL** | \(totalByVerdict(rows: tuningRows, verdict: "keep")) | \(totalByVerdict(rows: tuningRows, verdict: "warn")) | \(totalByVerdict(rows: tuningRows, verdict: "retakeRecommended")) | \(tuningRows.count) |\n\n"

    md += "## Quota allocation per stratum\n\n"
    md += "| stratum | corpus | blind quota | tuning quota |\n"
    md += "|---|---|---|---|\n"
    for key in strata.keys.sorted() {
        let q = quota[key] ?? 0
        let n = strata[key]?.count ?? 0
        md += "| \(key.label) | \(n) | \(q) | \(n - q) |\n"
    }
    if !unclear.isEmpty {
        md += "| unclear (excluded from strata → tuning) | \(unclear.count) | 0 | \(unclear.count) |\n"
    }
    md += "\n## Determinism\n\n"
    md += "- Within each stratum, rows ordered by `sha256(\"<seed>:<source_path>\")`.\n"
    md += "- Re-running with the same seed + same input bytes produces byte-identical outputs.\n"
    md += "- Input sha256 at split time: `\(inputSha.prefix(16))…` — TWO-946 calibration refuses to run if the input hash drifts.\n"

    do {
        try md.write(toFile: manifestPath, atomically: true, encoding: .utf8)
    } catch {
        die("cannot write split manifest: \(error)")
    }

    print("split generated (seed=\(args.seed)):")
    print("  blind:   \(blindPath) (\(blindRows.count) rows, back=\(blindBack))")
    print("  tuning:  \(tuningPath) (\(tuningRows.count) rows, back=\(tuningBack))")
    print("  manifest:\(manifestPath)")
}

// MARK: - Main

runSplit(parseArgs())

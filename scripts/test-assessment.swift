#!/usr/bin/env swift
//
// test-assessment.swift
// Unit tests for CheckInVisualAssessment score computation and override logic.
// Run: swift scripts/test-assessment.swift
//

import Foundation

// MARK: - Mirrored types (from CheckInVisualAssessment.swift)

enum Mode: String { case live, captured }
enum LiveState: String { case blocked, guiding, ready }
enum ReviewVerdict: String { case keep, warn, retakeRecommended }

enum ReasonTag: String {
    case bodyNotDetected, wrongPose, severeCrop, severeBacklight, severeBlur
    case headMissing, feetMissing, tooClose, tooFar, offCenter
    case flatLighting, weakDefinition, mildBacklight, tooDark, tooBright
    case stagedPose, poseUnclear, mildBlur

    var isCatastrophicLive: Bool {
        switch self {
        case .bodyNotDetected, .wrongPose, .severeCrop, .severeBacklight: return true
        default: return false
        }
    }
    var isCatastrophicCaptured: Bool {
        switch self {
        case .bodyNotDetected, .wrongPose, .severeCrop, .severeBacklight, .severeBlur: return true
        default: return false
        }
    }
}

struct SubScores {
    var definitionLighting: Double
    var framing: Double
    var poseAccuracy: Double
    var poseNeutrality: Double
    var sharpness: Double?
}

struct Assessment {
    let mode: Mode
    let overallScore: Double
    let liveState: LiveState
    let reviewVerdict: ReviewVerdict
    let reasonTags: [ReasonTag]
}

// Weights
let wDef = 0.45, wFrm = 0.20, wPose = 0.15, wNeut = 0.10, wSharp = 0.10

func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }

func compute(subScores s: SubScores, tags: [ReasonTag], mode: Mode) -> Assessment {
    let overall: Double
    if mode == .captured, let sharp = s.sharpness {
        overall = clamp(wDef * s.definitionLighting + wFrm * s.framing + wPose * s.poseAccuracy + wNeut * s.poseNeutrality + wSharp * sharp)
    } else {
        let total = wDef + wFrm + wPose + wNeut
        overall = clamp((wDef/total)*s.definitionLighting + (wFrm/total)*s.framing + (wPose/total)*s.poseAccuracy + (wNeut/total)*s.poseNeutrality)
    }

    let hasCatLive = tags.contains { $0.isCatastrophicLive }
    let live: LiveState = hasCatLive ? .blocked : (overall >= 0.78 ? .ready : .guiding)

    let hasCatCap = tags.contains { $0.isCatastrophicCaptured }
    let review: ReviewVerdict
    if hasCatCap || overall < 0.50 { review = .retakeRecommended }
    else if overall < 0.75 { review = .warn }
    else { review = .keep }

    return Assessment(mode: mode, overallScore: overall, liveState: live, reviewVerdict: review, reasonTags: tags)
}

// MARK: - Test infrastructure

var passed = 0
var failed = 0

func assert(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    if condition {
        passed += 1
    } else {
        failed += 1
        print("  FAIL (\(line)): \(message)")
    }
}

func assertEq<T: Equatable>(_ a: T, _ b: T, _ message: String, file: String = #file, line: Int = #line) {
    if a == b {
        passed += 1
    } else {
        failed += 1
        print("  FAIL (\(line)): \(message) — expected \(b), got \(a)")
    }
}

// MARK: - Tests

print("Running CheckInVisualAssessment unit tests...\n")

// 1. Perfect live assessment → ready
do {
    let r = compute(
        subScores: SubScores(definitionLighting: 1.0, framing: 1.0, poseAccuracy: 1.0, poseNeutrality: 1.0),
        tags: [], mode: .live)
    assertEq(r.liveState.rawValue, "ready", "Perfect live → ready")
    assert(r.overallScore >= 0.78, "Perfect live score >= 0.78 (got \(r.overallScore))")
}

// 2. Perfect captured assessment → keep
do {
    let r = compute(
        subScores: SubScores(definitionLighting: 1.0, framing: 1.0, poseAccuracy: 1.0, poseNeutrality: 1.0, sharpness: 1.0),
        tags: [], mode: .captured)
    assertEq(r.reviewVerdict.rawValue, "keep", "Perfect captured → keep")
    assert(r.overallScore >= 0.75, "Perfect captured score >= 0.75")
}

// 3. Catastrophic tag forces blocked (live) and retakeRecommended (captured)
for tag in [ReasonTag.bodyNotDetected, .wrongPose, .severeCrop, .severeBacklight] {
    let live = compute(
        subScores: SubScores(definitionLighting: 1.0, framing: 1.0, poseAccuracy: 1.0, poseNeutrality: 1.0),
        tags: [tag], mode: .live)
    assertEq(live.liveState.rawValue, "blocked", "\(tag.rawValue) → blocked (live)")

    let cap = compute(
        subScores: SubScores(definitionLighting: 1.0, framing: 1.0, poseAccuracy: 1.0, poseNeutrality: 1.0, sharpness: 1.0),
        tags: [tag], mode: .captured)
    assertEq(cap.reviewVerdict.rawValue, "retakeRecommended", "\(tag.rawValue) → retakeRecommended (captured)")
}

// 4. severeBlur is catastrophic only in captured mode
do {
    let live = compute(
        subScores: SubScores(definitionLighting: 1.0, framing: 1.0, poseAccuracy: 1.0, poseNeutrality: 1.0),
        tags: [.severeBlur], mode: .live)
    assertEq(live.liveState.rawValue, "ready", "severeBlur NOT catastrophic in live mode")

    let cap = compute(
        subScores: SubScores(definitionLighting: 1.0, framing: 1.0, poseAccuracy: 1.0, poseNeutrality: 1.0, sharpness: 1.0),
        tags: [.severeBlur], mode: .captured)
    assertEq(cap.reviewVerdict.rawValue, "retakeRecommended", "severeBlur IS catastrophic in captured mode")
}

// 5. Warn range: score 0.50-0.75 without catastrophic tags
do {
    // definitionLighting = 0.6 gives overall ~0.63 in captured mode
    let r = compute(
        subScores: SubScores(definitionLighting: 0.6, framing: 0.6, poseAccuracy: 0.6, poseNeutrality: 0.6, sharpness: 0.6),
        tags: [.weakDefinition], mode: .captured)
    assertEq(r.reviewVerdict.rawValue, "warn", "Mid-range score → warn (score: \(r.overallScore))")
    assert(r.overallScore >= 0.50, "Score >= 0.50 for warn")
    assert(r.overallScore < 0.75, "Score < 0.75 for warn")
}

// 6. Low overall → retakeRecommended even without catastrophic tags
do {
    let r = compute(
        subScores: SubScores(definitionLighting: 0.0, framing: 0.4, poseAccuracy: 0.35, poseNeutrality: 0.4, sharpness: 0.3),
        tags: [.flatLighting, .poseUnclear], mode: .captured)
    assertEq(r.reviewVerdict.rawValue, "retakeRecommended", "Very low score → retakeRecommended")
    assert(r.overallScore < 0.50, "Score < 0.50 for retakeRecommended")
}

// 7. Live mode weights exclude sharpness
do {
    // With sharpness = nil, weights are redistributed proportionally
    let r = compute(
        subScores: SubScores(definitionLighting: 0.8, framing: 0.8, poseAccuracy: 0.8, poseNeutrality: 0.8),
        tags: [], mode: .live)
    // In live mode, all sub-scores at 0.8 → overall = 0.8 (proportional redistribution)
    assert(abs(r.overallScore - 0.8) < 0.01, "Live mode at 0.8 all subs → score ~0.8 (got \(r.overallScore))")
    assertEq(r.liveState.rawValue, "ready", "0.8 live → ready (>= 0.78)")
}

// 8. Live guiding: just below threshold
do {
    let r = compute(
        subScores: SubScores(definitionLighting: 0.7, framing: 0.7, poseAccuracy: 0.7, poseNeutrality: 0.7),
        tags: [], mode: .live)
    assertEq(r.liveState.rawValue, "guiding", "0.7 live → guiding (< 0.78)")
}

// 9. Definition lighting weight dominance (45%)
do {
    // Zero definition but everything else perfect
    let r = compute(
        subScores: SubScores(definitionLighting: 0.0, framing: 1.0, poseAccuracy: 1.0, poseNeutrality: 1.0, sharpness: 1.0),
        tags: [], mode: .captured)
    let expected = 0.0 * 0.45 + 1.0 * 0.20 + 1.0 * 0.15 + 1.0 * 0.10 + 1.0 * 0.10
    assert(abs(r.overallScore - expected) < 0.01, "Zero lighting + perfect rest → \(expected) (got \(r.overallScore))")
    assertEq(r.reviewVerdict.rawValue, "warn", "Zero lighting → warn at \(r.overallScore)")
}

// 10. Non-catastrophic tags don't override verdict
do {
    let r = compute(
        subScores: SubScores(definitionLighting: 0.9, framing: 0.9, poseAccuracy: 0.9, poseNeutrality: 0.9, sharpness: 0.9),
        tags: [.flatLighting, .mildBlur, .stagedPose], mode: .captured)
    assertEq(r.reviewVerdict.rawValue, "keep", "Non-catastrophic tags don't force retake (score: \(r.overallScore))")
}

// MARK: - Results

print("")
print("  \(passed) passed, \(failed) failed")
if failed > 0 {
    print("  TESTS FAILED")
    exit(1)
} else {
    print("  ALL TESTS PASSED")
}

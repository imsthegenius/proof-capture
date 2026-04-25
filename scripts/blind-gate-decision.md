# TWO-947 — Blind-Holdout Offline Gate Decision

**Verdict: FAIL** (per-pose-front keep-recall 66.7% < 75% threshold)

Per the production recovery plan: gate failure does NOT invalidate the blind set; it remains reserved for the next constant-set termination. If the pilot gate (TWO-949) passes, the pilot wins per the plan's decision policy.

## Run provenance

- Report: `scripts/reports/blind-gate/2026-04-25T134809Z_9149a38/`
- Manifest: `scripts/blind-holdout.csv` (sha256 prefix `215ab6ed…`, 20 rows, gitignored)
- Scorer source: `ProofCapture/Services/CheckInScorer.swift` (sha256 prefix `49068b21…`)
- Git SHA: `9149a38` (post-squash-merge of PR #31 / TWO-970 into `worktree-unified-scoring`)
- UTC: `2026-04-25T13:48:09Z`
- Constants under test (from TWO-970 terminal state):
  - `isBacklit` brightness delta = `0.45`
  - `definitionNormalized` band = `contrast / 0.08`
  - All other constants unchanged from pre-TWO-970 baseline.

**Provenance note.** The calibration log's TWO-970 terminal entry references SHA `5d8e375` (the pre-merge PR head). The squash merge produced SHA `9149a38`. The scorer source bytes are identical between the two — the merge only touched `scripts/calibration-log.md`. Scorer sha256 prefix `49068b21…` is the same regardless of which commit you check out, so the constants-under-test do match the terminal-state constants the calibration log committed to.

## Gate evaluation

| Threshold | Required | Actual | Result |
|---|---|---|---|
| Aggregate keep-recall | ≥ 85% | 87.5% (7/8) | **PASS** |
| Catastrophic keep→retake | = 0 | 0 | **PASS** |
| Per-pose keep-recall — front | ≥ 75% | 66.7% (2/3) | **FAIL** |
| Per-pose keep-recall — side | ≥ 75% | 100.0% (3/3) | **PASS** |
| Per-pose keep-recall — back | ≥ 75% | 100.0% (2/2) | **PASS** |

FAR not measurable on blind set (0 gold-drop / gold-retakeRecommended rows).

## The single failing row

```
source_path:     Mehul /IMG_8945.JPG
expected_pose:   front
gold verdict:    keep
scorer verdict:  warn
primary reason:  "Adjust your position"
reason tags:     poseUnclear | stagedPose
```

Both tags applied are mid-severity (per `severityOrder` in `CheckInScorer.swift:760`) which cap the verdict at `warn`. After TWO-967 (stagedPose captured-decouple) and TWO-968 (confidence-aware poseUnclear), these tags are still firing on this front shot, and either tag alone is enough to drop verdict from keep → warn.

## Threshold sensitivity note (small-N caveat)

The blind-holdout has only **3 front gold-keep rows**. At the 75% threshold this requires 3/3 (since 2/3 = 66.7% < 75%); a single mis-classified front frame causes a hard fail. This is a structural property of the manifest, not a property of the scorer. If the team wants front-pose keep-recall to be meaningfully testable, the blind set needs more front gold-keep rows.

## Aggregate metrics (for context)

```
Total scored:        20  (skipped 0)
Agreement:           50.0%  (10/20)
Per-pose agreement:  front 22.2% (2/9), side 85.7% (6/7), back 50.0% (2/4)
FRR:                 12.5%  (1/8)
FAR:                 0.0%   (0/0)
Catastrophic:        0
```

Top mismatch reason tags on disagreed rows: `feetMissing` (9), `stagedPose` (7), `tooFar` (3), `poseUnclear` (1), `weakDefinition` (1).

## What this fails / does not fail

- **Does NOT fail** the merge-safety contract. Build passes, scope is clean, no catastrophic regressions.
- **Does NOT burn** the blind set. The blind set remains reserved per the rule "If the gate fails, the calibration loop re-opens; the blind run is invalidated and the blind set remains reserved for the next termination."
- **Does fail** the offline gate as written. Per the plan, the pilot gate (TWO-949) becomes the deciding signal. If the pilot passes, ship; if it also fails, calibration loop re-opens.

## Remediation options (not auto-applied)

1. **Single-row investigation.** Diagnose `Mehul /IMG_8945.JPG` directly: pose-detection landmark output, stagedPose detector signal strength, poseUnclear confidence margin. Determine whether the tagging is correct (the photo really is unclear/staged) or a detector bug. If the latter, file a tagged remediation ticket.
2. **Threshold renegotiation.** With N=3 front gold-keep, the 75% threshold is structurally a 100% threshold. Surface to the plan owner whether front per-pose threshold should be relaxed to ≥ 66% or expressed as "≤ 1 mis-rejection allowed in front."
3. **Blind-set augmentation.** Add more front gold-keep rows so per-pose thresholds are statistically meaningful. Requires re-locking the blind set and a fresh constants run.
4. **Defer to pilot.** Per the plan's decision policy, if pilot gate (TWO-949) passes, ship and treat the offline failure as a known small-N caveat. No code change required.

The orchestrator (Imraan) picks. This document does not pre-select.

## Files

- This decision doc: `scripts/blind-gate-decision.md`
- Run output: `scripts/reports/blind-gate/2026-04-25T134809Z_9149a38/{summary.txt,rows.csv}`
- Original report (default evaluator path, kept for traceability): `scripts/reports/2026-04-25T134809Z_9149a38/`

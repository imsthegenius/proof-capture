# Proof Capture — Lighting & Pose Analysis Test Harness

Standalone macOS script that runs the exact same lighting + pose analysis pipeline from the Proof Capture app against static image files. Used for regression testing lighting calibration changes.

## Usage

```bash
swift scripts/analyze-photo.swift scripts/test-images/*.jpg
```

Or analyze a single image:

```bash
swift scripts/analyze-photo.swift scripts/test-images/front_directional_good.jpg
```

## Test Images

11 Unsplash images of **standing persons** covering three poses and the full lighting spectrum. Most images represent the actual Proof use case — a person standing upright in conditions a coaching client would encounter at home or in a gym. Two edge-case images (`front_window_poor`, `back_studio_good`) use tighter framing to test failure modes.

### Naming Convention

```
{pose}_{lighting-condition}_{human-expected-quality}.jpg
```

- **pose**: `front`, `side`, `back`
- **lighting-condition**: descriptive tag (e.g., `directional`, `overhead`, `backlit`, `mirror`, `gym`)
- **human-expected-quality**: `good`, `fair`, `poor` — reflects what a photographer would say about the lighting for progress photos, NOT the algorithm output

### Image Matrix

| Image | Pose | Human Assessment | Analyzer Lighting | Analyzer Pose | Notes |
|-------|------|-----------------|-------------------|---------------|-------|
| `front_directional_good.jpg` | front | GOOD — directional teal light | GOOD — directional | front, 8 joints | Standing, full body, arms at sides |
| `front_mirror_fair.jpg` | front | FAIR — gym mirror, overhead light | GOOD — overhead | front, 6 joints | Mirror selfie scenario |
| `front_dim_poor.jpg` | front | POOR — very dark gym, overhead spots | GOOD — great shadows | front, 8 joints | Strong downlight gradient scores well |
| `front_backlit_poor.jpg` | front | POOR — silhouette against bright sky | POOR — too dark | back, 7 joints | Person is near-black silhouette |
| `front_window_poor.jpg` | front | POOR — silhouette against window | POOR — too dark | unknown, 0 joints | True backlit-window edge case; pure silhouette, body detection fails |
| `side_stage_good.jpg` | side | GOOD — stage directional | GOOD — overhead | side, 7 joints | Bodybuilding side pose, full body |
| `side_gym_fair.jpg` | side | FAIR — dark gym with overhead tracks | GOOD — great shadows | back, 7 joints | Person holding weight plate |
| `side_mirror_fair.jpg` | side | FAIR — gym mirror, flat light | FAIR — flat | side, 5 joints | Mirror selfie, side orientation |
| `back_studio_good.jpg` | back | GOOD — studio light, white background | POOR — backlit | back, 3 joints | Upper-body back muscles; white bg triggers backlit detection |
| `back_gym_poor.jpg` | back | POOR — dark gym, minimal light | FAIR — flat | back, 7 joints | Back double bicep, full body |
| `back_backlit_poor.jpg` | back | POOR — strong backlight from sky | POOR — backlit | front, 4 joints | True backlit detection confirmed |

### Coverage Summary

| Category | Count | Images |
|----------|-------|--------|
| Front pose | 5 | `front_*` |
| Side pose | 3 | `side_*` |
| Back pose | 3 | `back_*` |
| Backlit scenario | 3 | `front_backlit_poor`, `front_window_poor`, `back_backlit_poor` |
| Backlit-window | 1 | `front_window_poor` |
| Mirror selfie | 2 | `front_mirror_fair`, `side_mirror_fair` |
| GOOD lighting (human) | 3 | `front_directional_good`, `side_stage_good`, `back_studio_good` |
| FAIR lighting (human) | 3 | `front_mirror_fair`, `side_gym_fair`, `side_mirror_fair` |
| POOR lighting (human) | 5 | `front_dim_poor`, `front_backlit_poor`, `front_window_poor`, `back_gym_poor`, `back_backlit_poor` |

### Known Discrepancies

The "Human Assessment" and "Analyzer Lighting" columns intentionally differ in several cases. These discrepancies reveal where the algorithm's perception diverges from human judgment:

1. **White/bright backgrounds score as backlit** — `back_studio_good` has a bright white background that triggers backlighting detection even though the person is well-lit. This is a known limitation of the background-vs-person brightness comparison.
2. **Dark images with good shadow contrast score as GOOD** — `front_dim_poor` looks very dark to a human, but has strong directional shadow patterns that the algorithm values. The algorithm prioritizes shadow definition over absolute brightness.
3. **True backlighting is correctly detected** — `back_backlit_poor`, `front_backlit_poor`, and `front_window_poor` correctly flag strong backlight or extreme darkness from backlighting.
4. **Window backlighting produces zero-joint detection** — `front_window_poor` is a true backlit-window edge case where the person is a pure silhouette. Vision framework cannot detect any body landmarks (0/8 joints), confirming that window backlighting is the worst-case scenario for the pipeline. This image intentionally tests the failure mode, not the happy path.

These mismatches are intentional test data — they define the baseline for tuning heuristic thresholds in later work.

## What It Measures

### Lighting (4 layers)
1. **Exposure** — person brightness (0.0-1.0), too dark (<0.15), too bright (>0.82)
2. **Downlighting** — upper vs lower body brightness gradient (>0.03 = overhead light detected)
3. **Shadow Contrast** — quadrant variance normalized to 0-1 (>0.25 = good definition)
4. **Backlighting** — background significantly brighter than person (>0.25 delta)

### Pose
- Body detection + joint count (out of 8 tracked)
- Position quality (centered, correct distance)
- Orientation (front/side/back)
- Arms relaxed check

---

## `scripts/evaluate-scorer` — decision-grade evaluator (TWO-944)

Compiles the runtime `CheckInScorer.swift` + `CheckInVisualAssessment.swift` + supporting models alongside `scripts/evaluate-scorer-main.swift` and runs the scorer against a manifest. Does not re-implement scorer logic and does not modify scorer constants (calibration lives in TWO-946).

### Usage

```bash
scripts/evaluate-scorer [manifest.csv] [--images-root <path>] [--compare <prior_run_dir>]
```

- `manifest.csv` — defaults to `scripts/gold-set-manifest.csv`. Also accepts a blind-labeled holdout manifest (TWO-942 schema).
- `--images-root` — override the image root. Defaults to `scripts/test-images` for the gold schema and `/Users/imraan/Downloads/Client Pictures` for the holdout schema.
- `--compare <prior_run_dir>` — after the current run, print a delta vs the given prior run directory (expects `<dir>/summary.txt` and `<dir>/rows.csv`).

### Manifest schema auto-detection

| Header signal | Schema | Image root default |
|---|---|---|
| contains `filename` | gold (11-image regression set) | `scripts/test-images/` |
| contains `source_path` | reviewed-holdout (TWO-942, 83 rows) | `/Users/imraan/Downloads/Client Pictures/` |

Anything else: the evaluator dies with a header-mismatch error.

### Provenance banner (fail-hard)

Every run prints a banner and exits with code `2` if any component is unreadable:

- `git rev-parse --short HEAD` — short SHA; missing → run aborts
- `git status --porcelain` — empty → `(clean)`; non-empty → banner includes `(dirty tree — not reproducible)` flag
- SHA-256 prefix (first 16 bytes) of `ProofCapture/Services/CheckInScorer.swift`
- SHA-256 prefix of the manifest file
- Manifest path, images root, CWD, ISO-8601 UTC timestamp

The dirty-tree flag is an advisory, not a fail — calibration iterations often need dirty runs. It is surfaced in the banner and in the report directory name (`<UTC>_<sha>-dirty`).

### Metrics

- **Aggregate agreement** — scorer verdict equals gold verdict (using tier bucketing — `drop` and `retakeRecommended` count as equal).
- **Per-pose agreement** — front / side / back. Rows with `label_pose=unclear` are excluded from per-pose but included in aggregate.
- **FRR** (false-reject rate) — gold is `keep` → scorer is not `keep`. Denominator = gold keep rows.
- **FAR** (false-accept rate) — gold is `drop` or `retakeRecommended` → scorer is `keep` or `warn`. Denominator = gold negative rows.
- **Catastrophic rejects** — gold `keep` → scorer `retakeRecommended`. These are the worst possible miss.
- **3×3 confusion matrix** — rows = gold tier, cols = scorer tier (positive/middle/negative).
- **Top-N mismatch reason tags** — count of each scorer-emitted reason tag on rows where the verdict disagreed. Feeds TWO-946 calibration priorities.

### Artifacts

Every run writes to `scripts/reports/<UTC>_<shortSHA>[-dirty]/` (gitignored):

- `summary.txt` — provenance banner + metrics, human-readable.
- `rows.csv` — per-image detail: `source_path, expected_pose, gold_verdict_raw, scorer_verdict, overall_score, def_lighting, framing, pose_accuracy, pose_neutrality, sharpness, raw_sharpness_variance, orientation_confidence, orientation_margin, reason_tags, primary_reason, match, false_accept, false_reject, catastrophic_reject`.

`raw_sharpness_variance` is the unbounded center-crop Laplacian variance used to derive the normalized `sharpness` score.
`orientation_confidence` and `orientation_margin` are captured-pose diagnostics used to distinguish decisive `.wrongPose` mismatches from ambiguous `.poseUnclear` mismatches.

### Compare mode

```bash
scripts/evaluate-scorer scripts/reviewed-holdout.csv \
  --compare scripts/reports/2026-04-23T123456Z_abc1234/
```

Prints deltas against the prior run's `summary.txt` / `rows.csv`:

- aggregate agreement delta (pp)
- FRR / FAR delta (pp)
- per-pose delta (pp)
- reason-tag churn (new entries in current top-10, entries that vanished from prior top-10)

The comparison rendering is appended to the current run's `summary.txt` so the paired-diff artefact is portable.

### Scope boundary

TWO-944 changes the evaluator only. No scorer constants, thresholds, or reason-tag vocab were touched. Calibration iteration against these metrics is TWO-946's job, gated on TWO-943 frozen reviewed-holdout and TWO-945 stratified split.

---

## `scripts/stratified-split.swift` — deterministic 63/20 split (TWO-945)

Splits the frozen reviewed-holdout (83 rows, TWO-942/943 output) into `scripts/tuning-holdout.csv` (63 rows) + `scripts/blind-holdout.csv` (20 rows). TWO-946 reads the tuning set; TWO-947 offline gate runs once against the blind set.

Both output CSVs are gitignored (carry client-folder `source_path` values). The `scripts/split-manifest.md` summary is also gitignored — it regenerates on every run with a fresh timestamp and does not contain source paths.

### Usage

```bash
swift scripts/stratified-split.swift [--seed N] [--input <path>] \
                                     [--frozen-marker <path>] [--out-dir <dir>] \
                                     [--stdout blind|tuning]
```

Default input is the TWO-942 worktree frozen file:
`/Users/imraan/Desktop/proof-capture/.claude/worktrees/two-942-blind-relabel-harness/scripts/reviewed-holdout.csv`

The script dies with exit 2 if the frozen marker is missing.

### Strata

- `(label_pose × label_keep_verdict)` — rows with `label_pose=unclear` sit out of the stratified allocation and go directly to the tuning set.
- Blind quota per stratum = largest-remainder rounding of `20 × n_stratum / n_scorable`, with ASCII tiebreak on the stratum key for determinism.
- Back-pose floors: blind ≥ 4, tuning ≥ 12. When the initial allocation misses either, rows are moved between strata deterministically: non-back → back (to satisfy blind floor) or back → non-back (to satisfy tuning floor).

### Determinism

- Within each stratum, rows are ordered by `SHA-256("<seed>:<source_path>")`. Same seed + same input bytes → byte-identical outputs.
- Input SHA-256 is written into `split-manifest.md`. TWO-946 compares against this hash to abort if calibration is pointed at a drifted holdout.

### Byte-for-byte reproducibility check

```bash
swift scripts/stratified-split.swift                                  # write files
diff <(swift scripts/stratified-split.swift --stdout blind) scripts/blind-holdout.csv
diff <(swift scripts/stratified-split.swift --stdout tuning) scripts/tuning-holdout.csv
```

Both diffs must be empty.

### Scope boundary

TWO-945 changes nothing but the split generator. No scorer, no evaluator, no reviewed-holdout mutations. TWO-946 owns constant tuning.

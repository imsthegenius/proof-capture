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

## Blind re-label protocol (`scripts/blind-relabel.swift`)

Drives the TWO-942 holdout blind re-label pass under parent TWO-941. Produces the human-labeled truth that TWO-944 / TWO-945 / TWO-946 consume.

Contract is locked in the TWO-942 Linear comments (schema v1 + addendum). This section is operator-facing summary, not source of truth — if the two disagree, the ticket comments win.

### Why blind

`/Users/imraan/Downloads/Client Pictures.checkd-manifest.local.csv` has labels auto-seeded by `analyze-photo.swift` (same engine as `CheckInScorer`). Tuning against those labels is a consistency check, not validation. This harness presents the reviewer ONLY with `source_path` and the absolute image path; all seeded labels stay hidden until the reviewer has committed their own verdict.

### Input and output

| Path | Role | Committed? |
|---|---|---|
| `/Users/imraan/Downloads/Client Pictures.checkd-manifest.local.csv` | Source of truth for the 83 holdout rows (filters to `split IN {threshold_check, final_validation}`) | No, local only |
| `/Users/imraan/Downloads/Client Pictures/<path>` | Image corpus | No, local only |
| `scripts/reviewed-holdout.csv` | Blind-pass labels, then TWO-943 adjudicated freeze | No (in `.gitignore`) |
| `scripts/reviewed-holdout-disputes.csv` | Diff vs auto-seeded, adjudication worksheet | No (in `.gitignore`) |
| `scripts/relabel-metadata.json` | Manifest SHA, row count, harness SHA, started_at — drift guard | No (in `.gitignore`) |
| `scripts/reviewed-holdout.csv.frozen` | Marker that TWO-943 wrote; calibration refuses to run without it | No (in `.gitignore`) |

### Commands

```bash
swift scripts/blind-relabel.swift --status
swift scripts/blind-relabel.swift --next
swift scripts/blind-relabel.swift --commit <source_path> <verdict> <tags> <pose> <framing>
swift scripts/blind-relabel.swift --disputes
swift scripts/blind-relabel.swift --dry-run
swift scripts/blind-relabel.swift --test-classifier   # smoke test for dispute classification + tag normalization
```

`--next` is the entry point of the labeling loop. It emits exactly:
- `index` of current / total
- `source_path` (relative to image root)
- `absolute` path for opening the image
- `split` and `manifest_row_index`

It does NOT emit any seeded label.

`--commit` appends one row to `reviewed-holdout.csv`. Field order: `source_path`, `verdict`, `tags`, `pose`, `framing`. Rejects unknown values and rejects duplicate `source_path`.

`--disputes` can only run after all 83 rows are labeled. It reads seeded labels for the first time and emits `reviewed-holdout-disputes.csv` row-per-diverging-field. Raw seeded verdicts are preserved in `auto_value` / `legacy_seed_verdict` — no silent mapping.

### Field values

| Field | Values |
|---|---|
| `verdict` | `keep`, `warn`, `retakeRecommended` |
| `pose` | `front`, `side`, `back`, `unclear` |
| `framing` | `ideal`, `ok`, `tooClose`, `tooFar`, `partial` |
| `tags` | pipe or comma separated list drawn from: `arms`, `not-lockable`, `framing`, `tooClose`, `tooFar`, `backlight`, `dark`, `blurry`, `wrong-pose`, `partial-body`, `face-only`, `mirror-selfie`, `collage`, `stage-lighting`, `flash`, `low-contrast`. Use `none` or `-` for no tags. Harness normalizes to pipe-joined ASCII-sorted. |

### Resume + drift guard

- Resume key: `source_path` exact match.
- First pass order: holdout rows sorted ASCII ascending by `source_path`.
- If the source manifest's SHA-256 changes mid-pass, the harness aborts with a diff until `scripts/relabel-metadata.json` is deleted — prevents drift invalidating prior labels.

### Freeze semantics (TWO-943)

TWO-943 writes an empty `scripts/reviewed-holdout.csv.frozen` marker once adjudication is complete. With the marker present, the harness refuses `--commit`. The calibration loop (TWO-946) refuses to run without it.

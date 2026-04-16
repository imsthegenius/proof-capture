# Checkd — Lighting & Pose Analysis Harness

Standalone macOS script that runs the same live lock scoring pipeline as the app
against static image files. Used for regression testing and calibration reports.

## Usage

```bash
swift scripts/analyze-photo.swift scripts/edge-cases/*.jpg
```

Or analyze a single image:

```bash
swift scripts/analyze-photo.swift scripts/edge-cases/front_directional_good.jpg
```

Generate structured output for reports:

```bash
swift scripts/analyze-photo.swift --format json scripts/edge-cases/*.jpg
swift scripts/analyze-photo.swift --format csv scripts/edge-cases/*.jpg
```

Audit the local album and generate a local-only manifest beside it:

```bash
swift scripts/audit-calibration-album.swift ~/Downloads/Client\\ Pictures
```

## Edge Cases

`scripts/edge-cases/` contains the committed validation-only suite. These files
exist to preserve known failure modes and guard against regressions. They never
drive threshold calibration.

Representative client photos live outside git. The canonical local-only source is:

- `/Users/imraan/Downloads/Client Pictures`

Use [calibration-manifest.template.csv](/Users/imraan/Desktop/proof-capture/scripts/calibration-manifest.template.csv) as the repo-tracked schema for local manifests generated beside the album.

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

These mismatches are intentional validation data. They document the failure modes
the lock scorer must continue to handle while tuning against the local album.

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

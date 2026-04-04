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

13 Unsplash images of **standing persons** covering three poses and the full lighting spectrum. All images represent the actual Proof use case — a person standing upright, approximately full-body visible, in conditions a coaching client would encounter at home or in a gym.

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
| `front_even_good.jpg` | front | GOOD — even studio light | POOR — backlit | front, 8 joints | White background triggers backlit detection |
| `front_natural_good.jpg` | front | GOOD — natural outdoor light | POOR — backlit | front, 8 joints | Bright tree canopy triggers backlit |
| `front_flat_fair.jpg` | front | FAIR — flat gym fluorescent | POOR — backlit | front, 8 joints | Bright gym equipment behind person |
| `front_overhead_poor.jpg` | front | POOR — single overhead in dark room | GOOD — directional | unknown, 6 joints | Dark but high shadow contrast scores well |
| `front_dim_poor.jpg` | front | POOR — very dark gym, overhead spots | GOOD — great shadows | front, 8 joints | Strong downlight gradient scores well |
| `front_backlit_poor.jpg` | front | POOR — silhouette against bright sky | POOR — too dark | back, 7 joints | Person is near-black silhouette |
| `front_mirror_fair.jpg` | front | FAIR — gym mirror, overhead light | GOOD — overhead | front, 6 joints | Shows mirror selfie scenario |
| `side_stage_good.jpg` | side | GOOD — stage directional | GOOD — overhead | side, 7 joints | Bodybuilding side pose, full body |
| `side_gym_fair.jpg` | side | FAIR — dark gym with overhead tracks | GOOD — great shadows | back, 7 joints | Person holding weight plate |
| `side_mirror_fair.jpg` | side | FAIR — gym mirror, flat light | FAIR — flat | side, 5 joints | Mirror selfie, side orientation |
| `back_gym_poor.jpg` | back | POOR — dark gym, minimal light | FAIR — flat | back, 7 joints | Back double bicep, full body |
| `back_backlit_poor.jpg` | back | POOR — strong backlight from sky | POOR — backlit | front, 4 joints | True backlit detection confirmed |

### Coverage Summary

| Category | Count | Images |
|----------|-------|--------|
| Front pose | 8 | `front_*` |
| Side pose | 3 | `side_*` |
| Back pose | 2 | `back_*` |
| Backlit scenario | 3 | `front_backlit_poor`, `front_even_good`, `back_backlit_poor` |
| Mirror selfie | 2 | `front_mirror_fair`, `side_mirror_fair` |
| GOOD lighting (human) | 4 | `front_directional_good`, `front_even_good`, `front_natural_good`, `side_stage_good` |
| FAIR lighting (human) | 4 | `front_flat_fair`, `front_mirror_fair`, `side_gym_fair`, `side_mirror_fair` |
| POOR lighting (human) | 5 | `front_overhead_poor`, `front_dim_poor`, `front_backlit_poor`, `back_gym_poor`, `back_backlit_poor` |

### Known Discrepancies

The "Human Assessment" and "Analyzer Lighting" columns intentionally differ in several cases. These discrepancies reveal where the algorithm's perception diverges from human judgment:

1. **White/bright backgrounds score as backlit** — `front_even_good`, `front_natural_good`, `front_flat_fair` all have bright backgrounds that trigger backlighting detection even though the person is well-lit. This is a known limitation.
2. **Dark images with good shadow contrast score as GOOD** — `front_overhead_poor` and `front_dim_poor` look very dark to a human, but have strong directional shadow patterns that the algorithm values. The algorithm prioritizes shadow definition over absolute brightness.
3. **True backlighting is correctly detected** — `back_backlit_poor` and `front_backlit_poor` correctly flag strong backlight.

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

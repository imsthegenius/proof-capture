# Proof Capture — Lighting & Pose Analysis Test Harness

Standalone macOS script that runs the exact same lighting + pose analysis pipeline from the Proof Capture app against static image files. Used for regression testing lighting calibration changes.

## Usage

```bash
swift scripts/analyze-photo.swift scripts/test-images/*.jpg
```

Or analyze a single image:

```bash
swift scripts/analyze-photo.swift scripts/test-images/01_good_overhead.jpg
```

## Test Images

13 Unsplash images covering the full lighting spectrum:

| Image | Expected Lighting | Expected Pose |
|-------|------------------|---------------|
| `01_good_overhead.jpg` | GOOD — overhead light with shadows | Body detected, front |
| `02_good_directional.jpg` | GOOD — directional light | Body detected |
| `03_flat_mirror.jpg` | FAIR — flat/even lighting | Body detected |
| `04_backlit_silhouette.jpg` | POOR — strong backlight | Body detected |
| `05_very_dim.jpg` | POOR — too dark | Body detected |
| `06_side_light.jpg` | GOOD — directional side light | Body detected |
| `07_dark_gym.jpg` | FAIR — dark but defined shadows | Body detected |
| `08_rim_light.jpg` | FAIR/GOOD — rim lighting | Body detected |
| `backlit-window.jpg` | POOR — window backlight | Body detected |
| `dim-room.jpg` | POOR/FAIR — low ambient light | Body detected |
| `dramatic-side.jpg` | GOOD — strong directional | Body detected |
| `flat-bathroom.jpg` | FAIR — flat bathroom lighting | Body detected |
| `gym-overhead.jpg` | GOOD — gym overhead | Body detected |

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

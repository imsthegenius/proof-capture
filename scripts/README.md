# Checkd Scoring Scripts

These scripts support two different jobs:

- `scripts/analyze-photo.swift`
  - Static inspection of the current **live lock** lighting + pose pipeline
    against committed edge cases.
- `scripts/audit-calibration-album.swift`
  - Local-only inventory and `suggested_*` seeding for the canonical client
    album manifest.
- `scripts/prepare-captured-photo-manifest.swift`
  - Local-only prep for the real client album manifest used to calibrate the
    **captured-photo** scorer.

## Dataset Policy

The repo copy under `scripts/edge-cases/` is **validation-only**. It is useful
for edge cases and regression checks, but it is **not** the source of truth for
production thresholds.

Production scoring should be calibrated from the real client album manifest:

`/Users/imraan/Downloads/Client Pictures.checkd-manifest.local.csv`

Raw client images stay local-only and are ignored by git.

## Static Analysis Harness

Run the current live analyzer against validation images:

```bash
swift scripts/analyze-photo.swift scripts/edge-cases/*.jpg
```

Generate structured output for reports:

```bash
swift scripts/analyze-photo.swift --format json scripts/edge-cases/*.jpg
swift scripts/analyze-photo.swift --format csv scripts/edge-cases/*.jpg
```

`scripts/analyze-photo.swift` is a parity harness for the current **live
lock** analyzer. It mirrors the live lighting + pose gate, including the
arm-relaxation check, so you can inspect how the current lock logic sees
validation images.

Use `scripts/edge-cases/front_directional_good.jpg` as the deterministic
bent-left-elbow fixture for pose-gate parity checks.

This script mirrors the live lock pipeline:

- person-masked brightness
- downlight gradient
- shadow contrast
- backlight detection
- pose/orientation/framing checks
- arm-relaxation gating

Use it to understand how the current live gate is seeing a frame. It is **not**
a captured-photo scorer, and it is **not** enough by itself to justify
production threshold changes without album-based evaluation.

## Local Album Audit

Generate or refresh the local-only manifest beside the canonical album:

```bash
swift scripts/audit-calibration-album.swift "/Users/imraan/Downloads/Client Pictures"
```

What it does:

- inventories the local album recursively
- excludes obvious non-calibration assets such as `Before-After` composites and
  `Background.png`
- preserves existing `label_*` columns if the local manifest already exists
- seeds `suggested_pose`, `suggested_lockable`, and
  `suggested_lighting_quality` from the current live-lock parity harness
- writes the manifest to `/Users/imraan/Downloads/Client Pictures.checkd-manifest.local.csv`

## Local Manifest Prep

Prepare or upgrade the local client-album manifest for captured-photo labeling:

```bash
swift scripts/prepare-captured-photo-manifest.swift "/Users/imraan/Downloads/Client Pictures.checkd-manifest.local.csv"
```

What it does:

- adds the captured-photo label columns if they are missing
- assigns deterministic split buckets using a stable grouping key derived from
  each row's containing folder:
  - `train_tune`
  - `threshold_check`
  - `final_validation`
- keeps duplicates and excluded rows out of calibration splits

Template schema lives in:

`scripts/calibration-manifest.template.csv`

## Captured-Photo Label Rubric

Each included image should be judged with this question:

**"If this were sent to a coach as a weekly check-in, would it be good enough
to assess physique change?"**

Required labels:

- `label_pose`
- `label_keep_verdict`
- `label_coach_usable`
- `label_definition_visibility`
- `label_directionality`
- `label_body_exposure`
- `label_backlight`
- `label_sharpness`
- `label_framing`
- `label_reason_tags`

Scoring philosophy is body-first:

- lighting matters more than brightness
- definition matters more than prettiness
- face quality is not used to pick the final burst frame
- slightly dark but well-defined can still be acceptable
- bright but flat should not be treated as "good"

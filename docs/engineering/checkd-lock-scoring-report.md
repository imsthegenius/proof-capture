# Checkd Lock Scoring Report

## Scope

- Live lock scorer only: `LightingAnalyzer`, `PoseDetector`, `PhotoQualityGate`, and `scripts/analyze-photo.swift`
- Validation-only suite: `scripts/edge-cases/`
- Canonical local-only source: `/Users/imraan/Downloads/Client Pictures`

## Baseline

- Command:
  - `swift scripts/analyze-photo.swift --format human scripts/edge-cases/*.jpg`
- Current snapshot from the committed edge-case suite:
  - 11 total images
  - 4 currently score as lockable
  - 3 score `.poor` lighting
  - 2 score `.fair` lighting
  - 6 score `.good` lighting
  - 3 still report the wrong orientation for the expected pose
  - 4 fail the arm-readiness gate
  - 3 fail framing quality
- Current committed edge-case expectations:
  - mirror selfie contamination
  - stage/studio contamination
  - true backlit silhouettes
  - bright-background false backlight
  - dim-but-directional lighting
  - side/back orientation ambiguity
  - held-object framing noise

## Current Lock Contract

- A frame is lockable only when:
  - body detected
  - framing quality is good
  - orientation matches expected pose
  - arms are relaxed enough for a neutral starting stance
  - lighting is not `.poor`

## Local Album Workflow

- Generate the local-only manifest beside the album:
  - `swift scripts/audit-calibration-album.swift ~/Downloads/Client\\ Pictures`
- Fill the `label_*` columns manually using the repo-tracked template schema.
- Treat any generated `suggested_*` values as seeds only, never as ground truth.

## Recalibrated Results

- Reserved for the post-labeling report generated after the local album is fully audited.
- This section should capture before/after counts for:
  - false locks
  - missed locks
  - true window silhouettes
  - bright-background false backlight
  - side-vs-back orientation mistakes
  - partial-body and feet-occluded framing failures

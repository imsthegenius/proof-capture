# Checkd Lock Scoring Report

## Scope

- Live lock scorer only: `LightingAnalyzer`, `PoseDetector`, `PhotoQualityGate`, and `scripts/analyze-photo.swift`
- Committed validation-only suite: `scripts/edge-cases/`
- Canonical local-only source: `/Users/imraan/Downloads/Client Pictures`

## Baseline Edge-Case Snapshot

Command:

```bash
swift scripts/analyze-photo.swift --format json scripts/edge-cases/*.jpg
```

Current measured baseline from the committed edge-case suite:

- 11 total images
- 2 currently score as lockable
- 4 currently score `.poor` lighting
- 2 currently score `.fair` lighting
- 5 currently score `.good` lighting
- 4 currently report the wrong orientation for the expected pose
- 6 currently fail the arm-relaxation gate
- 3 currently fail framing / position quality

Current expectation buckets covered by the suite:

- arm-relaxation parity regression (`front_directional_good.jpg`)
- mirror selfie contamination
- stage/studio contamination
- true backlit silhouettes
- bright-background false backlight
- dim-but-directional lighting
- side/back orientation ambiguity
- held-object framing noise

Notable current mismatches versus the validation expectations:

- `front_dim_poor.jpg` currently scores `lockable: true`, so it acts as a false-lock guard for dim-but-directional lighting.
- `side_mirror_fair.jpg` currently scores `lockable: true`, so mirror contamination is still a live false-lock risk.
- `front_directional_good.jpg` is the deterministic bent-left-elbow parity fixture and currently fails `armsRelaxed`, which matches the live left-elbow gate.

## Current Lock Contract

A frame is lockable only when all of the following are true:

- body detected
- framing / position quality is `.good`
- orientation matches the expected pose when one is known
- arms are relaxed enough for the neutral starting stance
- lighting is not `.poor`

## Local Album Workflow

1. Generate or refresh the local-only manifest beside the album:

```bash
swift scripts/audit-calibration-album.swift ~/Downloads/Client\\ Pictures
```

2. Normalize the schema / deterministic splits if needed:

```bash
swift scripts/prepare-captured-photo-manifest.swift ~/Downloads/Client\\ Pictures.checkd-manifest.local.csv
```

3. Fill or review the `label_*` columns in the local manifest.

4. Use the structured analyzer output for calibration/reporting runs:

```bash
swift scripts/analyze-photo.swift --format json /absolute/path/to/images/*.jpg
swift scripts/analyze-photo.swift --format csv /absolute/path/to/images/*.jpg
```

Guidelines:

- `suggested_*` fields are seeds only, never the final ground truth.
- Raw client photos and generated local manifests stay outside git.
- The committed edge-case suite guards known regressions; it does not drive threshold calibration by itself.

## Recalibration Results

Current conservative retune applied under `TWO-939`:

- `PoseDetector.checkArmsRelaxed` wrist-to-hip X tolerance: `0.06 -> 0.10`
- Wrist-to-hip Y tolerance remains `0.08`
- Left-elbow angle cutoff remains `< 150`

Evidence from the local calibration manifest (`251` included frames, `151` labeled coach-usable):

- Before the retune, the current live lock allowed `36` included frames and missed `115` coach-usable frames.
- `89` of those coach-usable misses were failing the arm gate.
- The `0.10` X tolerance recovers `15` coach-usable frames while adding `0` newly lockable frames inside the `100` coach-unusable labeled set.
- All committed `scripts/edge-cases/` expectations remain unchanged at this threshold.

Why the retune stopped at `0.10` instead of going wider:

- Moving past `0.10` starts unlocking `front_directional_good.jpg` and `side_stage_good.jpg`.
- Those are deliberate non-lockable regression / contamination fixtures, so the wider `0.12+` options were rejected even though they recovered more local frames.

Residual follow-up:

- The local manifest labels are still a deterministic calibration aid, not final human-reviewed ground truth.
- Larger threshold moves should wait for manual album review so future retunes are backed by audited labels rather than harness-seeded suggestions.

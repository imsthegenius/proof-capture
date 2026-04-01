---
type: "note"
---
# Checkd — Product Requirements Document

> **For agents:** This document is your authoritative reference for what this app is, what it does, and every significant design and technical decision made. Read this before touching any code.

***

## What Is This App

**Checkd** (formerly Proof Capture) is an iOS app that guides fitness coaching clients through taking consistent, well-lit progress photos at home. Phone propped up 2 metres away, timer-based, audio-guided. Three shots per session (front, side, back) with burst capture and automatic best-frame selection.

It is **not** a general photo app, not a camera, not a social tool. One job: stand in the right spot and get a good photo every week, with zero friction.

**Distribution:** Coaches recommend it to clients. Zero CAC. Coaches are the growth channel — clients get a tool their coach told them to use.

***

## Two-App Ecosystem

| App                    | Audience                                                | Status       |
| ---------------------- | ------------------------------------------------------- | ------------ |
| **Checkd** (this repo) | Coaching clients — takes the photos                     | Building now |
| **Proof** (future)     | Coaches — generates comparison cards from client photos | Not started  |

Checkd is the data layer. Proof is the output layer.

***

## Locked V1 Decisions (2026-03-30)

These decisions are locked for the current v1 release and supersede any earlier planning artifact that conflicts with them.

- Deployment floor: iOS 17
- Release QA floor: iPhone 12 or newer
- Reminder scheduling is out of scope for v1
- In-app coach delivery or export is out of scope for v1
- Audio guidance is on by default, mirrored in text, with text-only as the fallback mode
- Canonical capture path: live positioning → readiness lock → automatic countdown → burst capture → 2-second auto-preview → next pose
- Per-pose retakes happen from the final review screen, not as an accept/reject step after each pose
- Partial drafts persist locally and resume at the current pose after cancellation or backgrounding
- Completed sessions are not overwritten in v1
- The side pose is left-facing for v1

See also:

- `docs/design/checkd-v1-brief.md`
- `docs/design/checkd-v1-decision-record.md`

***

## Target User

Fitness coaching clients, typically:

* Non-technical, not fitness enthusiasts

* Doing this because their coach told them to

* Phone propped against something, standing 2 metres away

* Back shots mean they literally cannot see the screen

* Want zero learning curve — they should not have to think about the app

***

## Session Flow

```text
Start Session
  → positioning (camera opens, border glow feedback)
  → countdown (3-2-1 with pose name above number)
  → capturing (burst: 7 frames, best selected automatically)
  → preview (2s auto, green check + self-drawing checkmark)
  → [auto-advance to next pose, or complete if last]
Complete Screen
  → shows all 3 captured photos
  → tap any photo to retake just that pose
```

**No mid-session decisions.** The user's only job is to stand correctly. Everything else is automatic:

* No "Capture now" button (there is an emergency fallback, but it's hidden)

* No "Retake"/"Next" buttons mid-session

* 2-second auto-preview then auto-advance

* Retake from complete screen only (reopens camera for that pose, returns to complete when done)

* Partial drafts persist locally and resume at the current pose after cancellation or backgrounding

* Completed sessions are saved as immutable weekly records and are not overwritten in v1

**Poses:** front → left side → back (always this order)

***

## Camera System — The Core UX

### Pattern: Banking KYC Border Glow

The camera view shows a **full-screen edge border glow** that changes colour based on readiness. This is the same pattern banks use for face ID verification — the user can see themselves in the frame and the border tells them whether they're in a good position.

**NOT:**

* A small status ring in the centre

* Text labels saying "READY" or "ADJUST"

* A dashed silhouette target zone

**YES:**

* Full-screen camera feed as a mirror

* Full-screen edge border that is the feedback system

* "Step into frame" large text (40pt ultraLight) when no body is detected

### Border States

| State   | Colour          | Width        | Meaning                                 |
| ------- | --------------- | ------------ | --------------------------------------- |
| Neutral | white 30%       | 2pt          | Body detected, calibrating              |
| Almost  | amber `#DCBE8C` | 3pt, pulsing | 1–2 checks failing                      |
| Ready   | green `#6ABE6E` | 4pt, solid   | All checks pass → auto-capture triggers |

The amber pulse uses a cubic-bezier `(0.37, 0.0, 0.63, 1.0)` easing at 1.2s duration — organic, not mechanical.

The body outline (from `PoseGuideOverlay`) is coloured to match the border state — the entire visual language is unified around one colour channel.

### What "Ready" Means

Three conditions must all pass:

1. **Body detected** — `VNDetectHumanBodyPoseRequest` sees a person in frame

2. **Pose correct** — position quality, correct orientation (front/side/back), arms relaxed

3. **Lighting good** — body-focused lighting analysis passes (see below)

A 300ms lock-on delay prevents flickering — the user must hold the ready state before countdown begins.

***

## Lighting Analysis — Body-Focused

### The Problem We're Solving

Progress photos need to show muscle definition. That requires:

* Overhead/directional light creating a **top-to-bottom brightness gradient** on the body

* **Shadow contrast** between body quadrants — not flat even lighting

**Face quality is irrelevant here.** We removed `VNDetectFaceCaptureQualityRequest` entirely from `LightingAnalyzer`. This was a key correction — the body is what we're photographing.

### The 4-Layer Pipeline

`LightingAnalyzer` uses `VNGeneratePersonSegmentationRequest` to isolate the person from the background, then runs 4 checks on the body region only:

**Layer 1 — Exposure**

* Uses `CIAreaAverage` on person mask

* `.poor` if brightness < 0.15 (too dark) or > 0.82 (blown out)

* `.fair` if in marginal range (0.15–0.25 or 0.72–0.82)

* `.good` if in acceptable range

**Layer 2 — Downlighting Gradient**

* Splits person-masked image into top half and bottom half

* Top should be brighter than bottom (overhead light from above)

* Threshold: top brightness must exceed bottom by > 0.03

* Fails if light is from below (bottom-lit) or flat

**Layer 3 — Shadow Contrast**

* Divides person mask into 4 quadrants

* Measures brightness variance across quadrants

* Maps variance → contrast score (0–1), threshold 0.003

* Muscle definition requires contrast score > 0.25 for `.good`

* "Flat" even lighting across all quadrants = no definition visible

**Layer 4 — Backlighting Detection**

* Compares background brightness to body brightness

* If background is 0.25+ brighter than body: silhouetted, body is underexposed

* Returns `.poor` immediately

### Composite Logic

```text
green (all-clear):
  exposure .good AND (downlight passes AND contrast > 0.25) → qualityLevel = .good
  OR (contrast > 0.3 regardless of downlight) → strong directional light

amber (almost):
  exposure OK but lighting not ideal (contrast 0.15–0.25, or gradient missing)

red/poor:
  exposure outside safe range OR backlighting OR contrast < 0.15
```

### Why This Matters

A face can look fine under flat overhead office lighting. A body will not show muscle definition under flat lighting. The downlighting gradient + shadow contrast checks ensure the photo will actually show what the client and coach need to see: shape, definition, change over time.

***

## Burst Capture & Best-Frame Selection

`AVCapturePhotoOutput` fires 7 frames. `BurstSelector` picks the best.

### Scoring Weights (Body-Focused)

| Pose  | Sharpness | Face Quality |
| ----- | --------- | ------------ |
| Front | 75%       | 25%          |
| Side  | 90%       | 10%          |
| Back  | 100%      | 0%           |

**Comment in code: "Body-focused: sharpness is king."**

Sharpness uses `CIConvolution3X3` Laplacian edge detection (variance of edge response). Face quality via `VNDetectFaceCaptureQualityRequest` is a minor tiebreaker for front shots only, and irrelevant for side/back.

***

## Pose Detection

`PoseDetector` uses `VNDetectHumanBodyPoseRequest` on every camera frame.

### What It Checks

* **Body in frame** — key landmarks (shoulders, hips) are visible with sufficient confidence

* **Position quality** — body not too close, not cut off at edges

* **Orientation** — front/side/back via nose/ear/shoulder geometry analysis

  * Front: nose visible, both ears visible, shoulders roughly symmetric

  * Side: one ear visible, shoulders asymmetric

  * Back: nose not visible, both shoulders visible

* **Arms relaxed** — wrists are not raised above hips (not hands-on-hips pose)

### Composite `isReady`

All checks must pass. `overallStatus: QualityLevel` (`.poor`/`.fair`/`.good`) feeds directly into:

* Border glow colour

* Whether countdown begins (requires `.good` held for 300ms)

* Body outline colour in `PoseGuideOverlay`

### Concurrency Architecture

`PoseDetector` is `@MainActor` isolated (all published state on main thread). The `captureOutput` delegate and all image analysis methods are `nonisolated` to avoid blocking the camera pipeline. `lastAnalysisTime` and `_targetPoseCache` are `nonisolated(unsafe)`. Results are published back to main via `Task { @MainActor in }`.

***

## Design System

### Philosophy

**Swiss design.** Zero decoration. Typography drives hierarchy. No gradients, no shadows, no illustrations, no mascots, no confetti, no celebrations.

**Audio-on-by-default, screen-second.** Every instruction is mirrored in text. Audio is the default guidance mode, and text-only is the fallback. The app must still work for the back shot where the user literally cannot see the screen.

**One thing at a time.** Each screen state shows exactly one piece of information at large scale.

### Color Tokens

| Token           | Hex       | Use                                             |
| --------------- | --------- | ----------------------------------------------- |
| `background`    | `#0C0B09` | Main canvas                                     |
| `surface`       | `#1C1B19` | Cards, sheets, rows                             |
| `elevated`      | `#2E2C2A` | Modals, popovers                                |
| `separator`     | `#1C1B19` | Dividers                                        |
| `textPrimary`   | `#F5F2ED` | Main text (17.6:1 contrast)                     |
| `textSecondary` | `#A8A39B` | Labels, supporting text (7.8:1)                 |
| `textTertiary`  | `#827D76` | Hints, inactive, dates (4.8:1)                  |
| `accent`        | `#EBEBE6` | Warm white — CTAs, interactive, earned states   |
| `statusGood`    | `#6ABE6E` | Ready, success                                  |
| `statusFair`    | `#DCBE8C` | Almost, warning (status only — NEVER as accent) |
| `statusPoor`    | `#D25A55` | Error, destructive                              |
| `overlayText`   | white     | Text on camera feed                             |
| `overlayPill`   | black 65% | Buttons on camera feed                          |

**NEVER use gold, yellow, or amber as accent colour.** `statusFair` is for status indicators only.

All colours via `ProofTheme` tokens. No raw `Color.red`, `.white`, `.black` in views (except camera overlays using `ProofTheme.overlayText`).

### Typography

SF Pro system fonts only. **NEVER use&#x20;**`.medium`**,&#x20;**`.semibold`**,&#x20;**`.bold`**, or&#x20;**`.heavy`**.**

| Role                      | Size    | Weight                             |
| ------------------------- | ------- | ---------------------------------- |
| Hero title (PROOF/CHECKD) | 60pt    | `.ultraLight`, tracking 12         |
| Countdown timer           | 120pt   | `.ultraLight`                      |
| "Step into frame"         | 40pt    | `.ultraLight`                      |
| Screen titles             | 24pt    | `.light`                           |
| Body / labels             | 15–17pt | `.light`                           |
| Captions / metadata       | 12–13pt | `.light`                           |
| Camera pose label         | 12pt    | `.regular`, tracking 4, small caps |

### Spacing (4pt grid)

`XS:4 SM:8 MD:16 LG:24 XL:32 XXL:48`

### Corner Radius

`SM:8 MD:12 LG:20`

### Buttons

* **Primary:** 52pt height, full width, glass on iOS 26 / accent on iOS 17, capsule

* **Secondary:** 52pt height, full width, glass on iOS 26 / surface on iOS 17, capsule

* **Destructive:** Text-only, `statusPoor` colour

* **Button press:** 0.97x scale (tactile feedback)

### Animation Rules

* Purpose-driven only — every animation communicates a state change

* Use `.animation(.easeInOut, value:)` — NEVER `.animation()` without value

* Amber pulse: cubic-bezier `(0.37, 0.0, 0.63, 1.0)` 1.2s (organic, breathing quality)

* No confetti, particles, bouncing, or celebration animations

* No shadows, no gradients

***

## Screen Inventory

### Home Screen

* No branding text (PROOF/CHECKD) — user knows what app they're in

* Settings gear top-right only

* Session count: 48pt ultraLight Swiss numeral (large, minimal)

* Last session's front photo as small thumbnail (visual progress motivation)

* Relative time since last session ("3 days ago")

* "Start Session" button in `textPrimary`

### Session / Camera View

See Camera System section above. Key details:

* Full-screen camera feed, mirrored

* Full-screen border glow (not rounded rect inset — actual edge of screen)

* "Step into frame" when no body detected

* Pose label at bottom: small caps, tracking 4, with asymmetric transition on pose change

* Countdown: 120pt ultraLight number, pose name above it in smaller type

* Emergency capture button: subtle, hidden unless session is stuck

### History View

* Sessions list with front photo thumbnails

* Relative timestamps

* Swipe-to-delete with confirmation

* Compare mode: tap "Compare sessions" → select any 2 sessions → comparison view

  * Not limited to adjacent sessions — compare week 1 vs week 12

  * Delete disabled while in compare mode (`.deleteDisabled(isCompareMode)`)

* Empty state: large "0" + "sessions" + "Start your first session" (Swiss pattern)

### Comparison View

* Side-by-side photos from two selected sessions

* Pose switcher (front/side/back)

* No editing, no filters, no annotations

### Complete Screen

* Shows all 3 captured photos in a row

* Tap any photo to retake that pose only

  * Camera reopens for that specific pose

  * `isRetaking` flag prevents retake from auto-advancing to next pose

  * Returns to complete screen when done

### Onboarding (3 steps only)

1. **Welcome** — value prop, hero title

2. **Setup** — prop phone instructions, overhead light guidance

3. **Permission + Guidance** — camera permission, audio-on-by-default, and text fallback for silent use

***

## Technical Architecture

### Stack

* **Swift / SwiftUI** (iOS 17+)

* **Vision** — `VNDetectHumanBodyPoseRequest`, `VNGeneratePersonSegmentationRequest`, `VNDetectFaceCaptureQualityRequest` (burst selector only)

* **AVFoundation** — `AVCaptureSession` (background queue), `AVCapturePhotoOutput`, burst capture

* **Core Image** — `CIAreaAverage` (exposure), `CIConvolution3X3` Laplacian (sharpness)

* **AVSpeechSynthesizer** — voice guidance

* **AudioToolbox** — ascending beep countdown pattern

* **Photos** — `PHPhotoLibrary` for camera roll saves

* **StoreKit 2** — subscription management (~£9.99/month)

* **SwiftData** — local persistence, single `ModelContainer`, source of truth

* **Supabase** — auth (Sign in with Apple), Storage (photos, private RLS per user), Postgres (metadata)

### Data Flow

```text
Camera feed → PoseDetector (Vision, background)
           → LightingAnalyzer (Core Image + Vision, background)
           → [overallStatus drives border glow on main thread]

Capture trigger → AVCapturePhotoOutput burst (7 frames)
               → BurstSelector scores frames
               → Best frame selected
               → SwiftData saves session/photo locally
               → Supabase sync in background (never blocks UI)
```

### SwiftData Architecture

Single `ModelContainer` created in `ProofCaptureApp`. The `SyncBootstrapView` pattern is used to avoid the double-container bug: `SyncManager` receives the SwiftUI-provided `modelContext` via `.onAppear`, not by creating its own container.

**SwiftData is source of truth.** Never bypass it for direct Supabase reads.

### Supabase

* Project: `pbntloqfayegjamsvmpy` (eu-west-2)

* URL: `https://pbntloqfayegjamsvmpy.supabase.co`

* Config: `Supabase.xcconfig` → injected into `Info.plist` as `SUPABASE_URL` / `SUPABASE_ANON_KEY`

* Tables: `photo_sessions` (RLS per user)

* Storage: `progress-photos` bucket (private, RLS per user folder)

* Auth: Sign in with Apple only — no email/password

### Bundle ID

`com.proof.capture`

***

## Key Decisions & Rationale

| Decision                            | Rationale                                                                                                                                                                            |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| No face quality in LightingAnalyzer | We're photographing bodies, not faces. Face quality is irrelevant and caused false-good readings under flat lighting.                                                                |
| Body segmentation for lighting      | CIAreaAverage on whole frame includes background (window, lamp). Must isolate person mask first for meaningful readings.                                                             |
| Downlighting gradient check         | Overhead light is best for muscle definition. Bottom-lit or flat-lit photos show no shape.                                                                                           |
| 4-quadrant shadow contrast          | Even if exposure is good, flat light means no contrast between body quadrants = no visible muscle definition.                                                                        |
| Border glow (not status ring)       | Status ring at centre is invisible at 2-metre viewing distance. Full-screen border is visible at any distance. KYC apps proved this UX works for "am I in a good position" feedback. |
| Audio-first                         | Back shots: user cannot see screen. App must work eyes-closed. Voice is primary channel, screen is secondary.                                                                        |
| No mid-session decisions            | Reduces friction to zero. Clients do this weekly for months — any friction compounds.                                                                                                |
| 300ms lock-on delay                 | Prevents flickering countdown triggers from brief ready states. User must genuinely hold the position.                                                                               |
| Retake from complete screen only    | Mid-session retake adds decision fatigue. Complete screen retake is deliberate, not reactive.                                                                                        |
| isRetaking flag                     | Prevents retake from auto-advancing to next pose — it should return to complete when done.                                                                                           |
| SyncBootstrapView pattern           | Avoids SwiftData double-container bug where SyncManager creates a second ModelContainer independent of SwiftUI's container.                                                          |
| Delete disabled in compare mode     | Prevents conflicting actions — selecting for comparison and swiping to delete are incompatible.                                                                                      |
| GeometryReader not UIScreen.main    | `UIScreen.main.bounds` is deprecated, breaks on iPad split-screen.                                                                                                                   |

***

## What This App Does NOT Do

* No photo editing, filters, retouching, or body modification tools

* No social features, no sharing between users

* No reminder scheduling in v1

* No in-app coach delivery or export in v1

* No analytics on photo content (metadata only: session count, timestamps)

* No email/password auth

* No free tier (decide after launch)

* No face-based quality scoring during capture

* No silhouette target zone overlay

* No "READY"/"ADJUST" text labels on camera

* No confetti or celebration animations on completion

***

## Monetization

StoreKit 2 subscription, approximately £9.99/month. No free tier gating for MVP — full feature access, decide on gating after launch data.

***

## Accessibility

* Every interactive element: accessibility label required

* Audio guidance has visual text equivalent (deaf/HoH)

* Minimum touch target: 44pt

* Dynamic Type support required

* WCAG AA contrast minimum: all text meets or exceeds (see contrast ratios in Color Tokens)

⠀

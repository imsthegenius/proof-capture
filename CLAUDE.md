@~/Desktop/second-brain/rules/brain-sync-rule.md
@~/Desktop/second-brain/rules/linear-workflow-rule.md
# Proof Capture — Guided Progress Photo App for Coaching Clients

## Project Overview
Standalone iOS app that guides fitness coaching clients through taking consistent, well-lit progress photos at home. Phone propped up, timer-based, audio-guided Photo Booth mode. Three shots per session (front, side, back) with burst capture and automatic best-frame selection.

## Stack
- Swift / SwiftUI (iOS 17+)
- Vision framework (VNDetectHumanBodyPoseRequest for body detection + distance estimation)
- AVFoundation (AVCaptureSession for live camera, burst capture)
- Core Image (lighting analysis)
- AVSpeechSynthesizer (voice prompts) + AudioToolbox (ascending beep pattern)
- Photos framework (save to camera roll)
- StoreKit 2 (subscription management)
- SwiftData (session history, local persistence — source of truth)
- Supabase (auth via Sign in with Apple, cloud backup via Storage + Postgres)
- supabase-swift SDK (2.x)

## Brain Sync
@~/Desktop/second-brain/ventures/proof/index.md

## Design Philosophy
- **Photo booth, not camera app** — zero learning curve, one job: stand in the right spot
- **Audio-first, screen-second** — every instruction is spoken. Screen confirms what voice said
- **One thing at a time** — each screen state shows exactly one piece of information at large scale
- **Automatic everything** — user's only job is to stand correctly. Capture, selection, advancement all auto

## Design System

### Color Tokens (warm near-black base)
| Token | Hex | Use |
|-------|-----|-----|
| `background` | `#0C0B09` | Main canvas |
| `surface` | `#1C1B19` | Cards, sheets, row backgrounds |
| `elevated` | `#2E2C2A` | Modals, popovers |
| `separator` | `#1C1B19` | Dividers |
| `textPrimary` | `#F5F2ED` | Main text, active elements |
| `textSecondary` | `#A8A39B` | Labels, supporting text (7.8:1 contrast) |
| `textTertiary` | `#827D76` | Hints, inactive, dates (4.8:1 contrast) |
| `accent` | `#EBEBE6` | Warm white — interactive elements, CTAs, earned states |
| `statusGood` | `#6ABE6E` | Green — ready, success |
| `statusFair` | `#DCBE8C` | Amber — almost, warning (status only, never as accent) |
| `statusPoor` | `#D25A55` | Red — error, destructive |
| `overlayText` | white | Text on camera feed |
| `overlayPill` | black 65% | Buttons on camera feed |

### Border Glow (camera readiness — banking KYC pattern)
| State | Color | Width | Meaning |
|-------|-------|-------|---------|
| Neutral | white 30% | 2pt | Body detected, adjusting |
| Almost | amber (statusFair) | 3pt, pulsing | 1-2 checks failing |
| Ready | green (statusGood) | 4pt, solid | All checks pass → auto-capture |

### Typography (SF Pro only)
| Role | Size | Weight |
|------|------|--------|
| Hero title (PROOF) | 60pt | `.ultraLight`, tracking 12 |
| Countdown timer | 120pt | `.ultraLight` |
| Screen titles | 24pt | `.light` |
| Body / labels | 15-17pt | `.light` |
| Captions / metadata | 12-13pt | `.light` |
| Camera pose label | 12pt | `.regular`, tracking 4 |

**NEVER use `.medium`, `.semibold`, `.bold`, or `.heavy`**

### Spacing (4pt grid)
`XS:4 SM:8 MD:16 LG:24 XL:32 XXL:48`

### Corner Radius
`SM:8 MD:12 LG:20`

### Buttons
- **Primary:** 52pt height, full width, glass on iOS 26 / accent on 17, capsule
- **Secondary:** 52pt height, full width, glass on iOS 26 / surface on 17, capsule
- **Destructive:** Text-only, statusPoor color

### Animation
- Purpose-driven only — every animation communicates a state change
- Use `.animation(.easeInOut, value:)` — NEVER `.animation()` without value
- No confetti, particles, bouncing, pulsing, or celebration animations
- No shadows, no gradients

## Key Rules
- Dark mode only — `.preferredColorScheme(.dark)` on root view
- NEVER use gold, yellow, or amber as accent color
- Swiss design: zero decoration, typography-driven hierarchy
- SF Pro system fonts only — no custom fonts
- All colors via ProofTheme tokens — no raw `Color.red`, `.white`, etc. in views (except camera overlays using `ProofTheme.overlayText`)
- Sign in with Apple required (Supabase Auth) — no email/password
- Local-first: SwiftData is source of truth, Supabase syncs in background (single ModelContainer)
- Cloud backup: photos uploaded to Supabase Storage, metadata to Postgres
- NO editing, NO filters, NO retouching, NO body modification
- Audio guidance is primary UX — app must work when user can't see screen (back shots)

## Camera UX Pattern
The camera view uses a banking KYC-style border glow — NOT a status ring, NOT text labels.
- Full-screen camera feed as mirror (user sees themselves posing)
- Full-screen edge border glow changes color based on readiness (white → amber → green)
- Body outline tracks detected person, colored to match border state
- "Step into frame" large text when no body detected
- Pose label at bottom in small caps
- No dashed silhouette target zone, no centered status ring, no "READY/ADJUST" text

## Session Flow
```
Start Session → positioning → countdown → capturing → preview (2s auto) → next pose or complete
```
- No "preparing" spinner — camera opens immediately
- No "reviewing" phase — 2-second auto-preview with green check, then auto-advance
- No manual "Capture now" button (subtle emergency fallback only)
- No "Retake"/"Next" buttons mid-session — auto-advance reduces decision fatigue
- Retake from complete screen: tap any photo to retake just that pose (camera reopens for that pose only)
- Countdown overlay shows pose name above the number (visible at 2 meters)
- Three poses: front → side → back

## Home Screen
- Session count in large thin number (48pt ultraLight) — the Swiss numeral pattern
- Last session's front photo as small thumbnail (visual progress motivation)
- Relative time since last session
- No branding text — just settings gear top-right

## History & Comparison
- Compare mode: tap "Compare sessions" → select any 2 sessions → navigate to comparison
- Not limited to last two sessions — users can compare week 1 vs week 12
- Swipe-to-delete with confirmation
- Swiss empty state: large "0" + "sessions" + "Start your first session" button

## Onboarding
3 steps total (not more):
1. Welcome — value prop, "PROOF" title
2. Setup — prop phone, overhead light, audio guide
3. Permission + Voice — camera access + guide voice choice (Male/Female)

## Empty States
Swiss typography pattern — large accent numeral ("0") + one-line explanation + optional CTA. No illustrations, no mascots, no emoji.

## Monetization
- ~GBP 9.99/month subscription via StoreKit 2
- No free tier gating for MVP — decide after launch

## Supabase
- Project: `pbntloqfayegjamsvmpy` (eu-west-2)
- URL: `https://pbntloqfayegjamsvmpy.supabase.co`
- Config via `Supabase.xcconfig` → injected into Info.plist as `SUPABASE_URL` / `SUPABASE_ANON_KEY`
- Tables: `photo_sessions` (RLS per user)
- Storage: `progress-photos` bucket (private, RLS per user folder)

## Bundle ID
`com.proof.capture`

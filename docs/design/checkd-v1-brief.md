# Checkd V1 Canonical Brief

Status: locked on 2026-03-30 for [ORB-13](/ORB/issues/ORB-13)

This is the real shared repo artifact for the Checkd v1 brief. It replaces earlier comment references to `docs/design/checkd-brief.md`, which did not exist in the readable source tree.

## Product Job

Checkd helps a coaching client complete a trustworthy weekly physique check-in alone at home without having to think like a photographer.

- User: coach-led fitness clients, usually non-technical, often setting the phone down 2 metres away and following instructions from across the room
- Core promise: tell me exactly what to do, capture the right three photos with low friction, and save a weekly set my coach can trust
- First value moment: the user completes a clean front, side, and back set in a single guided session and sees that the set was saved successfully

## Canonical V1 Experience

The v1 capture path is fixed:

1. Guided entry and setup context
2. Camera permission only after setup context is understood
3. Live positioning with readiness feedback
4. Readiness lock
5. Automatic countdown
6. Burst capture
7. 2-second auto-preview
8. Automatic advance to the next pose
9. Final review with per-pose retakes
10. Save the weekly check-in

The sequence is always:

1. Front
2. Left side
3. Back

## V1 Scope

V1 must include:

- onboarding and setup guidance for distance, framing, and lighting
- camera-permission request and recovery
- fixed front, left-side, back capture order
- readiness feedback and automatic countdown after lock
- burst capture plus automatic best-frame selection
- 2-second auto-preview after each pose
- final review screen with per-pose retakes
- local draft persistence and resume at the current pose
- explicit save confirmation and lightweight session history
- audio guidance on by default, mirrored in text, with text-only fallback

## Draft And Review Policy

- The primary capture flow has no per-pose accept or reject step.
- If a pose is captured successfully, the user sees a short auto-preview and then the app advances.
- Retakes happen only from the final review screen.
- Partial drafts persist locally after cancellation or backgrounding and resume at the current required pose.
- Completed sessions become immutable weekly records in v1. A later session creates a new record rather than overwriting the completed one.

## Out Of Scope For V1

The following are explicitly out of scope for this release:

- reminder scheduling
- in-app coach delivery or export
- pro-camera controls or manual photo workflows as a primary path
- social sharing, editing, filters, or body-analysis features
- iPad, Android, or cross-platform expansion

## Success Standard

Checkd v1 is successful when:

- a first-time user can complete a weekly set without external help
- the app feels like a guided check-in, not a camera tool
- interruptions and cancellations do not force a full restart when draft progress exists
- engineering and QA can validate one explicit capture path instead of reconciling conflicting design assumptions

## Downstream Handoff

- UX must model readiness lock, automatic countdown, auto-preview, final-review retakes, and safe draft resume as the canonical state path.
- UI must keep the camera experience legible from 2 metres away and treat audio as the default guidance channel rather than an optional enhancement.
- Engineering must implement local partial-draft persistence, safe resume, and immutable completed sessions.
- QA must validate the locked capture path on iOS 17 with release-floor coverage on iPhone 12 or newer.

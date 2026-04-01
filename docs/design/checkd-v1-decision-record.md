# Checkd V1 Decision Record

Status: locked on 2026-03-30 for [ORB-13](/ORB/issues/ORB-13)

## Why This Exists

Source access is now restored, which exposed two problems:

- earlier comments referenced a brief file that was not actually present in the readable repo
- the earlier UX handoff still described a more user-driven flow than the CEO-locked v1 product path

This record closes those questions so `docs/prd.md`, UX, engineering, and QA can converge on one buildable version of Checkd v1.

## Locked Decisions

| Topic | Locked v1 decision | Why it matters |
| --- | --- | --- |
| Deployment floor | iOS 17 | Keeps the build target aligned with the current app code and release expectations |
| Release QA floor | iPhone 12 or newer | Gives QA and engineering a concrete low-end physical-device target |
| Capture trigger | Countdown starts automatically after readiness lock | The app is a guided check-in, not a user-operated camera |
| Primary pose flow | `live positioning -> readiness lock -> automatic countdown -> burst capture -> 2 second auto-preview -> next pose` | Removes ambiguity from the main capture state machine |
| Pose review model | No per-pose accept or reject step in the main flow | Keeps the session low-friction and consistent from pose to pose |
| Retake model | Retakes happen from the final review screen only | Prevents decision fatigue during the primary capture path |
| Draft handling | Partial drafts persist locally and resume at the current pose | Real home-use interruptions should not erase progress |
| Resume safety | Active countdowns, burst capture, or transient preview states resume at the last safe positioning step | Prevents broken or confusing mid-countdown resume behavior |
| Completed sessions | Completed sessions are not overwritten in v1 | Preserves trust in weekly records and simplifies save semantics |
| Side pose | Side pose is left-facing for v1 | Removes orientation ambiguity for UX, copy, and QA |
| Guidance mode | Audio guidance is on by default, mirrored in text, with text-only fallback | Supports hands-free use while still covering silent or inaccessible contexts |
| V1 scope boundary | Reminder scheduling is out of scope | Protects the release from non-essential complexity |
| V1 scope boundary | In-app coach delivery or export is out of scope | Keeps Checkd focused on capture and local session trust, not downstream coach workflows |

## Conflicts Closed

- Earlier UX planning assumed the user would explicitly start each countdown. That is superseded by automatic countdown after readiness lock.
- Earlier UX planning assumed a `Use photo` or `Retake` decision after each pose. That is superseded by the 2-second auto-preview and final-review retake model.
- Open questions from earlier planning around side orientation, audio default, draft persistence, and overwrite behavior are now closed by this record.

## Downstream Implications

- `docs/prd.md` should be treated as the repo-level source of truth after its v1 alignment updates.
- UX documentation must be revised to remove user-initiated countdown and per-pose accept/reject states from the canonical path.
- Engineering must treat local draft persistence and immutable completed sessions as required product behavior, not optional polish.
- QA should validate against the locked capture path and release floors above.

## Residual Risk

- The readable repo and the locked design policy are not yet fully aligned in implementation, especially around draft resume and completion semantics.
- Until the updated UX handoff lands, older ORB-9 artifacts remain useful for edge cases but not for the canonical trigger and review model.

# Proof Capture — iOS / SwiftUI Quality Rules

## Design System (non-negotiable)

- Dark mode ONLY — `.preferredColorScheme(.dark)` on root view
- Background: `#0C0B09` | Text: `#F5F2ED` | Accent: warm white `#EBEBE6`
- **NEVER** use gold, yellow, or amber as accent color
- SF Pro system fonts only — no custom fonts, no downloaded fonts
- Swiss design: zero decoration, typography-driven hierarchy
- No gradients, no drop shadows on buttons, no particle effects, no confetti

## SwiftUI Patterns

- Use `@Observable` (iOS 17+) over `ObservableObject` + `@Published`
- Prefer `NavigationStack` over deprecated `NavigationView`
- Use `async/await` over Combine where possible
- Extract reusable views only when used 3+ times — don't over-componentize
- Keep views under ~100 lines; extract logic to view models when views get complex
- Use `Color(hex:)` extension for design system colors, defined once

## Camera & AV

- AVCaptureSession must be configured on a background queue
- Camera permissions: always check `AVCaptureDevice.authorizationStatus` before use
- Handle `.notDetermined`, `.denied`, `.restricted` gracefully with user-facing guidance
- Burst capture: use `AVCapturePhotoOutput` with bracketed settings

## Data Architecture

- SwiftData is source of truth — never bypass for direct Supabase reads
- Supabase syncs in background — UI should never wait on network
- Sign in with Apple via Supabase Auth — no email/password flows
- RLS enforced server-side — never trust client-side auth checks alone

## Accessibility

- Every interactive element needs an accessibility label
- Audio guidance must have visual text equivalent (deaf/HoH users)
- Minimum touch target: 44pt
- Dynamic Type support required

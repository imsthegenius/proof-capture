@~/Desktop/second-brain/rules/brain-sync-rule.md
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
@~/Desktop/second-brain/ventures/proof/context.md

## Key Rules
- Dark mode only (background #0B0B0B, text #F2F0EB, accent gold #E8C547)
- Swiss design: zero decoration, typography-driven hierarchy
- SF Pro system fonts only — no custom fonts
- Force dark: `.preferredColorScheme(.dark)` on root view
- Sign in with Apple required (Supabase Auth) — no email/password
- Local-first: SwiftData is source of truth, Supabase syncs in background
- Cloud backup: photos uploaded to Supabase Storage, metadata to Postgres
- NO editing, NO filters, NO retouching, NO body modification
- Audio guidance is primary UX — app must work when user can't see screen (back shots)

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

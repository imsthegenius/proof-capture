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
- SwiftData (session history, local persistence)

## Brain Sync
@~/Desktop/second-brain/ventures/proof/context.md

## Key Rules
- Dark mode only (background #0B0B0B, text #F2F0EB, accent gold #E8C547)
- Swiss design: zero decoration, typography-driven hierarchy
- SF Pro system fonts only — no custom fonts
- Force dark: `.preferredColorScheme(.dark)` on root view
- NO accounts, NO login, NO cloud sync, NO coach-client linking
- NO editing, NO filters, NO retouching, NO body modification
- Audio guidance is primary UX — app must work when user can't see screen (back shots)

## Monetization
- ~GBP 9.99/month subscription via StoreKit 2
- No free tier gating for MVP — decide after launch

## Bundle ID
`com.proof.capture`

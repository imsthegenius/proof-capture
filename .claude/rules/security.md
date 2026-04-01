# Proof Capture — Security Rules

## Secrets

- **NEVER** hardcode API keys, tokens, or secrets in Swift files
- Supabase credentials go in `Supabase.xcconfig` only — injected via Info.plist
- Never commit `.xcconfig` files containing real keys (check `.gitignore`)
- Never log secrets, tokens, or user data to console in release builds

## Hardcoded Paths

- **NEVER** use absolute paths like `/Users/imraan/` in code or configuration
- Use `Bundle.main`, `FileManager.default.urls`, or relative paths

## User Data

- Progress photos are sensitive body images — treat with maximum privacy
- Photos stored in Supabase Storage with RLS per user folder
- Never transmit photos without user consent
- No analytics on photo content — only metadata (session count, timestamps)
- No social features, no sharing between users within the app

## Dependencies

- Prefer Apple frameworks (Vision, AVFoundation, Core Image) over third-party
- Only dependency: supabase-swift SDK — minimize attack surface
- Pin dependency versions in Package.swift

---
name: ios-design-audit
description: Code-based design quality audit for iOS/SwiftUI projects — systematically greps for hardcoded colors, forbidden font weights, missing accessibility labels, layout anti-patterns, and animation issues across all .swift files. Produces a structured report with file:line references, section scores, and an overall grade. Use when REVIEWING or AUDITING existing iOS code, checking design compliance before App Store submission, scanning for violations after major UI changes, or when the user says "audit", "design review", "check my views", "scan for violations", "design quality score", "check the UI code". NOT for deciding what colors/fonts to use (that's ios-design-system) or for web UI audits (that's web-ui-audit).
metadata:
  filePattern:
    - "**/*.swift"
  bashPattern:
    - "xcodebuild"
---

# iOS Design Audit

You are running a systematic, code-based design quality audit on an iOS/SwiftUI project. You cannot take screenshots, so you analyze the SOURCE CODE for design violations. This is the iOS equivalent of web-ui-audit.

## Audit Protocol

Run each section in order. For each finding, record: file path, line number, violation, severity (critical/warning/info), and suggested fix.

### Pre-Audit Setup

1. Read the project's `CLAUDE.md` to understand project-specific design rules
2. Identify the theme/token file (usually `Theme.swift`, `Colors.swift`, or similar)
3. Find all SwiftUI view files: `Glob("**/*.swift")` then filter for files containing `struct.*View.*:.*View`

### Section 1: Build Check (if xcodebuild available)

```bash
# Try to build — a view that doesn't compile is the worst design violation
xcodebuild -project *.xcodeproj -scheme <scheme> -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20
```

If build fails, report errors and stop — no point auditing code that doesn't compile.

### Section 2: Design Tokens

**Goal:** All colors and sizes should flow through a theme system, not be hardcoded.

Search for violations:
```
# Hardcoded colors (should use theme tokens)
Grep: Color\(\s*red:|Color\(\s*\.red|Color\(\s*\.blue|Color\(\s*\.green|Color\(\s*\.orange|Color\(\s*\.purple|Color\(\s*\.pink|Color\(\s*\.yellow|Color\(\s*\.cyan|Color\(\s*\.mint|Color\(\s*\.teal|Color\(\s*\.indigo
# → Severity: warning (unless in a theme definition file)

# Hardcoded hex that doesn't go through theme
Grep: Color\(hex:\s*"  (in files OUTSIDE the theme file)
# → Severity: warning

# Hardcoded UIColor
Grep: UIColor\(red:|UIColor\(white:|UIColor\.system
# → Severity: info (may be UIKit interop)

# .foregroundColor(.primary) or .foregroundColor(.secondary) — system colors, not theme tokens
Grep: \.foregroundColor\(\.primary\)|\.foregroundColor\(\.secondary\)|\.foregroundStyle\(\.primary\)|\.foregroundStyle\(\.secondary\)
# → Severity: info (acceptable but prefer explicit theme tokens)
```

**Pass criteria:** <5 hardcoded colors outside theme file.

### Section 3: Typography

**Goal:** Consistent font weights and sizes following the design system.

```
# Forbidden font weights (per ios-design-system skill)
Grep: \.fontWeight\(\.regular\)|\.fontWeight\(\.medium\)|\.fontWeight\(\.semibold\)|\.fontWeight\(\.bold\)|\.fontWeight\(\.heavy\)|\.fontWeight\(\.black\)
# → Severity: critical (unless project CLAUDE.md explicitly permits)

# Font weight in .font(.system()) — check for medium/semibold/bold
Grep: weight:\s*\.(medium|semibold|bold|heavy|black)
# → Severity: critical

# Bold modifier
Grep: \.bold\(\)
# → Severity: critical

# Missing font specification (bare Text without .font modifier)
# This is harder to grep — check views with many Text() elements

# Inconsistent font sizes (look for sizes outside the standard scale)
# Standard: 12, 13, 15, 17, 20, 24, 28, 34, 40, 48, 60, 72, 88
Grep: size:\s*(\d+) — then check values against scale
# → Severity: info for non-standard sizes
```

**Pass criteria:** 0 forbidden font weights.

### Section 4: Accessibility

**Goal:** Every interactive element is accessible.

```
# onTapGesture without accessibilityLabel
# Search for onTapGesture, then check surrounding 5 lines for accessibilityLabel
Grep: \.onTapGesture
# For each match, Read surrounding lines and check for .accessibilityLabel or .accessibilityAddTraits
# → Severity: critical if no label found

# Images without accessibility treatment
Grep: Image\(|Image\(systemName:
# Check for .accessibilityLabel or .accessibilityHidden
# → Severity: warning

# Hardcoded frames that block Dynamic Type
Grep: \.frame\(height:\s*\d+\)  (on text containers)
# → Severity: warning

# Missing @ScaledMetric for custom spacing
Grep: @ScaledMetric
# If 0 found and project has custom spacing constants → info

# Small touch targets
Grep: \.frame\(width:\s*(\d+),\s*height:\s*(\d+)\)
# Flag any where both dimensions < 44
# → Severity: warning
```

**Pass criteria:** 0 tap gestures without labels.

### Section 5: Layout Anti-Patterns

**Goal:** Clean, performant SwiftUI layout code.

```
# GeometryReader inside ScrollView (performance killer)
Grep: GeometryReader  (then check if parent is ScrollView)
# → Severity: critical

# AnyView usage (type erasure, bad for SwiftUI diffing)
Grep: AnyView\(
# → Severity: warning

# Hardcoded frames instead of flexible layout
Grep: \.frame\(width:\s*\d+,\s*height:\s*\d+\)
# → Severity: info (sometimes necessary, but overuse = problem)

# NavigationView (deprecated — use NavigationStack)
Grep: NavigationView
# → Severity: warning

# VStack/HStack with inconsistent spacing
# Grep for spacing: values and check consistency within a file
Grep: spacing:\s*\d+
# → Severity: info if many different values in one file
```

**Pass criteria:** 0 GeometryReader-in-ScrollView, 0 AnyView.

### Section 6: Animation

**Goal:** Purpose-driven animation, properly implemented.

```
# .animation without value parameter (deprecated, causes issues)
Grep: \.animation\([^,)]+\)\s*$|\.animation\(\.[^,]+\)$
# This catches .animation(.default) or .animation(.easeInOut(duration: 0.3)) without value:
# → Severity: critical

# Confetti / celebration patterns
Grep: confetti|particle|Confetti|ParticleEmitter|celebration|firework
# → Severity: critical (per ios-design-system philosophy)

# Spring animations on non-interactive elements
Grep: \.spring\(|interpolatingSpring
# → Severity: info (check if applied to user-driven interaction)

# Lottie usage (heavy, usually decorative)
Grep: LottieView|Lottie
# → Severity: info
```

**Pass criteria:** 0 animations without value parameter, 0 confetti/celebrations.

### Section 7: Project-Specific Rules

Read the project's `CLAUDE.md` and extract all "FORBIDDEN" or "NEVER" or "No" rules. For each rule, construct a grep pattern and search the codebase.

Common project rules to check:
- Forbidden gradient usage: `Grep: LinearGradient|RadialGradient|\.gradient`
- Forbidden material usage: `Grep: \.ultraThinMaterial|\.thinMaterial|\.regularMaterial`
- Forbidden push notifications: `Grep: UNUserNotificationCenter|requestAuthorization.*alert`
- Widget background violations: check widget files for hardcoded backgrounds

### Section 8: AI-Slop Detection

```
# Card-on-card patterns (RoundedRectangle inside RoundedRectangle)
Grep: RoundedRectangle
# If >10 instances and most are nested → flag

# Shadow overuse
Grep: \.shadow\(
# → Severity: warning if >5 instances

# Excessive corner radius
Grep: cornerRadius\(\s*(\d+)\)
# Flag if average > 16 or if many different values

# Material as decoration (not overlay)
Grep: \.ultraThinMaterial|\.regularMaterial|\.thickMaterial
# → Severity: warning unless on image overlays
```

## Scoring

| Section | Weight | Scoring |
|---------|--------|---------|
| Build | 20% | Pass/Fail (0 or 20) |
| Design Tokens | 10% | 10 - (violations x 1), min 0 |
| Typography | 20% | 20 - (critical x 5) - (warning x 2), min 0 |
| Accessibility | 20% | 20 - (critical x 5) - (warning x 2), min 0 |
| Layout | 10% | 10 - (critical x 3) - (warning x 1), min 0 |
| Animation | 10% | 10 - (critical x 5) - (warning x 1), min 0 |
| Project Rules | 10% | 10 - (violations x 2), min 0 |

**Grade:**
- 90-100: Ship it
- 75-89: Good, minor issues
- 60-74: Needs work — fix criticals before shipping
- Below 60: Significant design debt

## Output Format

```
# iOS Design Audit Report
**Project:** {name}
**Date:** {date}
**Score:** {score}/100 ({grade})
**Files scanned:** {count}

## Critical Issues ({count})
1. **[Typography]** `Views/HomeView.swift:45` — `.fontWeight(.bold)` forbidden
   Fix: Use `.font(.system(size: 20, weight: .light))`

2. **[Accessibility]** `Views/SettingsView.swift:112` — `onTapGesture` without label
   Fix: Add `.accessibilityLabel("Delete account")`

## Warnings ({count})
...

## Info ({count})
...

## Section Breakdown
| Section | Score | Issues |
|---------|-------|--------|
| Build | 20/20 | Clean build |
| Typography | 15/20 | 1 critical |
| ... | ... | ... |

## Recommendations
1. {Most impactful fix}
2. {Second most impactful}
3. {Third most impactful}
```

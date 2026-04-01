---
name: ios-design-system
description: Opinionated iOS/SwiftUI design standards — dark mode palettes, typography hierarchy (thin/light only, no bold), spacing grid, component patterns, animation philosophy, and AI-slop detection. Use when BUILDING or WRITING new SwiftUI views, choosing colors, picking font weights, deciding on spacing, or asking "what should this look like" for native iOS apps. Trigger on "what colors", "what font", "how should I style", "make it look good", "design system", "dark mode palette", "spacing", "AI slop", or when starting a new SwiftUI view. NOT for auditing existing code (use ios-design-audit) or web design (use frontend-design/design-agent).
metadata:
  filePattern:
    - "**/*.swift"
  bashPattern:
    - "xcodebuild"
    - "swift build"
    - "simctl"
---

# iOS Design System — Universal Standards

You are enforcing a design philosophy: restraint over decoration, typography as the primary design element, dark mode as first-class, animation as communication not celebration. Beautiful iOS apps look like they were designed by someone who said "no" more than "yes."

## 1. Design Philosophy

### Core Principles
- **Restraint > decoration** — every visual element must earn its place. If removing it doesn't hurt comprehension, remove it.
- **Typography is the design** — hierarchy comes from weight and size, not color or ornament.
- **Dark mode is the default** — design dark first, adapt to light. Most productivity, health, and developer tools look better dark.
- **Flat is premium** — no shadows, no gradients, no cards-on-cards. Use color and spacing to create hierarchy.
- **Silence is confidence** — no celebration animations, no "you're amazing!" copy, no confetti. The app respects the user's intelligence.

### The Restraint Test
Before adding ANY visual element, ask:
1. Does this communicate information the user needs?
2. Can I achieve this with typography alone?
3. Would removing this hurt the experience?

If the answer to all three is "no," don't add it.

## 2. Color System

### Dark Mode Palette Construction
Every iOS project needs exactly 4-5 background layers and 3-4 text layers:

| Layer | Purpose | Typical Range | Example |
|-------|---------|---------------|---------|
| Background | Main canvas | `#09-#12` luminance | `#0C0B09` (warm), `#0A0A0C` (cool) |
| Surface | Cards, sheets | Background +2-3 steps | `#1C1B19`, `#141418` |
| Elevated | Modals, popovers | Surface +2-3 steps | `#2E2C2A`, `#1E1E22` |
| Separator | Dividers | Between surface/elevated | `#1C1B19` |

| Text Layer | Purpose | Typical Range |
|------------|---------|---------------|
| Primary | Main text, active icons | `#E8-#F8` luminance |
| Secondary | Labels, attribution | `#80-#90` luminance |
| Tertiary | Hints, inactive, dates | `#45-#55` luminance |

### Accent Colors
- **One accent maximum** — pick one warm or cool accent for the app's identity
- Accent appears on: interactive elements, earned states, progress indicators
- Accent does NOT appear on: text, backgrounds, decorative elements
- Gold/amber accents suit achievement/progress apps
- Blue/teal accents suit productivity/health apps

### Anti-Patterns (FORBIDDEN)
- Pure black `#000000` as background (too harsh, use warm/cool near-black)
- Neon accents (`#00FF00`, `#FF00FF`) — these scream "programmer art"
- Purple gradients — the universal sign of AI-generated design
- More than 2 accent colors
- Colored backgrounds behind text (use opacity or text color instead)
- Rainbow or multi-color schemes without explicit brand justification

### Contrast Requirements
- Primary text on background: minimum 7:1 (WCAG AAA)
- Secondary text on background: minimum 4.5:1 (WCAG AA)
- Interactive elements: minimum 3:1 against adjacent colors

## 3. Typography Hierarchy

### Weight Selection
| Use Case | Weight | Why |
|----------|--------|-----|
| Hero numerals (counters, metrics, timers) | `.thin` or `.ultraLight` at 60-100pt | Large thin type = premium, confident |
| Section headers | `.light` at 20-28pt | Lighter than you think — weight comes from size |
| Body text | `.light` or `.regular` at 15-17pt | Readable without being heavy |
| Captions, metadata | `.light` at 12-13pt | Whisper, don't shout |
| Editorial/quote content | Custom serif at 17-19pt | Georgia, New York, or similar — editorial warmth |

### Rules
- **NEVER use `.medium`, `.semibold`, `.bold`, or `.heavy`** unless the project CLAUDE.md explicitly permits it
- Use SF Pro as the system font — it's designed for iOS and handles every edge case
- Custom fonts ONLY for editorial content (quotes, letters, messages) — never for UI chrome
- Hero numbers should be the largest element on screen and the thinnest weight
- Don't specify `.fontWeight(.regular)` explicitly — it's the default and adds noise

### Font Size Scale
Use a consistent scale based on the 4pt grid:
`12 → 13 → 15 → 17 → 20 → 24 → 28 → 34 → 40 → 48 → 60 → 72 → 88`

## 4. Spacing & Layout

### Grid
- Base unit: 4pt
- Common intervals: 4, 8, 12, 16, 20, 24, 32, 40, 48
- Container padding: 16pt horizontal, 20pt vertical
- List item internal padding: 12pt vertical
- Section gaps: 24-32pt
- Screen edge padding: 16pt (compact), 20pt (regular)

### Layout Principles
- **Generous whitespace** — when in doubt, add more space, not less
- **Align to invisible grid** — leading edges of text should align vertically across sections
- **No card soup** — use separators, not rounded rectangles, to divide content in lists
- **Full-width by default** — cards and containers go edge-to-edge with horizontal padding, not inset with margins

### Navigation
- Use `NavigationStack` (not deprecated `NavigationView`)
- Tab bars: text-only labels are more premium than icon-based tabs
- Sheet presentations for secondary flows
- Full-screen covers for immersive moments (onboarding, celebrations)

## 5. Component Patterns

### Hero Counter/Metric
```
ZStack {
    // Optional: ring or progress indicator behind number
    Circle()
        .trim(from: 0, to: progress)
        .stroke(accentColor, lineWidth: 2)

    // The number: thin, large, centered
    Text("\(count)")
        .font(.system(size: 88, weight: .thin, design: .default))
        .foregroundColor(primaryText)

    // Optional: small label below
    Text("days")
        .font(.system(size: 13, weight: .light))
        .foregroundColor(secondaryText)
}
```

### List Rows
- Flat, no card backgrounds
- Separator between items (1px line, separator color)
- Left-aligned text, right-aligned metadata
- No chevrons unless navigating to a detail view
- No icons unless they carry distinct meaning (not decoration)

### Empty States
- Text only — no illustrations, no SF Symbols as heroes
- One line explaining what will appear here
- Optional: one action button if the user can remedy the state

### Forms/Settings
- Grouped list style (`.insetGrouped`)
- No custom styling on toggles/pickers — use system defaults
- Section headers in secondary text, uppercase, small

### Loading States
- Prefer skeleton screens over spinners
- If spinner needed, use system `ProgressView()` — no custom animations
- Never block the entire screen for loading

### Tab Bar
- Text-only labels preferred over icons
- If icons required, use SF Symbols at regular weight
- Active state: primary text color. Inactive: tertiary text color
- No badges unless counting truly unread items

## 6. Animation Philosophy

### Purpose-Driven Only
Every animation must answer: "What state change am I communicating?"

| Acceptable | Purpose |
|-----------|---------|
| Ring fill on action | Confirms the action was registered |
| View transition (push/sheet) | Shows navigation hierarchy |
| Opacity fade on appear | Reduces visual jarring |
| Progress bar advancement | Shows passage of time/completion |

| FORBIDDEN | Why |
|-----------|-----|
| Confetti / particles | Celebration, not communication |
| Bouncing elements | Draws attention to nothing |
| Pulsing / breathing | Anxiety-inducing, not calming |
| Spring animations on static elements | Motion for motion's sake |
| Lottie animations as decoration | Heavy, unnecessary |

### Timing
- State changes: 0.3s `easeInOut`
- Micro-interactions (tap feedback): 0.15s
- Navigation transitions: system default (don't override)
- Always respect `@Environment(\.accessibilityReduceMotion)` — provide instant alternatives

### Implementation
```swift
// Always use withAnimation with explicit value parameter
withAnimation(.easeInOut(duration: 0.3)) {
    showContent = true
}

// Or the .animation modifier WITH value:
.animation(.easeInOut(duration: 0.3), value: isExpanded)

// NEVER: .animation(.default) without value parameter
```

## 7. Accessibility

### Non-Negotiable
- Every `onTapGesture` must have `.accessibilityLabel()` and `.accessibilityAddTraits(.isButton)`
- Every `Image` must have `.accessibilityLabel()` or `.accessibilityHidden(true)` if decorative
- Touch targets: minimum 44x44pt
- Support Dynamic Type: use `.font(.system(size:))` not hardcoded frames for text containers
- Use `@ScaledMetric` for spacing that should scale with text size
- Test with "Larger Accessibility Sizes" in Settings

### VoiceOver
- Read order should match visual hierarchy (top to bottom, left to right)
- Group related elements with `.accessibilityElement(children: .combine)`
- Provide `.accessibilityHint()` for non-obvious actions
- Use `.accessibilityValue()` for stateful elements (toggles, progress)

## 8. AI-Slop Checklist

Before shipping ANY SwiftUI view, check for these AI-generated-code smells:

- [ ] **Rounded cards with shadows everywhere** — cards should be flat or use subtle borders only
- [ ] **`.ultraThinMaterial` as decoration** — materials are for overlays on images, not for making things look "glassy"
- [ ] **Gradients as decoration** — no `LinearGradient` or `RadialGradient` unless it communicates data (like a heat map)
- [ ] **SF Symbols used as illustrations** — symbols are for UI chrome (nav, actions), not for empty state heroes or onboarding
- [ ] **Inconsistent spacing** — magic numbers scattered through the code instead of a spacing scale
- [ ] **Motivational copy** — "Great job!", "You're doing amazing!", "Keep it up!" — this is an app, not a life coach
- [ ] **`.bold` or `.semibold` everywhere** — if everything is bold, nothing is. Use thin/light as your default.
- [ ] **Card-on-card layouts** — a card inside a card inside a scroll view is a design bankruptcy filing
- [ ] **Rainbow accent colors** — more than 2 colors competing for attention
- [ ] **Excessive corner radius** — `cornerRadius(20)` on everything is the new `drop-shadow: 0 0 10px rgba(0,0,0,0.1)`
- [ ] **Padding inconsistency** — some items have 8pt padding, others 16pt, others 24pt with no pattern
- [ ] **Decorative dividers** — using `Divider()` between every element instead of spacing

## 9. Project Integration

This skill provides the UNIVERSAL layer. Projects customize on top:

1. **Project CLAUDE.md** defines specific tokens (exact hex values, font choices, forbidden patterns)
2. **This skill** defines the philosophy and patterns that make those tokens work
3. When conflict: **Project CLAUDE.md wins** — it knows its own brand

### How to Use
When reviewing or writing SwiftUI code:
1. Check project CLAUDE.md for specific design tokens first
2. Apply this skill's patterns for anything not covered by project rules
3. Run the AI-slop checklist before considering any view "done"
4. When suggesting UI changes, cite which principle from this skill supports the suggestion

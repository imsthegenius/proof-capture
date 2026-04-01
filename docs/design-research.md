# Checkd — Design Research Brief
> Compiled 2026-03-29 from 20+ sources including ColorBox, Opal, Atoms, PillowTalk, UX resource sites, and dark mode best practice guides.

---

## 1. Color Scheme Analysis

### ColorBox Blue Scale (Reference Palette)
The ColorBox tool generated an 11-step blue scale from `#ebf1ff` (near-white) to `#000033` (deep navy), with:
- Hue range: 220° → 240° (easeOut quadratic curve)
- Saturation: 0.08 → 1.0 (accelerating via easeOut)
- Brightness: 1.0 → 0.2 (descending via easeInQuart)

| Step | Hex | Use Case for Checkd |
|------|-----|---------------------|
| 0 | `#ebf1ff` | — (too blue for warm palette) |
| 10 | `#000033` | — (too blue for warm palette) |

**Verdict:** The blue scale demonstrates excellent perceptual luminance distribution but doesn't align with Checkd's warm near-black base. The *technique* is valuable — apply the same saturation/brightness curves to Checkd's warm hue range (30°–40°).

### Dark Mode Color Architecture (Cross-Source Consensus)

| Layer | Industry Standard | Checkd Current | Recommendation |
|-------|-------------------|----------------|----------------|
| Primary BG | `#121212` (Material) | `#0C0B09` | **Keep** — warmer and more distinctive than Material grey |
| Surface | `#1E1E1E` (Material) | `#1C1B19` | **Keep** — good elevation step |
| Elevated | `#2E2C2A` (Checkd) | `#2E2C2A` | **Keep** — clear 3-tier hierarchy |
| Primary text | `#E0E0E0` – `#FFFFFF` | `#F5F2ED` | **Keep** — warm white is premium differentiator |
| Secondary text | `#B3B3B3` (7.2:1) | `#A8A39B` (7.8:1) | **Keep** — exceeds WCAG AA |
| Tertiary text | `#757575` (4.5:1) | `#827D76` (4.8:1) | **Keep** — meets WCAG AA minimum |

**Key insight from Opal:** Use opacity-based text hierarchy (`rgba(255,255,255, 0.87/0.60/0.38)`) rather than separate color tokens. This creates more cohesive dark palettes because the text automatically harmonizes with any background tint.

### Accent Color Patterns from Reference Apps

| App | Accent Strategy | Hex Values |
|-----|----------------|------------|
| Opal | Multi-gradient pastels on dark | `#A9CBFF`, `#B39AFF`, `#D4FF9C`, `#9EF9FF`, `#E59CFF` |
| Atoms | Single warm yellow | `#FFDC61` active, `#F1ECDF` inactive |
| PillowTalk (chat) | Rose gradient | `#ff6b9d` → `#c44569` |

**Recommendation for Checkd:** Current warm white accent (`#EBEBE6`) is correct — it's the *anti-accent*. Where other apps use color to draw attention, Checkd uses luminance. This is the Swiss design move. **Don't add color accents.** The green/amber/red status colors already provide all the chromatic information needed.

### Desaturation Rule for Dark Mode
From multiple sources: saturated colors "vibrate" against dark surfaces. Use the 200–50 tone range (lighter, desaturated variants). Checkd's `statusGood` (`#6ABE6E`), `statusFair` (`#DCBE8C`), and `statusPoor` (`#D25A55`) are already appropriately desaturated — no change needed.

---

## 2. Typography Patterns

### Industry Benchmarks

| App/Source | Primary Font | Weight Strategy | Size Range |
|-----------|-------------|-----------------|------------|
| Opal | System sans + antialiased | Variable, responsive calc() | `0.875rem` base, viewport-scaled |
| Atoms | System (antialiased) | Not specified (likely regular/medium) | 62.5% base → responsive scaling |
| Apple HIG 2025 | SF Pro | Regular → Bold | 17pt default body |
| Premium dark apps | SF Pro / system | ultraLight–light for hero, regular for body | 12pt–120pt |

### What Makes Typography Feel Premium on Dark Backgrounds

1. **Font smoothing is critical:** `-webkit-font-smoothing: antialiased` + `-moz-osx-font-smoothing: grayscale`. Light text on dark backgrounds renders thicker without antialiasing (subpixel rendering adds weight). Checkd should ensure this is applied globally.

2. **Thin weights read as luxurious on dark:** Checkd's use of `.ultraLight` for hero numbers and `.light` for body is the correct premium strategy. On dark backgrounds, thin type with generous tracking looks expensive (watch/jewelry brand pattern).

3. **Weight contrast replaces color contrast:** Instead of using different colors to create hierarchy (which clutters dark palettes), use weight + size steps. Checkd already does this: 60pt ultraLight → 24pt light → 15pt light → 12pt regular.

4. **Tracking increases with size:** Checkd's 12-point tracking on the 60pt PROOF title follows the luxury typography rule — large type needs wide tracking. The 4-point tracking on 12pt pose labels also follows this correctly.

### Specific Recommendation
**Add text shadow for body text readability:** `text-shadow: rgba(0,0,0,0.01)` (from Opal). This is a near-invisible shadow that triggers the GPU text rendering path on iOS, producing smoother edges on light-on-dark text. Zero visual impact, measurable clarity improvement.

---

## 3. Micro-Animation Catalogue

### Animations Worth Implementing (Prioritized)

#### P0 — Essential (directly improves core UX)

**1. Border Glow Pulse (Already Designed, Refine Timing)**
- Current: Pulsing amber border when "almost ready"
- Refinement from Opal: Use `cubic-bezier(0.4, 0, 0.6, 1)` easing (not linear pulse). Pulse cycle: 1.2s. Opacity range: 0.6 → 1.0 → 0.6. The ease-in-out makes the glow feel organic, like breathing.

**2. Ready → Capture Transition**
- When all checks pass (border turns green): border glow should *settle* (stop pulsing, hold at full opacity) for 300ms before countdown begins. This "lock-on" moment gives the user confidence the system has committed.
- Timing: 300ms ease-out to full green → 200ms hold → countdown begins

**3. Countdown Number Transitions**
- Each number should scale from 1.1x → 1.0x with `0.3s ease-out` opacity from 0 → 1
- Outgoing number: scale 1.0x → 0.9x, opacity 1 → 0, `0.2s ease-in`
- Stagger: slight overlap (outgoing starts 50ms before incoming)
- Reference: PillowTalk uses `cubic-bezier(0.4, 0, 0.6, 1)` for similar pulse effects

**4. Photo Preview Check Animation**
- After capture, when the 2s preview shows: green checkmark should draw itself (stroke animation)
- SVG path stroke-dashoffset from full length → 0 over `0.4s ease-out`
- Simultaneous: captured photo scales from 1.05x → 1.0x with `0.3s ease-out` (subtle "landed" feel)

#### P1 — Polish (enhances premium feel)

**5. Pose Transition**
- Between poses (front → side → back): cross-dissolve the pose label
- Outgoing label: opacity 1 → 0, translateY 0 → -8pt, `0.2s ease-in`
- Incoming label: opacity 0 → 1, translateY 8pt → 0, `0.3s ease-out`, delayed 100ms
- Total transition: ~400ms perceived

**6. Session Complete — Photo Grid Reveal**
- When all 3 photos are captured, reveal them with staggered entry
- Each photo: opacity 0 → 1, scale 0.95 → 1.0, `0.3s ease-out`
- Stagger: 80ms between each (front, side, back)
- Total perceived time: ~540ms

**7. History Row Entry (List Animations)**
- When history list populates: each row enters with opacity 0 → 1, translateY 12pt → 0
- Timing: `0.25s ease-out`, staggered 50ms per item
- Maximum stagger: 5 items (items 6+ appear instantly to avoid sluggish feel)
- Reference: Atoms uses similar stagger on habit list

**8. Home Screen Number Counter**
- Session count (large ultraLight number): when value changes, animate via counting up
- Old value slides up and fades out, new value slides up from below
- Timing: `0.4s ease-out` for both
- Reference: Opal uses similar treatment for focus score

#### P2 — Delight (nice-to-have, implement last)

**9. Comparison Slider**
- When comparing two sessions: implement a drag-reveal slider between two photos
- Drag handle should have subtle haptic feedback at midpoint
- Photos should have slight parallax (0.5% translateX in opposite directions based on handle position)

**10. Empty State Number**
- The large "0" on empty states: subtle float animation
- translateY: 0 → -4pt → 0, `3s ease-in-out`, infinite, paused until view appears
- Very subtle — should feel like the number is breathing, not bouncing

### Animations to AVOID (from research)

| Pattern | Why Not |
|---------|---------|
| Confetti/particles on completion | Violates Swiss design, adds no information |
| Bouncing/spring physics on buttons | Feels playful, not professional |
| Gradient color cycling (Opal style) | Contradicts warm white accent strategy |
| 3D gem/reward unlocking (Opal) | Gamification doesn't fit coaching context |
| Expanding card transitions | Adds latency to navigation, no value for photo review |

---

## 4. Layout & Spacing Intelligence

### Spacing Patterns from Reference Apps

**Opal (most relevant for dark mode):**
- Grid column gap: 54px (desktop) — suggests generous horizontal spacing
- Card border-radius: 18px
- Consistent 1px padding offsets for gradient border technique
- Viewport-relative sizing throughout

**Atoms:**
- Responsive container system with named sizes (small/medium/large)
- Consistent use of flexbox with inline-flex patterns
- Breakpoints: 480, 768, 992, 1680px

### Negative Space as Premium Signal
Multiple sources confirm: premium dark apps use *more* negative space than light apps. On dark backgrounds, content islands feel more "staged" — like gallery pieces on dark walls. Checkd's current spacing (4pt grid: 4/8/16/24/32/48) is tight enough for mobile utility but should err toward the larger values for primary content areas.

**Specific recommendations:**
- Home screen: increase vertical spacing between session count and last photo to 48pt (XXL)
- Camera view: pose label should have 32pt (XL) bottom padding, not 24pt, for 2-meter readability
- History list: row height of 72pt minimum (44pt content + 28pt padding) for comfortable touch targets
- Session complete: 32pt gap between photo thumbnails

### Card vs. Flat
Checkd currently uses a flat approach (no card containers). **Keep this.** Cards add visual noise on dark backgrounds because they require border or shadow treatment. Flat layouts with spacing-only separation are the Swiss approach and feel more premium in dark mode.

---

## 5. Component Inspiration

### Buttons

| Source | Pattern | Checkd Application |
|--------|---------|-------------------|
| Opal | Scale to 1.05x on press, glow shadow on active | Add subtle scale: pressed → 0.97x, `0.1s ease-out`. No glow (too decorative) |
| Atoms | Arrow translateX 0.25rem on hover | N/A (no hover on iOS) |
| PillowTalk | translateY -2px lift on hover | N/A (no hover on iOS), but useful for long-press feedback |
| Apple HIG | 52pt min height, capsule shape | Already implemented in Checkd |

**Recommended button press feedback:**
- Scale: 1.0 → 0.97 on touchDown, `0.08s ease-out`
- Scale: 0.97 → 1.0 on touchUp, `0.15s ease-out`
- Opacity: 1.0 → 0.85 on touchDown, simultaneous
- No shadow, no glow, no gradient shift

### Progress Indicators

**Atoms habit completion circle (highly relevant):**
- Tap-and-hold triggers inner circle growing toward outer border
- When inner reaches outer → completion registered
- This is the exact pattern for Checkd's capture readiness: border glow fills inward as checks pass

**Adaptation for Checkd:**
- Body detection confidence could drive a subtle inner glow that intensifies as readiness increases
- Instead of binary "ready/not ready", the border could show *progress toward readiness*
- 0% = white 30% border → 50% = amber, thickening → 100% = green, solid 4pt

### Toggle/Selection Components

**For voice selection (Male/Female) in onboarding:**
- Segmented control pattern (not toggle switch — this is a selection, not on/off)
- Background: `surface` color (`#1C1B19`)
- Selected segment: `accent` color (`#EBEBE6`) with `0.2s ease-out` slide
- Text: selected = `background` color (`#0C0B09`), unselected = `textSecondary`

### Empty States

Checkd's current pattern (large "0" + one-line explanation) aligns with Swiss design best practices. No app in the research set does this better. The only addition: the subtle float animation on the "0" described in the micro-animation section.

---

## 6. UX Flow Insights

### Onboarding Patterns

| App | Steps | Pattern | Lesson for Checkd |
|-----|-------|---------|-------------------|
| Opal | 24 steps | Personalized quiz → Focus Report | Too long for Checkd, but the "personalized output" pattern is powerful |
| Atoms | ~5 steps | Identity-first framing ("I will X to become Y") | Motivation framing could work for first session setup |
| PillowTalk | 3-4 steps | Minimal, straight to value | Closest to Checkd's 3-step approach |

**Checkd's 3-step onboarding is correct.** The research confirms: for utility apps with a single job (take photos), fewer steps = faster time-to-value. Opal's 24-step quiz works because their product *is* the personalization. Checkd's product is the photo session.

**One enhancement:** After the first completed session, show a one-time "Your first session is saved" confirmation with a subtle visual of the 3 captured photos. This is the "personalized output" moment — the user sees the system worked.

### Navigation Patterns

**Tab bar vs. no tab bar:**
- Opal: Tab bar (multiple primary features)
- Atoms: Tab bar (habits, mindset, settings)
- Checkd should NOT have a tab bar — it has one job. The home screen *is* the app. History and settings are secondary (accessible via icon/gesture).

**Gesture navigation:**
- Swipe-to-delete (already in Checkd for history) is standard
- Consider: swipe right on history row to quick-compare with previous session
- Do NOT add pull-to-refresh (there's nothing to refresh — local-first)

### Camera UX Insights

From dark mode camera research:
- **Never put UI elements in the camera feed area** except critical status (Checkd already follows this)
- **Border glow > overlay text** for readiness indication (Checkd already follows this)
- **Audio feedback > visual feedback** for actions the user can't see (back pose) — Checkd's audio-first approach is validated

---

## 7. Recommended Changes for Checkd (Prioritized)

### Must-Do (Before Launch)

1. **Add font smoothing globally** — Apply `-webkit-font-smoothing: antialiased` equivalent in SwiftUI. Light text on dark backgrounds renders too heavy without it. This is a one-line change with significant visual impact.
   - SwiftUI: `.environment(\.legibilityWeight, .regular)` or custom font rendering

2. **Refine border glow pulse easing** — Change from linear pulse to `cubic-bezier(0.4, 0, 0.6, 1)` (easeInOut) with 1.2s cycle. Current linear pulse feels mechanical; the eased version feels like breathing.

3. **Add countdown number transitions** — Numbers should cross-fade with subtle scale (1.1 → 1.0 incoming, 1.0 → 0.9 outgoing). Currently abrupt number changes feel jarring at 2-meter viewing distance.

4. **Add capture confirmation animation** — Green checkmark should draw itself (stroke animation, 0.4s) on the 2-second preview. This gives users confidence the photo was captured successfully without needing to read text.

### Should-Do (Polish Pass)

5. **Implement staggered list entry** — History rows and session complete photos should enter with staggered opacity + translateY animation (0.25s ease-out, 50ms stagger). This is the single most impactful "premium feel" animation.

6. **Add button press scale feedback** — All tappable elements: scale to 0.97x on press, 0.08s ease-out. Release to 1.0x, 0.15s ease-out. Subtle but universally expected in premium iOS apps.

7. **Session count number transition** — When session count changes, animate the number sliding up (old out, new in). Small touch but reinforces "something happened."

8. **Increase key spacing values** — Camera pose label bottom padding: 24pt → 32pt. Home screen vertical gaps: use XXL (48pt) between major sections. History row height: minimum 72pt.

### Could-Do (Future Enhancement)

9. **Comparison drag slider** — For photo comparison, implement a vertical drag-to-reveal slider. More engaging than side-by-side static view.

10. **Opacity-based text hierarchy** — Consider migrating from separate hex color tokens to opacity-based system (`rgba(245, 242, 237, 0.87/0.60/0.38)`). This ensures text always harmonizes with background changes and simplifies the token system.

---

## Appendix: Source Quality Assessment

| Source | Usefulness | Notes |
|--------|-----------|-------|
| ColorBox | ★★★☆☆ | Technique valuable, specific palette not applicable |
| Opal (app + site) | ★★★★★ | Best dark mode reference — gradient borders, opacity text, animation timing |
| Atoms (app + site) | ★★★★☆ | Habit completion circle animation is directly applicable pattern |
| PillowTalk | ★★★☆☆ | Rose/pink palette irrelevant, but pulse timing and glass morphism technique useful |
| UX Myths | ★★★★☆ | Myth #28 (whitespace) and #34 (simple ≠ minimal) directly validate Checkd approach |
| learnmobile.design | ★★★☆☆ | Good iOS resource index, no deep patterns |
| degreeless.design | ★★★☆☆ | Typography book references (Lupton) valuable for deepening type knowledge |
| designsystems.com | ★★★☆☆ | Confirmed token-based approach is industry standard |
| goodpractices.design | ★★☆☆☆ | Surface-level, mostly links |
| principles.design | ★★☆☆☆ | Index only, would need deep dives per principle set |
| Dark mode guides (3 sources) | ★★★★★ | Concrete hex values, contrast ratios, elevation patterns — essential reference |
| Mobbin screens | ☆☆☆☆☆ | All blocked (requires authentication) — couldn't access any |
| Twitter (@Abmankendrick) | ☆☆☆☆☆ | 402 paywall — couldn't access |

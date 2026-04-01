---
description: Blocks celebration animations, confetti, particle effects, motivational copy, and push notification patterns in SwiftUI apps.
globs:
  - "**/*.swift"
---

<rule>
When editing Swift/SwiftUI files, NEVER add:

**Celebration animations:**
- Confetti effects or confetti libraries
- Particle emitters or particle effects
- Firework animations
- Bouncing or pulsing celebration elements
- Lottie animations used as decoration

**Motivational copy:**
- "Great job!", "You're amazing!", "Keep it up!", "Way to go!"
- "You're doing incredible!", "Proud of you!"
- Any wellness-coach language — the app respects the user's intelligence

**Push notifications:**
- `UNUserNotificationCenter`
- `requestAuthorization(.alert)`
- Any push notification scheduling

The app communicates through state changes, not celebrations. Animation exists to confirm actions, not to applaud them.
</rule>

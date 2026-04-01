---
description: Blocks gradient usage in SwiftUI — LinearGradient, RadialGradient, AngularGradient, .gradient modifier. Flat design only unless gradients communicate data.
globs:
  - "**/*.swift"
---

<rule>
When editing Swift/SwiftUI files, NEVER use decorative gradients:
- `LinearGradient`
- `RadialGradient`
- `AngularGradient`
- `.gradient` modifier on colors
- `MeshGradient`

Flat backgrounds with solid colors are premium. Gradients as decoration are the universal sign of AI-generated or amateur design.

Exception: gradients that communicate DATA (heat maps, progress visualization, chart fills) are acceptable.
</rule>

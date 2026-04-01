---
description: Blocks forbidden font weights in SwiftUI — .regular, .medium, .bold, .semibold, .heavy, .black. Only .thin, .ultraLight, and .light are permitted unless project CLAUDE.md says otherwise.
globs:
  - "**/*.swift"
---

<rule>
When editing Swift/SwiftUI files, NEVER use these font weights:
- `.fontWeight(.regular)` — unnecessary (it's the default)
- `.fontWeight(.medium)`
- `.fontWeight(.semibold)`
- `.fontWeight(.bold)`
- `.fontWeight(.heavy)`
- `.fontWeight(.black)`
- `.bold()` modifier
- `weight: .medium`, `weight: .semibold`, `weight: .bold`, `weight: .heavy`, `weight: .black`

Permitted weights: `.thin`, `.ultraLight`, `.light`

Typography hierarchy comes from SIZE, not weight. Large thin type reads as premium and confident. Bold type reads as shouting.

If you need emphasis, increase font size or use a different color — not weight.
</rule>

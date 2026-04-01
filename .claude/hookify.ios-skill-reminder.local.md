---
description: Reminds to check ios-design-system skill and project CLAUDE.md when editing any Swift file. Generic iOS reminder — not project-specific.
globs:
  - "**/*.swift"
---

<rule>
You are editing a Swift file in an iOS project.

Before making changes:
1. Check the project's CLAUDE.md for project-specific design tokens and forbidden patterns
2. Use the `ios-design-system` skill for universal iOS design standards (typography, spacing, animation, color)
3. If this is a major UI change, plan to run `ios-design-audit` skill afterward

Key reminders:
- Font weights: prefer .thin/.ultraLight/.light — avoid .medium/.bold/.semibold
- Colors: use theme tokens, not hardcoded Color(.red) or Color(hex:) outside the theme file
- Animation: always use .animation(_, value:) — never .animation() without value parameter
- Accessibility: every onTapGesture needs .accessibilityLabel()
- Layout: no GeometryReader inside ScrollView, no AnyView
</rule>

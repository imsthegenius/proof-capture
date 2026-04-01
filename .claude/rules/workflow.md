# Proof Capture — Development Workflow Rules

These rules apply to ALL agents working in this project, regardless of session or plugin configuration.

## Phase Discipline

### Before ANY new feature or UI work:
1. **Brainstorm first** — explore intent, requirements, and design before writing code. Ask clarifying questions. Do not scaffold, create files, or write implementation code until the approach is agreed upon.
2. **Write a plan** — break the work into discrete tasks with clear acceptance criteria before implementing.

### Before ANY bug fix:
1. **Diagnose before fixing** — read the error, check assumptions, form a hypothesis. Do not guess-and-check or blindly retry.
2. **Reproduce first** — confirm the bug exists and understand the conditions before changing code.

### Before claiming work is complete:
1. **Build verification required** — run `xcodebuild` and confirm zero errors before claiming success.
2. **Evidence before assertions** — never say "fixed", "done", or "working" without showing proof (build output, test result, screenshot).

## Implementation Standards

- **TDD when testable** — write the test first, see it fail, then implement. Not every Swift view needs a test, but all model/service/utility code should be test-driven.
- **One concern per commit** — each commit should do one thing. Don't bundle unrelated changes.
- **Read before edit** — always read a file before modifying it. Understand existing code before suggesting changes.
- **No speculative abstractions** — don't add protocols, generics, or abstractions for hypothetical future needs. Three similar lines > one premature abstraction.

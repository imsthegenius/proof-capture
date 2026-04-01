---
name: design-agent
disable-model-invocation: true
description: "Dispatch the design agent for any UI/UX design work: landing pages, dashboards, components, page redesigns, new features. This agent autonomously generates a design system (UI UX Pro Max), creates visual mockups (Stitch MCP + Nano Banana 2), builds production code (21st.dev + frontend-design principles), and verifies the result (web-ui-audit). Use when the user says 'design', 'build a page', 'redesign', 'new landing page', 'dashboard UI', 'component design', 'make it look good', 'UI for', 'design system', or any request involving visual interface creation. Also trigger when frontend-design skill would normally trigger, as this agent wraps and extends it. Do NOT trigger for non-visual work (API routes, database, scripts, content writing)."
---

# Design Agent — Dispatch Skill

This is a thin dispatch layer. The agent's brain lives at `.claude/agents/design-agent/AGENT.md`.

## How to Dispatch

1. **Read** `.claude/agents/design-agent/AGENT.md` to get the full agent instruction set
2. **Build a brief** from the user's request (what, who, industry, stack, constraints)
3. **Spawn** the agent:

```
Agent(
  description: "Design: <3-5 word summary>",
  subagent_type: "designer",
  prompt: "<agent instructions from AGENT.md>\n\n<design brief>\nTask: ...\nProject: ...\nStack: ...\n</design brief>",
  mode: "auto",
  run_in_background: <true if user has parallel work, false if design is the focus>
)
```

## Parallel Design Tasks

If the user asks for multiple designs (e.g., "design the landing page and the dashboard"), spawn separate agents in a single message. Each gets its own brief.

## Tool Dependencies

The agent expects these to be available:
- **UI UX Pro Max** — `.claude/skills/ui-ux-pro-max/` (Python search scripts)
- **Stitch MCP** — configured in `.mcp.json` (optional, graceful fallback)
- **Nano Banana 2** — `gemini-3.1-flash-image-preview` via AI Gateway
- **21st.dev MCP** — `mcp__magic__21st_magic_component_builder`
- **Playwright** — for verification screenshots

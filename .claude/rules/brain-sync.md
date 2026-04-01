---
description: CRITICAL — persist knowledge to second brain continuously to survive context compaction
globs: ["**"]
---

# Brain Sync — Continuous Persistence

The second brain at `~/Desktop/second-brain/` is the ONLY thing that survives context compaction. If you don't write it to the brain, it's lost when context compresses.

## How to find your vault path

Read `~/Desktop/second-brain/.workspace-map.json` to find the vault subfolder for the current workspace. If no mapping exists, use `learnings/`.

## RULE: Update the brain AS YOU WORK, not after

After completing any of these, IMMEDIATELY update the brain before doing anything else:
- A milestone or significant progress → update the vault folder's main file (e.g., `context.md` or `progress.md`)
- A design decision or correction → update vault folder + relevant pattern file
- An API tested with useful results → update or create a pattern in the relevant patterns folder
- A technical lesson learned → update `learnings/<topic>.md`
- User feedback that changes approach → update vault folder + relevant file
- A credential obtained or status changed → update vault folder

Do NOT batch brain updates. Do NOT wait until end of session. Do NOT plan to "sync later."

## RULE: Maintain the knowledge graph

When creating a NEW note, you MUST:
1. Search for related notes: `obsidian search vault=second-brain query="<topic>"`
2. Add a `## Links` section with `[[wikilinks]]` to related notes (minimum 1 link)
3. Append a backlink to the most relevant existing note: `obsidian append vault=second-brain file="<related>" content="\n- [[new-note]] — description"`

When UPDATING an existing note with a new topic/connection, add a `[[wikilink]]` inline or in the Links section if the connection doesn't already exist.

Zero-link notes are forbidden. Every note must connect to the graph.

## At conversation start

ALWAYS read your vault folder's main file first (check the workspace map) to know where things stand.

## What stays out of the brain
- API keys/secrets (stay in .env)
- Code (stays in repo)
- Ephemeral task tracking (use Claude Code tasks)

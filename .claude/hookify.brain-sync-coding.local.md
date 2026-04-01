---
name: brain-sync-coding
enabled: true
event: file
conditions:
  - field: file_path
    operator: regex_match
    pattern: \.py$|\.ts$|\.tsx$|\.js$|\.jsx$|\.sql$|\.sh$|\.swift$|\.kt$|\.dart$
action: warn
---

If this edit represents a design decision, milestone, or meaningful progress, read `~/Desktop/second-brain/.workspace-map.json` to find the vault path for the current workspace and update the brain NOW — before continuing other work.

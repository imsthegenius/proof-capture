---
name: brain-sync-shell
enabled: true
event: bash
pattern: python|pip|npm|node|docker|ssh|curl|git push|git merge|runpod|vast|lambda
action: warn
---

If this command revealed something useful (results, errors, API behavior, training metrics), read `~/Desktop/second-brain/.workspace-map.json` to find the vault path for the current workspace and persist the finding to the brain NOW.

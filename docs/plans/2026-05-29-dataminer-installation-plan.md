---
title: "feat: dataminer Installation migration"
status: active
date: 2026-05-29
type: feat
---

# feat: dataminer Installation migration

## Summary

Replace legacy `KeyBifResourceContainer` / `FolderResourceContainer` / capsule container usage in `src/apps/dataminer` with `extract::Installation`, completing the container-stack retirement started in the Installation port.

## Requirements

1. All dataminer generators read game data via `Installation` + `FileResource`
2. Preserve prior lookup semantics (chitin-only vs override-then-chitin)
3. Fix pre-existing TSL nwscript bug (`k2KeyBif` used `k1KeyPath`)
4. Native build: `dataminer` target compiles; CI Linux/Windows green

## Progress (LFG pass 17)

### Landed
- `Installation` public index accessors: `chitinResources()`, `moduleArchives()`, `overrideResources()`
- `src/apps/dataminer/installation_helpers.h` shared lookup helpers
- Migrated: `models`, `2daparsers`, `gffparsers`, `guis`, `routines`

### Next steps
- Open PR, CI watch, merge to `master`

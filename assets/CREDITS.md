# CREDITS.md — CoilClash (Snake Arena)

Asset provenance and licensing record. **Non-negotiable (§0.1.2):** no
copyrighted or proprietary material. Every placeholder must be procedural
(hand-made by the agent) or CC0, with the licence recorded here.

## Policy

* All placeholder art/audio is generated procedurally by the build agent
  (scripts under `tools/`) or is engine-built-in. No downloaded assets.
* If any external asset is ever added: it MUST be CC0 (or similarly
  permissive) and recorded in the table below with source URL + licence
  text reference.

## Current assets

| Asset | Origin | Licence | Notes |
|---|---|---|---|
| `icon.svg` | Repo-provided original placeholder (initial commit) | Project-owned | Replace before shipping (human task, §47.17) |
| Arena ground / boundary / soft-zone ring materials | Procedural (StandardMaterial3D in `scenes/arena/arena.tscn`) | Project-owned | No textures used |
| Default UI font | Godot engine built-in default theme font (engine-embedded) | Godot Engine license (MIT) | Will be replaced by an OFL-licensed font in Phase 8; record it here then |
| Audio | None yet | — | Phase 10: procedural SFX via `tools/gen_sfx.gd` |
| AI names (`resources/data/ai_names.txt`) | Not created yet | — | Will be original, non-infringing (§8.4) |

## Third-party code

| Component | Licence | Notes |
|---|---|---|
| Godot Engine 4.7.2 | MIT | Engine only; no third-party addons used |
| No addons installed (`addons/` empty) | — | Ad SDK plugins arrive in Phase 11 and will be recorded here |

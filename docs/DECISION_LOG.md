# DECISION LOG — CoilClash (Snake Arena)

> Mirror of §46 in `MASTER_PROMPT_SNAKE_ARENA.md`. That file is the source of
> truth; keep both in sync when appending.

| # | Decision | Rationale | Reversible? |
|---|---|---|---|
| 1 | Boost costs power, no cooldown | Creates a real economic tradeoff and feeds the arena with motes | Yes — `boost_mode` enum |
| 2 | Circular arena with soft, non-lethal walls | Corner camping and unfair wall deaths both kill retention | Yes |
| 3 | Distance-sampled history ring buffer for bodies | Best smoothness-to-cost ratio; trivially supports growth | Hard |
| 4 | Custom spatial hash instead of physics bodies | 400+ Area3Ds is not viable on web/mobile | Hard |
| 5 | Self-collision off by default | Feels arbitrary in continuous movement | Yes |
| 6 | Rim-light threat colouring | Highest-impact readability feature | Yes |
| 7 | No ads in the first session run | First-session retention > first-session revenue | Yes (config) |
| 8 | Ad layer fully abstracted behind `AdProvider` | Lets us ship on web and mobile from one codebase and test without an SDK | Hard |
| 9 | 10% power buffer on eat rule | Removes coin-flip outcomes | Yes |
| 10 | Engine version pinned to **Godot 4.7.2 stable** | Repo's `project.godot` already declared features `"4.7", "GL Compatibility"`; newest stable 4.x available at Phase 0. Recorded in `docs/ENVIRONMENT.md`. | Yes |
| 11 | Dev sandbox has no GPU/audio/display; all AI-side runs are headless or under Xvfb+Mesa llvmpipe | Sandbox constraint, not a choice. Perf budgets (§19), audio quality, and touch feel must be human-verified on real hardware (Part C of `docs/HUMAN_TASKS.md`). `tools/setup_env.sh` restores the toolchain after sandbox restarts. | Yes |
| 12 | Repo's `3d/physics_engine="Jolt Physics"` removed → default GodotPhysics3D | Jolt is a GDExtension; §19 mandates Extensions Support = off for the web export, which would leave the primary target without a physics server. Gameplay barely uses physics (§6.4: one Area3D per head; bodies are MultiMesh + custom spatial hash). | Yes |
| 13 | Hand-rolled headless test runner (`tests/run_tests.gd`) instead of GUT | §9A explicitly allows it; zero external addons, deterministic exit codes, works fully headless in the sandbox. | Yes |
| 14 | Phase 1 boot flow: `main.tscn` → arena directly, no menu (menu screens don't exist until Phase 8) | Matches the §13.4 FTUE philosophy (straight into gameplay). Temporary dev flow; the MENU state path activates in Phase 8. | Yes |
| 15 | `.tscn` Transform3D values are serialized row-flat: `(X.x, Y.x, Z.x, X.y, Y.y, Z.y, X.z, Y.z, Z.z)`. NEVER hand-compute scene transforms — take the tuple from the engine (PackedScene.pack, or set rotation/look_at at runtime). | A hand-written transform with vector-grouped triples loads TRANSPOSED — the arena sun pointed up and the ground rendered unlit (caught by the screenshot harness, fixed by re-serializing from the engine). | No (format rule) |
| 16 | Snake body = one `MultiMeshInstance3D` per snake with **fixed-cap buffers**: `instance_count` set once to `max_segment_count` (§19 zero-alloc pattern); grow/shrink drive `visible_instance_count` only. | Per-grow buffer resizing errors every tick (buffers must match `instance_count` exactly) and reallocates; fixed cap is the §19-approved steady-state path. | Hard |
| 17 | MultiMesh **TRANSFORM_3D buffer is 16 floats per instance** in Godot 4.7 (`basis.x + w`, `basis.y + w`, `basis.z + w`, `origin + w`) — verified empirically: a 12-float buffer is REJECTED with "different size from existing buffer". | Docs implied 12 for TRANSFORM_3D; the engine validates 16. Empiricism wins. | No (engine behaviour) |
| 18 | Camera yaw convention bridge: snake `facing_angle_deg` (0° = +Z, positive → +X) vs camera yaw (0° = −Z, positive → −X) differ by 180°, so `camera_yaw = facing + 180°` and the rig position offset is `+facing` horizontal × distance. | First version tracked exactly backwards — head projected off-screen (caught by the new on-screen framing assertion in the verify harness, §50-compliant "see it before claiming it"). | No (convention rule) |
| 19 | Boost drain **also shrinks the body** (via `_sync_segment_target`) — a long snake boosts fast, so boosting must cost length as well as power. | Completes the §3.4 risk loop. Corpse-mote emission when shrinking is deferred to Phase 3 (mote system). | Yes |
| 20 | Phase 2 verify harness (`scenes/boot/verify.tscn`): replicates the boot state sequence (GameManager → PLAYING), pre-feeds `add_power(10)` before asserting boost (spawn power 2.0 < `min_boost_power` 4.0, so a fresh snake legitimately cannot boost — a "false fail" trap), asserts the §3.2 segment formula, checks the head projects on-screen, guards double-print with a `_finished` flag. | Exit criteria §50: every claim must be observed. The harness encodes them as executable checks with `CC_VERIFY_PASS`/`CC_VERIFY_FAIL` + exit codes. | Yes |
| 21 | §3.1 curves apply at **power 1 too** — tests assert the formula value (speed ≈ 10.68, turn ≈ 260.62) rather than the raw base constants (11.0 / 280.0). | The curve terms are non-zero at power 1; treating base constants as "power 1 values" is a misreading of §3.1. | No (spec reading) |
| 22 | Head visual = plain `MeshInstance3D` sphere (1.15× head radius, power-tier tinted), child-added by `SnakeBody`; the controller node itself has no mesh. | Keeps the controller physics-only while the body owns all visuals; a separate head instance avoids MultiMesh index-0 special-casing. | Yes |
| 23 | `add_power` growth eases in per segment (~0.25 s, `ease_out_cubic`); synchronous tests assert `_segments_target` (the target), not the live eased count. | §3.2 growth is an animation, not an instant resize; asserting the eased count would be timing-fragile. | Yes |

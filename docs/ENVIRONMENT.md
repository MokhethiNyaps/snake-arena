# ENVIRONMENT.md — CoilClash (Snake Arena)

**Phase 0 — Recon report. Written: 2026-08-31. Godot: 4.7.2.stable.official.ed1daf0bf**

This file records the development environment the AI agent works in, what it
verified, and what it cannot do here. Update it whenever the toolchain changes.

---

## 1. Sandbox host

| Item | Value |
|---|---|
| OS | Debian GNU/Linux 13 (trixie), kernel 6.1.158+, x86_64 |
| CPU | 2 vCPU — Intel Xeon @ 2.60 GHz |
| RAM | 1.9 GB total (no swap) |
| Disk | 20 GB free |
| GPU | **None** (`/dev/dri` absent — no hardware acceleration of any kind) |
| Audio | No sound hardware; no ALSA/Pulse libs → Godot falls back to its **dummy audio driver** |
| Network | Internet access OK (GitHub reachable) |
| Display | None. Rendered runs use **Xvfb** + **Mesa llvmpipe** (software OpenGL 4.5 core). |
| Permissions | Non-root user with passwordless `sudo` |

**Consequence:** performance numbers measured here (frame time, AI ms, draw calls)
are *not* representative of target hardware. They are useful for regression
detection and correctness, but the §19 performance budgets must be validated by
the human on real devices (see `docs/HUMAN_TASKS.md` Part C when it exists).

## 2. Godot engine

| Item | Value |
|---|---|
| Version | **4.7.2.stable.official.ed1daf0bf** (latest 4.x stable at install time) |
| Build | Official Linux x86_64, standard (non-.NET) |
| Install path | `/opt/godot472/godot`, symlinked to `/usr/local/bin/godot` |
| Source | `github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip` |
| Chosen because | Repo's `project.godot` already declares features `"4.7", "GL Compatibility"`; spec requires 4.3+ and prefers newest. Logged in §46 decision #10. |
| Persistence caveat | `/opt` is **outside the sandbox's persisted workspace** — after a sandbox restart, re-run `bash tools/setup_env.sh` (idempotent, restores everything in ~1 minute). |

### Verified (Phase 0 exit criteria)

```
$ godot --version
4.7.2.stable.official.ed1daf0bf

$ godot --headless --path <empty project>     # empty project, 60 frames, clean exit 0
EMPTYTEST_READY
EMPTYTEST_60_FRAMES_OK
```

* Headless mode works with the dummy display driver — this is how the automated
  test suite will run (`tests/run_tests.gd`).
* Rendered mode works under `xvfb-run` with Mesa llvmpipe: OpenGL 4.5 Core
  (Compatibility renderer), screenshot capture via
  `Viewport.get_texture().get_image().save_png()` verified (1280×720 PNG with
  real content).
* All dynamic libraries of the engine binary resolve (`ldd` clean).

### Capability matrix for later phases

| Need | Available here? | How |
|---|---|---|
| Headless project run / tests | ✅ | `godot --headless --path . --script res://tests/run_tests.gd` |
| Rendered run + screenshots (no GPU) | ✅ | `xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720` |
| Input simulation (mouse/keys) for verification | ✅ | GDScript `Input.parse_input_event()` in test scripts (touch = emulated via `InputEventScreenTouch/Drag`; gamepad via `InputEventJoypadMotion`) |
| Audio audible playback | ❌ | Dummy audio driver. Audio *logic* (voice limiting, ducking, state) is testable; sound quality is not. Human must listen on real hardware. |
| GPU performance profiling | ❌ | Software rasterizer. Budgets (§19) validated by human on real devices. |
| Vulkan / Forward+ | ❌ | No GPU. Project uses GL Compatibility (matches Web target: WebGL2). |
| Android build / real device test | ❌ | No Android SDK, no device. Later human task (§47). |
| Real ad SDK calls | ❌ | Mock/Null providers only (§45.7) — by design. |

## 3. Export templates

* **Status at Phase 0:** not downloaded. URL verified reachable:
  `https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz`
  (the GitHub release asset redirects to the CDN correctly).
* Plan: install into `~/.local/share/godot/export_templates/4.7.2.stable/` during
  Phase 11 when the Web export preset is built. The Web template alone is what
  we need for the primary target.

## 4. Git / repo access

| Item | Value |
|---|---|
| Repo | `https://github.com/MokhethiNyaps/snake-arena.git` (branch `main`) |
| Clone / pull | ✅ works |
| Commit | ✅ works locally (identity: `ArenaAI Agent <agent@arena.ai>` — change if you prefer different attribution) |
| **Push** | ✅ works (2026-09-02): human-provided fine-grained PAT, stored ONLY in `~/.git-credentials` via `credential.helper store` — that file and `.git/config` are excluded from workspace snapshots, so a FRESH session loses both: re-add the remote (`tools/setup_env.sh` does) and re-provide the token (or push locally). Token value is intentionally NOT recorded here. |

## 5. Blockers (Phase 0)

| # | Blocker | Impact | Needed from the human |
|---|---|---|---|
| 1 | ~~No GitHub push credentials~~ **RESOLVED 2026-09-02** — PAT pasted in chat, first push succeeded (`7c3fb2d..5b9ba5a`). Residual: the credential is session-scoped (see §4) and the token was exposed in chat — the human should rotate it once the engagement ends. | n/a — resolved. |
| 2 | No GPU / no audio / no real devices in sandbox | Perf budgets, audio quality, touch feel, real ads must be validated by a human on real hardware (expected — see §47) | Later phases: manual test runs per `docs/HUMAN_TASKS.md`. Not urgent now. |

## 6. Command cheat-sheet (used in every phase report)

```bash
# (once per fresh sandbox) restore the toolchain
bash tools/setup_env.sh

# headless run of the game (exit immediately after load)
godot --headless --path . --quit

# automated test suite (from Phase 1 onward)
godot --headless --path . --script res://tests/run_tests.gd

# rendered run + manual verification under a virtual framebuffer
xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720

# import-check / script-parse check (fast CI-style gate)
godot --headless --path . --import
```

# TESTING.md — CoilClash (Snake Arena)

What is auto-tested, how to run it, what is manual, and the results log.
Updated at the end of every phase. **A build that fails tests is not "done" (§9A).**

## 1. Automated tests

Framework: hand-rolled headless runner (master prompt §9A explicitly allows
this instead of GUT; decision #13 — zero external dependencies).

```bash
godot --headless --path . --script res://tests/run_tests.gd
```

* Exit code `0` = green, `1` = at least one failure.
* Discovery: any `tests/test_*.gd`; methods named `test_*()` returning `true` pass.
* Autoloads ARE loaded during test runs (project settings), so tests may
  exercise GameManager/EventBus etc. — but they must not depend on rendering.

### Current coverage

| Test file | Covers |
|---|---|
| `test_spatial_hash.gd` | insert/query, distance filtering, no false negatives AND no false positives vs brute force (randomized), cell boundaries, negative coords, removal, moves, dense cells, clear (§9A.1) |
| `test_config.gd` | all `.tres` load; spec starting values for balance/snake/collectibles/power-ups/personalities/ad placements; GameManager state machine transitions |
| `test_util.gd` | Smoothing convergence + frame-rate independence + half-life math; ObjectPool prewarm/acquire/release/refusal |

Coverage will grow per §9A (body-following, eat-rule matrix, growth math,
spawn validity, save/load, ad state machine, leaderboard sort) as those
systems land in their phases.

## 2. Manual / harness checks (run every phase)

```bash
# Headless smoke: boot the game, expect "BOOT_DONE" + "CC_SMOKE_OK" and exit 0
CC_SMOKE_TEST=1 godot --headless --path .

# Rendered check under virtual framebuffer (no GPU in sandbox → llvmpipe):
# expect "CC_SCREENSHOT_OK" and a non-blank 1280x720 PNG
xvfb-run -a -s "-screen 0 1280x720x24" \
  env CC_SCREENSHOT=/tmp/cc.png godot --path . --resolution 1280x720
# then verify the PNG has varied content (blank-frame detector: tools/check_png.py)
```

## 3. Manual tests only a human can do (see docs/HUMAN_TASKS.md Part C)

Everything requiring real hardware: 60 FPS budgets on mid-range phones
(§19), touch feel, gamepad feel, audio quality, real ad rendering, browser
WebGL builds.

## 4. Results log

| Date | Phase | Automated | Smoke | Rendered | Notes |
|---|---|---|---|---|---|
| 2026-08-31 | 1 — Skeleton | 25 passed / 0 failed (exit 0, no leaks) | PASS (`CC_SMOKE_OK arena_loaded=true state=PLAYING`) | PASS (ground uniformly lit in all pixel regions; wall/ring/marker visible; verified via `tools/check_png.py`) | Fixed a hand-serialized `.tscn` transform bug (sun pointed up — ground unlit). See decision #15. |
| 2026-09-01 | 2 — Snake Body, Movement, Camera | 47 passed / 0 failed (exit 0) | PASS (`CC_SMOKE_OK arena_loaded=true player_loaded=true segs=6 state=PLAYING`) | PASS (snake trail visible in frame — 799 amber pixels tracing the boost path; head projected on-screen at (640, 385); `tools/check_png.py` real-render verdict) | Live exit-criteria harness (`scenes/boot/verify.tscn`) → `CC_VERIFY_PASS moved=68.7 power=8.8 speed=9.08 segs=8`, exit 0. Caught + fixed: MultiMesh buffer must be 16 floats/instance (#17), camera yaw 180° convention bridge (#18), head mesh added (#22). |

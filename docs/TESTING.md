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
| 2026-09-01 | 2 — Snake Body, Movement, Camera | 47 passed / 0 failed (exit 0) | PASS (`CC_SMOKE_OK arena_loaded=true player_loaded=true segs=6 state=PLAYING`) | PASS (60-segment snake visible — 6130 body pixels; head on-screen at (640, 374); `tools/check_png.py` real-render verdict) | Live exit-criteria harness (`scenes/boot/verify.tscn`) → `CC_VERIFY_PASS moved=88.4 power=190.0 speed=7.92 segs=60 path_3s=27.6 max_frame_ms=16.7 avg_frame_ms=16.7`, exit 0 — the §48 criterion "drive a 60-segment snake at 60 FPS" verified with both scenarios (small: steer/boost/drain/shrink; big: grow to 60, weave, path-length + frame budget). Caught + fixed: MultiMesh 16-float buffer (#17), camera yaw 180° bridge (#18), head mesh (#22), per-tick buffer upload churn (#24). |
| 2026-09-01 | 3 — Economy | 56 passed / 0 failed (exit 0) | PASS (`CC_SMOKE_OK … state=PLAYING`) | PASS (arena visibly populated: 269 cyan / 125 green / 3 amber / 2 mote-white pixels — matches §3.3 weights; rare shards correctly absent before 60 s; `tools/check_png.py` real-render verdict) | Live harness scenario C → `CC_VERIFY_PICKUP power=198 score=306 combo=1 alive=420` + `CC_VERIFY_PHASE3_PASS collectibles=420 motes=2`, `CC_VERIFY_PASS … max_frame_ms=16.7 avg_frame_ms=16.7` exit 0, 3/3 consecutive runs. Caught + fixed: boost motes spawned exactly ON the collect radius at high power (~50% instant re-collection — boost would be free; #32). Surge + claim + 1000-attempt spawn validity + combo table unit-tested. |
| 2026-09-01 | 4 — Ad scaffolding | 69 passed / 0 failed (exit 0) — incl. §9A.7: every mock outcome (completed/skipped/no-fill/error/crash/**watchdog timeout**/busy/focus-out) asserting unpause + input/audio restore + reward rules; all 10 §45.4 pacer gates; null-provider playability | PASS (`CC_SMOKE_OK` with BOTH `AdProviderMock` and `CC_AD_PROVIDER=null` — the §45.1 "playable with AdProviderNull" check) | PASS (debug ad panel visible in frame; `tools/check_png.py` real-render verdict) | Live harness scenario D → mock rewarded ad triggered from the debug panel: contract engaged (tree paused + audio ducked −80 dB + input suspended + opaque overlay) → reward granted → full restore; **forced timeout**: hung provider un-stuck by the watchdog (TIMEOUT, restored). `CC_VERIFY_PHASE4_PASS rewarded=true timeout=true contract=true`, exit 0, **3/3 consecutive runs**, `max_frame_ms=16.7`. |
| 2026-09-01 | 5 — Opponents | 80 passed / 0 failed (exit 0) — §8.3 personality table, context steering (interest + danger repulsion), §8.2 FSM priority chain (8 states, table-driven), stale snapshots (§8.4), aim-error bound + blunder hold, staggered ticks + §8.5 LOD + **same-interface guarantee** (live), name uniqueness, AI spawn validity ×1000 | PASS (`CC_SMOKE_OK`) | PASS (8 AI in frame, `tools/check_png.py` real-render verdict) | Live harness scenario E → `CC_VERIFY_AI_SPAWNED count=8` (8 unique names), `CC_VERIFY_AI_WINDOW` (6 FSM states seen, AI powers grew past start spread), `CC_VERIFY_PHASE5_PASS ai_ms_max=0.88–1.14 vs 2.50 budget` — exit 0, **3/3 consecutive runs**, `max_frame_ms=16.7`. Caught + fixed live: §8.5 budget blown 3.26–3.78 ms → cursor-free trail probe (#39), top-k cluster/mote queries (#41), typed-array insert error trap (#42), decision budget scheduler (#40). |

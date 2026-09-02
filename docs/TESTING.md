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
| 2026-09-01 | 6 — Conflict | 86 passed / 0 failed (exit 0) — §9 matrix table-driven (head-body both ways incl. the exact 1.10 boundary, head-head all 3 cases), absorb/corpse-mote/rank-bonus math, rim-light classification, shrink curve, hit-stop math | PASS (`CC_SMOKE_OK`) | PASS (death site + motes in frame, `tools/check_png.py` real-render verdict) | Live harness scenario F → `CC_VERIFY_KILL` (player 100 → AI victim; rim green readable pre-kill), `CC_VERIFY_PHASE6_KILL ok power+3.05 score+272 motes hit_stop=true` (absorb 0.62× + 250+floor(4×power) landed; corpse motes staggered; hit-stop dipped time_scale), `CC_VERIFY_RESPAWN ok count=8` (§11 2.5 s), `CC_VERIFY_PLAYER_DIED state=DYING` → GAME_OVER + input suspended, `CC_VERIFY_PHASE6_PASS killed=true died=true` — exit 0, **3/3 consecutive runs**. Caught + fixed live: float-boundary at 1.10× (#45), time-scaled ad watchdog after hit-stop (#46), harness god-mode for early scenarios (#47), mote-drop verify race with the 0.55 s dissolve. |
| 2026-09-01 | 7 — Verbs | 95 passed / 0 failed (exit 0) — §10 inventory table (durations/weights/params), cap-3 + refresh rules, surge stat multipliers + aura attachment, bloom instant, aegis consume-once, doubler consult, chill slows OTHERS only, magnet pull math, powerup spawn validity ×1000 | PASS (`CC_SMOKE_OK`) | PASS (power-ups + auras in frame) | Live harness scenario G → SURGE picked up under the head (speed mult 1.35 verified live), cap 3/3 + refresh (remaining time grows), aegis consumed once, doubler 2.0× — `CC_VERIFY_PHASE7_PASS`, exit 0, **3/3 consecutive runs** (then scenario F2 death still passes). AI use the same power-up path (#49). |
| 2026-09-02 | 7 — hardening (wall-freeze + harness determinism) | **100 passed / 0 failed** (exit 0) — adds `test_wall_slide.gd` ×5: slow-curve floor, slide-not-freeze at the wall, hard-stop + slide, inward recovery, soft-zone inward push | PASS (`CC_SMOKE_OK`) | PASS (real-render verdict) | Fresh-agent recon found the live harness **flaky (failed 2-of-3)** at the Phase 5 AI window: an AI "travelled 0.0 units for 6 s". Root cause #51: `_soft_zone_factor` returned 0.0 at `r >= arena_radius` → wall-pinned snakes froze alive forever (pre-existing since Phase 2). Fixed (floor at 0.85 + §3.5 inward push #52); a second flake (harness-only, #53: stray AEGIS evicted by the harness's own SURGE re-apply) fixed via `clear_effects`. **Full harness now 6/6 consecutive PASS** (was 1/3), `ai_ms_max 0.83–1.10 vs 2.50 budget`, `max_frame_ms 16.7`. Known minor: 6 ObjectDB instances leak at suite exit (investigate in Phase 12). |
| 2026-09-02 | 8 — Interface | **108 passed / 0 failed** (exit 0) — adds leaderboard sort stability + build-rows + player rank (§9A.8), settings.cfg round-trip, §7 scheme tests (keyboard/mouse dead-zone/touch joystick math/suspend), context-steering origin regression (#62) | PASS (mock AND `CC_AD_PROVIDER=null`) | PASS (menu, HUD landscape+portrait, pause, game-over, revived; all screens pixel-verified varied + HUD regions sampled: score/board/power-pill/boost-ring present in both orientations) | NEW UI harness (`CC_UI_VERIFY=1`, decision #59): fresh install → straight into run (§13.4) + FTUE hints + ZERO ads before first run; HUD tracks score (10 Hz) + leaderboard + power pill; **mouse steering verified live (Δ≈98.5° turn toward the raycast point)**; **touchscreen navigation verified end-to-end** (`CC_UI_TOUCH_TAP`: HOW TO PLAY opened + closed by emulated-finger taps; `CC_UI_TOUCH_STEER`: dynamic joystick planted by real `InputEventScreenTouch`, drag steers +X, snake turns Δ57–248°, release clears — decision #63); pause/resume via real P-key + button clicks; death → §12.2 panel (count-ups, PLAY AGAIN never disabled, REVIVE visible only when available) → **mock rewarded revive resumes at 65 % power** → REVIVE hidden after single use → MAIN MENU → PLAY → run 3 with INTER_RUN interstitial — **5/5 consecutive passes** + portrait pass. Bugs caught + fixed live: §3.6 free-growth window never enforced (#61), ContextSteering dangers world-origin-relative (#62), PlayerController never passed the head position to the §7 dead zone (#60). |

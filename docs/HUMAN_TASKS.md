# HUMAN_TASKS.md — CoilClash (Snake Arena)

The human/AI division of labour (§47). Kept current every phase. Reproduced
in the final report (§49.11).

---

## PART A — What the AI completed and verified

### Phase 0 — Recon
| Item | Files | Verified by | Human one-step check |
|---|---|---|---|
| Environment recon + Godot 4.7.2 install | `docs/ENVIRONMENT.md`, `tools/setup_env.sh` | `godot --version` → 4.7.2.stable; headless launch of an empty project ran 60 frames and exited 0 | run `bash tools/setup_env.sh && godot --version` |

### Phase 1 — Skeleton
| Item | Files | Verified by | Human one-step check |
|---|---|---|---|
| Folder tree, project settings, Input Map | §21 tree, `project.godot` | Input actions verified at runtime via test script | open `project.godot` in the editor; Input Map tab shows all §7 actions |
| 11 autoload stubs in §22 order | `scripts/autoload/*.gd` | Boot smoke test (`CC_SMOKE_TEST=1`) prints state transitions and exits 0 | `CC_SMOKE_TEST=1 godot --headless --path .` |
| Config resource classes + .tres | `scripts/config/*.gd`, `resources/config/*.tres`, `resources/ai/*.tres` | `test_config.gd` green | `godot --headless --path . --script res://tests/run_tests.gd` |
| SpatialHash + tests | `scripts/systems/spatial_hash.gd`, `tests/test_spatial_hash.gd` | 9 tests green incl. randomized brute-force cross-check | same test command |
| ObjectPool, Smoothing, MathUtil | `scripts/util/*.gd`, `tests/test_util.gd` | 6 tests green | same test command |
| Arena scene (ground/boundary/soft ring/lighting) | `scenes/arena/*`, `scenes/boot/*` | rendered screenshot under Xvfb (non-blank, pixel-verified) | `xvfb-run -a -s "-screen 0 1280x720x24" env CC_SCREENSHOT=/tmp/cc.png godot --path . --resolution 1280x720` |
| Docs: ENVIRONMENT, TESTING, DEVIATIONS, DECISION_LOG, CREDITS | `docs/*.md`, `assets/CREDITS.md` | files committed & pushed | read them |

### Phases 2–7 (previous agent's verified work, re-verified 2026-09-02 by the current agent)
| Item | Files | Verified by | Human one-step check |
|---|---|---|---|
| Snake body/movement/camera, economy, ad scaffolding, AI opponents, conflict, verbs (Phases 2–7) | `scripts/`, `scenes/`, `tests/` (per-phase details in `docs/TESTING.md` results log) | Full suite re-run **100/100 green** and the live verify harness re-run **6/6 PASS** on 2026-09-02 (after the wall-freeze fix below) | `godot --headless --path . --script res://tests/run_tests.gd` |
| Wall-freeze fix: §3.5 slide restored (factor floored at 0.85 at the wall, never 0.0) + soft-zone inward push (`soft_zone_push_strength`) | `scripts/snake/snake_controller.gd`, `scripts/config/game_balance_config.gd`, `resources/config/game_balance.tres`, decisions #51/#52 | 5 new regression tests (`tests/test_wall_slide.gd`) green; harness AI-window flake (was failing 2-of-3 runs: "AI travelled 0.0 units for 6 s") gone — 6/6 consecutive full-harness passes | same test command, then `xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720 res://scenes/boot/verify.tscn` (expect `CC_VERIFY_PASS`, exit 0) |
| Verify-harness Phase 7 determinism: `PowerUpManager.clear_effects()` test aid + chill-tolerant SURGE check (harness-only fix, decision #53) | `scripts/systems/powerup_manager.gd`, `scenes/boot/verify.gd` | Harness powerup scenario deterministic across 6/6 runs | same harness command |

---

## PART B — What the AI CANNOT do at all, and why

**Accounts, credentials, and contracts — I have no ability to create or hold these:**
1. Create a Google AdMob account, an app entry, and real ad unit IDs. *You must do this, then paste the IDs into `resources/config/ads.tres`.* Google's official test IDs ship as defaults.
2. Sign up with a web portal (Poki, CrazyGames, GameDistribution, Y8), get approved, and receive their SDK key / game ID. Portals review games manually — requires a human submission.
3. Create a Google Play Developer account ($25 one-time), an Apple Developer account ($99/yr), and complete identity verification.
4. Set up AdMob payment details, tax forms (W-8BEN / W-9 or the ZA equivalent), and a bank account for payouts.
5. Set up ad mediation (AppLovin MAX, ironSource, AdMob mediation waterfalls) — multiple network accounts and dashboard configuration.
6. Register a company/sole-proprietorship if required for payouts in your jurisdiction (ZA: SARS tax number for the tax interview).

**Legal and policy — I must not author these as binding documents:**
7. Write and **host** a real Privacy Policy and Terms of Service at public URLs. I can draft template text; a human (ideally with legal review) must approve, adapt to your jurisdiction, and host it. Put the URLs in `ads.tres`.
8. Complete the Google Play Data Safety form and the Apple App Privacy nutrition labels — legal declarations made by the account holder.
9. Decide and declare the target age rating (IARC questionnaire), COPPA status, and family-policy compliance.
10. Verify ad-network policy compliance for your specific placements before launch (policies change; a human must read the current version).

**Hardware and device reality:**
11. Test on real physical devices (low-end Android, mid-range Android, iPhone, Safari on iOS, Chrome on Android). I cannot run Godot mobile export templates on real hardware or measure real thermal/battery behaviour.
12. Verify real ad rendering, real fill rates, real latency, and real eCPM. Mock/test ads behave differently from live inventory.
13. Test on real network conditions (3G, flaky Wi-Fi) and confirm the ad watchdog behaves correctly.
14. Confirm the game passes Google Play's pre-launch report and Apple's review.

**Subjective and creative judgement:**
15. Decide whether the game is *fun*. Playtest with at least 5 people who have never seen it.
16. Final balance tuning based on that playtesting. Every number is exposed in `.tres` files so you can do this without code changes.
17. Final art direction, character/skin design, logo, icon, and store screenshots. My placeholders are procedural and functional, not beautiful.
18. Final music and sound design. Commissioned or licensed audio requires a human purchase and licence agreement.
19. Choose the final game name and check it for trademark conflicts.
20. Marketing: store listing copy, ASO keywords, trailer, social presence, influencer outreach, paid UA.

**Infrastructure I can code against but cannot provision:**
21. Online leaderboard backend (Silent Wolf / PlayFab / Nakama / custom). `ILeaderboardBackend` will be a one-file swap; account/server/keys are yours.
22. Analytics backend (GameAnalytics / Firebase) — needs an account and an API key. `Analytics` autoload is ready for a backend.
23. Remote config hosting — `RemoteConfig` reads a JSON endpoint you provide.
24. Web hosting with correct COOP/COEP headers for a multithreaded web export.
25. Multiplayer servers, if you ever go real-time online.

**Things I deliberately did not do (scope control), which a human should schedule:**
26. In-app purchases (a "Remove Ads" product). The `no_ads_purchased` flag will be built and honoured throughout `AdPacer`, but the IAP plugin, store product setup, and receipt validation are human tasks.
27. Localisation. All user-facing strings will be routed through a strings file so translation is a drop-in — but translation quality needs humans.
28. Cloud save / account system.

---

## PART C — What the AI built but could NOT fully verify

| What | Untested aspect | Risk | How the human should test |
|---|---|---|---|
| Rendered arena visuals | Correctness verified via software-rendered (llvmpipe) screenshots only; no GPU | Low | Open the project in the Godot editor on a real GPU; the circular arena with cyan boundary wall and red outer ring should render at 60 FPS |
| Input Map events | Actions verified to exist with correct keycodes; physical feel untested | Low | Launch, press WASD/arrows/Space/F3 — steering vector and boost signals fire (debug printouts until Phase 2) |

*(This table grows every phase. Everything listed in Part B is also, by definition, unverifiable by me.)*

---

## PART D — Prioritized roadmap from here to commercial

Phase-by-phase build order is fixed by master prompt §48; this is the
shippability overlay on top of it.

| Task | Why | Effort | Who | Depends on |
|---|---|---|---|---|
| Phases 2–3: snake feel + economy | Core loop must be fun first (§50.1) | L | AI | — |
| Phase 4: ad scaffolding | Ad layer must be first-class from early | M | AI | — |
| Phases 5–8: AI, combat, verbs, interface | Complete playable loop | L | AI | — |
| Phase 9–10: meta + feel | Retention mechanics + polish | L | AI | — |
| Phase 11: web export + monetization wiring | Primary revenue surface | M | AI + Human (portal keys) | — |
| Phase 12–13: harden + report | Shippable confidence | M | AI | — |
| **After Phase 13** | | | | |
| Portal submission (Poki/CrazyGames/GameDistribution) | First revenue | S | Human | Phase 11 |
| Playtesting round (≥5 fresh players) | Fun check (§47.15) | S | Human | Phase 10 |
| Balance pass from playtest data | Retention | S | Human | playtest |
| Real ad accounts + IDs | First cent of revenue | M | Human | Phase 11 |
| Google Play listing + store submission | Android revenue | L | Human | portal validation |
| 60 FPS device matrix validation | Budgets (§19) | M | Human | Phase 12 |

*Week grouping (from commercial, after the phase plan completes): Week 1 =
playtest + balance; Weeks 2–3 = portal submission + ad IDs + Play store;
Week 4 = soft launch + measure; Months 2–3 = scale (marketing, mediation,
iOS).*

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

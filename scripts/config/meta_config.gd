class_name MetaConfig
extends Resource
## §16 meta economy tuning (starting values — tune in Phase 10 §39).
##
## Owns: the coin/XP/mission/skin economy NUMBERS only. No state, no I/O.
## Talks to: boot (payout), MissionManager (defs/rewards), SkinManager
##           (nothing — skins carry their own prices in SkinDef).

## §16: 1 coin per N score.
@export var coins_per_score: float = 120.0
## §16: flat bonus for finishing top 3.
@export var top3_coin_bonus: int = 25
## §16: XP = score / N.
@export var xp_per_score: float = 10.0
## §16: xp_needed(level) = level_coef * level^level_exp.
@export var level_coef: float = 220.0
@export var level_exp: float = 1.35
## Coin bonus granted on each level-up (retention hook, §16 "levels ...
## give coin bonuses").
@export var level_up_coin_bonus: int = 50
## Daily mission count (§16: 3 per day).
@export var daily_mission_count: int = 3
## Max high-score entries persisted (§17: top 20).
@export var high_score_cap: int = 20


## Cumulative XP needed to REACH `level` (from start). Level 1 = 0 XP.
static func xp_needed_cumulative(cfg: MetaConfig, level: int) -> int:
	if level <= 1:
		return 0
	var total: float = 0.0
	for l in range(1, level):
		total += cfg.level_coef * pow(float(l), cfg.level_exp)
	return int(round(total))


## Level reached with `xp` total XP (>= 1).
static func level_for_xp(cfg: MetaConfig, xp: int) -> int:
	var level: int = 1
	while xp >= xp_needed_cumulative(cfg, level + 1):
		level += 1
		if level > 999:
			break
	return level

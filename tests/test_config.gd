extends RefCounted
## §9A.3/4 + Phase-1 skeleton checks — every config .tres loads, and the
## spec's starting numbers are present (they are the contract until Phase 10
## tuning deliberately changes them, which must then update these tests).


func test_all_config_resources_load() -> bool:
	var paths: Array[String] = [
		"res://resources/config/game_balance.tres",
		"res://resources/config/snake_player.tres",
		"res://resources/config/snake_ai.tres",
		"res://resources/config/collectibles.tres",
		"res://resources/config/powerups.tres",
		"res://resources/config/ads.tres",
		"res://resources/ai/ai_collector.tres",
		"res://resources/ai/ai_aggressive.tres",
		"res://resources/ai/ai_defensive.tres",
		"res://resources/ai/ai_explorer.tres",
		"res://resources/ai/ai_opportunist.tres",
	]
	for path in paths:
		if not ResourceLoader.exists(path):
			printerr("  missing: %s" % path)
			return false
		var res: Resource = load(path)
		if res == null:
			printerr("  failed to load: %s" % path)
			return false
	return true


func test_game_balance_matches_spec() -> bool:
	var b: GameBalanceConfig = load("res://resources/config/game_balance.tres")
	var checks: Array = [
		b.arena_radius == 120.0,
		b.soft_zone_width == 8.0,
		b.soft_zone_slow_multiplier == 0.85,
		b.shrink_start_time == 180.0,
		b.shrink_floor_radius == 70.0,
		b.surge_interval == 45.0,
		b.surge_collectible_count == 40,
		b.target_collectible_count == 420,
		b.refill_rate_per_second == 18.0,
		b.max_rare_alive == 6,
		b.ai_count == 8,
		b.ai_respawn_delay == 2.5,
		b.min_spawn_distance_from_player == 22.0,
		b.collectible_min_spawn_distance == 6.0,
	]
	if checks.has(false):
		printerr("  game_balance.tres diverges from §3.5/§3.6/§11")
		return false
	return b.shrink_floor_radius < b.arena_radius and b.max_rare_alive <= b.target_collectible_count


func test_snake_config_matches_spec() -> bool:
	var s: SnakeConfig = load("res://resources/config/snake_player.tres")
	var checks: Array = [
		s.base_move_speed == 11.0,
		s.min_move_speed == 7.6,
		s.boost_multiplier == 1.85,
		s.boost_turn_penalty == 0.72,
		s.boost_power_drain == 2.2,
		s.min_boost_power == 4.0,
		s.boost_mote_emission_rate == 4.0,
		s.base_turn_rate == 280.0,
		s.head_radius == 0.55,
		s.radius_power_exponent == 0.19,
		s.segment_spacing_radius_factor == 0.62,
		s.start_segment_count == 6,
		s.max_segment_count == 240,
		s.start_power == 2.0,
		s.segments_per_power == 3.5,
		s.min_turn_radius_factor == 1.15,
		s.self_collision_enabled == false,
		s.history_sample_distance == 0.10,
		s.max_history_points == 4096,
		s.eat_power_ratio == 1.10,
		s.absorbed_power_fraction == 0.62,
		s.dropped_mass_fraction == 0.72,
		s.corpse_mote_decay_time == 14.0,
		s.boost_mode == SnakeConfig.BoostMode.DRAIN,
	]
	if checks.has(false):
		printerr("  snake_player.tres diverges from §3.1/§3.2/§3.4")
		return false
	return s.min_move_speed <= s.base_move_speed


func test_collectible_table_matches_spec() -> bool:
	var t: CollectibleTable = load("res://resources/config/collectibles.tres")
	if t.entries.size() != 5:
		printerr("  expected 5 entries, got %d" % t.entries.size())
		return false
	var small: CollectibleDef = t.get_def(CollectibleDef.Type.CELL_SMALL)
	var med: CollectibleDef = t.get_def(CollectibleDef.Type.CELL_MEDIUM)
	var large: CollectibleDef = t.get_def(CollectibleDef.Type.CELL_LARGE)
	var rare: CollectibleDef = t.get_def(CollectibleDef.Type.SHARD_RARE)
	var mote: CollectibleDef = t.get_def(CollectibleDef.Type.CORPSE_MOTE)
	if small == null or med == null or large == null or rare == null or mote == null:
		printerr("  missing archetype")
		return false
	var table_ok: bool = (
		small.power == 1.0 and small.score == 10 and small.spawn_weight == 70.0
		and med.power == 3.0 and med.score == 35 and med.spawn_weight == 20.0
		and large.power == 8.0 and large.score == 100 and large.spawn_weight == 7.0
		and rare.power == 22.0 and rare.score == 400 and rare.spawn_weight == 3.0
		and mote.spawn_weight == 0.0 and mote.decay_time == 14.0
	)
	if not table_ok:
		printerr("  values diverge from §3.3 table")
		return false
	# Weights sum to 100 (70 + 20 + 7 + 3).
	return is_equal_approx(t.total_weight(), 100.0)


func test_powerup_table_matches_spec() -> bool:
	var t: PowerUpTableConfig = load("res://resources/config/powerups.tres")
	if t.powerups.size() != 6:
		printerr("  expected 6 power-ups, got %d" % t.powerups.size())
		return false
	var surge: PowerUpDef = t.get_def(PowerUpDef.Effect.SURGE)
	var magnet: PowerUpDef = t.get_def(PowerUpDef.Effect.MAGNET)
	var aegis: PowerUpDef = t.get_def(PowerUpDef.Effect.AEGIS)
	var bloom: PowerUpDef = t.get_def(PowerUpDef.Effect.BLOOM)
	var doubler: PowerUpDef = t.get_def(PowerUpDef.Effect.DOUBLER)
	var chill: PowerUpDef = t.get_def(PowerUpDef.Effect.CHILL)
	if surge == null or magnet == null or aegis == null or bloom == null or doubler == null or chill == null:
		printerr("  missing power-up archetype")
		return false
	var ok: bool = (
		surge.duration == 6.0 and surge.surge_speed_mult == 1.35 and surge.surge_turn_mult == 1.15
		and magnet.duration == 8.0 and magnet.magnet_radius == 9.0 and magnet.magnet_pull_speed == 14.0
		and aegis.duration == 12.0
		and bloom.duration == 0.0 and bloom.bloom_power == 18.0
		and doubler.duration == 10.0 and doubler.doubler_mult == 2.0
		and chill.duration == 7.0 and chill.chill_radius == 16.0 and chill.chill_speed_mult == 0.7
	)
	if not ok:
		printerr("  values diverge from §10 table")
		return false
	var total: int = 0
	for p in t.powerups:
		total += p.weight
	return total == 100


func test_personalities_match_spec() -> bool:
	var table: Dictionary = {
		"res://resources/ai/ai_collector.tres": [14.0, 34.0, 1.0, 0.10, 0.15, 0.30],
		"res://resources/ai/ai_aggressive.tres": [42.0, 18.0, 0.4, 0.55, 0.75, 0.18],
		"res://resources/ai/ai_defensive.tres": [8.0, 46.0, 0.7, 0.05, 0.40, 0.22],
		"res://resources/ai/ai_explorer.tres": [20.0, 30.0, 0.6, 0.20, 0.30, 0.28],
		"res://resources/ai/ai_opportunist.tres": [30.0, 30.0, 0.8, 0.70, 0.55, 0.20],
	}
	for path in table:
		var p: AIPersonalityConfig = load(path)
		var expected: Array = table[path]
		if p.aggro_radius != expected[0] or p.fear_radius != expected[1] \
				or p.greed != expected[2] or p.cutoff_skill != expected[3] \
				or p.boost_willingness != expected[4] or p.reaction_delay != expected[5]:
			printerr("  %s diverges from §8.3 table" % path)
			return false
		if p.sense_radius != 55.0 or p.collectible_sense_radius != 28.0 or p.blunder_chance != 0.04:
			printerr("  %s diverges from §8.4" % path)
			return false
	return true


func test_ad_config_placements_complete() -> bool:
	var a: AdConfig = load("res://resources/config/ads.tres")
	if a.placements.size() != 9:
		printerr("  expected 9 placements (§45.3), got %d" % a.placements.size())
		return false
	var inter_run: AdPlacementDef = a.get_placement(AdPlacementId.ID.INTER_RUN)
	var revive: AdPlacementDef = a.get_placement(AdPlacementId.ID.REVIVE)
	var app_open: AdPlacementDef = a.get_placement(AdPlacementId.ID.APP_OPEN)
	var banner: AdPlacementDef = a.get_placement(AdPlacementId.ID.BANNER_MENU)
	if inter_run == null or revive == null or app_open == null or banner == null:
		printerr("  missing placement row")
		return false
	var ok: bool = (
		inter_run.min_run_index == 3 and inter_run.min_gap_seconds == 120.0
		and inter_run.type == AdPlacementDef.AdType.INTERSTITIAL
		and revive.type == AdPlacementDef.AdType.REWARDED
		and not revive.grant_on_no_fill
		and app_open.min_run_index == 2 and app_open.min_gap_seconds == 14400.0
		and banner.type == AdPlacementDef.AdType.BANNER
	)
	if not ok:
		printerr("  placement caps diverge from §45.3 table")
		return false
	# Google official demo ids ship as defaults; real ids are a HUMAN task.
	return a.app_id.begins_with("ca-app-pub-3940256099942544")


func test_game_manager_state_machine() -> bool:
	# Autoload is present in --script runs. Drive a valid flow.
	# State-agnostic entry: other suites may leave any state behind, so
	# first reach a state that can transition to LOADING.
	match GameManager.current_state:
		GameManager.State.PLAYING:
			if not GameManager.request_state(GameManager.State.GAME_OVER):
				printerr("  PLAYING -> GAME_OVER refused")
				return false
		GameManager.State.PAUSED:
			if not GameManager.request_state(GameManager.State.GAME_OVER):
				printerr("  PAUSED -> GAME_OVER refused")
				return false
		GameManager.State.PAUSED_FOR_AD:
			if not GameManager.request_state(GameManager.State.PLAYING):
				printerr("  PAUSED_FOR_AD -> PLAYING refused")
				return false
			if not GameManager.request_state(GameManager.State.GAME_OVER):
				printerr("  PLAYING -> GAME_OVER refused")
				return false
		GameManager.State.DYING:
			if not GameManager.request_state(GameManager.State.GAME_OVER):
				printerr("  DYING -> GAME_OVER refused")
				return false
	if not GameManager.request_state(GameManager.State.LOADING):
		printerr("  -> LOADING refused (from %s)" % GameManager.state_name())
		return false
	if not GameManager.request_state(GameManager.State.PLAYING):
		printerr("  LOADING -> PLAYING refused")
		return false
	if not GameManager.request_state(GameManager.State.PAUSED):
		printerr("  PLAYING -> PAUSED refused")
		return false
	if GameManager.request_state(GameManager.State.BOOT):
		printerr("  PAUSED -> BOOT should be invalid but was accepted")
		return false
	if not GameManager.request_state(GameManager.State.PLAYING):
		printerr("  PAUSED -> PLAYING refused")
		return false
	# §45.6 ad-contract transitions (added in Phase 4): PLAYING ->
	# PAUSED_FOR_AD -> PLAYING, and GAME_OVER -> PAUSED_FOR_AD (revive ad).
	if not GameManager.request_state(GameManager.State.PAUSED_FOR_AD):
		printerr("  PLAYING -> PAUSED_FOR_AD refused")
		return false
	if not GameManager.request_state(GameManager.State.PLAYING):
		printerr("  PAUSED_FOR_AD -> PLAYING refused")
		return false
	if not GameManager.request_state(GameManager.State.GAME_OVER):
		printerr("  PLAYING -> GAME_OVER refused")
		return false
	if not GameManager.request_state(GameManager.State.PAUSED_FOR_AD):
		printerr("  GAME_OVER -> PAUSED_FOR_AD refused (revive ad path)")
		return false
	return GameManager.request_state(GameManager.State.GAME_OVER)

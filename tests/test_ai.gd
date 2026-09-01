extends RefCounted
## §8/§9A tests for the AI layer: the §8.3 personality table, context
## steering, the §8.2 FSM priority chain, stale snapshots (§8.4), aim
## error + blunder, staggered 10 Hz decisions, the §8.5 LOD rules, name
## uniqueness, AI spawn validity, and the §8.1 same-interface guarantee.

const SnakeControllerClass = preload("res://scripts/snake/snake_controller.gd")
const AI_SCENE = preload("res://scenes/ai/ai_snake.tscn")
const ArenaScene = preload("res://scenes/arena/arena.tscn")

const BALANCE: GameBalanceConfig = preload("res://resources/config/game_balance.tres")


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _to_playing() -> void:
	var gm: GameManager = _tree().root.get_node("GameManager")
	if gm.current_state == GameManager.State.PLAYING:
		return
	if gm.current_state == GameManager.State.BOOT:
		gm.request_state(GameManager.State.LOADING)
	if gm.current_state == GameManager.State.LOADING or gm.current_state == GameManager.State.GAME_OVER \
			or gm.current_state == GameManager.State.PAUSED:
		gm.request_state(GameManager.State.LOADING)
		gm.request_state(GameManager.State.PLAYING)


func _ctx(overrides: Dictionary = {}) -> Dictionary:
	var ctx: Dictionary = {
		"me_pos": Vector3.ZERO,
		"me_facing": Vector3.FORWARD,
		"me_speed": 10.0,
		"me_power": 10.0,
		"me_radius": 0.55,
		"peak_power": 10.0,
		"snakes": [],
		"threats": [],
		"prey": [],
		"clusters": [],
		"motes": [],
		"wall": {"center_dist": 0.0, "soft_inner": 112.0, "radius": 120.0, "inside_soft": false, "predicted_out": false},
		"body_hit": [],
		"rng": RandomNumberGenerator.new(),
		"personality": load("res://resources/ai/ai_collector.tres").duplicate(true),
		"balance": BALANCE,
		"now": 0.0,
		"dt": 0.016,
		"waypoint": Vector3(30, 0, 30),
		"recover_active": false,
	}
	for k in overrides:
		ctx[k] = overrides[k]
	return ctx


# --- §8.3 personality table -------------------------------------------------

func test_personality_table_values() -> bool:
	var table: Array = [
		["ai_collector.tres", 14.0, 34.0, 1.0, 0.10, 0.15, 0.30],
		["ai_aggressive.tres", 42.0, 18.0, 0.4, 0.55, 0.75, 0.18],
		["ai_defensive.tres", 8.0, 46.0, 0.7, 0.05, 0.40, 0.22],
		["ai_explorer.tres", 20.0, 30.0, 0.6, 0.20, 0.30, 0.28],
		["ai_opportunist.tres", 30.0, 30.0, 0.8, 0.70, 0.55, 0.20],
	]
	for row in table:
		var p: AIPersonalityConfig = load("res://resources/ai/" + row[0])
		if absf(p.aggro_radius - row[1]) > 0.001 \
				or absf(p.fear_radius - row[2]) > 0.001 \
				or absf(p.greed - row[3]) > 0.001 \
				or absf(p.cutoff_skill - row[4]) > 0.001 \
				or absf(p.boost_willingness - row[5]) > 0.001 \
				or absf(p.reaction_delay - row[6]) > 0.001:
			printerr("  personality %s mismatch vs §8.3" % row[0])
			return false
	return true


# --- §8.2 Layer 2: context steering ----------------------------------------

func test_steering_follows_interest() -> bool:
	var cs: ContextSteering = ContextSteering.new()
	# Facing aligned with the interest: the winner must BE the interest
	# direction (16-way discretization includes it exactly).
	var heading: Vector3 = cs.pick(Vector3(1, 0, 0), [], Vector3(1, 0, 0))
	if heading.dot(Vector3(1, 0, 0)) < 0.999:
		printerr("  no-danger heading %s should be exactly +X" % heading)
		return false
	return true


func test_steering_avoids_danger() -> bool:
	var cs: ContextSteering = ContextSteering.new()
	var dangers: Array = [{"pos": Vector3(5, 0, 0), "radius": 10.0, "weight": 1.5}]
	var heading: Vector3 = cs.pick(Vector3(1, 0, 0), dangers, Vector3.FORWARD)
	# A danger directly ahead must turn the heading away from it.
	if heading.dot(Vector3(1, 0, 0)) > 0.0:
		printerr("  heading %s still points into the danger" % heading)
		return false
	return true


# --- §8.2 Layer 1: FSM priority chain --------------------------------------

func test_fsm_priority_chain() -> bool:
	var fsm: AIStateMachine = AIStateMachine.new()
	var checks: Array = []
	# Full danger stack → AVOID_WALL wins (highest priority).
	var wall_ctx: Dictionary = _ctx({"wall": {"center_dist": 115.0, "soft_inner": 112.0, "radius": 120.0, "inside_soft": true, "predicted_out": true}, "body_hit": [{"pos": Vector3(1, 0, 1), "radius": 3.0, "weight": 1.0}], "threats": [{"pos": Vector3(10, 0, 0), "power": 50.0, "facing": 0.0, "speed": 9.0, "radius": 0.6}], "prey": [{"pos": Vector3(8, 0, 0), "power": 3.0, "facing": 0.0, "speed": 9.0, "radius": 0.55}], "motes": [{"pos": Vector3(5, 0, 5), "power": 1.0}], "clusters": [{"pos": Vector3(3, 0, 3), "power": 1.0, "score": 10.0, "count": 1}]})
	checks.append(fsm.pick(wall_ctx).state_name == &"AVOID_WALL")
	# Wall clear, body hit present → AVOID_BODY.
	var body_ctx: Dictionary = _ctx({"body_hit": [{"pos": Vector3(1, 0, 1), "radius": 3.0, "weight": 1.0}], "threats": wall_ctx["threats"]})
	checks.append(fsm.pick(body_ctx).state_name == &"AVOID_BODY")
	# Threat within fear radius (personality collector: 34) → FLEE.
	var flee_ctx: Dictionary = _ctx({"threats": [{"pos": Vector3(10, 0, 0), "power": 50.0, "facing": 0.0, "speed": 9.0, "radius": 0.6}]})
	checks.append(fsm.pick(flee_ctx).state_name == &"FLEE")
	# Prey within aggro (collector: 14) → HUNT.
	var hunt_ctx: Dictionary = _ctx({"prey": [{"pos": Vector3(8, 0, 0), "power": 3.0, "facing": 0.0, "speed": 9.0, "radius": 0.55}]})
	checks.append(fsm.pick(hunt_ctx).state_name == &"HUNT")
	# Motes → SCAVENGE.
	var scav_ctx: Dictionary = _ctx({"motes": [{"pos": Vector3(5, 0, 5), "power": 1.0}]})
	checks.append(fsm.pick(scav_ctx).state_name == &"SCAVENGE")
	# Clusters → COLLECT.
	var collect_ctx: Dictionary = _ctx({"clusters": [{"pos": Vector3(3, 0, 3), "power": 1.0, "score": 10.0, "count": 1}]})
	checks.append(fsm.pick(collect_ctx).state_name == &"COLLECT")
	# Recover active → RECOVER.
	var recover_ctx: Dictionary = _ctx({"recover_active": true})
	checks.append(fsm.pick(recover_ctx).state_name == &"RECOVER")
	# Nothing → WANDER.
	checks.append(fsm.pick(_ctx()).state_name == &"WANDER")
	for i in checks.size():
		if not checks[i]:
			printerr("  priority chain step %d failed" % i)
			return false
	return true


# --- §8.4 humanizing --------------------------------------------------------

func test_stale_snapshot_reaction_delay() -> bool:
	var director: AIDirector = AIDirector.new()
	director.balance = BALANCE
	var ai: AIController = AIController.new()
	ai.director = director
	ai.personality = load("res://resources/ai/ai_collector.tres").duplicate(true)
	ai.personality.reaction_delay = 0.5
	# The snake must be IN the tree: global_position on an untethered node
	# errors and stays ZERO (engine guard, verified empirically).
	var snake: SnakeController = SnakeControllerClass.new()
	snake.config = load("res://resources/config/snake_ai.tres")
	_tree().root.add_child(snake)
	snake.alive = false
	snake.global_position = Vector3(10, 0, 0)
	snake.facing_angle_deg = 0.0
	snake.current_speed = 10.0
	snake.power = 5.0
	snake.current_radius = 0.55
	ai.snake = snake
	director._game_time = 0.0
	ai._sample_world()
	snake.global_position = Vector3(60, 0, 0)
	director._game_time = 1.0
	ai._sample_world()
	# At t=1.4 with 0.5 s staleness, the AI perceives the t=0 position.
	director._game_time = 1.4
	var ctx: Dictionary = ai._stale_context()
	var seen: Vector3 = ctx["me_pos"]
	if seen.distance_to(Vector3(10, 0, 0)) > 0.01:
		printerr("  stale snapshot position %s, expected the t=0 position" % seen)
		return false
	# With 0.2 s staleness it perceives the t=1.0 position.
	ai.personality.reaction_delay = 0.2
	var ctx2: Dictionary = ai._stale_context()
	if (ctx2["me_pos"] as Vector3).distance_to(Vector3(60, 0, 0)) > 0.01:
		printerr("  fresh snapshot position %s, expected the t=1 position" % ctx2["me_pos"])
		return false
	ai.free()
	director.free()
	snake.free()
	return true


func test_blunder_holds_bad_heading() -> bool:
	var director: AIDirector = AIDirector.new()
	director.balance = BALANCE
	var ai: AIController = AIController.new()
	ai.director = director
	ai.personality = load("res://resources/ai/ai_aggressive.tres").duplicate(true)
	ai.personality.blunder_chance = 1.0
	ai.personality.aim_error_deg = 0.0
	var heading: Vector3 = Vector3(1, 0, 0)
	ai._blunder_timer = 1.9
	var ctx: Dictionary = {"now": 0.0, "dt": 0.2}
	var first: Vector3 = ai._apply_humanizing(ctx, heading)
	if first.angle_to(heading) < deg_to_rad(50.0):
		printerr("  blunder heading barely differs (%.1f°)" % rad_to_deg(first.angle_to(heading)))
		return false
	# Still within the hold window → same bad heading.
	var second: Vector3 = ai._apply_humanizing({"now": 0.2, "dt": 0.016}, heading)
	if not second.is_equal_approx(first):
		printerr("  blunder heading changed mid-hold")
		return false
	# After the hold → back to normal (aim error 0 → the input heading).
	var third: Vector3 = ai._apply_humanizing({"now": 1.0, "dt": 0.016}, heading)
	if third.angle_to(heading) > deg_to_rad(1.0):
		printerr("  blunder never released (%.1f° off)" % rad_to_deg(third.angle_to(heading)))
		return false
	ai.free()
	director.free()
	return true


func test_aim_error_bounded() -> bool:
	var director: AIDirector = AIDirector.new()
	director.balance = BALANCE
	var ai: AIController = AIController.new()
	ai.director = director
	ai.personality = load("res://resources/ai/ai_collector.tres").duplicate(true)
	ai.personality.aim_error_deg = 6.0
	ai.personality.blunder_chance = 0.0
	var heading: Vector3 = Vector3(1, 0, 0)
	var max_deg: float = 0.0
	for i in 20:
		var out: Vector3 = ai._apply_humanizing({"now": 0.0, "dt": 0.5}, heading)
		max_deg = maxf(max_deg, rad_to_deg(out.angle_to(heading)))
	if max_deg > 6.5:
		printerr("  aim error %.1f° exceeds the %.1f° bound" % [max_deg, 6.0])
		return false
	ai.free()
	director.free()
	return true


func test_recover_trigger_and_state() -> bool:
	var director: AIDirector = AIDirector.new()
	director.balance = BALANCE
	var ai: AIController = AIController.new()
	ai.director = director
	ai.personality = load("res://resources/ai/ai_collector.tres").duplicate(true)
	var snake: SnakeController = SnakeControllerClass.new()
	snake.config = load("res://resources/config/snake_ai.tres")
	snake.power = 30.0
	ai.snake = snake
	ai._peak_power = 100.0
	ai._update_timers({"now": 0.0, "dt": 0.016})
	if ai._recover_until <= 0.0:
		printerr("  recover timer not armed at 30% of peak")
		return false
	var fsm: AIStateMachine = AIStateMachine.new()
	var state: AIState = fsm.pick(_ctx({"recover_active": true}))
	if state.state_name != &"RECOVER":
		printerr("  recover-active picked %s" % state.state_name)
		return false
	ai.free()
	director.free()
	snake.free()
	return true


# --- §8.5 staggered ticks + LOD + §8.1 same-interface (live, brief) ---------

func test_ai_world_behaviour() -> bool:
	_to_playing()
	var root: Node = _tree().root
	var director: AIDirector = AIDirector.new()
	director.balance = BALANCE
	director.collectibles = null
	director.spawn_manager = null
	root.add_child(director)
	# Static distant player proxy → every AI should go LOD-far (dist=100).
	var far_snake: SnakeController = SnakeControllerClass.new()
	far_snake.config = load("res://resources/config/snake_player.tres")
	root.add_child(far_snake)
	far_snake.global_position = Vector3(100, 0, 0)
	far_snake.alive = false
	director.player_snake = far_snake
	var ais: Array[AIController] = []
	var phases: Array[float] = []
	var start_positions: Array[Vector3] = []
	for i in 8:
		var ai: AIController = AI_SCENE.instantiate()
		ai.director = director
		ai.personality = load("res://resources/ai/ai_collector.tres")
		root.add_child(ai)
		director.ai_controllers.append(ai)
		phases.append(ai._decide_elapsed)
		start_positions.append(ai.snake.global_position)
		ais.append(ai)
	# §8.5 stagger: phases are spread across the 0.1 s decision window.
	var distinct_phases: Dictionary = {}
	for p in phases:
		if p < 0.0 or p > 0.1:
			printerr("  stagger phase %.3f outside [0, 0.1]" % p)
			return false
		distinct_phases[snappedf(p, 0.01)] = true
	if distinct_phases.size() < 4:
		printerr("  stagger phases too clustered: %d distinct" % distinct_phases.size())
		return false
	# Let them think and move for 0.8 s of real frames.
	await _tree().create_timer(0.8, true).timeout
	var all_decided: bool = true
	var all_moved: bool = true
	var all_lod_far: bool = true
	var interface_ok: bool = true
	for i in 8:
		var ai: AIController = ais[i]
		if ai.visited_states.is_empty():
			all_decided = false
		if ai.snake.global_position.distance_to(start_positions[i]) < 2.0:
			all_moved = false
		if not ai.is_lod_far() or ai.snake.body_tick_stride != 3 or ai.snake.body.mmi.visible:
			all_lod_far = false
		# §8.1: the AI drives through the SAME set_steer_target interface.
		if not ai.snake._has_steer_target:
			interface_ok = false
	if not all_decided:
		printerr("  some AI never decided in 0.8 s")
		return false
	if not all_moved:
		printerr("  some AI never moved")
		return false
	if not all_lod_far:
		printerr("  distant-AI LOD not applied (stride/cull)")
		return false
	if not interface_ok:
		printerr("  AI bypassed set_steer_target (same-interface violation)")
		return false
	for ai in ais:
		ai.free()
	director.free()
	far_snake.free()
	return true


# --- §8.4 names -------------------------------------------------------------

func test_names_file_unique_and_assignable() -> bool:
	var director: AIDirector = AIDirector.new()
	director._load_names()
	if director._all_names.size() < 120:
		printerr("  names file has %d names, spec wants ~120" % director._all_names.size())
		return false
	var seen: Dictionary = {}
	for n in director._all_names:
		if seen.has(n):
			printerr("  duplicate name in file: %s" % n)
			return false
		seen[n] = true
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var assigned: Dictionary = {}
	for i in 8:
		var name: String = director._take_name(rng)
		if assigned.has(name):
			printerr("  name reused within match: %s" % name)
			return false
		assigned[name] = true
	director.free()
	return true


# --- §11 AI spawn validity --------------------------------------------------

func test_ai_spawn_validity_1000() -> bool:
	var arena: Node3D = ArenaScene.instantiate()
	_tree().root.add_child(arena)
	var sm: SpawnManager = arena.spawn_manager
	var snake: SnakeController = SnakeControllerClass.new()
	snake.config = load("res://resources/config/snake_player.tres")
	_tree().root.add_child(snake)
	snake.alive = false
	snake.global_position = Vector3.ZERO
	sm.player_snake = snake
	var radius_limit: float = sm.balance.arena_radius - 4.0
	for i in 1000:
		var pos: Vector3 = sm.find_ai_spawn_position(45.0)
		if pos.length() > radius_limit:
			printerr("  attempt %d outside arena: %s" % [i, pos])
			return false
		if pos.length() < 45.0:
			printerr("  attempt %d within 45 of player: %s" % [i, pos])
			return false
	arena.free()
	snake.free()
	return true

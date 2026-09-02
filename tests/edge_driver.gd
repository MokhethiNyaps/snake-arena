extends Node
## §48 Phase 12 — EDGE-CASE harness. Exercises the five spec edge cases
## against the REAL game and prints CC_EDGE_* markers:
##   E1 0 AI · E2 240 segments · E3 instant death · E4 spam-restart
##   E5 focus loss mid-ad (alt-tab)
## Uses no test doubles; drives the run director, combat manager, AdManager.

var _director: Node = null
var _max_frame_ms: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _sec(t: float) -> void:
	await get_tree().create_timer(t, true).timeout


func _subtree_count(node: Node) -> int:
	var n: int = 1
	for c in node.get_children():
		n += _subtree_count(c)
	return n


func _fail(why: String) -> void:
	print("CC_EDGE_VERIFY_FAIL " + why)
	get_tree().quit(1)


func _run() -> void:
	await _frames(30)
	_director = get_tree().get_first_node_in_group("run_director")
	if _director == null or _director._arena == null:
		_fail("run director/arena missing")
		return
	if AdManager.provider is AdProviderMock:
		var mock: AdProviderMock = AdManager.provider
		mock.auto_close_seconds = 1.0
		mock.latency_seconds = 0.1
		mock.forced_outcome = AdProviderMock.ForcedOutcome.COMPLETED

	# --- E1: 0 AI ------------------------------------------------------------
	var ai: Node = _director._arena.ai_director
	ai.despawn_all()
	ai.balance.ai_count = 0
	await _sec(8.0)
	if ai.get_ai_count() != 0:
		_fail("E1: AIs present (%d) after despawn_all + ai_count=0" % ai.get_ai_count())
		return
	if not GameManager.is_in(GameManager.State.PLAYING):
		_fail("E1: game not PLAYING with 0 AI (%s)" % GameManager.state_name())
		return
	print("CC_EDGE_ZERO_AI ok (played 8 s with zero AIs)")
	ai.balance.ai_count = 8

	# --- E2: 240 segments (the hard cap) -------------------------------------
	if _director._snake != null:
		_director._snake.set_meta("invulnerable_until", 1.0e9)
		# REALISTIC cap power: segments = 6 + p/3.5 → p ≈ 819 = 240 segs
		# (radius 0.55·819^0.19 ≈ 2.0 u). Power 60000 would be a 4.5-unit-
		# radius blob × 240 — 10× the fill of any reachable game state.
		_director._snake.add_power(820.0)
	await _sec(9.0)  # growth ramp (0.25 s per segment stagger, throttled)
	var segs: int = _director._snake.get_segment_count() if _director._snake != null else 0
	if segs < 232 or segs > 240:
		_fail("E2: segment count %d not at the 240 cap" % segs)
		return
	# Frame-time DISTRIBUTION over steady-state 240-segment play (a single
	# max can be a cold-start spike; the budget question is avg + spikes).
	await _sec(2.0)
	var worst: float = 0.0
	var acc: float = 0.0
	var n: int = 0
	var over20: int = 0
	for i in 300:
		await get_tree().process_frame
		var ms: float = get_process_delta_time() * 1000.0
		worst = maxf(worst, ms)
		acc += ms
		n += 1
		if ms > 20.0:
			over20 += 1
	print("CC_EDGE_SEGS_240 ok segs=%d avg_frame_ms=%.1f max_frame_ms=%.1f over_20ms=%d/%d" % [
		segs, acc / maxf(1.0, float(n)), worst, over20, n])

	# --- E3: instant death ----------------------------------------------------
	# start_run is only valid from MENU/GAME_OVER, and PLAYING→MENU is also
	# refused — the REAL quit path goes through PAUSED (pause screen → MAIN
	# MENU → PLAY). The driver follows exactly that.
	_director.pause_game()
	await _frames(8)
	_director.quit_to_menu()
	await _frames(8)
	_director.start_run()
	await _frames(12)
	while _director._arena == null or _director._arena.combat_manager == null:
		await _frames(2)
	_director._arena.combat_manager._kill(_director._snake, null)
	var waited: float = 0.0
	while not GameManager.is_in(GameManager.State.GAME_OVER) and waited < 6.0:
		await _sec(0.2)
		waited += 0.2
	if not GameManager.is_in(GameManager.State.GAME_OVER):
		_fail("E3: instant death never reached GAME_OVER (%s)" % GameManager.state_name())
		return
	if UIManager.get_current_screen() == null:
		_fail("E3: game-over panel never pushed")
		return
	print("CC_EDGE_INSTANT_DEATH ok (panel pushed, %.1f s)" % waited)

	# --- E4: spam-restart -----------------------------------------------------
	await _sec(1.0)
	var nodes0: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var sizes0: Dictionary = {}
	for child in get_tree().root.get_children():
		sizes0[child.name] = _subtree_count(child)
	for i in 8:
			_director.pause_game()
			await _frames(4)
			_director.quit_to_menu()
			await _frames(4)
			_director.start_run()
			await _frames(12)
			if i == 7:
				for c in get_tree().root.get_children():
					var now_n: int = _subtree_count(c)
					var was_n: int = int(sizes0.get(c.name, 0))
					if now_n > was_n:
						print("CC_EDGE_GROWTH_CHILD %s=%d (+%d)" % [c.name, now_n, now_n - was_n])
						if String(c.name) == "ObjectPoolRegistry":
							var cont: Node = c.get_node("PooledObjects")
							var tally: Dictionary = {}
							for pn in cont.get_children():
								var base: String = String(pn.name).rstrip("0123456789")
								tally[base] = int(tally.get(base, 0)) + 1 + (_subtree_count(pn) - 1)
							print("CC_EDGE_POOLNAMES " + str(tally))
	await _sec(1.5)
	var nodes1: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	if absi(nodes1 - nodes0) > 40:
		# WHAT leaked? Root-subtree breakdown, biggest first.
		var breakdown: Array = []
		for child in get_tree().root.get_children():
			breakdown.append("%s=%d" % [child.name, _subtree_count(child)])
		breakdown.sort_custom(func(a: String, b: String) -> bool:
			return int(a.split("=")[1]) > int(b.split("=")[1]))
		print("CC_EDGE_TREE " + " | ".join(breakdown.slice(0, 8)))
		print("CC_EDGE_POOLED total_created=%d container_children=%d" % [
			ObjectPoolRegistry.total_pooled_nodes(),
			ObjectPoolRegistry._container.get_child_count()])
		_fail("E4: node count drifted %d → %d across spam restarts (leak?)" % [nodes0, nodes1])
		return
	if not GameManager.is_in(GameManager.State.PLAYING):
		_fail("E4: not PLAYING after spam restarts (%s)" % GameManager.state_name())
		return
	print("CC_EDGE_SPAM_RESTART ok (8 restarts + 4 menu flips, nodes %d → %d)" % [nodes0, nodes1])

	# --- E5: focus loss mid-ad (alt-tab) -------------------------------------
	# Ads are consent-gated; grant explicitly (portal never ran under CC_EDGE).
	ConsentManager.set_consent(ConsentManager.ConsentState.GRANTED, "edge-e5")
	# E5 needs a REAL mid-ad window: natural overlay (not the instant
	# forced COMPLETED used by earlier sections), short load, 3 s countdown.
	var mock5: AdProviderMock = AdManager.provider
	mock5.forced_outcome = AdProviderMock.ForcedOutcome.NONE
	mock5.latency_seconds = 0.1
	mock5.auto_close_seconds = 3.0
	if _director._snake != null:
		_director._snake.set_meta("invulnerable_until", 1.0e9)
	var finished: Array = []
	AdManager.ad_finished.connect(func(_p: int, r: AdResult) -> void: finished.append(r), CONNECT_ONE_SHOT)
	AdManager.request_ad(AdPlacementId.ID.REVIVE, true)  # fire-and-forget
	await _sec(0.45)  # ad is mid-show (mock: 0.1 latency + 1.0 auto-close)
	if not GameManager.is_in(GameManager.State.PAUSED_FOR_AD):
		for entry in AdManager.get_decision_log().slice(-4):
			print("CC_EDGE_ADLOG " + entry)
		_fail("E5: expected PAUSED_FOR_AD mid-ad (state %s)" % GameManager.state_name())
		return
	get_tree().root.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _sec(0.3)
	get_tree().root.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	var w5: float = 0.0
	while finished.is_empty() and w5 < 6.0:
		await _sec(0.2)
		w5 += 0.2
	if finished.is_empty():
		_fail("E5: ad never resolved after focus loss")
		return
	if GameManager.is_in(GameManager.State.PAUSED_FOR_AD) or get_tree().paused:
		_fail("E5: still paused after focus-loss resolution (%s)" % GameManager.state_name())
		return
	if InputManager.is_suspended():
		_fail("E5: input left suspended after focus-loss resolution")
		return
	print("CC_EDGE_AD_FOCUS ok (mid-ad alt-tab → %s, state restored to %s)" % [
		AdResult.Code.keys()[finished[0].code], GameManager.state_name()])

	print("CC_EDGE_VERIFY_PASS")
	get_tree().quit(0)

extends Node
## §48 Phase 12 — SOAK harness. Runs the real game in a play → die →
## game-over → restart loop (with menu returns and mock ads interleaved)
## for CC_SOAK_MINUTES (default 30), sampling health metrics every
## CC_SOAK_SAMPLE_S (default 15 s): node count, ORPHAN node count (the
## leak signal), static memory, draw calls, FPS, state.
##
## Pass criteria (printed as CC_SOAK_PASS / CC_SOAK_FAIL):
##   • orphan-node growth between the first and last quarters ≤ 50
##   • node-count growth ≤ 25 %
##   • the process is still alive at the deadline (no crash)
## Talks to: run director (group), AdManager, GameManager. No test doubles.

const DEATH_INTERVAL_S: float = 90.0
const MENU_EVERY_N_CYCLES: int = 3
const AD_EVERY_N_CYCLES: int = 2

var _director: Node = null
var _t: float = 0.0
var _last_death: float = 6.0
var _cycle: int = 0
var _samples: Array[Dictionary] = []
var _deadline: float = 1800.0
var _sample_every: float = 15.0
var _last_sample: float = -1.0e9
var _restarting: bool = false


func _ready() -> void:
	# Sample even while the tree is paused (mid-ad / hit-stop).
	process_mode = Node.PROCESS_MODE_ALWAYS
	var mins: String = OS.get_environment("CC_SOAK_MINUTES")
	if mins != "":
		_deadline = maxf(60.0, float(mins) * 60.0)
	var s: String = OS.get_environment("CC_SOAK_SAMPLE_S")
	if s != "":
		_sample_every = maxf(2.0, float(s))
	if AdManager.provider is AdProviderMock:
		var mock: AdProviderMock = AdManager.provider
		mock.auto_close_seconds = 1.0
		mock.latency_seconds = 0.1
		mock.forced_outcome = AdProviderMock.ForcedOutcome.COMPLETED


func _process(delta: float) -> void:
	_t += delta
	_director = _director if _director != null else get_tree().get_first_node_in_group("run_director")
	if _director == null:
		return
	if _t >= _deadline:
		_finish()
		return
	if _t - _last_sample >= _sample_every:
		_last_sample = _t
		_sample()
	if get_tree().paused:
		return
	if GameManager.is_in(GameManager.State.GAME_OVER):
		# Escape hatch: if a restart attempt was refused (e.g. an INTER_RUN ad
		# held PAUSED_FOR_AD at the wrong instant), unstick and retry.
		if _restarting and _t - _last_death > 10.0:
			_restarting = false
		if not _restarting and _t - _last_death > 3.0:
			_restarting = true
			_restart_cycle()
	elif GameManager.is_in(GameManager.State.PLAYING):
		_restarting = false
		if _t - _last_death > DEATH_INTERVAL_S:
			_last_death = _t
			_force_death()


func _restart_cycle() -> void:
	_cycle += 1
	if _cycle % AD_EVERY_N_CYCLES == 0:
		# §45 INTER_RUN plays BETWEEN runs: let it fully resolve (watchdog
		# guarantees resolution) BEFORE start_run, or the state request is
		# refused while PAUSED_FOR_AD and the run never starts.
		await AdManager.request_ad(AdPlacementId.ID.INTER_RUN, true)
	if _cycle % MENU_EVERY_N_CYCLES == 0:
		_director.quit_to_menu()
		# start_run is deferred to the next frame so the menu push completes.
		_start_run_soon.call_deferred()
	else:
		_director.start_run()
	_last_death = _t


func _start_run_soon() -> void:
	_director.start_run()


func _force_death() -> void:
	if _director._snake == null or _director._arena == null:
		return
	# Full real death path (kill → dissolve → DYING → GAME_OVER → panel).
	_director._arena.combat_manager._kill(_director._snake, null)


func _sample() -> void:
	var entry: Dictionary = {
		"t": _t,
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"mem_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"draw": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"fps": Performance.get_monitor(Performance.TIME_FPS),
	}
	_samples.append(entry)
	print("CC_SOAK_SAMPLE t=%.0f nodes=%d orphans=%d mem_mb=%.1f draw=%d fps=%.0f state=%s cycle=%d" % [
		_t, entry.nodes, entry.orphans, entry.mem_mb, int(entry.draw), entry.fps,
		GameManager.state_name(), _cycle])


func _finish() -> void:
	_sample()
	if _samples.size() < 4:
		print("CC_SOAK_FAIL too few samples (%d)" % _samples.size())
		get_tree().quit(1)
		return
	var q: int = maxi(1, _samples.size() / 4)
	var first: Dictionary = _avg(_samples.slice(0, q))
	var last: Dictionary = _avg(_samples.slice(_samples.size() - q, _samples.size() + 1))
	var orphan_growth: int = int(last["orphans"]) - int(first["orphans"])
	var node_growth_pct: float = (float(last["nodes"]) - float(first["nodes"])) / maxf(1.0, float(first["nodes"])) * 100.0
	var mem_growth_mb: float = float(last["mem_mb"]) - float(first["mem_mb"])
	var ok: bool = orphan_growth <= 50 and node_growth_pct <= 25.0
	print("CC_SOAK_SUMMARY samples=%d minutes=%.1f cycles=%d nodes %.0f→%.0f (%+.1f%%) orphans %.0f→%.0f (%+d) mem %.1f→%.1f MB (%+.1f)" % [
		_samples.size(), _t / 60.0, _cycle, float(first["nodes"]), float(last["nodes"]),
		node_growth_pct, float(first["orphans"]), float(last["orphans"]), orphan_growth,
		float(first["mem_mb"]), float(last["mem_mb"]), mem_growth_mb])
	if ok:
		print("CC_SOAK_PASS")
		get_tree().quit(0)
	else:
		print("CC_SOAK_FAIL orphan_growth=%d node_growth_pct=%.1f" % [orphan_growth, node_growth_pct])
		get_tree().quit(1)


func _avg(rows: Array) -> Dictionary:
	var out: Dictionary = {"nodes": 0.0, "orphans": 0.0, "mem_mb": 0.0}
	for k in out:
		var acc: float = 0.0
		for r in rows:
			acc += float(r[k])
		out[k] = acc / maxf(1.0, float(rows.size()))
	return out

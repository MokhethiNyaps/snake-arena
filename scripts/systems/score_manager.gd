class_name ScoreManager
extends Node
## §12.3 — Score + combo bookkeeping for the current run.
##
## Placement: scene-level node created by arena.gd (decision #25).
##
## Owns: score, combo state, survival accrual, the multiplier table.
## Does NOT own: what grants score (callers decide), display (HUD, Phase 8).
## Talks to: EventBus (score_changed / combo_changed emissions).

@export var balance: GameBalanceConfig = preload("res://resources/config/game_balance.tres")

## Injectable clock (ms) so tests can control time deterministically.
var clock_ms: Callable = func() -> int: return Time.get_ticks_msec()

var score: float = 0.0
var combo: int = 0
var _last_collect_ms: int = -1000000
var _survival_carry: float = 0.0
var _survival_emit_timer: float = 0.0


func _ready() -> void:
	EventBus.run_started.connect(reset)


func reset() -> void:
	score = 0.0
	combo = 0
	_last_collect_ms = -1000000
	_survival_carry = 0.0
	EventBus.score_changed.emit(score)
	EventBus.combo_changed.emit(combo)


## Register one collectible absorb. Returns the score gained (base × combo
## multiplier). §12.3 literal formula: combo increments when collecting
## within combo_window of the previous collect; multiplier =
## 1 + min(combo, combo_max_bonus_steps) * combo_multiplier_step (max 2x).
func on_collectible(score_base: float) -> float:
	var now: int = clock_ms.call()
	var since: float = float(now - _last_collect_ms) / 1000.0
	combo = combo + 1 if since <= balance.combo_window else 1
	_last_collect_ms = now
	var mult: float = combo_multiplier()
	var gain: float = score_base * mult
	add_score(gain)
	EventBus.combo_changed.emit(combo)
	return gain


func combo_multiplier() -> float:
	return 1.0 + minf(float(combo), float(balance.combo_max_bonus_steps)) * balance.combo_multiplier_step


## Seconds left in the combo window (HUD ring, Phase 8).
func combo_time_left() -> float:
	var since: float = float(clock_ms.call() - _last_collect_ms) / 1000.0
	return maxf(0.0, balance.combo_window - since)


## Flat score from any non-collect source (absorb, survival, claims...).
func add_score(base: float) -> void:
	score += base
	EventBus.score_changed.emit(score)


## Survival score §12.3: 6/s while alive. Accrues continuously; emitted
## throttled so per-tick listeners don't spam.
func tick(delta: float) -> void:
	_survival_carry += balance.survival_score_per_second * delta
	var whole: float = floor(_survival_carry)
	if whole >= 1.0:
		_survival_carry -= whole
		score += whole
		_survival_emit_timer += delta
		if _survival_emit_timer >= 0.25:
			_survival_emit_timer = 0.0
			EventBus.score_changed.emit(score)


func get_score() -> float:
	return score


func get_combo() -> int:
	return combo

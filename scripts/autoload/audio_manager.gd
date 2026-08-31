extends Node
## AUTOLOAD #7 — AudioManager (§15). Buses: Master -> Music / SFX / UI.
##
## Owns: bus topology, volumes, ducking (§45.6), play calls.
## Phase 1: bus setup + duck/restore + stubs for play_sfx/play_music.
## Phase 10: voice-limited 3D SFX pools, combo-pitched collect sounds, music
##           layers, procedural SFX from tools/gen_sfx.gd.
## Does NOT own: audio assets; it only routes and plays them.
## Talks to: gameplay systems (play calls), AdManager (duck_all/restore).

const BUS_MASTER: StringName = &"Master"
const BUS_MUSIC: StringName = &"Music"
const BUS_SFX: StringName = &"SFX"
const BUS_UI: StringName = &"UI"

const DUCK_DB: float = -80.0

var _ducked: bool = false
var _pre_duck_volumes: Dictionary = {}


func _ready() -> void:
	_ensure_buses()


## Creates Music/SFX/UI buses routed to Master if missing (survives projects
## without a hand-authored default_bus_layout).
func _ensure_buses() -> void:
	for bus in [BUS_MUSIC, BUS_SFX, BUS_UI]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var idx: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, BUS_MASTER)
	print("[AudioManager] Buses ready (driver: %s)" % AudioServer.get_driver_name())


## Instant full duck for ads (§45.6) — not faded.
func duck_all(db: float = DUCK_DB) -> void:
	if _ducked:
		return
	_ducked = true
	for bus in [BUS_MUSIC, BUS_SFX, BUS_UI]:
		_pre_duck_volumes[bus] = AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus))
		set_bus_volume_db(bus, db)


## Restores pre-duck volumes after an ad resolves (any path).
func restore_audio() -> void:
	if not _ducked:
		return
	_ducked = false
	for bus in _pre_duck_volumes:
		set_bus_volume_db(bus, _pre_duck_volumes[bus])
	_pre_duck_volumes.clear()


func set_bus_volume_db(bus: StringName, db: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, db)


func get_bus_volume_db(bus: StringName) -> float:
	var idx: int = AudioServer.get_bus_index(bus)
	return AudioServer.get_bus_volume_db(idx) if idx >= 0 else 0.0


## Phase 10 stub — real implementation pools voices and coalesces bursts.
func play_sfx(_id: StringName, _pitch_variation: bool = true) -> void:
	pass


## Phase 10 stub — menu/gameplay loops with intensity layers.
func play_music(_id: StringName) -> void:
	pass

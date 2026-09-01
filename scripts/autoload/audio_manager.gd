extends Node
## AUTOLOAD #7 — AudioManager (§15). Buses: Master -> Music / SFX / UI.
##
## Owns: bus topology, volumes, ducking (§45.6), the §15 voice pools
##       (24 AudioStreamPlayer3D + 12 AudioStreamPlayer), burst coalescing,
##       and pitch variation.
## Phase 3: voice pools + procedural collect SFX (tools/gen_sfx.gd).
## Phase 10: music loops/layers; fuller SFX set.
## Does NOT own: audio assets; it only routes and plays them.
## Talks to: gameplay systems (play calls), AdManager (duck_all/restore).

const BUS_MASTER: StringName = &"Master"
const BUS_MUSIC: StringName = &"Music"
const BUS_SFX: StringName = &"SFX"
const BUS_UI: StringName = &"UI"

const DUCK_DB: float = -80.0

## §15 voice limits.
const VOICE_LIMIT_3D: int = 24
const VOICE_LIMIT_2D: int = 12
## §15 burst coalescing: more than COALESCE_THRESHOLD plays within
## COALESCE_WINDOW collapses into one louder instance.
const COALESCE_WINDOW: float = 0.15
const COALESCE_THRESHOLD: int = 10
const COALESCE_LOUD_DB: float = 6.0
const PITCH_VARIATION: float = 0.08  # ±8% (§15)
const COMBO_SEMITONE_MAX: int = 12   # combo pitch caps at one octave (§15)

const SFX_COLLECT: StringName = &"collect"
const SFX_RARE: StringName = &"rare"
const SFX_MOTE: StringName = &"mote"

const _SFX_STREAMS: Dictionary = {
	SFX_COLLECT: preload("res://audio/sfx/collect_pop.wav"),
	SFX_RARE: preload("res://audio/sfx/collect_rare.wav"),
	SFX_MOTE: preload("res://audio/sfx/collect_mote.wav"),
}

var _ducked: bool = false
var _pre_duck_volumes: Dictionary = {}

var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_2d: Array[AudioStreamPlayer] = []
var _next_3d: int = 0
var _next_2d: int = 0
## Ring of play timestamps for burst coalescing.
var _recent_plays: Array[float] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_ensure_buses()
	_build_pools()
	_rng.randomize()


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


## Phase 10 stub — menu/gameplay loops with intensity layers.
func play_music(_id: StringName) -> void:
	pass


## §15 voice pools: 24 3D voices for world SFX, 12 2D voices for UI.
func _build_pools() -> void:
	for i in VOICE_LIMIT_3D:
		var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		p.bus = BUS_SFX
		p.max_distance = 60.0
		add_child(p)
		_pool_3d.append(p)
	for i in VOICE_LIMIT_2D:
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.bus = BUS_SFX
		add_child(p)
		_pool_2d.append(p)


## Plays `id` as a positional (3D) SFX with optional pitch scale.
func play_sfx(id: StringName, pitch_scale: float = 1.0, at_pos: Vector3 = Vector3.INF) -> void:
	var stream: AudioStream = _SFX_STREAMS.get(id)
	if stream == null:
		return
	if _coalesce_drop():
		return
	if at_pos.is_finite() and not _pool_3d.is_empty():
		var p: AudioStreamPlayer3D = _pool_3d[_next_3d]
		_next_3d = (_next_3d + 1) % VOICE_LIMIT_3D
		p.global_position = at_pos
		p.stream = stream
		p.pitch_scale = pitch_scale * _varied_pitch()
		p.volume_db = 0.0
		p.play()
	elif not _pool_2d.is_empty():
		var p: AudioStreamPlayer = _pool_2d[_next_2d]
		_next_2d = (_next_2d + 1) % VOICE_LIMIT_2D
		p.stream = stream
		p.pitch_scale = pitch_scale * _varied_pitch()
		p.volume_db = 0.0
		p.play()


## §15 combo-pitched collect SFX: one semitone per combo step, capped at an
## octave, plus the ±8% variation. `type_id` picks collect/rare/mote.
func play_pickup(type_id: int, combo_steps: int, at_pos: Vector3) -> void:
	var id: StringName = SFX_COLLECT
	if type_id == CollectibleDef.Type.SHARD_RARE:
		id = SFX_RARE
	elif type_id == CollectibleDef.Type.CORPSE_MOTE:
		id = SFX_MOTE
	var semitones: int = clampi(combo_steps, 0, COMBO_SEMITONE_MAX)
	var scale: float = pow(2.0, float(semitones) / 12.0)
	play_sfx(id, scale, at_pos)


func _varied_pitch() -> float:
	return 1.0 + _rng.randf_range(-PITCH_VARIATION, PITCH_VARIATION)


## §15 burst coalescing: beyond COALESCE_THRESHOLD plays in
## COALESCE_WINDOW, drop this request — the burst already coalesced into
## one louder instance when the threshold was crossed.
func _coalesce_drop() -> bool:
	var now: float = Time.get_ticks_msec() / 1000.0
	_recent_plays.append(now)
	while not _recent_plays.is_empty() and now - _recent_plays[0] > COALESCE_WINDOW:
		_recent_plays.pop_front()
	if _recent_plays.size() < COALESCE_THRESHOLD:
		return false
	if _recent_plays.size() == COALESCE_THRESHOLD:
		# Crossed the threshold: play one LOUDER instance instead of the
		# machine-gun. Route through a 2D voice at +6 dB.
		var stream: AudioStream = _SFX_STREAMS.get(SFX_COLLECT)
		if stream != null and not _pool_2d.is_empty():
			var p: AudioStreamPlayer = _pool_2d[_next_2d]
			_next_2d = (_next_2d + 1) % VOICE_LIMIT_2D
			p.stream = stream
			p.pitch_scale = _varied_pitch()
			p.volume_db = COALESCE_LOUD_DB
			p.play()
	return true

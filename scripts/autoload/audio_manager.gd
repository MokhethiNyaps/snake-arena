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
	&"ui_click": preload("res://audio/sfx/ui_click.wav"),
	&"absorb_zap": preload("res://audio/sfx/absorb_zap.wav"),
	&"boost_whoosh": preload("res://audio/sfx/boost_whoosh.wav"),
	&"powerup": preload("res://audio/sfx/powerup.wav"),
	&"revive": preload("res://audio/sfx/revive.wav"),
	&"new_best": preload("res://audio/sfx/new_best.wav"),
	&"level_up": preload("res://audio/sfx/level_up.wav"),
	&"mission_done": preload("res://audio/sfx/mission_done.wav"),
	&"coin_tick": preload("res://audio/sfx/coin_tick.wav"),
	&"wall_thud": preload("res://audio/sfx/wall_thud.wav"),
	&"surge_ping": preload("res://audio/sfx/surge_ping.wav"),
	&"shrink_alarm": preload("res://audio/sfx/shrink_alarm.wav"),
	&"death_sting": preload("res://audio/sfx/death_sting.wav"),
	&"gameover": preload("res://audio/sfx/gameover.wav"),
}

## §15 music layers — gentle procedural pads (see tools/gen_sfx.gd).
const MUSIC_MENU: StringName = &"menu"
const MUSIC_GAMEPLAY: StringName = &"gameplay"
const MUSIC_CROSSFADE_S: float = 1.2
const MUSIC_INTENSITY_SMOOTH: float = 0.5  # seconds per intensity re-step

var _ducked: bool = false
var _pre_duck_volumes: Dictionary = {}
## §15 web autoplay: nothing audible until the first user gesture.
var _unlocked: bool = false
var _music_players: Dictionary = {}   # layer id -> AudioStreamPlayer
var _music_current: StringName = &""
var _music_intensity: float = 0.0
var _last_coin_sfx: float = -1.0

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
	_build_music()
	_wire_event_sfx()
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


## Called from ANY first input (InputManager forwards the first event) —
## §15 web autoplay policy. Until then, play calls silently no-op except
## UI clicks, which are themselves gestures and unlock on the spot.
func unlock() -> void:
	if _unlocked:
		return
	_unlocked = true
	if _music_current != &"":
		_fade_layer(_music_current, 1.0)


func is_unlocked() -> bool:
	return _unlocked


## §15 music: one menu loop; gameplay = low + high layers cross-faded by
## `set_music_intensity` (nearby threat count drives it).
func play_music(id: StringName) -> void:
	if _music_current == id:
		return
	_music_current = id
	if not _unlocked:
		return  # starts on unlock()
	match id:
		MUSIC_MENU:
			_fade_layer(&"menu", 1.0)
			_fade_layer(&"game_low", 0.0)
			_fade_layer(&"game_high", 0.0)
		MUSIC_GAMEPLAY:
			_fade_layer(&"menu", 0.0)
			_apply_intensity()
		_:
			_fade_layer(&"menu", 0.0)
			_fade_layer(&"game_low", 0.0)
			_fade_layer(&"game_high", 0.0)


## 0..1 — how hot the gameplay layer stack runs (threat pressure).
func set_music_intensity(x: float) -> void:
	_music_intensity = clampf(x, 0.0, 1.0)
	if _music_current == MUSIC_GAMEPLAY and _unlocked:
		_apply_intensity()


func _apply_intensity() -> void:
	# Low layer always up in gameplay; high layer fades in with threat.
	_fade_layer(&"game_low", 1.0)
	_fade_layer(&"game_high", _music_intensity)


func _fade_layer(layer: StringName, volume: float) -> void:
	var player: AudioStreamPlayer = _music_players.get(layer)
	if player == null:
		return
	var target_db: float = linear_to_db(clampf(volume, 0.0001, 1.0)) if volume > 0.0 else -80.0
	var tween: Tween = create_tween()
	tween.tween_property(player, "volume_db", target_db, MUSIC_CROSSFADE_S)


func _build_music() -> void:
	var layers: Dictionary = {
		&"menu": preload("res://audio/sfx/music_menu.wav"),
		&"game_low": preload("res://audio/sfx/music_game_low.wav"),
		&"game_high": preload("res://audio/sfx/music_game_high.wav"),
	}
	for layer in layers:
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.name = "Music_" + String(layer)
		p.bus = BUS_MUSIC
		p.stream = layers[layer]
		p.volume_db = -80.0
		add_child(p)
		_music_players[layer] = p
		p.play()


## EventBus → SFX wiring (self-contained; systems never call audio directly
## except positional world sounds).
func _wire_event_sfx() -> void:
	EventBus.player_died.connect(func() -> void: play_sfx(&"death_sting", 1.0, Vector3.INF))
	EventBus.powerup_collected.connect(func(_t: int) -> void: play_sfx(&"powerup"))
	EventBus.level_up.connect(func(_l: int) -> void: play_sfx(&"level_up"))
	EventBus.mission_completed.connect(func(_id: StringName) -> void: play_sfx(&"mission_done"))
	EventBus.surge_incoming.connect(func(_p: Vector3) -> void: play_sfx(&"surge_ping"))
	EventBus.arena_shrinking.connect(func(_r: float) -> void: play_sfx(&"shrink_alarm"))
	EventBus.coins_changed.connect(_on_coins_changed)
	InputManager.boost_pressed.connect(func() -> void: play_sfx(&"boost_whoosh"))
	EventBus.game_state_changed.connect(_on_music_state)


func _on_music_state(_from: int, to: int) -> void:
	match to:
		GameManager.State.MENU:
			play_music(MUSIC_MENU)
		GameManager.State.PLAYING:
			play_music(MUSIC_GAMEPLAY)
		GameManager.State.GAME_OVER:
			play_music(&"")
			play_sfx(&"gameover")


func _on_coins_changed(_coins: int) -> void:
	# Rate-limited tick so a big payout does not machine-gun.
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_coin_sfx < 0.08:
		return
	_last_coin_sfx = now
	play_sfx(&"coin_tick", 1.0, Vector3.INF)


## UI-bus one-shot (buttons etc.). A UI interaction IS a user gesture —
## it also unlocks audio (§15 autoplay).
func play_ui(id: StringName) -> void:
	unlock()
	var stream: AudioStream = _SFX_STREAMS.get(id)
	if stream == null or _pool_2d.is_empty():
		return
	var p: AudioStreamPlayer = _pool_2d[_next_2d]
	_next_2d = (_next_2d + 1) % VOICE_LIMIT_2D
	p.bus = BUS_UI
	p.stream = stream
	p.pitch_scale = _varied_pitch()
	p.volume_db = 0.0
	p.play()


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
	if not _unlocked:
		return  # §15 autoplay: no audio before the first user gesture
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

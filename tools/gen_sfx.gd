extends SceneTree
## §15 — Procedural SFX generator. Synthesises and saves .wav files to
## res://audio/sfx/ so the project ships zero downloaded audio assets
## (placeholder art/audio must be procedural or CC0 — assets/CREDITS.md).
##
## Run:  godot --headless --path . --script res://tools/gen_sfx.gd
## Re-run after tweaking the synth code; the .wav files are committed.

const RATE: int = 22050

const OUT_DIR: String = "res://audio/sfx/"

# id -> [duration_s, envelope_params, partial list]
# partials: [freq_hz, amplitude, freq_sweep_to (0 = none), attack_fraction]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_make_collect_pop()
	_make_collect_rare()
	_make_collect_mote()
	_make_phase10()
	print("GEN_SFX_DONE -> %s" % OUT_DIR)
	quit(0)


# --- Phase 10 batch ----------------------------------------------------------

func _make_phase10() -> void:
	_make_ui_click()
	_make_absorb_zap()
	_make_boost_whoosh()
	_make_powerup()
	_make_revive()
	_make_new_best()
	_make_level_up()
	_make_mission_done()
	_make_coin_tick()
	_make_wall_thud()
	_make_surge_ping()
	_make_shrink_alarm()
	_make_death_sting()
	_make_gameover()
	_make_music_menu()
	_make_music_low()
	_make_music_high()


func _make_ui_click() -> void:
	var dur: float = 0.035
	var n: int = int(dur * RATE)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var t: float = float(i) / RATE
		var v: float = sin(TAU * 1250.0 * t) * exp(-t * 120.0)
		v += rng.randf_range(-1.0, 1.0) * exp(-t * 400.0) * 0.4
		s[i] = v * 0.5
	_write_wav(OUT_DIR + "ui_click.wav", s)


func _make_absorb_zap() -> void:
	var dur: float = 0.18
	var n: int = int(dur * RATE)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t: float = float(i) / RATE
		var f: float = 300.0 + 620.0 * (t / dur)
		var env: float = exp(-t * 16.0)
		var v: float = sin(TAU * f * t) + sin(TAU * f * 2.0 * t) * 0.4
		s[i] = v * env * 0.5
	_write_wav(OUT_DIR + "absorb_zap.wav", s)


func _make_boost_whoosh() -> void:
	var dur: float = 0.45
	var n: int = int(dur * RATE)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 21
	var smooth: float = 0.0
	for i in n:
		var t: float = float(i) / RATE
		# Lowpassed noise (moving average) = airy whoosh body.
		var raw: float = rng.randf_range(-1.0, 1.0)
		smooth = smooth * 0.92 + raw * 0.08
		var env: float = sin(PI * t / dur)
		var f: float = 180.0 + 90.0 * (t / dur)
		s[i] = (smooth * 1.6 + sin(TAU * f * t) * 0.3) * env * 0.5
	_write_wav(OUT_DIR + "boost_whoosh.wav", s)


func _make_powerup() -> void:
	var dur: float = 0.3
	var n: int = int(dur * RATE)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	var notes: Array = [[523.0, 0.0], [659.0, 0.07], [784.0, 0.14]]
	for i in n:
		var t: float = float(i) / RATE
		var v: float = 0.0
		for note in notes:
			var start: float = note[1]
			if t >= start:
				var lt: float = t - start
				v += sin(TAU * note[0] * t) * exp(-lt * 9.0) * 0.8
		s[i] = v * 0.4
	_write_wav(OUT_DIR + "powerup.wav", s)


func _make_revive() -> void:
	var dur: float = 0.8
	var n: int = int(dur * RATE)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	var partials: Array = [[440.0, 0.0, 3.0], [554.0, 0.12, 3.0], [659.0, 0.24, 3.5], [880.0, 0.36, 4.0], [1109.0, 0.48, 5.0]]
	for i in n:
		var t: float = float(i) / RATE
		var v: float = 0.0
		for p in partials:
			if t >= p[1]:
				var lt: float = t - p[1]
				v += sin(TAU * p[0] * t) * exp(-lt * p[2]) * 0.7
		s[i] = v * 0.4
	_write_wav(OUT_DIR + "revive.wav", s)


func _make_new_best() -> void:
	var dur: float = 0.9
	var n: int = int(dur * RATE)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	# Quick fanfare: C5 C5 G5, then a C-major stack held.
	var notes: Array = [[523.0, 0.0, 6.0, 1.0], [523.0, 0.12, 6.0, 1.0], [784.0, 0.24, 3.5, 1.0],
		[523.0, 0.4, 2.2, 0.7], [659.0, 0.4, 2.2, 0.6], [784.0, 0.4, 2.2, 0.6], [1046.0, 0.4, 2.4, 0.5]]
	for i in n:
		var t: float = float(i) / RATE
		var v: float = 0.0
		for note in notes:
			if t >= note[1]:
				var lt: float = t - note[1]
				v += sin(TAU * note[0] * t) * exp(-lt * note[2]) * note[3]
		s[i] = v * 0.4
	_write_wav(OUT_DIR + "new_best.wav", s)


func _make_level_up() -> void:
	var dur: float = 0.6
	var n: int = int(dur * RATE)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	var notes: Array = [[523.0, 0.0], [659.0, 0.09], [784.0, 0.18], [1046.0, 0.27]]
	for i in n:
		var t: float = float(i) / RATE
		var v: float = 0.0
		for note in notes:
			if t >= note[1]:
				var lt: float = t - note[1]
				v += sin(TAU * note[0] * t) * exp(-lt * 7.0) * 0.8
		s[i] = v * 0.4
	_write_wav(OUT_DIR + "level_up.wav", s)


func _make_mission_done() -> void:
	var dur: float = 0.45
	var n: int = int(dur * RATE)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t: float = float(i) / RATE
		var v: float = sin(TAU * 784.0 * t) * exp(-t * 7.0)
		if t >= 0.15:
			v += sin(TAU * 1046.0 * t) * exp(-(t - 0.15) * 5.0)
		s[i] = v * 0.4
	_write_wav(OUT_DIR + "mission_done.wav", s)


func _make_coin_tick() -> void:
	var dur: float = 0.06
	var n: int = int(dur * RATE)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t: float = float(i) / RATE
		var f: float = 1500.0 + 500.0 * (t / dur)
		s[i] = sin(TAU * f * t) * exp(-t * 60.0) * 0.35
	_write_wav(OUT_DIR + "coin_tick.wav", s)


func _make_wall_thud() -> void:
	var dur: float = 0.2
	var n: int = int(dur * RATE)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 33
	for i in n:
		var t: float = float(i) / RATE
		var v: float = sin(TAU * 88.0 * t) * exp(-t * 26.0) * 1.0
		v += rng.randf_range(-1.0, 1.0) * exp(-t * 220.0) * 0.35
		s[i] = v * 0.55
	_write_wav(OUT_DIR + "wall_thud.wav", s)


func _make_surge_ping() -> void:
	var dur: float = 0.8
	var n: int = int(dur * RATE)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t: float = float(i) / RATE
		var v: float = 0.0
		# Sonar: 660 Hz ping, echo at 200 ms (quieter).
		v += sin(TAU * 660.0 * t) * exp(-t * 9.0) * 0.8
		if t >= 0.2:
			v += sin(TAU * 660.0 * t) * exp(-(t - 0.2) * 9.0) * 0.4
		s[i] = v * 0.4
	_write_wav(OUT_DIR + "surge_ping.wav", s)


func _make_shrink_alarm() -> void:
	var dur: float = 0.9
	var n: int = int(dur * RATE)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t: float = float(i) / RATE
		# Three alternating two-tone bursts (A4 / C#5).
		var seg: float = fmod(t, 0.3)
		var f: float = 440.0 if int(t / 0.15) % 2 == 0 else 554.0
		var gate: float = 1.0 if t < 0.75 else 0.0
		var env: float = sin(PI * seg / 0.15) * gate
		s[i] = sin(TAU * f * t) * env * 0.35
	_write_wav(OUT_DIR + "shrink_alarm.wav", s)


func _make_death_sting() -> void:
	var dur: float = 0.9
	var n: int = int(dur * RATE)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t: float = float(i) / RATE
		# Dark glide: minor triad sliding down (220 -> 130 Hz), harmonics fade.
		var k: float = t / dur
		var f: float = 220.0 - 90.0 * k
		var env: float = exp(-t * 3.2) * minf(1.0, t * 60.0)
		var v: float = sin(TAU * f * t) * 1.0 \
			+ sin(TAU * f * 1.2 * t) * 0.5 \
			+ sin(TAU * f * 1.5 * t) * 0.4 \
			+ sin(TAU * f * 2.0 * t) * 0.25
		s[i] = v * env * 0.45
	_write_wav(OUT_DIR + "death_sting.wav", s)


func _make_gameover() -> void:
	var dur: float = 1.2
	var n: int = int(dur * RATE)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t: float = float(i) / RATE
		var env: float = exp(-t * 2.4) * minf(1.0, t * 30.0)
		var v: float = sin(TAU * 110.0 * t) * 1.0 + sin(TAU * 165.0 * t) * 0.5 + sin(TAU * 220.0 * t) * 0.3
		s[i] = v * env * 0.4
	_write_wav(OUT_DIR + "gameover.wav", s)


# --- Music layers (§15: gentle procedural pads; integer-Hz partials over an
# integer-second loop length = PERFECT seamless loops; human-taste flagged) ---

func _make_music_menu() -> void:
	# Warm calm pad (A2/E3/B3/F#3-ish stack, slow breathing LFO 1/6 Hz).
	var dur: float = 12.0
	synthesize_pad(OUT_DIR + "music_menu.wav", dur, [110.0, 165.0, 185.0, 220.0, 330.0], 0.22, 1.0 / 6.0, 33)


func _make_music_low() -> void:
	# Gameplay base layer: pulsing D2/A2, 1.5 Hz pulse (drives urgency).
	var dur: float = 8.0
	synthesize_pad(OUT_DIR + "music_game_low.wav", dur, [73.0, 110.0, 147.0], 0.2, 1.5, 44)


func _make_music_high() -> void:
	# Tension layer: sparse bright pluck pattern over a D-min pad.
	var dur: float = 8.0
	var n: int = int(dur * RATE)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	var pad: Array = [294.0, 349.0, 440.0]
	for i in n:
		var t: float = float(i) / RATE
		var v: float = 0.0
		for f in pad:
			v += sin(TAU * f * t) * 0.12 * (0.75 + 0.25 * sin(TAU * 0.25 * t))
		# Pluck every 1 s (integer second offsets — loop-safe).
		for step_t in [1.0, 3.0, 4.0, 6.0]:
			if t >= step_t and t < step_t + 0.5:
				var lt: float = t - step_t
				v += sin(TAU * 587.0 * t) * exp(-lt * 8.0) * 0.35
		s[i] = v * 0.5
	_write_wav(OUT_DIR + "music_game_high.wav", s)


## Pad synthesiser shared by the menu/low layers. LFO frequency must divide
## the loop length evenly so the amplitude also loops seamlessly.
func synthesize_pad(path: String, dur: float, freqs: Array, peak: float, lfo_hz: float, seed: int) -> void:
	var n: int = int(dur * RATE)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed
	var air: float = 0.0
	for i in n:
		var t: float = float(i) / RATE
		var lfo: float = 0.7 + 0.3 * sin(TAU * lfo_hz * t)
		var v: float = 0.0
		for j in freqs.size():
			var f: float = freqs[j]
			var amp: float = 1.0 / float(j + 2)
			v += sin(TAU * f * t + float(j) * 0.7) * amp
		air = air * 0.95 + rng.randf_range(-1.0, 1.0) * 0.05
		s[i] = (v * 0.55 + air * 0.25) * lfo * peak
	_write_wav(path, s)


func _make_collect_pop() -> void:
	# Soft "pop": 880 Hz fundamental with a quick downward sweep and a
	# 2nd harmonic; fast exponential decay. ~70 ms.
	var dur: float = 0.07
	var n: int = int(dur * RATE)
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(n)
	for i in n:
		var t: float = float(i) / RATE
		var f0: float = 920.0 - 80.0 * (t / dur)
		var env: float = exp(-t * 45.0)
		var v: float = sin(TAU * f0 * t) * 1.0 + sin(TAU * f0 * 2.0 * t) * 0.35
		samples[i] = v * env * 0.6
	_write_wav(OUT_DIR + "collect_pop.wav", samples)


func _make_collect_rare() -> void:
	# Sparkling chime: C6 + G6 + C7 partials, staggered decays. ~350 ms.
	var dur: float = 0.35
	var n: int = int(dur * RATE)
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(n)
	var partials: Array = [[1046.5, 1.0, 10.0], [1568.0, 0.6, 8.0], [2093.0, 0.4, 7.0], [3136.0, 0.2, 6.0]]
	for i in n:
		var t: float = float(i) / RATE
		var v: float = 0.0
		for p in partials:
			var f: float = p[0]
			var amp: float = p[1]
			var decay: float = p[2]
			v += sin(TAU * f * t) * amp * exp(-t * decay)
		samples[i] = v * 0.45
	_write_wav(OUT_DIR + "collect_rare.wav", samples)


func _make_collect_mote() -> void:
	# Barely-there tick for corpse motes. ~50 ms at 2.2 kHz.
	var dur: float = 0.05
	var n: int = int(dur * RATE)
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(n)
	for i in n:
		var t: float = float(i) / RATE
		samples[i] = sin(TAU * 2200.0 * t) * exp(-t * 70.0) * 0.35
	_write_wav(OUT_DIR + "collect_mote.wav", samples)


## 16-bit mono PCM WAV writer.
func _write_wav(path: String, samples: PackedFloat32Array) -> void:
	var data: PackedByteArray = PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var s: float = clampf(samples[i], -1.0, 1.0)
		var v: int = int(s * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	# RIFF header: 44 bytes + PCM data.
	var chunk_size: int = 36 + data.size()
	f.store_32(0x46464952)          # "RIFF"
	f.store_32(chunk_size)
	f.store_32(0x45564157)          # "WAVE"
	f.store_32(0x20746D66)          # "fmt "
	f.store_32(16)                  # fmt chunk size
	f.store_16(1)                   # PCM
	f.store_16(1)                   # mono
	f.store_32(RATE)
	f.store_32(RATE * 2)            # byte rate
	f.store_16(2)                   # block align
	f.store_16(16)                  # bits per sample
	f.store_32(0x61746164)          # "data"
	f.store_32(data.size())
	f.store_buffer(data)
	f.close()
	print("  wrote %s (%d samples)" % [path, samples.size()])

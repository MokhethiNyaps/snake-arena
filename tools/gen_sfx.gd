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
	print("GEN_SFX_DONE -> %s" % OUT_DIR)
	quit(0)


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

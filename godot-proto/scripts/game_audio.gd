class_name GameAudio
extends Node

# Procedural synthesized audio matching src/audio.ts.
# Uses pre-generated procedural PCM AudioStreamWAV buffers + native C++ AudioServer
# DSP buses (lowpass/bandpass/compressor) for zero per-frame GDScript DSP cost on iOS.

const SAMPLE_RATE := 22050
const MASTER_VOLUME_DB := -6.5
const GEAR_COUNT := 4.0
const POP_GAP := 0.045
const BLAST_GAP := 0.07
const SCREECH_GAP := 0.12
const CRUNCH_GAP := 0.06
const SHOT_GAP := 0.05
const SFX_POOL_SIZE := 18

var muted := false

var _engine_player: AudioStreamPlayer
var _skid_player: AudioStreamPlayer
var _nitro_player: AudioStreamPlayer
var _engine_filter: AudioEffectLowPassFilter
var _skid_filter: AudioEffectBandPassFilter
var _nitro_filter: AudioEffectBandPassFilter

var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_cursor := 0
var _streams: Dictionary = {}

var _clock := 0.0
var _last_shot := -1.0
var _last_pop := -1.0
var _last_screech := -1.0
var _last_crunch := -1.0
var _last_blast := -1.0

var _engine_freq := 42.0
var _engine_cutoff := 500.0
var _engine_gain := 0.0
var _skid_gain := 0.0
var _skid_cutoff := 700.0
var _nitro_gain := 0.0
var _nitro_cutoff := 1400.0


func setup() -> void:
	_setup_buses()
	_generate_all_streams()
	_setup_players()


func _process(delta: float) -> void:
	_clock += delta


func toggle_mute() -> void:
	muted = not muted
	AudioServer.set_bus_mute(0, muted)


func drive(dt: float, speed_fraction: float, throttle: float, slide: float, boost: float, active: bool) -> void:
	if _engine_player == null:
		return
	var gear_pos := clampf(speed_fraction, 0.0, 0.999) * GEAR_COUNT
	var gear_frac := gear_pos - floorf(gear_pos)
	var cruise := clampf(0.25 + 0.6 * gear_frac + 0.15 * speed_fraction + slide * 0.25 * throttle, 0.0, 1.2)
	var revs := lerpf(cruise, 1.45, boost * 0.85)
	var target_freq := lerpf(42.0, 150.0, revs)
	var target_cutoff := lerpf(320.0, 1500.0, clampf(throttle * 0.7 + revs * 0.4, 0.0, 1.0))
	var target_egain := (0.1 + 0.1 * throttle + 0.07 * boost) if active else 0.0
	var target_sgain := clampf(slide, 0.0, 1.2) * 0.2 if active else 0.0
	var target_scut := lerpf(500.0, 1100.0, speed_fraction)
	var target_ngain := boost * 0.2 if active else 0.0
	var target_ncut := lerpf(1100.0, 2600.0, boost)

	_engine_freq = SimMath.damp(_engine_freq, target_freq, 20.0, dt)
	_engine_cutoff = SimMath.damp(_engine_cutoff, target_cutoff, 12.5, dt)
	_engine_gain = SimMath.damp(_engine_gain, target_egain, 12.5, dt)
	_skid_gain = SimMath.damp(_skid_gain, target_sgain, 16.0, dt)
	_skid_cutoff = SimMath.damp(_skid_cutoff, target_scut, 10.0, dt)
	_nitro_gain = SimMath.damp(_nitro_gain, target_ngain, 20.0, dt)
	_nitro_cutoff = SimMath.damp(_nitro_cutoff, target_ncut, 8.0, dt)

	# Engine base wave is generated at 100 Hz
	_engine_player.pitch_scale = clampf(_engine_freq / 100.0, 0.25, 3.0)
	_engine_player.volume_db = _gain_to_db(_engine_gain)
	_engine_filter.cutoff_hz = _engine_cutoff

	_skid_player.volume_db = _gain_to_db(_skid_gain)
	_skid_filter.cutoff_hz = _skid_cutoff

	_nitro_player.volume_db = _gain_to_db(_nitro_gain)
	_nitro_filter.cutoff_hz = _nitro_cutoff


func thud(strength: float) -> void:
	_play_sfx("thud", clampf(strength, 0.1, 1.0) * 0.65, randf_range(0.9, 1.1), "Master")


func wreck(size: float, loudness: float) -> void:
	if loudness <= 0.02 or _clock - _last_pop < POP_GAP:
		return
	_last_pop = _clock
	var pitch := lerpf(1.18, 0.72, size) * randf_range(0.88, 1.12)
	_play_sfx("wreck", (0.55 + size * 0.35) * loudness, pitch, "Impacts")


func screech(_seconds: float, size: float, loudness: float) -> void:
	if loudness <= 0.03 or _clock - _last_screech < SCREECH_GAP:
		return
	_last_screech = _clock
	var pitch := lerpf(1.25, 0.68, size) * randf_range(0.9, 1.1)
	_play_sfx("screech", 0.55 * loudness, pitch, "Impacts")


func crunch(strength: float, loudness: float) -> void:
	if loudness <= 0.03 or _clock - _last_crunch < CRUNCH_GAP:
		return
	_last_crunch = _clock
	_play_sfx("crunch", (0.35 + strength * 0.3) * loudness, randf_range(0.9, 1.12), "Impacts")


func explosion(power: float, loudness: float) -> void:
	if loudness <= 0.02 or _clock - _last_blast < BLAST_GAP:
		return
	_last_blast = _clock
	var pitch := lerpf(1.12, 0.8, power) * randf_range(0.9, 1.1)
	_play_sfx("explosion", 0.95 * loudness, pitch, "Impacts")


func shot() -> void:
	if _clock - _last_shot < SHOT_GAP:
		return
	_last_shot = _clock
	_play_sfx("shot", 0.14, randf_range(0.92, 1.08), "Master")


func mine_drop() -> void:
	_play_sfx("mine_drop", 0.24, randf_range(0.94, 1.06), "Master")


func grenade_toss() -> void:
	_play_sfx("grenade_toss", 0.22, randf_range(0.92, 1.1), "Master")


func pickup(pitch_step: float) -> void:
	var scale := (660.0 + pitch_step * 40.0) / 660.0
	_play_sfx("pickup", 0.16, scale, "Master")


func nitro_ignite() -> void:
	_play_sfx("nitro_ignite", 0.85, 1.0, "Impacts")


func nitro_ready() -> void:
	_play_sfx("nitro_ready", 0.25, 1.0, "Master")


func nitro_empty() -> void:
	_play_sfx("nitro_empty", 0.22, 1.0, "Master")


func level_up() -> void:
	_play_sfx("level_up", 0.28, 1.0, "Master")


func defeat() -> void:
	_play_sfx("defeat", 0.32, 1.0, "Master")


func warning(heavy: bool) -> void:
	_play_sfx("warning_boss" if heavy else "warning_party", 0.35 if heavy else 0.24, 1.0, "Master")


func _play_sfx(key: String, linear_gain: float, pitch: float, bus_name: String) -> void:
	if linear_gain <= 0.005 or not _streams.has(key):
		return
	var p := _sfx_pool[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % SFX_POOL_SIZE
	p.stream = _streams[key]
	p.bus = bus_name
	p.volume_db = _gain_to_db(linear_gain)
	p.pitch_scale = clampf(pitch, 0.35, 3.0)
	p.play()


static func _gain_to_db(linear_gain: float) -> float:
	if linear_gain <= 0.0005:
		return -80.0
	return linear_to_db(linear_gain)


func _ensure_bus(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	return idx


func _setup_buses() -> void:
	AudioServer.set_bus_volume_db(0, MASTER_VOLUME_DB)

	var eng_idx := _ensure_bus("Engine")
	_engine_filter = AudioEffectLowPassFilter.new()
	_engine_filter.cutoff_hz = 500.0
	AudioServer.add_bus_effect(eng_idx, _engine_filter)

	var skid_idx := _ensure_bus("Skid")
	_skid_filter = AudioEffectBandPassFilter.new()
	_skid_filter.cutoff_hz = 700.0
	_skid_filter.resonance = 0.8
	AudioServer.add_bus_effect(skid_idx, _skid_filter)

	var nitro_idx := _ensure_bus("Nitro")
	_nitro_filter = AudioEffectBandPassFilter.new()
	_nitro_filter.cutoff_hz = 1400.0
	_nitro_filter.resonance = 0.6
	AudioServer.add_bus_effect(nitro_idx, _nitro_filter)

	var imp_idx := _ensure_bus("Impacts")
	var comp := AudioEffectCompressor.new()
	comp.threshold = -16.0
	comp.ratio = 9.0
	comp.attack_us = 2000.0
	comp.release_ms = 220.0
	AudioServer.add_bus_effect(imp_idx, comp)


func _setup_players() -> void:
	_engine_player = AudioStreamPlayer.new()
	_engine_player.name = "EngineLoop"
	_engine_player.stream = _streams["engine_loop"]
	_engine_player.bus = "Engine"
	_engine_player.volume_db = -80.0
	add_child(_engine_player)
	_engine_player.play()

	_skid_player = AudioStreamPlayer.new()
	_skid_player.name = "SkidLoop"
	_skid_player.stream = _streams["noise_loop"]
	_skid_player.bus = "Skid"
	_skid_player.volume_db = -80.0
	add_child(_skid_player)
	_skid_player.play()

	_nitro_player = AudioStreamPlayer.new()
	_nitro_player.name = "NitroLoop"
	_nitro_player.stream = _streams["noise_loop"]
	_nitro_player.bus = "Nitro"
	_nitro_player.volume_db = -80.0
	add_child(_nitro_player)
	_nitro_player.play(0.7)

	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "Sfx_%d" % i
		add_child(p)
		_sfx_pool.append(p)


func _generate_all_streams() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x517CC1B7

	# 1. Engine loop: sawtooth @ 100 Hz + 0.35 * square @ 50.2 Hz (2 seconds seamless)
	var eng_len := SAMPLE_RATE * 2
	var eng := PackedFloat32Array()
	eng.resize(eng_len)
	for i in eng_len:
		var t := float(i) / float(SAMPLE_RATE)
		var p1 := fposmod(t * 100.0, 1.0)
		var saw := p1 * 2.0 - 1.0
		var p2 := fposmod(t * 50.0, 1.0)
		var sq := 1.0 if p2 < 0.5 else -1.0
		eng[i] = (saw + 0.35 * sq) * 0.65
	_streams["engine_loop"] = _make_wav(eng, true)

	# 2. White noise loop (2 seconds seamless)
	var noise_len := SAMPLE_RATE * 2
	var noise := PackedFloat32Array()
	noise.resize(noise_len)
	for i in noise_len:
		noise[i] = rng.randf_range(-1.0, 1.0)
	_streams["noise_loop"] = _make_wav(noise, true)

	# 3. Thud: 0.18s lowpass noise @ 220 Hz
	_streams["thud"] = _make_wav(_synth_filtered_noise(0.18, 220.0, 140.0, false, false, rng), false)

	# 4. Shot: 0.04s highpass noise @ 2400 Hz
	_streams["shot"] = _make_wav(_synth_highpass_noise(0.045, 2400.0, rng), false)

	# 5. Pickup: 0.07s triangle @ 660 Hz
	_streams["pickup"] = _make_wav(_synth_notes([[660.0, 0.0, 0.075, 0.75, 2]]), false)

	# 6. Wreck: sine drop 170->42 + filtered noise sweep 2400->240 + metallic clatter
	var wreck_buf := _zero_buf(0.55)
	_mix_sine_drop(wreck_buf, 0.0, 0.24, 170.0, 42.0, 0.65)
	_mix_sweep(wreck_buf, 0.0, 0.34, 2400.0, 240.0, 0.42, false, rng)
	_mix_clatter(wreck_buf, 0.1, 3, 0.3, 0.14, rng)
	_streams["wreck"] = _make_wav(wreck_buf, false)

	# 7. Screech: resonant bandpass noise sweeping 1350 -> 820 Hz
	_streams["screech"] = _make_wav(_synth_screech(0.75, 1350.0, 820.0, rng), false)

	# 8. Crunch: impact drop + waveshaped crunch sweep + clatter
	var crunch_buf := _zero_buf(0.24)
	_mix_sine_drop(crunch_buf, 0.0, 0.12, 170.0, 60.0, 0.55)
	_mix_sweep(crunch_buf, 0.0, 0.14, 2400.0, 400.0, 0.45, true, rng)
	_mix_clatter(crunch_buf, 0.03, 2, 0.12, 0.12, rng)
	_streams["crunch"] = _make_wav(crunch_buf, false)

	# 9. Explosion: multi-layer crack + deep sub drop + waveshaped roar + rumble + clatter
	var exp_buf := _zero_buf(1.9)
	_mix_sweep(exp_buf, 0.0, 0.07, 7000.0, 1500.0, 0.55, true, rng)
	_mix_sine_drop(exp_buf, 0.0, 0.9, 150.0, 27.0, 0.9)
	_mix_sweep(exp_buf, 0.0, 1.2, 3600.0, 80.0, 0.8, true, rng)
	_mix_sweep(exp_buf, 0.05, 1.8, 190.0, 55.0, 0.45, false, rng)
	_mix_clatter(exp_buf, 0.2, 5, 0.7, 0.14, rng)
	_streams["explosion"] = _make_wav(exp_buf, false)

	# 10. Nitro ignite
	var ni_buf := _zero_buf(0.95)
	_mix_sine_drop(ni_buf, 0.0, 0.5, 170.0, 38.0, 0.8)
	_mix_sweep(ni_buf, 0.0, 0.45, 500.0, 7000.0, 0.45, true, rng)
	_mix_sweep(ni_buf, 0.02, 0.88, 6000.0, 900.0, 0.28, false, rng)
	_mix_notes_into(ni_buf, [[330.0, 0.0, 0.22, 0.12, 1], [495.0, 0.035, 0.22, 0.12, 1], [990.0, 0.07, 0.22, 0.12, 1]])
	_streams["nitro_ignite"] = _make_wav(ni_buf, false)

	# 11. Nitro ready: crisp square chime
	_streams["nitro_ready"] = _make_wav(_synth_notes([
		[988.0, 0.0, 0.14, 0.5, 3],
		[1319.0, 0.06, 0.14, 0.5, 3],
		[1976.0, 0.12, 0.14, 0.5, 3],
	]), false)

	# 12. Nitro empty
	var ne_buf := _synth_notes([[120.0, 0.0, 0.09, 0.55, 3]])
	_mix_sweep(ne_buf, 0.0, 0.05, 900.0, 600.0, 0.35, false, rng)
	_streams["nitro_empty"] = _make_wav(ne_buf, false)

	# 13. Level up: ascending triangle arpeggio
	_streams["level_up"] = _make_wav(_synth_notes([
		[523.0, 0.0, 0.16, 0.55, 2],
		[659.0, 0.07, 0.16, 0.55, 2],
		[784.0, 0.14, 0.16, 0.55, 2],
		[1047.0, 0.21, 0.22, 0.6, 2],
	]), false)

	# 14. Defeat: descending sawtooth chord
	_streams["defeat"] = _make_wav(_synth_notes([
		[392.0, 0.0, 0.3, 0.55, 1],
		[311.0, 0.16, 0.3, 0.55, 1],
		[233.0, 0.32, 0.3, 0.55, 1],
		[155.0, 0.48, 0.38, 0.6, 1],
	]), false)

	# 15. Warnings (party & boss)
	_streams["warning_party"] = _make_wav(_synth_notes([
		[740.0, 0.0, 0.14, 0.5, 3],
		[740.0, 0.2, 0.14, 0.5, 3],
	]), false)
	_streams["warning_boss"] = _make_wav(_synth_notes([
		[196.0, 0.0, 0.14, 0.65, 1],
		[196.0, 0.2, 0.14, 0.65, 1],
		[196.0, 0.4, 0.14, 0.65, 1],
		[196.0, 0.6, 0.16, 0.65, 1],
	]), false)

	# 16. Mine drop: metallic latch clunk + arming chirp
	var md_buf := _zero_buf(0.18)
	_mix_sine_drop(md_buf, 0.0, 0.09, 260.0, 95.0, 0.55)
	_mix_clatter(md_buf, 0.0, 2, 0.05, 0.18, rng)
	_mix_notes_into(md_buf, [[880.0, 0.05, 0.08, 0.35, 3]])
	_streams["mine_drop"] = _make_wav(md_buf, false)

	# 17. Grenade toss: hollow pneumatic pop/thump
	var gt_buf := _zero_buf(0.16)
	_mix_sine_drop(gt_buf, 0.0, 0.10, 320.0, 110.0, 0.6)
	_mix_sweep(gt_buf, 0.0, 0.11, 1400.0, 320.0, 0.35, false, rng)
	_streams["grenade_toss"] = _make_wav(gt_buf, false)


static func _zero_buf(seconds: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(int(ceil(seconds * float(SAMPLE_RATE))))
	buf.fill(0.0)
	return buf


static func _mix_sine_drop(buf: PackedFloat32Array, start_s: float, dur_s: float, f0: float, f1: float, amp: float) -> void:
	var s0 := int(start_s * float(SAMPLE_RATE))
	var count := mini(buf.size() - s0, int(dur_s * float(SAMPLE_RATE)))
	if count <= 0:
		return
	var phase := 0.0
	var log_ratio := log(maxf(1.0, f1) / maxf(1.0, f0))
	for i in count:
		var t := float(i) / float(count)
		var freq := f0 * exp(log_ratio * t)
		phase += TAU * freq / float(SAMPLE_RATE)
		var env := exp(-5.0 * t)
		buf[s0 + i] += sin(phase) * env * amp


static func _mix_sweep(buf: PackedFloat32Array, start_s: float, dur_s: float, f0: float, f1: float, amp: float, crunch_on: bool, rng: RandomNumberGenerator) -> void:
	var s0 := int(start_s * float(SAMPLE_RATE))
	var count := mini(buf.size() - s0, int(dur_s * float(SAMPLE_RATE)))
	if count <= 0:
		return
	var lp := 0.0
	var log_ratio := log(maxf(20.0, f1) / maxf(20.0, f0))
	for i in count:
		var t := float(i) / float(count)
		var cutoff := f0 * exp(log_ratio * t)
		var rc := 1.0 / (TAU * cutoff)
		var dt := 1.0 / float(SAMPLE_RATE)
		var alpha := clampf(dt / (rc + dt), 0.0, 1.0)
		var n := rng.randf_range(-1.0, 1.0)
		lp += alpha * (n - lp)
		var sample := tanh(lp * 3.0) if crunch_on else lp
		var env := exp(-4.8 * t)
		buf[s0 + i] += sample * env * amp


static func _mix_clatter(buf: PackedFloat32Array, start_s: float, hits: int, spread_s: float, amp: float, rng: RandomNumberGenerator) -> void:
	for _h in hits:
		var at := start_s + rng.randf() * spread_s
		var s0 := int(at * float(SAMPLE_RATE))
		var count := mini(buf.size() - s0, int(0.07 * float(SAMPLE_RATE)))
		if count <= 0:
			continue
		var freq := rng.randf_range(1500.0, 4100.0)
		var vol := amp * rng.randf_range(0.5, 1.5) * 2.4
		var phase := 0.0
		for i in count:
			var t := float(i) / float(count)
			phase += TAU * freq / float(SAMPLE_RATE)
			var env := exp(-6.5 * t)
			buf[s0 + i] += (sin(phase) * 0.6 + rng.randf_range(-0.4, 0.4)) * env * vol


static func _synth_filtered_noise(dur_s: float, f0: float, f1: float, crunch_on: bool, _unused: bool, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf := _zero_buf(dur_s)
	_mix_sweep(buf, 0.0, dur_s, f0, f1, 0.9, crunch_on, rng)
	return buf


static func _synth_highpass_noise(dur_s: float, cutoff: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf := _zero_buf(dur_s)
	var lp := 0.0
	var rc := 1.0 / (TAU * cutoff)
	var dt := 1.0 / float(SAMPLE_RATE)
	var alpha := clampf(dt / (rc + dt), 0.0, 1.0)
	var count := buf.size()
	for i in count:
		var t := float(i) / float(count)
		var n := rng.randf_range(-1.0, 1.0)
		lp += alpha * (n - lp)
		var hp := n - lp
		buf[i] = hp * exp(-5.5 * t) * 0.9
	return buf


static func _synth_screech(dur_s: float, f0: float, f1: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf := _zero_buf(dur_s)
	var count := buf.size()
	var y1 := 0.0
	var y2 := 0.0
	var log_ratio := log(f1 / f0)
	for i in count:
		var t := float(i) / float(count)
		var freq := f0 * exp(log_ratio * t)
		var w := TAU * freq / float(SAMPLE_RATE)
		var r := 0.94
		var x := rng.randf_range(-1.0, 1.0) * 0.25
		var y := x + 2.0 * r * cos(w) * y1 - r * r * y2
		y2 = y1
		y1 = y
		var attack := minf(1.0, (float(i) / float(SAMPLE_RATE)) / 0.05)
		var decay := exp(-3.5 * t)
		buf[i] = clampf(y * attack * decay * 0.65, -1.0, 1.0)
	return buf


static func _synth_notes(notes: Array) -> PackedFloat32Array:
	# Each note: [freq, delay_s, dur_s, amp, wave_type (0=sine,1=saw,2=tri,3=sq)]
	var max_end := 0.05
	for n in notes:
		max_end = maxf(max_end, float(n[1]) + float(n[2]) + 0.02)
	var buf := _zero_buf(max_end)
	_mix_notes_into(buf, notes)
	return buf


static func _mix_notes_into(buf: PackedFloat32Array, notes: Array) -> void:
	for n in notes:
		var freq: float = n[0]
		var s0 := int(float(n[1]) * float(SAMPLE_RATE))
		var count := mini(buf.size() - s0, int(float(n[2]) * float(SAMPLE_RATE)))
		var amp: float = n[3]
		var wave: int = n[4]
		for i in count:
			var t := float(i) / float(count)
			var p := fposmod((float(i) / float(SAMPLE_RATE)) * freq, 1.0)
			var sample := 0.0
			match wave:
				0: sample = sin(p * TAU)
				1: sample = p * 2.0 - 1.0
				2: sample = 1.0 - 4.0 * absf(p - 0.5)
				3: sample = 1.0 if p < 0.5 else -1.0
			var env := exp(-4.8 * t)
			buf[s0 + i] += sample * env * amp


static func _make_wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(tanh(samples[i]), -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav

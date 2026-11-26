extends SceneTree

# Deterministic stress benchmark for the game loop.
#
#   godot --path . --headless --fixed-fps 60 -s res://tools/bench.gd -- [frames] [seed] [start_seconds] [shot_dir]
#
# Starts a real run, gives the car a mid-game loadout, jumps the clock to
# start_seconds so the spawner fields a late-run enemy population, then drives
# a scripted run-and-drift pattern. Prints the average and worst frame cost,
# a per-subsystem breakdown (the Perf.mark() calls in main.gd), and a digest of
# the final game state.
#
# The digest is the regression check: with the same arguments it must not
# change unless a commit intentionally changes gameplay. A pure optimisation
# that changes it has altered the simulation.
#
# --headless measures script cost only. Without it the game renders for real,
# which adds draw-call and primitive counts and lets shot_dir collect a
# screenshot every 300 frames for before/after comparison. A windowed run takes
# keyboard focus, and real key presses would disturb it; a temporary
# override.cfg with `[display] window/size/no_focus=true` avoids both. Mouse
# and touch input are ignored either way.

const WARMUP_FRAMES := 240
const SHOT_INTERVAL := 300

var _main: Node
var _frames := 3000
var _seed := 1234
var _start_seconds := 420.0
var _shot_dir := ""
var _frame := 0
var _prev_tick := 0
var _frame_ms := PackedFloat64Array()
var _render_cpu := 0.0
var _draw_calls := 0.0
var _prims := 0.0
var _peak_enemies := 0
var _sum_enemies := 0
var _sum_puffs := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_frames = int(args[0])
	if args.size() > 1:
		_seed = int(args[1])
	if args.size() > 2:
		_start_seconds = float(args[2])
	if args.size() > 3:
		_shot_dir = args[3]

	# Only the scripted key presses below may steer the run: a real mouse over
	# a windowed benchmark would otherwise work the touch controls.
	Input.emulate_touch_from_mouse = false
	root.gui_disable_input = true

	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)


func _setup_run() -> void:
	seed(_seed)
	_main._start_run()
	seed(_seed)
	var levels: Dictionary = _main._levels
	for id: String in ["rich", "fan", "linger", "ash", "ember", "toxic", "gun", "mines", "grenades"]:
		levels[id] = 3
	levels["salvo"] = 1
	_main._stats = Upgrades.derive_stats(levels)
	Upgrades.apply_to_car(_main._car, _main._stats)
	_main._car_model.sync_attachments(true, true, false, true, true)
	_main._time = _start_seconds
	# Skip the war parties and bosses that were due before start_seconds.
	_main._spawner._next_war_party = ceilf(_start_seconds / 60.0) * 60.0 + 20.0
	_main._spawner._next_boss = ceilf(_start_seconds / 150.0) * 150.0 + 45.0


func _key(code: Key, down: bool) -> void:
	# Checked against the live state every frame: a windowed run that loses
	# focus has all its held keys released by the engine.
	if Input.is_key_pressed(code) == down:
		return
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)


func _process(_delta: float) -> bool:
	if _frame == 0:
		_setup_run()
	_frame += 1

	# Keep the run alive and out of menus so every frame is a gameplay frame.
	_main._hp = _main._stats.max_hp
	_main._scrap = 0.0
	if _main._phase != "playing":
		_main._set_phase("playing")

	# 7 s cycle: run straight with a weave, then a long handbrake drift.
	var t := fmod(float(_frame) / 60.0, 7.0)
	var drifting := t > 3.2
	_key(KEY_W, true)
	_key(KEY_D, drifting and t < 5.6)
	_key(KEY_A, (not drifting and t > 1.2 and t < 1.9) or t >= 5.6)
	_key(KEY_SPACE, drifting and fmod(t, 1.2) < 0.75)
	_key(KEY_E, t > 0.2 and t < 0.3)
	Input.flush_buffered_events()

	var measured := _frame - WARMUP_FRAMES
	if measured == 0:
		Perf.acc.clear()
		Perf.peak.clear()
		Perf.enabled = true
	elif measured > 0:
		Perf.end_frame()
		_frame_ms.append(float(Time.get_ticks_usec() - _prev_tick) / 1000.0)
		_render_cpu += RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()) + RenderingServer.get_frame_setup_time_cpu()
		_draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		_prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		var enemy_count: int = _main._enemies.active.size()
		_sum_enemies += enemy_count
		_peak_enemies = maxi(_peak_enemies, enemy_count)
		_sum_puffs += int(_main._smoke.count)
		if _shot_dir != "" and measured % SHOT_INTERVAL == 0:
			root.get_texture().get_image().save_png("%s/frame_%04d.png" % [_shot_dir, measured])

	_prev_tick = Time.get_ticks_usec()
	if measured >= _frames:
		_report()
		return true
	return false


func _report() -> void:
	var n := _frame_ms.size()
	var sorted := _frame_ms.duplicate()
	sorted.sort()
	var total := 0.0
	for v in sorted:
		total += v
	print("=== bench: %d frames, seed %d, start %.0fs ===" % [n, _seed, _start_seconds])
	# Headless frames run back to back, so this is the cost of a frame; windowed
	# frames are paced by vsync and only the breakdown below is meaningful.
	print("frame ms        avg %.3f  p50 %.3f  p95 %.3f  p99 %.3f  max %.3f" % [
		total / n, sorted[n / 2], sorted[int(n * 0.95)], sorted[int(n * 0.99)], sorted[n - 1],
	])
	print("render          cpu %.3f ms  draw calls %.0f  primitives %.0f  (zero when headless)" % [
		_render_cpu / n, _draw_calls / n, _prims / n,
	])
	print("load            enemies avg %.1f peak %d  puffs avg %.0f  kills %d" % [
		float(_sum_enemies) / n, _peak_enemies, float(_sum_puffs) / n, int(_main._kills),
	])

	var digest := float(_main._car.x) * 3.0 + float(_main._car.z) * 7.0 + float(_main._car.heading)
	for enemy in _main._enemies.active:
		digest += enemy.x + enemy.z * 0.5 + enemy.hp * 0.01
	var smoke: SmokeSystem = _main._smoke
	for i in smoke.count:
		digest += smoke.px[i] * 0.001 + smoke.pz[i] * 0.002
	print("state digest    %.9f" % digest)

	var names := Perf.acc.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return Perf.acc[a] > Perf.acc[b])
	for section: String in names:
		print("  %-22s %7.3f ms   peak %7.3f" % [
			section, float(Perf.acc[section]) / 1000.0 / n, float(Perf.peak.get(section, 0)) / 1000.0,
		])

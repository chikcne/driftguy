extends Node3D

# Complete Driftguy game loop ported 1:1 from src/main.ts + Gyroscope
# horizon-locked counter-rotating screen and native iOS touch + gamepad support.

const MAX_FRAME_SECONDS := 1.0 / 20.0
const FOG_START := 120.0
const FOG_END := 320.0
const SUN_DIR_GODOT := Vector3(-0.5, -0.7, -0.42) # Matches sim (-0.5, -0.7, +0.42)
const CAMERA_OFFSET := Vector3(0.0, 0.8, 0.6) # Normalized in _ready
const CAMERA_DISTANCE_SLOW := 70.0
const CAMERA_DISTANCE_FAST := 100.0
const CAMERA_LOOK_AHEAD_SECONDS := 0.45
const CAMERA_FOV_DEG := 31.5
const TILT_ZOOM_EXTRA := 11.0
const CAR_RADIUS := 1.45
const WALL_BOUNCE := 0.3
const PLANT_TWIST := 0.35
const PLANT_TWIST_LIMIT := 1.6
const PLANT_THUD_IMPULSE := 1.2
const ROOT_SOIL_PUFFS := 7
const SMOKE_PUFFS_PER_SECOND := 22.0
const SMOKE_LIFE_SECONDS := 5.5
const SMOKE_GROWTH := 1.25
const SMOKE_CARRY := 0.45
const SMOKE_FLING := 1.5
const FRONT_SMOKE_SLIP := 6.0
const DUST_PER_METRE := 0.3
const HIT_INVULNERABILITY := 0.5
const LEVEL_UP_GRACE := 0.6
const DEATH_SECONDS := 1.3
const REPAIR_DROP_CHANCE := 0.025
const CRATE_INTERVAL_MIN := 50.0
const CRATE_INTERVAL_MAX := 80.0
const CRATE_DISTANCE_MIN := 45.0
const CRATE_DISTANCE_MAX := 80.0
const CRATE_HEADING_SPREAD := 1.2
const CRATE_CLEARANCE := 2.5
const BLAST_CHAIN_DELAY := 0.09
const BOSS_BLAST_RADIUS := 11.0
const EMBER_GIB_POWER := 1.9
const RIDER_THROW_CARRY := 0.7
const RIDER_THROW_SIDE := 4.0
const HEARING_RANGE := 110.0
const TRACK_SLIP_SPEED := 2.5
const COMPOUND_BAND_SECONDS := 0.7
const NITROUS_MAX_TANKS := 6
const NITROUS_STARTING_TANKS := 2
const NITROUS_HARM_PER_TANK := 40.0
const NITROUS_SECONDS := 1.2
const NITROUS_ATTACK := 0.1
const NITROUS_FADE := 0.25
const NITROUS_PULLBACK := 6.0
const NITROUS_PULLBACK_EASE_IN := 2.2
const NITROUS_PULLBACK_EASE_OUT := 1.4
const NITROUS_FOV_DEG := 2.0
const NITROUS_FOV_KICK_DEG := 2.0
const NITROUS_SHAKE := 0.32
const NITROUS_LOOK_AHEAD := 0.12
const NITROUS_FLAME_PUFFS_PER_SECOND := 36.0
const LEVEL_UP_PICK_GUARD := 0.55


class PendingBlast:
	extends RefCounted
	var x: float
	var z: float
	var delay: float
	var damage: float
	var radius: float

	func _init(px: float, pz: float, p_delay: float, p_damage: float, p_radius: float) -> void:
		x = px
		z = pz
		delay = p_delay
		damage = p_damage
		radius = p_radius


var _car := CarBody.new()
var _stabilizer := GyroStabilizer.new()
var _spawner := EnemySystem.Spawner.new()
var _world: World
var _smoke: SmokeSystem
var _enemies: EnemySystem
var _combat: Combat
var _effects: Effects
var _gibs: GibSystem
var _tracks: SkidTracks
var _enemy_tracks: SkidTracks
var _audio: GameAudio
var _car_model: CarModel
var _camera: Camera3D
var _sun: DirectionalLight3D
var _hud: GameHud

var _contact := World.Contact.new()
var _shove := LooseSystem.ShoveResult.new()
var _pending_blasts: Array[PendingBlast] = []
var _smoke_acc := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _prev_wheel := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])

var _phase := "title"
var _levels: Dictionary = {}
var _stats: Upgrades.Stats
var _hp := 100.0
var _scrap := 0.0
var _level := 1
var _kills := 0
var _time := 0.0
var _clock := 0.0
var _track_time := 0.0
var _invulnerable := 0.0
var _shake := 0.0
var _cam_dir := CAMERA_OFFSET.normalized()
var _cam_target := Vector3.ZERO # Godot space (sim_x, y, -sim_z)
var _cam_distance := CAMERA_DISTANCE_SLOW
var _dust_acc := 0.0
var _death_timer := 0.0
var _smoke_output := 0.0
var _next_crate := 65.0
var _nitro_tanks := NITROUS_STARTING_TANKS
var _nitro_harm := 0.0
var _nitro_burn := 0.0
var _nitro_level := 0.0
var _nitro_view := 0.0
var _nitro_pull := 0.0
var _nitro_kick := 0.0
var _flame_acc := 0.0
var _pick_guard := 0.0
var _last_handbrake := false
var _last_throttle := 0.0

# Edge-triggered keyboard/gamepad state
var _prev_nitro_key := false
var _prev_confirm_pad := false
var _prev_pause_pad := false
var _prev_menu_dir := 0

var _cb_player_hit: Callable
var _cb_wreck: Callable
var _cb_bump: Callable
var _cb_scrape: Callable
var _cb_kill: Callable
var _cb_collect: Callable
var _cb_shot: Callable
var _cb_throw_pipe: Callable
var _cb_pipe_hit: Callable
var _cb_akira: Callable


func _ready() -> void:
	randomize()

	var shared_mat := StandardMaterial3D.new()
	shared_mat.vertex_color_use_as_albedo = true
	shared_mat.roughness = 0.96
	shared_mat.metallic = 0.0
	shared_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	shared_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_setup_environment()
	_setup_camera()

	_audio = GameAudio.new()
	_audio.name = "GameAudio"
	add_child(_audio)
	_audio.setup()

	_world = World.new()
	_world.name = "World"
	add_child(_world)
	_world.setup(shared_mat)

	_tracks = SkidTracks.new()
	_tracks.name = "SkidTracks"
	add_child(_tracks)
	_tracks.setup(4, 2400, Palette.SKID_MARK, 10.0, 16.0, 0.065, 0.35, 1)

	_enemy_tracks = SkidTracks.new()
	_enemy_tracks.name = "EnemySkidTracks"
	add_child(_enemy_tracks)
	_enemy_tracks.setup(0, 3200, Palette.ENEMY_SKID_MARK, 0.55, 3.0, 0.055, 0.52, 0)

	_smoke = SmokeSystem.new()
	_smoke.name = "SmokeSystem"
	add_child(_smoke)
	_smoke.setup(Palette.HAZE, FOG_START, FOG_END, SUN_DIR_GODOT.normalized())

	_enemies = EnemySystem.new()
	_enemies.name = "EnemySystem"
	add_child(_enemies)
	_enemies.setup(shared_mat)

	_combat = Combat.new()
	_combat.name = "Combat"
	add_child(_combat)
	_combat.setup(shared_mat)

	_effects = Effects.new()
	_effects.name = "Effects"
	add_child(_effects)
	_effects.setup()

	_gibs = GibSystem.new()
	_gibs.name = "GibSystem"
	add_child(_gibs)
	_gibs.setup(shared_mat)

	_car_model = CarModel.new()
	_car_model.name = "PlayerCar"
	add_child(_car_model)
	_car_model.build(shared_mat)

	_stabilizer.apply_screen_defaults()

	_hud = GameHud.new()
	_hud.name = "GameHud"
	add_child(_hud)
	_hud.setup(_stabilizer)
	_hud.start_pressed.connect(_start_run)
	_hud.retry_pressed.connect(_start_run)
	_hud.pause_pressed.connect(_toggle_pause)
	_hud.resume_pressed.connect(func() -> void: _set_phase("playing"))
	_hud.mute_pressed.connect(_toggle_mute)
	_hud.recenter_pressed.connect(func() -> void: _stabilizer.recenter())
	_hud.upgrade_picked.connect(_apply_upgrade)

	_cb_player_hit = Callable(self, "_hurt_player")
	_cb_wreck = Callable(self, "_on_enemy_wrecked")
	_cb_bump = Callable(self, "_on_enemy_bumped")
	_cb_scrape = Callable(self, "_on_enemy_scrape")
	_cb_kill = Callable(self, "_on_enemy_killed")
	_cb_collect = Callable(self, "_collect")
	_cb_shot = Callable(_audio, "shot")
	_cb_throw_pipe = Callable(_gibs, "throw_pipe")
	_cb_pipe_hit = Callable(self, "_on_pipe_hit")
	_cb_akira = Callable(self, "_on_enemy_akira")
	_world.on_spawn_cache = Callable(self, "_on_spawn_cache")
	_spawner.on_threat = Callable(self, "_on_threat")

	_reset_run()
	_snap_camera()
	_set_phase("title")


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var code: Key = event.keycode
	if code == KEY_M:
		_toggle_mute()
		return
	if code == KEY_R:
		_stabilizer.recenter()
		return
	match _phase:
		"title":
			if code == KEY_ENTER or code == KEY_KP_ENTER or code == KEY_SPACE:
				_start_run()
		"playing":
			if code == KEY_ESCAPE or code == KEY_P:
				_set_phase("paused")
		"paused":
			if code == KEY_ESCAPE or code == KEY_P or code == KEY_ENTER or code == KEY_KP_ENTER:
				_set_phase("playing")
		"levelup":
			if code == KEY_A or code == KEY_LEFT:
				_hud.move_selection(-1)
			elif code == KEY_D or code == KEY_RIGHT:
				_hud.move_selection(1)
			elif code == KEY_ENTER or code == KEY_KP_ENTER or code == KEY_SPACE:
				_hud.confirm_selection()
		"gameover":
			if code == KEY_ENTER or code == KEY_KP_ENTER or code == KEY_SPACE:
				_start_run()


func _process(delta: float) -> void:
	var dt := minf(delta, MAX_FRAME_SECONDS)
	_clock += dt
	_poll_gamepad_menus()

	match _phase:
		"title":
			_idle(dt)
		"playing":
			_simulate(dt)
		"levelup":
			_pick_guard = maxf(0.0, _pick_guard - dt)
		"paused":
			pass
		"dying":
			_death_timer -= dt
			_idle(dt)
			if _death_timer <= 0.0:
				_set_phase("gameover")
		"gameover":
			_idle(dt)

	var driving := _phase == "playing"
	_audio.drive(
		dt,
		SimMath.saturate(_car.speed / _stats.top_speed),
		_last_throttle if driving else 0.0,
		_smoke_output,
		_nitro_level,
		driving,
	)
	_hud.set_rush(_nitro_view if driving else 0.0)


func _poll_gamepad_menus() -> void:
	if Input.get_connected_joypads().is_empty():
		return
	var pad_confirm := Input.is_joy_button_pressed(0, JOY_BUTTON_A)
	var pad_pause := Input.is_joy_button_pressed(0, JOY_BUTTON_START)
	var stick_x := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var dir := 0
	if stick_x < -0.5 or Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_LEFT):
		dir = -1
	elif stick_x > 0.5 or Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_RIGHT):
		dir = 1

	var confirm_edge := pad_confirm and not _prev_confirm_pad
	var pause_edge := pad_pause and not _prev_pause_pad
	var dir_edge := dir if dir != _prev_menu_dir else 0
	_prev_confirm_pad = pad_confirm
	_prev_pause_pad = pad_pause
	_prev_menu_dir = dir

	match _phase:
		"title", "gameover":
			if confirm_edge:
				_start_run()
		"playing":
			if pause_edge:
				_set_phase("paused")
		"paused":
			if pause_edge or confirm_edge:
				_set_phase("playing")
		"levelup":
			if dir_edge != 0:
				_hud.move_selection(dir_edge)
			if confirm_edge and _pick_guard <= 0.0:
				_hud.confirm_selection()


func _toggle_pause() -> void:
	if _phase == "playing":
		_set_phase("paused")
	elif _phase == "paused":
		_set_phase("playing")


func _toggle_mute() -> void:
	_audio.toggle_mute()
	_hud.set_muted(_audio.muted)


func _set_phase(new_phase: String) -> void:
	_phase = new_phase
	_hud.show_phase(new_phase)
	if new_phase == "gameover":
		_hud.show_game_over_stats(_time, _kills, _level)


func _start_run() -> void:
	_reset_run()
	_snap_camera()
	_set_phase("playing")


func _reset_run() -> void:
	_levels = Upgrades.empty_levels()
	_stats = Upgrades.derive_stats(_levels)
	Upgrades.apply_to_car(_car, _stats)
	_hp = _stats.max_hp
	_scrap = 0.0
	_level = 1
	_kills = 0
	_time = 0.0
	_invulnerable = 0.0
	_shake = 0.0
	_pending_blasts.clear()
	_next_crate = randf_range(CRATE_INTERVAL_MIN, CRATE_INTERVAL_MAX)
	_nitro_tanks = NITROUS_STARTING_TANKS
	_nitro_harm = 0.0
	_nitro_burn = 0.0
	_nitro_level = 0.0
	_nitro_view = 0.0
	_nitro_pull = 0.0
	_nitro_kick = 0.0
	_flame_acc = 0.0
	_dust_acc = 0.0
	_smoke_output = 0.0
	_smoke_acc.fill(0.0)

	_car.reset()
	_enemies.clear()
	_spawner.reset()
	_combat.clear()
	_effects.clear()
	_gibs.clear()
	_track_time = 0.0
	_tracks.set_time(0.0)
	_tracks.clear_tracks()
	_enemy_tracks.set_time(0.0)
	_enemy_tracks.clear_tracks()
	_smoke.clear()
	_world.reset_world()
	_world.update_around(0.0, 0.0)
	_remember_wheels()

	_car_model.visible = true
	_car_model.sync_attachments(false, false, false)
	_hud.set_loadout(_levels)
	_hud.set_nitro(_nitro_tanks, NITROUS_MAX_TANKS, 0.0, false)
	_hud.set_frame(_hp, _stats.max_hp, 0.0, _level, 0.0, 0, 0.0, 0.0, Engine.get_frames_per_second())


func _idle(dt: float) -> void:
	_track_time += dt
	_tracks.set_time(_track_time)
	_enemy_tracks.set_time(_track_time)
	_world.step_world(dt, _car.x, _car.z)
	_effects.update_effects(dt)
	_gibs.update_gibs(dt, _smoke)
	_update_smoke(dt)
	_update_car_visuals(dt)
	_update_camera(dt)
	_enemies.render_all(_clock)
	_combat.render_all(_clock)


func _simulate(dt: float) -> void:
	_time += dt
	_track_time += dt
	_tracks.set_time(_track_time)
	_enemy_tracks.set_time(_track_time)
	_invulnerable -= dt

	# Gather controls from Gyro + Touch + Keyboard + Gamepad
	var key_left := Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)
	var key_right := Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)
	var key_hold_left := Input.is_key_pressed(KEY_Q)
	var key_hold_right := false # E is nitrous!
	var key_throttle := Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)
	var key_brake := Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)
	var key_handbrake := Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_SHIFT)
	var key_nitro := Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_N) or Input.is_key_pressed(KEY_F)

	var pad_connected := not Input.get_connected_joypads().is_empty()
	var pad_steer := 0.0
	var pad_throttle := 0.0
	var pad_brake := 0.0
	var pad_handbrake := false
	var pad_nitro := false
	if pad_connected:
		var sx := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
		if absf(sx) > 0.12:
			pad_steer = clampf((absf(sx) - 0.12) / 0.88, 0.0, 1.0) * signf(sx)
		pad_throttle = maxf(0.0, Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT))
		pad_brake = maxf(0.0, Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT))
		pad_handbrake = Input.is_joy_button_pressed(0, JOY_BUTTON_B) or Input.is_joy_button_pressed(0, JOY_BUTTON_X) or Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER)
		pad_nitro = Input.is_joy_button_pressed(0, JOY_BUTTON_A)

	_stabilizer.update(dt, key_left, key_right, key_hold_left, key_hold_right)

	var key_steer := (1.0 if key_right else 0.0) - (1.0 if key_left else 0.0)
	var steer := pad_steer
	if absf(steer) <= 0.01:
		if _stabilizer.gyro_enabled and not _stabilizer.has_hardware_imu:
			steer = _stabilizer.steer_output
		elif absf(key_steer) > 0.01:
			steer = key_steer
		else:
			steer = _stabilizer.steer_output
	var brake := maxf(pad_brake, 1.0 if (_hud.touch_brake or key_brake) else 0.0)
	var handbrake := _hud.touch_handbrake or key_handbrake or pad_handbrake
	var throttle := pad_throttle
	if brake <= 0.0 and (_hud.auto_throttle or key_throttle):
		throttle = maxf(throttle, 1.0)

	var nitro_pressed_now := key_nitro or pad_nitro
	var nitro_trigger := (nitro_pressed_now and not _prev_nitro_key) or _hud.consume_touch_nitro()
	_prev_nitro_key = nitro_pressed_now
	var boost := _update_nitrous(dt, nitro_trigger)

	_last_handbrake = handbrake
	_last_throttle = throttle

	_car.step(dt, throttle, brake, steer, handbrake, boost)
	_collide_car_with_world()
	_world.update_around(_car.x, _car.z)

	_emit_tyre_smoke(dt)
	_emit_exhaust_flames(dt)
	_spawner.update(dt, _time, _car, _enemies)
	_enemies.update_enemies(
		dt,
		_car,
		_stats,
		_world,
		_smoke,
		_spawner.damage_scale(_time),
		_cb_player_hit,
		_cb_wreck,
		_cb_bump,
		_cb_scrape,
		_cb_kill,
		_cb_throw_pipe,
		_enemy_tracks,
		_track_time,
		_cb_akira,
	)
	_world.step_world(dt, _car.x, _car.z)
	_combat.update_gun(dt, _car, _stats, _enemies, _cb_shot)
	_enemies.sweep_dead(_cb_wreck, _cb_kill)
	_update_blasts(dt)
	_gather_nitrous()
	_update_crates(dt)
	_combat.update_pickups(dt, _car, _stats.magnet_radius, _cb_collect)

	_effects.update_effects(dt)
	_gibs.update_gibs(dt, _smoke, _car, _cb_pipe_hit)
	_update_smoke(dt)
	_update_car_visuals(dt)
	_update_camera(dt)
	_enemies.render_all(_clock)
	_combat.render_all(_clock)
	_tracks.flush()
	_enemy_tracks.flush()

	var needed := Upgrades.scrap_needed(_level)
	_hud.set_frame(
		_hp,
		_stats.max_hp,
		_scrap / needed,
		_level,
		_time,
		_kills,
		_car.speed * 3.6,
		_smoke_output,
		Engine.get_frames_per_second(),
	)
	_hud.set_enemy_indicators(_enemies.active, _spawner.threats, _combat.get_pickups(), _car, _camera)
	_hud.set_threats(_spawner.threats, _stabilizer.display_roll)
	var nitro_fill := 0.0
	if _nitro_burn > 0.0:
		nitro_fill = _nitro_burn / NITROUS_SECONDS
	elif _nitro_tanks >= NITROUS_MAX_TANKS:
		nitro_fill = 1.0
	else:
		nitro_fill = _nitro_harm / NITROUS_HARM_PER_TANK
	_hud.set_nitro(_nitro_tanks, NITROUS_MAX_TANKS, nitro_fill, _nitro_burn > 0.0)

	if _hp <= 0.0:
		_die()
	elif _scrap >= needed:
		_scrap -= needed
		_level += 1
		_audio.level_up()
		_hud.open_level_up(Upgrades.roll_choices(_levels, 3), _levels)
		_pick_guard = LEVEL_UP_PICK_GUARD
		_set_phase("levelup")


func _update_nitrous(dt: float, trigger: bool) -> float:
	if trigger and _nitro_burn <= 0.0:
		if _nitro_tanks > 0:
			_ignite_nitrous()
		else:
			_audio.nitro_empty()
	if _nitro_burn <= 0.0:
		_nitro_level = 0.0
		return 0.0
	_nitro_burn = maxf(0.0, _nitro_burn - dt)
	var burned := NITROUS_SECONDS - _nitro_burn
	_nitro_level = minf(SimMath.saturate(burned / NITROUS_ATTACK), SimMath.saturate(_nitro_burn / NITROUS_FADE))
	return _nitro_level


func _ignite_nitrous() -> void:
	var fx := sin(_car.heading)
	var fz := cos(_car.heading)
	var ex := _car.x - fx * CarModel.EXHAUST_REAR
	var ez := _car.z - fz * CarModel.EXHAUST_REAR
	_nitro_tanks -= 1
	_nitro_burn = NITROUS_SECONDS
	_nitro_kick = 1.0
	_shake = maxf(_shake, 0.6)
	_effects.spawn_ring(ex, ez, 8.0)
	_gibs.sparks(ex, DesertTerrain.ground_height(ex, ez) + CarModel.EXHAUST_HEIGHT, ez, 14, 13.0, _car.vx - fx * 14.0, _car.vz - fz * 14.0)
	_smoke.shockwave(ex, ez, 9.0, 7.0)
	_audio.nitro_ignite()
	_hud.kick_rush()
	_haptic(220)


func _gather_nitrous() -> void:
	var harm := _enemies.take_harm_dealt()
	if _nitro_tanks >= NITROUS_MAX_TANKS:
		_nitro_harm = 0.0
		return
	_nitro_harm += harm
	while _nitro_harm >= NITROUS_HARM_PER_TANK and _nitro_tanks < NITROUS_MAX_TANKS:
		_nitro_harm -= NITROUS_HARM_PER_TANK
		_nitro_tanks += 1
		_audio.nitro_ready()
	if _nitro_tanks >= NITROUS_MAX_TANKS:
		_nitro_harm = 0.0


func _emit_exhaust_flames(dt: float) -> void:
	if _nitro_level <= 0.0:
		return
	var fx := sin(_car.heading)
	var fz := cos(_car.heading)
	_flame_acc += NITROUS_FLAME_PUFFS_PER_SECOND * _nitro_level * dt
	while _flame_acc >= 1.0:
		_flame_acc -= 1.0
		var side := -CarModel.EXHAUST_HALF_SPAN if randf() < 0.5 else CarModel.EXHAUST_HALF_SPAN
		var back := CarModel.EXHAUST_REAR + randf_range(0.4, 1.6)
		var x := _car.x - fx * back + fz * side
		var z := _car.z - fz * back - fx * side
		_smoke.emit(
			SmokeSystem.PUFF_FIRE,
			x, DesertTerrain.ground_height(x, z) + CarModel.EXHAUST_HEIGHT + 0.1, z,
			_car.vx * 0.55 - fx * 6.0 + SimMath.rand_signed(1.2),
			randf_range(0.2, 1.4),
			_car.vz * 0.55 - fz * 6.0 + SimMath.rand_signed(1.2),
			randf_range(0.3, 0.5), 1.4, randf_range(0.22, 0.42), 0.8, 2.5,
		)


func _collide_car_with_world() -> void:
	_plough_through_plants()
	if not _world.resolve(_car, CAR_RADIUS, _contact).hit:
		return
	var into := _car.vx * _contact.nx + _car.vz * _contact.nz
	if into >= 0.0:
		return
	_car.vx -= (1.0 + WALL_BOUNCE) * into * _contact.nx
	_car.vz -= (1.0 + WALL_BOUNCE) * into * _contact.nz
	_car.yaw_rate *= 0.6
	var impact := -into
	if impact > 5.0:
		_shake = maxf(_shake, SimMath.saturate(impact / 25.0))
		_audio.thud(impact / 25.0)
		_haptic(100)


func _plough_through_plants() -> void:
	var spd := sqrt(_car.vx * _car.vx + _car.vz * _car.vz)
	var dir_x := _car.vx / spd if spd > 0.01 else 0.0
	var dir_z := _car.vz / spd if spd > 0.01 else 0.0
	var imp := _world.shove(_car, CAR_RADIUS, 1.0, _shove).impulse
	if imp <= 0.0:
		return
	if _shove.torn > 0:
		_burst_soil(_shove.x, _shove.z, dir_x * spd, dir_z * spd)
	var off_x := _shove.x - _car.x
	var off_z := _shove.z - _car.z
	var twist := (off_x * dir_z - off_z * dir_x) * imp * PLANT_TWIST
	_car.yaw_rate += clampf(twist, -PLANT_TWIST_LIMIT, PLANT_TWIST_LIMIT)
	if imp > PLANT_THUD_IMPULSE:
		_shake = maxf(_shake, SimMath.saturate(imp / 14.0))
		_audio.thud(imp / 10.0)
		_haptic(80)


func _burst_soil(x: float, z: float, vx: float, vz: float) -> void:
	var gnd := DesertTerrain.ground_height(x, z)
	for _i in ROOT_SOIL_PUFFS:
		_smoke.emit(
			SmokeSystem.PUFF_DUST,
			x + SimMath.rand_signed(0.6), gnd + randf_range(0.1, 0.5), z + SimMath.rand_signed(0.6),
			vx * 0.3 + SimMath.rand_signed(3.0), randf_range(1.5, 4.5), vz * 0.3 + SimMath.rand_signed(3.0),
			randf_range(0.5, 0.9), 1.1, randf_range(0.9, 1.6), 0.6, 0.2,
		)
	_audio.crunch(0.7, 0.8)


func _wheel_pos(index: int) -> Vector2:
	var fx := sin(_car.heading)
	var fz := cos(_car.heading)
	var along := CarBody.AXLE_FRONT if index < 2 else -CarBody.AXLE_REAR
	var across := -CarBody.HALF_TRACK if index % 2 == 0 else CarBody.HALF_TRACK
	return Vector2(_car.x + fx * along + fz * across, _car.z + fz * along - fx * across)


func _remember_wheels() -> void:
	for w in 4:
		var p := _wheel_pos(w)
		_prev_wheel[w * 2] = p.x
		_prev_wheel[w * 2 + 1] = p.y


func _pick_smoke_kind() -> int:
	var owned: Array[int] = []
	if _levels["ash"] > 0:
		owned.append(SmokeSystem.PUFF_ASH)
	if _levels["ember"] > 0:
		owned.append(SmokeSystem.PUFF_EMBER)
	if _levels["toxic"] > 0:
		owned.append(SmokeSystem.PUFF_TOXIC)
	if owned.is_empty():
		return SmokeSystem.PUFF_WHITE
	return owned[int(floor(_time / COMPOUND_BAND_SECONDS)) % owned.size()]


func _emit_tyre_smoke(dt: float) -> void:
	var rear_int := _car.smoke_intensity()
	var front_int := SimMath.saturate((_car.front_slip_speed - FRONT_SMOKE_SLIP) / 10.0) * 0.4
	_smoke_output = SimMath.damp(_smoke_output, rear_int / 1.2, 8.0, dt)
	var fx := sin(_car.heading)
	var fz := cos(_car.heading)

	for w in 4:
		var spot := _wheel_pos(w)
		var from_x := _prev_wheel[w * 2]
		var from_z := _prev_wheel[w * 2 + 1]
		var intensity := front_int if w < 2 else rear_int
		var slip_spd := _car.front_slip_speed if w < 2 else _car.rear_slip_speed
		_tracks.mark(w, spot.x, spot.y, slip_spd > TRACK_SLIP_SPEED or (w >= 2 and _car.burnout > 0.3))

		if intensity > 0.04:
			_smoke_acc[w] += SMOKE_PUFFS_PER_SECOND * intensity * _stats.smoke_rate * dt
			var n := int(floor(_smoke_acc[w]))
			_smoke_acc[w] -= float(n)
			for i in n:
				var t := (float(i) + randf()) / float(n)
				var sx := lerpf(from_x, spot.x, t)
				var sz := lerpf(from_z, spot.y, t)
				var fling := SMOKE_FLING + _car.burnout * 5.0 + minf(4.0, slip_spd * 0.3)
				var spill := (-1.0 if w % 2 == 0 else 1.0) * randf_range(0.2, 1.4)
				_smoke.emit(
					_pick_smoke_kind(),
					sx, DesertTerrain.ground_height(sx, sz) + 0.35, sz,
					_car.vx * SMOKE_CARRY - fx * fling + fz * spill + SimMath.rand_signed(0.6),
					randf_range(1.0, 2.6),
					_car.vz * SMOKE_CARRY - fz * fling - fx * spill + SimMath.rand_signed(0.6),
					randf_range(0.7, 1.0),
					SMOKE_GROWTH * _stats.smoke_spread * randf_range(0.85, 1.15),
					SMOKE_LIFE_SECONDS * _stats.smoke_life * randf_range(0.8, 1.2),
					0.9, 1.0,
				)
		_prev_wheel[w * 2] = spot.x
		_prev_wheel[w * 2 + 1] = spot.y

	_dust_acc += _car.speed * DUST_PER_METRE * dt
	while _dust_acc >= 1.0:
		_dust_acc -= 1.0
		var side := -CarBody.HALF_TRACK if randf() < 0.5 else CarBody.HALF_TRACK
		var dx := _car.x - fx * CarBody.AXLE_REAR + fz * side
		var dz := _car.z - fz * CarBody.AXLE_REAR - fx * side
		_smoke.emit(
			SmokeSystem.PUFF_DUST,
			dx, DesertTerrain.ground_height(dx, dz) + 0.25, dz,
			_car.vx * 0.25 + SimMath.rand_signed(0.8), randf_range(0.5, 1.4), _car.vz * 0.25 + SimMath.rand_signed(0.8),
			0.45, 0.95, randf_range(1.0, 1.6), 0.4, 0.2,
		)


func _on_threat(threat: EnemySystem.Threat) -> void:
	_audio.warning(threat.kind == "boss")


func _hurt_player(enemy: EnemySystem.Enemy, damage: float, closing_speed: float) -> void:
	_shake = maxf(_shake, 0.22 + SimMath.saturate(closing_speed / 30.0) * 0.45)
	_audio.thud(0.35 + SimMath.saturate(closing_speed / 30.0) * 0.35 + enemy.spec.mass * 0.15)
	if damage <= 0.0 or _invulnerable > 0.0:
		return
	_invulnerable = HIT_INVULNERABILITY
	_hp -= damage
	_hud.flash_damage()
	_haptic(180)


func _on_pipe_hit(_enemy: Variant, damage: float, impact_speed: float, hx: float, _hy: float, hz: float) -> void:
	_shake = maxf(_shake, 0.18 + SimMath.saturate(impact_speed / 35.0) * 0.22)
	_audio.crunch(0.45, _loudness_at(hx, hz))
	if damage <= 0.0 or _invulnerable > 0.0:
		return
	_invulnerable = HIT_INVULNERABILITY
	_hp -= damage
	_hud.flash_damage()
	_haptic(120)


func _on_enemy_wrecked(enemy: EnemySystem.Enemy) -> void:
	_audio.screech(enemy.wreck, SimMath.saturate(enemy.spec.radius / 3.6), _loudness_at(enemy.x, enemy.z))
	if enemy.spec.kind != "bike":
		return
	var away := -enemy.wreck_side * RIDER_THROW_SIDE
	var fx := sin(enemy.heading)
	var fz := cos(enemy.heading)
	_gibs.throw_rider(
		enemy.x, enemy.z, enemy.heading,
		enemy.vx * RIDER_THROW_CARRY + fz * away + enemy.knock_x,
		randf_range(5.0, 8.0),
		enemy.vz * RIDER_THROW_CARRY - fx * away + enemy.knock_z,
	)


func _on_enemy_bumped(enemy: EnemySystem.Enemy, strength: float) -> void:
	var y := DesertTerrain.ground_height(enemy.x, enemy.z) + 0.8
	_gibs.sparks(enemy.x, y, enemy.z, 3 + int(round(strength * 4.0)), 12.0, enemy.vx, enemy.vz)
	_audio.crunch(strength, _loudness_at(enemy.x, enemy.z))


func _on_enemy_scrape(enemy: EnemySystem.Enemy) -> void:
	var sx := enemy.x
	var sz := enemy.z
	if enemy.akira_timer > 0.0:
		var fx := sin(enemy.heading)
		var fz := cos(enemy.heading)
		var side := enemy.akira_dir * 0.55
		sx = enemy.x - fx * 0.35 + fz * side
		sz = enemy.z - fz * 0.35 - fx * side
	_gibs.sparks(sx, DesertTerrain.ground_height(sx, sz) + 0.2, sz, 2, 7.0, enemy.vx, enemy.vz)


func _on_enemy_akira(enemy: EnemySystem.Enemy) -> void:
	_audio.screech(enemy.akira_duration, 0.14, _loudness_at(enemy.x, enemy.z) * 0.45)


func _on_enemy_killed(enemy: EnemySystem.Enemy) -> void:
	_kills += 1
	var spec := enemy.spec
	var pieces := mini(10, int(ceil(spec.scrap / 3.0)))
	_combat.drop_pickup("scrap", enemy.x, enemy.z, pieces, spec.scrap / float(pieces))
	if randf() < REPAIR_DROP_CHANCE * (1.0 + spec.mass * 2.0):
		_combat.drop_pickup("repair", enemy.x, enemy.z, 1, Combat.REPAIR_DROP_VALUE)

	var y := DesertTerrain.ground_height(enemy.x, enemy.z) + 1.0
	var ember := enemy.ember_timer > 0.0 and _stats.ember_damage > 0.0
	var boss := spec.kind == "rig"
	var sz := SimMath.saturate(spec.radius / 3.6)
	_effects.spawn_blast(enemy.x, y, enemy.z, spec.radius * 1.6)
	_gibs.burst(
		spec.kind, enemy.x, enemy.z, enemy.heading, enemy.vx, enemy.vz,
		enemy.knock_x, enemy.knock_z, EMBER_GIB_POWER if ember else 1.0, ember,
	)
	_gibs.sparks(enemy.x, y, enemy.z, (14 if ember else 5) + int(round(spec.radius * 2.0)), 24.0 if ember else 15.0, enemy.vx, enemy.vz)
	var puff_count := 3 + int(round(spec.radius * 2.0))
	for i in puff_count:
		_smoke.emit(
			SmokeSystem.PUFF_FIRE if i % 3 == 0 else SmokeSystem.PUFF_SOOT,
			enemy.x + SimMath.rand_signed(spec.radius), y, enemy.z + SimMath.rand_signed(spec.radius),
			enemy.vx * 0.3 + SimMath.rand_signed(3.0), randf_range(2.0, 5.0), enemy.vz * 0.3 + SimMath.rand_signed(3.0),
			randf_range(0.6, 1.1) * (0.7 + spec.radius * 0.3), 1.6, randf_range(0.9, 1.8), 0.85, 2.0,
		)
	if ember:
		_pending_blasts.append(PendingBlast.new(enemy.x, enemy.z, BLAST_CHAIN_DELAY, _stats.ember_damage, _stats.ember_radius))
	elif boss:
		_fireball(enemy.x, enemy.z, BOSS_BLAST_RADIUS)
	else:
		_audio.wreck(sz, _loudness_at(enemy.x, enemy.z))
		_shake = maxf(_shake, (0.12 + 0.3 * sz) * _nearness_at(enemy.x, enemy.z))


func _nearness_at(x: float, z: float) -> float:
	return SimMath.saturate(1.0 - sqrt((x - _car.x) * (x - _car.x) + (z - _car.z) * (z - _car.z)) / 60.0)


func _loudness_at(x: float, z: float) -> float:
	var dx := x - _cam_target.x
	var dz := z - (-_cam_target.z)
	var fade := SimMath.saturate(1.0 - sqrt(dx * dx + dz * dz) / HEARING_RANGE)
	return fade * fade


func _update_blasts(dt: float) -> void:
	var detonated := false
	for i in range(_pending_blasts.size() - 1, -1, -1):
		var b := _pending_blasts[i]
		b.delay -= dt
		if b.delay > 0.0:
			continue
		_pending_blasts.remove_at(i)
		_detonate(b.x, b.z, b.radius, b.damage)
		detonated = true
	if detonated:
		_enemies.sweep_dead(_cb_wreck, _cb_kill)


func _detonate(x: float, z: float, radius: float, damage: float) -> void:
	_fireball(x, z, radius)
	if damage > 0.0:
		_enemies.hurt_area(x, z, radius, damage)


func _fireball(x: float, z: float, radius: float) -> void:
	var y := DesertTerrain.ground_height(x, z) + 1.2
	var near := _nearness_at(x, z)
	_effects.spawn_blast(x, y, z, radius)
	_effects.spawn_blast(x, y + 0.6, z, radius * 0.55)
	_effects.spawn_ring(x, z, radius * 1.7)
	_gibs.sparks(x, y, z, 16, 30.0, 0.0, 0.0)
	_smoke.shockwave(x, z, radius * 2.4, 16.0)
	for _i in 9:
		_smoke.emit(
			SmokeSystem.PUFF_FIRE,
			x + SimMath.rand_signed(radius * 0.5), y, z + SimMath.rand_signed(radius * 0.5),
			SimMath.rand_signed(7.0), randf_range(2.0, 7.0), SimMath.rand_signed(7.0),
			randf_range(1.0, 1.8), 3.0, randf_range(0.4, 0.8), 0.9, 2.5,
		)
	for _i in 4:
		_smoke.emit(
			SmokeSystem.PUFF_SOOT,
			x + SimMath.rand_signed(radius * 0.3), y + 1.0, z + SimMath.rand_signed(radius * 0.3),
			SimMath.rand_signed(2.0), randf_range(5.0, 9.0), SimMath.rand_signed(2.0),
			randf_range(1.0, 1.5), 2.2, randf_range(1.4, 2.2), 0.85, 2.5,
		)
	_audio.explosion(SimMath.saturate(radius / 10.0), _loudness_at(x, z))
	_shake = maxf(_shake, 0.75 * near)
	if near > 0.25:
		_haptic(180)


func _update_crates(dt: float) -> void:
	_next_crate -= dt
	if _next_crate > 0.0:
		return
	_next_crate = randf_range(CRATE_INTERVAL_MIN, CRATE_INTERVAL_MAX)
	var moving := sqrt(_car.vx * _car.vx + _car.vz * _car.vz) > 1.0
	var heading := atan2(_car.vx, _car.vz) + SimMath.rand_signed(CRATE_HEADING_SPREAD) if moving else randf() * TAU
	var dist := randf_range(CRATE_DISTANCE_MIN, CRATE_DISTANCE_MAX)
	var spot := { "x": _car.x + sin(heading) * dist, "z": _car.z + cos(heading) * dist }
	_world.resolve(spot, CRATE_CLEARANCE, _contact)
	_combat.place_pickup("repair", spot["x"], spot["z"], Combat.REPAIR_CRATE_VALUE)


func _on_spawn_cache(bx: float, bz: float) -> void:
	_combat.place_pickup_cluster("scrap", bx, bz, Combat.BARREL_SCRAP_PIECES, 1.0)


func _collect(kind: String, value: float) -> void:
	if kind == "scrap":
		_scrap += value * Combat.SCRAP_XP_MULTIPLIER
		_audio.pickup(minf(8.0, value))
	else:
		_hp = minf(_stats.max_hp, _hp + value)
		_audio.level_up()


func _apply_upgrade(upgrade: Upgrades.UpgradeDef) -> void:
	if _phase != "levelup":
		return
	_levels[upgrade.id] = int(_levels[upgrade.id]) + 1
	_stats = Upgrades.derive_stats(_levels)
	Upgrades.apply_to_car(_car, _stats)
	if Upgrades.HEAL_ON_PICK.has(upgrade.id):
		_hp = minf(_stats.max_hp, _hp + float(Upgrades.HEAL_ON_PICK[upgrade.id]))
	_invulnerable = LEVEL_UP_GRACE
	_car_model.sync_attachments(_levels["gun"] > 0, _levels["fan"] > 0, _levels["ram"] > 0)
	_hud.set_loadout(_levels)
	_set_phase("playing")


func _die() -> void:
	_death_timer = DEATH_SECONDS
	_detonate(_car.x, _car.z, 9.0, 0.0)
	_car_model.visible = false
	_car.vx = 0.0
	_car.vz = 0.0
	_car.yaw_rate = 0.0
	_shake = 1.0
	_nitro_burn = 0.0
	_nitro_level = 0.0
	_smoke_output = 0.0
	_audio.defeat()
	_haptic(350)
	_set_phase("dying")


func _update_smoke(dt: float) -> void:
	_smoke.update_smoke(
		dt,
		_clock,
		_car.x,
		_car.z,
		_car.vx,
		_car.vz,
		sin(_car.heading),
		cos(_car.heading),
		_stats.fan_power,
		_stats.fan_range,
	)


func _update_car_visuals(dt: float) -> void:
	var slope := DesertTerrain.sample_slope(_car.x, _car.z, _car.heading, CarBody.AXLE_FRONT, CarBody.HALF_TRACK)
	_car_model.update_visuals(
		_car,
		slope.x,
		slope.y,
		slope.z,
		_last_handbrake,
		_nitro_level,
		_combat.turret_angle,
		_clock,
		dt,
	)


func _snap_camera() -> void:
	var h := DesertTerrain.ground_height(_car.x, _car.z)
	_cam_target = Vector3(_car.x, h, -_car.z)
	_cam_distance = CAMERA_DISTANCE_SLOW
	_nitro_view = 0.0
	_nitro_pull = 0.0
	_nitro_kick = 0.0
	_update_camera(0.0)


func _update_camera(dt: float) -> void:
	var speed_fraction := SimMath.saturate(_car.speed / _stats.top_speed)
	_nitro_view = SimMath.damp(_nitro_view, _nitro_level, 9.0 if _nitro_level > _nitro_view else 2.6, dt)
	_nitro_pull = SimMath.damp(_nitro_pull, _nitro_level, NITROUS_PULLBACK_EASE_IN if _nitro_level > _nitro_pull else NITROUS_PULLBACK_EASE_OUT, dt)
	_nitro_kick = maxf(0.0, _nitro_kick - dt * 3.2)

	var look_ahead := CAMERA_LOOK_AHEAD_SECONDS + NITROUS_LOOK_AHEAD * _nitro_view
	var aim_x := _car.x + _car.vx * look_ahead
	var aim_z := _car.z + _car.vz * look_ahead
	var aim_y := DesertTerrain.ground_height(_car.x, _car.z)

	if dt > 0.0:
		_cam_target.x = SimMath.damp(_cam_target.x, aim_x, 5.0, dt)
		_cam_target.z = SimMath.damp(_cam_target.z, -aim_z, 5.0, dt)
		_cam_target.y = SimMath.damp(_cam_target.y, aim_y, 3.0, dt)
		_cam_distance = SimMath.damp(_cam_distance, lerpf(CAMERA_DISTANCE_SLOW, CAMERA_DISTANCE_FAST, speed_fraction), 1.5, dt)
	else:
		_cam_target = Vector3(aim_x, aim_y, -aim_z)
		_cam_distance = CAMERA_DISTANCE_SLOW

	_shake = maxf(NITROUS_SHAKE * _nitro_level, _shake - dt * 2.2)
	var jolt := _shake * _shake * 1.6
	var shake_vec := Vector3(
		SimMath.rand_signed(jolt),
		SimMath.rand_signed(jolt),
		SimMath.rand_signed(jolt),
	) if jolt > 0.001 else Vector3.ZERO

	var tilt_zoom := TILT_ZOOM_EXTRA * absf(sin(_stabilizer.display_roll)) if _hud.zoom_compensation else 0.0
	var distance := _cam_distance + NITROUS_PULLBACK * _nitro_pull + tilt_zoom

	_camera.fov = CAMERA_FOV_DEG + NITROUS_FOV_DEG * _nitro_view + NITROUS_FOV_KICK_DEG * _nitro_kick * _nitro_kick
	_camera.position = _cam_target + _cam_dir * distance + shake_vec
	_camera.look_at(_cam_target, Vector3.UP)
	# Counter-rotate the 3D camera around its view axis so the desert stays level with gravity
	_camera.rotate_object_local(Vector3.BACK, -_stabilizer.display_roll)


func _haptic(ms: int) -> void:
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Palette.HAZE
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.86, 0.8, 0.98)
	env.ambient_light_energy = 0.72
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Palette.HAZE
	env.fog_light_energy = 1.0
	env.fog_depth_begin = FOG_START
	env.fog_depth_end = FOG_END
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.15

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.light_color = Color(1.0, 0.9, 0.74)
	_sun.light_energy = 1.05
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 190.0
	_sun.shadow_bias = 0.05
	_sun.shadow_normal_bias = 1.2
	add_child(_sun)
	_sun.look_at_from_position(-SUN_DIR_GODOT.normalized() * 60.0, Vector3.ZERO, Vector3.UP)


func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.fov = CAMERA_FOV_DEG
	_camera.near = 2.0
	_camera.far = 700.0
	_camera.current = true
	add_child(_camera)

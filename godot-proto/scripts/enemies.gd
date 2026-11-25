class_name EnemySystem
extends Node3D

# Direct 1:1 port of src/enemies.ts: all 5 enemy archetypes, rider animations,
# smoke damage/blindness/compounds, skidding wrecks, enemy-enemy bumping,
# ramming, and progressive Spawner with War Parties & War Rig bosses.

const MAX_ENEMIES := 200
const SMOKE_THRESHOLD := 0.2
const SMOKE_FULL_DENSITY := 3.0
const SMOKE_DENSITY_CAP := 2.5
const KIND_SHARE_THRESHOLD := 0.25
const ASH_LINGER := 0.5
const EMBER_LINGER := 1.2
const TOXIC_LINGER := 3.0
const HIT_COOLDOWN := 1.0
const BLINDED_SPEED_FACTOR := 0.72
const BLINDED_LINGER := 0.25
const RAM_COOLDOWN := 0.4
const RAM_MIN_SPEED := 8.0
const CAR_CIRCLE_OFFSET := 1.05
const CAR_CIRCLE_RADIUS := 1.15
const DUST_INTERVAL := 0.3
const DUST_VISIBLE_RANGE := 75.0
const FLANK_DISTANCE := 16.0
const STIR_RATE := 1.6
const BLAST_KNOCK := 11.0
const KNOCK_FADE := 5.0
const BLIND_RISE := 4.0
const BLIND_FADE := 1.3
const REEL_FADE := 1.1
const REEL_STEER_LOSS := 0.85
const SPIN_FADE := 2.5
const SWAY_RATE_MIN := 5.0
const SWAY_RATE_MAX := 7.5
const SWAY_ANGLE := 0.6
const SWAY_KICK := 16.0
const SWAY_GRIP_LOSS := 0.82
const SWAY_FISHTAIL := 0.17
const BIKE_SWAY_ROLL := 0.3
const CAR_SWAY_ROLL := 0.11
const RIDER_WIGGLE_ROLL := 0.3
const RIDER_WIGGLE_YAW := 0.38
const RIDER_RECOIL := -0.24
const ARM_GRIP_YAW := 0.1
const ARM_GRIP_PITCH := 0.48
const ARM_GRIP_LENGTH := 1.12
const ARM_COVER_YAW := -0.86
const ARM_COVER_PITCH := -0.5
const ARM_COVER_LENGTH := 0.75
const ARM_RUB := 0.09
const WRECK_SECONDS_SPREAD := 0.25
const WRECK_SPIN_UP := 6.0
const WRECK_VEER := 1.1
const WRECK_VEER_FADE := 1.6
const WRECK_ROLL_DRAG := 0.45
const WRECK_SLIDE_DRAG := 1.2
const WRECK_TILT_PER_SLIP := 0.035
const WRECK_TILT_MAX := 0.42
const WRECK_CRASH_SPEED := 7.0
const WRECK_FX_INTERVAL := 0.05
const WRECK_FUSE := 0.35
const BIKE_LAY_ANGLE := 1.38
const BIKE_LAY_RATE := 8.0
const BIKE_SPIN_FADE := 3.2
const BIKE_SLIDE_DRAG := 1.5
const BUMP_COOLDOWN := 0.5
const BUMP_DAMAGE := 0.3
const BUMP_SHOVE := 5.0
const BUMP_SPIN := 5.0


class EnemySpec:
	extends RefCounted
	var kind: String
	var radius: float
	var hp: float
	var speed: float
	var accel: float
	var turn: float
	var grip: float
	var damage: float
	var scrap: float
	var half_length: float
	var half_width: float
	var mass: float
	var sway: float
	var wreck_seconds: float
	var wreck_spin: float

	func _init(
		p_kind: String, p_radius: float, p_hp: float, p_speed: float, p_accel: float,
		p_turn: float, p_grip: float, p_damage: float, p_scrap: float, p_hl: float,
		p_hw: float, p_mass: float, p_sway: float, p_wsec: float, p_wspin: float,
	) -> void:
		kind = p_kind
		radius = p_radius
		hp = p_hp
		speed = p_speed
		accel = p_accel
		turn = p_turn
		grip = p_grip
		damage = p_damage
		scrap = p_scrap
		half_length = p_hl
		half_width = p_hw
		mass = p_mass
		sway = p_sway
		wreck_seconds = p_wsec
		wreck_spin = p_wspin


class Enemy:
	extends RefCounted
	var spec: EnemySpec
	var x: float = 0.0
	var z: float = 0.0
	var heading: float = 0.0
	var vx: float = 0.0
	var vz: float = 0.0
	var hp: float = 10.0
	var max_hp: float = 10.0
	var hit_cooldown: float = 0.0
	var ram_cooldown: float = 0.0
	var blind_timer: float = 0.0
	var slow_timer: float = 0.0
	var ember_timer: float = 0.0
	var toxic_timer: float = 0.0
	var flinch: float = 0.0
	var dust_timer: float = 0.0
	var flank: float = 0.0
	var knock_x: float = 0.0
	var knock_z: float = 0.0
	var blind: float = 0.0
	var reel: float = 0.0
	var spin: float = 0.0
	var sway_phase: float = 0.0
	var sway_rate: float = 6.0
	var bump_cooldown: float = 0.0
	var wreck: float = 0.0
	var wreck_age: float = 0.0
	var wreck_side: float = 1.0
	var tilt: float = 0.0
	var fx_timer: float = 0.0


class Threat:
	extends RefCounted
	var kind: String # "party" or "boss"
	var bearing: float
	var countdown: float
	var distance: float
	var size: int
	var members: Array[Enemy] = []


class Spawner:
	extends RefCounted
	const SPAWN_RING_MIN := 115.0
	const SPAWN_RING_MAX := 140.0
	const RECYCLE_DISTANCE := 215.0
	const WAVE_FIRST_DELAY := 0.6
	const WAVE_INTERVAL_START := 5.4
	const WAVE_INTERVAL_MIN := 3.0
	const WAVE_INTERVAL_RAMP := 300.0
	const WAVE_BURST_DURATION := 1.6
	const WAVE_MIN_STEP := 0.06
	const WAVE_MAX_STEP := 0.28
	const WAVE_TWO_SIDE_SHARE := 0.75
	const WAVE_STRAGGLER_CHANCE := 0.1
	const WAVE_MIN_SHIFT := 0.7
	const WAVE_FAR_START := 110.0
	const WAVE_FAR_FULL := 170.0
	const WAVE_FAR_SPEEDUP := 3.5
	const STRAY_INTERVAL_MIN := 7.0
	const STRAY_INTERVAL_MAX := 13.0
	const WAR_PARTY_INTERVAL := 60.0
	const WAR_PARTY_WARNING := 4.0
	const WAR_PARTY_SPREAD := 0.22
	const BOSS_INTERVAL := 150.0
	const BOSS_WARNING := 6.0
	const THREAT_ARRIVAL_DISTANCE := 42.0
	const AHEAD_BIAS := 0.55
	const HP_GROWTH_SECONDS := 140.0
	const DAMAGE_GROWTH_SECONDS := 420.0

	# Corner sectors span two adjacent sides plus the corner between them (e.g. bottom, bottom-left, left).
	const CORNER_SECTORS := [
		[PI * 0.25, PI * 0.25],
		[PI * 0.75, PI * 0.25],
		[-PI * 0.75, PI * 0.25],
		[-PI * 0.25, PI * 0.25],
	]

	# Single-side sectors focus a wave onto one edge of the screen.
	const SIDE_SECTORS := [
		[0.0, 0.42],
		[PI * 0.5, 0.42],
		[PI, 0.42],
		[-PI * 0.5, 0.42],
	]

	const SPAWN_TABLE := [
		["bike", 0.0, 3.0],
		["buggy", 25.0, 3.0],
		["truck", 110.0, 1.1],
		["interceptor", 230.0, 1.3],
	]

	var threats: Array[Threat] = []
	var on_threat: Callable = Callable()
	var _wave_bearing := PI * 0.25
	var _wave_spread := PI * 0.25
	var _wave_timer := WAVE_FIRST_DELAY
	var _wave_spawn_timer := 0.0
	var _wave_step := 0.2
	var _wave_total := 0
	var _wave_angles: Array[float] = []
	var _wave_members: Array[Enemy] = []
	var _stray_timer := 10.0
	var _next_war_party := WAR_PARTY_INTERVAL
	var _next_boss := BOSS_INTERVAL

	func reset() -> void:
		threats.clear()
		var initial: Array = CORNER_SECTORS[randi() % CORNER_SECTORS.size()]
		_wave_bearing = initial[0]
		_wave_spread = initial[1]
		_wave_timer = WAVE_FIRST_DELAY
		_wave_spawn_timer = 0.0
		_wave_step = 0.2
		_wave_total = 0
		_wave_angles.clear()
		_wave_members.clear()
		_stray_timer = randf_range(STRAY_INTERVAL_MIN, STRAY_INTERVAL_MAX)
		_next_war_party = WAR_PARTY_INTERVAL
		_next_boss = BOSS_INTERVAL

	func damage_scale(time_s: float) -> float:
		return 1.0 + time_s / DAMAGE_GROWTH_SECONDS

	func update(dt: float, time_s: float, car: CarBody, enemies: EnemySystem) -> void:
		var hp_scale := 1.0 + time_s / HP_GROWTH_SECONDS
		var minutes := time_s / 60.0
		var desired := minf(float(MAX_ENEMIES - 20), 3.0 + time_s * 0.19 + minutes * minutes * 1.2)

		for enemy in enemies.active:
			if absf(enemy.x - car.x) < RECYCLE_DISTANCE and absf(enemy.z - car.z) < RECYCLE_DISTANCE:
				continue
			var angle := _wave_bearing + SimMath.rand_signed(_wave_spread)
			var distance := randf_range(SPAWN_RING_MIN, SPAWN_RING_MAX)
			enemy.x = car.x + sin(angle) * distance
			enemy.z = car.z + cos(angle) * distance
			enemy.heading = angle + PI

		_update_waves(dt, time_s, desired, car, enemies, hp_scale)
		_update_stragglers(dt, time_s, desired, car, enemies, hp_scale)

		if time_s >= _next_war_party - WAR_PARTY_WARNING:
			_next_war_party += WAR_PARTY_INTERVAL
			_announce("party", WAR_PARTY_WARNING, mini(26, 6 + int(floor(time_s / 25.0))), car)
		if time_s >= _next_boss - BOSS_WARNING:
			_next_boss += BOSS_INTERVAL
			_announce("boss", BOSS_WARNING, 1, car)

		_update_threats(dt, car, enemies, hp_scale)

	func _update_waves(dt: float, time_s: float, desired: float, car: CarBody, enemies: EnemySystem, hp_scale: float) -> void:
		if not _wave_angles.is_empty():
			_wave_spawn_timer -= dt
			while _wave_spawn_timer <= 0.0 and not _wave_angles.is_empty():
				_wave_spawn_timer += _wave_step
				var base_angle: float = _wave_angles.pop_back()
				if enemies.active.size() >= MAX_ENEMIES - 15:
					continue
				var straggler := _wave_total >= 4 and randf() < WAVE_STRAGGLER_CHANCE
				var angle := _pick_straggler_angle() if straggler else base_angle
				var spawned := _spawn_at(enemies, _pick_kind(time_s), car, angle, hp_scale)
				if spawned != null and not straggler:
					_wave_members.append(spawned)
			return

		var wave_dist := _nearest_wave_distance(car)
		var far_factor := clampf((wave_dist - WAVE_FAR_START) / (WAVE_FAR_FULL - WAVE_FAR_START), 0.0, 1.0) if wave_dist > WAVE_FAR_START else 0.0
		_wave_timer -= dt * (1.0 + far_factor * WAVE_FAR_SPEEDUP)
		if enemies.active.size() <= maxi(1, int(floor(desired * 0.2))):
			_wave_timer = minf(_wave_timer, 1.0)
		if _wave_timer > 0.0:
			return

		var drove_far := far_factor > 0.0
		var min_wave := mini(3, int(ceil(desired)))
		var soft_cap := minf(float(MAX_ENEMIES - 20), ceil(desired * 1.35 + 4.0)) if drove_far else desired
		var deficit := int(ceil(soft_cap - float(enemies.active.size())))
		if deficit < min_wave and not enemies.active.is_empty():
			_wave_timer = 0.5
			return

		var room := MAX_ENEMIES - 20 - enemies.active.size()
		if room <= 0:
			_wave_timer = 0.6
			return

		var sector := _pick_ahead_sector(car) if drove_far and car.speed > 8.0 else _pick_next_sector()
		_wave_bearing = sector[0]
		_wave_spread = sector[1]
		_wave_members.clear()

		var target_wave := maxi(min_wave, mini(deficit, int(ceil(desired * 0.65 + 1.0))))
		var count := clampi(target_wave, 1, mini(22, room))
		_wave_total = count
		_wave_step = clampf(WAVE_BURST_DURATION / float(count), WAVE_MIN_STEP, WAVE_MAX_STEP)
		_wave_spawn_timer = 0.0

		# Stratify across the 1-2 side sector so the wave spans its edges cleanly, then shuffle arrival order.
		_wave_angles.clear()
		var jitter := 0.5 / float(count)
		for i in count:
			var slot := clampf(((float(i) + 0.5) / float(count)) * 2.0 - 1.0 + SimMath.rand_signed(jitter), -1.0, 1.0)
			_wave_angles.append(_wave_bearing + slot * _wave_spread)
		for i in range(_wave_angles.size() - 1, 0, -1):
			var j := randi() % (i + 1)
			var tmp := _wave_angles[i]
			_wave_angles[i] = _wave_angles[j]
			_wave_angles[j] = tmp

		var ramp := clampf(time_s / WAVE_INTERVAL_RAMP, 0.0, 1.0)
		_wave_timer = lerpf(WAVE_INTERVAL_START, WAVE_INTERVAL_MIN, ramp)

	func _nearest_wave_distance(car: CarBody) -> float:
		var best_sq := INF
		for enemy in _wave_members:
			if enemy.hp <= 0.0:
				continue
			var dx := enemy.x - car.x
			var dz := enemy.z - car.z
			var dist_sq := dx * dx + dz * dz
			if dist_sq < best_sq:
				best_sq = dist_sq
		return sqrt(best_sq) if best_sq < INF else -1.0

	func _pick_ahead_sector(car: CarBody) -> Array:
		var travel := atan2(car.vx, car.vz)
		var pool: Array = CORNER_SECTORS if randf() < WAVE_TWO_SIDE_SHARE else SIDE_SECTORS
		var best: Array = pool[0]
		var best_diff := INF
		for sector in pool:
			var diff := absf(SimMath.wrap_angle(sector[0] - travel))
			if diff < best_diff:
				best_diff = diff
				best = sector
		return best

	func _update_stragglers(dt: float, time_s: float, desired: float, car: CarBody, enemies: EnemySystem, hp_scale: float) -> void:
		_stray_timer -= dt
		if _stray_timer > 0.0:
			return
		_stray_timer = randf_range(STRAY_INTERVAL_MIN, STRAY_INTERVAL_MAX)
		if float(enemies.active.size()) >= desired:
			return
		_spawn_at(enemies, _pick_kind(time_s), car, _pick_straggler_angle(), hp_scale)

	func _pick_next_sector() -> Array:
		var pool: Array = CORNER_SECTORS if randf() < WAVE_TWO_SIDE_SHARE else SIDE_SECTORS
		var fresh: Array = []
		for sector in pool:
			if absf(SimMath.wrap_angle(sector[0] - _wave_bearing)) > WAVE_MIN_SHIFT:
				fresh.append(sector)
		var list: Array = fresh if not fresh.is_empty() else pool
		return list[randi() % list.size()]

	func _pick_straggler_angle() -> float:
		var clear_half := _wave_spread + 0.65
		var span := maxf(0.4, TAU - clear_half * 2.0)
		return SimMath.wrap_angle(_wave_bearing + clear_half + randf() * span)

	func _announce(kind: String, warning: float, size: int, car: CarBody) -> void:
		var threat := Threat.new()
		threat.kind = kind
		threat.bearing = _pick_wave_angle(car)
		threat.countdown = warning
		threat.distance = SPAWN_RING_MIN
		threat.size = size
		threats.append(threat)
		if on_threat.is_valid():
			on_threat.call(threat)

	func _update_threats(dt: float, car: CarBody, enemies: EnemySystem, hp_scale: float) -> void:
		for i in range(threats.size() - 1, -1, -1):
			var threat := threats[i]
			if threat.countdown > 0.0:
				threat.countdown -= dt
				if threat.countdown > 0.0:
					continue
				_release(threat, car, enemies, hp_scale)
			if not _track(threat, car):
				threats.remove_at(i)

	func _release(threat: Threat, car: CarBody, enemies: EnemySystem, hp_scale: float) -> void:
		var kind := "rig" if threat.kind == "boss" else "bike"
		var spread := 0.0 if threat.kind == "boss" else WAR_PARTY_SPREAD
		for _i in threat.size:
			var enemy := _spawn_at(enemies, kind, car, threat.bearing + SimMath.rand_signed(spread), hp_scale)
			if enemy != null:
				threat.members.append(enemy)

	func _track(threat: Threat, car: CarBody) -> bool:
		var tx := 0.0
		var tz := 0.0
		var alive := 0
		for enemy in threat.members:
			if enemy.hp <= 0.0:
				continue
			tx += enemy.x - car.x
			tz += enemy.z - car.z
			alive += 1
		if alive == 0:
			return false
		tx /= float(alive)
		tz /= float(alive)
		threat.distance = sqrt(tx * tx + tz * tz)
		if threat.distance < THREAT_ARRIVAL_DISTANCE:
			return false
		threat.bearing = atan2(tx, tz)
		return true

	func _spawn_at(enemies: EnemySystem, kind: String, car: CarBody, angle: float, hp_scale: float) -> Enemy:
		var distance := randf_range(SPAWN_RING_MIN, SPAWN_RING_MAX)
		return enemies.spawn(kind, car.x + sin(angle) * distance, car.z + cos(angle) * distance, hp_scale, angle + PI)

	func _pick_wave_angle(car: CarBody) -> float:
		if car.speed > 8.0 and randf() < AHEAD_BIAS:
			return atan2(car.vx, car.vz) + SimMath.rand_signed(1.0)
		return randf() * TAU

	func _pick_kind(time_s: float) -> String:
		var total := 0.0
		for entry in SPAWN_TABLE:
			if time_s >= entry[1]:
				total += entry[2]
		var roll := randf() * total
		for entry in SPAWN_TABLE:
			if time_s < entry[1]:
				continue
			roll -= entry[2]
			if roll <= 0.0:
				return entry[0]
		return "bike"


var specs: Dictionary = {} # String -> EnemySpec
var active: Array[Enemy] = []
var wrecks: Array[Enemy] = []
var _batches: Dictionary = {} # String -> SimMath.InstanceBatch
var _riders: SimMath.InstanceBatch
var _arms: SimMath.InstanceBatch
var _sample := SmokeSystem.SmokeSample.new()
var _contact := World.Contact.new()
var _shove := LooseSystem.ShoveResult.new()
var _harm_dealt := 0.0


func setup(base_material: StandardMaterial3D) -> void:
	specs = {
		"bike": EnemySpec.new("bike", 0.95, 8.0, 30.0, 16.0, 2.6, 3.6, 3.0, 1.0, 0.9, 0.4, 0.2, 1.0, 0.9, 4.5),
		"buggy": EnemySpec.new("buggy", 1.55, 26.0, 26.0, 12.0, 1.9, 2.6, 7.0, 2.0, 1.5, 0.95, 0.6, 0.85, 1.25, 4.6),
		"truck": EnemySpec.new("truck", 2.4, 110.0, 19.0, 7.0, 1.1, 2.0, 18.0, 7.0, 2.8, 1.2, 1.5, 0.5, 1.6, 2.4),
		"interceptor": EnemySpec.new("interceptor", 1.7, 60.0, 35.0, 15.0, 1.7, 2.2, 14.0, 4.0, 2.2, 1.0, 0.9, 0.75, 1.35, 4.0),
		"rig": EnemySpec.new("rig", 3.6, 900.0, 22.0, 6.0, 0.8, 1.8, 30.0, 45.0, 5.4, 1.5, 4.0, 0.25, 2.0, 1.1),
	}

	# Duplicate base material: write stencil=1 on visible enemy fragments so the
	# occluded silhouette next_pass never self-occludes or stacks alpha layers.
	var enemy_mat: StandardMaterial3D = base_material.duplicate()
	enemy_mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	enemy_mat.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
	enemy_mat.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
	enemy_mat.stencil_reference = 1
	var sil_shader: Shader = load("res://shaders/enemy_silhouette.gdshader")
	var sil_mat := ShaderMaterial.new()
	sil_mat.shader = sil_shader
	enemy_mat.next_pass = sil_mat

	var models := Models.build_enemy_models()
	for kind: String in models.keys():
		_batches[kind] = SimMath.InstanceBatch.new(self, models[kind], enemy_mat, MAX_ENEMIES, false, true, "Enemy_" + kind)

	var rider_models := Models.build_rider_models()
	_riders = SimMath.InstanceBatch.new(self, rider_models["body"], enemy_mat, MAX_ENEMIES, false, true, "EnemyRiders")
	_arms = SimMath.InstanceBatch.new(self, rider_models["arm"], enemy_mat, MAX_ENEMIES * 2, false, true, "EnemyRiderArms")


func clear() -> void:
	active.clear()
	wrecks.clear()
	_harm_dealt = 0.0
	render_all(0.0)


func hurt(enemy: Enemy, amount: float) -> void:
	var landed := minf(amount, enemy.hp)
	if landed <= 0.0:
		return
	enemy.hp -= amount
	_harm_dealt += (landed * enemy.spec.hp) / enemy.max_hp


func take_harm_dealt() -> float:
	var harm := _harm_dealt
	_harm_dealt = 0.0
	return harm


func spawn(kind: String, x: float, z: float, hp_scale: float, facing: float) -> Enemy:
	if active.size() >= MAX_ENEMIES:
		return null
	var spec: EnemySpec = specs[kind]
	var e := Enemy.new()
	e.spec = spec
	e.x = x
	e.z = z
	e.heading = facing
	e.vx = sin(facing) * spec.speed * 0.7
	e.vz = cos(facing) * spec.speed * 0.7
	e.hp = spec.hp * hp_scale
	e.max_hp = spec.hp * hp_scale
	e.dust_timer = randf() * DUST_INTERVAL
	e.flank = SimMath.rand_signed(1.0)
	e.sway_phase = randf() * TAU
	e.sway_rate = randf_range(SWAY_RATE_MIN, SWAY_RATE_MAX)
	active.append(e)
	return e


func hurt_area(x: float, z: float, radius: float, damage: float) -> void:
	for enemy in active:
		var reach := radius + enemy.spec.radius
		var dx := enemy.x - x
		var dz := enemy.z - z
		var dist_sq := dx * dx + dz * dz
		if dist_sq > reach * reach:
			continue
		hurt(enemy, damage)
		enemy.flinch = 1.0
		var dist := sqrt(dist_sq)
		if dist < 0.001:
			dist = 1.0
		var knock := BLAST_KNOCK * (1.0 - (0.6 * dist) / reach)
		enemy.knock_x = (dx / dist) * knock
		enemy.knock_z = (dz / dist) * knock


func sweep_dead(on_wreck: Callable, on_kill: Callable) -> void:
	for i in range(active.size() - 1, -1, -1):
		var enemy := active[i]
		if enemy.hp > 0.0:
			continue
		active[i] = active[active.size() - 1]
		active.pop_back()
		if enemy.blind_timer <= 0.0:
			on_kill.call(enemy)
			continue
		_begin_wreck(enemy)
		wrecks.append(enemy)
		on_wreck.call(enemy)


func _begin_wreck(enemy: Enemy) -> void:
	var spec := enemy.spec
	var swing := enemy.spin + sin(enemy.sway_phase) * maxf(enemy.blind, enemy.reel)
	if absf(swing) > 0.2:
		enemy.wreck_side = signf(swing)
	else:
		enemy.wreck_side = -1.0 if randf() < 0.5 else 1.0
	enemy.wreck = spec.wreck_seconds * (1.0 + SimMath.rand_signed(WRECK_SECONDS_SPREAD))
	enemy.wreck_age = 0.0
	enemy.fx_timer = 0.0
	enemy.flinch = 1.0


func update_enemies(
	dt: float,
	car: CarBody,
	stats: Upgrades.Stats,
	world: World,
	smoke: SmokeSystem,
	damage_scale: float,
	on_player_hit: Callable,
	on_wreck: Callable,
	on_bump: Callable,
	on_scrape: Callable,
	on_kill: Callable,
) -> void:
	var stir := minf(1.0, STIR_RATE * dt)
	var knock_fade := exp(-KNOCK_FADE * dt)
	var spin_fade := exp(-SPIN_FADE * dt)

	for enemy in active:
		var spec := enemy.spec
		enemy.knock_x *= knock_fade
		enemy.knock_z *= knock_fade
		enemy.hit_cooldown -= dt
		enemy.ram_cooldown -= dt
		enemy.blind_timer -= dt
		enemy.slow_timer -= dt
		enemy.ember_timer -= dt
		enemy.toxic_timer -= dt
		enemy.flinch = maxf(0.0, enemy.flinch - dt * 4.0)
		enemy.bump_cooldown -= dt
		enemy.reel = maxf(0.0, enemy.reel - REEL_FADE * dt)
		enemy.spin *= spin_fade
		enemy.heading += enemy.spin * dt
		enemy.sway_phase += enemy.sway_rate * dt

		var cloud := smoke.sample(enemy.x, enemy.z, _sample, enemy.vx, enemy.vz, stir)
		if cloud.total > SMOKE_THRESHOLD:
			var density := minf(SMOKE_DENSITY_CAP, cloud.total / SMOKE_FULL_DENSITY)
			hurt(enemy, stats.smoke_damage * density * dt)
			enemy.flinch = maxf(enemy.flinch, 0.6)
			enemy.blind_timer = BLINDED_LINGER
			var share := cloud.total * KIND_SHARE_THRESHOLD
			if cloud.by_kind[SmokeSystem.PUFF_ASH] > share:
				enemy.slow_timer = ASH_LINGER
			if cloud.by_kind[SmokeSystem.PUFF_EMBER] > share:
				enemy.ember_timer = EMBER_LINGER
			if cloud.by_kind[SmokeSystem.PUFF_TOXIC] > share:
				enemy.toxic_timer = TOXIC_LINGER
		if enemy.toxic_timer > 0.0:
			hurt(enemy, stats.toxic_dps * dt)
		if enemy.blind_timer > 0.0:
			enemy.blind = minf(1.0, enemy.blind + BLIND_RISE * dt)
		else:
			enemy.blind = maxf(0.0, enemy.blind - BLIND_FADE * dt)

		_steer(enemy, dt, car, stats)
		enemy.x += enemy.vx * dt
		enemy.z += enemy.vz * dt

		if world.resolve(enemy, spec.radius, _contact).hit:
			var into := enemy.vx * _contact.nx + enemy.vz * _contact.nz
			if into < 0.0:
				enemy.vx -= into * _contact.nx * 1.2
				enemy.vz -= into * _contact.nz * 1.2
		world.shove(enemy, spec.radius, spec.mass, _shove)
		_collide_with_car(enemy, car, stats, damage_scale, on_player_hit, false)

		enemy.dust_timer -= dt
		if enemy.dust_timer <= 0.0:
			enemy.dust_timer = DUST_INTERVAL
			var spd := sqrt(enemy.vx * enemy.vx + enemy.vz * enemy.vz)
			if spd > 6.0 and absf(enemy.x - car.x) < DUST_VISIBLE_RANGE and absf(enemy.z - car.z) < DUST_VISIBLE_RANGE:
				var back := spec.half_length
				var dx := enemy.x - sin(enemy.heading) * back + SimMath.rand_signed(spec.half_width)
				var dz := enemy.z - cos(enemy.heading) * back + SimMath.rand_signed(spec.half_width)
				smoke.emit(
					SmokeSystem.PUFF_DUST,
					dx,
					DesertTerrain.ground_height(dx, dz) + 0.3,
					dz,
					enemy.vx * 0.2,
					0.8,
					enemy.vz * 0.2,
					0.5 + spec.radius * 0.25,
					0.9,
					1.3,
					0.4,
					0.2,
				)

	_separate()
	sweep_dead(on_wreck, on_kill)
	_update_wrecks(dt, car, stats, world, smoke, damage_scale, on_player_hit, on_bump, on_scrape, on_kill)


func _update_wrecks(
	dt: float,
	car: CarBody,
	stats: Upgrades.Stats,
	world: World,
	smoke: SmokeSystem,
	damage_scale: float,
	on_player_hit: Callable,
	on_bump: Callable,
	on_scrape: Callable,
	on_kill: Callable,
) -> void:
	for i in range(wrecks.size() - 1, -1, -1):
		var enemy := wrecks[i]
		var spec := enemy.spec
		var is_bike := spec.kind == "bike"
		enemy.wreck -= dt
		enemy.wreck_age += dt
		enemy.hit_cooldown -= dt
		enemy.flinch = maxf(maxf(0.0, enemy.flinch - dt * 4.0), 1.0 - enemy.wreck / WRECK_FUSE)

		var spin_target := enemy.wreck_side * spec.wreck_spin * (exp(-BIKE_SPIN_FADE * enemy.wreck_age) if is_bike else 1.0)
		enemy.spin = SimMath.damp(enemy.spin, spin_target, WRECK_SPIN_UP, dt)
		enemy.heading += enemy.spin * dt

		var veer := enemy.wreck_side * WRECK_VEER * exp(-WRECK_VEER_FADE * enemy.wreck_age) * dt
		var c := cos(veer)
		var s := sin(veer)
		var nvx := enemy.vx * c + enemy.vz * s
		var nvz := enemy.vz * c - enemy.vx * s
		var fx := sin(enemy.heading)
		var fz := cos(enemy.heading)
		var forward := (nvx * fx + nvz * fz) * exp(-(BIKE_SLIDE_DRAG if is_bike else WRECK_ROLL_DRAG) * dt)
		var slip := (nvx * fz - nvz * fx) * exp(-(BIKE_SLIDE_DRAG if is_bike else WRECK_SLIDE_DRAG) * dt)
		enemy.vx = fx * forward + fz * slip
		enemy.vz = fz * forward - fx * slip
		enemy.x += enemy.vx * dt
		enemy.z += enemy.vz * dt
		if is_bike:
			enemy.tilt = SimMath.damp(enemy.tilt, enemy.wreck_side * BIKE_LAY_ANGLE, BIKE_LAY_RATE, dt)
		else:
			enemy.tilt = SimMath.damp(enemy.tilt, clampf(-slip * WRECK_TILT_PER_SLIP, -WRECK_TILT_MAX, WRECK_TILT_MAX), 9.0, dt)

		if world.resolve(enemy, spec.radius, _contact).hit:
			var into := enemy.vx * _contact.nx + enemy.vz * _contact.nz
			if into < 0.0:
				enemy.vx -= into * _contact.nx * 1.2
				enemy.vz -= into * _contact.nz * 1.2
				if into < -WRECK_CRASH_SPEED:
					enemy.wreck = 0.0
		world.shove(enemy, spec.radius, spec.mass, _shove)
		_collide_with_car(enemy, car, stats, damage_scale, on_player_hit, true)
		_bump_into(enemy, on_bump)

		enemy.fx_timer -= dt
		if enemy.fx_timer <= 0.0:
			enemy.fx_timer = WRECK_FX_INTERVAL
			if absf(enemy.x - car.x) < DUST_VISIBLE_RANGE and absf(enemy.z - car.z) < DUST_VISIBLE_RANGE:
				var spd := sqrt(enemy.vx * enemy.vx + enemy.vz * enemy.vz)
				var sx := enemy.x + SimMath.rand_signed(spec.half_length) * fx + SimMath.rand_signed(spec.half_width) * fz
				var sz := enemy.z + SimMath.rand_signed(spec.half_length) * fz - SimMath.rand_signed(spec.half_width) * fx
				var gnd := DesertTerrain.ground_height(sx, sz)
				if spd > 4.0:
					smoke.emit(
						SmokeSystem.PUFF_DUST,
						sx, gnd + 0.3, sz,
						enemy.vx * 0.15, 1.0, enemy.vz * 0.15,
						0.5 + spec.radius * 0.3, 1.1, randf_range(0.9, 1.5), 0.5, 0.2,
					)
				var cooked := enemy.wreck_age / maxf(0.001, enemy.wreck_age + maxf(0.0, enemy.wreck))
				if randf() < cooked:
					var burning := enemy.wreck < WRECK_FUSE or randf() < cooked * 0.3
					smoke.emit(
						SmokeSystem.PUFF_FIRE if burning else SmokeSystem.PUFF_SOOT,
						enemy.x, gnd + 0.6 + spec.radius * 0.3, enemy.z,
						enemy.vx * 0.3, randf_range(1.5, 3.5), enemy.vz * 0.3,
						0.3 + spec.radius * 0.18, 1.2,
						randf_range(0.25, 0.45) if burning else randf_range(0.6, 1.0),
						0.8, 1.5 if burning else 0.8,
					)
				if is_bike and spd > 3.0:
					on_scrape.call(enemy)

		if enemy.wreck > 0.0:
			continue
		wrecks[i] = wrecks[wrecks.size() - 1]
		wrecks.pop_back()
		on_kill.call(enemy)


func _bump_into(wreck: Enemy, on_bump: Callable) -> void:
	for other in active:
		var reach := (wreck.spec.radius + other.spec.radius) * 0.9
		var dx := other.x - wreck.x
		if dx > reach or dx < -reach:
			continue
		var dz := other.z - wreck.z
		var dist_sq := dx * dx + dz * dz
		if dist_sq >= reach * reach:
			continue
		var dist := sqrt(dist_sq)
		if dist < 0.001:
			dist = 0.001
		var nx := dx / dist
		var nz := dz / dist
		var share := wreck.spec.mass / (wreck.spec.mass + other.spec.mass)
		var overlap := reach - dist
		other.x += nx * overlap * share
		other.z += nz * overlap * share
		wreck.x -= nx * overlap * (1.0 - share)
		wreck.z -= nz * overlap * (1.0 - share)
		if other.bump_cooldown > 0.0:
			continue
		other.bump_cooldown = BUMP_COOLDOWN
		var closing := maxf(0.0, (wreck.vx - other.vx) * nx + (wreck.vz - other.vz) * nz)
		var str_val := minf(1.0, share * 2.0)
		var kick := (BUMP_SHOVE + closing) * str_val
		other.vx += nx * kick
		other.vz += nz * kick
		wreck.vx -= nx * closing * (1.0 - share)
		wreck.vz -= nz * closing * (1.0 - share)
		var side := signf(nx * cos(other.heading) - nz * sin(other.heading))
		if side == 0.0:
			side = 1.0
		other.spin = clampf(other.spin + side * BUMP_SPIN * str_val, -BUMP_SPIN, BUMP_SPIN)
		other.reel = maxf(other.reel, str_val)
		other.flinch = 1.0
		hurt(other, wreck.spec.damage * BUMP_DAMAGE)
		on_bump.call(other, str_val)


func render_all(time_s: float) -> void:
	for batch: SimMath.InstanceBatch in _batches.values():
		batch.begin()
	_riders.begin()
	_arms.begin()
	for enemy in active:
		_draw_enemy(enemy, time_s)
	for enemy in wrecks:
		_draw_wreck(enemy, time_s)
	for batch: SimMath.InstanceBatch in _batches.values():
		batch.commit()
	_riders.commit()
	_arms.commit()


func _draw_enemy(enemy: Enemy, time_s: float) -> void:
	var spec := enemy.spec
	var is_bike := spec.kind == "bike"
	var loose := maxf(enemy.blind, enemy.reel) * spec.sway
	var yaw := enemy.heading + sin(enemy.sway_phase + 1.3) * SWAY_FISHTAIL * loose
	var slope := DesertTerrain.sample_slope(enemy.x, enemy.z, yaw, spec.half_length, spec.half_width)
	var shake := enemy.flinch * 0.07 * sin(time_s * 55.0 + enemy.flank * 9.0)
	var lean := clampf((enemy.vx * cos(enemy.heading) - enemy.vz * sin(enemy.heading)) * 0.02, -0.3, 0.3)
	var sway := sin(enemy.sway_phase) * (BIKE_SWAY_ROLL if is_bike else CAR_SWAY_ROLL) * loose
	var roll := slope.z + lean + sway + shake
	(_batches[spec.kind] as SimMath.InstanceBatch).push(
		enemy.x, slope.x, enemy.z, yaw, slope.y, roll, 1.0 + shake, 1.0 - shake, 1.0 + shake
	)
	if not is_bike:
		return

	var blind := SimMath.smoothstep_f(0.0, 1.0, enemy.blind)
	var wiggle := time_s * 11.0 + enemy.flank * 9.0
	var mount := SimMath.sim_transform(enemy.x, slope.x, enemy.z, yaw, slope.y, roll, 1.0, 1.0, 1.0)
	var seat := _riders.push_under(
		mount,
		Models.RIDER_SEAT.x, Models.RIDER_SEAT.y, Models.RIDER_SEAT.z,
		sin(wiggle * 0.73) * RIDER_WIGGLE_YAW * blind,
		RIDER_RECOIL * blind,
		sin(wiggle) * RIDER_WIGGLE_ROLL * blind,
		1.0, 1.0, 1.0,
	)
	for side in [-1.0, 1.0]:
		_arms.push_under(
			seat,
			side * Models.RIDER_SHOULDER.x, Models.RIDER_SHOULDER.y, Models.RIDER_SHOULDER.z,
			side * lerpf(ARM_GRIP_YAW, ARM_COVER_YAW, blind),
			lerpf(ARM_GRIP_PITCH, ARM_COVER_PITCH, blind) + (sin(wiggle * 1.7 + side) * ARM_RUB - side * 0.07) * blind,
			0.0,
			1.0, 1.0, lerpf(ARM_GRIP_LENGTH, ARM_COVER_LENGTH, blind),
		)


func _draw_wreck(enemy: Enemy, time_s: float) -> void:
	var spec := enemy.spec
	var slope := DesertTerrain.sample_slope(enemy.x, enemy.z, enemy.heading, spec.half_length, spec.half_width)
	var shake := enemy.flinch * 0.07 * sin(time_s * 55.0 + enemy.flank * 9.0)
	var lift := spec.half_width * absf(sin(enemy.tilt))
	(_batches[spec.kind] as SimMath.InstanceBatch).push(
		enemy.x, slope.x + lift, enemy.z, enemy.heading, slope.y, slope.z + enemy.tilt + shake,
		1.0 + shake, 1.0 - shake, 1.0 + shake,
	)


func _steer(enemy: Enemy, dt: float, car: CarBody, stats: Upgrades.Stats) -> void:
	var spec := enemy.spec
	var to_car_x := car.x - enemy.x
	var to_car_z := car.z - enemy.z
	var distance := sqrt(to_car_x * to_car_x + to_car_z * to_car_z) + 0.001
	var lead := minf(0.9, distance / 40.0)
	var target_x := car.x + car.vx * lead
	var target_z := car.z + car.vz * lead
	if distance > FLANK_DISTANCE:
		var sideways := enemy.flank * minf(distance * 0.35, 22.0)
		target_x += (to_car_z / distance) * sideways
		target_z -= (to_car_x / distance) * sideways

	var loose := maxf(enemy.blind, enemy.reel) * spec.sway
	var desired := atan2(target_x - enemy.x, target_z - enemy.z) + sin(enemy.sway_phase) * SWAY_ANGLE * loose
	var err := SimMath.wrap_angle(desired - enemy.heading)
	var turn := spec.turn * dt * (1.0 - REEL_STEER_LOSS * enemy.reel)
	enemy.heading += clampf(err, -turn, turn)

	var fx := sin(enemy.heading)
	var fz := cos(enemy.heading)
	var cap := spec.speed
	if enemy.blind_timer > 0.0:
		cap *= BLINDED_SPEED_FACTOR
	if enemy.slow_timer > 0.0:
		cap *= 1.0 - stats.ash_slow
	if absf(err) > 1.2:
		cap *= 0.65
	var forward := move_toward(enemy.vx * fx + enemy.vz * fz, cap, spec.accel * dt)
	var grip := spec.grip * (1.0 - SWAY_GRIP_LOSS * loose)
	var side_slip := (enemy.vx * fz - enemy.vz * fx + cos(enemy.sway_phase) * SWAY_KICK * loose * dt) * exp(-grip * dt)
	enemy.vx = fx * forward + fz * side_slip
	enemy.vz = fz * forward - fx * side_slip


func _collide_with_car(enemy: Enemy, car: CarBody, stats: Upgrades.Stats, damage_scale: float, on_player_hit: Callable, wrecked: bool) -> void:
	var spec := enemy.spec
	var fx := sin(car.heading)
	var fz := cos(car.heading)
	var reach := CAR_CIRCLE_RADIUS + spec.radius
	var best_depth := 0.0
	var nx := 0.0
	var nz := 0.0
	for side: float in [-1.0, 1.0]:
		var dx := enemy.x - (car.x + fx * CAR_CIRCLE_OFFSET * side)
		var dz := enemy.z - (car.z + fz * CAR_CIRCLE_OFFSET * side)
		var dist := sqrt(dx * dx + dz * dz)
		if dist < 0.001:
			dist = 0.001
		var depth := reach - dist
		if depth > best_depth:
			best_depth = depth
			nx = dx / dist
			nz = dz / dist
	if best_depth <= 0.0:
		return

	enemy.x += nx * best_depth
	enemy.z += nz * best_depth
	var closing := maxf(0.0, (car.vx - enemy.vx) * nx + (car.vz - enemy.vz) * nz)
	enemy.vx += nx * (3.0 + closing * 0.6)
	enemy.vz += nz * (3.0 + closing * 0.6)
	var shove := minf(closing * 0.25, 5.0) * spec.mass
	car.vx -= nx * shove
	car.vz -= nz * shove
	car.yaw_rate += (nx * fz - nz * fx) * shove * 0.08
	if wrecked:
		return

	if stats.ram_damage > 0.0 and car.speed > RAM_MIN_SPEED and enemy.ram_cooldown <= 0.0:
		enemy.ram_cooldown = RAM_COOLDOWN
		hurt(enemy, stats.ram_damage * (car.speed / 20.0))
		enemy.flinch = 1.0
	if enemy.hit_cooldown <= 0.0:
		enemy.hit_cooldown = HIT_COOLDOWN
		on_player_hit.call(enemy, spec.damage * damage_scale * (1.0 - stats.ram_guard), closing)


func _separate() -> void:
	var n := active.size()
	for i in n:
		var a := active[i]
		for j in range(i + 1, n):
			var b := active[j]
			var reach := (a.spec.radius + b.spec.radius) * 0.9
			var dx := b.x - a.x
			if dx > reach or dx < -reach:
				continue
			var dz := b.z - a.z
			var dist_sq := dx * dx + dz * dz
			if dist_sq >= reach * reach:
				continue
			var dist := sqrt(dist_sq)
			if dist < 0.001:
				dist = 0.001
			var overlap := (reach - dist) * 0.5
			var total := a.spec.mass + b.spec.mass
			var nx := dx / dist
			var nz := dz / dist
			a.x -= nx * overlap * (b.spec.mass / total) * 2.0
			a.z -= nz * overlap * (b.spec.mass / total) * 2.0
			b.x += nx * overlap * (a.spec.mass / total) * 2.0
			b.z += nz * overlap * (a.spec.mass / total) * 2.0

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
const HIT_COOLDOWN := 0.45
const BLINDED_SPEED_FACTOR := 0.72
const BLINDED_LINGER := 0.25
const DUST_INTERVAL := 0.3
const DUST_VISIBLE_RANGE := 75.0
const STIR_RATE := 1.6

# Directional collision faces
const FACE_FRONT := 0
const FACE_SIDE := 1
const FACE_REAR := 2

# 3-state maneuver AI
const AI_SETUP := 0
const AI_CHARGE := 1
const AI_RECOVER := 2

# Biker pipe-throwing states
const PIPE_IDLE := 0
const PIPE_WINDUP := 1
const PIPE_FOLLOW := 2

# Player OBB & momentum collision tuning
const PLAYER_HALF_LENGTH := 2.15
const PLAYER_PLOW_EXTRA_LENGTH := 0.22
const PLAYER_HALF_WIDTH := 0.92
const PLAYER_MASS := 1.0
const COLLISION_MIN_SPEED := 5.0
const COLLISION_DAMAGE_PER_SPEED := 0.40
const FACE_VULN_FRONT := 1.0
const FACE_VULN_SIDE := 1.5
const FACE_VULN_REAR := 1.15
const BIKE_LETHAL_CRASH_SPEED := 9.0

# Biker swoop & smoke-obscured pipe throw tuning
const PIPE_WINDUP_SECONDS := 0.36
const PIPE_FOLLOW_SECONDS := 0.28
const PIPE_COOLDOWN_SECONDS := 1.7
const PIPE_RANGE_MIN := 2.6
const PIPE_RANGE_MAX := 15.5
const PIPE_PASS_OFFSET := 4.0
const PIPE_THROW_SPEED := 34.0
const PIPE_DAMAGE := 3.5
const PIPE_SMOKE_LOS_THRESHOLD := 0.25
const PIPE_CLEAR_SPREAD := 0.04
const PIPE_OBSCURED_SPREAD := 0.68
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

# Enemy drift tracks
const TRACK_VISIBLE_RANGE := 95.0
const ENEMY_TRACK_SLIP_SPEED := 3.0
const ENEMY_TRACK_SLIP_RATIO := 0.14
const ENEMY_TRACK_HEAVY_SLIP := 6.5

# Biker Akira slide tuning
const AKIRA_MIN_SPEED := 14.5
const AKIRA_MIN_TURN_ERR := 1.05
const AKIRA_VISIBLE_RANGE := 55.0
const AKIRA_DURATION_MIN := 0.72
const AKIRA_DURATION_MAX := 1.02
const AKIRA_COOLDOWN_MIN := 2.6
const AKIRA_COOLDOWN_MAX := 4.4
const AKIRA_SLIP_ANGLE := 1.42
const AKIRA_WHIP_RATE := 11.5
const AKIRA_ARC_RATE := 0.72
const AKIRA_BRAKE_DRAG := 2.05
const AKIRA_LEAN_ANGLE := 0.92
const AKIRA_DUST_INTERVAL := 0.045
const AKIRA_SPARK_INTERVAL := 0.065
const AKIRA_ABORT_SPEED := 4.5


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
	var front_armor: float
	var side_armor: float
	var rear_armor: float
	var front_bonus: float
	var side_bonus: float
	var rear_bonus: float
	var ram_arc: float

	func _init(
		p_kind: String, p_radius: float, p_hp: float, p_speed: float, p_accel: float,
		p_turn: float, p_grip: float, p_damage: float, p_scrap: float, p_hl: float,
		p_hw: float, p_mass: float, p_sway: float, p_wsec: float, p_wspin: float,
		p_front_armor: float = 0.0, p_side_armor: float = 0.0, p_rear_armor: float = 0.0,
		p_front_bonus: float = 0.0, p_side_bonus: float = 0.0, p_rear_bonus: float = 0.0,
		p_ram_arc: float = 14.0,
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
		front_armor = p_front_armor
		side_armor = p_side_armor
		rear_armor = p_rear_armor
		front_bonus = p_front_bonus
		side_bonus = p_side_bonus
		rear_bonus = p_rear_bonus
		ram_arc = p_ram_arc

	func armor_for_face(face: int) -> float:
		match face:
			FACE_FRONT: return front_armor
			FACE_SIDE: return side_armor
			_: return rear_armor

	func bonus_for_face(face: int) -> float:
		match face:
			FACE_FRONT: return front_bonus
			FACE_SIDE: return side_bonus
			_: return rear_bonus


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
	var ai_state: int = AI_SETUP
	var ai_timer: float = 0.0
	var ai_side: float = 1.0
	var avoid_side: float = 0.0
	var avoid_timer: float = 0.0
	var pipe_state: int = PIPE_IDLE
	var pipe_timer: float = 0.0
	var pipe_cooldown: float = 0.0
	var pipe_side: float = 1.0
	var akira_timer: float = 0.0
	var akira_duration: float = 0.85
	var akira_dir: float = 1.0
	var akira_blend: float = 0.0
	var akira_cooldown: float = 0.0
	var akira_dust_timer: float = 0.0
	var akira_spark_timer: float = 0.0
	var track_heads: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var track_times: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var track_intensities: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var track_active: PackedByteArray = PackedByteArray([0, 0, 0, 0])


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
			enemy.akira_timer = 0.0
			enemy.akira_blend = 0.0
			enemy.track_active.fill(0)

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
var _legs: SimMath.InstanceBatch
var _arms: SimMath.InstanceBatch
var _pipes: SimMath.InstanceBatch
var _sample := SmokeSystem.SmokeSample.new()
var _contact := World.Contact.new()
var _avoid := World.AvoidanceResult.new()
var _shove := LooseSystem.ShoveResult.new()
var _harm_dealt := 0.0


func setup(base_material: StandardMaterial3D) -> void:
	# Positional args: kind, radius, hp, speed, accel, turn, grip, damage, scrap, half_length, half_width, mass, sway, wreck_seconds, wreck_spin,
	#                  front_armor, side_armor, rear_armor, front_bonus, side_bonus, rear_bonus, ram_arc
	specs = {
		"bike": EnemySpec.new("bike", 0.95, 8.0, 30.0, 16.0, 2.8, 3.6, PIPE_DAMAGE, 1.0, 0.9, 0.4, 0.2, 1.0, 0.9, 4.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 11.0),
		"buggy": EnemySpec.new("buggy", 1.55, 26.0, 26.0, 12.0, 2.1, 2.6, 7.0, 2.0, 1.5, 0.95, 0.6, 0.85, 1.25, 4.6, 18.0, 0.0, 0.0, 10.0, 0.0, 0.0, 14.0),
		"truck": EnemySpec.new("truck", 2.4, 110.0, 19.0, 7.0, 1.2, 2.0, 18.0, 7.0, 2.8, 1.2, 1.5, 0.5, 1.6, 2.4, 28.0, 6.0, 0.0, 16.0, 2.0, 0.0, 22.0),
		"interceptor": EnemySpec.new("interceptor", 1.7, 60.0, 35.0, 15.0, 1.9, 2.2, 14.0, 4.0, 2.2, 1.0, 0.9, 0.75, 1.35, 4.0, 20.0, 0.0, 0.0, 14.0, 0.0, 0.0, 16.0),
		"rig": EnemySpec.new("rig", 3.6, 900.0, 22.0, 6.0, 0.85, 1.8, 30.0, 45.0, 5.4, 1.5, 4.0, 0.25, 2.0, 1.1, 40.0, 10.0, 0.0, 22.0, 4.0, 0.0, 30.0),
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
	_legs = SimMath.InstanceBatch.new(self, rider_models["leg"], enemy_mat, MAX_ENEMIES * 2, false, true, "EnemyRiderLegs")
	_arms = SimMath.InstanceBatch.new(self, rider_models["arm"], enemy_mat, MAX_ENEMIES * 2, false, true, "EnemyRiderArms")
	_pipes = SimMath.InstanceBatch.new(self, rider_models["pipe"], enemy_mat, MAX_ENEMIES, false, true, "EnemyRiderPipes")


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
	e.ai_side = -1.0 if randf() < 0.5 else 1.0
	e.pipe_side = -e.ai_side
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
	enemy.akira_timer = 0.0
	enemy.akira_blend = 0.0


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
	on_throw_pipe: Callable = Callable(),
	tracks: SkidTracks = null,
	track_time: float = 0.0,
	on_akira: Callable = Callable(),
) -> void:
	var stir := minf(1.0, STIR_RATE * dt)
	var knock_fade := exp(-KNOCK_FADE * dt)
	var spin_fade := exp(-SPIN_FADE * dt)

	for enemy in active:
		var spec := enemy.spec
		enemy.knock_x *= knock_fade
		enemy.knock_z *= knock_fade
		enemy.hit_cooldown -= dt
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
		enemy.akira_cooldown = maxf(0.0, enemy.akira_cooldown - dt)

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

		_steer(enemy, dt, car, stats, world, on_akira)
		enemy.x += enemy.vx * dt
		enemy.z += enemy.vz * dt

		if world.resolve(enemy, spec.radius, _contact).hit:
			var into := enemy.vx * _contact.nx + enemy.vz * _contact.nz
			if into < 0.0:
				enemy.vx -= into * _contact.nx * 1.2
				enemy.vz -= into * _contact.nz * 1.2
				if enemy.akira_timer > 0.0:
					enemy.akira_timer = 0.0
			# Commit to sliding around the obstacle tangent so enemies never stall nose-first on walls
			var fx := sin(enemy.heading)
			var fz := cos(enemy.heading)
			var cross := _contact.nx * fz - _contact.nz * fx
			var slide_side := -1.0 if cross >= 0.0 else 1.0
			if enemy.avoid_timer <= 0.0:
				enemy.avoid_side = slide_side
			enemy.avoid_timer = maxf(enemy.avoid_timer, 0.75)
			var tx := -_contact.nz * enemy.avoid_side
			var tz := _contact.nx * enemy.avoid_side
			enemy.vx += tx * 1.6
			enemy.vz += tz * 1.6
		world.shove(enemy, spec.radius, spec.mass, _shove)
		_collide_with_car(enemy, car, stats, damage_scale, on_player_hit, on_bump, false)
		if spec.kind == "bike":
			_update_biker_pipe(enemy, dt, car, smoke, damage_scale, on_throw_pipe)
			_update_akira_fx(enemy, dt, car, smoke, on_scrape)

		if tracks != null:
			_update_enemy_tracks(enemy, car, tracks, track_time, false)

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
	_update_wrecks(dt, car, stats, world, smoke, damage_scale, on_player_hit, on_bump, on_scrape, on_kill, tracks, track_time)


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
	tracks: SkidTracks = null,
	track_time: float = 0.0,
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
		_collide_with_car(enemy, car, stats, damage_scale, on_player_hit, on_bump, true)
		_bump_into(enemy, on_bump)
		if tracks != null:
			_update_enemy_tracks(enemy, car, tracks, track_time, true)

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
	_legs.begin()
	_arms.begin()
	_pipes.begin()
	for enemy in active:
		_draw_enemy(enemy, time_s)
	for enemy in wrecks:
		_draw_wreck(enemy, time_s)
	for batch: SimMath.InstanceBatch in _batches.values():
		batch.commit()
	_riders.commit()
	_legs.commit()
	_arms.commit()
	_pipes.commit()


func _draw_enemy(enemy: Enemy, time_s: float) -> void:
	var spec := enemy.spec
	var is_bike := spec.kind == "bike"
	var loose := maxf(enemy.blind, enemy.reel) * spec.sway
	var yaw := enemy.heading + sin(enemy.sway_phase + 1.3) * SWAY_FISHTAIL * loose
	var slope := DesertTerrain.sample_slope(enemy.x, enemy.z, yaw, spec.half_length, spec.half_width)
	var shake := enemy.flinch * 0.07 * sin(time_s * 55.0 + enemy.flank * 9.0)
	var lean := clampf((enemy.vx * cos(enemy.heading) - enemy.vz * sin(enemy.heading)) * 0.02, -0.3, 0.3)
	var sway := sin(enemy.sway_phase) * (BIKE_SWAY_ROLL if is_bike else CAR_SWAY_ROLL) * loose
	var akira := enemy.akira_blend if is_bike else 0.0
	var akira_roll := -enemy.akira_dir * AKIRA_LEAN_ANGLE * akira
	var effective_lean := lerpf(lean, akira_roll, akira)
	var roll := slope.z + effective_lean + sway + shake
	var bike_lift := 0.08 * akira
	(_batches[spec.kind] as SimMath.InstanceBatch).push(
		enemy.x, slope.x + bike_lift, enemy.z, yaw, slope.y, roll, 1.0 + shake, 1.0 - shake, 1.0 + shake
	)
	if not is_bike:
		return

	var blind := SimMath.smoothstep_f(0.0, 1.0, enemy.blind)
	var wiggle := time_s * 11.0 + enemy.flank * 9.0
	var mount := SimMath.sim_transform(enemy.x, slope.x + bike_lift, enemy.z, yaw, slope.y, roll, 1.0, 1.0, 1.0)
	var seat_yaw := sin(wiggle * 0.73) * RIDER_WIGGLE_YAW * blind
	var seat_pitch := RIDER_RECOIL * blind
	var seat_roll := sin(wiggle) * RIDER_WIGGLE_ROLL * blind

	# Akira slide rider posture: reclined back, looking into the slide direction, braced against the lean
	if akira > 0.001:
		seat_yaw += -enemy.akira_dir * 0.44 * akira
		seat_pitch += -0.32 * akira
		seat_roll += enemy.akira_dir * 0.28 * akira

	var weapon_side := enemy.pipe_side
	var choking := enemy.blind >= 0.65
	if not choking and akira < 0.35:
		match enemy.pipe_state:
			PIPE_WINDUP:
				var u := SimMath.smoothstep_f(0.0, 1.0, 1.0 - clampf(enemy.pipe_timer / PIPE_WINDUP_SECONDS, 0.0, 1.0))
				seat_yaw -= weapon_side * 0.32 * u
				seat_pitch -= 0.14 * u
			PIPE_FOLLOW:
				var f := clampf(enemy.pipe_timer / PIPE_FOLLOW_SECONDS, 0.0, 1.0)
				seat_yaw += weapon_side * 0.35 * f
				seat_roll += weapon_side * 0.14 * f

	var seat := _riders.push_under(
		mount,
		Models.RIDER_SEAT.x, Models.RIDER_SEAT.y, Models.RIDER_SEAT.z,
		seat_yaw, seat_pitch, seat_roll,
		1.0, 1.0, 1.0,
	)

	for side: float in [-1.0, 1.0]:
		var leg_yaw := 0.0
		var leg_pitch := 0.0
		var leg_roll := 0.0
		var leg_sz := 1.0
		if akira > 0.001:
			if side * enemy.akira_dir > 0.0:
				# Inside leg kicks out and extends down to plant the boot on the desert floor
				leg_yaw = side * 0.78 * akira
				leg_pitch = 0.44 * akira
				leg_roll = -side * 0.42 * akira
				leg_sz = lerpf(1.0, 1.22, akira)
			else:
				# Outside leg braces tight against the bike frame
				leg_pitch = -0.10 * akira
		_legs.push_under(
			seat,
			side * Models.RIDER_HIP.x, Models.RIDER_HIP.y, Models.RIDER_HIP.z,
			leg_yaw, leg_pitch, leg_roll,
			1.0, 1.0, leg_sz,
		)

	var has_pipe_in_hand := (not choking) and (akira < 0.35) and (enemy.pipe_state == PIPE_WINDUP or (enemy.pipe_state == PIPE_IDLE and enemy.pipe_cooldown <= 0.45))
	for side: float in [-1.0, 1.0]:
		var arm_yaw := side * lerpf(ARM_GRIP_YAW, ARM_COVER_YAW, blind)
		var arm_pitch := lerpf(ARM_GRIP_PITCH, ARM_COVER_PITCH, blind) + (sin(wiggle * 1.7 + side) * ARM_RUB - side * 0.07) * blind
		var arm_len := lerpf(ARM_GRIP_LENGTH, ARM_COVER_LENGTH, blind)
		var is_throw_arm := (side * weapon_side > 0.0) and not choking and akira < 0.35

		var pipe_yaw := 0.0
		var pipe_pitch := 0.0

		if is_throw_arm:
			match enemy.pipe_state:
				PIPE_IDLE:
					if has_pipe_in_hand:
						# Hold a metal pipe ready off the grip
						arm_yaw = side * 0.45
						arm_pitch = 0.30
						arm_len = 1.0
						pipe_yaw = side * 0.2
						pipe_pitch = -0.65
				PIPE_WINDUP:
					# Cock throwing arm high and back behind shoulder to hurl the pipe
					var u := SimMath.smoothstep_f(0.0, 1.0, 1.0 - clampf(enemy.pipe_timer / PIPE_WINDUP_SECONDS, 0.0, 1.0))
					arm_yaw = side * lerpf(0.45, 2.05, u)
					arm_pitch = lerpf(0.30, -1.05, u)
					arm_len = 1.08
					pipe_yaw = side * lerpf(0.2, 0.35, u)
					pipe_pitch = lerpf(-0.65, 0.35, u)
				PIPE_FOLLOW:
					# Whipped forward after release (empty-handed while pipe flies)
					var f := clampf(enemy.pipe_timer / PIPE_FOLLOW_SECONDS, 0.0, 1.0)
					arm_yaw = side * lerpf(ARM_GRIP_YAW, 1.15, f)
					arm_pitch = lerpf(ARM_GRIP_PITCH, -0.05, f)
					arm_len = lerpf(ARM_GRIP_LENGTH, 1.18, f)

		if akira > 0.001 and not choking:
			# Both hands locked hard on the handlebars while leaning back into the slide
			arm_yaw = lerpf(arm_yaw, side * 0.16 + enemy.akira_dir * 0.22, akira)
			arm_pitch = lerpf(arm_pitch, 0.56, akira)
			arm_len = lerpf(arm_len, 1.24, akira)

		var arm_xform := _arms.push_under(
			seat,
			side * Models.RIDER_SHOULDER.x, Models.RIDER_SHOULDER.y, Models.RIDER_SHOULDER.z,
			arm_yaw, arm_pitch, 0.0,
			1.0, 1.0, arm_len,
		)

		if is_throw_arm and has_pipe_in_hand:
			_pipes.push_under(arm_xform, 0.0, 0.0, 0.72, pipe_yaw, pipe_pitch, 0.0, 1.0, 1.0, 1.0)


func _draw_wreck(enemy: Enemy, time_s: float) -> void:
	var spec := enemy.spec
	var slope := DesertTerrain.sample_slope(enemy.x, enemy.z, enemy.heading, spec.half_length, spec.half_width)
	var shake := enemy.flinch * 0.07 * sin(time_s * 55.0 + enemy.flank * 9.0)
	var lift := spec.half_width * absf(sin(enemy.tilt))
	(_batches[spec.kind] as SimMath.InstanceBatch).push(
		enemy.x, slope.x + lift, enemy.z, enemy.heading, slope.y, slope.z + enemy.tilt + shake,
		1.0 + shake, 1.0 - shake, 1.0 + shake,
	)


func _steer(enemy: Enemy, dt: float, car: CarBody, stats: Upgrades.Stats, world: World, on_akira: Callable = Callable()) -> void:
	if enemy.spec.kind == "bike":
		_steer_bike(enemy, dt, car, stats, world, on_akira)
	else:
		_steer_car(enemy, dt, car, stats, world)


func _steer_car(enemy: Enemy, dt: float, car: CarBody, stats: Upgrades.Stats, world: World) -> void:
	var spec := enemy.spec
	enemy.ai_timer += dt

	var pfx := sin(car.heading)
	var pfz := cos(car.heading)
	var prx := pfz
	var prz := -pfx

	var rel_x := enemy.x - car.x
	var rel_z := enemy.z - car.z
	var distance := sqrt(rel_x * rel_x + rel_z * rel_z) + 0.001
	var along := rel_x * pfx + rel_z * pfz
	var across := rel_x * prx + rel_z * prz
	var arc := spec.ram_arc

	var lead := clampf(distance / maxf(14.0, spec.speed), 0.08, 0.75)
	var pred_x := car.x + car.vx * lead
	var pred_z := car.z + car.vz * lead

	var target_x := pred_x
	var target_z := pred_z
	var speed_mult := 1.0

	match enemy.ai_state:
		AI_SETUP:
			# Choose the flank we are already closer to if clearly to one side
			if absf(across) > 3.5:
				enemy.ai_side = signf(across)
			# Stage off the player's chosen flank slightly ahead so we can turn in perpendicular to T-bone
			var stage_out := arc * 0.95
			var stage_ahead := arc * 0.45
			target_x = pred_x + prx * (enemy.ai_side * stage_out) + pfx * stage_ahead
			target_z = pred_z + prz * (enemy.ai_side * stage_out) + pfz * stage_ahead

			var in_flank_band := absf(across) > 5.0 and absf(along) < arc * 1.15 and distance < arc * 1.65
			var to_player_x := -rel_x / distance
			var to_player_z := -rel_z / distance
			var fx := sin(enemy.heading)
			var fz := cos(enemy.heading)
			var facing_player := fx * to_player_x + fz * to_player_z
			if (in_flank_band and facing_player > 0.25) or (distance < arc * 1.1 and enemy.ai_timer > 1.2) or enemy.ai_timer > 4.5:
				enemy.ai_state = AI_CHARGE
				enemy.ai_timer = 0.0

		AI_CHARGE:
			# Full-speed frontal ram aimed at the player's center/flank
			var charge_lead := clampf(distance / maxf(16.0, spec.speed * 1.1), 0.04, 0.55)
			target_x = car.x + car.vx * charge_lead
			target_z = car.z + car.vz * charge_lead
			speed_mult = 1.12

			var fx := sin(enemy.heading)
			var fz := cos(enemy.heading)
			var passed := ((-rel_x) * fx + (-rel_z) * fz) < -2.5 and distance < arc
			if passed or enemy.ai_timer > 3.2:
				enemy.ai_state = AI_RECOVER
				enemy.ai_timer = 0.0

		AI_RECOVER:
			# Swing wide away from the player to build speed and line up a fresh flank run
			var recover_time := 1.1 + (arc - 12.0) * 0.045
			var out_x := rel_x / distance
			var out_z := rel_z / distance
			var fx := sin(enemy.heading)
			var fz := cos(enemy.heading)
			target_x = enemy.x + (out_x * 0.75 + fx * 0.65) * arc
			target_z = enemy.z + (out_z * 0.75 + fz * 0.65) * arc
			if enemy.ai_timer >= recover_time or distance > arc * 1.45:
				enemy.ai_state = AI_SETUP
				enemy.ai_timer = 0.0
				if absf(across) > 2.5:
					enemy.ai_side = signf(across)
				else:
					enemy.ai_side = -enemy.ai_side

	_drive_toward(enemy, dt, target_x, target_z, stats, world, speed_mult, enemy.ai_state == AI_CHARGE)


func _steer_bike(enemy: Enemy, dt: float, car: CarBody, stats: Upgrades.Stats, world: World, on_akira: Callable = Callable()) -> void:
	var spec := enemy.spec
	enemy.ai_timer += dt

	if enemy.akira_timer > 0.0:
		var spd := sqrt(enemy.vx * enemy.vx + enemy.vz * enemy.vz)
		if spd > 4.0 and enemy.blind < 0.45:
			var vel_angle := atan2(enemy.vx, enemy.vz)
			world.steer_around_obstacles(
				enemy.x, enemy.z, vel_angle, vel_angle, spec.radius,
				spd, spec.mass, spec.turn, 10.0, enemy.avoid_side, _avoid,
			)
			if _avoid.avoiding:
				# Abort the slide early if sliding toward an obstacle so the bike can swerve clear
				enemy.akira_timer = 0.0
		if enemy.akira_timer > 0.0:
			_step_akira_slide(enemy, dt, stats)
			return

	var pfx := sin(car.heading)
	var pfz := cos(car.heading)
	var prx := pfz
	var prz := -pfx

	var rel_x := enemy.x - car.x
	var rel_z := enemy.z - car.z
	var distance := sqrt(rel_x * rel_x + rel_z * rel_z) + 0.001
	var along := rel_x * pfx + rel_z * pfz
	var across := rel_x * prx + rel_z * prz

	var lead := clampf(distance / maxf(16.0, spec.speed), 0.05, 0.55)
	var pred_x := car.x + car.vx * lead
	var pred_z := car.z + car.vz * lead

	var target_x := pred_x
	var target_z := pred_z
	var speed_mult := 1.0
	var just_peeled := false

	match enemy.ai_state:
		AI_SETUP:
			if absf(across) > 2.5:
				enemy.ai_side = signf(across)
			# Stage behind and offset from the player's flank to swoop in close for a pipe throw
			target_x = pred_x + prx * (enemy.ai_side * 7.5) - pfx * 5.5
			target_z = pred_z + prz * (enemy.ai_side * 7.5) - pfz * 5.5
			if distance < 16.5 or enemy.ai_timer > 3.5:
				enemy.ai_state = AI_CHARGE
				enemy.ai_timer = 0.0

		AI_CHARGE:
			# Swoop close alongside the player's flank (close-quarters melee-like skirmish feel)
			target_x = pred_x + prx * (enemy.ai_side * PIPE_PASS_OFFSET) + pfx * 6.0
			target_z = pred_z + prz * (enemy.ai_side * PIPE_PASS_OFFSET) + pfz * 6.0
			var desired_spd := maxf(spec.speed * 0.9, car.speed + 6.0)
			speed_mult = clampf(desired_spd / spec.speed, 0.8, 1.12)
			if along > 6.5 or enemy.ai_timer > 2.8:
				enemy.ai_state = AI_RECOVER
				enemy.ai_timer = 0.0
				just_peeled = true

		AI_RECOVER:
			# Peel outward away from the player before looping back for another pass
			target_x = car.x + prx * (enemy.ai_side * 15.0) + pfx * 11.0
			target_z = car.z + prz * (enemy.ai_side * 15.0) + pfz * 11.0
			if enemy.ai_timer <= dt * 1.6:
				just_peeled = true
			if enemy.ai_timer >= 1.45 or distance > 16.5:
				enemy.ai_state = AI_SETUP
				enemy.ai_timer = 0.0
				if randf() < 0.35:
					enemy.ai_side = -enemy.ai_side

	# Active nose-avoidance: if bike is right in front of the player's bumper, swerve outward
	if along > 0.5 and along < 12.5 and absf(across) < 4.2:
		var dodge_side := signf(across) if absf(across) > 0.4 else enemy.ai_side
		target_x += prx * (dodge_side * 10.0)
		target_z += prz * (dodge_side * 10.0)

	# Stylish Akira slide trigger: whip broadside on sharp reversals, dodges, or post-pass peel-outs
	# Only trigger when not actively weaving around an obstacle
	if enemy.akira_cooldown <= 0.0 and enemy.avoid_timer <= 0.0 and enemy.blind < 0.35 and enemy.reel < 0.25 and enemy.pipe_state != PIPE_WINDUP and distance < AKIRA_VISIBLE_RANGE:
		var spd := sqrt(enemy.vx * enemy.vx + enemy.vz * enemy.vz)
		if spd >= AKIRA_MIN_SPEED:
			var vel_angle := atan2(enemy.vx, enemy.vz)
			var desired := atan2(target_x - enemy.x, target_z - enemy.z)
			var turn_err := SimMath.wrap_angle(desired - vel_angle)
			var can_slide := absf(turn_err) >= AKIRA_MIN_TURN_ERR or (just_peeled and spd >= 16.0 and randf() < 0.62)
			if can_slide:
				# Verify clear space ahead before committing to a broadside slide
				world.steer_around_obstacles(
					enemy.x, enemy.z, vel_angle, vel_angle, spec.radius,
					spd, spec.mass, spec.turn, 12.0, 0.0, _avoid,
				)
				if not _avoid.avoiding:
					if absf(turn_err) >= AKIRA_MIN_TURN_ERR:
						_begin_akira_slide(enemy, signf(turn_err), on_akira)
					else:
						var peel_dir := enemy.ai_side if (distance < 8.5 and along > 0.0) else (signf(turn_err) if absf(turn_err) > 0.25 else enemy.ai_side)
						_begin_akira_slide(enemy, peel_dir, on_akira)
					_step_akira_slide(enemy, dt, stats)
					return

	_drive_toward(enemy, dt, target_x, target_z, stats, world, speed_mult, false)


func _begin_akira_slide(enemy: Enemy, dir: float, on_akira: Callable) -> void:
	enemy.akira_dir = 1.0 if dir >= 0.0 else -1.0
	enemy.akira_duration = randf_range(AKIRA_DURATION_MIN, AKIRA_DURATION_MAX)
	enemy.akira_timer = enemy.akira_duration
	enemy.akira_cooldown = randf_range(AKIRA_COOLDOWN_MIN, AKIRA_COOLDOWN_MAX)
	enemy.akira_dust_timer = 0.0
	enemy.akira_spark_timer = 0.0
	if on_akira.is_valid():
		on_akira.call(enemy)


func _step_akira_slide(enemy: Enemy, dt: float, stats: Upgrades.Stats) -> void:
	var spd := sqrt(enemy.vx * enemy.vx + enemy.vz * enemy.vz)
	if enemy.blind >= 0.6 or enemy.reel >= 0.4 or spd < AKIRA_ABORT_SPEED:
		enemy.akira_timer = 0.0
		return

	enemy.akira_timer = maxf(0.0, enemy.akira_timer - dt)
	var prog := 1.0 - enemy.akira_timer / maxf(0.01, enemy.akira_duration)

	# Curve velocity smoothly along the turn arc while scrubbing speed broadside
	var vel_angle := atan2(enemy.vx, enemy.vz)
	var arc_delta := enemy.akira_dir * AKIRA_ARC_RATE * (1.0 - 0.35 * prog) * dt
	vel_angle += arc_delta

	var drag := AKIRA_BRAKE_DRAG * (1.15 if enemy.slow_timer > 0.0 else 1.0)
	var new_spd := spd * exp(-drag * dt)
	enemy.vx = sin(vel_angle) * new_spd
	enemy.vz = cos(vel_angle) * new_spd

	# Whip bike broadside (~81 deg) to the velocity vector, then straighten on exit
	var target_slip := AKIRA_SLIP_ANGLE * (1.0 if prog < 0.78 else lerpf(1.0, 0.25, (prog - 0.78) / 0.22))
	var target_heading := vel_angle + enemy.akira_dir * target_slip
	var h_err := SimMath.wrap_angle(target_heading - enemy.heading)
	enemy.heading += clampf(h_err, -AKIRA_WHIP_RATE * dt, AKIRA_WHIP_RATE * dt)

	# Kick throttle on the tail end of the slide so the bike snaps out cleanly
	if prog > 0.78:
		var exit_push := ((prog - 0.78) / 0.22) * enemy.spec.accel * 1.15 * dt
		if enemy.slow_timer > 0.0:
			exit_push *= 1.0 - stats.ash_slow
		enemy.vx += sin(enemy.heading) * exit_push
		enemy.vz += cos(enemy.heading) * exit_push


func _update_akira_fx(enemy: Enemy, dt: float, car: CarBody, smoke: SmokeSystem, on_scrape: Callable) -> void:
	if enemy.akira_timer > 0.0:
		var prog := 1.0 - enemy.akira_timer / maxf(0.01, enemy.akira_duration)
		var target_blend := 1.0 if prog < 0.80 else clampf((1.0 - prog) / 0.20, 0.0, 1.0)
		enemy.akira_blend = SimMath.damp(enemy.akira_blend, target_blend, 18.0 if target_blend > enemy.akira_blend else 10.0, dt)
	else:
		enemy.akira_blend = SimMath.damp(enemy.akira_blend, 0.0, 10.0, dt)
		return

	if absf(enemy.x - car.x) > DUST_VISIBLE_RANGE or absf(enemy.z - car.z) > DUST_VISIBLE_RANGE:
		return

	var spd := sqrt(enemy.vx * enemy.vx + enemy.vz * enemy.vz)
	if spd < 5.0:
		return

	var fx := sin(enemy.heading)
	var fz := cos(enemy.heading)
	var rx := fz
	var rz := -fx

	# Stylized dust/tire plumes blasting off both front and rear tires opposite the slide
	enemy.akira_dust_timer -= dt
	if enemy.akira_dust_timer <= 0.0:
		enemy.akira_dust_timer = AKIRA_DUST_INTERVAL
		for wheel_z: float in [0.85, -0.80]:
			var wx := enemy.x + fx * wheel_z
			var wz := enemy.z + fz * wheel_z
			smoke.emit(
				SmokeSystem.PUFF_DUST,
				wx + SimMath.rand_signed(0.18),
				DesertTerrain.ground_height(wx, wz) + 0.28,
				wz + SimMath.rand_signed(0.18),
				enemy.vx * 0.15 + rx * (enemy.akira_dir * 2.2) + SimMath.rand_signed(0.9),
				randf_range(1.1, 2.3),
				enemy.vz * 0.15 + rz * (enemy.akira_dir * 2.2) + SimMath.rand_signed(0.9),
				randf_range(0.55, 0.85),
				1.25,
				randf_range(0.85, 1.35),
				0.68,
				0.35,
			)

	# Sparks spraying from the dragging boot / low footpeg
	enemy.akira_spark_timer -= dt
	if enemy.akira_spark_timer <= 0.0 and spd > 8.5:
		enemy.akira_spark_timer = AKIRA_SPARK_INTERVAL
		if on_scrape.is_valid():
			on_scrape.call(enemy)


func _update_enemy_tracks(enemy: Enemy, car: CarBody, tracks: SkidTracks, track_time: float, wrecked: bool) -> void:
	if absf(enemy.x - car.x) > TRACK_VISIBLE_RANGE or absf(enemy.z - car.z) > TRACK_VISIBLE_RANGE:
		enemy.track_active.fill(0)
		return

	var spec := enemy.spec
	var is_bike := spec.kind == "bike"
	var loose := maxf(enemy.blind, enemy.reel) * spec.sway
	var yaw := enemy.heading + (0.0 if wrecked else sin(enemy.sway_phase + 1.3) * SWAY_FISHTAIL * loose)
	var fx := sin(yaw)
	var fz := cos(yaw)

	var spd := sqrt(enemy.vx * enemy.vx + enemy.vz * enemy.vz)
	var side_slip := absf(enemy.vx * cos(enemy.heading) - enemy.vz * sin(enemy.heading))
	var slip_ratio := side_slip / (spd + 1.0)

	var is_akira := is_bike and not wrecked and enemy.akira_blend > 0.25 and spd > 4.0
	var drifting := false
	var heavy := false
	var intensity := 0.0

	if wrecked:
		drifting = spd > 3.5
		heavy = spd > 5.5
		intensity = clampf(spd / 12.0, 0.35, 1.0)
	elif is_akira:
		drifting = true
		heavy = true
		intensity = lerpf(0.75, 1.3, enemy.akira_blend) * clampf(spd / 12.0, 0.5, 1.0)
	else:
		drifting = spd > 5.0 and side_slip > ENEMY_TRACK_SLIP_SPEED and slip_ratio > ENEMY_TRACK_SLIP_RATIO
		heavy = drifting and (side_slip > ENEMY_TRACK_HEAVY_SLIP or enemy.blind > 0.35 or enemy.reel > 0.25)
		intensity = clampf((side_slip - ENEMY_TRACK_SLIP_SPEED) / 8.0, 0.28, 1.0)

	if not drifting:
		enemy.track_active.fill(0)
		return

	if is_bike:
		# Slot 0: rear wheel, Slot 1: front wheel (Akira/heavy/wreck), Slot 2: dragging boot (Akira)
		_mark_enemy_wheel(enemy, 0, enemy.x - fx * 0.80, enemy.z - fz * 0.80, 0.12, true, intensity, tracks, track_time)
		_mark_enemy_wheel(enemy, 1, enemy.x + fx * 0.85, enemy.z + fz * 0.85, 0.10, heavy, intensity * 0.92, tracks, track_time)
		var boot_on := is_akira and enemy.akira_blend > 0.42
		var boot_across := enemy.akira_dir * 0.68
		_mark_enemy_wheel(enemy, 2, enemy.x + fx * 0.05 + fz * boot_across, enemy.z + fz * 0.05 - fx * boot_across, 0.07, boot_on, intensity * 0.65, tracks, track_time)
		enemy.track_active[3] = 0
		return

	var rear_x := 1.0
	var rear_z := -1.05
	var front_x := 0.95
	var front_z := 1.05
	var half_w := 0.16
	match spec.kind:
		"interceptor":
			rear_x = 1.0
			rear_z = -1.30
			front_x = 0.95
			front_z = 1.30
			half_w = 0.16
		"truck":
			rear_x = 1.2
			rear_z = -2.2
			front_x = 1.2
			front_z = 1.8
			half_w = 0.21
		"rig":
			rear_x = 1.45
			rear_z = -4.3
			front_x = 1.45
			front_z = 3.6
			half_w = 0.25

	# Rear axle (always marks while drifting)
	_mark_enemy_wheel(enemy, 0, enemy.x + fx * rear_z - fz * rear_x, enemy.z + fz * rear_z + fx * rear_x, half_w, true, intensity, tracks, track_time)
	_mark_enemy_wheel(enemy, 1, enemy.x + fx * rear_z + fz * rear_x, enemy.z + fz * rear_z - fx * rear_x, half_w, true, intensity, tracks, track_time)
	# Front axle (marks on heavy drifts, smoke fishtails, and spinning wrecks)
	_mark_enemy_wheel(enemy, 2, enemy.x + fx * front_z - fz * front_x, enemy.z + fz * front_z + fx * front_x, half_w * 0.88, heavy, intensity * 0.78, tracks, track_time)
	_mark_enemy_wheel(enemy, 3, enemy.x + fx * front_z + fz * front_x, enemy.z + fz * front_z - fx * front_x, half_w * 0.88, heavy, intensity * 0.78, tracks, track_time)


func _mark_enemy_wheel(
	enemy: Enemy,
	slot: int,
	wx: float,
	wz: float,
	half_width: float,
	sliding: bool,
	intensity: float,
	tracks: SkidTracks,
	track_time: float,
) -> void:
	if not sliding:
		enemy.track_active[slot] = 0
		return
	if enemy.track_active[slot] == 0:
		enemy.track_heads[slot] = Vector2(wx, wz)
		enemy.track_times[slot] = track_time
		enemy.track_intensities[slot] = intensity
		enemy.track_active[slot] = 1
		return
	var prev := enemy.track_heads[slot]
	var dx := wx - prev.x
	var dz := wz - prev.y
	if dx * dx + dz * dz < tracks.min_step * tracks.min_step:
		return
	tracks.add_segment(prev.x, prev.y, wx, wz, half_width, enemy.track_times[slot], track_time, enemy.track_intensities[slot], intensity)
	enemy.track_heads[slot] = Vector2(wx, wz)
	enemy.track_times[slot] = track_time
	enemy.track_intensities[slot] = intensity


func _drive_toward(
	enemy: Enemy,
	dt: float,
	target_x: float,
	target_z: float,
	stats: Upgrades.Stats,
	world: World,
	speed_mult: float,
	charging_target: bool,
) -> void:
	var spec := enemy.spec
	var loose := maxf(enemy.blind, enemy.reel) * spec.sway
	var tdx := target_x - enemy.x
	var tdz := target_z - enemy.z
	var target_dist := sqrt(tdx * tdx + tdz * tdz)
	var base_desired := atan2(tdx, tdz)
	var avoid_speed := 1.0
	var is_avoiding := false

	# Clear-sighted enemies actively steer around rocks, walls, outposts, barrels, and sturdy trees;
	# smoke-blinded enemies lose obstacle awareness and can crash into terrain
	var sight := clampf(1.0 - enemy.blind * 1.6, 0.0, 1.0)
	if sight > 0.05:
		var cur_spd := sqrt(enemy.vx * enemy.vx + enemy.vz * enemy.vz)
		var look_cap := target_dist + 1.0 if charging_target else 999.0
		var prev_side := enemy.avoid_side if enemy.avoid_timer > 0.0 else 0.0
		world.steer_around_obstacles(
			enemy.x,
			enemy.z,
			enemy.heading,
			base_desired,
			spec.radius,
			maxf(cur_spd, spec.speed * 0.6),
			spec.mass,
			spec.turn,
			look_cap,
			prev_side,
			_avoid,
		)
		if _avoid.avoiding:
			is_avoiding = true
			var steer_delta := SimMath.wrap_angle(_avoid.heading - base_desired)
			base_desired = SimMath.wrap_angle(base_desired + steer_delta * sight)
			avoid_speed = lerpf(1.0, _avoid.speed_factor, sight)
			enemy.avoid_side = _avoid.side_bias
			enemy.avoid_timer = 0.65
		else:
			enemy.avoid_timer = maxf(0.0, enemy.avoid_timer - dt)
			if enemy.avoid_timer <= 0.0:
				enemy.avoid_side = 0.0
	else:
		enemy.avoid_timer = maxf(0.0, enemy.avoid_timer - dt)

	var desired := base_desired + sin(enemy.sway_phase) * SWAY_ANGLE * loose
	var err := SimMath.wrap_angle(desired - enemy.heading)
	var turn_boost := 1.25 if is_avoiding and sight > 0.5 else 1.0
	var turn := spec.turn * turn_boost * dt * (1.0 - REEL_STEER_LOSS * enemy.reel)
	enemy.heading += clampf(err, -turn, turn)

	var fx := sin(enemy.heading)
	var fz := cos(enemy.heading)
	var cap := spec.speed * speed_mult * avoid_speed
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


func _dist_to_player_obb(px: float, pz: float, car: CarBody, stats: Upgrades.Stats) -> float:
	var pfx := sin(car.heading)
	var pfz := cos(car.heading)
	var prx := pfz
	var prz := -pfx
	var hl := PLAYER_HALF_LENGTH + (PLAYER_PLOW_EXTRA_LENGTH if stats.ram_front_armor > 0.0 else 0.0)
	var hw := PLAYER_HALF_WIDTH
	var dx := px - car.x
	var dz := pz - car.z
	var local_f := dx * pfx + dz * pfz
	var local_r := dx * prx + dz * prz
	var clamped_f := clampf(local_f, -hl, hl)
	var clamped_r := clampf(local_r, -hw, hw)
	var df := local_f - clamped_f
	var dr := local_r - clamped_r
	return sqrt(df * df + dr * dr)


func _update_biker_pipe(
	enemy: Enemy,
	dt: float,
	car: CarBody,
	smoke: SmokeSystem,
	damage_scale: float,
	on_throw_pipe: Callable,
) -> void:
	enemy.pipe_cooldown = maxf(0.0, enemy.pipe_cooldown - dt)
	# Heavy smoke directly on the biker (or holding both bars during an Akira slide) prevents throwing
	if enemy.blind >= 0.65 or enemy.akira_timer > 0.0:
		enemy.pipe_state = PIPE_IDLE
		enemy.pipe_timer = 0.0
		return

	var bfx := sin(enemy.heading)
	var bfz := cos(enemy.heading)
	var brx := bfz
	var brz := -bfx
	var to_car_x := car.x - enemy.x
	var to_car_z := car.z - enemy.z
	var dist := sqrt(to_car_x * to_car_x + to_car_z * to_car_z)

	match enemy.pipe_state:
		PIPE_IDLE:
			var side_dot := to_car_x * brx + to_car_z * brz
			if absf(side_dot) > 0.25:
				enemy.pipe_side = signf(side_dot)
			if enemy.pipe_cooldown > 0.0 or enemy.ai_state == AI_RECOVER:
				return
			if dist >= PIPE_RANGE_MIN and dist <= PIPE_RANGE_MAX and enemy.ai_state == AI_CHARGE:
				enemy.pipe_side = signf(side_dot) if absf(side_dot) > 0.1 else -enemy.ai_side
				enemy.pipe_state = PIPE_WINDUP
				enemy.pipe_timer = PIPE_WINDUP_SECONDS

		PIPE_WINDUP:
			enemy.pipe_timer -= dt
			if enemy.pipe_timer <= 0.0:
				_release_biker_pipe(enemy, car, smoke, damage_scale, on_throw_pipe)
				enemy.pipe_state = PIPE_FOLLOW
				enemy.pipe_timer = PIPE_FOLLOW_SECONDS
				enemy.pipe_cooldown = PIPE_COOLDOWN_SECONDS
				# Peel away after hurling the pipe during the drive-by pass
				enemy.ai_state = AI_RECOVER
				enemy.ai_timer = 0.0

		PIPE_FOLLOW:
			enemy.pipe_timer -= dt
			if enemy.pipe_timer <= 0.0:
				enemy.pipe_state = PIPE_IDLE


func _release_biker_pipe(
	enemy: Enemy,
	car: CarBody,
	smoke: SmokeSystem,
	damage_scale: float,
	on_throw_pipe: Callable,
) -> void:
	if not on_throw_pipe.is_valid():
		return
	var bfx := sin(enemy.heading)
	var bfz := cos(enemy.heading)
	var brx := bfz
	var brz := -bfx

	var hx := enemy.x + brx * (enemy.pipe_side * 0.55) + bfx * 0.35
	var hz := enemy.z + brz * (enemy.pipe_side * 0.55) + bfz * 0.35
	var hy := DesertTerrain.ground_height(hx, hz) + 1.55

	var dx := car.x - hx
	var dz := car.z - hz
	var dist := maxf(0.5, sqrt(dx * dx + dz * dz))

	# Check whether drift smoke obscures line of sight between biker and player
	var obscuration := smoke.obscuration_along_ray(enemy.x, enemy.z, car.x, car.z)
	var obscured := obscuration >= PIPE_SMOKE_LOS_THRESHOLD or enemy.blind >= 0.25

	var pvx := 0.0
	var pvy := 0.0
	var pvz := 0.0
	var throw_yaw := atan2(dx, dz)

	if not obscured:
		# Clear line of sight: lead the player's car cleanly with tight accuracy
		var est_t := clampf(dist / PIPE_THROW_SPEED, 0.08, 0.7)
		var aim_x := car.x + car.vx * est_t * 0.92
		var aim_z := car.z + car.vz * est_t * 0.92
		var adx := aim_x - hx
		var adz := aim_z - hz
		var aim_dist := maxf(0.5, sqrt(adx * adx + adz * adz))
		var flight_t := clampf(aim_dist / PIPE_THROW_SPEED, 0.08, 0.72)
		throw_yaw = atan2(adx, adz) + SimMath.rand_signed(PIPE_CLEAR_SPREAD)
		var horiz_spd := clampf((aim_dist / flight_t) * (1.0 + 0.12 * flight_t), 14.0, 56.0)
		pvx = sin(throw_yaw) * horiz_spd
		pvz = cos(throw_yaw) * horiz_spd
		var target_y := DesertTerrain.ground_height(aim_x, aim_z) + 0.95
		pvy = (target_y - hy) / flight_t + 0.5 * GibSystem.GRAVITY * flight_t
	else:
		# Obscured by drift smoke: throw blindly into a wide cone toward the vague direction
		# (misses the vast majority of the time at range, but gets deadlier up close as the cone narrows)
		var spread := SimMath.rand_signed(PIPE_OBSCURED_SPREAD)
		throw_yaw = atan2(dx, dz) + spread
		var flight_t := clampf(dist / PIPE_THROW_SPEED, 0.1, 0.72)
		var horiz_spd := clampf((dist / flight_t) * randf_range(0.84, 1.16), 14.0, 48.0)
		pvx = sin(throw_yaw) * horiz_spd
		pvz = cos(throw_yaw) * horiz_spd
		var target_y := DesertTerrain.ground_height(car.x, car.z) + 0.95
		pvy = (target_y - hy) / flight_t + 0.5 * GibSystem.GRAVITY * flight_t + SimMath.rand_signed(1.6)

	on_throw_pipe.call(hx, hy, hz, pvx, pvy, pvz, throw_yaw, enemy.spec.damage * damage_scale, enemy)


static func _face_vuln(face: int) -> float:
	match face:
		FACE_SIDE: return FACE_VULN_SIDE
		FACE_REAR: return FACE_VULN_REAR
		_: return FACE_VULN_FRONT


static func _classify_face(nx: float, nz: float, fx: float, fz: float, rx: float, rz: float) -> int:
	var fwd := nx * fx + nz * fz
	var side := absf(nx * rx + nz * rz)
	if absf(fwd) >= side:
		return FACE_FRONT if fwd > 0.0 else FACE_REAR
	return FACE_SIDE


func _collide_with_car(
	enemy: Enemy,
	car: CarBody,
	stats: Upgrades.Stats,
	damage_scale: float,
	on_player_hit: Callable,
	on_bump: Callable,
	wrecked: bool,
) -> void:
	var spec := enemy.spec
	var p_hl := PLAYER_HALF_LENGTH + (PLAYER_PLOW_EXTRA_LENGTH if stats.ram_front_armor > 0.0 else 0.0)
	var p_hw := PLAYER_HALF_WIDTH
	var e_hl := spec.half_length
	var e_hw := spec.half_width

	# Fast broadphase bounding-circle reject
	var dx := enemy.x - car.x
	var dz := enemy.z - car.z
	var broad := sqrt(p_hl * p_hl + p_hw * p_hw) + sqrt(e_hl * e_hl + e_hw * e_hw)
	if dx * dx + dz * dz >= broad * broad:
		return

	# 2D OBB Separating Axis Theorem (4 candidate axes)
	var pfx := sin(car.heading)
	var pfz := cos(car.heading)
	var prx := pfz
	var prz := -pfx

	var efx := sin(enemy.heading)
	var efz := cos(enemy.heading)
	var erx := efz
	var erz := -efx

	var best_depth := INF
	var nx := 0.0
	var nz := 0.0

	var axes := [
		[pfx, pfz],
		[prx, prz],
		[efx, efz],
		[erx, erz],
	]
	for axis in axes:
		var ax: float = axis[0]
		var az: float = axis[1]
		var center_dist := dx * ax + dz * az
		var proj_p := p_hl * absf(pfx * ax + pfz * az) + p_hw * absf(prx * ax + prz * az)
		var proj_e := e_hl * absf(efx * ax + efz * az) + e_hw * absf(erx * ax + erz * az)
		var overlap := proj_p + proj_e - absf(center_dist)
		if overlap <= 0.0:
			return
		if overlap < best_depth:
			best_depth = overlap
			var s := 1.0 if center_dist >= 0.0 else -1.0
			nx = ax * s
			nz = az * s

	# Separate enemy out of player OBB along MTV normal (points from player -> enemy)
	enemy.x += nx * best_depth
	enemy.z += nz * best_depth

	var closing := maxf(0.0, (car.vx - enemy.vx) * nx + (car.vz - enemy.vz) * nz)
	var mass_total := PLAYER_MASS + spec.mass
	var enemy_push := (2.5 + closing * 0.65) * (PLAYER_MASS / mass_total) * 1.4
	enemy.vx += nx * enemy_push
	enemy.vz += nz * enemy_push
	var shove := minf(closing * 0.3, 6.5) * (spec.mass / mass_total) * 1.4
	car.vx -= nx * shove
	car.vz -= nz * shove
	car.yaw_rate += (nx * pfz - nz * pfx) * shove * 0.09

	if wrecked:
		return

	# Slow scrapes / gentle pushes deal zero damage
	if closing <= COLLISION_MIN_SPEED:
		return
	if enemy.hit_cooldown > 0.0:
		return
	enemy.hit_cooldown = HIT_COOLDOWN

	var player_face := _classify_face(nx, nz, pfx, pfz, prx, prz)
	var enemy_face := _classify_face(-nx, -nz, efx, efz, erx, erz)

	var is_bike := spec.kind == "bike"
	var enemy_mass_mult := 0.45 if is_bike else clampf(sqrt(spec.mass / PLAYER_MASS), 0.75, 2.2)
	var player_mass_mult := 2.4 if is_bike else clampf(sqrt(PLAYER_MASS / spec.mass), 0.5, 1.35)

	var eff := closing - COLLISION_MIN_SPEED
	var base_impact := eff * COLLISION_DAMAGE_PER_SPEED

	var p_armor := stats.ram_front_armor if player_face == FACE_FRONT else 0.0
	var p_bonus := stats.ram_front_bonus if player_face == FACE_FRONT else 0.0
	var e_armor := spec.armor_for_face(enemy_face)
	var e_bonus := spec.bonus_for_face(enemy_face)

	var raw_to_player := (base_impact * enemy_mass_mult + e_bonus) * _face_vuln(player_face) * damage_scale
	var dmg_to_player := maxf(0.0, raw_to_player - p_armor)

	var raw_to_enemy := (base_impact * player_mass_mult + p_bonus) * _face_vuln(enemy_face)
	var dmg_to_enemy := maxf(0.0, raw_to_enemy - e_armor)

	# Bikes are fragile: any real collision with the player car wrecks them in one hit
	if is_bike and closing >= BIKE_LETHAL_CRASH_SPEED:
		dmg_to_enemy = maxf(dmg_to_enemy, enemy.max_hp)

	if dmg_to_enemy > 0.0:
		hurt(enemy, dmg_to_enemy)
		enemy.flinch = 1.0
		if enemy_face == FACE_SIDE:
			var spin_dir := signf(nx * efz - nz * efx)
			if spin_dir == 0.0:
				spin_dir = 1.0
			enemy.spin = clampf(enemy.spin + spin_dir * minf(eff * 0.25, BUMP_SPIN), -BUMP_SPIN, BUMP_SPIN)
			enemy.reel = maxf(enemy.reel, clampf(eff / 22.0, 0.25, 1.0))

	if on_bump.is_valid():
		on_bump.call(enemy, clampf(eff / 25.0, 0.25, 1.0))
	on_player_hit.call(enemy, dmg_to_player, closing)

	# After an impact, peel off and loop around for a fresh ramming/swoop run
	enemy.akira_timer = 0.0
	enemy.ai_state = AI_RECOVER
	enemy.ai_timer = 0.0


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

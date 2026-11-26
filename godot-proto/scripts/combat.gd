class_name Combat
extends Node3D

# GunSystem (spiral turret + bullets), Explosive weapons (proximity mines +
# physics-bouncing rear grenades), and PickupSystem (scrap XP hexes + repair crates).

const MAX_BULLETS := 400
const BULLET_SPEED := 58.0
const BULLET_LIFE := 0.8
const BULLET_RADIUS := 0.35
const SPIRAL_STEP := 0.41
const MUZZLE_HEIGHT := 1.9
const MUZZLE_OFFSET := 1.2

const MAX_MINES := 96
const MINE_DROP_REAR := 2.45
const MINE_TRIGGER_RADIUS := 1.45
const MINE_GRAVITY := 28.0
const MINE_GROUND_DRAG := 9.0

const MAX_GRENADES := 96
const GRENADE_DROP_REAR := 2.25
const GRENADE_LAUNCH_HEIGHT := 1.15
const GRENADE_CLEARANCE := 0.36
const GRENADE_PHYS_RADIUS := 0.42
const GRENADE_COLLIDE_RADIUS := 0.55
const GRENADE_GRAVITY := 30.0
const GRENADE_AIR_DRAG := 0.25
const GRENADE_BOUNCE := 0.54
const GRENADE_BOUNCE_KEEP := 0.80
const GRENADE_SETTLE_SPEED := 2.4
const GRENADE_SLIDE_FRICTION := 2.2
const GRENADE_WALL_BOUNCE := 0.65
const GRENADE_KICK_COOLDOWN := 0.12
const GRENADE_PLAYER_GRACE := 0.28
const GRENADE_TRAIL_INTERVAL := 0.11

const MODE_AIR := 0
const MODE_GROUND := 1

const REPAIR_DROP_VALUE := 20.0
const REPAIR_CRATE_VALUE := 35.0
const MAX_PICKUPS := 500
const COLLECT_RADIUS := 2.2
const MAGNET_ACCEL := 90.0
const MAGNET_TOP_SPEED := 55.0
const SCATTER_FRICTION := 3.5
const HOVER_HEIGHT := 0.7
const SCRAP_RENDER_SCALE := 1.5
const SCRAP_XP_MULTIPLIER := 3.0
const BARREL_SCRAP_PIECES := 4


class Bullet:
	extends RefCounted
	var x: float
	var y: float
	var z: float
	var vx: float
	var vz: float
	var life: float
	var damage: float


class Mine:
	extends RefCounted
	var x: float
	var y: float
	var z: float
	var vx: float
	var vy: float
	var vz: float
	var yaw: float
	var fuse: float
	var max_fuse: float
	var radius: float
	var damage: float
	var settled: bool


class Grenade:
	extends RefCounted
	var x: float
	var y: float
	var z: float
	var vx: float
	var vy: float
	var vz: float
	var yaw: float
	var pitch: float
	var roll: float
	var spin_yaw: float
	var spin_pitch: float
	var spin_roll: float
	var mode: int
	var fuse: float
	var max_fuse: float
	var age: float
	var radius: float
	var damage: float
	var kick_cooldown: float
	var trail_timer: float


class Pickup:
	extends RefCounted
	var kind: String # "scrap" or "repair"
	var x: float
	var z: float
	var vx: float
	var vz: float
	var value: float
	var phase: float
	var attracted: bool
	var spawned: bool = false


var turret_angle := 0.0
var _shot_angle := 0.0
var _gun_cooldown := 0.0
var _mine_cooldown := 0.0
var _grenade_cooldown := 0.0

var _bullets: Array[Bullet] = []
var _mines: Array[Mine] = []
var _grenades: Array[Grenade] = []
var _contact := World.Contact.new()

var _bullet_batch: SimMath.InstanceBatch
var _mine_batch: SimMath.InstanceBatch
var _mine_beacon_batch: SimMath.InstanceBatch
var _grenade_batch: SimMath.InstanceBatch
var _grenade_spark_batch: SimMath.InstanceBatch

var _pickups: Array[Pickup] = []
var _scrap_batch: SimMath.InstanceBatch
var _repair_batch: SimMath.InstanceBatch


func setup(shared_material: StandardMaterial3D) -> void:
	var bullet_mat := StandardMaterial3D.new()
	bullet_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bullet_mat.albedo_color = Color(1.0, 0.86, 0.4)
	_bullet_batch = SimMath.InstanceBatch.new(self, Models.build_bullet_model(), bullet_mat, MAX_BULLETS, false, false, "Bullets")

	var beacon_mat := StandardMaterial3D.new()
	beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beacon_mat.vertex_color_use_as_albedo = true
	beacon_mat.vertex_color_is_srgb = true
	beacon_mat.albedo_color = Color.WHITE

	_mine_batch = SimMath.InstanceBatch.new(self, Models.build_mine_model(), shared_material, MAX_MINES, false, true, "Mines")
	_mine_beacon_batch = SimMath.InstanceBatch.new(self, Models.build_mine_beacon_model(), beacon_mat, MAX_MINES, true, false, "MineBeacons")
	_grenade_batch = SimMath.InstanceBatch.new(self, Models.build_grenade_model(), shared_material, MAX_GRENADES, false, true, "Grenades")
	_grenade_spark_batch = SimMath.InstanceBatch.new(self, Models.build_grenade_spark_model(), beacon_mat, MAX_GRENADES, true, false, "GrenadeSparks")

	var sil_shader: Shader = load("res://shaders/enemy_silhouette.gdshader")

	var scrap_mat := StandardMaterial3D.new()
	scrap_mat.vertex_color_use_as_albedo = true
	scrap_mat.vertex_color_is_srgb = true
	scrap_mat.roughness = 0.85
	scrap_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	scrap_mat.emission_enabled = true
	scrap_mat.emission = Palette.SCRAP_PICKUP * 0.55
	scrap_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	scrap_mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	scrap_mat.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
	scrap_mat.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
	scrap_mat.stencil_reference = 1
	var scrap_sil_mat := ShaderMaterial.new()
	scrap_sil_mat.shader = sil_shader
	scrap_sil_mat.set_shader_parameter("veil_color", Color(0.06, 0.55, 0.96, 0.94))
	scrap_sil_mat.render_priority = 3
	scrap_mat.next_pass = scrap_sil_mat
	_scrap_batch = SimMath.InstanceBatch.new(self, Models.build_scrap_model(), scrap_mat, MAX_PICKUPS, false, false, "ScrapPickups")

	var repair_mat: StandardMaterial3D = shared_material.duplicate()
	repair_mat.emission_enabled = true
	repair_mat.emission = Palette.REPAIR * 0.35
	repair_mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	repair_mat.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
	repair_mat.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
	repair_mat.stencil_reference = 1
	var repair_sil_mat := ShaderMaterial.new()
	repair_sil_mat.shader = sil_shader
	repair_sil_mat.set_shader_parameter("veil_color", Color(0.14, 0.88, 0.36, 0.90))
	repair_sil_mat.render_priority = 2
	repair_mat.next_pass = repair_sil_mat
	_repair_batch = SimMath.InstanceBatch.new(self, Models.build_repair_model(), repair_mat, 64, false, true, "RepairPickups")


func get_pickups() -> Array[Pickup]:
	return _pickups


func clear() -> void:
	_bullets.clear()
	_mines.clear()
	_grenades.clear()
	_gun_cooldown = 0.0
	_mine_cooldown = 0.0
	_grenade_cooldown = 0.0
	_shot_angle = 0.0
	turret_angle = 0.0
	_pickups.clear()
	render_all(0.0)


func update_gun(
	dt: float,
	car: CarBody,
	stats: Upgrades.Stats,
	enemies: EnemySystem,
	on_shot: Callable,
) -> void:
	if stats.gun_barrels > 0:
		var interval := 1.0 / stats.gun_fire_rate
		_gun_cooldown = minf(_gun_cooldown - dt, interval)
		while _gun_cooldown <= 0.0:
			_gun_cooldown += interval
			_shot_angle = fposmod(_shot_angle + SPIRAL_STEP, TAU)
			var base_h := DesertTerrain.ground_height(car.x, car.z) + MUZZLE_HEIGHT
			for barrel in stats.gun_barrels:
				if _bullets.size() >= MAX_BULLETS:
					break
				var direction := _shot_angle + (float(barrel) * TAU) / float(stats.gun_barrels)
				var dx := sin(direction)
				var dz := cos(direction)
				var b := Bullet.new()
				b.x = car.x + dx * MUZZLE_OFFSET
				b.y = base_h
				b.z = car.z + dz * MUZZLE_OFFSET
				b.vx = dx * BULLET_SPEED + car.vx * 0.5
				b.vz = dz * BULLET_SPEED + car.vz * 0.5
				b.life = BULLET_LIFE
				b.damage = stats.gun_damage
				_bullets.append(b)
			if on_shot.is_valid():
				on_shot.call()
		var progress := 1.0 - _gun_cooldown / interval
		turret_angle = _shot_angle + SPIRAL_STEP * progress

	for i in range(_bullets.size() - 1, -1, -1):
		var b := _bullets[i]
		b.life -= dt
		b.x += b.vx * dt
		b.z += b.vz * dt
		var spent := b.life <= 0.0
		if not spent:
			var enemy := enemies.first_within(b.x, b.z, BULLET_RADIUS)
			if enemy != null:
				enemies.hurt(enemy, b.damage)
				enemy.flinch = 1.0
				spent = true
		if spent:
			_bullets[i] = _bullets[_bullets.size() - 1]
			_bullets.pop_back()


func update_explosives(
	dt: float,
	car: CarBody,
	stats: Upgrades.Stats,
	enemies: EnemySystem,
	world: World,
	smoke: SmokeSystem,
	on_explode: Callable,
	on_mine_drop: Callable = Callable(),
	on_grenade_toss: Callable = Callable(),
	on_grenade_kick: Callable = Callable(),
) -> void:
	_update_mines(dt, car, stats, enemies, on_explode, on_mine_drop)
	_update_grenades(dt, car, stats, enemies, world, smoke, on_explode, on_grenade_toss, on_grenade_kick)


func _update_mines(
	dt: float,
	car: CarBody,
	stats: Upgrades.Stats,
	enemies: EnemySystem,
	on_explode: Callable,
	on_mine_drop: Callable,
) -> void:
	if stats.mine_interval > 0.0:
		_mine_cooldown = minf(_mine_cooldown - dt, stats.mine_interval)
		if _mine_cooldown <= 0.0:
			_mine_cooldown += stats.mine_interval
			_spawn_mines(car, stats)
			if on_mine_drop.is_valid():
				on_mine_drop.call()
	else:
		_mine_cooldown = 0.0

	var drag := exp(-MINE_GROUND_DRAG * dt)
	for i in range(_mines.size() - 1, -1, -1):
		var m := _mines[i]
		m.fuse -= dt

		if not m.settled:
			m.vy -= MINE_GRAVITY * dt
			m.x += m.vx * dt
			m.y += m.vy * dt
			m.z += m.vz * dt
			var fl := DesertTerrain.ground_height(m.x, m.z)
			if m.y <= fl:
				m.y = fl
				m.vy = 0.0
				m.settled = true
		else:
			m.vx *= drag
			m.vz *= drag
			m.x += m.vx * dt
			m.z += m.vz * dt
			m.y = DesertTerrain.ground_height(m.x, m.z)

		var triggered := m.fuse <= 0.0
		if not triggered:
			triggered = enemies.first_within(m.x, m.z, MINE_TRIGGER_RADIUS) != null

		if triggered:
			_mines[i] = _mines[_mines.size() - 1]
			_mines.pop_back()
			if on_explode.is_valid():
				on_explode.call(m.x, m.z, m.radius, m.damage)


func _spawn_mines(car: CarBody, stats: Upgrades.Stats) -> void:
	var fx := sin(car.heading)
	var fz := cos(car.heading)
	var rx := fz
	var rz := -fx
	var count := maxi(1, stats.explosive_count)
	var spread := 0.0 if count == 1 else (1.15 if count == 2 else 1.55)

	for i in count:
		if _mines.size() >= MAX_MINES:
			break
		var t := 0.0 if count == 1 else (float(i) / float(count - 1) * 2.0 - 1.0)
		var lateral := t * spread + SimMath.rand_signed(0.2)
		var rear := MINE_DROP_REAR + absf(t) * 0.35 + SimMath.rand_signed(0.15)
		var mx := car.x - fx * rear + rx * lateral
		var mz := car.z - fz * rear + rz * lateral
		var m := Mine.new()
		m.x = mx
		m.z = mz
		m.y = DesertTerrain.ground_height(mx, mz) + 0.45
		m.vx = car.vx * 0.14 + rx * t * 2.6
		m.vz = car.vz * 0.14 + rz * t * 2.6
		m.vy = 1.8
		m.yaw = randf() * TAU
		m.fuse = Upgrades.MINE_FUSE
		m.max_fuse = Upgrades.MINE_FUSE
		m.radius = stats.mine_radius
		m.damage = stats.mine_damage
		m.settled = false
		_mines.append(m)


func _update_grenades(
	dt: float,
	car: CarBody,
	stats: Upgrades.Stats,
	enemies: EnemySystem,
	world: World,
	smoke: SmokeSystem,
	on_explode: Callable,
	on_grenade_toss: Callable,
	on_grenade_kick: Callable,
) -> void:
	if stats.grenade_interval > 0.0:
		_grenade_cooldown = minf(_grenade_cooldown - dt, stats.grenade_interval)
		if _grenade_cooldown <= 0.0:
			_grenade_cooldown += stats.grenade_interval
			_spawn_grenades(car, stats)
			if on_grenade_toss.is_valid():
				on_grenade_toss.call()
	else:
		_grenade_cooldown = 0.0

	var air_drag := exp(-GRENADE_AIR_DRAG * dt)
	var ground_drag := exp(-GRENADE_SLIDE_FRICTION * dt)

	for i in range(_grenades.size() - 1, -1, -1):
		var g := _grenades[i]
		g.age += dt
		g.fuse -= dt
		g.kick_cooldown = maxf(0.0, g.kick_cooldown - dt)

		if g.mode == MODE_AIR:
			g.vy -= GRENADE_GRAVITY * dt
			g.vx *= air_drag
			g.vz *= air_drag
			g.x += g.vx * dt
			g.y += g.vy * dt
			g.z += g.vz * dt
			g.yaw += g.spin_yaw * dt
			g.pitch += g.spin_pitch * dt
			g.roll += g.spin_roll * dt

			var fl := DesertTerrain.ground_height(g.x, g.z) + GRENADE_CLEARANCE
			if g.y <= fl and g.vy <= 0.0:
				g.y = fl
				var impact := -g.vy
				var spd := sqrt(g.vx * g.vx + g.vz * g.vz)
				if impact > GRENADE_SETTLE_SPEED:
					g.vy = impact * GRENADE_BOUNCE
					g.vx *= GRENADE_BOUNCE_KEEP
					g.vz *= GRENADE_BOUNCE_KEEP
					var tumble := clampf(spd * 0.9 + impact * 0.6, 3.0, 16.0)
					g.spin_yaw = SimMath.rand_signed(tumble)
					g.spin_pitch = SimMath.rand_signed(tumble)
					g.spin_roll = SimMath.rand_signed(tumble)
				else:
					g.vy = 0.0
					g.mode = MODE_GROUND
		else:
			g.vx *= ground_drag
			g.vz *= ground_drag
			g.x += g.vx * dt
			g.z += g.vz * dt
			var spd := sqrt(g.vx * g.vx + g.vz * g.vz)
			if spd > 0.2:
				g.yaw += SimMath.wrap_angle(atan2(g.vx, g.vz) - g.yaw) * minf(1.0, 8.0 * dt)
				g.pitch += (spd / GRENADE_CLEARANCE) * dt
			else:
				g.spin_yaw *= exp(-4.0 * dt)
				g.yaw += g.spin_yaw * dt
			g.y = DesertTerrain.ground_height(g.x, g.z) + GRENADE_CLEARANCE

		if world != null and world.resolve(g, GRENADE_PHYS_RADIUS, _contact).hit:
			var into := g.vx * _contact.nx + g.vz * _contact.nz
			if into < 0.0:
				g.vx -= (1.0 + GRENADE_WALL_BOUNCE) * into * _contact.nx
				g.vz -= (1.0 + GRENADE_WALL_BOUNCE) * into * _contact.nz
				g.spin_yaw = SimMath.rand_signed(16.0)
				g.spin_pitch = SimMath.rand_signed(16.0)

		# Debris physics: enemies (and wrecks / player after brief grace) toss the grenade
		# around instead of triggering early detonation.
		if g.kick_cooldown <= 0.0:
			var gnd := DesertTerrain.ground_height(g.x, g.z)
			if g.y <= gnd + 2.3:
				var kicked := false
				var kicker := enemies.first_within(g.x, g.z, GRENADE_COLLIDE_RADIUS)
				if kicker != null:
					kicked = _try_kick_grenade_by_circle(g, kicker.x, kicker.z, kicker.vx, kicker.vz, kicker.spec.radius, on_grenade_kick)
				if not kicked:
					kicked = _try_kick_grenade_by_enemies(g, enemies.wrecks, on_grenade_kick)
				if not kicked and g.age > GRENADE_PLAYER_GRACE:
					_try_kick_grenade_by_circle(g, car.x, car.z, car.vx, car.vz, 1.45, on_grenade_kick)

		# Subtle fuse spark/soot trail so bouncing grenades stay readable
		if smoke != null:
			g.trail_timer -= dt
			if g.trail_timer <= 0.0:
				g.trail_timer = GRENADE_TRAIL_INTERVAL
				smoke.emit(
					SmokeSystem.PUFF_FIRE if g.fuse < 0.55 else SmokeSystem.PUFF_SOOT,
					g.x, g.y + 0.2, g.z,
					g.vx * 0.12, 1.2, g.vz * 0.12,
					0.24, 0.85, 0.35, 0.7, 1.4,
				)

		if g.fuse <= 0.0:
			_grenades[i] = _grenades[_grenades.size() - 1]
			_grenades.pop_back()
			if on_explode.is_valid():
				on_explode.call(g.x, g.z, g.radius, g.damage)


func _spawn_grenades(car: CarBody, stats: Upgrades.Stats) -> void:
	var fx := sin(car.heading)
	var fz := cos(car.heading)
	var count := maxi(1, stats.explosive_count)
	var max_fan := 0.0 if count == 1 else (0.36 if count == 2 else 0.52)

	for i in count:
		if _grenades.size() >= MAX_GRENADES:
			break
		var t := 0.0 if count == 1 else (float(i) / float(count - 1) * 2.0 - 1.0)
		var angle := car.heading + PI + t * max_fan + SimMath.rand_signed(0.12)
		var throw_spd := randf_range(9.5, 13.5)
		var gx := car.x - fx * GRENADE_DROP_REAR + fz * t * 0.55
		var gz := car.z - fz * GRENADE_DROP_REAR - fx * t * 0.55
		var g := Grenade.new()
		g.x = gx
		g.z = gz
		g.y = DesertTerrain.ground_height(gx, gz) + GRENADE_LAUNCH_HEIGHT
		g.vx = car.vx * 0.42 + sin(angle) * throw_spd
		g.vz = car.vz * 0.42 + cos(angle) * throw_spd
		g.vy = randf_range(7.0, 10.5)
		g.yaw = angle
		g.pitch = randf() * TAU
		g.roll = randf() * TAU
		g.spin_yaw = SimMath.rand_signed(12.0)
		g.spin_pitch = randf_range(9.0, 16.0) * (-1.0 if randf() < 0.5 else 1.0)
		g.spin_roll = SimMath.rand_signed(12.0)
		g.mode = MODE_AIR
		g.fuse = Upgrades.GRENADE_FUSE
		g.max_fuse = Upgrades.GRENADE_FUSE
		g.age = 0.0
		g.radius = stats.grenade_radius
		g.damage = stats.grenade_damage
		g.kick_cooldown = 0.0
		g.trail_timer = randf() * GRENADE_TRAIL_INTERVAL
		_grenades.append(g)


func _try_kick_grenade_by_enemies(g: Grenade, list: Array[EnemySystem.Enemy], on_kick: Callable) -> bool:
	for enemy in list:
		if _try_kick_grenade_by_circle(g, enemy.x, enemy.z, enemy.vx, enemy.vz, enemy.spec.radius, on_kick):
			return true
	return false


func _try_kick_grenade_by_circle(
	g: Grenade,
	cx: float,
	cz: float,
	cvx: float,
	cvz: float,
	c_radius: float,
	on_kick: Callable,
) -> bool:
	var reach := c_radius + GRENADE_COLLIDE_RADIUS
	var dx := g.x - cx
	var dz := g.z - cz
	var dist_sq := dx * dx + dz * dz
	if dist_sq > reach * reach:
		return false
	var dist := sqrt(dist_sq)
	var nx := 0.0
	var nz := 0.0
	if dist > 0.01:
		nx = dx / dist
		nz = dz / dist
	else:
		var a := randf() * TAU
		nx = sin(a)
		nz = cos(a)

	# Push out of overlap and launch like debris
	g.x = cx + nx * (reach + 0.18)
	g.z = cz + nz * (reach + 0.18)
	var cspd := sqrt(cvx * cvx + cvz * cvz)
	var punt := maxf(8.5, cspd * 0.7) + randf_range(3.0, 7.0)
	g.vx = cvx * 0.85 + nx * punt + SimMath.rand_signed(2.5)
	g.vz = cvz * 0.85 + nz * punt + SimMath.rand_signed(2.5)
	g.vy = maxf(g.vy, randf_range(6.5, 11.5) + minf(4.5, cspd * 0.16))
	g.mode = MODE_AIR
	g.spin_yaw = SimMath.rand_signed(20.0)
	g.spin_pitch = SimMath.rand_signed(22.0)
	g.spin_roll = SimMath.rand_signed(20.0)
	g.kick_cooldown = GRENADE_KICK_COOLDOWN
	if on_kick.is_valid():
		on_kick.call(g.x, g.y, g.z, g.vx, g.vz)
	return true


func drop_pickup(kind: String, x: float, z: float, pieces: int, value_each: float) -> void:
	for _i in pieces:
		if _pickups.size() >= MAX_PICKUPS:
			for item in _pickups:
				if item.kind == kind:
					item.value += value_each
					break
			continue
		var angle := randf() * TAU
		var spd := randf_range(2.0, 9.0)
		var p := Pickup.new()
		p.kind = kind
		p.x = x
		p.z = z
		p.vx = sin(angle) * spd
		p.vz = cos(angle) * spd
		p.value = value_each
		p.phase = randf() * TAU
		p.attracted = false
		p.spawned = false
		_pickups.append(p)


func place_pickup(kind: String, x: float, z: float, value: float, spawned: bool = true) -> void:
	if _pickups.size() >= MAX_PICKUPS:
		return
	var p := Pickup.new()
	p.kind = kind
	p.x = x
	p.z = z
	p.vx = 0.0
	p.vz = 0.0
	p.value = value
	p.phase = randf() * TAU
	p.attracted = false
	p.spawned = spawned
	_pickups.append(p)


func place_pickup_cluster(kind: String, x: float, z: float, pieces: int, value_each: float) -> void:
	if pieces <= 1:
		place_pickup(kind, x, z, value_each, true)
		return
	var base_angle := randf() * TAU
	var ring_r := 0.95
	for i in pieces:
		var angle := base_angle + (float(i) / float(pieces)) * TAU + randf_range(-0.2, 0.2)
		var dist := ring_r * randf_range(0.8, 1.15)
		place_pickup(kind, x + sin(angle) * dist, z + cos(angle) * dist, value_each, true)


func update_pickups(dt: float, car: CarBody, magnet_radius: float, on_collect: Callable) -> void:
	var friction := exp(-SCATTER_FRICTION * dt)
	for i in range(_pickups.size() - 1, -1, -1):
		var item := _pickups[i]
		var dx := car.x - item.x
		var dz := car.z - item.z
		var dist := sqrt(dx * dx + dz * dz)
		if dist < 0.001:
			dist = 0.001
		if dist < COLLECT_RADIUS:
			on_collect.call(item.kind, item.value)
			_pickups[i] = _pickups[_pickups.size() - 1]
			_pickups.pop_back()
			continue
		if dist < magnet_radius:
			item.attracted = true
		if item.attracted:
			item.vx += (dx / dist) * MAGNET_ACCEL * dt
			item.vz += (dz / dist) * MAGNET_ACCEL * dt
			var spd := sqrt(item.vx * item.vx + item.vz * item.vz)
			var along := (item.vx * dx + item.vz * dz) / dist
			var steer_to_car := minf(1.0, 6.0 * dt)
			item.vx += ((dx / dist) * maxf(along, spd) - item.vx) * steer_to_car
			item.vz += ((dz / dist) * maxf(along, spd) - item.vz) * steer_to_car
			var top := MAGNET_TOP_SPEED + car.speed
			if spd > top:
				item.vx *= top / spd
				item.vz *= top / spd
		else:
			item.vx *= friction
			item.vz *= friction
		item.x += item.vx * dt
		item.z += item.vz * dt


func render_all(time_s: float) -> void:
	_bullet_batch.begin()
	for b in _bullets:
		_bullet_batch.push(b.x, b.y, b.z, atan2(b.vx, b.vz), 0.0, 0.0, 1.0, 1.0, 1.0)
	_bullet_batch.commit()

	_mine_batch.begin()
	_mine_beacon_batch.begin()
	for m in _mines:
		_mine_batch.push(m.x, m.y, m.z, m.yaw, 0.0, 0.0, 1.0, 1.0, 1.0)
		var urgency := 1.0 - clampf(m.fuse / maxf(0.01, m.max_fuse), 0.0, 1.0)
		var rate := lerpf(4.0, 22.0, urgency * urgency)
		var blink := 0.5 + 0.5 * sin(time_s * rate * PI)
		var sc := 0.85 + 0.45 * blink
		_mine_beacon_batch.push(m.x, m.y, m.z, m.yaw, 0.0, 0.0, sc, sc, sc)
		var col := Color(0.42, 0.08, 0.06).lerp(Color(1.0, 0.22, 0.14), blink)
		_mine_beacon_batch.tint(col)
	_mine_batch.commit()
	_mine_beacon_batch.commit()

	_grenade_batch.begin()
	_grenade_spark_batch.begin()
	for g in _grenades:
		_grenade_batch.push(g.x, g.y, g.z, g.yaw, g.pitch, g.roll, 1.0, 1.0, 1.0)
		var urgency := 1.0 - clampf(g.fuse / maxf(0.01, g.max_fuse), 0.0, 1.0)
		var flash := 0.5 + 0.5 * sin(time_s * lerpf(10.0, 34.0, urgency) * PI)
		var sc := 0.7 + 0.8 * flash
		_grenade_spark_batch.push(g.x, g.y, g.z, g.yaw, g.pitch, g.roll, sc, sc, sc)
		var col := Color(1.0, 0.42, 0.12).lerp(Color(1.0, 0.96, 0.65), flash)
		_grenade_spark_batch.tint(col)
	_grenade_batch.commit()
	_grenade_spark_batch.commit()

	_scrap_batch.begin()
	_repair_batch.begin()
	for item in _pickups:
		var y := DesertTerrain.ground_height(item.x, item.z) + HOVER_HEIGHT + sin(time_s * 3.0 + item.phase) * 0.15
		var spin := time_s * 2.4 + item.phase
		if item.kind == "scrap":
			var sz := (1.5 if item.value >= 5.0 else (1.15 if item.value >= 2.0 else 0.9)) * SCRAP_RENDER_SCALE
			_scrap_batch.push(item.x, y, item.z, spin, 0.4, 0.0, sz, sz, sz)
		else:
			var sz := 2.0 if item.value > REPAIR_DROP_VALUE else 1.2
			_repair_batch.push(item.x, y + 0.55 * sz, item.z, spin, 0.0, 0.0, sz, sz, sz)
	_scrap_batch.commit()
	_repair_batch.commit()

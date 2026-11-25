class_name Combat
extends Node3D

# Direct 1:1 port of src/combat.ts: GunSystem (spiral turret + bullets)
# and PickupSystem (scrap XP hexes + repair crates with magnet pull).

const MAX_BULLETS := 400
const BULLET_SPEED := 58.0
const BULLET_LIFE := 0.8
const BULLET_RADIUS := 0.35
const SPIRAL_STEP := 0.41
const MUZZLE_HEIGHT := 1.9
const MUZZLE_OFFSET := 1.2

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


var turret_angle := 0.0
var _shot_angle := 0.0
var _gun_cooldown := 0.0
var _bullets: Array[Bullet] = []
var _bullet_batch: SimMath.InstanceBatch

var _pickups: Array[Pickup] = []
var _scrap_batch: SimMath.InstanceBatch
var _repair_batch: SimMath.InstanceBatch


func setup(shared_material: StandardMaterial3D) -> void:
	var bullet_mat := StandardMaterial3D.new()
	bullet_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bullet_mat.albedo_color = Color(1.0, 0.86, 0.4)
	_bullet_batch = SimMath.InstanceBatch.new(self, Models.build_bullet_model(), bullet_mat, MAX_BULLETS, false, false, "Bullets")

	var sil_shader: Shader = load("res://shaders/enemy_silhouette.gdshader")

	var scrap_mat := StandardMaterial3D.new()
	scrap_mat.vertex_color_use_as_albedo = true
	scrap_mat.roughness = 0.85
	scrap_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	scrap_mat.emission_enabled = true
	scrap_mat.emission = Palette.SCRAP * 0.45
	scrap_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	scrap_mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	scrap_mat.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
	scrap_mat.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
	scrap_mat.stencil_reference = 1
	var scrap_sil_mat := ShaderMaterial.new()
	scrap_sil_mat.shader = sil_shader
	scrap_sil_mat.set_shader_parameter("veil_color", Color(0.96, 0.64, 0.02, 0.94))
	scrap_sil_mat.render_priority = 3
	scrap_mat.next_pass = scrap_sil_mat
	_scrap_batch = SimMath.InstanceBatch.new(self, Models.build_scrap_model(), scrap_mat, MAX_PICKUPS, false, false, "ScrapPickups")

	var repair_mat: StandardMaterial3D = shared_material.duplicate()
	repair_mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	repair_mat.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
	repair_mat.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
	repair_mat.stencil_reference = 1
	var repair_sil_mat := ShaderMaterial.new()
	repair_sil_mat.shader = sil_shader
	repair_sil_mat.set_shader_parameter("veil_color", Color(0.24, 0.76, 0.38, 0.82))
	repair_sil_mat.render_priority = 2
	repair_mat.next_pass = repair_sil_mat
	_repair_batch = SimMath.InstanceBatch.new(self, Models.build_repair_model(), repair_mat, 32, false, true, "RepairPickups")


func clear() -> void:
	_bullets.clear()
	_gun_cooldown = 0.0
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
	hit_barrels: Callable,
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
		if not spent and hit_barrels.is_valid():
			spent = hit_barrels.call(b.x, b.z, BULLET_RADIUS)
		if not spent:
			for enemy in enemies.active:
				var reach := enemy.spec.radius + BULLET_RADIUS
				var dx := enemy.x - b.x
				var dz := enemy.z - b.z
				if dx * dx + dz * dz > reach * reach:
					continue
				enemies.hurt(enemy, b.damage)
				enemy.flinch = 1.0
				spent = true
				break
		if spent:
			_bullets[i] = _bullets[_bullets.size() - 1]
			_bullets.pop_back()


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
		_pickups.append(p)


func place_pickup(kind: String, x: float, z: float, value: float) -> void:
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
	_pickups.append(p)


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
			_repair_batch.push(item.x, y + 0.2, item.z, spin, 0.0, 0.0, sz, sz, sz)
	_scrap_batch.commit()
	_repair_batch.commit()

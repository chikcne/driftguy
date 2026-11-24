class_name GibSystem
extends Node3D

# Direct 1:1 port of src/gibs.ts: enemies burst into flying wreckage pieces
# (chassis plates, bouncing/rolling wheels, pipes, spikes, skulls, sparks, thrown riders)
# trailing soot & fire smoke before settling and fading.

const SHAPES := ["box", "wheel", "pipe", "spike", "skull", "spark", "rider"]
const BAKED_SHAPES := ["wheel", "spark", "rider"]
const RIDER_HEIGHT := 1.1
const RIDER_THICKNESS := 0.34
const MAX_GIBS := 640
const GRAVITY := 30.0
const AIR_DRAG := 0.25
const BOUNCE := 0.36
const WHEEL_BOUNCE := 0.58
const BOUNCE_KEEP := 0.72
const SETTLE_SPEED := 3.0
const SLIDE_FRICTION := 4.5
const ROLL_FRICTION := 0.55
const TOPPLE_SPEED := 2.2
const TOPPLE_FRICTION := 3.0
const REST_SPEED := 0.5
const FADE_SECONDS := 0.6
const INHERIT := 0.45
const TRAIL_INTERVAL := 0.06
const TRAIL_SECONDS := 1.4
const HALF_TURN := PI

const MODE_AIR := 0
const MODE_GROUND := 1
const MODE_REST := 2

const TRAIL_NONE := 0
const TRAIL_SOOT := 1
const TRAIL_FIRE := 2


class Part:
	extends RefCounted
	var shape: String
	var size: Vector3
	var at: Vector3
	var color: Color

	func _init(p_shape: String, p_size: Vector3, p_at: Vector3, p_color: Color) -> void:
		shape = p_shape
		size = p_size
		at = p_at
		color = p_color


class Gib:
	extends RefCounted
	var live: bool = false
	var shape: String = "box"
	var mode: int = MODE_AIR
	var x: float = 0.0
	var y: float = 0.0
	var z: float = 0.0
	var vx: float = 0.0
	var vy: float = 0.0
	var vz: float = 0.0
	var yaw: float = 0.0
	var pitch: float = 0.0
	var roll: float = 0.0
	var spin_yaw: float = 0.0
	var spin_pitch: float = 0.0
	var spin_roll: float = 0.0
	var sx: float = 1.0
	var sy: float = 1.0
	var sz: float = 1.0
	var color: Color = Color.WHITE
	var clearance: float = 0.0
	var rest_clearance: float = 0.0
	var age: float = 0.0
	var life: float = 0.0
	var trail: int = TRAIL_NONE
	var trail_timer: float = 0.0


var _pool: Array[Gib] = []
var _batches: Dictionary = {} # String -> SimMath.InstanceBatch
var _recipes: Dictionary = {} # String -> Array[Part]
var _cursor := 0


static func _box(sz: Vector3, at: Vector3, col: Color) -> Part:
	return Part.new("box", sz, at, col)


static func _pipe(diam: float, length: float, at: Vector3, col: Color) -> Part:
	return Part.new("pipe", Vector3(diam, diam, length), at, col)


static func _spike(length: float, at: Vector3) -> Part:
	return Part.new("spike", Vector3(0.2, 0.2, length), at, Palette.RAIDER_BONE)


static func _skull(diam: float, at: Vector3) -> Part:
	return Part.new("skull", Vector3(diam, diam, diam), at, Palette.RAIDER_BONE)


static func _wheel(diam: float, width: float, at: Vector3) -> Part:
	return Part.new("wheel", Vector3(width, diam, diam), at, Palette.RUBBER)


static func _add_axle(arr: Array[Part], x: float, z: float, diam: float, width: float) -> void:
	arr.append(_wheel(diam, width, Vector3(x, diam * 0.5, z)))
	arr.append(_wheel(diam, width, Vector3(-x, diam * 0.5, z)))


func _build_recipes() -> void:
	var bike: Array[Part] = [
		_wheel(0.72, 0.2, Vector3(0.0, 0.36, 0.85)),
		_wheel(0.72, 0.24, Vector3(0.0, 0.36, -0.8)),
		_box(Vector3(0.26, 0.34, 0.8), Vector3(0.0, 0.62, 0.4), Palette.RAIDER_RED),
		_box(Vector3(0.26, 0.34, 0.7), Vector3(0.0, 0.62, -0.4), Palette.RAIDER_RED),
		_box(Vector3(0.34, 0.24, 0.5), Vector3(0.0, 0.82, 0.2), Palette.RAIDER_BLACK),
		_box(Vector3(0.8, 0.07, 0.07), Vector3(0.0, 1.02, 0.62), Palette.METAL_DARK),
		_box(Vector3(0.06, 0.06, 1.5), Vector3(0.0, 1.5, -0.85), Palette.METAL_DARK),
		_box(Vector3(0.6, 0.04, 0.34), Vector3(0.0, 2.05, -1.15), Palette.RAIDER_RED),
	]

	var buggy: Array[Part] = []
	_add_axle(buggy, 0.95, 1.05, 0.9, 0.36)
	_add_axle(buggy, 1.0, -1.05, 1.0, 0.44)
	buggy.append_array([
		_box(Vector3(1.5, 0.3, 1.5), Vector3(0.0, 0.6, 0.75), Palette.RUST),
		_box(Vector3(1.5, 0.3, 1.5), Vector3(0.0, 0.6, -0.75), Palette.RUST),
		_box(Vector3(1.2, 0.34, 1.0), Vector3(0.0, 0.86, 1.0), Palette.RAIDER_RED),
		_box(Vector3(1.0, 0.5, 0.8), Vector3(0.0, 0.98, -1.05), Palette.METAL_DARK),
		_pipe(0.14, 0.9, Vector3(0.3, 1.5, -1.2), Palette.METAL),
		_pipe(0.14, 0.9, Vector3(-0.3, 1.5, -1.2), Palette.METAL),
		_box(Vector3(0.08, 0.08, 1.0), Vector3(0.66, 1.25, 0.45), Palette.RAIDER_BLACK),
		_box(Vector3(0.08, 0.08, 1.0), Vector3(-0.66, 1.25, 0.45), Palette.RAIDER_BLACK),
		_box(Vector3(0.08, 0.08, 1.0), Vector3(0.66, 1.25, -0.5), Palette.RAIDER_BLACK),
		_box(Vector3(0.08, 0.08, 1.0), Vector3(-0.66, 1.25, -0.5), Palette.RAIDER_BLACK),
		_box(Vector3(1.4, 0.08, 1.0), Vector3(0.0, 1.72, 0.0), Palette.RAIDER_BLACK),
		_skull(0.44, Vector3(0.0, 1.3, -0.05)),
		_box(Vector3(1.7, 0.16, 0.16), Vector3(0.0, 0.6, 1.58), Palette.METAL_DARK),
		_spike(0.6, Vector3(0.6, 0.62, 1.86)),
		_spike(0.7, Vector3(0.0, 0.62, 1.9)),
		_spike(0.6, Vector3(-0.6, 0.62, 1.86)),
	])

	var truck: Array[Part] = []
	_add_axle(truck, 1.2, 1.8, 1.2, 0.5)
	_add_axle(truck, 1.2, -0.9, 1.2, 0.5)
	_add_axle(truck, 1.2, -2.2, 1.2, 0.5)
	truck.append_array([
		_box(Vector3(2.2, 0.5, 2.8), Vector3(0.0, 0.95, 1.2), Palette.RAIDER_BLACK),
		_box(Vector3(2.2, 0.5, 2.8), Vector3(0.0, 0.95, -1.6), Palette.RAIDER_BLACK),
		_box(Vector3(2.2, 0.7, 1.7), Vector3(0.0, 1.55, 1.5), Palette.RUST_DARK),
		_box(Vector3(2.2, 0.12, 1.7), Vector3(0.0, 2.45, 1.5), Palette.RUST_DARK),
		_box(Vector3(1.9, 0.1, 0.5), Vector3(0.0, 2.0, 2.37), Palette.GLASS),
		_box(Vector3(2.3, 0.14, 1.6), Vector3(1.1, 1.7, -1.3), Palette.RUST),
		_box(Vector3(2.3, 0.14, 1.6), Vector3(-1.1, 1.7, -1.3), Palette.RUST),
		_box(Vector3(2.3, 0.14, 1.0), Vector3(0.0, 1.7, -2.9), Palette.RUST),
		_box(Vector3(2.36, 0.14, 3.36), Vector3(0.0, 2.26, -1.3), Palette.RUST_LIGHT),
		_box(Vector3(1.5, 0.14, 1.1), Vector3(0.7, 0.85, 2.85), Palette.METAL),
		_box(Vector3(1.5, 0.14, 1.1), Vector3(-0.7, 0.85, 2.85), Palette.METAL),
		_pipe(0.2, 1.6, Vector3(1.0, 3.0, 0.55), Palette.METAL),
		_pipe(0.2, 1.6, Vector3(-1.0, 3.0, 0.55), Palette.METAL),
		_skull(0.68, Vector3(0.0, 1.5, 2.42)),
		_box(Vector3(0.08, 0.08, 1.7), Vector3(0.9, 3.1, -2.6), Palette.METAL_DARK),
		_box(Vector3(0.8, 0.05, 0.5), Vector3(0.9, 3.7, -3.0), Palette.RAIDER_RED),
	])

	var interceptor: Array[Part] = []
	_add_axle(interceptor, 0.95, 1.3, 0.76, 0.34)
	_add_axle(interceptor, 1.0, -1.3, 0.86, 0.44)
	interceptor.append_array([
		_box(Vector3(1.86, 0.46, 2.2), Vector3(0.0, 0.6, 1.1), Palette.RAIDER_PURPLE),
		_box(Vector3(1.86, 0.46, 2.2), Vector3(0.0, 0.6, -1.1), Palette.RAIDER_PURPLE),
		_box(Vector3(1.5, 0.4, 1.7), Vector3(0.0, 1.0, -0.5), Palette.RAIDER_BLACK),
		_box(Vector3(1.56, 0.08, 1.4), Vector3(0.0, 1.24, -0.55), Palette.RAIDER_PURPLE),
		_box(Vector3(0.6, 0.42, 0.7), Vector3(0.0, 1.0, 1.15), Palette.METAL),
		_box(Vector3(0.7, 0.16, 0.5), Vector3(0.0, 1.28, 1.2), Palette.RAIDER_YELLOW),
		_box(Vector3(1.9, 0.08, 0.5), Vector3(0.0, 1.1, -2.1), Palette.RAIDER_BLACK),
		_box(Vector3(1.96, 0.2, 0.2), Vector3(0.0, 0.46, 2.26), Palette.METAL_DARK),
		_pipe(0.18, 1.6, Vector3(1.02, 0.5, -1.2), Palette.METAL),
		_pipe(0.18, 1.6, Vector3(-1.02, 0.5, -1.2), Palette.METAL),
		_spike(0.7, Vector3(0.7, 0.5, 2.6)),
		_spike(0.7, Vector3(-0.7, 0.5, 2.6)),
	])

	var rig: Array[Part] = []
	for z_off in [3.6, 1.0, -0.3, -3.0, -4.3]:
		_add_axle(rig, 1.45, z_off, 1.4, 0.6)
	rig.append_array([
		_box(Vector3(2.7, 0.6, 3.6), Vector3(0.0, 1.15, 3.1), Palette.RAIDER_BLACK),
		_box(Vector3(2.7, 0.6, 3.5), Vector3(0.0, 1.15, -0.4), Palette.RAIDER_BLACK),
		_box(Vector3(2.7, 0.6, 3.5), Vector3(0.0, 1.15, -3.9), Palette.RAIDER_BLACK),
		_box(Vector3(2.7, 0.9, 2.2), Vector3(0.0, 1.9, 3.4), Palette.RAIDER_RED),
		_box(Vector3(2.7, 0.16, 2.2), Vector3(0.0, 3.1, 3.4), Palette.RAIDER_RED),
		_box(Vector3(2.3, 0.1, 0.6), Vector3(0.0, 2.6, 4.52), Palette.GLASS),
		_box(Vector3(2.4, 1.0, 1.4), Vector3(0.0, 1.9, 5.0), Palette.RUST_DARK),
		_pipe(2.6, 2.2, Vector3(0.0, 2.75, 0.3), Palette.RUST),
		_pipe(2.6, 2.2, Vector3(0.0, 2.75, -1.9), Palette.RUST),
		_pipe(2.6, 2.2, Vector3(0.0, 2.75, -4.1), Palette.RUST),
		_pipe(2.7, 0.3, Vector3(0.0, 2.75, 0.2), Palette.RUST_DARK),
		_pipe(2.7, 0.3, Vector3(0.0, 2.75, -4.0), Palette.RUST_DARK),
		_box(Vector3(2.2, 0.18, 1.5), Vector3(0.95, 1.1, 5.95), Palette.METAL),
		_box(Vector3(2.2, 0.18, 1.5), Vector3(-0.95, 1.1, 5.95), Palette.METAL),
		_pipe(0.26, 2.4, Vector3(1.2, 4.0, 2.5), Palette.METAL),
		_pipe(0.26, 2.4, Vector3(-1.2, 4.0, 2.5), Palette.METAL),
		_skull(1.0, Vector3(0.0, 2.2, 5.75)),
		_spike(0.9, Vector3(0.0, 4.4, -3.4)),
		_spike(0.9, Vector3(0.0, 4.4, -2.0)),
		_spike(0.9, Vector3(0.0, 4.4, -0.6)),
		_box(Vector3(0.1, 0.1, 2.4), Vector3(1.2, 5.0, -4.6), Palette.METAL_DARK),
		_box(Vector3(1.3, 0.06, 0.8), Vector3(1.2, 5.8, -5.3), Palette.RAIDER_YELLOW),
	])

	_recipes = {
		"bike": bike,
		"buggy": buggy,
		"truck": truck,
		"interceptor": interceptor,
		"rig": rig,
	}


func setup(shared_material: StandardMaterial3D) -> void:
	_build_recipes()
	var models := Models.build_gib_models()

	var glow_mat := StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.albedo_color = Color(1.0, 0.8, 0.36)

	for shape: String in SHAPES:
		var tinted := not BAKED_SHAPES.has(shape)
		var mat: Material = glow_mat if shape == "spark" else shared_material
		var casts := shape != "spark"
		_batches[shape] = SimMath.InstanceBatch.new(self, models[shape], mat, MAX_GIBS, tinted, casts, "Gib_" + shape)

	_pool.resize(MAX_GIBS)
	for i in MAX_GIBS:
		_pool[i] = Gib.new()


func clear() -> void:
	for g in _pool:
		g.live = false
	_render()


func burst(
	kind: String,
	x: float,
	z: float,
	heading: float,
	vx: float,
	vz: float,
	push_x: float,
	push_z: float,
	power: float,
	burning: bool,
) -> void:
	var fx := sin(heading)
	var fz := cos(heading)
	var base := DesertTerrain.ground_height(x, z)
	var trail_chance := 0.5 if burning else 0.16
	var pieces: Array[Part] = _recipes[kind]
	for piece in pieces:
		var ox := piece.at.x
		var oy := piece.at.y
		var oz := piece.at.z
		var off_x := oz * fx + ox * fz
		var off_z := oz * fz - ox * fx
		var reach := sqrt(off_x * off_x + off_z * off_z)
		var stray := randf() * TAU
		var dir_x := off_x / reach if reach > 0.25 else sin(stray)
		var dir_z := off_z / reach if reach > 0.25 else cos(stray)
		var largest := maxf(piece.size.x, maxf(piece.size.y, piece.size.z))
		var heft := 1.0 / (0.75 + largest * 0.22)
		var fling := randf_range(3.5, 10.0) * power * heft
		var g := _take()
		g.shape = piece.shape
		g.mode = MODE_AIR
		g.x = x + off_x
		g.y = base + oy
		g.z = z + off_z
		g.vx = vx * INHERIT + push_x + dir_x * fling + SimMath.rand_signed(2.5)
		g.vz = vz * INHERIT + push_z + dir_z * fling + SimMath.rand_signed(2.5)
		g.vy = randf_range(7.0, 15.0) * sqrt(power) * heft + oy * 0.8
		g.yaw = heading
		g.pitch = 0.0
		g.roll = 0.0
		var spin := 15.0 * heft
		g.spin_yaw = SimMath.rand_signed(spin)
		g.spin_pitch = SimMath.rand_signed(spin)
		g.spin_roll = SimMath.rand_signed(spin)
		g.sx = piece.size.x
		g.sy = piece.size.y
		g.sz = piece.size.z
		var ch := randf_range(0.3, 0.7) if burning else randf_range(0.82, 1.0)
		g.color = Color(piece.color.r * ch, piece.color.g * ch, piece.color.b * ch, 1.0)
		g.rest_clearance = piece.size.x * 0.5 if piece.shape == "wheel" else piece.size.y * 0.5
		g.clearance = piece.size.y * 0.5 if piece.shape == "wheel" else maxf(g.rest_clearance, minf(largest * 0.35, 0.9))
		g.age = 0.0
		g.life = randf_range(4.5, 7.5)
		if randf() < trail_chance:
			g.trail = TRAIL_FIRE if (burning and randf() < 0.6) else TRAIL_SOOT
		else:
			g.trail = TRAIL_NONE
		g.trail_timer = randf() * TRAIL_INTERVAL


func throw_rider(x: float, z: float, heading: float, vx: float, vy: float, vz: float) -> void:
	var g := _take()
	g.shape = "rider"
	g.mode = MODE_AIR
	g.x = x
	g.y = DesertTerrain.ground_height(x, z) + RIDER_HEIGHT
	g.z = z
	g.vx = vx
	g.vy = vy
	g.vz = vz
	g.yaw = heading
	g.pitch = -HALF_TURN * 0.5
	g.roll = 0.0
	g.spin_yaw = SimMath.rand_signed(4.0)
	g.spin_pitch = randf_range(5.0, 9.0) * (-1.0 if randf() < 0.7 else 1.0)
	g.spin_roll = SimMath.rand_signed(5.0)
	g.sx = 1.0
	g.sy = 1.0
	g.sz = 1.0
	g.clearance = 0.45
	g.rest_clearance = RIDER_THICKNESS * 0.5
	g.age = 0.0
	g.life = randf_range(4.5, 6.5)
	g.trail = TRAIL_NONE


func sparks(x: float, y: float, z: float, count: int, spd: float, vx: float, vz: float) -> void:
	for _i in count:
		var angle := randf() * TAU
		var out := randf_range(0.3, 1.0) * spd
		var sz := randf_range(0.12, 0.26)
		var g := _take()
		g.shape = "spark"
		g.mode = MODE_AIR
		g.x = x
		g.y = y
		g.z = z
		g.vx = vx * INHERIT + sin(angle) * out
		g.vz = vz * INHERIT + cos(angle) * out
		g.vy = randf_range(0.3, 1.0) * spd
		g.yaw = angle
		g.pitch = 0.0
		g.roll = 0.0
		g.spin_yaw = SimMath.rand_signed(20.0)
		g.spin_pitch = SimMath.rand_signed(20.0)
		g.spin_roll = SimMath.rand_signed(20.0)
		g.sx = sz
		g.sy = sz
		g.sz = sz * randf_range(1.0, 2.5)
		g.clearance = sz * 0.5
		g.rest_clearance = sz * 0.5
		g.age = 0.0
		g.life = randf_range(0.35, 0.9)
		g.trail = TRAIL_NONE


func update_gibs(dt: float, smoke: SmokeSystem) -> void:
	for g in _pool:
		if not g.live:
			continue
		g.age += dt
		if g.age >= g.life:
			g.live = false
			continue
		if g.mode == MODE_AIR:
			_fly(g, dt, smoke)
		elif g.mode == MODE_GROUND:
			_settle(g, dt)
	_render()


func _take() -> Gib:
	var g := _pool[_cursor]
	_cursor = (_cursor + 1) % MAX_GIBS
	g.live = true
	return g


static func _nearest_half_turn(angle: float) -> float:
	return round(angle / HALF_TURN) * HALF_TURN


func _fly(g: Gib, dt: float, smoke: SmokeSystem) -> void:
	var drag := exp(-AIR_DRAG * dt)
	g.vy -= GRAVITY * dt
	g.vx *= drag
	g.vz *= drag
	g.x += g.vx * dt
	g.y += g.vy * dt
	g.z += g.vz * dt
	g.yaw += g.spin_yaw * dt
	g.pitch += g.spin_pitch * dt
	g.roll += g.spin_roll * dt

	if g.trail != TRAIL_NONE and g.age < TRAIL_SECONDS:
		g.trail_timer -= dt
		if g.trail_timer <= 0.0:
			g.trail_timer = TRAIL_INTERVAL
			var fire := g.trail == TRAIL_FIRE and g.age < TRAIL_SECONDS * 0.6
			smoke.emit(
				SmokeSystem.PUFF_FIRE if fire else SmokeSystem.PUFF_SOOT,
				g.x, g.y, g.z,
				g.vx * 0.15, 1.0, g.vz * 0.15,
				randf_range(0.3, 0.5), 1.1,
				randf_range(0.3, 0.5) if fire else randf_range(0.5, 0.9),
				0.7, 1.2 if fire else 0.5,
			)

	var fl := DesertTerrain.ground_height(g.x, g.z) + g.clearance
	if g.y > fl or g.vy > 0.0:
		return
	g.y = fl
	var impact := -g.vy
	var spd := sqrt(g.vx * g.vx + g.vz * g.vz)
	if g.shape == "spark":
		g.life = minf(g.life, g.age + 0.12)
	if impact > SETTLE_SPEED:
		g.vy = impact * (WHEEL_BOUNCE if g.shape == "wheel" else BOUNCE)
		g.vx *= BOUNCE_KEEP
		g.vz *= BOUNCE_KEEP
		var tumble := clampf(spd * 0.9 + impact * 0.5, 2.0, 14.0)
		g.spin_yaw = SimMath.rand_signed(tumble)
		g.spin_pitch = SimMath.rand_signed(tumble)
		g.spin_roll = SimMath.rand_signed(tumble)
		return
	g.vy = 0.0
	g.mode = MODE_GROUND


func _settle(g: Gib, dt: float) -> void:
	var spd := sqrt(g.vx * g.vx + g.vz * g.vz)
	var friction := SLIDE_FRICTION
	var done := spd < REST_SPEED
	if g.shape == "wheel":
		if spd > TOPPLE_SPEED:
			friction = ROLL_FRICTION
			g.yaw += SimMath.wrap_angle(atan2(g.vx, g.vz) - g.yaw) * minf(1.0, 12.0 * dt)
			g.pitch += (spd / maxf(0.05, g.clearance)) * dt
			g.roll = SimMath.damp(g.roll, _nearest_half_turn(g.roll), 12.0, dt)
			done = false
		else:
			friction = TOPPLE_FRICTION
			var lying := _nearest_half_turn(g.roll - HALF_TURN * 0.5) + HALF_TURN * 0.5
			g.roll = SimMath.damp(g.roll, lying, 8.0, dt)
			g.pitch = SimMath.damp(g.pitch, _nearest_half_turn(g.pitch), 8.0, dt)
			g.clearance = SimMath.damp(g.clearance, g.rest_clearance, 8.0, dt)
			done = done and absf(g.roll - lying) < 0.04
	else:
		var flat_p := _nearest_half_turn(g.pitch)
		var flat_r := _nearest_half_turn(g.roll)
		g.pitch = SimMath.damp(g.pitch, flat_p, 14.0, dt)
		g.roll = SimMath.damp(g.roll, flat_r, 14.0, dt)
		g.spin_yaw *= exp(-3.0 * dt)
		g.yaw += g.spin_yaw * dt
		g.clearance = SimMath.damp(g.clearance, g.rest_clearance, 14.0, dt)
		done = done and absf(g.pitch - flat_p) + absf(g.roll - flat_r) < 0.04

	var slow := exp(-friction * dt)
	g.vx *= slow
	g.vz *= slow
	g.x += g.vx * dt
	g.z += g.vz * dt
	g.y = DesertTerrain.ground_height(g.x, g.z) + g.clearance
	if not done:
		return
	g.mode = MODE_REST
	g.clearance = g.rest_clearance
	g.y = DesertTerrain.ground_height(g.x, g.z) + g.clearance


func _render() -> void:
	for shape: String in SHAPES:
		(_batches[shape] as SimMath.InstanceBatch).begin()
	for g in _pool:
		if not g.live:
			continue
		var batch: SimMath.InstanceBatch = _batches[g.shape]
		var fade := minf(1.0, (g.life - g.age) / FADE_SECONDS)
		var sink := 0.0 if g.mode == MODE_AIR else g.clearance * (1.0 - fade)
		batch.push(g.x, g.y - sink, g.z, g.yaw, g.pitch, g.roll, g.sx * fade, g.sy * fade, g.sz * fade)
		batch.tint(g.color)
	for shape: String in SHAPES:
		(_batches[shape] as SimMath.InstanceBatch).commit()

class_name Props
extends RefCounted

# Direct port of src/props.ts: all 16 procedural wasteland props,
# collider definitions, underground root meshes, loose physics specs, and tire stacks.

const HALF_PI := PI * 0.5
const BARREL_SCALE := 1.44224957 # cbrt(3)
const TIRE_DIAMETER := 1.1
const TIRE_HEIGHT := 0.36
const TIRE_TREAD_POINTS := 8
const TIRE_STACK_FOOTPRINT := 1.75

const TIRE_STACK := [
	{ "name": "tire", "x": 0.0, "y": 0.0, "z": 0.0 },
	{ "name": "tireDark", "x": 0.08, "y": TIRE_HEIGHT + 0.01, "z": 0.05 },
	{ "name": "tire", "x": -0.05, "y": TIRE_HEIGHT * 2.0 + 0.02, "z": -0.04 },
	{ "name": "tire", "x": 1.15, "y": 0.0, "z": 0.4 },
]


class LocalCollider:
	extends RefCounted
	var x: float
	var z: float
	var r: float

	func _init(px: float, pz: float, pr: float) -> void:
		x = px
		z = pz
		r = pr


class LooseSpec:
	extends RefCounted
	var mass: float
	var radius: float
	var centre: float
	var points: Array[Vector4] # (x, y, z, radius)

	func _init(p_mass: float, p_radius: float, p_centre: float, p_points: Array[Vector4]) -> void:
		mass = p_mass
		radius = p_radius
		centre = p_centre
		points = p_points


class RootSpec:
	extends RefCounted
	var hold: float
	var tear: float

	func _init(p_hold: float, p_tear: float) -> void:
		hold = p_hold
		tear = p_tear


class PropDef:
	extends RefCounted
	var name: String
	var mesh: ArrayMesh
	var colliders: Array[LocalCollider]
	var casts_shadow: bool
	var min_scale: float
	var max_scale: float
	var sink: float
	var loose: LooseSpec # nullable
	var roots: RootSpec # nullable

	func _init(
		p_name: String,
		p_mesh: ArrayMesh,
		p_colliders: Array[LocalCollider],
		p_min_scale: float,
		p_max_scale: float,
		p_casts_shadow: bool = true,
		p_sink: float = 0.1,
		p_loose: LooseSpec = null,
		p_roots: RootSpec = null,
	) -> void:
		name = p_name
		mesh = p_mesh
		colliders = p_colliders
		min_scale = p_min_scale
		max_scale = p_max_scale
		casts_shadow = p_casts_shadow
		sink = p_sink
		loose = p_loose
		roots = p_roots


static func _solid(r: float) -> Array[LocalCollider]:
	var arr: Array[LocalCollider] = [LocalCollider.new(0.0, 0.0, r)]
	return arr


static func _no_colliders() -> Array[LocalCollider]:
	var arr: Array[LocalCollider] = []
	return arr


static func _stalk(mass: float, height: float, radius: float, limbs: Array[Vector4] = []) -> LooseSpec:
	var pts: Array[Vector4] = []
	for i in 4:
		pts.append(Vector4(0.0, radius + ((height - radius * 2.0) * float(i)) / 3.0, 0.0, radius))
	for limb in limbs:
		pts.append(limb)
	return LooseSpec.new(mass, radius, height * 0.45, pts)


static func _tread(mass: float, diameter: float, height: float) -> LooseSpec:
	var half := height * 0.5
	var ring := diameter * 0.5 - half
	var pts: Array[Vector4] = []
	for i in TIRE_TREAD_POINTS:
		var angle := (float(i) / float(TIRE_TREAD_POINTS)) * TAU
		pts.append(Vector4(sin(angle) * ring, half, cos(angle) * ring, half))
	return LooseSpec.new(mass, diameter * 0.5, half, pts)


static func _tuft(mass: float, height: float, radius: float) -> LooseSpec:
	var pts: Array[Vector4] = [Vector4(0.0, height, 0.0, radius)]
	return LooseSpec.new(mass, radius, height, pts)


static func _sink_roots(kit: ModelKit, count: int, length_base: float, girth: float, splay: float, tap: float, clod: float, color: Color) -> ModelKit:
	for i in count:
		var yaw := ((float(i) + 0.5) / float(count)) * TAU
		var length := length_base * (0.85 + 0.3 * float((i * 7) % count) / float(count))
		# Simulate BabylonJS RotationYawPitchRoll(yaw, 0, splay) applied to Down(0, -1, 0):
		# Roll around Z turns (0, -1, 0) -> (sin(splay), -cos(splay), 0);
		# Yaw around Y turns (rx, ry, 0) -> (rx*cos(yaw), ry, -rx*sin(yaw)) in BabylonJS LH
		var rx0 := sin(splay)
		var ry0 := -cos(splay)
		var reach := Vector3(rx0 * cos(yaw), ry0, -rx0 * sin(yaw)) * (length * 0.5)
		kit.cylinder(girth, girth * 0.25, length, 5, Vector3(reach.x, reach.y + 0.05, reach.z), color, Vector3(0.0, yaw, splay))
	kit.cylinder(girth * 1.6, girth * 0.3, tap, 5, Vector3(0.0, -tap * 0.5, 0.0), color)
	kit.blob(clod, Vector3(0.0, -clod * 0.8, 0.0), Palette.SAND_SHADOW, Vector3(1.0, 0.6, 1.0), 0.3, 17)
	return kit


static func build_props() -> Dictionary:
	var kit := ModelKit.new()

	var rock_a := kit \
		.blob(1.0, Vector3(0.0, 0.35, 0.0), Palette.ROCK_MID, Vector3(1.25, 0.8, 1.0), 0.28, 3) \
		.build()

	var rock_b := kit \
		.blob(1.0, Vector3(-0.3, 0.4, 0.0), Palette.ROCK_LIGHT, Vector3(1.0, 0.9, 1.1), 0.3, 7) \
		.blob(0.7, Vector3(0.75, 0.2, 0.35), Palette.ROCK_MID, Vector3(1.0, 0.8, 1.0), 0.3, 11) \
		.blob(0.45, Vector3(0.2, 0.1, -0.95), Palette.ROCK_DARK, Vector3.ONE, 0.3, 13) \
		.build()

	var spire := kit \
		.cylinder(5.2, 6.6, 4.6, 7, Vector3(0.0, 2.1, 0.0), Palette.ROCK_DARK) \
		.cylinder(4.6, 5.0, 1.2, 7, Vector3(0.1, 5.0, 0.0), Palette.ROCK_PALE, Vector3(0.0, 0.4, 0.0)) \
		.cylinder(4.0, 4.7, 3.6, 7, Vector3(0.15, 7.4, 0.1), Palette.ROCK_MID, Vector3(0.0, 0.2, 0.0)) \
		.cylinder(3.6, 4.2, 0.9, 7, Vector3(0.2, 9.6, 0.1), Palette.ROCK_PALE, Vector3(0.0, 0.9, 0.0)) \
		.cylinder(2.4, 3.7, 2.4, 6, Vector3(0.3, 11.2, 0.2), Palette.ROCK_LIGHT, Vector3(0.0, 0.5, 0.0)) \
		.blob(1.6, Vector3(2.9, 0.4, 1.2), Palette.ROCK_MID, Vector3(1.2, 0.6, 1.0), 0.3, 5) \
		.blob(1.1, Vector3(-2.6, 0.3, -1.8), Palette.ROCK_DARK, Vector3(1.0, 0.7, 1.2), 0.3, 9) \
		.build()

	var wreck := kit \
		.box(Vector3(1.8, 0.6, 4.0), Vector3(0.0, 0.55, 0.0), Palette.RUST, Vector3(0.03, 0.0, 0.1)) \
		.box(Vector3(1.5, 0.5, 1.7), Vector3(0.05, 1.05, -0.3), Palette.RUST_DARK, Vector3(0.03, 0.0, 0.1)) \
		.box(Vector3(1.7, 0.12, 1.2), Vector3(0.0, 0.92, 1.3), Palette.RUST_LIGHT, Vector3(-0.25, 0.0, 0.1)) \
		.cylinder(0.72, 0.72, 0.3, 8, Vector3(1.3, 0.16, 1.5), Palette.RUBBER, Vector3(0.1, 0.0, 0.0)) \
		.box(Vector3(0.3, 0.3, 0.3), Vector3(-0.8, 0.2, -1.5), Palette.METAL_DARK) \
		.build()

	var tire := kit.cylinder(TIRE_DIAMETER, TIRE_DIAMETER, TIRE_HEIGHT, 9, Vector3(0.0, TIRE_HEIGHT * 0.5, 0.0), Palette.RUBBER).build()
	var tire_dark := kit.cylinder(TIRE_DIAMETER, TIRE_DIAMETER, TIRE_HEIGHT, 9, Vector3(0.0, TIRE_HEIGHT * 0.5, 0.0), Palette.METAL_DARK).build()

	var shack := kit \
		.box(Vector3(5.0, 2.6, 4.0), Vector3(0.0, 1.3, 0.0), Palette.TEAL) \
		.box(Vector3(5.8, 0.16, 4.9), Vector3(0.0, 2.85, 0.0), Palette.RUST, Vector3(0.0, 0.0, 0.09)) \
		.box(Vector3(1.0, 1.9, 0.12), Vector3(-1.1, 0.95, 2.02), Palette.RUST_DARK) \
		.box(Vector3(1.3, 0.8, 0.12), Vector3(1.2, 1.6, 2.02), Palette.GLASS) \
		.box(Vector3(5.1, 0.5, 4.1), Vector3(0.0, 0.25, 0.0), Palette.TEAL_DARK) \
		.cylinder(0.3, 0.3, 1.6, 6, Vector3(1.6, 3.6, -1.1), Palette.METAL_DARK) \
		.box(Vector3(1.6, 1.0, 0.9), Vector3(3.3, 0.5, -0.8), Palette.RUST_LIGHT, Vector3(0.0, 0.3, 0.0)) \
		.build()

	var tower := kit \
		.box(Vector3(0.26, 6.2, 0.26), Vector3(1.3, 3.1, 1.3), Palette.METAL_DARK, Vector3(0.06, 0.0, -0.06)) \
		.box(Vector3(0.26, 6.2, 0.26), Vector3(-1.3, 3.1, 1.3), Palette.METAL_DARK, Vector3(0.06, 0.0, 0.06)) \
		.box(Vector3(0.26, 6.2, 0.26), Vector3(1.3, 3.1, -1.3), Palette.METAL_DARK, Vector3(-0.06, 0.0, -0.06)) \
		.box(Vector3(0.26, 6.2, 0.26), Vector3(-1.3, 3.1, -1.3), Palette.METAL_DARK, Vector3(-0.06, 0.0, 0.06)) \
		.box(Vector3(3.0, 0.14, 0.14), Vector3(0.0, 2.4, 1.38), Palette.METAL, Vector3(0.0, 0.0, 0.5)) \
		.box(Vector3(3.0, 0.14, 0.14), Vector3(0.0, 2.4, -1.38), Palette.METAL, Vector3(0.0, 0.0, -0.5)) \
		.box(Vector3(0.14, 0.14, 3.0), Vector3(1.38, 3.8, 0.0), Palette.METAL, Vector3(0.5, 0.0, 0.0)) \
		.box(Vector3(0.14, 0.14, 3.0), Vector3(-1.38, 3.8, 0.0), Palette.METAL, Vector3(-0.5, 0.0, 0.0)) \
		.cylinder(3.5, 3.5, 2.6, 9, Vector3(0.0, 7.4, 0.0), Palette.RUST_LIGHT) \
		.cylinder(3.6, 3.6, 0.3, 9, Vector3(0.0, 7.0, 0.0), Palette.RUST_DARK) \
		.cylinder(0.2, 3.8, 1.1, 9, Vector3(0.0, 9.2, 0.0), Palette.RUST) \
		.build()

	var wall := kit \
		.box(Vector3(3.0, 2.6, 0.55), Vector3(-3.1, 1.3, 0.1), Palette.CONCRETE, Vector3(0.0, 0.06, 0.02)) \
		.box(Vector3(3.1, 2.1, 0.55), Vector3(0.0, 1.05, -0.1), Palette.CONCRETE_DARK, Vector3(0.04, -0.05, 0.0)) \
		.box(Vector3(2.9, 1.3, 0.55), Vector3(3.1, 0.65, 0.05), Palette.CONCRETE, Vector3(0.0, 0.04, -0.05)) \
		.box(Vector3(0.12, 1.5, 0.12), Vector3(3.6, 1.9, 0.05), Palette.RUST_DARK, Vector3(0.0, 0.0, 0.2)) \
		.box(Vector3(0.12, 1.2, 0.12), Vector3(2.7, 1.8, 0.05), Palette.RUST_DARK, Vector3(0.0, 0.0, -0.15)) \
		.box(Vector3(1.2, 0.5, 0.9), Vector3(1.4, 0.25, 0.9), Palette.CONCRETE_DARK, Vector3(0.0, 0.5, 0.0)) \
		.build()

	var cactus := _sink_roots(kit, 5, 1.0, 0.2, 1.0, 0.7, 0.45, Palette.ROOT) \
		.cylinder(0.42, 0.5, 3.2, 6, Vector3(0.0, 1.6, 0.0), Palette.CACTUS) \
		.cylinder(0.3, 0.3, 0.9, 6, Vector3(0.55, 1.5, 0.0), Palette.CACTUS_DARK, Vector3(0.0, 0.0, HALF_PI)) \
		.cylinder(0.26, 0.3, 1.2, 6, Vector3(0.95, 2.0, 0.0), Palette.CACTUS) \
		.cylinder(0.28, 0.28, 0.7, 6, Vector3(-0.45, 2.0, 0.0), Palette.CACTUS_DARK, Vector3(0.0, 0.0, HALF_PI)) \
		.cylinder(0.24, 0.28, 0.9, 6, Vector3(-0.75, 2.4, 0.0), Palette.CACTUS) \
		.build()

	var dead_tree := _sink_roots(kit, 4, 1.1, 0.26, 0.8, 0.9, 0.42, Palette.DEAD_WOOD) \
		.cylinder(0.2, 0.42, 3.4, 5, Vector3(0.0, 1.7, 0.0), Palette.DEAD_WOOD, Vector3(0.0, 0.0, 0.08)) \
		.cylinder(0.08, 0.18, 1.8, 5, Vector3(0.55, 3.0, 0.0), Palette.DEAD_WOOD, Vector3(0.0, 0.0, -0.8)) \
		.cylinder(0.07, 0.16, 1.5, 5, Vector3(-0.55, 3.4, 0.2), Palette.DEAD_WOOD, Vector3(0.3, 0.0, 0.9)) \
		.cylinder(0.06, 0.14, 1.3, 5, Vector3(0.0, 3.8, -0.4), Palette.DEAD_WOOD, Vector3(-0.7, 0.0, 0.0)) \
		.build()

	var barrel := kit \
		.cylinder(0.7, 0.7, 1.0, 8, Vector3(0.0, 0.5, 0.0), Palette.RAIDER_RED) \
		.cylinder(0.74, 0.74, 0.1, 8, Vector3(0.0, 0.72, 0.0), Palette.RUST_DARK) \
		.cylinder(0.74, 0.74, 0.1, 8, Vector3(0.0, 0.28, 0.0), Palette.RUST_DARK) \
		.build()

	var rib_spacing := 1.7
	for i in 5:
		var z := float(i - 2) * rib_spacing
		var sz := 1.0 - absf(float(i - 2)) * 0.12
		kit \
			.box(Vector3(0.28, 3.2 * sz, 0.28), Vector3(-1.5 * sz, 1.5 * sz, z), Palette.BONE, Vector3(0.0, 0.0, -0.32)) \
			.box(Vector3(0.24, 1.7 * sz, 0.24), Vector3(-0.62 * sz, 3.25 * sz, z), Palette.BONE, Vector3(0.0, 0.0, -1.05)) \
			.box(Vector3(0.28, 3.2 * sz, 0.28), Vector3(1.5 * sz, 1.5 * sz, z), Palette.BONE, Vector3(0.0, 0.0, 0.32)) \
			.box(Vector3(0.24, 1.7 * sz, 0.24), Vector3(0.62 * sz, 3.25 * sz, z), Palette.BONE, Vector3(0.0, 0.0, 1.05))
	var ribs := kit.box(Vector3(0.4, 0.4, 9.4), Vector3(0.0, 3.55, 0.0), Palette.BONE).build()

	var pylon := kit \
		.cylinder(0.18, 0.3, 7.5, 5, Vector3(0.0, 3.75, 0.0), Palette.DEAD_WOOD, Vector3(0.0, 0.0, 0.05)) \
		.box(Vector3(2.6, 0.16, 0.16), Vector3(0.15, 6.6, 0.0), Palette.DEAD_WOOD) \
		.box(Vector3(1.6, 0.14, 0.14), Vector3(0.12, 5.8, 0.0), Palette.DEAD_WOOD) \
		.box(Vector3(0.1, 0.3, 0.1), Vector3(1.2, 6.8, 0.0), Palette.TEAL) \
		.box(Vector3(0.1, 0.3, 0.1), Vector3(-0.9, 6.8, 0.0), Palette.TEAL) \
		.build()

	var pebble := kit.blob(0.3, Vector3(0.0, 0.05, 0.0), Palette.ROCK_LIGHT, Vector3(1.2, 0.6, 1.0), 0.3, 21).build()

	var shrub := kit \
		.box(Vector3(0.08, 0.9, 0.08), Vector3(0.0, 0.4, 0.0), Palette.SHRUB, Vector3(0.5, 0.0, 0.3)) \
		.box(Vector3(0.08, 0.8, 0.08), Vector3(0.1, 0.35, 0.0), Palette.SHRUB, Vector3(-0.4, 0.0, -0.5)) \
		.box(Vector3(0.08, 0.7, 0.08), Vector3(-0.1, 0.3, 0.1), Palette.SHRUB, Vector3(0.2, 0.0, 0.7)) \
		.box(Vector3(0.08, 0.75, 0.08), Vector3(0.0, 0.3, -0.1), Palette.SHRUB, Vector3(-0.6, 0.0, 0.1)) \
		.blob(0.3, Vector3(0.0, 0.12, 0.0), Palette.CACTUS_DARK, Vector3(1.3, 0.5, 1.3), 0.4, 4) \
		.build()

	var wall_cols: Array[LocalCollider] = [
		LocalCollider.new(-3.1, 0.0, 1.5),
		LocalCollider.new(0.0, 0.0, 1.5),
		LocalCollider.new(3.1, 0.0, 1.5),
	]
	var cactus_limbs: Array[Vector4] = [
		Vector4(0.0, -0.3, 0.0, 0.4),
		Vector4(0.95, 2.4, 0.0, 0.3),
		Vector4(-0.75, 2.65, 0.0, 0.28),
	]
	var tree_limbs: Array[Vector4] = [
		Vector4(0.0, -0.3, 0.0, 0.38),
		Vector4(1.15, 3.55, 0.0, 0.14),
		Vector4(-1.1, 3.85, 0.3, 0.14),
		Vector4(0.0, 4.2, -0.8, 0.14),
	]

	return {
		"rockA": PropDef.new("rockA", rock_a, _solid(0.95), 1.2, 3.6, true, 0.25),
		"rockB": PropDef.new("rockB", rock_b, _solid(1.15), 1.2, 3.2, true, 0.25),
		"spire": PropDef.new("spire", spire, _solid(3.3), 0.8, 1.5, true, 0.6),
		"wreck": PropDef.new("wreck", wreck, _solid(1.9), 1.0, 1.15),
		"tire": PropDef.new("tire", tire, _solid(TIRE_DIAMETER * 0.5), 1.0, 1.2, true, 0.02, _tread(0.07, TIRE_DIAMETER, TIRE_HEIGHT)),
		"tireDark": PropDef.new("tireDark", tire_dark, _solid(TIRE_DIAMETER * 0.5), 1.0, 1.2, true, 0.02, _tread(0.07, TIRE_DIAMETER, TIRE_HEIGHT)),
		"shack": PropDef.new("shack", shack, _solid(3.0), 1.0, 1.2),
		"tower": PropDef.new("tower", tower, _solid(2.0), 1.0, 1.25),
		"wall": PropDef.new("wall", wall, wall_cols, 1.0, 1.3),
		"cactus": PropDef.new("cactus", cactus, _solid(0.45), 0.8, 1.5, true, 0.1, _stalk(0.2, 3.2, 0.45, cactus_limbs), RootSpec.new(9.0, 4.5)),
		"deadTree": PropDef.new("deadTree", dead_tree, _solid(0.4), 0.9, 1.6, true, 0.1, _stalk(0.15, 3.4, 0.32, tree_limbs), RootSpec.new(10.0, 5.0)),
		"barrel": PropDef.new("barrel", barrel, _solid(0.45), BARREL_SCALE, 1.1 * BARREL_SCALE),
		"ribs": PropDef.new("ribs", ribs, _no_colliders(), 0.9, 1.6, true, 0.3),
		"pylon": PropDef.new("pylon", pylon, _solid(0.35), 1.0, 1.2),
		"pebble": PropDef.new("pebble", pebble, _no_colliders(), 0.5, 1.6, false, 0.0),
		"shrub": PropDef.new("shrub", shrub, _no_colliders(), 0.8, 1.8, false, 0.0, _tuft(0.012, 0.32, 0.36)),
	}

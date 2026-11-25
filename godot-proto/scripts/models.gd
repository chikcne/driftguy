class_name Models
extends RefCounted

# Procedural models for enemies, bike riders, pickups, bullets, and gibs
# matching src/models.ts.

const HALF_PI := PI * 0.5
const WHEEL_AXIS := Vector3(0.0, 0.0, HALF_PI)
const RIDER_SEAT := Vector3(0.0, 0.9, -0.27)
const RIDER_SHOULDER := Vector3(0.29, 0.5, 0.17)


static func _wheel_pair(kit: ModelKit, x: float, z: float, diameter: float, width: float) -> void:
	kit.cylinder(diameter, diameter, width, 8, Vector3(x, diameter * 0.5, z), Palette.RUBBER, WHEEL_AXIS)
	kit.cylinder(diameter, diameter, width, 8, Vector3(-x, diameter * 0.5, z), Palette.RUBBER, WHEEL_AXIS)


static func _spike(kit: ModelKit, pos: Vector3, length: float) -> void:
	kit.cylinder(0.0, 0.16, length, 5, pos, Palette.RAIDER_BONE, Vector3(HALF_PI, 0.0, 0.0))


static func build_rider_models() -> Dictionary:
	var kit := ModelKit.new()
	var body := kit \
		.box(Vector3(0.46, 0.62, 0.32), Vector3(0.0, 0.3, 0.07), Palette.RAIDER_BLACK, Vector3(0.3, 0.0, 0.0)) \
		.blob(0.2, Vector3(0.0, 0.72, 0.25), Palette.RAIDER_BONE, Vector3.ONE, 0.05) \
		.box(Vector3(0.15, 0.2, 0.5), Vector3(0.25, -0.04, 0.2), Palette.RUST_DARK) \
		.box(Vector3(0.15, 0.2, 0.5), Vector3(-0.25, -0.04, 0.2), Palette.RUST_DARK) \
		.box(Vector3(0.13, 0.42, 0.14), Vector3(0.25, -0.3, 0.38), Palette.RUST_DARK) \
		.box(Vector3(0.13, 0.42, 0.14), Vector3(-0.25, -0.3, 0.38), Palette.RUST_DARK) \
		.build()

	var arm := kit \
		.box(Vector3(0.12, 0.12, 0.66), Vector3(0.0, 0.0, 0.33), Palette.RAIDER_BLACK) \
		.box(Vector3(0.16, 0.16, 0.16), Vector3(0.0, 0.0, 0.72), Palette.RAIDER_BONE) \
		.build()

	# Weathered metal pipe held by biker before throwing (origin at grip, extends along +Z)
	kit \
		.cylinder(0.14, 0.14, 1.05, 7, Vector3(0.0, 0.0, 0.42), Palette.METAL, Vector3(HALF_PI, 0.0, 0.0)) \
		.cylinder(0.18, 0.18, 0.12, 7, Vector3(0.0, 0.0, 0.92), Palette.RUST_DARK, Vector3(HALF_PI, 0.0, 0.0)) \
		.cylinder(0.17, 0.17, 0.10, 7, Vector3(0.0, 0.0, -0.06), Palette.METAL_DARK, Vector3(HALF_PI, 0.0, 0.0))
	var pipe := kit.build()

	return { "body": body, "arm": arm, "pipe": pipe }


static func build_enemy_models() -> Dictionary:
	var kit := ModelKit.new()

	# Bike
	kit \
		.cylinder(0.72, 0.72, 0.2, 8, Vector3(0.0, 0.36, 0.85), Palette.RUBBER, WHEEL_AXIS) \
		.cylinder(0.72, 0.72, 0.24, 8, Vector3(0.0, 0.36, -0.8), Palette.RUBBER, WHEEL_AXIS) \
		.box(Vector3(0.26, 0.34, 1.5), Vector3(0.0, 0.62, 0.0), Palette.RAIDER_RED) \
		.box(Vector3(0.34, 0.24, 0.5), Vector3(0.0, 0.82, 0.2), Palette.RAIDER_BLACK) \
		.box(Vector3(0.8, 0.07, 0.07), Vector3(0.0, 1.02, 0.62), Palette.METAL_DARK) \
		.box(Vector3(0.1, 0.5, 0.1), Vector3(0.0, 0.78, 0.74), Palette.METAL_DARK, Vector3(0.4, 0.0, 0.0)) \
		.box(Vector3(0.06, 1.5, 0.06), Vector3(0.0, 1.5, -0.85), Palette.METAL_DARK) \
		.box(Vector3(0.04, 0.34, 0.6), Vector3(0.0, 2.05, -1.15), Palette.RAIDER_RED)
	var bike := kit.build()

	# Buggy
	_wheel_pair(kit, 0.95, 1.05, 0.9, 0.36)
	_wheel_pair(kit, 1.0, -1.05, 1.0, 0.44)
	kit \
		.box(Vector3(1.5, 0.3, 3.0), Vector3(0.0, 0.6, 0.0), Palette.RUST) \
		.box(Vector3(1.2, 0.34, 1.0), Vector3(0.0, 0.86, 1.0), Palette.RAIDER_RED, Vector3(0.12, 0.0, 0.0)) \
		.box(Vector3(1.0, 0.5, 0.8), Vector3(0.0, 0.98, -1.05), Palette.METAL_DARK) \
		.cylinder(0.14, 0.14, 0.9, 5, Vector3(0.3, 1.5, -1.2), Palette.METAL) \
		.cylinder(0.14, 0.14, 0.9, 5, Vector3(-0.3, 1.5, -1.2), Palette.METAL) \
		.box(Vector3(0.08, 1.0, 0.08), Vector3(0.66, 1.25, 0.45), Palette.RAIDER_BLACK, Vector3(0.25, 0.0, 0.0)) \
		.box(Vector3(0.08, 1.0, 0.08), Vector3(-0.66, 1.25, 0.45), Palette.RAIDER_BLACK, Vector3(0.25, 0.0, 0.0)) \
		.box(Vector3(0.08, 1.0, 0.08), Vector3(0.66, 1.25, -0.5), Palette.RAIDER_BLACK, Vector3(-0.25, 0.0, 0.0)) \
		.box(Vector3(0.08, 1.0, 0.08), Vector3(-0.66, 1.25, -0.5), Palette.RAIDER_BLACK, Vector3(-0.25, 0.0, 0.0)) \
		.box(Vector3(1.4, 0.08, 1.0), Vector3(0.0, 1.72, -0.02), Palette.RAIDER_BLACK) \
		.blob(0.22, Vector3(0.0, 1.3, -0.05), Palette.RAIDER_BONE, Vector3.ONE, 0.05) \
		.box(Vector3(1.7, 0.16, 0.16), Vector3(0.0, 0.6, 1.58), Palette.METAL_DARK)
	_spike(kit, Vector3(0.6, 0.62, 1.86), 0.6)
	_spike(kit, Vector3(0.0, 0.62, 1.9), 0.7)
	_spike(kit, Vector3(-0.6, 0.62, 1.86), 0.6)
	var buggy := kit.build()

	# Truck
	_wheel_pair(kit, 1.2, 1.8, 1.2, 0.5)
	_wheel_pair(kit, 1.2, -0.9, 1.2, 0.5)
	_wheel_pair(kit, 1.2, -2.2, 1.2, 0.5)
	kit \
		.box(Vector3(2.2, 0.5, 5.6), Vector3(0.0, 0.95, -0.2), Palette.RAIDER_BLACK) \
		.box(Vector3(2.2, 1.3, 1.7), Vector3(0.0, 1.85, 1.5), Palette.RUST_DARK) \
		.box(Vector3(1.9, 0.5, 0.1), Vector3(0.0, 2.0, 2.37), Palette.GLASS) \
		.box(Vector3(2.3, 1.0, 3.3), Vector3(0.0, 1.7, -1.3), Palette.RUST) \
		.box(Vector3(2.36, 0.14, 3.36), Vector3(0.0, 2.26, -1.3), Palette.RUST_LIGHT) \
		.box(Vector3(1.5, 1.1, 0.14), Vector3(0.7, 0.85, 2.85), Palette.METAL, Vector3(0.2, 0.5, 0.0)) \
		.box(Vector3(1.5, 1.1, 0.14), Vector3(-0.7, 0.85, 2.85), Palette.METAL, Vector3(0.2, -0.5, 0.0)) \
		.cylinder(0.2, 0.2, 1.6, 6, Vector3(1.0, 3.0, 0.55), Palette.METAL) \
		.cylinder(0.2, 0.2, 1.6, 6, Vector3(-1.0, 3.0, 0.55), Palette.METAL) \
		.blob(0.34, Vector3(0.0, 1.5, 2.42), Palette.RAIDER_BONE, Vector3.ONE, 0.08) \
		.box(Vector3(0.08, 1.7, 0.08), Vector3(0.9, 3.1, -2.6), Palette.METAL_DARK) \
		.box(Vector3(0.05, 0.5, 0.8), Vector3(0.9, 3.7, -3.0), Palette.RAIDER_RED)
	var truck := kit.build()

	# Interceptor
	_wheel_pair(kit, 0.95, 1.3, 0.76, 0.34)
	_wheel_pair(kit, 1.0, -1.3, 0.86, 0.44)
	kit \
		.box(Vector3(1.86, 0.46, 4.4), Vector3(0.0, 0.6, 0.0), Palette.RAIDER_PURPLE) \
		.box(Vector3(1.5, 0.4, 1.7), Vector3(0.0, 1.0, -0.5), Palette.RAIDER_BLACK) \
		.box(Vector3(1.56, 0.08, 1.4), Vector3(0.0, 1.24, -0.55), Palette.RAIDER_PURPLE) \
		.box(Vector3(0.6, 0.42, 0.7), Vector3(0.0, 1.0, 1.15), Palette.METAL) \
		.box(Vector3(0.7, 0.16, 0.5), Vector3(0.0, 1.28, 1.2), Palette.RAIDER_YELLOW) \
		.box(Vector3(1.9, 0.08, 0.5), Vector3(0.0, 1.1, -2.1), Palette.RAIDER_BLACK, Vector3(-0.2, 0.0, 0.0)) \
		.box(Vector3(1.96, 0.2, 0.2), Vector3(0.0, 0.46, 2.26), Palette.METAL_DARK) \
		.cylinder(0.18, 0.18, 1.6, 6, Vector3(1.02, 0.5, -1.2), Palette.METAL, Vector3(HALF_PI, 0.0, 0.0)) \
		.cylinder(0.18, 0.18, 1.6, 6, Vector3(-1.02, 0.5, -1.2), Palette.METAL, Vector3(HALF_PI, 0.0, 0.0))
	_spike(kit, Vector3(0.7, 0.5, 2.6), 0.7)
	_spike(kit, Vector3(-0.7, 0.5, 2.6), 0.7)
	var interceptor := kit.build()

	# War Rig (Boss)
	for z_off in [3.6, 1.0, -0.3, -3.0, -4.3]:
		_wheel_pair(kit, 1.45, z_off, 1.4, 0.6)
	kit \
		.box(Vector3(2.7, 0.6, 10.6), Vector3(0.0, 1.15, -0.4), Palette.RAIDER_BLACK) \
		.box(Vector3(2.7, 1.7, 2.2), Vector3(0.0, 2.3, 3.4), Palette.RAIDER_RED) \
		.box(Vector3(2.3, 0.6, 0.1), Vector3(0.0, 2.6, 4.52), Palette.GLASS) \
		.box(Vector3(2.4, 1.0, 1.4), Vector3(0.0, 1.9, 5.0), Palette.RUST_DARK) \
		.cylinder(2.6, 2.6, 6.6, 10, Vector3(0.0, 2.75, -1.9), Palette.RUST, Vector3(HALF_PI, 0.0, 0.0)) \
		.cylinder(2.7, 2.7, 0.3, 10, Vector3(0.0, 2.75, 0.2), Palette.RUST_DARK, Vector3(HALF_PI, 0.0, 0.0)) \
		.cylinder(2.7, 2.7, 0.3, 10, Vector3(0.0, 2.75, -4.0), Palette.RUST_DARK, Vector3(HALF_PI, 0.0, 0.0)) \
		.box(Vector3(2.2, 1.5, 0.18), Vector3(0.95, 1.1, 5.95), Palette.METAL, Vector3(0.25, 0.55, 0.0)) \
		.box(Vector3(2.2, 1.5, 0.18), Vector3(-0.95, 1.1, 5.95), Palette.METAL, Vector3(0.25, -0.55, 0.0)) \
		.cylinder(0.26, 0.26, 2.4, 6, Vector3(1.2, 4.0, 2.5), Palette.METAL) \
		.cylinder(0.26, 0.26, 2.4, 6, Vector3(-1.2, 4.0, 2.5), Palette.METAL) \
		.blob(0.5, Vector3(0.0, 2.2, 5.75), Palette.RAIDER_BONE, Vector3.ONE, 0.08) \
		.box(Vector3(0.1, 2.4, 0.1), Vector3(1.2, 5.0, -4.6), Palette.METAL_DARK) \
		.box(Vector3(0.06, 0.8, 1.3), Vector3(1.2, 5.8, -5.3), Palette.RAIDER_YELLOW)
	for z_off in [-3.4, -2.0, -0.6]:
		kit.cylinder(0.0, 0.3, 0.9, 5, Vector3(0.0, 4.4, z_off), Palette.RAIDER_BONE)
	var rig := kit.build()

	return {
		"bike": bike,
		"buggy": buggy,
		"truck": truck,
		"interceptor": interceptor,
		"rig": rig,
	}


static func build_scrap_model() -> ArrayMesh:
	return ModelKit.new() \
		.cylinder(0.7, 0.7, 0.2, 6, Vector3.ZERO, Palette.SCRAP, Vector3(HALF_PI, 0.0, 0.0)) \
		.box(Vector3(0.26, 0.26, 0.26), Vector3.ZERO, Palette.METAL_DARK) \
		.build()


static func build_repair_model() -> ArrayMesh:
	return ModelKit.new() \
		.box(Vector3(0.9, 0.9, 0.5), Vector3.ZERO, Palette.CAR_BODY) \
		.box(Vector3(0.7, 0.22, 0.54), Vector3.ZERO, Palette.REPAIR) \
		.box(Vector3(0.22, 0.7, 0.54), Vector3.ZERO, Palette.REPAIR) \
		.build()


static func build_bullet_model() -> ArrayMesh:
	return ModelKit.new() \
		.box(Vector3(0.14, 0.14, 1.4), Vector3.ZERO, Palette.HEADLIGHT) \
		.build()


static func build_gib_models() -> Dictionary:
	var kit := ModelKit.new()
	var white := Color.WHITE
	var lengthwise := Vector3(HALF_PI, 0.0, 0.0)
	return {
		"box": kit.box(Vector3.ONE, Vector3.ZERO, white).build(),
		"wheel": kit \
			.cylinder(1.0, 1.0, 1.0, 8, Vector3.ZERO, Palette.RUBBER, WHEEL_AXIS) \
			.cylinder(0.5, 0.5, 1.06, 6, Vector3.ZERO, Palette.METAL, WHEEL_AXIS) \
			.build(),
		"pipe": kit.cylinder(1.0, 1.0, 1.0, 8, Vector3.ZERO, white, lengthwise).build(),
		"spike": kit.cylinder(0.0, 1.0, 1.0, 5, Vector3.ZERO, white, lengthwise).build(),
		"skull": kit.blob(0.5, Vector3.ZERO, white, Vector3.ONE, 0.05).build(),
		"spark": kit.box(Vector3.ONE, Vector3.ZERO, white).build(),
		"rider": kit \
			.box(Vector3(0.46, 0.3, 0.62), Vector3(0.0, 0.0, 0.1), Palette.RAIDER_BLACK) \
			.blob(0.2, Vector3(0.0, 0.02, 0.6), Palette.RAIDER_BONE, Vector3.ONE, 0.05) \
			.box(Vector3(0.12, 0.12, 0.7), Vector3(0.42, -0.04, 0.42), Palette.RAIDER_BLACK, Vector3(0.0, 0.5, 0.0)) \
			.box(Vector3(0.12, 0.12, 0.7), Vector3(-0.4, -0.04, 0.1), Palette.RAIDER_BLACK, Vector3(0.0, 1.2, 0.0)) \
			.box(Vector3(0.15, 0.16, 0.8), Vector3(0.2, -0.04, -0.6), Palette.RUST_DARK, Vector3(0.0, 0.22, 0.0)) \
			.box(Vector3(0.15, 0.16, 0.8), Vector3(-0.2, -0.04, -0.6), Palette.RUST_DARK, Vector3(0.0, -0.3, 0.0)) \
			.build(),
	}

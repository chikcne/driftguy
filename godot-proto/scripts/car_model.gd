class_name CarModel
extends Node3D

# Procedural player car matching src/models.ts, including roof spiral gun,
# rear turbine fan, front ram plow, turning/rolling wheels, body lean, and nitrous flames.

const WHEEL_RADIUS := 0.37
const WHEEL_X := CarBody.HALF_TRACK + 0.08
const HALF_PI := PI * 0.5
const EXHAUST_HALF_SPAN := 0.98
const EXHAUST_HEIGHT := 0.5
const EXHAUST_REAR := 2.3

var lean: Node3D
var gun: MeshInstance3D
var fan: MeshInstance3D
var plow: MeshInstance3D
var steer_pivots: Array[Node3D] = []
var wheels: Array[MeshInstance3D] = []
var _flames: Array[Node3D] = []
var _material: StandardMaterial3D


func build(shared_material: StandardMaterial3D) -> void:
	# Write stencil=1 on the player car so occluded enemy silhouettes do not bleed through it
	_material = shared_material.duplicate()
	_material.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	_material.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
	_material.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
	_material.stencil_reference = 1

	lean = Node3D.new()
	lean.name = "CarLean"
	add_child(lean)

	var body_instance := MeshInstance3D.new()
	body_instance.name = "CarBody"
	body_instance.mesh = _build_body_mesh()
	body_instance.material_override = _material
	lean.add_child(body_instance)

	var wheel_mesh := _build_wheel_mesh()
	var wheel_spots := [
		Vector2(-WHEEL_X, CarBody.AXLE_FRONT),
		Vector2(WHEEL_X, CarBody.AXLE_FRONT),
		Vector2(-WHEEL_X, -CarBody.AXLE_REAR),
		Vector2(WHEEL_X, -CarBody.AXLE_REAR),
	]
	for i in wheel_spots.size():
		var spot: Vector2 = wheel_spots[i]
		var pivot := Node3D.new()
		pivot.name = "WheelPivot_%d" % i
		pivot.position = Vector3(spot.x, WHEEL_RADIUS, -spot.y)
		add_child(pivot)

		var wheel := MeshInstance3D.new()
		wheel.name = "Wheel_%d" % i
		wheel.mesh = wheel_mesh
		wheel.material_override = _material
		pivot.add_child(wheel)

		steer_pivots.append(pivot)
		wheels.append(wheel)

	# Upgrade attachments: Spiral Gun, Turbine Fan, Ram Plow
	gun = MeshInstance3D.new()
	gun.name = "SpiralGun"
	gun.mesh = _build_gun_mesh()
	gun.material_override = _material
	gun.position = Vector3(0.0, 1.42, 0.4) # sim z = -0.4 -> godot z = +0.4
	gun.visible = false
	lean.add_child(gun)

	fan = MeshInstance3D.new()
	fan.name = "TurbineFan"
	fan.mesh = _build_fan_mesh()
	fan.material_override = _material
	fan.position = Vector3(0.0, 1.25, 2.42) # sim z = -2.42 -> godot z = +2.42
	fan.visible = false
	lean.add_child(fan)

	plow = MeshInstance3D.new()
	plow.name = "RamPlow"
	plow.mesh = _build_plow_mesh()
	plow.material_override = _material
	plow.position = Vector3(0.0, 0.55, -2.28) # sim z = +2.28 -> godot z = -2.28
	plow.visible = false
	lean.add_child(plow)

	_build_exhaust_flames()


func sync_attachments(has_gun: bool, has_fan: bool, has_plow: bool) -> void:
	gun.visible = has_gun
	fan.visible = has_fan
	plow.visible = has_plow


func update_visuals(
	car: CarBody,
	slope_height: float,
	slope_pitch: float,
	slope_roll: float,
	handbrake: bool,
	nitro_level: float,
	turret_angle: float,
	clock: float,
	dt: float,
) -> void:
	position = Vector3(car.x, slope_height, -car.z)
	rotation_order = EULER_ORDER_YXZ
	rotation = Vector3(-slope_pitch, -car.heading, slope_roll)

	var blend := 1.0 - exp(-10.0 * dt)
	lean.rotation.z = lerpf(lean.rotation.z, clampf(car.lat_accel * 0.011, -0.16, 0.16), blend)
	lean.rotation.x = lerpf(lean.rotation.x, clampf(car.long_accel * 0.006, -0.08, 0.08), blend)

	var steer := clampf(car.steer_angle, -0.62, 0.62)
	steer_pivots[0].rotation.y = -steer
	steer_pivots[1].rotation.y = -steer

	var rolling := (car.forward_speed / WHEEL_RADIUS) * dt
	var rear_spin := 0.0 if handbrake else rolling * (1.0 + car.burnout * 3.0)
	wheels[0].rotation.x -= rolling
	wheels[1].rotation.x -= rolling
	wheels[2].rotation.x -= rear_spin
	wheels[3].rotation.x -= rear_spin

	if gun.visible:
		gun.rotation.y = -(turret_angle - car.heading)
	if fan.visible:
		fan.rotation.z += 26.0 * dt

	var lit := nitro_level > 0.02
	for i in _flames.size():
		var flame := _flames[i]
		flame.visible = lit
		if lit:
			var phase := -1.7 if i == 0 else 1.7
			var flicker := 0.82 + 0.18 * sin(clock * 71.0 + phase) + 0.1 * sin(clock * 173.0 + phase * 3.0)
			var length := 3.6 * nitro_level * flicker
			var width := 0.62 * (0.6 + 0.4 * nitro_level)
			flame.scale = Vector3(width, width, length)


func _build_body_mesh() -> ArrayMesh:
	var kit := ModelKit.new()
	return kit \
		.box(Vector3(1.8, 0.5, 4.2), Vector3(0.0, 0.62, 0.0), Palette.CAR_BODY) \
		.box(Vector3(1.84, 0.16, 4.24), Vector3(0.0, 0.42, 0.0), Palette.CAR_STRIPE) \
		.box(Vector3(0.46, 0.03, 1.5), Vector3(-0.2, 0.885, 1.32), Palette.CAR_STRIPE) \
		.box(Vector3(0.16, 0.03, 1.5), Vector3(0.24, 0.885, 1.32), Palette.CAR_STRIPE_ALT) \
		.box(Vector3(1.56, 0.46, 1.9), Vector3(0.0, 1.08, -0.3), Palette.GLASS) \
		.box(Vector3(1.62, 0.1, 1.7), Vector3(0.0, 1.36, -0.32), Palette.CAR_BODY) \
		.box(Vector3(0.46, 0.03, 1.7), Vector3(-0.2, 1.42, -0.32), Palette.CAR_STRIPE) \
		.box(Vector3(0.16, 0.03, 1.7), Vector3(0.24, 1.42, -0.32), Palette.CAR_STRIPE_ALT) \
		.box(Vector3(0.14, 0.5, 0.14), Vector3(0.74, 1.08, 0.6), Palette.CAR_BODY, Vector3(0.5, 0.0, 0.0)) \
		.box(Vector3(0.14, 0.5, 0.14), Vector3(-0.74, 1.08, 0.6), Palette.CAR_BODY, Vector3(0.5, 0.0, 0.0)) \
		.box(Vector3(0.46, 0.03, 0.9), Vector3(-0.2, 0.885, -1.65), Palette.CAR_STRIPE) \
		.box(Vector3(0.16, 0.03, 0.9), Vector3(0.24, 0.885, -1.65), Palette.CAR_STRIPE_ALT) \
		.box(Vector3(1.92, 0.2, 0.22), Vector3(0.0, 0.44, 2.16), Palette.METAL_DARK) \
		.box(Vector3(1.92, 0.2, 0.22), Vector3(0.0, 0.44, -2.16), Palette.METAL_DARK) \
		.box(Vector3(1.3, 0.34, 0.1), Vector3(0.0, 0.7, 2.24), Palette.METAL) \
		.box(Vector3(0.36, 0.16, 0.06), Vector3(0.62, 0.7, 2.11), Palette.HEADLIGHT) \
		.box(Vector3(0.36, 0.16, 0.06), Vector3(-0.62, 0.7, 2.11), Palette.HEADLIGHT) \
		.box(Vector3(0.4, 0.14, 0.06), Vector3(0.62, 0.72, -2.11), Palette.TAIL_LIGHT) \
		.box(Vector3(0.4, 0.14, 0.06), Vector3(-0.62, 0.72, -2.11), Palette.TAIL_LIGHT) \
		.box(Vector3(0.2, 0.18, 0.14), Vector3(0.45, 1.5, 0.42), Palette.HEADLIGHT) \
		.box(Vector3(0.2, 0.18, 0.14), Vector3(0.15, 1.5, 0.42), Palette.HEADLIGHT) \
		.box(Vector3(0.2, 0.18, 0.14), Vector3(-0.15, 1.5, 0.42), Palette.HEADLIGHT) \
		.box(Vector3(0.2, 0.18, 0.14), Vector3(-0.45, 1.5, 0.42), Palette.HEADLIGHT) \
		.box(Vector3(1.76, 0.07, 0.42), Vector3(0.0, 1.28, -2.02), Palette.CAR_STRIPE, Vector3(-0.12, 0.0, 0.0)) \
		.box(Vector3(0.1, 0.36, 0.3), Vector3(0.7, 1.06, -1.98), Palette.METAL_DARK) \
		.box(Vector3(0.1, 0.36, 0.3), Vector3(-0.7, 1.06, -1.98), Palette.METAL_DARK) \
		.box(Vector3(0.16, 0.36, 1.0), Vector3(0.94, 0.6, CarBody.AXLE_FRONT), Palette.METAL_DARK) \
		.box(Vector3(0.16, 0.36, 1.0), Vector3(-0.94, 0.6, CarBody.AXLE_FRONT), Palette.METAL_DARK) \
		.box(Vector3(0.16, 0.36, 1.0), Vector3(0.94, 0.6, -CarBody.AXLE_REAR), Palette.METAL_DARK) \
		.box(Vector3(0.16, 0.36, 1.0), Vector3(-0.94, 0.6, -CarBody.AXLE_REAR), Palette.METAL_DARK) \
		.cylinder(0.16, 0.16, 0.8, 6, Vector3(0.98, 0.5, -1.9), Palette.METAL, Vector3(HALF_PI, 0.0, 0.0)) \
		.cylinder(0.16, 0.16, 0.8, 6, Vector3(-0.98, 0.5, -1.9), Palette.METAL, Vector3(HALF_PI, 0.0, 0.0)) \
		.box(Vector3(0.5, 0.36, 0.3), Vector3(0.45, 1.06, -1.55), Palette.RAIDER_RED) \
		.build()


func _build_wheel_mesh() -> ArrayMesh:
	var kit := ModelKit.new()
	return kit \
		.cylinder(WHEEL_RADIUS * 2.0, WHEEL_RADIUS * 2.0, 0.32, 10, Vector3.ZERO, Palette.RUBBER, Vector3(0.0, 0.0, HALF_PI)) \
		.cylinder(0.4, 0.4, 0.34, 6, Vector3.ZERO, Palette.CAR_STRIPE_ALT, Vector3(0.0, 0.0, HALF_PI)) \
		.box(Vector3(0.36, 0.1, 0.5), Vector3.ZERO, Palette.METAL_DARK) \
		.build()


func _build_gun_mesh() -> ArrayMesh:
	var kit := ModelKit.new()
	return kit \
		.cylinder(0.5, 0.62, 0.24, 8, Vector3(0.0, 0.12, 0.0), Palette.METAL_DARK) \
		.box(Vector3(0.34, 0.3, 0.6), Vector3(0.0, 0.36, 0.0), Palette.METAL) \
		.box(Vector3(0.1, 0.1, 1.2), Vector3(0.09, 0.4, 0.8), Palette.METAL_DARK) \
		.box(Vector3(0.1, 0.1, 1.2), Vector3(-0.09, 0.4, 0.8), Palette.METAL_DARK) \
		.box(Vector3(0.26, 0.2, 0.3), Vector3(0.28, 0.34, -0.05), Palette.RAIDER_YELLOW) \
		.build()


func _build_fan_mesh() -> ArrayMesh:
	var kit := ModelKit.new()
	return kit \
		.box(Vector3(1.5, 0.16, 0.06), Vector3.ZERO, Palette.METAL) \
		.box(Vector3(0.16, 1.5, 0.06), Vector3.ZERO, Palette.METAL) \
		.box(Vector3(1.1, 0.14, 0.06), Vector3.ZERO, Palette.METAL_DARK, Vector3(0.0, 0.0, PI * 0.25)) \
		.box(Vector3(0.14, 1.1, 0.06), Vector3.ZERO, Palette.METAL_DARK, Vector3(0.0, 0.0, PI * 0.25)) \
		.cylinder(0.34, 0.34, 0.2, 8, Vector3.ZERO, Palette.CAR_STRIPE_ALT, Vector3(HALF_PI, 0.0, 0.0)) \
		.build()


func _build_plow_mesh() -> ArrayMesh:
	var kit := ModelKit.new()
	return kit \
		.box(Vector3(1.1, 0.7, 0.12), Vector3(0.5, 0.0, 0.12), Palette.METAL, Vector3(0.25, 0.45, 0.0)) \
		.box(Vector3(1.1, 0.7, 0.12), Vector3(-0.5, 0.0, 0.12), Palette.METAL, Vector3(0.25, -0.45, 0.0)) \
		.box(Vector3(0.16, 0.5, 0.5), Vector3(0.0, 0.05, 0.38), Palette.RAIDER_YELLOW) \
		.cylinder(0.0, 0.18, 0.5, 5, Vector3(0.6, 0.1, 0.42), Palette.METAL_DARK, Vector3(HALF_PI, 0.0, 0.0)) \
		.cylinder(0.0, 0.18, 0.5, 5, Vector3(-0.6, 0.1, 0.42), Palette.METAL_DARK, Vector3(HALF_PI, 0.0, 0.0)) \
		.build()


func _build_exhaust_flames() -> void:
	var glow_mat := StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.albedo_color = Palette.NITRO_GLOW
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Palette.NITRO_CORE

	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.5
	cone.height = 1.0
	cone.radial_segments = 6
	cone.rings = 1

	for side in [-1.0, 1.0]:
		var holder := Node3D.new()
		holder.position = Vector3(side * EXHAUST_HALF_SPAN, EXHAUST_HEIGHT, EXHAUST_REAR)
		holder.visible = false
		lean.add_child(holder)

		var glow := MeshInstance3D.new()
		glow.mesh = cone
		glow.material_override = glow_mat
		glow.rotation.x = HALF_PI
		glow.position.z = 0.5
		holder.add_child(glow)

		var core := MeshInstance3D.new()
		core.mesh = cone
		core.material_override = core_mat
		core.rotation.x = HALF_PI
		core.position.z = 0.275
		core.scale = Vector3(0.55, 0.55, 0.55)
		holder.add_child(core)

		_flames.append(holder)

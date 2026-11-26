class_name SimMath
extends RefCounted

# Shared math utilities, deterministic Mulberry32 RNG, BabylonJS -> Godot
# coordinate conversion helpers, and a fast MultiMesh InstanceBatch wrapper.

const HUGE_AABB := AABB(Vector3(-100000.0, -2000.0, -100000.0), Vector3(200000.0, 4000.0, 200000.0))


static func saturate(v: float) -> float:
	return clampf(v, 0.0, 1.0)


static func damp(from_val: float, to_val: float, rate: float, dt: float) -> float:
	return lerpf(from_val, to_val, 1.0 - exp(-rate * dt))


static func damp_angle(from_angle: float, to_angle: float, rate: float, dt: float) -> float:
	var diff := wrap_angle(to_angle - from_angle)
	return wrap_angle(from_angle + diff * (1.0 - exp(-rate * dt)))


static func smoothstep_f(edge0: float, edge1: float, v: float) -> float:
	var t := saturate((v - edge0) / (edge1 - edge0))
	return t * t * (3.0 - 2.0 * t)


static func wrap_angle(angle: float) -> float:
	var wrapped := fmod(angle + PI, TAU)
	if wrapped < 0.0:
		wrapped += TAU
	return wrapped - PI


static func rand_signed(magnitude: float) -> float:
	return (randf() * 2.0 - 1.0) * magnitude


static func hash2(a: int, b: int) -> float:
	# 32-bit unsigned mix matching src/math.ts hash2
	var h := ((a & 0xFFFFFFFF) * 374761393 + (b & 0xFFFFFFFF) * 668265263) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = (h ^ (h >> 16)) & 0xFFFFFFFF
	return float(h) / 4294967296.0


static func sim_pos(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, -z)


static func sim_basis_ypr(yaw: float, pitch: float, roll: float, sx: float = 1.0, sy: float = 1.0, sz: float = 1.0) -> Basis:
	# Exact conjugation S * R_sim * S where S = diag(1, 1, -1).
	# scaled_local() scales the basis columns in one native call.
	return Basis.from_euler(Vector3(-pitch, -yaw, roll), EULER_ORDER_YXZ).scaled_local(Vector3(sx, sy, sz))


static func sim_transform(
	x: float,
	y: float,
	z: float,
	yaw: float = 0.0,
	pitch: float = 0.0,
	roll: float = 0.0,
	sx: float = 1.0,
	sy: float = 1.0,
	sz: float = 1.0,
) -> Transform3D:
	# sim_basis_ypr() written out in place: this runs once per drawn instance.
	return Transform3D(
		Basis.from_euler(Vector3(-pitch, -yaw, roll), EULER_ORDER_YXZ).scaled_local(Vector3(sx, sy, sz)),
		Vector3(x, y, -z),
	)


static func sim_quat_transform(
	x: float,
	y: float,
	z: float,
	qx: float,
	qy: float,
	qz: float,
	qw: float,
	scale: float,
	scale_y: float,
	origin: float,
) -> Transform3D:
	# Exact conjugation S * B_sim * S for loose rigid bodies and leaning rooted plants
	var b00 := 1.0 - 2.0 * (qy * qy + qz * qz)
	var b10 := 2.0 * (qx * qy + qz * qw)
	var b20 := 2.0 * (qx * qz - qy * qw)

	var xy := 2.0 * (qx * qy - qz * qw)
	var yy := 1.0 - 2.0 * (qx * qx + qz * qz)
	var zy := 2.0 * (qy * qz + qx * qw)

	var b02 := 2.0 * (qx * qz + qy * qw)
	var b12 := 2.0 * (qy * qz - qx * qw)
	var b22 := 1.0 - 2.0 * (qx * qx + qy * qy)

	var col0 := Vector3(b00 * scale, b10 * scale, -b20 * scale)
	var col1 := Vector3(xy * scale_y, yy * scale_y, -zy * scale_y)
	var col2 := Vector3(-b02 * scale, -b12 * scale, b22 * scale)
	var pos := Vector3(x - xy * origin, y - yy * origin, -(z - zy * origin))
	return Transform3D(Basis(col0, col1, col2), pos)


class SeededRng:
	extends RefCounted

	var _state: int = 0

	func _init(seed_val: int) -> void:
		_state = seed_val & 0xFFFFFFFF

	func next() -> float:
		_state = (_state + 0x6D2B79F5) & 0xFFFFFFFF
		var t := ((_state ^ (_state >> 15)) * (1 | _state)) & 0xFFFFFFFF
		t = ((t + (((t ^ (t >> 7)) * (61 | t)) & 0xFFFFFFFF)) ^ t) & 0xFFFFFFFF
		return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0


class InstanceBatch:
	extends RefCounted

	var node: MultiMeshInstance3D
	var multimesh: MultiMesh
	var capacity: int = 0
	var count: int = 0
	var _tinted: bool = false

	func _init(
		parent: Node3D,
		mesh: Mesh,
		material: Material,
		max_count: int,
		tinted: bool = false,
		casts_shadow: bool = true,
		batch_name: String = "Batch",
	) -> void:
		capacity = max_count
		_tinted = tinted

		multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = tinted
		multimesh.mesh = mesh
		multimesh.instance_count = max_count
		multimesh.visible_instance_count = 0
		multimesh.custom_aabb = HUGE_AABB

		node = MultiMeshInstance3D.new()
		node.name = batch_name
		node.multimesh = multimesh
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visible = false
		parent.add_child(node)

	func begin() -> void:
		count = 0

	func push_transform(xform: Transform3D) -> void:
		if count >= capacity:
			return
		multimesh.set_instance_transform(count, xform)
		count += 1

	func push(
		x: float,
		y: float,
		z: float,
		yaw: float = 0.0,
		pitch: float = 0.0,
		roll: float = 0.0,
		sx: float = 1.0,
		sy: float = 1.0,
		sz: float = 1.0,
	) -> void:
		if count >= capacity:
			return
		multimesh.set_instance_transform(count, Transform3D(
			Basis.from_euler(Vector3(-pitch, -yaw, roll), EULER_ORDER_YXZ).scaled_local(Vector3(sx, sy, sz)),
			Vector3(x, y, -z),
		))
		count += 1

	func push_under(
		parent_xform: Transform3D,
		x: float,
		y: float,
		z: float,
		yaw: float,
		pitch: float,
		roll: float,
		sx: float,
		sy: float,
		sz: float,
	) -> Transform3D:
		var world := parent_xform * Transform3D(
			Basis.from_euler(Vector3(-pitch, -yaw, roll), EULER_ORDER_YXZ).scaled_local(Vector3(sx, sy, sz)),
			Vector3(x, y, -z),
		)
		if count < capacity:
			multimesh.set_instance_transform(count, world)
			count += 1
		return world

	func tint(color: Color) -> void:
		if not _tinted or count <= 0:
			return
		multimesh.set_instance_color(count - 1, color)

	func commit() -> void:
		multimesh.visible_instance_count = count
		node.visible = count > 0

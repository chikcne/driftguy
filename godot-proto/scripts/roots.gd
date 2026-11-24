class_name Roots
extends RefCounted

# Direct port of src/roots.ts: rooted cacti & dead trees resist, bend, sway,
# or tear out depending on impact momentum.

const OUTCOME_CLEAR := 0
const OUTCOME_HELD := 1
const OUTCOME_TORN := 2

const ROOT_BOUNCE := 0.15
const SWAY_KICK := 7.0
const SWAY_STIFFNESS := 196.0
const SWAY_DAMPING := 6.0
const SWAY_MAX_STEP := 1.0 / 30.0
const LEAN_LIMIT := 0.4
const REST_LEAN_SQ := 0.00001
const REST_SWAY_SQ := 0.001


class StrainResult:
	extends RefCounted
	var impulse: float = 0.0
	var x: float = 0.0
	var z: float = 0.0


static func strain(anchor: Variant, mover: Variant, radius: float, mass: float, out: StrainResult) -> int:
	out.impulse = 0.0
	var dx: float = anchor.x - mover.x
	var dz: float = anchor.z - mover.z
	var reach: float = radius + anchor.r
	var dist_sq := dx * dx + dz * dz
	if dist_sq >= reach * reach:
		return OUTCOME_CLEAR
	var dist := sqrt(dist_sq)
	if dist < 0.001:
		var spd := sqrt(mover.vx * mover.vx + mover.vz * mover.vz)
		dx = mover.vx / spd if spd > 0.0 else 0.0
		dz = mover.vz / spd if spd > 0.0 else 1.0
		dist = 1.0
	var nx := dx / dist
	var nz := dz / dist
	var closing: float = mover.vx * nx + mover.vz * nz
	var momentum := mass * closing
	out.x = mover.x + nx * radius
	out.z = mover.z + nz * radius
	if momentum > anchor.hold:
		out.impulse = anchor.tear
		mover.vx -= (nx * anchor.tear) / mass
		mover.vz -= (nz * anchor.tear) / mass
		return OUTCOME_TORN
	mover.x = anchor.x - nx * reach
	mover.z = anchor.z - nz * reach
	if closing <= 0.0:
		return OUTCOME_HELD
	mover.vx -= (1.0 + ROOT_BOUNCE) * closing * nx
	mover.vz -= (1.0 + ROOT_BOUNCE) * closing * nz
	var kick: float = (momentum / anchor.hold) * SWAY_KICK
	anchor.sway_x += nx * kick
	anchor.sway_z += nz * kick
	out.impulse = (1.0 + ROOT_BOUNCE) * momentum
	return OUTCOME_HELD


static func sway(anchor: Variant, dt: float) -> bool:
	var step := minf(dt, SWAY_MAX_STEP)
	anchor.sway_x += (-SWAY_STIFFNESS * anchor.lean_x - SWAY_DAMPING * anchor.sway_x) * step
	anchor.sway_z += (-SWAY_STIFFNESS * anchor.lean_z - SWAY_DAMPING * anchor.sway_z) * step
	anchor.lean_x += anchor.sway_x * step
	anchor.lean_z += anchor.sway_z * step
	var lean := sqrt(anchor.lean_x * anchor.lean_x + anchor.lean_z * anchor.lean_z)
	if lean > LEAN_LIMIT:
		var ux: float = anchor.lean_x / lean
		var uz: float = anchor.lean_z / lean
		anchor.lean_x = ux * LEAN_LIMIT
		anchor.lean_z = uz * LEAN_LIMIT
		var outward: float = anchor.sway_x * ux + anchor.sway_z * uz
		if outward > 0.0:
			anchor.sway_x -= outward * ux
			anchor.sway_z -= outward * uz
	var lean_sq: float = anchor.lean_x * anchor.lean_x + anchor.lean_z * anchor.lean_z
	var sway_sq: float = anchor.sway_x * anchor.sway_x + anchor.sway_z * anchor.sway_z
	return lean_sq > REST_LEAN_SQ or sway_sq > REST_SWAY_SQ


static func lean_transform(anchor: Variant, y: float, yaw: float, scale: float, scale_y: float) -> Transform3D:
	var lean := sqrt(anchor.lean_x * anchor.lean_x + anchor.lean_z * anchor.lean_z)
	var tilt := sin(lean * 0.5) / lean if lean > 0.000001 else 0.0
	var tx: float = anchor.lean_z * tilt
	var tz: float = -anchor.lean_x * tilt
	var tw := cos(lean * 0.5)
	var sy := sin(yaw * 0.5)
	var cy := cos(yaw * 0.5)
	return SimMath.sim_quat_transform(
		anchor.x,
		y,
		anchor.z,
		tx * cy - tz * sy,
		tw * sy,
		tx * sy + tz * cy,
		tw * cy,
		scale,
		scale_y,
		0.0,
	)

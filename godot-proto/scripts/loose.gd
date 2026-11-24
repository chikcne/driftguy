class_name LooseSystem
extends RefCounted

# Direct port of src/loose.ts: 120 Hz rigid-body physics for uprooted cacti,
# dead trees, shrubs, and knocked-over tire stacks.

const STEP := 1.0 / 120.0
const MAX_STEPS := 8
const MAX_BODIES := 56
const DESPAWN_DISTANCE := 240.0
const GRAVITY := 22.0
const GROUND_BOUNCE := 0.3
const BOUNCE_MIN_SPEED := 3.0
const GROUND_FRICTION := 0.7
const GROUND_SPIN_DAMPING := 1.6
const GROUND_SLIDE_DAMPING := 1.8
const AIR_DAMPING := 0.6
const SLEEP_SPEED_SQ := 0.3
const SLEEP_SPIN_SQ := 0.6
const SLEEP_SECONDS := 0.5
const SHOVE_BOUNCE := 0.1
const SHOVE_LIFT := 0.28
const SHOVE_CLEARANCE := 1.1
const OBSTACLE_BOUNCE := 0.3
const GYRATION := 0.6
const UPROOT_SPIN := 0.8


class ShoveResult:
	extends RefCounted
	var hit: bool = false
	var impulse: float = 0.0
	var x: float = 0.0
	var z: float = 0.0
	var torn: int = 0


class Obstruction:
	extends RefCounted
	var hit: bool = false
	var nx: float = 0.0
	var nz: float = 0.0


class LooseBody:
	extends RefCounted
	var kind: String = ""
	var x: float = 0.0
	var y: float = 0.0
	var z: float = 0.0
	var vx: float = 0.0
	var vy: float = 0.0
	var vz: float = 0.0
	var qx: float = 0.0
	var qy: float = 0.0
	var qz: float = 0.0
	var qw: float = 1.0
	var wx: float = 0.0
	var wy: float = 0.0
	var wz: float = 0.0
	var scale: float = 1.0
	var scale_y: float = 1.0
	var origin: float = 0.0
	var mass: float = 1.0
	var inertia: float = 1.0
	var reach: float = 1.0
	var girth: float = 0.5
	var points: PackedFloat32Array = PackedFloat32Array()
	var calm: float = 0.0
	var asleep: bool = false


var bodies: Array[LooseBody] = []
var _obstruction := Obstruction.new()
var _leftover := 0.0
var _b := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])


func clear() -> void:
	bodies.clear()
	_leftover = 0.0


func spawn(kind: String, spec: Props.LooseSpec, x: float, base_y: float, z: float, yaw: float, scale: float, scale_y: float) -> LooseBody:
	var orig := spec.centre * scale_y
	var pts := PackedFloat32Array()
	pts.resize(spec.points.size() * 4)
	var reach := 0.0
	for i in spec.points.size():
		var p: Vector4 = spec.points[i]
		var lx := p.x * scale
		var ly := p.y * scale_y - orig
		var lz := p.z * scale
		pts[i * 4] = lx
		pts[i * 4 + 1] = ly
		pts[i * 4 + 2] = lz
		pts[i * 4 + 3] = p.w * scale
		reach = maxf(reach, sqrt(lx * lx + ly * ly + lz * lz) + p.w * scale)
	var mass := spec.mass * scale * scale
	var body := LooseBody.new()
	body.kind = kind
	body.x = x
	body.y = base_y + orig
	body.z = z
	body.qy = sin(yaw * 0.5)
	body.qw = cos(yaw * 0.5)
	body.wx = SimMath.rand_signed(UPROOT_SPIN)
	body.wy = SimMath.rand_signed(UPROOT_SPIN)
	body.wz = SimMath.rand_signed(UPROOT_SPIN)
	body.scale = scale
	body.scale_y = scale_y
	body.origin = orig
	body.mass = mass
	var gy := GYRATION * reach
	body.inertia = mass * gy * gy
	body.reach = reach
	body.girth = spec.radius * scale
	body.points = pts
	bodies.append(body)
	if bodies.size() > MAX_BODIES:
		bodies.pop_front()
	return body


func _orient(body: LooseBody) -> void:
	var qx := body.qx
	var qy := body.qy
	var qz := body.qz
	var qw := body.qw
	_b[0] = 1.0 - 2.0 * (qy * qy + qz * qz)
	_b[1] = 2.0 * (qx * qy - qz * qw)
	_b[2] = 2.0 * (qx * qz + qy * qw)
	_b[3] = 2.0 * (qx * qy + qz * qw)
	_b[4] = 1.0 - 2.0 * (qx * qx + qz * qz)
	_b[5] = 2.0 * (qy * qz - qx * qw)
	_b[6] = 2.0 * (qx * qz - qy * qw)
	_b[7] = 2.0 * (qy * qz + qx * qw)
	_b[8] = 1.0 - 2.0 * (qx * qx + qy * qy)


func _punch(body: LooseBody, rx: float, ry: float, rz: float, jx: float, jy: float, jz: float) -> void:
	body.vx += jx / body.mass
	body.vy += jy / body.mass
	body.vz += jz / body.mass
	body.wx += (ry * jz - rz * jy) / body.inertia
	body.wy += (rz * jx - rx * jz) / body.inertia
	body.wz += (rx * jy - ry * jx) / body.inertia


func shove(mover: Variant, radius: float, mass: float, out: ShoveResult) -> ShoveResult:
	out.hit = false
	out.impulse = 0.0
	out.x = 0.0
	out.z = 0.0
	out.torn = 0
	var ceiling_set := false
	var ceiling := 0.0
	for body in bodies:
		var span := radius + body.reach
		var off_x: float = body.x - mover.x
		var off_z: float = body.z - mover.z
		if off_x * off_x + off_z * off_z >= span * span:
			continue
		if not ceiling_set:
			ceiling = DesertTerrain.ground_height(mover.x, mover.z) + SHOVE_CLEARANCE
			ceiling_set = true
		_orient(body)
		var pts := body.points
		var i := 0
		var plen := pts.size()
		while i < plen:
			var lx := pts[i]
			var ly := pts[i + 1]
			var lz := pts[i + 2]
			var sz := pts[i + 3]
			i += 4
			var cx := _b[0] * lx + _b[1] * ly + _b[2] * lz
			var cy := _b[3] * lx + _b[4] * ly + _b[5] * lz
			var cz := _b[6] * lx + _b[7] * ly + _b[8] * lz
			if body.y + cy - sz > ceiling:
				continue
			var dx: float = body.x + cx - mover.x
			var dz: float = body.z + cz - mover.z
			var limit := radius + sz
			var dist_sq := dx * dx + dz * dz
			if dist_sq >= limit * limit:
				continue
			var dist := sqrt(dist_sq)
			if dist < 0.001:
				var spd := sqrt(mover.vx * mover.vx + mover.vz * mover.vz)
				dx = mover.vx / spd if spd > 0.0 else 0.0
				dz = mover.vz / spd if spd > 0.0 else 1.0
				dist = 1.0
			var nx := dx / dist
			var nz := dz / dist
			var rx := cx - nx * sz
			var ry := cy
			var rz := cz - nz * sz
			var ux := body.vx + body.wy * rz - body.wz * ry
			var uz := body.vz + body.wx * ry - body.wy * rx
			var closing: float = (ux - mover.vx) * nx + (uz - mover.vz) * nz
			var depth := limit - sqrt(dist_sq)
			body.x += nx * depth
			body.z += nz * depth
			body.asleep = false
			body.calm = 0.0
			out.hit = true
			if closing >= 0.0:
				continue
			var tx := ry * nz
			var ty := rz * nx - rx * nz
			var tz := -ry * nx
			var resistance := 1.0 / body.mass + (tx * tx + ty * ty + tz * tz) / body.inertia + 1.0 / mass
			var imp := (-(1.0 + SHOVE_BOUNCE) * closing) / resistance
			_punch(body, rx, ry, rz, imp * nx, 0.0, imp * nz)
			body.vy += (imp * SHOVE_LIFT) / body.mass
			mover.vx -= (imp * nx) / mass
			mover.vz -= (imp * nz) / mass
			out.impulse += imp
			out.x += (mover.x + nx * radius) * imp
			out.z += (mover.z + nz * radius) * imp
	if out.impulse > 0.0:
		out.x /= out.impulse
		out.z /= out.impulse
	return out


func step(dt: float, focus_x: float, focus_z: float, resolve_fn: Callable = Callable()) -> void:
	for i in range(bodies.size() - 1, -1, -1):
		var body := bodies[i]
		if absf(body.x - focus_x) > DESPAWN_DISTANCE or absf(body.z - focus_z) > DESPAWN_DISTANCE:
			bodies.remove_at(i)
	_leftover += dt
	var steps := 0
	while _leftover >= STEP:
		_leftover -= STEP
		if steps >= MAX_STEPS:
			steps += 1
			continue
		steps += 1
		for body in bodies:
			if not body.asleep:
				_integrate(body, STEP, resolve_fn)


func _integrate(body: LooseBody, dt: float, resolve_fn: Callable) -> void:
	body.vy -= GRAVITY * dt
	body.x += body.vx * dt
	body.y += body.vy * dt
	body.z += body.vz * dt

	var qx := body.qx
	var qy := body.qy
	var qz := body.qz
	var qw := body.qw
	var wx := body.wx
	var wy := body.wy
	var wz := body.wz
	var half := dt * 0.5
	body.qx = qx + half * (wx * qw + wy * qz - wz * qy)
	body.qy = qy + half * (wy * qw + wz * qx - wx * qz)
	body.qz = qz + half * (wz * qw + wx * qy - wy * qx)
	body.qw = qw - half * (wx * qx + wy * qy + wz * qz)
	var norm := sqrt(body.qx * body.qx + body.qy * body.qy + body.qz * body.qz + body.qw * body.qw)
	if norm < 0.000001:
		norm = 1.0
	body.qx /= norm
	body.qy /= norm
	body.qz /= norm
	body.qw /= norm

	_orient(body)
	var pts := body.points
	var sunk := 0.0
	var grounded := false
	var i := 0
	var plen := pts.size()
	while i < plen:
		var lx := pts[i]
		var ly := pts[i + 1]
		var lz := pts[i + 2]
		var sz := pts[i + 3]
		i += 4
		var rx := _b[0] * lx + _b[1] * ly + _b[2] * lz
		var ry := _b[3] * lx + _b[4] * ly + _b[5] * lz - sz
		var rz := _b[6] * lx + _b[7] * ly + _b[8] * lz
		var depth := DesertTerrain.ground_height(body.x + rx, body.z + rz) - (body.y + ry)
		if depth <= 0.0:
			continue
		grounded = true
		if depth > sunk:
			sunk = depth
		var uy := body.vy + body.wz * rx - body.wx * rz
		if uy >= 0.0:
			continue
		var bounce := GROUND_BOUNCE if uy < -BOUNCE_MIN_SPEED else 0.0
		var normal := (-(1.0 + bounce) * uy) / (1.0 / body.mass + (rx * rx + rz * rz) / body.inertia)
		_punch(body, rx, ry, rz, 0.0, normal, 0.0)

		var ux := body.vx + body.wy * rz - body.wz * ry
		var uz := body.vz + body.wx * ry - body.wy * rx
		var slide := sqrt(ux * ux + uz * uz)
		if slide < 0.001:
			continue
		var tx := ux / slide
		var tz := uz / slide
		var ax := ry * tz
		var ay := rz * tx - rx * tz
		var az := -ry * tx
		var grip := minf(GROUND_FRICTION * normal, slide / (1.0 / body.mass + (ax * ax + ay * ay + az * az) / body.inertia))
		_punch(body, rx, ry, rz, -grip * tx, 0.0, -grip * tz)

	if grounded:
		body.y += sunk
		var spin := exp(-GROUND_SPIN_DAMPING * dt)
		var slide_d := exp(-GROUND_SLIDE_DAMPING * dt)
		body.wx *= spin
		body.wy *= spin
		body.wz *= spin
		body.vx *= slide_d
		body.vz *= slide_d
	else:
		var drag := exp(-AIR_DAMPING * dt)
		body.vx *= drag
		body.vz *= drag

	if resolve_fn.is_valid():
		resolve_fn.call(body, body.girth, _obstruction)
		if _obstruction.hit:
			var into := body.vx * _obstruction.nx + body.vz * _obstruction.nz
			if into < 0.0:
				body.vx -= (1.0 + OBSTACLE_BOUNCE) * into * _obstruction.nx
				body.vz -= (1.0 + OBSTACLE_BOUNCE) * into * _obstruction.nz

	var speed_sq := body.vx * body.vx + body.vy * body.vy + body.vz * body.vz
	var spin_sq := body.wx * body.wx + body.wy * body.wy + body.wz * body.wz
	if grounded and speed_sq < SLEEP_SPEED_SQ and spin_sq < SLEEP_SPIN_SQ:
		body.calm += dt
		if body.calm > SLEEP_SECONDS:
			body.asleep = true
			body.vx = 0.0
			body.vy = 0.0
			body.vz = 0.0
			body.wx = 0.0
			body.wy = 0.0
			body.wz = 0.0
	else:
		body.calm = 0.0

class_name CarBody
extends RefCounted

# Direct 1:1 port of src/vehicle.ts (240 Hz drift handling model).
# Simulation coordinates: +X right, +Z forward (heading = 0 -> +Z, steer > 0 turns right).

const AXLE_FRONT := 1.25
const AXLE_REAR := 1.35
const HALF_TRACK := 0.8

const WHEELBASE := AXLE_FRONT + AXLE_REAR
const WEIGHT_FRONT := AXLE_REAR / WHEELBASE
const WEIGHT_REAR := AXLE_FRONT / WHEELBASE
const SUBSTEP := 1.0 / 240.0
const LOW_SPEED_SOFTENING := 1.5
const TYRE_STIFFNESS := 6.0
const TYRE_SHAPE := 1.6
const TRACTION_LIMIT := 15.0
const BRAKE_DECEL := 17.0
const LOCKED_REAR_FRICTION := 0.7
const SELF_ALIGN := 1.0
const MAX_STEER_ANGLE := 1.1
const YAW_DAMPING := 0.9
const REVERSE_SPEED_FRACTION := 0.3
const BRAKE_REAR_UNLOAD := 0.3
const LIFT_OFF_REAR_UNLOAD := 0.1
const ROLLING_DRAG := 0.5
const LINEAR_DRAG := 0.012
const ENGINE_BRAKING := 1.2
const DRIFT_ANGLE_LIMIT := 0.8
const SLIDE_SCRUB := 0.38
const HANDBRAKE_DRIFT_ANGLE_LIMIT := 1.25
const DRIFT_CATCH_STIFFNESS := 16.0
const DRIFT_CATCH_DAMPING := 3.0
const NITROUS_THRUST := 21.0
const NITROUS_TOP_SPEED := 0.45
const OVERSPEED_DRAG := 1.6

# Base tuning matching BASE_TUNING in src/vehicle.ts
var engine_accel := 13.0
var top_speed := 33.0
var grip_front := 12.5
var grip_rear := 11.0
var steer_lock_low := 0.6
var steer_lock_high := 0.26
var steer_speed := 4.2
var yaw_response := 1.0

var x := 0.0
var z := 0.0
var heading := 0.0
var vx := 0.0
var vz := 0.0
var yaw_rate := 0.0
var steer_angle := 0.0

var speed := 0.0
var forward_speed := 0.0
var lateral_speed := 0.0
var rear_slip_speed := 0.0
var front_slip_speed := 0.0
var burnout := 0.0
var long_accel := 0.0
var lat_accel := 0.0

var _leftover := 0.0


static func _saturate(v: float) -> float:
	return clampf(v, 0.0, 1.0)


static func _tyre_curve(slip_angle: float) -> float:
	return sin(TYRE_SHAPE * atan(TYRE_STIFFNESS * slip_angle))


func reset() -> void:
	x = 0.0
	z = 0.0
	heading = 0.0
	vx = 0.0
	vz = 0.0
	yaw_rate = 0.0
	steer_angle = 0.0
	speed = 0.0
	forward_speed = 0.0
	lateral_speed = 0.0
	rear_slip_speed = 0.0
	front_slip_speed = 0.0
	burnout = 0.0
	long_accel = 0.0
	lat_accel = 0.0
	_leftover = 0.0


func get_drift_angle() -> float:
	return atan2(lateral_speed, absf(forward_speed) + 0.5)


func step(dt: float, in_throttle: float, in_brake: float, in_steer: float, in_handbrake: bool, in_boost: float, in_stop: float) -> void:
	_leftover += minf(dt, 0.05)
	while _leftover >= SUBSTEP:
		_substep(SUBSTEP, in_throttle, in_brake, in_steer, in_handbrake, in_boost, in_stop)
		_leftover -= SUBSTEP


func _substep(dt: float, in_throttle: float, in_brake: float, in_steer: float, in_handbrake: bool, in_boost: float, in_stop: float) -> void:
	var fx := sin(heading)
	var fz := cos(heading)
	var rx := fz
	var rz := -fx
	var v_f := vx * fx + vz * fz
	var v_r := vx * rx + vz * rz
	var w := yaw_rate
	var abs_f := absf(v_f)
	var direction := 1.0 if v_f >= 0.0 else -1.0

	var front_lat := v_r + AXLE_FRONT * w
	var rear_lat := v_r - AXLE_REAR * w

	var speed_fraction := _saturate(abs_f / top_speed)
	var lock := lerpf(steer_lock_low, steer_lock_high, speed_fraction)
	var align_angle := atan2(front_lat, abs_f + 1.0) if v_f > 2.0 else 0.0
	var steer_target := clampf(in_steer * lock + SELF_ALIGN * align_angle, -MAX_STEER_ANGLE, MAX_STEER_ANGLE)
	steer_angle = move_toward(steer_angle, steer_target, steer_speed * dt)

	var cd := cos(steer_angle)
	var sd := sin(steer_angle)
	var wheel_lat := -sd * v_f + cd * front_lat
	var wheel_long := cd * v_f + sd * front_lat
	var front_slip_angle := atan2(wheel_lat, absf(wheel_long) + LOW_SPEED_SOFTENING)
	var front_force := -grip_front * WEIGHT_FRONT * _tyre_curve(front_slip_angle)

	var boost := _saturate(in_boost)
	var throttle := maxf(in_throttle, boost)
	var speed_limit := top_speed * (1.0 + NITROUS_TOP_SPEED * boost)
	var ratio := v_f / speed_limit
	var headroom := maxf(0.0, 1.0 - ratio * ratio) if v_f > 0.0 else 1.0
	var reversing := in_brake > 0.0 and in_stop <= 0.0 and throttle <= 0.0 and v_f < 1.5
	var engine := 0.0
	var brake := 0.0
	if reversing:
		var reverse_limit := top_speed * REVERSE_SPEED_FRACTION
		engine = -in_brake * engine_accel * 0.6 * _saturate(1.0 + v_f / reverse_limit)
	else:
		engine = throttle * engine_accel * headroom
		brake = maxf(in_brake, in_stop)
	if in_handbrake:
		engine = 0.0

	var traction_use := minf(0.97, absf(engine) / TRACTION_LIMIT)
	var rear_grip_factor := sqrt(1.0 - traction_use * traction_use)
	rear_grip_factor *= 1.0 - BRAKE_REAR_UNLOAD * brake * _saturate(abs_f / 6.0)
	if throttle <= 0.05 and not reversing:
		rear_grip_factor *= 1.0 - LIFT_OFF_REAR_UNLOAD

	var rear_lat_force := 0.0
	var rear_long_force := 0.0
	if in_handbrake:
		var rear_speed := sqrt(v_f * v_f + rear_lat * rear_lat)
		var scale := (LOCKED_REAR_FRICTION * grip_rear * WEIGHT_REAR * _saturate(rear_speed / 1.5)) / (rear_speed + 0.0001)
		rear_lat_force = -rear_lat * scale
		rear_long_force = -v_f * scale
	else:
		var rear_slip_angle := atan2(rear_lat, abs_f + LOW_SPEED_SOFTENING)
		rear_lat_force = -grip_rear * WEIGHT_REAR * rear_grip_factor * _tyre_curve(rear_slip_angle)

	var brake_force := -direction * brake * BRAKE_DECEL * _saturate(abs_f)
	var coasting := ENGINE_BRAKING if (throttle <= 0.05 and not reversing) else 0.0
	var drag_force := -((ROLLING_DRAG + coasting) * tanh(v_f) + LINEAR_DRAG * v_f + OVERSPEED_DRAG * maxf(0.0, v_f - speed_limit))
	var force_long := engine + boost * NITROUS_THRUST * headroom + brake_force + drag_force + rear_long_force - front_force * sd
	var force_lat := front_force * cd + rear_lat_force

	var yaw_accel := (
		((AXLE_FRONT * front_force * cd - AXLE_REAR * rear_lat_force) / (AXLE_FRONT * AXLE_REAR)) * yaw_response
		- w * YAW_DAMPING
		+ _drift_catch(v_f, v_r, w, in_handbrake)
	)

	var scrub := 0.0 if in_handbrake else (SLIDE_SCRUB * maxf(0.0, absf(rear_lat) - 2.0)) / (sqrt(v_f * v_f + v_r * v_r) + 0.5)
	vx += (fx * force_long + rx * force_lat - vx * scrub) * dt
	vz += (fz * force_long + rz * force_lat - vz * scrub) * dt
	yaw_rate += yaw_accel * dt
	heading += yaw_rate * dt
	x += vx * dt
	z += vz * dt

	speed = sqrt(vx * vx + vz * vz)
	forward_speed = v_f
	lateral_speed = v_r
	rear_slip_speed = sqrt(v_f * v_f + rear_lat * rear_lat) if in_handbrake else absf(rear_lat)
	front_slip_speed = absf(wheel_lat)
	burnout = 0.0 if in_handbrake else traction_use * throttle * _saturate(1.0 - abs_f / (top_speed * 0.6))
	long_accel = lerpf(long_accel, force_long, 0.02)
	lat_accel = lerpf(lat_accel, force_lat, 0.02)


func _drift_catch(v_f: float, v_r: float, w: float, in_handbrake: bool) -> float:
	var spd := sqrt(v_f * v_f + v_r * v_r)
	if spd < 3.0:
		return 0.0
	var slip_angle := atan2(v_r, v_f)
	var limit := HANDBRAKE_DRIFT_ANGLE_LIMIT if in_handbrake else DRIFT_ANGLE_LIMIT
	var excess := absf(slip_angle) - limit
	if excess <= 0.0 or absf(slip_angle) > PI * 0.75:
		return 0.0
	var authority := _saturate(spd / 8.0)
	var swinging_out := 1.0 if signf(slip_angle) * w < 0.0 else 0.0
	return authority * (signf(slip_angle) * excess * DRIFT_CATCH_STIFFNESS - w * DRIFT_CATCH_DAMPING * swinging_out * _saturate(excess * 4.0))


func smoke_intensity() -> float:
	var slide := _saturate((rear_slip_speed - 2.0) / 7.0)
	var spin := 0.7 * burnout * burnout
	return minf(1.5, slide + spin)

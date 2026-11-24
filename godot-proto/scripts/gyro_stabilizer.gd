class_name GyroStabilizer
extends RefCounted

# High-accuracy roll estimator for steering + counter-rotating horizon lock.
#
# On iOS, Godot's platform/ios/godot_view.mm already rotates CoreMotion's
# CMDeviceMotion gravity and rotationRate into the active screen orientation:
#   +X = screen right, +Y = screen up, +Z = out of screen toward viewer.
#
# Turning the phone clockwise (steering right) produces:
#   - gravity tilting toward +X (gravity_roll = atan2(g.x, -g.y) > 0)
#   - negative rotation rate around +Z (-gyro.z > 0)
#
# Fusing gyro.z (zero-lag) with gravity_roll (drift-free) gives crisp,
# drift-free horizon lock, with automatic gimbal fade if the phone is held flat.
# On desktop (where no IMU is present), keyboard A/D or Left/Right simulates
# turning the phone like a steering wheel so counter-rotation can be previewed.

var max_steer_deg := 38.0
var deadzone_deg := 2.5
var steer_curve := 1.25
var gravity_correction := 0.035 # Complementary filter anchor weight per 60Hz tick
var counter_rotate_scale := 1.0 # 1.0 = full horizon lock, 0.5 = half, 0.0 = off
var invert_gyro := false

var has_hardware_imu := false
var raw_gyro := Vector3.ZERO
var raw_gravity := Vector3.ZERO
var gravity_roll := 0.0
var fused_roll := 0.0
var zero_offset := 0.0
var plane_gravity := 0.0

var steer_output := 0.0
var display_roll := 0.0 # Radians to counter-rotate camera (+ = phone turned clockwise)

var _initialized := false
var _sim_roll := 0.0


func recenter() -> void:
	zero_offset = fused_roll


func reset_zero() -> void:
	zero_offset = 0.0


func update(dt: float, sim_left: bool, sim_right: bool, sim_hold_left: bool, sim_hold_right: bool) -> void:
	raw_gyro = Input.get_gyroscope()
	raw_gravity = Input.get_gravity()

	var grav_len_sq := raw_gravity.length_squared()
	var gyro_len_sq := raw_gyro.length_squared()
	if grav_len_sq > 0.01 or gyro_len_sq > 0.0001:
		has_hardware_imu = true

	if has_hardware_imu:
		_update_imu(dt)
	else:
		_update_desktop_sim(dt, sim_left, sim_right, sim_hold_left, sim_hold_right)

	var relative_roll := _wrap_angle(fused_roll - zero_offset)
	var sign_mult := -1.0 if invert_gyro else 1.0
	var signed_roll := relative_roll * sign_mult

	# Map roll angle -> [-1, 1] steering with deadzone and gentle non-linear curve
	var max_rad := deg_to_rad(maxf(10.0, max_steer_deg))
	var dead_rad := deg_to_rad(deadzone_deg)
	var mag := absf(signed_roll)
	if mag <= dead_rad:
		steer_output = 0.0
	else:
		var norm := clampf((mag - dead_rad) / maxf(0.01, max_rad - dead_rad), 0.0, 1.0)
		steer_output = signf(signed_roll) * pow(norm, steer_curve)

	# Counter-rotation uses the true physical roll (so screen stays level with gravity)
	display_roll = signed_roll * counter_rotate_scale


func _update_imu(dt: float) -> void:
	# In screen coords (+X right, +Y up), upright level gravity is (0, -9.8, 0).
	# Clockwise rotation of the phone (+roll) shifts gravity toward +X.
	plane_gravity = sqrt(raw_gravity.x * raw_gravity.x + raw_gravity.y * raw_gravity.y)
	if plane_gravity > 0.25:
		gravity_roll = atan2(raw_gravity.x, -raw_gravity.y)

	if not _initialized:
		fused_roll = gravity_roll if plane_gravity > 0.25 else 0.0
		_initialized = true
		return

	# Integrate instantaneous gyro around screen Z axis (clockwise = -gyro.z)
	var predicted := _wrap_angle(fused_roll - raw_gyro.z * dt)

	# Fade gravity anchor out smoothly if phone is held nearly flat (avoids gimbal jitter)
	var flat_fade := clampf((plane_gravity - 1.2) / 3.3, 0.0, 1.0)
	var alpha := 1.0 - pow(1.0 - clampf(gravity_correction, 0.0, 0.5), dt * 60.0)
	alpha *= flat_fade

	if alpha > 0.0 and plane_gravity > 0.25:
		fused_roll = _lerp_angle(predicted, gravity_roll, alpha)
	else:
		fused_roll = predicted


func _update_desktop_sim(dt: float, left: bool, right: bool, hold_left: bool, hold_right: bool) -> void:
	# Desktop preview:
	# - A/D or Left/Right tilts virtual phone smoothly and springs back to level
	# - Q/E holds an exact tilt angle without springing back (great for inspecting horizon lock)
	var max_rad := deg_to_rad(max_steer_deg)
	if hold_left or hold_right:
		var delta_dir := (1.0 if hold_right else 0.0) - (1.0 if hold_left else 0.0)
		_sim_roll = clampf(_sim_roll + delta_dir * deg_to_rad(75.0) * dt, -deg_to_rad(75.0), deg_to_rad(75.0))
	else:
		var target := ((1.0 if right else 0.0) - (1.0 if left else 0.0)) * max_rad
		_sim_roll = lerpf(_sim_roll, target, 1.0 - exp(-9.0 * dt))
	fused_roll = _sim_roll
	gravity_roll = _sim_roll
	plane_gravity = 9.81


static func _wrap_angle(angle: float) -> float:
	return fposmod(angle + PI, TAU) - PI


static func _lerp_angle(from_angle: float, to_angle: float, weight: float) -> float:
	var diff := _wrap_angle(to_angle - from_angle)
	return _wrap_angle(from_angle + diff * weight)

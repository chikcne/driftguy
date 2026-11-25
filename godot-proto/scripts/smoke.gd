class_name SmokeSystem
extends Node3D

# Direct port of src/smoke.ts puff simulation + GPU cel-shaded clustered lump
# MultiMesh renderer tuned for 60-120 FPS on iOS Metal.

const PUFF_WHITE := 0
const PUFF_ASH := 1
const PUFF_EMBER := 2
const PUFF_TOXIC := 3
const PUFF_DUST := 4
const PUFF_FIRE := 5
const PUFF_SOOT := 6
const DAMAGING_KINDS := 4

const LOOK_COLORS := [
	Color(0.98, 0.97, 0.95), # white
	Color(0.50, 0.51, 0.55), # ash
	Color(0.95, 0.34, 0.24), # ember
	Color(0.58, 0.86, 0.36), # toxic
	Color(0.98, 0.86, 0.70), # dust
	Color(1.00, 0.60, 0.18), # fire
	Color(0.16, 0.14, 0.15), # soot
]
const LOOK_GLOWS := [0.0, 0.0, 0.18, 0.12, 0.0, 0.95, 0.0]

const MAX_PUFFS := 2200
const MAX_DENSE := 1800
const MAX_DUST := 600
const GRID_CELL := 4.0
const GRID_SPAN := 128
const GRID_HALF := 64
const SAMPLE_REACH_CELLS := 2
const MAX_RADIUS := 8.0
const SQUASH_RADIUS := 4.5
const AIR_DRAG := 2.2
const JET_DRAG := 0.35
const HEAT_FADE_SECONDS := 1.5
const HOT_RISE_SPEED := 2.4
const COOL_RISE_SPEED := 0.3
const LOFT_MIN := 0.6
const LOFT_SPREAD := 0.9
const CEILING_HEIGHT := 10.0
const GROUND_HUG := 0.55
const WAKE_PULL := 4.0
const WAKE_CARRY := 0.6
const WAKE_LEAD := 2.0
const WAKE_HALF_WIDTH := 1.8
const WAKE_FLARE := 0.22
const WAKE_INFLOW := 0.25
const BOW_PUSH := 0.35
const WAKE_UPWASH := 0.08
const WAKE_CHURN := 3.0
const VIGOR_FADE_SECONDS := 1.8
const VIGOR_MAX := 1.6
const BILLOW_WAVENUMBER := 0.85
const BILLOW_HEIGHT_WAVENUMBER := 0.57
const BILLOW_ROLL := BILLOW_HEIGHT_WAVENUMBER / BILLOW_WAVENUMBER
const BILLOW_CALM := 0.45
const BILLOW_GAIN := 2.6
const EDDY_WAVENUMBER := 2.2
const EDDY_SHEAR := 1.3
const EDDY_CALM := 0.2
const EDDY_GAIN := 1.8
const WAVE_SIZE := 4096
const WAVE_MASK := 4095
const WAVE_QUARTER := 1024
const WAVE_SCALE := float(WAVE_SIZE) / TAU
const DILUTION_EXPONENT := 0.8
const FLOOR_REFRESH_MASK := 3
const NOISE_RISE := 0.35


class SmokeSample:
	extends RefCounted
	var total: float = 0.0
	var by_kind: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])


var count := 0
var px := PackedFloat32Array()
var py := PackedFloat32Array()
var pz := PackedFloat32Array()
var vx := PackedFloat32Array()
var vy := PackedFloat32Array()
var vz := PackedFloat32Array()
var age := PackedFloat32Array()
var life := PackedFloat32Array()
var start_radius := PackedFloat32Array()
var growth := PackedFloat32Array()
var radius := PackedFloat32Array()
var density := PackedFloat32Array()
var strength := PackedFloat32Array()
var heat := PackedFloat32Array()
var vigor := PackedFloat32Array()
var floor_y := PackedFloat32Array()
var seed_arr := PackedFloat32Array()
var kind := PackedByteArray()

var _wave := PackedFloat32Array()
var _grid_head := PackedInt32Array()
var _grid_next := PackedInt32Array()
var _grid_origin_x := 0
var _grid_origin_z := 0
var _frame := 0
var _drift := Vector3.ZERO

var _dense_mm: MultiMesh
var _dense_mmi: MultiMeshInstance3D
var _dense_mat: ShaderMaterial
var _dust_mm: MultiMesh
var _dust_mmi: MultiMeshInstance3D


func setup(fog_color: Color, fog_start: float, fog_end: float, sun_dir_godot: Vector3) -> void:
	px.resize(MAX_PUFFS)
	py.resize(MAX_PUFFS)
	pz.resize(MAX_PUFFS)
	vx.resize(MAX_PUFFS)
	vy.resize(MAX_PUFFS)
	vz.resize(MAX_PUFFS)
	age.resize(MAX_PUFFS)
	life.resize(MAX_PUFFS)
	start_radius.resize(MAX_PUFFS)
	growth.resize(MAX_PUFFS)
	radius.resize(MAX_PUFFS)
	density.resize(MAX_PUFFS)
	strength.resize(MAX_PUFFS)
	heat.resize(MAX_PUFFS)
	vigor.resize(MAX_PUFFS)
	floor_y.resize(MAX_PUFFS)
	seed_arr.resize(MAX_PUFFS)
	kind.resize(MAX_PUFFS)

	_grid_head.resize(GRID_SPAN * GRID_SPAN)
	_grid_next.resize(MAX_PUFFS)

	_wave.resize(WAVE_SIZE)
	for i in WAVE_SIZE:
		_wave[i] = sin((float(i) / float(WAVE_SIZE)) * TAU)

	# Dense cel-shaded clustered smoke sphere mesh
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6

	var lump_shader: Shader = load("res://shaders/smoke_lump.gdshader")
	_dense_mat = ShaderMaterial.new()
	_dense_mat.shader = lump_shader
	var sunward := (-sun_dir_godot)
	sunward.y *= 0.75
	sunward = sunward.normalized()
	_dense_mat.set_shader_parameter("sun_dir", sunward)
	_dense_mat.set_shader_parameter("fog_color", Vector3(fog_color.r, fog_color.g, fog_color.b))
	_dense_mat.set_shader_parameter("fog_range", Vector2(fog_start, fog_end))

	_dense_mm = MultiMesh.new()
	_dense_mm.transform_format = MultiMesh.TRANSFORM_3D
	_dense_mm.use_colors = true
	_dense_mm.use_custom_data = true
	_dense_mm.mesh = sphere
	_dense_mm.instance_count = MAX_DENSE
	_dense_mm.visible_instance_count = 0
	_dense_mm.custom_aabb = SimMath.HUGE_AABB

	_dense_mmi = MultiMeshInstance3D.new()
	_dense_mmi.name = "SmokeClouds"
	_dense_mmi.multimesh = _dense_mm
	_dense_mmi.material_override = _dense_mat
	_dense_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_dense_mmi.visible = false
	add_child(_dense_mmi)

	# Translucent ground dust puffs
	var dust_sphere := SphereMesh.new()
	dust_sphere.radius = 1.0
	dust_sphere.height = 2.0
	dust_sphere.radial_segments = 8
	dust_sphere.rings = 4

	var dust_shader: Shader = load("res://shaders/smoke_dust.gdshader")
	var dust_mat := ShaderMaterial.new()
	dust_mat.shader = dust_shader
	dust_mat.set_shader_parameter("fog_color", Vector3(fog_color.r, fog_color.g, fog_color.b))
	dust_mat.set_shader_parameter("fog_range", Vector2(fog_start, fog_end))

	_dust_mm = MultiMesh.new()
	_dust_mm.transform_format = MultiMesh.TRANSFORM_3D
	_dust_mm.use_colors = true
	_dust_mm.use_custom_data = true
	_dust_mm.mesh = dust_sphere
	_dust_mm.instance_count = MAX_DUST
	_dust_mm.visible_instance_count = 0
	_dust_mm.custom_aabb = SimMath.HUGE_AABB

	_dust_mmi = MultiMeshInstance3D.new()
	_dust_mmi.name = "SmokeDust"
	_dust_mmi.multimesh = _dust_mm
	_dust_mmi.material_override = dust_mat
	_dust_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dust_mmi.visible = false
	add_child(_dust_mmi)


func clear() -> void:
	count = 0
	if _dense_mmi != null:
		_dense_mm.visible_instance_count = 0
		_dense_mmi.visible = false
	if _dust_mmi != null:
		_dust_mm.visible_instance_count = 0
		_dust_mmi.visible = false


static func puff_height(r: float) -> float:
	return r / (1.0 + r / SQUASH_RADIUS)


func emit(
	p_kind: int,
	x: float,
	y: float,
	z: float,
	p_vx: float,
	p_vy: float,
	p_vz: float,
	p_radius: float,
	p_growth: float,
	p_life: float,
	p_density: float,
	p_heat: float,
) -> void:
	var i := count
	if i >= MAX_PUFFS:
		i = randi() % MAX_PUFFS
	else:
		count += 1
	kind[i] = p_kind
	px[i] = x
	py[i] = y
	pz[i] = z
	vx[i] = p_vx
	vy[i] = p_vy
	vz[i] = p_vz
	age[i] = 0.0
	life[i] = p_life
	start_radius[i] = p_radius
	radius[i] = p_radius
	growth[i] = p_growth
	density[i] = p_density
	strength[i] = 0.0
	var r1 := randf()
	heat[i] = p_heat * (LOFT_MIN + LOFT_SPREAD * r1 * r1)
	vigor[i] = minf(VIGOR_MAX, 0.35 + sqrt(p_vx * p_vx + p_vy * p_vy + p_vz * p_vz) * 0.12)
	floor_y[i] = DesertTerrain.ground_height(x, z)
	seed_arr[i] = randf()


func update_smoke(
	dt: float,
	t: float,
	car_x: float,
	car_z: float,
	car_vx: float,
	car_vz: float,
	car_fx: float,
	car_fz: float,
	fan_power: float,
	fan_range: float,
) -> void:
	_frame += 1
	var prevailing_angle := t * 0.05
	var prevailing_x := cos(prevailing_angle) * 1.1
	var prevailing_z := sin(prevailing_angle) * 1.1
	_drift.x += prevailing_x * dt
	_drift.y += NOISE_RISE * dt
	_drift.z -= prevailing_z * dt

	var heat_keep := exp(-dt / HEAT_FADE_SECONDS)
	var vigor_keep := exp(-dt / VIGOR_FADE_SECONDS)

	var car_speed := sqrt(car_vx * car_vx + car_vz * car_vz)
	var moving := car_speed > 0.5
	var travel_x := car_vx / car_speed if moving else car_fx
	var travel_z := car_vz / car_speed if moving else car_fz
	var wake_gate := clampf(car_speed / 6.0, 0.0, 1.0)
	var wake_length := minf(12.0, 2.5 + car_speed * 0.4)
	var wake_reach := wake_length + WAKE_LEAD
	var wake_reach_sq := wake_reach * wake_reach if wake_gate > 0.0 else 0.0
	var fan_reach_sq := fan_range * fan_range if fan_power > 0.0 else 0.0
	var near_sq := maxf(wake_reach_sq, fan_reach_sq)

	var wind_p1_x := t * 0.25
	var wind_p1_z := -t * 0.21
	var wind_p2_x := -t * 0.6
	var wind_p2_z := t * 0.5
	var billow_px := t * 0.9
	var billow_pz := -t * 0.7
	var eddy_px := -t * 1.9
	var eddy_pz := t * 1.6

	var dense_count := 0
	var dust_count := 0

	var i := count - 1
	while i >= 0:
		var a := age[i] + dt
		var lf := life[i]
		if a >= lf:
			_remove_at(i)
			i -= 1
			continue
		age[i] = a
		var x := px[i]
		var z := pz[i]
		var fl := floor_y[i]
		var h := py[i] - fl
		var rad := minf(MAX_RADIUS, start_radius[i] + growth[i] * sqrt(a))
		var vig := vigor[i] * vigor_keep
		var warmth := heat[i] * heat_keep
		heat[i] = warmth

		var a1 := int((x * 0.07 + wind_p1_x) * WAVE_SCALE)
		var b1 := int((z * 0.07 + wind_p1_z) * WAVE_SCALE)
		var a2 := int((x * 0.23 + wind_p2_x) * WAVE_SCALE)
		var b2 := int((z * 0.23 + wind_p2_z) * WAVE_SCALE)
		var flow_x := prevailing_x - _wave[a1 & WAVE_MASK] * _wave[b1 & WAVE_MASK] - 0.8 * _wave[a2 & WAVE_MASK] * _wave[b2 & WAVE_MASK]
		var flow_z := prevailing_z - _wave[(a1 + WAVE_QUARTER) & WAVE_MASK] * _wave[(b1 + WAVE_QUARTER) & WAVE_MASK] - 0.8 * _wave[(a2 + WAVE_QUARTER) & WAVE_MASK] * _wave[(b2 + WAVE_QUARTER) & WAVE_MASK]

		var a3 := int((x * BILLOW_WAVENUMBER + billow_px) * WAVE_SCALE)
		var b3 := int((z * BILLOW_WAVENUMBER + billow_pz) * WAVE_SCALE)
		var c3 := int(h * BILLOW_HEIGHT_WAVENUMBER * WAVE_SCALE)
		var sin_a := _wave[a3 & WAVE_MASK]
		var cos_a := _wave[(a3 + WAVE_QUARTER) & WAVE_MASK]
		var sin_b := _wave[b3 & WAVE_MASK]
		var cos_b := _wave[(b3 + WAVE_QUARTER) & WAVE_MASK]
		var sin_c := _wave[c3 & WAVE_MASK]
		var cos_c := _wave[(c3 + WAVE_QUARTER) & WAVE_MASK]
		var billow := BILLOW_CALM + BILLOW_GAIN * vig
		flow_x += billow * (BILLOW_ROLL * cos_a * cos_c - sin_a * sin_b)
		flow_z += billow * (BILLOW_ROLL * sin_b * cos_c - cos_a * cos_b)
		var flow_y := COOL_RISE_SPEED + HOT_RISE_SPEED * warmth + billow * (sin_a - cos_b) * sin_c

		var a4 := int((x * EDDY_WAVENUMBER + h * EDDY_SHEAR + eddy_px) * WAVE_SCALE)
		var b4 := int((z * EDDY_WAVENUMBER + eddy_pz) * WAVE_SCALE)
		var eddy := (EDDY_CALM + EDDY_GAIN * vig) / (1.0 + 0.35 * rad)
		flow_x -= eddy * _wave[a4 & WAVE_MASK] * _wave[b4 & WAVE_MASK]
		flow_z -= eddy * _wave[(a4 + WAVE_QUARTER) & WAVE_MASK] * _wave[(b4 + WAVE_QUARTER) & WAVE_MASK]

		var pvx := vx[i]
		var pvy := vy[i]
		var pvz := vz[i]
		var slip_x := flow_x - pvx
		var slip_y := flow_y - pvy
		var slip_z := flow_z - pvz
		var drag_step := (AIR_DRAG + JET_DRAG * sqrt(slip_x * slip_x + slip_y * slip_y + slip_z * slip_z)) * dt
		var follow := drag_step / (1.0 + drag_step)
		pvx += slip_x * follow
		pvy += slip_y * follow
		pvz += slip_z * follow

		var dx := x - car_x
		var dz := z - car_z
		var dist_sq := dx * dx + dz * dz
		if dist_sq < near_sq:
			if dist_sq < wake_reach_sq:
				var behind := -(dx * travel_x + dz * travel_z)
				var across := dx * travel_z - dz * travel_x
				var half_w := WAKE_HALF_WIDTH + (behind * WAKE_FLARE if behind > 0.0 else 0.0)
				var offset := across / half_w
				var core := 1.0 - offset * offset
				var taper := (1.0 + behind / WAKE_LEAD) if behind < 0.0 else (1.0 - behind / wake_length)
				if core > 0.0 and taper > 0.0:
					var hold := wake_gate * core * taper
					var pull := minf(1.0, hold * WAKE_PULL * dt)
					var side_coef := 0.0
					if behind < 0.0:
						side_coef = BOW_PUSH * (1.0 if across >= 0.0 else -1.0)
					elif behind > 1.0:
						side_coef = -WAKE_INFLOW * offset
					var sideways := side_coef * car_speed * pull
					pvx += (car_vx * WAKE_CARRY - pvx) * pull + travel_z * sideways
					pvz += (car_vz * WAKE_CARRY - pvz) * pull - travel_x * sideways
					pvy += car_speed * WAKE_UPWASH * pull
					vig = minf(VIGOR_MAX, vig + hold * WAKE_CHURN * dt)
			if dist_sq < fan_reach_sq and dist_sq > 0.01:
				var dist := sqrt(dist_sq)
				var behind := clampf(0.3 - (dx * car_fx + dz * car_fz) / dist, 0.0, 1.0)
				var push := fan_power * (1.0 - dist / fan_range) * (0.4 + 0.6 * behind) * dt
				pvx += (dx / dist) * push
				pvz += (dz / dist) * push

		x += pvx * dt
		z += pvz * dt
		if ((i + _frame) & FLOOR_REFRESH_MASK) == 0:
			fl = DesertTerrain.ground_height(x, z)
			floor_y[i] = fl
		var y := py[i] + pvy * dt
		var ceiling := fl + CEILING_HEIGHT
		if y > ceiling:
			pvy -= (y - ceiling) * 3.0 * dt
		var ph := puff_height(rad)
		var rest := fl + ph * GROUND_HUG
		if y < rest:
			y = rest
			if pvy < 0.0:
				pvy = 0.0

		var life_frac := a / lf
		var fade_in := clampf(a / 0.12, 0.0, 1.0)
		var f_t := clampf((life_frac - 0.5) / 0.5, 0.0, 1.0)
		var fade_out := 1.0 - f_t * f_t * (3.0 - 2.0 * f_t)
		var str_val := density[i] * pow(start_radius[i] / rad, DILUTION_EXPONENT) * fade_in * fade_out

		strength[i] = str_val
		radius[i] = rad
		px[i] = x
		py[i] = y
		pz[i] = z
		vx[i] = pvx
		vy[i] = pvy
		vz[i] = pvz
		vigor[i] = vig

		# Push visual instance to dense cel-shaded clouds or translucent dust
		var k := kind[i]
		if k == PUFF_DUST:
			if dust_count < MAX_DUST and str_val > 0.02:
				var rx := rad * 0.85
				var ry := ph * 0.65
				var xform := Transform3D(Basis.from_scale(Vector3(rx, ry, rx)), Vector3(x, y, -z))
				_dust_mm.set_instance_transform(dust_count, xform)
				_dust_mm.set_instance_color(dust_count, LOOK_COLORS[k])
				_dust_mm.set_instance_custom_data(dust_count, Color(minf(0.42, str_val * 0.9), 0.0, 0.0, 1.0))
				dust_count += 1
		else:
			if dense_count < MAX_DENSE and str_val > 0.015:
				# Iso-surface style radius shrink on fade-in and fade-out
				var vis := clampf(str_val * 2.4, 0.0, 1.0)
				var s_vis := sqrt(vis)
				var rx := rad * 0.92 * s_vis
				var ry := ph * 0.96 * s_vis
				var yaw := seed_arr[i] * TAU
				var c_y := cos(yaw)
				var s_y := sin(yaw)
				var b := Basis(Vector3(c_y * rx, 0.0, s_y * rx), Vector3(0.0, ry, 0.0), Vector3(-s_y * rx, 0.0, c_y * rx))
				_dense_mm.set_instance_transform(dense_count, Transform3D(b, Vector3(x, y, -z)))
				_dense_mm.set_instance_color(dense_count, LOOK_COLORS[k])
				var glow_v: float = LOOK_GLOWS[k] * (1.0 - life_frac)
				_dense_mm.set_instance_custom_data(dense_count, Color(glow_v, life_frac, seed_arr[i], 1.0))
				dense_count += 1
		i -= 1

	_rebuild_grid(car_x, car_z)

	_dense_mat.set_shader_parameter("drift", _drift)
	_dense_mm.visible_instance_count = dense_count
	_dense_mmi.visible = dense_count > 0
	_dust_mm.visible_instance_count = dust_count
	_dust_mmi.visible = dust_count > 0


func sample(x: float, z: float, out: SmokeSample, stir_vx: float, stir_vz: float, stir_gain: float) -> SmokeSample:
	out.total = 0.0
	out.by_kind[0] = 0.0
	out.by_kind[1] = 0.0
	out.by_kind[2] = 0.0
	out.by_kind[3] = 0.0
	var cx := int(floor(x / GRID_CELL)) - _grid_origin_x
	var cz := int(floor(z / GRID_CELL)) - _grid_origin_z
	var min_x := maxi(0, cx - SAMPLE_REACH_CELLS)
	var max_x := mini(GRID_SPAN - 1, cx + SAMPLE_REACH_CELLS)
	var min_z := maxi(0, cz - SAMPLE_REACH_CELLS)
	var max_z := mini(GRID_SPAN - 1, cz + SAMPLE_REACH_CELLS)
	for gz in range(min_z, max_z + 1):
		var row := gz * GRID_SPAN
		for gx in range(min_x, max_x + 1):
			var idx := _grid_head[row + gx]
			while idx >= 0:
				var dx := px[idx] - x
				var dz := pz[idx] - z
				var r := radius[idx]
				var dist_sq := dx * dx + dz * dz
				if dist_sq < r * r:
					var contribution := strength[idx] * (1.0 - dist_sq / (r * r))
					out.total += contribution
					out.by_kind[kind[idx]] += contribution
					if stir_gain > 0.0:
						var dvx := stir_vx - vx[idx]
						var dvz := stir_vz - vz[idx]
						var churn := sqrt(dvx * dvx + dvz * dvz) * stir_gain
						vx[idx] += dvx * stir_gain
						vz[idx] += dvz * stir_gain
						vigor[idx] = minf(VIGOR_MAX, vigor[idx] + churn * 0.12)
				idx = _grid_next[idx]
	return out


func sample_density(x: float, z: float) -> float:
	var total := 0.0
	var cx := int(floor(x / GRID_CELL)) - _grid_origin_x
	var cz := int(floor(z / GRID_CELL)) - _grid_origin_z
	var min_x := maxi(0, cx - SAMPLE_REACH_CELLS)
	var max_x := mini(GRID_SPAN - 1, cx + SAMPLE_REACH_CELLS)
	var min_z := maxi(0, cz - SAMPLE_REACH_CELLS)
	var max_z := mini(GRID_SPAN - 1, cz + SAMPLE_REACH_CELLS)
	for gz in range(min_z, max_z + 1):
		var row := gz * GRID_SPAN
		for gx in range(min_x, max_x + 1):
			var idx := _grid_head[row + gx]
			while idx >= 0:
				var dx := px[idx] - x
				var dz := pz[idx] - z
				var r := radius[idx]
				var dist_sq := dx * dx + dz * dz
				if dist_sq < r * r:
					total += strength[idx] * (1.0 - dist_sq / (r * r))
				idx = _grid_next[idx]
	return total


func obscuration_along_ray(x0: float, z0: float, x1: float, z1: float) -> float:
	var dx := x1 - x0
	var dz := z1 - z0
	var dist := sqrt(dx * dx + dz * dz)
	if dist < 0.01:
		return sample_density(x0, z0)
	var steps := clampi(int(ceil(dist / 2.5)), 2, 12)
	var peak := 0.0
	var accum := 0.0
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var d := sample_density(x0 + dx * t, z0 + dz * t)
		if d > peak:
			peak = d
		accum += d
	return maxf(peak, accum / float(steps + 1) * 1.6)


func shockwave(x: float, z: float, reach: float, spd: float) -> void:
	var reach_sq := reach * reach
	for i in count:
		var dx := px[i] - x
		var dz := pz[i] - z
		var dist_sq := dx * dx + dz * dz
		if dist_sq > reach_sq or dist_sq < 0.01:
			continue
		var dist := sqrt(dist_sq)
		var kick := spd * (1.0 - dist / reach)
		vx[i] += (dx / dist) * kick
		vz[i] += (dz / dist) * kick
		vy[i] += kick * 0.25
		vigor[i] = VIGOR_MAX


func _remove_at(i: int) -> void:
	count -= 1
	var last := count
	if i == last:
		return
	px[i] = px[last]
	py[i] = py[last]
	pz[i] = pz[last]
	vx[i] = vx[last]
	vy[i] = vy[last]
	vz[i] = vz[last]
	age[i] = age[last]
	life[i] = life[last]
	start_radius[i] = start_radius[last]
	growth[i] = growth[last]
	radius[i] = radius[last]
	density[i] = density[last]
	strength[i] = strength[last]
	heat[i] = heat[last]
	vigor[i] = vigor[last]
	floor_y[i] = floor_y[last]
	seed_arr[i] = seed_arr[last]
	kind[i] = kind[last]


func _rebuild_grid(center_x: float, center_z: float) -> void:
	_grid_head.fill(-1)
	_grid_origin_x = int(floor(center_x / GRID_CELL)) - GRID_HALF
	_grid_origin_z = int(floor(center_z / GRID_CELL)) - GRID_HALF
	for i in count:
		if kind[i] >= DAMAGING_KINDS:
			continue
		var gx := int(floor(px[i] / GRID_CELL)) - _grid_origin_x
		var gz := int(floor(pz[i] / GRID_CELL)) - _grid_origin_z
		if gx < 0 or gz < 0 or gx >= GRID_SPAN or gz >= GRID_SPAN:
			continue
		var cell := gz * GRID_SPAN + gx
		_grid_next[i] = _grid_head[cell]
		_grid_head[cell] = i

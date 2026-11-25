class_name SkidTracks
extends MeshInstance3D

# Ring-buffer tyre tracks with GPU time-based smooth fading.
# Supports both fixed-index wheels (player car) and stateless segments (enemies).

const DEFAULT_MAX_QUADS := 2400
const HALF_WIDTH := 0.16
const DEFAULT_LIFT := 0.065
const DEFAULT_MIN_STEP := 0.35
const MAX_STEP := 6.0

var min_step := DEFAULT_MIN_STEP

var _max_quads := DEFAULT_MAX_QUADS
var _lift := DEFAULT_LIFT
var _verts := PackedVector3Array()
var _uvs := PackedVector2Array()
var _heads: Array[Vector2] = []
var _head_times: Array[float] = []
var _head_intensities: Array[float] = []
var _active: Array[bool] = []
var _cursor := 0
var _dirty := false
var _time := 0.0
var _array_mesh := ArrayMesh.new()
var _mat: ShaderMaterial


func setup(
	wheel_count: int,
	max_quads: int = DEFAULT_MAX_QUADS,
	color: Color = Palette.SKID_MARK,
	fade_start: float = 10.0,
	fade_end: float = 16.0,
	lift: float = DEFAULT_LIFT,
	step_min: float = DEFAULT_MIN_STEP,
	priority: int = 1,
) -> void:
	_max_quads = max_quads
	_lift = lift
	min_step = step_min

	_verts.resize(_max_quads * 6)
	_verts.fill(Vector3.ZERO)
	_uvs.resize(_max_quads * 6)
	_uvs.fill(Vector2.ZERO)

	_heads.resize(wheel_count)
	_head_times.resize(wheel_count)
	_head_intensities.resize(wheel_count)
	_active.resize(wheel_count)
	for i in wheel_count:
		_heads[i] = Vector2.ZERO
		_head_times[i] = 0.0
		_head_intensities[i] = 1.0
		_active[i] = false

	mesh = _array_mesh
	extra_cull_margin = 16384.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var shader: Shader = load("res://shaders/skid_tracks.gdshader")
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.render_priority = priority
	_mat.set_shader_parameter("mark_color", color)
	_mat.set_shader_parameter("current_time", _time)
	_mat.set_shader_parameter("fade_start", fade_start)
	_mat.set_shader_parameter("fade_end", fade_end)
	material_override = _mat


func set_time(t: float) -> void:
	_time = t
	if _mat != null:
		_mat.set_shader_parameter("current_time", t)


func clear_tracks() -> void:
	_verts.fill(Vector3.ZERO)
	_uvs.fill(Vector2.ZERO)
	for i in _active.size():
		_active[i] = false
	_cursor = 0
	_dirty = true
	flush()


func mark(wheel: int, sim_x: float, sim_z: float, sliding: bool, intensity: float = 1.0) -> void:
	if not sliding:
		_active[wheel] = false
		return
	if not _active[wheel]:
		_heads[wheel] = Vector2(sim_x, sim_z)
		_head_times[wheel] = _time
		_head_intensities[wheel] = intensity
		_active[wheel] = true
		return

	var prev := _heads[wheel]
	var dx := sim_x - prev.x
	var dz := sim_z - prev.y
	var length := sqrt(dx * dx + dz * dz)
	if length < min_step:
		return

	if length < MAX_STEP:
		_write_quad(prev.x, prev.y, sim_x, sim_z, dx, dz, length, HALF_WIDTH, _head_times[wheel], _time, _head_intensities[wheel], intensity)

	_heads[wheel] = Vector2(sim_x, sim_z)
	_head_times[wheel] = _time
	_head_intensities[wheel] = intensity


func add_segment(
	x0: float,
	z0: float,
	x1: float,
	z1: float,
	half_width: float,
	t0: float,
	t1: float,
	i0: float = 1.0,
	i1: float = 1.0,
) -> void:
	var dx := x1 - x0
	var dz := z1 - z0
	var length := sqrt(dx * dx + dz * dz)
	if length < 0.001 or length >= MAX_STEP:
		return
	_write_quad(x0, z0, x1, z1, dx, dz, length, half_width, t0, t1, i0, i1)


func _write_quad(
	x0: float,
	z0: float,
	x1: float,
	z1: float,
	dx: float,
	dz: float,
	length: float,
	half_width: float,
	t0: float,
	t1: float,
	i0: float,
	i1: float,
) -> void:
	var sx := (dz / length) * half_width
	var sz := (-dx / length) * half_width
	var v0 := _ground_point(x0 - sx, z0 - sz)
	var v1 := _ground_point(x0 + sx, z0 + sz)
	var v2 := _ground_point(x1 - sx, z1 - sz)
	var v3 := _ground_point(x1 + sx, z1 + sz)

	var uv_start := Vector2(t0, i0)
	var uv_end := Vector2(t1, i1)

	var base := _cursor * 6
	_verts[base] = v0
	_verts[base + 1] = v2
	_verts[base + 2] = v1
	_verts[base + 3] = v1
	_verts[base + 4] = v2
	_verts[base + 5] = v3

	_uvs[base] = uv_start
	_uvs[base + 1] = uv_end
	_uvs[base + 2] = uv_start
	_uvs[base + 3] = uv_start
	_uvs[base + 4] = uv_end
	_uvs[base + 5] = uv_end

	_cursor = (_cursor + 1) % _max_quads
	_dirty = true


func flush() -> void:
	if not _dirty:
		return
	_dirty = false
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	_array_mesh.clear_surfaces()
	_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _ground_point(sim_x: float, sim_z: float) -> Vector3:
	return Vector3(sim_x, DesertTerrain.ground_height(sim_x, sim_z) + _lift, -sim_z)

class_name SkidTracks
extends MeshInstance3D

# Ring-buffer tyre tracks with GPU time-based smooth fading.
# Supports both fixed-index wheels (player car) and stateless segments (enemies).

const DEFAULT_MAX_QUADS := 2400
const HALF_WIDTH := 0.16
const DEFAULT_LIFT := 0.065
const DEFAULT_MIN_STEP := 0.35
const MAX_STEP := 6.0



class WindowMax:
	extends RefCounted
	# Largest of the most recent `window` values pushed (a monotonic queue), so
	# the bounds of a ring buffer can be followed without rescanning it.
	var _values := PackedFloat64Array()
	var _stamps := PackedInt64Array()
	var _head := 0

	func clear() -> void:
		_values.clear()
		_stamps.clear()
		_head = 0

	func push(stamp: int, value: float, window: int) -> void:
		var n := _values.size()
		while n > _head and _values[n - 1] <= value:
			n -= 1
		_values.resize(n)
		_stamps.resize(n)
		_values.append(value)
		_stamps.append(stamp)
		while _stamps[_head] <= stamp - window:
			_head += 1
		if _head >= 512:
			_values = _values.slice(_head)
			_stamps = _stamps.slice(_head)
			_head = 0

	func top() -> float:
		return _values[_head]


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
# Quads written since the last flush: a run of _dirty_count starting at
# _dirty_from, wrapping around the ring buffer.
var _dirty_from := 0
var _dirty_count := 0
# True when the GPU buffers use the plain layout flush() patches in place
# (12 bytes of position, 8 bytes of UV per vertex).
var _can_patch := false
# Bounds of the quads currently in the ring: -min x/y/z, then max x/y/z.
# Patching the buffers no longer lets the engine recompute the mesh bounds,
# and those bounds decide how the marks sort against other translucent things.
var _bounds: Array[WindowMax] = []
var _written := 0
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

	for _i in 6:
		_bounds.append(WindowMax.new())
	_build_surface()
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
	_written = 0
	for bound in _bounds:
		bound.clear()
	_dirty_from = 0
	_dirty_count = _max_quads
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

	_written += 1
	_bounds[0].push(_written, -minf(minf(v0.x, v1.x), minf(v2.x, v3.x)), _max_quads)
	_bounds[1].push(_written, -minf(minf(v0.y, v1.y), minf(v2.y, v3.y)), _max_quads)
	_bounds[2].push(_written, -minf(minf(v0.z, v1.z), minf(v2.z, v3.z)), _max_quads)
	_bounds[3].push(_written, maxf(maxf(v0.x, v1.x), maxf(v2.x, v3.x)), _max_quads)
	_bounds[4].push(_written, maxf(maxf(v0.y, v1.y), maxf(v2.y, v3.y)), _max_quads)
	_bounds[5].push(_written, maxf(maxf(v0.z, v1.z), maxf(v2.z, v3.z)), _max_quads)

	if _dirty_count == 0:
		_dirty_from = _cursor
	_dirty_count += 1
	_cursor = (_cursor + 1) % _max_quads


func flush() -> void:
	if _dirty_count == 0:
		return
	var count := mini(_dirty_count, _max_quads)
	var from := _dirty_from if count < _max_quads else 0
	_dirty_count = 0
	if not _can_patch:
		_build_surface()
		return
	# Upload only the quads laid since the last flush instead of rebuilding the
	# whole mesh (tens of thousands of vertices) every frame a wheel is sliding.
	var first := mini(count, _max_quads - from)
	_upload_quads(from, first)
	if count > first:
		_upload_quads(0, count - first)
	_update_bounds()


func _upload_quads(from: int, count: int) -> void:
	var begin := from * 6
	var end := begin + count * 6
	_array_mesh.surface_update_vertex_region(0, begin * 12, _verts.slice(begin, end).to_byte_array())
	_array_mesh.surface_update_attribute_region(0, begin * 8, _uvs.slice(begin, end).to_byte_array())


func _update_bounds() -> void:
	# The box the engine would compute over every vertex in the buffer. Slots
	# never written still sit at the origin until the ring has filled once.
	var low := Vector3.ZERO
	var high := Vector3.ZERO
	if _written > 0:
		low = Vector3(-_bounds[0].top(), -_bounds[1].top(), -_bounds[2].top())
		high = Vector3(_bounds[3].top(), _bounds[4].top(), _bounds[5].top())
		if _written < _max_quads:
			low = low.min(Vector3.ZERO)
			high = high.max(Vector3.ZERO)
	custom_aabb = AABB(low, high - low)


func _build_surface() -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	_array_mesh.clear_surfaces()
	_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	var format := _array_mesh.surface_get_format(0)
	var vertex_count := _verts.size()
	_can_patch = (
		RenderingServer.mesh_surface_get_format_vertex_stride(format, vertex_count) == 12
		and RenderingServer.mesh_surface_get_format_attribute_stride(format, vertex_count) == 8
		and RenderingServer.mesh_surface_get_format_offset(format, vertex_count, Mesh.ARRAY_VERTEX) == 0
		and RenderingServer.mesh_surface_get_format_offset(format, vertex_count, Mesh.ARRAY_TEX_UV) == 0
	)


func _ground_point(sim_x: float, sim_z: float) -> Vector3:
	return Vector3(sim_x, DesertTerrain.ground_height(sim_x, sim_z) + _lift, -sim_z)

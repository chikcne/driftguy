class_name SkidTracks
extends MeshInstance3D

# Ring-buffer tyre tracks matching src/effects.ts SkidTracks.

const MAX_QUADS := 2400
const HALF_WIDTH := 0.16
const LIFT := 0.06
const MIN_STEP := 0.35
const MAX_STEP := 6.0

var _verts := PackedVector3Array()
var _heads: Array[Vector2] = []
var _active: Array[bool] = []
var _cursor := 0
var _dirty := false
var _array_mesh := ArrayMesh.new()


func setup(wheel_count: int) -> void:
	_verts.resize(MAX_QUADS * 6)
	_verts.fill(Vector3.ZERO)
	_heads.resize(wheel_count)
	_active.resize(wheel_count)
	for i in wheel_count:
		_heads[i] = Vector2.ZERO
		_active[i] = false

	mesh = _array_mesh
	extra_cull_margin = 16384.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Palette.SKID_MARK
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	material_override = mat


func clear_tracks() -> void:
	_verts.fill(Vector3.ZERO)
	for i in _active.size():
		_active[i] = false
	_cursor = 0
	_dirty = true
	flush()


func mark(wheel: int, sim_x: float, sim_z: float, sliding: bool) -> void:
	if not sliding:
		_active[wheel] = false
		return
	if not _active[wheel]:
		_heads[wheel] = Vector2(sim_x, sim_z)
		_active[wheel] = true
		return

	var prev := _heads[wheel]
	var dx := sim_x - prev.x
	var dz := sim_z - prev.y
	var length := sqrt(dx * dx + dz * dz)
	if length < MIN_STEP:
		return

	if length < MAX_STEP:
		var sx := (dz / length) * HALF_WIDTH
		var sz := (-dx / length) * HALF_WIDTH
		var v0 := _ground_point(prev.x - sx, prev.y - sz)
		var v1 := _ground_point(prev.x + sx, prev.y + sz)
		var v2 := _ground_point(sim_x - sx, sim_z - sz)
		var v3 := _ground_point(sim_x + sx, sim_z + sz)

		var base := _cursor * 6
		_verts[base] = v0
		_verts[base + 1] = v2
		_verts[base + 2] = v1
		_verts[base + 3] = v1
		_verts[base + 4] = v2
		_verts[base + 5] = v3

		_cursor = (_cursor + 1) % MAX_QUADS
		_dirty = true

	_heads[wheel] = Vector2(sim_x, sim_z)


func flush() -> void:
	if not _dirty:
		return
	_dirty = false
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	_array_mesh.clear_surfaces()
	_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


static func _ground_point(sim_x: float, sim_z: float) -> Vector3:
	return Vector3(sim_x, DesertTerrain.ground_height(sim_x, sim_z) + LIFT, -sim_z)

class_name ModelKit
extends RefCounted

# Direct port of src/kit.ts ModelKit.
# Builds flat-shaded vertex-colored ArrayMeshes from boxes, cylinders, and
# jittered icosphere blobs. All inputs are in BabylonJS simulation coordinates
# (+X right, +Y up, +Z forward) and automatically converted to Godot (-Z forward).

const JITTER_QUANTUM := 1000.0

var _st: SurfaceTool
var _has_parts := false


func _init() -> void:
	_st = SurfaceTool.new()
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)


func box(size: Vector3, sim_pos: Vector3, color: Color, sim_rot := Vector3.ZERO) -> ModelKit:
	var mesh := BoxMesh.new()
	mesh.size = size
	_append_primitive(mesh, sim_pos, color, sim_rot, Vector3.ONE)
	return self


func cylinder(
	top_diam: float,
	bottom_diam: float,
	height: float,
	sides: int,
	sim_pos: Vector3,
	color: Color,
	sim_rot := Vector3.ZERO,
) -> ModelKit:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_diam * 0.5
	mesh.bottom_radius = bottom_diam * 0.5
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	_append_primitive(mesh, sim_pos, color, sim_rot, Vector3.ONE)
	return self


func blob(
	radius: float,
	sim_pos: Vector3,
	color: Color,
	scale := Vector3.ONE,
	roughness: float = 0.2,
	seed_val: int = 1,
	detail: int = 1,
	sim_rot := Vector3.ZERO,
) -> ModelKit:
	var verts := _build_icosphere_verts(radius, detail)
	# Apply deterministic vertex jitter matching src/kit.ts roughen()
	for i in verts.size():
		var v := verts[i]
		var qx := int(round(v.x * JITTER_QUANTUM))
		var qy := int(round(v.y * JITTER_QUANTUM))
		var qz := int(round(v.z * JITTER_QUANTUM))
		var key := ((qx * 73856093) ^ (qy * 19349663) ^ (qz * 83492791)) & 0xFFFFFFFF
		var factor := 1.0 + (SimMath.hash2(key, seed_val) * 2.0 - 1.0) * roughness
		verts[i] = v * factor

	var basis := SimMath.sim_basis_ypr(sim_rot.y, sim_rot.x, sim_rot.z, scale.x, scale.y, scale.z)
	var xform := Transform3D(basis, Vector3(sim_pos.x, sim_pos.y, -sim_pos.z))

	_st.set_color(color)
	var tri_count := verts.size() / 3
	for t in tri_count:
		var a := xform * verts[t * 3]
		var b := xform * verts[t * 3 + 1]
		var c := xform * verts[t * 3 + 2]
		var n := (c - a).cross(b - a).normalized()
		_st.set_normal(n)
		_st.add_vertex(a)
		_st.add_vertex(b)
		_st.add_vertex(c)

	_has_parts = true
	return self


func build() -> ArrayMesh:
	assert(_has_parts, "ModelKit.build() called with no parts")
	var mesh := _st.commit()
	_st = SurfaceTool.new()
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_has_parts = false
	return mesh


func _append_primitive(primitive: PrimitiveMesh, sim_pos: Vector3, color: Color, sim_rot: Vector3, scale: Vector3) -> void:
	var arrays := primitive.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	# Note: sim_rot is (pitch, yaw, roll) in BabylonJS order
	var basis := SimMath.sim_basis_ypr(sim_rot.y, sim_rot.x, sim_rot.z, scale.x, scale.y, scale.z)
	var xform := Transform3D(basis, Vector3(sim_pos.x, sim_pos.y, -sim_pos.z))

	_st.set_color(color)
	if indices.size() > 0:
		var tri_count := indices.size() / 3
		for t in tri_count:
			var a := xform * verts[indices[t * 3]]
			var b := xform * verts[indices[t * 3 + 1]]
			var c := xform * verts[indices[t * 3 + 2]]
			var n := (c - a).cross(b - a).normalized()
			_st.set_normal(n)
			_st.add_vertex(a)
			_st.add_vertex(b)
			_st.add_vertex(c)
	else:
		var tri_count := verts.size() / 3
		for t in tri_count:
			var a := xform * verts[t * 3]
			var b := xform * verts[t * 3 + 1]
			var c := xform * verts[t * 3 + 2]
			var n := (c - a).cross(b - a).normalized()
			_st.set_normal(n)
			_st.add_vertex(a)
			_st.add_vertex(b)
			_st.add_vertex(c)
	_has_parts = true


static func _build_icosphere_verts(radius: float, subdivisions: int) -> PackedVector3Array:
	var t := (1.0 + sqrt(5.0)) * 0.5
	var raw: Array[Vector3] = [
		Vector3(-1, t, 0).normalized(), Vector3(1, t, 0).normalized(),
		Vector3(-1, -t, 0).normalized(), Vector3(1, -t, 0).normalized(),
		Vector3(0, -1, t).normalized(), Vector3(0, 1, t).normalized(),
		Vector3(0, -1, -t).normalized(), Vector3(0, 1, -t).normalized(),
		Vector3(t, 0, -1).normalized(), Vector3(t, 0, 1).normalized(),
		Vector3(-t, 0, -1).normalized(), Vector3(-t, 0, 1).normalized(),
	]
	var tris: Array[Vector3i] = [
		Vector3i(0, 11, 5), Vector3i(0, 5, 1), Vector3i(0, 1, 7), Vector3i(0, 7, 10), Vector3i(0, 10, 11),
		Vector3i(1, 5, 9), Vector3i(5, 11, 4), Vector3i(11, 10, 2), Vector3i(10, 7, 6), Vector3i(7, 1, 8),
		Vector3i(3, 9, 4), Vector3i(3, 4, 2), Vector3i(3, 2, 6), Vector3i(3, 6, 8), Vector3i(3, 8, 9),
		Vector3i(4, 9, 5), Vector3i(2, 4, 11), Vector3i(6, 2, 10), Vector3i(8, 6, 7), Vector3i(9, 8, 1),
	]

	var subs := maxi(0, subdivisions)
	for _s in subs:
		var next_tris: Array[Vector3i] = []
		var cache: Dictionary = {}
		for tri in tris:
			var a := _ico_mid(raw, cache, tri.x, tri.y)
			var b := _ico_mid(raw, cache, tri.y, tri.z)
			var c := _ico_mid(raw, cache, tri.z, tri.x)
			next_tris.append(Vector3i(tri.x, a, c))
			next_tris.append(Vector3i(tri.y, b, a))
			next_tris.append(Vector3i(tri.z, c, b))
			next_tris.append(Vector3i(a, b, c))
		tris = next_tris

	var out := PackedVector3Array()
	out.resize(tris.size() * 3)
	for i in tris.size():
		var tri := tris[i]
		# Winding order for outward normals in Godot RH
		out[i * 3] = raw[tri.x] * radius
		out[i * 3 + 1] = raw[tri.z] * radius
		out[i * 3 + 2] = raw[tri.y] * radius
	return out


static func _ico_mid(verts: Array[Vector3], cache: Dictionary, i0: int, i1: int) -> int:
	var lo := mini(i0, i1)
	var hi := maxi(i0, i1)
	var key := (lo << 16) | hi
	if cache.has(key):
		return cache[key]
	var idx := verts.size()
	verts.append((verts[i0] + verts[i1]).normalized())
	cache[key] = idx
	return idx

class_name Effects
extends Node3D

# Direct port of src/effects.ts BlastPool and ShockRings.

const BLAST_POOL := 24
const BLAST_SECONDS := 0.38
const BLAST_HOT := Color(1.0, 0.9, 0.6)
const BLAST_COOL := Color(1.0, 0.35, 0.12)

const RING_POOL := 12
const RING_SECONDS := 0.5
const RING_LIFT := 0.7


class Blast:
	extends RefCounted
	var mesh: MeshInstance3D
	var mat: StandardMaterial3D
	var age: float = 0.0
	var radius: float = 1.0
	var active: bool = false


class Ring:
	extends RefCounted
	var mesh: MeshInstance3D
	var mat: StandardMaterial3D
	var age: float = 0.0
	var radius: float = 1.0
	var active: bool = false


var _blasts: Array[Blast] = []
var _blast_cursor := 0
var _rings: Array[Ring] = []
var _ring_cursor := 0


func setup() -> void:
	var blast_mesh := ModelKit.new().blob(1.0, Vector3.ZERO, Color.WHITE, Vector3.ONE, 0.0, 1, 2).build()
	for i in BLAST_POOL:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = Color(1.0, 0.62, 0.22, 0.0)
		mat.no_depth_test = false
		mat.render_priority = 20

		var mi := MeshInstance3D.new()
		mi.name = "Blast_%d" % i
		mi.mesh = blast_mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)

		var b := Blast.new()
		b.mesh = mi
		b.mat = mat
		_blasts.append(b)

	var torus := TorusMesh.new()
	torus.inner_radius = 0.91
	torus.outer_radius = 1.09
	torus.rings = 36
	torus.ring_segments = 12
	for i in RING_POOL:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = Color(1.0, 0.82, 0.5, 0.0)
		mat.render_priority = 19

		var mi := MeshInstance3D.new()
		mi.name = "ShockRing_%d" % i
		mi.mesh = torus
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)

		var r := Ring.new()
		r.mesh = mi
		r.mat = mat
		_rings.append(r)


func clear() -> void:
	for b in _blasts:
		b.active = false
		b.mesh.visible = false
	for r in _rings:
		r.active = false
		r.mesh.visible = false


func spawn_blast(sim_x: float, y: float, sim_z: float, radius: float) -> void:
	var b := _blasts[_blast_cursor]
	_blast_cursor = (_blast_cursor + 1) % BLAST_POOL
	b.age = 0.0
	b.radius = radius
	b.active = true
	b.mesh.position = Vector3(sim_x, y, -sim_z)
	b.mesh.scale = Vector3.ONE * (radius * 0.25)
	b.mesh.visible = true


func spawn_ring(sim_x: float, sim_z: float, radius: float) -> void:
	var r := _rings[_ring_cursor]
	_ring_cursor = (_ring_cursor + 1) % RING_POOL
	r.age = 0.0
	r.radius = radius
	r.active = true
	r.mesh.position = Vector3(sim_x, DesertTerrain.ground_height(sim_x, sim_z) + RING_LIFT, -sim_z)
	r.mesh.scale = Vector3(0.01, 0.01, 0.01)
	r.mesh.visible = true


func update_effects(dt: float) -> void:
	for b in _blasts:
		if not b.active:
			continue
		b.age += dt
		var t := b.age / BLAST_SECONDS
		if t >= 1.0:
			b.active = false
			b.mesh.visible = false
			continue
		var eased := 1.0 - (1.0 - t) * (1.0 - t)
		b.mesh.scale = Vector3.ONE * (b.radius * (0.25 + 0.75 * eased))
		var col := BLAST_HOT.lerp(BLAST_COOL, t)
		col.a = 0.85 * (1.0 - t)
		b.mat.albedo_color = col

	for r in _rings:
		if not r.active:
			continue
		r.age += dt
		var t := r.age / RING_SECONDS
		if t >= 1.0:
			r.active = false
			r.mesh.visible = false
			continue
		var eased := 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t)
		var reach := r.radius * (0.15 + 0.85 * eased)
		r.mesh.scale = Vector3(reach, 1.0 + 5.0 * (1.0 - t), reach)
		var col := BLAST_HOT.lerp(BLAST_COOL, t)
		col.a = 0.8 * (1.0 - t) * (1.0 - t)
		r.mat.albedo_color = col

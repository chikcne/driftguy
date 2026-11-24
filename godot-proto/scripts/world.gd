class_name World
extends Node3D

# Direct port of src/world.ts: infinite chunked desert terrain, deterministic
# outposts & wasteland props via MultiMeshInstance3D, breakable barrels,
# rooted swaying/uprootable cacti & trees, and loose rigid-body physics.

const VIEW_RADIUS_CHUNKS := 2
const COLLIDER_CELL := 16.0
const SPAWN_CLEARING := 28.0
const OUTPOST_CHANCE := 0.16
const PLACEMENT_ATTEMPTS := 5
const ROOTED_ID_STRIDE := 256
const LOOSE_CAPACITY := 64
const SWAY_CAPACITY := 8
const STACK_MIN_SCALE := 1.0
const STACK_MAX_SCALE := 1.2
const STACK_SPACING := 1.5

const SCATTER_TABLE := [
	["rockA", 5.0],
	["rockB", 4.0],
	["spire", 1.4],
	["wreck", 1.6],
	["tireStack", 1.0],
	["cactus", 3.0],
	["deadTree", 2.0],
	["ribs", 0.5],
	["pylon", 0.8],
	["wall", 0.7],
	["barrel", 0.8],
]
const SCATTER_TOTAL := 20.8


class Contact:
	extends RefCounted
	var hit: bool = false
	var nx: float = 0.0
	var nz: float = 0.0


class BreakableBarrel:
	extends RefCounted
	var id: String
	var list: Array # Array[Transform3D]
	var index: int
	var destroyed: bool = false

	func _init(p_id: String, p_list: Array, p_index: int, p_destroyed: bool) -> void:
		id = p_id
		list = p_list
		index = p_index
		destroyed = p_destroyed


class Collider:
	extends RefCounted
	var x: float
	var z: float
	var r: float
	var barrel: BreakableBarrel # nullable

	func _init(px: float, pz: float, pr: float, p_barrel: BreakableBarrel = null) -> void:
		x = px
		z = pz
		r = pr
		barrel = p_barrel


class Rooted:
	extends RefCounted
	var id: int
	var prop_name: String
	var x: float
	var y: float
	var z: float
	var r: float
	var yaw: float
	var scale: float
	var scale_y: float
	var solid: bool
	var alive: bool
	var list: Array # Array[Transform3D]
	var index: int
	var group: Array # Array[Rooted] or empty
	var chunk_key: Vector2i = Vector2i.ZERO
	var saved_xform: Variant = null # Transform3D when swaying
	var hold: float = 0.0
	var tear: float = 0.0
	var lean_x: float = 0.0
	var lean_z: float = 0.0
	var sway_x: float = 0.0
	var sway_z: float = 0.0


class ChunkData:
	extends RefCounted
	var cx: int
	var cz: int
	var ground: MeshInstance3D
	var placements: Dictionary = {} # String -> Array[Transform3D]
	var colliders: Array[Collider] = []
	var rooted: Array[Rooted] = []


var _props: Dictionary = {} # String -> Props.PropDef
var _prop_meshes: Dictionary = {} # String -> MultiMeshInstance3D
var _loose_batches: Dictionary = {} # String -> SimMath.InstanceBatch
var _chunks: Dictionary = {} # Vector2i -> ChunkData
var _collider_grid: Dictionary = {} # Vector2i -> Array[Collider]
var _rooted_grid: Dictionary = {} # Vector2i -> Array[Rooted]
var _uprooted: Dictionary = {} # int -> bool
var _broken_barrels: Dictionary = {} # String -> bool
var _loose := LooseSystem.new()
var _swaying: Array[Rooted] = []
var _strain := Roots.StrainResult.new()
var _material: StandardMaterial3D
var _center_cx := 999999
var _center_cz := 999999
var _resolve_callable: Callable


func setup(shared_material: StandardMaterial3D) -> void:
	_material = shared_material
	_props = Props.build_props()
	_resolve_callable = Callable(self, "_resolve_obstruction")

	for prop_name: String in _props.keys():
		var prop: Props.PropDef = _props[prop_name]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = prop.mesh
		mm.custom_aabb = SimMath.HUGE_AABB
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Prop_" + prop_name
		mmi.multimesh = mm
		mmi.material_override = _material
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if prop.casts_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visible = false
		add_child(mmi)
		_prop_meshes[prop_name] = mmi

		if prop.loose != null:
			_loose_batches[prop_name] = SimMath.InstanceBatch.new(
				self,
				prop.mesh,
				_material,
				LOOSE_CAPACITY,
				false,
				prop.casts_shadow,
				"Loose_" + prop_name,
			)


func reset_world() -> void:
	_loose.clear()
	_uprooted.clear()
	_broken_barrels.clear()
	_swaying.clear()
	for chunk: ChunkData in _chunks.values():
		_dispose_chunk(chunk)
	_chunks.clear()
	_collider_grid.clear()
	_rooted_grid.clear()
	_center_cx = 999999
	_center_cz = 999999
	_render_loose()


func _dispose_chunk(chunk: ChunkData) -> void:
	for r in chunk.rooted:
		r.group.clear()
	chunk.rooted.clear()
	chunk.colliders.clear()
	chunk.placements.clear()
	if is_instance_valid(chunk.ground):
		chunk.ground.queue_free()


func _exit_tree() -> void:
	for chunk: ChunkData in _chunks.values():
		for r in chunk.rooted:
			r.group.clear()
		chunk.rooted.clear()
	_chunks.clear()
	_swaying.clear()
	_collider_grid.clear()
	_rooted_grid.clear()


func step_world(dt: float, focus_x: float, focus_z: float) -> void:
	_loose.step(dt, focus_x, focus_z, _resolve_callable)
	for i in range(_swaying.size() - 1, -1, -1):
		var plant := _swaying[i]
		if not Roots.sway(plant, dt):
			_settle(plant)
	_render_loose()


func shove(mover: Variant, radius: float, mass: float, out: LooseSystem.ShoveResult) -> LooseSystem.ShoveResult:
	var min_x := int(floor((mover.x - radius) / COLLIDER_CELL))
	var max_x := int(floor((mover.x + radius) / COLLIDER_CELL))
	var min_z := int(floor((mover.z - radius) / COLLIDER_CELL))
	var max_z := int(floor((mover.z + radius) / COLLIDER_CELL))
	var torn := 0
	var grip := 0.0
	var grip_x := 0.0
	var grip_z := 0.0

	for gz in range(min_z, max_z + 1):
		for gx in range(min_x, max_x + 1):
			var key := Vector2i(gx, gz)
			if not _rooted_grid.has(key):
				continue
			var bucket: Array = _rooted_grid[key]
			for plant: Rooted in bucket:
				if not plant.alive:
					continue
				var reach := radius + plant.r
				var dx: float = plant.x - mover.x
				var dz: float = plant.z - mover.z
				if dx * dx + dz * dz >= reach * reach:
					continue
				if plant.hold > 0.0:
					var outcome := Roots.strain(plant, mover, radius, mass, _strain)
					grip += _strain.impulse
					grip_x += _strain.x * _strain.impulse
					grip_z += _strain.z * _strain.impulse
					if outcome != Roots.OUTCOME_TORN:
						if _strain.impulse > 0.0:
							_bend(plant)
						continue
					torn += 1
				_uproot(plant)

	_loose.shove(mover, radius, mass, out)
	out.torn = torn
	if grip > 0.0:
		var total := out.impulse + grip
		out.x = (out.x * out.impulse + grip_x) / total
		out.z = (out.z * out.impulse + grip_z) / total
		out.impulse = total
		out.hit = true
	return out


func update_around(sim_x: float, sim_z: float) -> void:
	var cx := int(floor(sim_x / DesertTerrain.CHUNK_SIZE))
	var cz := int(floor(sim_z / DesertTerrain.CHUNK_SIZE))
	if cx == _center_cx and cz == _center_cz:
		return
	_center_cx = cx
	_center_cz = cz

	var wanted: Dictionary = {}
	for dz in range(-VIEW_RADIUS_CHUNKS, VIEW_RADIUS_CHUNKS + 1):
		for dx in range(-VIEW_RADIUS_CHUNKS, VIEW_RADIUS_CHUNKS + 1):
			var key := Vector2i(cx + dx, cz + dz)
			wanted[key] = true
			if not _chunks.has(key):
				_chunks[key] = _create_chunk(cx + dx, cz + dz)

	var to_remove: Array[Vector2i] = []
	for key: Vector2i in _chunks.keys():
		if not wanted.has(key):
			to_remove.append(key)
	for key in to_remove:
		var chunk: ChunkData = _chunks[key]
		_dispose_chunk(chunk)
		_chunks.erase(key)

	for i in range(_swaying.size() - 1, -1, -1):
		var home_key := _swaying[i].chunk_key
		if not _chunks.has(home_key):
			_swaying.remove_at(i)

	_rebuild_all_instances()
	_rebuild_collider_grid()


func break_barrels(sim_x: float, sim_z: float, radius: float, on_break: Callable) -> bool:
	var hit := false
	var min_x := int(floor((sim_x - radius) / COLLIDER_CELL))
	var max_x := int(floor((sim_x + radius) / COLLIDER_CELL))
	var min_z := int(floor((sim_z - radius) / COLLIDER_CELL))
	var max_z := int(floor((sim_z + radius) / COLLIDER_CELL))
	for gz in range(min_z, max_z + 1):
		for gx in range(min_x, max_x + 1):
			var key := Vector2i(gx, gz)
			if not _collider_grid.has(key):
				continue
			var bucket: Array = _collider_grid[key]
			for col: Collider in bucket:
				var barrel := col.barrel
				if barrel == null or barrel.destroyed:
					continue
				var dx := sim_x - col.x
				var dz := sim_z - col.z
				var reach := radius + col.r
				if dx * dx + dz * dz > reach * reach:
					continue
				barrel.destroyed = true
				_broken_barrels[barrel.id] = true
				barrel.list[barrel.index] = Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0.0, -9999.0, 0.0))
				on_break.call(col.x, col.z)
				hit = true
	if hit:
		_rebuild_instances_of("barrel")
	return hit


func resolve(body: Variant, radius: float, contact: Contact) -> Contact:
	contact.hit = false
	var min_x := int(floor((body.x - radius) / COLLIDER_CELL))
	var max_x := int(floor((body.x + radius) / COLLIDER_CELL))
	var min_z := int(floor((body.z - radius) / COLLIDER_CELL))
	var max_z := int(floor((body.z + radius) / COLLIDER_CELL))
	for gz in range(min_z, max_z + 1):
		for gx in range(min_x, max_x + 1):
			var key := Vector2i(gx, gz)
			if not _collider_grid.has(key):
				continue
			var bucket: Array = _collider_grid[key]
			for col: Collider in bucket:
				if col.barrel != null and col.barrel.destroyed:
					continue
				var dx: float = body.x - col.x
				var dz: float = body.z - col.z
				var reach := radius + col.r
				var dist_sq := dx * dx + dz * dz
				if dist_sq >= reach * reach:
					continue
				var dist := sqrt(dist_sq)
				if dist < 0.001:
					dist = 0.001
				var nx := dx / dist
				var nz := dz / dist
				body.x = col.x + nx * reach
				body.z = col.z + nz * reach
				contact.hit = true
				contact.nx = nx
				contact.nz = nz
	return contact


func _resolve_obstruction(body: LooseSystem.LooseBody, radius: float, out: LooseSystem.Obstruction) -> void:
	var c := Contact.new()
	resolve(body, radius, c)
	out.hit = c.hit
	out.nx = c.nx
	out.nz = c.nz


func _pick_scatter(rng: SimMath.SeededRng) -> String:
	var roll := rng.next() * SCATTER_TOTAL
	for entry in SCATTER_TABLE:
		roll -= entry[1]
		if roll <= 0.0:
			return entry[0]
	return "rockA"


func _create_chunk(cx: int, cz: int) -> ChunkData:
	var chunk := ChunkData.new()
	chunk.cx = cx
	chunk.cz = cz
	chunk.ground = _create_ground(cx, cz)
	add_child(chunk.ground)

	var rng := SimMath.SeededRng.new(int(floor(SimMath.hash2(cx, cz) * 4294967296.0)))
	var origin_x := float(cx) * DesertTerrain.CHUNK_SIZE
	var origin_z := float(cz) * DesertTerrain.CHUNK_SIZE

	if rng.next() < OUTPOST_CHANCE:
		_place_outpost(chunk, origin_x + lerpf(18.0, 46.0, rng.next()), origin_z + lerpf(18.0, 46.0, rng.next()), rng)

	var scatter_count := 4 + int(floor(rng.next() * 5.0))
	for _i in scatter_count:
		var scatter_name := _pick_scatter(rng)
		for _attempt in PLACEMENT_ATTEMPTS:
			var px := origin_x + rng.next() * DesertTerrain.CHUNK_SIZE
			var pz := origin_z + rng.next() * DesertTerrain.CHUNK_SIZE
			var yaw := rng.next() * TAU
			var placed := false
			if scatter_name == "tireStack":
				placed = _place_stack(chunk, Props.TIRE_STACK, Props.TIRE_STACK_FOOTPRINT, px, pz, yaw, rng)
			else:
				placed = _place(chunk, scatter_name, px, pz, yaw, rng)
			if placed:
				break

	for _i in 16:
		_place(chunk, "pebble", origin_x + rng.next() * DesertTerrain.CHUNK_SIZE, origin_z + rng.next() * DesertTerrain.CHUNK_SIZE, rng.next() * TAU, rng)
	for _i in 9:
		_place(chunk, "shrub", origin_x + rng.next() * DesertTerrain.CHUNK_SIZE, origin_z + rng.next() * DesertTerrain.CHUNK_SIZE, rng.next() * TAU, rng)

	return chunk


func _place_outpost(chunk: ChunkData, x: float, z: float, rng: SimMath.SeededRng) -> void:
	var facing := rng.next() * TAU
	_place(chunk, "shack", x, z, facing, rng)
	_place(chunk, "tower", x + sin(facing + 2.2) * 9.0, z + cos(facing + 2.2) * 9.0, rng.next() * TAU, rng)
	_place(chunk, "wall", x + sin(facing + 0.2) * 13.0, z + cos(facing + 0.2) * 13.0, facing + 0.2 + PI * 0.5, rng)
	_place(chunk, "wall", x + sin(facing + 3.6) * 14.0, z + cos(facing + 3.6) * 14.0, facing + 3.6 + PI * 0.5, rng)
	_place(chunk, "wreck", x + sin(facing + 4.6) * 8.0, z + cos(facing + 4.6) * 8.0, rng.next() * TAU, rng)
	_place_stack(chunk, Props.TIRE_STACK, Props.TIRE_STACK_FOOTPRINT, x + sin(facing + 1.0) * 6.5, z + cos(facing + 1.0) * 6.5, rng.next() * TAU, rng)
	_place(chunk, "barrel", x + sin(facing + 5.4) * 5.2, z + cos(facing + 5.4) * 5.2, 0.0, rng)
	_place(chunk, "barrel", x + sin(facing + 5.65) * 6.1, z + cos(facing + 5.65) * 6.1, 0.0, rng)
	_place(chunk, "barrel", x + sin(facing + 1.5) * 10.5, z + cos(facing + 1.5) * 10.5, 0.0, rng)
	_place(chunk, "pylon", x + sin(facing + 5.0) * 11.5, z + cos(facing + 5.0) * 11.5, facing, rng)


func _fits(chunk: ChunkData, x: float, z: float, footprint: float) -> bool:
	if sqrt(x * x + z * z) < SPAWN_CLEARING:
		return false
	for other in chunk.colliders:
		var d := sqrt((other.x - x) * (other.x - x) + (other.z - z) * (other.z - z))
		if d < other.r + footprint + STACK_SPACING:
			return false
	for other in chunk.rooted:
		if other.solid:
			var d := sqrt((other.x - x) * (other.x - x) + (other.z - z) * (other.z - z))
			if d < other.r + footprint + STACK_SPACING:
				return false
	return true


func _place_stack(chunk: ChunkData, parts: Array, footprint: float, x: float, z: float, yaw: float, rng: SimMath.SeededRng) -> bool:
	var scale := lerpf(STACK_MIN_SCALE, STACK_MAX_SCALE, rng.next())
	if not _fits(chunk, x, z, footprint * scale):
		return false
	var s := sin(yaw)
	var c := cos(yaw)
	var base := DesertTerrain.ground_height(x, z)
	var group: Array = []
	for part in parts:
		var part_x: float = part["x"]
		var part_y: float = part["y"]
		var part_z: float = part["z"]
		var px := x + (part_x * c + part_z * s) * scale
		var pz := z + (-part_x * s + part_z * c) * scale
		var ground := base if part_y > 0.0 else DesertTerrain.ground_height(px, pz)
		_place(chunk, part["name"], px, pz, yaw + rng.next() * TAU, rng, true, scale, ground + part_y * scale, group)
	return true


func _place(
	chunk: ChunkData,
	prop_name: String,
	x: float,
	z: float,
	yaw: float,
	rng: SimMath.SeededRng,
	is_stack: bool = false,
	stack_scale: float = 1.0,
	stack_y: float = 0.0,
	stack_group: Array = [],
) -> bool:
	var prop: Props.PropDef = _props[prop_name]
	var scale := stack_scale if is_stack else lerpf(prop.min_scale, prop.max_scale, rng.next())
	if not is_stack and prop.colliders.size() > 0:
		var footprint := 0.0
		for c in prop.colliders:
			footprint = maxf(footprint, sqrt(c.x * c.x + c.z * c.z) + c.r)
		footprint *= scale
		if not _fits(chunk, x, z, footprint):
			return false

	var list: Array
	if chunk.placements.has(prop_name):
		list = chunk.placements[prop_name]
	else:
		list = []
		chunk.placements[prop_name] = list

	var slot_index := list.size()
	var barrel: BreakableBarrel = null
	if prop_name == "barrel":
		var barrel_id := "%d:%d:%d" % [chunk.cx, chunk.cz, slot_index]
		barrel = BreakableBarrel.new(barrel_id, list, slot_index, _broken_barrels.has(barrel_id))

	var s := sin(yaw)
	var c := cos(yaw)
	if prop.loose == null:
		for local in prop.colliders:
			chunk.colliders.append(Collider.new(
				x + (local.x * c + local.z * s) * scale,
				z + (-local.x * s + local.z * c) * scale,
				local.r * scale,
				barrel,
			))

	var squash := 1.0 if is_stack else lerpf(0.85, 1.15, rng.next())
	var y := (stack_y if is_stack else DesertTerrain.ground_height(x, z)) - prop.sink * scale

	if prop.loose != null:
		var chunk_key_num := (chunk.cx + 32768) * 65536 + (chunk.cz + 32768)
		var rid := chunk_key_num * ROOTED_ID_STRIDE + chunk.rooted.size()
		var alive := not _uprooted.has(rid)
		var rooted := Rooted.new()
		rooted.id = rid
		rooted.prop_name = prop_name
		rooted.x = x
		rooted.y = y
		rooted.z = z
		rooted.r = prop.loose.radius * scale
		rooted.yaw = yaw
		rooted.scale = scale
		rooted.scale_y = scale * squash
		rooted.solid = prop.colliders.size() > 0
		rooted.alive = alive
		rooted.list = list
		rooted.index = slot_index
		rooted.group = stack_group
		rooted.chunk_key = Vector2i(chunk.cx, chunk.cz)
		if not is_stack and prop.roots != null:
			rooted.hold = prop.roots.hold * scale * scale
			rooted.tear = prop.roots.tear * scale * scale
		chunk.rooted.append(rooted)
		if is_stack:
			stack_group.append(rooted)
		if not alive:
			return true

	var xform := SimMath.sim_transform(x, y, z, yaw, 0.0, 0.0, scale, scale * squash, scale)
	if barrel != null and barrel.destroyed:
		xform = Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0.0, -9999.0, 0.0))
	list.append(xform)
	return true


func _uproot(plant: Rooted) -> void:
	var members: Array = plant.group if plant.group.size() > 0 else [plant]
	var touched: Dictionary = {}
	for member: Rooted in members:
		var prop: Props.PropDef = _props[member.prop_name]
		if prop.loose == null or not member.alive:
			continue
		member.alive = false
		_uprooted[member.id] = true
		if member.saved_xform != null:
			member.saved_xform = null
			_swaying.erase(member)
		member.list[member.index] = Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0.0, -9999.0, 0.0))
		touched[member.prop_name] = true
		_loose.spawn(member.prop_name, prop.loose, member.x, member.y, member.z, member.yaw, member.scale, member.scale_y)
	for prop_name: String in touched.keys():
		_rebuild_instances_of(prop_name)


func _bend(plant: Rooted) -> void:
	if plant.saved_xform != null:
		return
	if _swaying.size() >= SWAY_CAPACITY:
		_settle(_swaying[0])
	plant.saved_xform = plant.list[plant.index]
	plant.list[plant.index] = Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0.0, -9999.0, 0.0))
	_swaying.append(plant)
	_rebuild_instances_of(plant.prop_name)


func _settle(plant: Rooted) -> void:
	_swaying.erase(plant)
	plant.lean_x = 0.0
	plant.lean_z = 0.0
	plant.sway_x = 0.0
	plant.sway_z = 0.0
	if plant.saved_xform == null:
		return
	plant.list[plant.index] = plant.saved_xform
	plant.saved_xform = null
	_rebuild_instances_of(plant.prop_name)


func _render_loose() -> void:
	for prop_name: String in _loose_batches.keys():
		var batch: SimMath.InstanceBatch = _loose_batches[prop_name]
		batch.begin()
		for body in _loose.bodies:
			if body.kind != prop_name:
				continue
			batch.push_transform(SimMath.sim_quat_transform(
				body.x,
				body.y,
				body.z,
				body.qx,
				body.qy,
				body.qz,
				body.qw,
				body.scale,
				body.scale_y,
				body.origin,
			))
		for plant in _swaying:
			if plant.prop_name != prop_name:
				continue
			batch.push_transform(Roots.lean_transform(plant, plant.y, plant.yaw, plant.scale, plant.scale_y))
		batch.commit()


func _rebuild_all_instances() -> void:
	for prop_name: String in _props.keys():
		_rebuild_instances_of(prop_name)


func _rebuild_instances_of(prop_name: String) -> void:
	var mmi: MultiMeshInstance3D = _prop_meshes[prop_name]
	var total := 0
	for chunk: ChunkData in _chunks.values():
		if chunk.placements.has(prop_name):
			total += (chunk.placements[prop_name] as Array).size()
	if total == 0:
		mmi.visible = false
		return
	var mm := mmi.multimesh
	if mm.instance_count < total:
		mm.instance_count = total
	var idx := 0
	for chunk: ChunkData in _chunks.values():
		if not chunk.placements.has(prop_name):
			continue
		var list: Array = chunk.placements[prop_name]
		for xform: Transform3D in list:
			mm.set_instance_transform(idx, xform)
			idx += 1
	mm.visible_instance_count = idx
	mmi.visible = idx > 0


func _rebuild_collider_grid() -> void:
	_collider_grid.clear()
	_rooted_grid.clear()
	for chunk: ChunkData in _chunks.values():
		for plant in chunk.rooted:
			if not plant.alive:
				continue
			var min_x := int(floor((plant.x - plant.r) / COLLIDER_CELL))
			var max_x := int(floor((plant.x + plant.r) / COLLIDER_CELL))
			var min_z := int(floor((plant.z - plant.r) / COLLIDER_CELL))
			var max_z := int(floor((plant.z + plant.r) / COLLIDER_CELL))
			for gz in range(min_z, max_z + 1):
				for gx in range(min_x, max_x + 1):
					var key := Vector2i(gx, gz)
					if not _rooted_grid.has(key):
						_rooted_grid[key] = []
					(_rooted_grid[key] as Array).append(plant)
		for col in chunk.colliders:
			var min_x := int(floor((col.x - col.r) / COLLIDER_CELL))
			var max_x := int(floor((col.x + col.r) / COLLIDER_CELL))
			var min_z := int(floor((col.z - col.r) / COLLIDER_CELL))
			var max_z := int(floor((col.z + col.r) / COLLIDER_CELL))
			for gz in range(min_z, max_z + 1):
				for gx in range(min_x, max_x + 1):
					var key := Vector2i(gx, gz)
					if not _collider_grid.has(key):
						_collider_grid[key] = []
					(_collider_grid[key] as Array).append(col)


static func _ground_color(ix: int, iz: int, variant: int, h: float) -> Color:
	var patch := 0.5 + 0.5 * sin(float(ix) * 0.19 + 1.7) * cos(float(iz) * 0.23 - 0.6)
	var grain := SimMath.hash2(ix * 2 + variant, iz)
	var t := clampf(0.55 - h * 0.09 + (grain - 0.5) * 0.3 + (patch - 0.5) * 0.35, 0.0, 1.0)
	var c := Palette.SAND_LIGHT.lerp(Palette.SAND_DARK, t)
	if patch > 0.9 and grain > 0.5:
		c = c.lerp(Palette.SAND_SHADOW, 0.5)
	return c


func _create_ground(cx: int, cz: int) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var base_ix := cx * DesertTerrain.CHUNK_CELLS
	var base_iz := cz * DesertTerrain.CHUNK_CELLS

	for local_z in DesertTerrain.CHUNK_CELLS:
		for local_x in DesertTerrain.CHUNK_CELLS:
			var ix := base_ix + local_x
			var iz := base_iz + local_z
			var x0 := float(ix) * DesertTerrain.CELL_SIZE
			var x1 := x0 + DesertTerrain.CELL_SIZE
			var z0 := float(iz) * DesertTerrain.CELL_SIZE
			var z1 := z0 + DesertTerrain.CELL_SIZE

			var h00 := DesertTerrain.vertex_height(ix, iz)
			var h10 := DesertTerrain.vertex_height(ix + 1, iz)
			var h01 := DesertTerrain.vertex_height(ix, iz + 1)
			var h11 := DesertTerrain.vertex_height(ix + 1, iz + 1)

			var p00 := Vector3(x0, h00, -z0)
			var p10 := Vector3(x1, h10, -z0)
			var p01 := Vector3(x0, h01, -z1)
			var p11 := Vector3(x1, h11, -z1)

			var c1 := _ground_color(ix, iz, 0, (h00 + h10 + h11) / 3.0)
			var n1 := (p10 - p00).cross(p11 - p00).normalized()
			if n1.y < 0.0:
				n1 = -n1
			st.set_color(c1)
			st.set_normal(n1)
			st.add_vertex(p00)
			st.add_vertex(p11)
			st.add_vertex(p10)

			var c2 := _ground_color(ix, iz, 1, (h00 + h11 + h01) / 3.0)
			var n2 := (p11 - p00).cross(p01 - p00).normalized()
			if n2.y < 0.0:
				n2 = -n2
			st.set_color(c2)
			st.set_normal(n2)
			st.add_vertex(p00)
			st.add_vertex(p01)
			st.add_vertex(p11)

	var ground := MeshInstance3D.new()
	ground.name = "Ground_%d_%d" % [cx, cz]
	ground.mesh = st.commit()
	ground.material_override = _material
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ground

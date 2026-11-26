class_name World
extends Node3D

# Direct port of src/world.ts: infinite chunked desert terrain, deterministic
# outposts & wasteland props via MultiMeshInstance3D, breakable barrels,
# rooted swaying/uprootable cacti & trees, and loose rigid-body physics.

const VIEW_RADIUS_CHUNKS := 2
const COLLIDER_CELL := 16.0
const SPAWN_CLEARING := 28.0
const OUTPOST_CHANCE := 0.08
const PLACEMENT_ATTEMPTS := 5
const ROOTED_ID_STRIDE := 256
const LOOSE_CAPACITY := 64
const SWAY_CAPACITY := 8
# Loaded chunks span 20 collider cells; two spare cells each side cover props
# whose radius pokes past a chunk edge.
const GRID_MARGIN := 2
const GRID_SPAN := (VIEW_RADIUS_CHUNKS * 2 + 1) * 4 + GRID_MARGIN * 2
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
	["pickup_cache", 0.8],
]
const SCATTER_TOTAL := 20.8


class Contact:
	extends RefCounted
	var hit: bool = false
	var nx: float = 0.0
	var nz: float = 0.0


class AvoidanceResult:
	extends RefCounted
	var heading: float = 0.0
	var speed_factor: float = 1.0
	var side_bias: float = 0.0
	var avoiding: bool = false


const AVOID_ANGLES := [
	0.0,
	0.22, -0.22,
	0.45, -0.45,
	0.72, -0.72,
	1.05, -1.05,
	1.45, -1.45,
	1.90, -1.90,
	2.35, -2.35,
]
const AVOID_MAX_OBS := 48


class Collider:
	extends RefCounted
	var x: float
	var z: float
	var r: float

	func _init(px: float, pz: float, pr: float) -> void:
		x = px
		z = pz
		r = pr


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
	var cache_count: int = 0


var on_spawn_cache: Callable

var _props: Dictionary = {} # String -> Props.PropDef
var _prop_meshes: Dictionary = {} # String -> MultiMeshInstance3D
var _loose_batches: Dictionary = {} # String -> SimMath.InstanceBatch
var _chunks: Dictionary = {} # Vector2i -> ChunkData

# Broadphase grid over the loaded chunks, rebuilt whenever the chunk set changes.
# Stored as flat cell-sorted arrays (cell c owns entries start[c] .. start[c + 1])
# so the per-enemy queries below read packed floats instead of hashing Vector2i
# keys and walking object buckets. Entries keep the order the old dictionary
# buckets had, so collision results are unchanged.
var _grid_ox := 0
var _grid_oz := 0
var _col_start := PackedInt32Array()
var _col_x := PackedFloat64Array()
var _col_z := PackedFloat64Array()
var _col_r := PackedFloat64Array()
var _root_start := PackedInt32Array()
var _root_x := PackedFloat64Array()
var _root_z := PackedFloat64Array()
var _root_r := PackedFloat64Array()
var _root_hold := PackedFloat64Array()
var _root_obj: Array[Rooted] = []
var _uprooted: Dictionary = {} # int -> bool
var _spawned_caches: Dictionary = {} # String -> bool
var _loose := LooseSystem.new()
var _swaying: Array[Rooted] = []
var _sway_drawn := 0 # swaying plants in the loose batches as last drawn
var _strain := Roots.StrainResult.new()
var _loose_contact := Contact.new()
var _ground_heights := PackedFloat64Array() # scratch for _create_ground
# Chunks streamed in while driving get their ground mesh a frame or so later,
# one per frame, so crossing a chunk edge does not build a whole row of meshes
# at once. They sit two chunks out, beyond the camera's normal view.
var _pending_ground: Array[ChunkData] = []
var _material: StandardMaterial3D
var _center_cx := 999999
var _center_cz := 999999
var _resolve_callable: Callable
var _avoid_obs_x := PackedFloat32Array()
var _avoid_obs_z := PackedFloat32Array()
var _avoid_obs_r := PackedFloat32Array()


func setup(shared_material: StandardMaterial3D) -> void:
	_material = shared_material
	_props = Props.build_props()
	_resolve_callable = Callable(self, "_resolve_obstruction")
	_avoid_obs_x.resize(AVOID_MAX_OBS)
	_avoid_obs_z.resize(AVOID_MAX_OBS)
	_avoid_obs_r.resize(AVOID_MAX_OBS)
	_col_start.resize(GRID_SPAN * GRID_SPAN + 1)
	_root_start.resize(GRID_SPAN * GRID_SPAN + 1)

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
	_pending_ground.clear()
	_loose.clear()
	_uprooted.clear()
	_spawned_caches.clear()
	_swaying.clear()
	for chunk: ChunkData in _chunks.values():
		_dispose_chunk(chunk)
	_chunks.clear()
	_clear_collider_grid()
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
	_pending_ground.clear()
	_swaying.clear()
	_clear_collider_grid()


func step_world(dt: float, focus_x: float, focus_z: float) -> void:
	_build_pending_ground()
	_loose.step(dt, focus_x, focus_z, _resolve_callable)
	for i in range(_swaying.size() - 1, -1, -1):
		var plant := _swaying[i]
		if not Roots.sway(plant, dt):
			_settle(plant)
	_render_loose()


func shove(mover: Variant, radius: float, mass: float, out: LooseSystem.ShoveResult) -> LooseSystem.ShoveResult:
	var mx: float = mover.x
	var mz: float = mover.z
	var min_x := maxi(int(floor((mx - radius) / COLLIDER_CELL)) - _grid_ox, 0)
	var max_x := mini(int(floor((mx + radius) / COLLIDER_CELL)) - _grid_ox, GRID_SPAN - 1)
	var min_z := maxi(int(floor((mz - radius) / COLLIDER_CELL)) - _grid_oz, 0)
	var max_z := mini(int(floor((mz + radius) / COLLIDER_CELL)) - _grid_oz, GRID_SPAN - 1)
	var torn := 0
	var grip := 0.0
	var grip_x := 0.0
	var grip_z := 0.0

	for gz in range(min_z, max_z + 1):
		var row := gz * GRID_SPAN
		for gx in range(min_x, max_x + 1):
			for k in range(_root_start[row + gx], _root_start[row + gx + 1]):
				var reach := radius + _root_r[k]
				var dx := _root_x[k] - mx
				var dz := _root_z[k] - mz
				if dx * dx + dz * dz >= reach * reach:
					continue
				var plant := _root_obj[k]
				if not plant.alive:
					continue
				if plant.hold > 0.0:
					var outcome := Roots.strain(plant, mover, radius, mass, _strain)
					# A plant that holds pushes the mover back out of itself.
					mx = mover.x
					mz = mover.z
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
	# A fresh world has to be fully drawn on its first frame.
	var defer_ground := _center_cx != 999999
	_center_cx = cx
	_center_cz = cz

	var wanted: Dictionary = {}
	for dz in range(-VIEW_RADIUS_CHUNKS, VIEW_RADIUS_CHUNKS + 1):
		for dx in range(-VIEW_RADIUS_CHUNKS, VIEW_RADIUS_CHUNKS + 1):
			var key := Vector2i(cx + dx, cz + dz)
			wanted[key] = true
			if not _chunks.has(key):
				_chunks[key] = _create_chunk(cx + dx, cz + dz, defer_ground)

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


func resolve(body: Variant, radius: float, contact: Contact) -> Contact:
	contact.hit = false
	var bx: float = body.x
	var bz: float = body.z
	var min_x := maxi(int(floor((bx - radius) / COLLIDER_CELL)) - _grid_ox, 0)
	var max_x := mini(int(floor((bx + radius) / COLLIDER_CELL)) - _grid_ox, GRID_SPAN - 1)
	var min_z := maxi(int(floor((bz - radius) / COLLIDER_CELL)) - _grid_oz, 0)
	var max_z := mini(int(floor((bz + radius) / COLLIDER_CELL)) - _grid_oz, GRID_SPAN - 1)
	var hit := false
	for gz in range(min_z, max_z + 1):
		var row := gz * GRID_SPAN
		for gx in range(min_x, max_x + 1):
			for k in range(_col_start[row + gx], _col_start[row + gx + 1]):
				var dx := bx - _col_x[k]
				var dz := bz - _col_z[k]
				var reach := radius + _col_r[k]
				var dist_sq := dx * dx + dz * dz
				if dist_sq >= reach * reach:
					continue
				var dist := sqrt(dist_sq)
				if dist < 0.001:
					dist = 0.001
				var nx := dx / dist
				var nz := dz / dist
				bx = _col_x[k] + nx * reach
				bz = _col_z[k] + nz * reach
				hit = true
				contact.nx = nx
				contact.nz = nz
	if hit:
		body.x = bx
		body.z = bz
		contact.hit = true
	return contact


func _resolve_obstruction(body: LooseSystem.LooseBody, radius: float, out: LooseSystem.Obstruction) -> void:
	var c := _loose_contact
	resolve(body, radius, c)
	out.hit = c.hit
	out.nx = c.nx
	out.nz = c.nz


func steer_around_obstacles(
	x: float,
	z: float,
	heading: float,
	desired_heading: float,
	radius: float,
	speed: float,
	mass: float,
	turn_rate: float,
	target_dist: float,
	prev_side: float,
	out: AvoidanceResult,
) -> AvoidanceResult:
	out.heading = desired_heading
	out.speed_factor = 1.0
	out.side_bias = prev_side
	out.avoiding = false

	var turn_pad := clampf(speed / maxf(0.6, turn_rate) * 0.25, 0.0, 7.0)
	var base_look := clampf(radius * 2.5 + speed * 0.5 + turn_pad, 9.0, 26.0)
	var lookahead := minf(base_look, maxf(radius + 1.5, target_dist))

	var dfx := sin(desired_heading)
	var dfz := cos(desired_heading)
	var cfx := sin(heading)
	var cfz := cos(heading)

	var end_x1 := x + dfx * lookahead
	var end_z1 := z + dfz * lookahead
	var end_x2 := x + cfx * (lookahead * 0.75)
	var end_z2 := z + cfz * (lookahead * 0.75)
	var pad := radius + 5.0
	var min_x := maxi(int(floor((minf(x, minf(end_x1, end_x2)) - pad) / COLLIDER_CELL)) - _grid_ox, 0)
	var max_x := mini(int(floor((maxf(x, maxf(end_x1, end_x2)) + pad) / COLLIDER_CELL)) - _grid_ox, GRID_SPAN - 1)
	var min_z := maxi(int(floor((minf(z, minf(end_z1, end_z2)) - pad) / COLLIDER_CELL)) - _grid_oz, 0)
	var max_z := mini(int(floor((maxf(z, maxf(end_z1, end_z2)) + pad) / COLLIDER_CELL)) - _grid_oz, GRID_SPAN - 1)

	var obs_count := 0
	var root_hold_limit := mass * maxf(speed, 12.0) * 0.58
	var max_range_sq := (lookahead + pad) * (lookahead + pad)

	for gz in range(min_z, max_z + 1):
		var row := gz * GRID_SPAN
		for gx in range(min_x, max_x + 1):
			var cell := row + gx
			for k in range(_col_start[cell], _col_start[cell + 1]):
				var rx := _col_x[k] - x
				var rz := _col_z[k] - z
				if rx * rx + rz * rz > max_range_sq:
					continue
				if obs_count < AVOID_MAX_OBS:
					_avoid_obs_x[obs_count] = rx
					_avoid_obs_z[obs_count] = rz
					_avoid_obs_r[obs_count] = _col_r[k] + radius + 0.9
					obs_count += 1
			for k in range(_root_start[cell], _root_start[cell + 1]):
				# Heavy vehicles plow through weak plants; lighter ones steer around trees/cacti that bounce them
				var hold := _root_hold[k]
				if hold <= 0.0 or hold < root_hold_limit:
					continue
				var rx := _root_x[k] - x
				var rz := _root_z[k] - z
				if rx * rx + rz * rz > max_range_sq:
					continue
				if not _root_obj[k].alive:
					continue
				if obs_count < AVOID_MAX_OBS:
					_avoid_obs_x[obs_count] = rx
					_avoid_obs_z[obs_count] = rz
					_avoid_obs_r[obs_count] = _root_r[k] + radius + 0.75
					obs_count += 1

	if obs_count == 0:
		return out

	# Fast path: if both the desired heading and immediate current heading are completely clear, keep going
	var desired_free := _ray_free_dist(dfx, dfz, lookahead, obs_count)
	var current_free := _ray_free_dist(cfx, cfz, lookahead * 0.65, obs_count)
	if desired_free >= lookahead - 0.01 and current_free >= lookahead * 0.65 - 0.01:
		return out

	out.avoiding = true

	var best_heading := desired_heading
	var best_score := -INF
	var best_free := 0.0
	var best_offset := 0.0

	for offset: float in AVOID_ANGLES:
		var cand := SimMath.wrap_angle(desired_heading + offset)
		var ux := sin(cand)
		var uz := cos(cand)
		var free_d := _ray_free_dist(ux, uz, lookahead, obs_count)
		var clear_ratio := free_d / lookahead
		var goal_align := cos(offset)
		var turn_diff := absf(SimMath.wrap_angle(cand - heading))
		var heading_align := cos(turn_diff)

		var side_bonus := 0.0
		if prev_side != 0.0 and offset != 0.0 and (offset * prev_side > 0.0):
			side_bonus = 0.28

		# Strongly prioritize unobstructed rays; among clear rays pick the one closest to the goal & current heading
		var score := clear_ratio * 3.6 + goal_align * 1.15 + heading_align * 0.55 + side_bonus
		if free_d >= lookahead - 0.01:
			score += 0.9
		if score > best_score:
			best_score = score
			best_heading = cand
			best_free = free_d
			best_offset = offset

	out.heading = best_heading
	if absf(best_offset) > 0.05:
		out.side_bias = signf(best_offset)
	elif prev_side == 0.0:
		out.side_bias = 1.0 if SimMath.wrap_angle(best_heading - heading) >= 0.0 else -1.0

	# Slow down smoothly when forced into a sharp turn or close to an obstacle
	var turn_need := absf(SimMath.wrap_angle(best_heading - heading))
	var tight := clampf(best_free / maxf(4.0, lookahead * 0.55), 0.35, 1.0)
	var turn_slow := clampf(1.0 - maxf(0.0, turn_need - 0.55) * 0.38, 0.45, 1.0)
	out.speed_factor = minf(tight, turn_slow)
	return out


func _ray_free_dist(ux: float, uz: float, max_dist: float, obs_count: int) -> float:
	var best := max_dist
	for i in obs_count:
		var rx := _avoid_obs_x[i]
		var rz := _avoid_obs_z[i]
		var r := _avoid_obs_r[i]
		var r_sq := r * r
		var dist_sq := rx * rx + rz * rz
		var proj := rx * ux + rz * uz
		if dist_sq < r_sq:
			# Already inside safety margin: block rays heading deeper into the obstacle, allow escape rays
			if proj > -0.15:
				return 0.0
			continue
		if proj <= 0.0 or proj - r >= best:
			continue
		var perp_sq := dist_sq - proj * proj
		if perp_sq >= r_sq:
			continue
		var hit_d := proj - sqrt(r_sq - perp_sq)
		if hit_d < best:
			best = maxf(0.0, hit_d)
	return best


func _pick_scatter(rng: SimMath.SeededRng) -> String:
	var roll := rng.next() * SCATTER_TOTAL
	for entry in SCATTER_TABLE:
		roll -= entry[1]
		if roll <= 0.0:
			return entry[0]
	return "rockA"


func _build_pending_ground() -> void:
	while not _pending_ground.is_empty():
		var chunk: ChunkData = _pending_ground.pop_front()
		# Skip chunks that were unloaded again before their turn came.
		if _chunks.get(Vector2i(chunk.cx, chunk.cz)) != chunk:
			continue
		chunk.ground = _create_ground(chunk.cx, chunk.cz)
		add_child(chunk.ground)
		return


func _create_chunk(cx: int, cz: int, defer_ground: bool = false) -> ChunkData:
	var chunk := ChunkData.new()
	chunk.cx = cx
	chunk.cz = cz
	if defer_ground:
		_pending_ground.append(chunk)
	else:
		chunk.ground = _create_ground(cx, cz)
		add_child(chunk.ground)

	var rng := SimMath.SeededRng.new(int(floor(SimMath.hash2(cx, cz) * 4294967296.0)))
	var origin_x := float(cx) * DesertTerrain.CHUNK_SIZE
	var origin_z := float(cz) * DesertTerrain.CHUNK_SIZE

	if rng.next() < OUTPOST_CHANCE:
		_place_outpost(chunk, origin_x + lerpf(18.0, 46.0, rng.next()), origin_z + lerpf(18.0, 46.0, rng.next()), rng)

	var scatter_count := 2 + int(floor(rng.next() * 3.0))
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
	_place(chunk, "pickup_cache", x + sin(facing + 5.4) * 5.2, z + cos(facing + 5.4) * 5.2, 0.0, rng)
	_place(chunk, "pickup_cache", x + sin(facing + 5.65) * 6.1, z + cos(facing + 5.65) * 6.1, 0.0, rng)
	_place(chunk, "pickup_cache", x + sin(facing + 1.5) * 10.5, z + cos(facing + 1.5) * 10.5, 0.0, rng)
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
	if prop_name == "pickup_cache":
		if not _fits(chunk, x, z, 0.75):
			return false
		var cache_id := "%d:%d:%d" % [chunk.cx, chunk.cz, chunk.cache_count]
		chunk.cache_count += 1
		if not _spawned_caches.has(cache_id):
			_spawned_caches[cache_id] = true
			if on_spawn_cache.is_valid():
				on_spawn_cache.call(x, z)
		return true

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

	var s := sin(yaw)
	var c := cos(yaw)
	if prop.loose == null:
		for local in prop.colliders:
			chunk.colliders.append(Collider.new(
				x + (local.x * c + local.z * s) * scale,
				z + (-local.x * s + local.z * c) * scale,
				local.r * scale,
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
	# Sleeping debris and settled plants keep last frame's instances: redraw only
	# when a body moved, or a plant is swaying (or just stopped).
	if not _loose.dirty and _swaying.is_empty() and _sway_drawn == 0:
		return
	_loose.dirty = false
	_sway_drawn = _swaying.size()
	for batch: SimMath.InstanceBatch in _loose_batches.values():
		batch.begin()
	for body in _loose.bodies:
		(_loose_batches[body.kind] as SimMath.InstanceBatch).push_transform(SimMath.sim_quat_transform(
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
		(_loose_batches[plant.prop_name] as SimMath.InstanceBatch).push_transform(
			Roots.lean_transform(plant, plant.y, plant.yaw, plant.scale, plant.scale_y)
		)
	for batch: SimMath.InstanceBatch in _loose_batches.values():
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


func _clear_collider_grid() -> void:
	_col_start.fill(0)
	_root_start.fill(0)
	_col_x.clear()
	_col_z.clear()
	_col_r.clear()
	_root_x.clear()
	_root_z.clear()
	_root_r.clear()
	_root_hold.clear()
	_root_obj.clear()


func _rebuild_collider_grid() -> void:
	_grid_ox = (_center_cx - VIEW_RADIUS_CHUNKS) * 4 - GRID_MARGIN
	_grid_oz = (_center_cz - VIEW_RADIUS_CHUNKS) * 4 - GRID_MARGIN

	# Counting sort: tally each cell's entries, turn the tallies into start
	# offsets, then drop every entry into its cell in the original order.
	var col_fill := PackedInt32Array()
	var root_fill := PackedInt32Array()
	col_fill.resize(GRID_SPAN * GRID_SPAN + 1)
	root_fill.resize(GRID_SPAN * GRID_SPAN + 1)
	for chunk: ChunkData in _chunks.values():
		for plant in chunk.rooted:
			if plant.alive:
				_tally_cells(root_fill, plant.x, plant.z, plant.r)
		for col in chunk.colliders:
			_tally_cells(col_fill, col.x, col.z, col.r)
	var col_total := _tallies_to_starts(col_fill, _col_start)
	var root_total := _tallies_to_starts(root_fill, _root_start)

	_col_x.resize(col_total)
	_col_z.resize(col_total)
	_col_r.resize(col_total)
	_root_x.resize(root_total)
	_root_z.resize(root_total)
	_root_r.resize(root_total)
	_root_hold.resize(root_total)
	_root_obj.resize(root_total)

	for chunk: ChunkData in _chunks.values():
		for plant in chunk.rooted:
			if not plant.alive:
				continue
			var min_x := maxi(int(floor((plant.x - plant.r) / COLLIDER_CELL)) - _grid_ox, 0)
			var max_x := mini(int(floor((plant.x + plant.r) / COLLIDER_CELL)) - _grid_ox, GRID_SPAN - 1)
			var min_z := maxi(int(floor((plant.z - plant.r) / COLLIDER_CELL)) - _grid_oz, 0)
			var max_z := mini(int(floor((plant.z + plant.r) / COLLIDER_CELL)) - _grid_oz, GRID_SPAN - 1)
			for gz in range(min_z, max_z + 1):
				for gx in range(min_x, max_x + 1):
					var cell := gz * GRID_SPAN + gx
					var k := root_fill[cell]
					root_fill[cell] = k + 1
					_root_x[k] = plant.x
					_root_z[k] = plant.z
					_root_r[k] = plant.r
					_root_hold[k] = plant.hold
					_root_obj[k] = plant
		for col in chunk.colliders:
			var min_x := maxi(int(floor((col.x - col.r) / COLLIDER_CELL)) - _grid_ox, 0)
			var max_x := mini(int(floor((col.x + col.r) / COLLIDER_CELL)) - _grid_ox, GRID_SPAN - 1)
			var min_z := maxi(int(floor((col.z - col.r) / COLLIDER_CELL)) - _grid_oz, 0)
			var max_z := mini(int(floor((col.z + col.r) / COLLIDER_CELL)) - _grid_oz, GRID_SPAN - 1)
			for gz in range(min_z, max_z + 1):
				for gx in range(min_x, max_x + 1):
					var cell := gz * GRID_SPAN + gx
					var k := col_fill[cell]
					col_fill[cell] = k + 1
					_col_x[k] = col.x
					_col_z[k] = col.z
					_col_r[k] = col.r


func _tally_cells(tally: PackedInt32Array, x: float, z: float, r: float) -> void:
	var min_x := maxi(int(floor((x - r) / COLLIDER_CELL)) - _grid_ox, 0)
	var max_x := mini(int(floor((x + r) / COLLIDER_CELL)) - _grid_ox, GRID_SPAN - 1)
	var min_z := maxi(int(floor((z - r) / COLLIDER_CELL)) - _grid_oz, 0)
	var max_z := mini(int(floor((z + r) / COLLIDER_CELL)) - _grid_oz, GRID_SPAN - 1)
	for gz in range(min_z, max_z + 1):
		for gx in range(min_x, max_x + 1):
			tally[gz * GRID_SPAN + gx] += 1


static func _tallies_to_starts(tally: PackedInt32Array, starts: PackedInt32Array) -> int:
	# Leaves `tally` holding each cell's first free slot, ready for the fill pass.
	var total := 0
	for cell in GRID_SPAN * GRID_SPAN:
		var n := tally[cell]
		starts[cell] = total
		tally[cell] = total
		total += n
	starts[GRID_SPAN * GRID_SPAN] = total
	return total


func _create_ground(cx: int, cz: int) -> MeshInstance3D:
	# Runs for a whole row of chunks whenever the car crosses a chunk edge, so
	# it writes the vertex arrays directly rather than going through
	# SurfaceTool one call per vertex, and samples each grid corner once.
	var cells := DesertTerrain.CHUNK_CELLS
	var side := cells + 1
	var base_ix := cx * cells
	var base_iz := cz * cells

	var heights := _ground_heights
	heights.resize(side * side)
	for local_z in side:
		for local_x in side:
			heights[local_z * side + local_x] = DesertTerrain.vertex_height(base_ix + local_x, base_iz + local_z)

	var vertex_count := cells * cells * 6
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(vertex_count)
	normals.resize(vertex_count)
	colors.resize(vertex_count)

	var v := 0
	for local_z in cells:
		var row := local_z * side
		for local_x in cells:
			var ix := base_ix + local_x
			var iz := base_iz + local_z
			var x0 := float(ix) * DesertTerrain.CELL_SIZE
			var x1 := x0 + DesertTerrain.CELL_SIZE
			var z0 := float(iz) * DesertTerrain.CELL_SIZE
			var z1 := z0 + DesertTerrain.CELL_SIZE

			var h00 := heights[row + local_x]
			var h10 := heights[row + local_x + 1]
			var h01 := heights[row + side + local_x]
			var h11 := heights[row + side + local_x + 1]

			var p00 := Vector3(x0, h00, -z0)
			var p10 := Vector3(x1, h10, -z0)
			var p01 := Vector3(x0, h01, -z1)
			var p11 := Vector3(x1, h11, -z1)

			# Sand colour of the two triangles; they share the per-cell patch term.
			var patch := 0.5 + 0.5 * sin(float(ix) * 0.19 + 1.7) * cos(float(iz) * 0.23 - 0.6)
			var grain1 := SimMath.hash2(ix * 2, iz)
			var c1 := Palette.SAND_LIGHT.lerp(Palette.SAND_DARK, clampf(0.55 - ((h00 + h10 + h11) / 3.0) * 0.09 + (grain1 - 0.5) * 0.3 + (patch - 0.5) * 0.35, 0.0, 1.0))
			if patch > 0.9 and grain1 > 0.5:
				c1 = c1.lerp(Palette.SAND_SHADOW, 0.5)
			var n1 := (p10 - p00).cross(p11 - p00).normalized()
			if n1.y < 0.0:
				n1 = -n1
			verts[v] = p00
			verts[v + 1] = p11
			verts[v + 2] = p10
			normals[v] = n1
			normals[v + 1] = n1
			normals[v + 2] = n1
			colors[v] = c1
			colors[v + 1] = c1
			colors[v + 2] = c1

			var grain2 := SimMath.hash2(ix * 2 + 1, iz)
			var c2 := Palette.SAND_LIGHT.lerp(Palette.SAND_DARK, clampf(0.55 - ((h00 + h11 + h01) / 3.0) * 0.09 + (grain2 - 0.5) * 0.3 + (patch - 0.5) * 0.35, 0.0, 1.0))
			if patch > 0.9 and grain2 > 0.5:
				c2 = c2.lerp(Palette.SAND_SHADOW, 0.5)
			var n2 := (p11 - p00).cross(p01 - p00).normalized()
			if n2.y < 0.0:
				n2 = -n2
			verts[v + 3] = p00
			verts[v + 4] = p01
			verts[v + 5] = p11
			normals[v + 3] = n2
			normals[v + 4] = n2
			normals[v + 5] = n2
			colors[v + 3] = c2
			colors[v + 4] = c2
			colors[v + 5] = c2
			v += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var ground_mesh := ArrayMesh.new()
	ground_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var ground := MeshInstance3D.new()
	ground.name = "Ground_%d_%d" % [cx, cz]
	ground.mesh = ground_mesh
	ground.material_override = _material
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ground

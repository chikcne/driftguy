class_name DesertTerrain
extends RefCounted

# Exact rolling desert heightfield math from src/terrain.ts.

const CELL_SIZE := 4.0
const CHUNK_CELLS := 16
const CHUNK_SIZE := CELL_SIZE * CHUNK_CELLS

# ground_height() is called thousands of times a frame (smoke, gibs, enemies,
# pickups, tyre marks), and each uncached call costs 15 trig evaluations. The
# corner heights of recently touched cells are kept in a direct-mapped cache:
# a 128 x 128 cell window (512 m), far wider than anything on screen. Entries
# store the same doubles vertex_height() returns, so results are bit-identical.
const CACHE_BITS := 7
const CACHE_MASK := (1 << CACHE_BITS) - 1
const CACHE_STRIDE := 5 # key, h00, h10, h01, h11
const CACHE_KEY_SCALE := 131072.0

static var _cells := _new_cache()


static func _new_cache() -> PackedFloat64Array:
	var cells := PackedFloat64Array()
	cells.resize((1 << (CACHE_BITS * 2)) * CACHE_STRIDE)
	cells.fill(NAN) # NAN never equals a key, so every slot starts as a miss
	return cells


static func vertex_height(ix: int, iz: int) -> float:
	var x := float(ix) * CELL_SIZE
	var z := float(iz) * CELL_SIZE
	return (
		2.2 * sin(x * 0.021 + 1.3) * cos(z * 0.017 - 0.4)
		+ 1.5 * sin((x + z) * 0.011 + 2.1)
		+ 0.6 * sin(x * 0.063 - z * 0.047)
		+ 0.22 * sin(x * 0.21 + z * 0.17)
	)


static func ground_height(x: float, z: float) -> float:
	var gx := x / CELL_SIZE
	var gz := z / CELL_SIZE
	var fx := floorf(gx)
	var fz := floorf(gz)
	var ix := int(fx)
	var iz := int(fz)
	var cells := _cells
	var o := ((ix & CACHE_MASK) | ((iz & CACHE_MASK) << CACHE_BITS)) * CACHE_STRIDE
	var key := fx * CACHE_KEY_SCALE + fz
	if cells[o] != key:
		cells[o] = key
		cells[o + 1] = vertex_height(ix, iz)
		cells[o + 2] = vertex_height(ix + 1, iz)
		cells[o + 3] = vertex_height(ix, iz + 1)
		cells[o + 4] = vertex_height(ix + 1, iz + 1)
	var tx := gx - fx
	var tz := gz - fz
	var h00 := cells[o + 1]
	var h11 := cells[o + 4]
	if tx >= tz:
		var h10 := cells[o + 2]
		return h00 + (h10 - h00) * tx + (h11 - h10) * tz
	var h01 := cells[o + 3]
	return h00 + (h11 - h01) * tx + (h01 - h00) * tz


static func sample_slope(x: float, z: float, heading: float, half_length: float, half_width: float) -> Vector3:
	# Returns Vector3(height, pitch, roll) matching src/terrain.ts
	var fx := sin(heading)
	var fz := cos(heading)
	var front := ground_height(x + fx * half_length, z + fz * half_length)
	var back := ground_height(x - fx * half_length, z - fz * half_length)
	var right := ground_height(x + fz * half_width, z - fx * half_width)
	var left := ground_height(x - fz * half_width, z + fx * half_width)
	var h := (front + back + right + left) * 0.25
	var pitch := -atan2(front - back, half_length * 2.0)
	var roll := atan2(right - left, half_width * 2.0)
	return Vector3(h, pitch, roll)

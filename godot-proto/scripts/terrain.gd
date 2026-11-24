class_name DesertTerrain
extends RefCounted

# Exact rolling desert heightfield math from src/terrain.ts.

const CELL_SIZE := 4.0
const CHUNK_CELLS := 16
const CHUNK_SIZE := CELL_SIZE * CHUNK_CELLS


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
	var ix := int(floor(gx))
	var iz := int(floor(gz))
	var tx := gx - float(ix)
	var tz := gz - float(iz)
	var h00 := vertex_height(ix, iz)
	var h11 := vertex_height(ix + 1, iz + 1)
	if tx >= tz:
		var h10 := vertex_height(ix + 1, iz)
		return h00 + (h10 - h00) * tx + (h11 - h10) * tz
	var h01 := vertex_height(ix, iz + 1)
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

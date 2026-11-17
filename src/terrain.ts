export const CELL_SIZE = 4;
export const CHUNK_CELLS = 16;
export const CHUNK_SIZE = CELL_SIZE * CHUNK_CELLS;

export function vertexHeight(ix: number, iz: number): number {
  const x = ix * CELL_SIZE;
  const z = iz * CELL_SIZE;
  return (
    2.2 * Math.sin(x * 0.021 + 1.3) * Math.cos(z * 0.017 - 0.4) +
    1.5 * Math.sin((x + z) * 0.011 + 2.1) +
    0.6 * Math.sin(x * 0.063 - z * 0.047) +
    0.22 * Math.sin(x * 0.21 + z * 0.17)
  );
}

export function groundHeight(x: number, z: number): number {
  const gx = x / CELL_SIZE;
  const gz = z / CELL_SIZE;
  const ix = Math.floor(gx);
  const iz = Math.floor(gz);
  const tx = gx - ix;
  const tz = gz - iz;
  const h00 = vertexHeight(ix, iz);
  const h11 = vertexHeight(ix + 1, iz + 1);
  if (tx >= tz) {
    const h10 = vertexHeight(ix + 1, iz);
    return h00 + (h10 - h00) * tx + (h11 - h10) * tz;
  }
  const h01 = vertexHeight(ix, iz + 1);
  return h00 + (h11 - h01) * tx + (h01 - h00) * tz;
}

export interface Slope {
  height: number;
  pitch: number;
  roll: number;
}

export function sampleSlope(x: number, z: number, heading: number, halfLength: number, halfWidth: number, out: Slope): Slope {
  const fx = Math.sin(heading);
  const fz = Math.cos(heading);
  const front = groundHeight(x + fx * halfLength, z + fz * halfLength);
  const back = groundHeight(x - fx * halfLength, z - fz * halfLength);
  const right = groundHeight(x + fz * halfWidth, z - fx * halfWidth);
  const left = groundHeight(x - fz * halfWidth, z + fx * halfWidth);
  out.height = (front + back + right + left) * 0.25;
  out.pitch = -Math.atan2(front - back, halfLength * 2);
  out.roll = Math.atan2(right - left, halfWidth * 2);
  return out;
}

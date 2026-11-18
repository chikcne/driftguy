import { writePose, type Mover } from "./loose";

export interface RootSpec {
  hold: number;
  tear: number;
}

export interface Anchor {
  x: number;
  z: number;
  r: number;
  hold: number;
  tear: number;
  leanX: number;
  leanZ: number;
  swayX: number;
  swayZ: number;
}

export interface Strain {
  impulse: number;
  x: number;
  z: number;
}

export type RootOutcome = "clear" | "held" | "torn";

const ROOT_BOUNCE = 0.15;
const SWAY_KICK = 7;
const SWAY_STIFFNESS = 196;
const SWAY_DAMPING = 6;
const SWAY_MAX_STEP = 1 / 30;
const LEAN_LIMIT = 0.4;
const REST_LEAN_SQ = 0.00001;
const REST_SWAY_SQ = 0.001;

export function strain(anchor: Anchor, mover: Mover, radius: number, mass: number, out: Strain): RootOutcome {
  out.impulse = 0;
  let dx = anchor.x - mover.x;
  let dz = anchor.z - mover.z;
  const reach = radius + anchor.r;
  const distSq = dx * dx + dz * dz;
  if (distSq >= reach * reach) return "clear";
  let dist = Math.sqrt(distSq);
  if (dist < 0.001) {
    const speed = Math.hypot(mover.vx, mover.vz);
    dx = speed > 0 ? mover.vx / speed : 0;
    dz = speed > 0 ? mover.vz / speed : 1;
    dist = 1;
  }
  const nx = dx / dist;
  const nz = dz / dist;
  const closing = mover.vx * nx + mover.vz * nz;
  const momentum = mass * closing;
  out.x = mover.x + nx * radius;
  out.z = mover.z + nz * radius;
  if (momentum > anchor.hold) {
    out.impulse = anchor.tear;
    mover.vx -= (nx * anchor.tear) / mass;
    mover.vz -= (nz * anchor.tear) / mass;
    return "torn";
  }
  mover.x = anchor.x - nx * reach;
  mover.z = anchor.z - nz * reach;
  if (closing <= 0) return "held";
  mover.vx -= (1 + ROOT_BOUNCE) * closing * nx;
  mover.vz -= (1 + ROOT_BOUNCE) * closing * nz;
  const kick = (momentum / anchor.hold) * SWAY_KICK;
  anchor.swayX += nx * kick;
  anchor.swayZ += nz * kick;
  out.impulse = (1 + ROOT_BOUNCE) * momentum;
  return "held";
}

export function sway(anchor: Anchor, dt: number): boolean {
  const step = Math.min(dt, SWAY_MAX_STEP);
  anchor.swayX += (-SWAY_STIFFNESS * anchor.leanX - SWAY_DAMPING * anchor.swayX) * step;
  anchor.swayZ += (-SWAY_STIFFNESS * anchor.leanZ - SWAY_DAMPING * anchor.swayZ) * step;
  anchor.leanX += anchor.swayX * step;
  anchor.leanZ += anchor.swayZ * step;
  const lean = Math.hypot(anchor.leanX, anchor.leanZ);
  if (lean > LEAN_LIMIT) {
    const ux = anchor.leanX / lean;
    const uz = anchor.leanZ / lean;
    anchor.leanX = ux * LEAN_LIMIT;
    anchor.leanZ = uz * LEAN_LIMIT;
    const outward = anchor.swayX * ux + anchor.swayZ * uz;
    if (outward > 0) {
      anchor.swayX -= outward * ux;
      anchor.swayZ -= outward * uz;
    }
  }
  const leanSq = anchor.leanX * anchor.leanX + anchor.leanZ * anchor.leanZ;
  const swaySq = anchor.swayX * anchor.swayX + anchor.swayZ * anchor.swayZ;
  return leanSq > REST_LEAN_SQ || swaySq > REST_SWAY_SQ;
}

export function writeLean(target: Float32Array, offset: number, anchor: Anchor, y: number, yaw: number, scale: number, scaleY: number): void {
  const lean = Math.hypot(anchor.leanX, anchor.leanZ);
  const tilt = lean > 0.000001 ? Math.sin(lean / 2) / lean : 0;
  const tx = anchor.leanZ * tilt;
  const tz = -anchor.leanX * tilt;
  const tw = Math.cos(lean / 2);
  const sy = Math.sin(yaw / 2);
  const cy = Math.cos(yaw / 2);
  writePose(target, offset, anchor.x, y, anchor.z, tx * cy - tz * sy, tw * sy, tx * sy + tz * cy, tw * cy, scale, scaleY, 0);
}

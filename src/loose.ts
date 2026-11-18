import { groundHeight } from "./terrain";

export type LoosePoint = [x: number, y: number, z: number, radius: number];

export interface LooseSpec {
  mass: number;
  radius: number;
  centre: number;
  points: LoosePoint[];
}

export interface Mover {
  x: number;
  z: number;
  vx: number;
  vz: number;
}

export interface Shove {
  hit: boolean;
  impulse: number;
  x: number;
  z: number;
  torn: number;
}

export interface Obstruction {
  hit: boolean;
  nx: number;
  nz: number;
}

export type Obstacles = (spot: { x: number; z: number }, radius: number, out: Obstruction) => Obstruction;

export interface LooseBody<Kind> {
  kind: Kind;
  x: number;
  y: number;
  z: number;
  vx: number;
  vy: number;
  vz: number;
  qx: number;
  qy: number;
  qz: number;
  qw: number;
  wx: number;
  wy: number;
  wz: number;
  scale: number;
  scaleY: number;
  origin: number;
  mass: number;
  inertia: number;
  reach: number;
  girth: number;
  points: Float32Array;
  calm: number;
  asleep: boolean;
}

const STEP = 1 / 120;
const MAX_STEPS = 8;
const MAX_BODIES = 56;
const DESPAWN_DISTANCE = 240;
const GRAVITY = 22;
const GROUND_BOUNCE = 0.3;
const BOUNCE_MIN_SPEED = 3;
const GROUND_FRICTION = 0.7;
const GROUND_SPIN_DAMPING = 1.6;
const GROUND_SLIDE_DAMPING = 1.8;
const AIR_DAMPING = 0.6;
const SLEEP_SPEED_SQ = 0.3;
const SLEEP_SPIN_SQ = 0.6;
const SLEEP_SECONDS = 0.5;
const SHOVE_BOUNCE = 0.1;
const SHOVE_LIFT = 0.28;
const SHOVE_CLEARANCE = 1.1;
const OBSTACLE_BOUNCE = 0.3;
const GYRATION = 0.6;
const UPROOT_SPIN = 0.8;

const basis = new Float64Array(9);

function orient(body: LooseBody<unknown>): void {
  const { qx, qy, qz, qw } = body;
  basis[0] = 1 - 2 * (qy * qy + qz * qz);
  basis[1] = 2 * (qx * qy - qz * qw);
  basis[2] = 2 * (qx * qz + qy * qw);
  basis[3] = 2 * (qx * qy + qz * qw);
  basis[4] = 1 - 2 * (qx * qx + qz * qz);
  basis[5] = 2 * (qy * qz - qx * qw);
  basis[6] = 2 * (qx * qz - qy * qw);
  basis[7] = 2 * (qy * qz + qx * qw);
  basis[8] = 1 - 2 * (qx * qx + qy * qy);
}

function punch(body: LooseBody<unknown>, rx: number, ry: number, rz: number, jx: number, jy: number, jz: number): void {
  body.vx += jx / body.mass;
  body.vy += jy / body.mass;
  body.vz += jz / body.mass;
  body.wx += (ry * jz - rz * jy) / body.inertia;
  body.wy += (rz * jx - rx * jz) / body.inertia;
  body.wz += (rx * jy - ry * jx) / body.inertia;
}

export function writePose(
  target: Float32Array,
  o: number,
  x: number,
  y: number,
  z: number,
  qx: number,
  qy: number,
  qz: number,
  qw: number,
  scale: number,
  scaleY: number,
  origin: number,
): void {
  const xy = 2 * (qx * qy - qz * qw);
  const yy = 1 - 2 * (qx * qx + qz * qz);
  const zy = 2 * (qy * qz + qx * qw);
  target[o] = (1 - 2 * (qy * qy + qz * qz)) * scale;
  target[o + 1] = 2 * (qx * qy + qz * qw) * scale;
  target[o + 2] = 2 * (qx * qz - qy * qw) * scale;
  target[o + 3] = 0;
  target[o + 4] = xy * scaleY;
  target[o + 5] = yy * scaleY;
  target[o + 6] = zy * scaleY;
  target[o + 7] = 0;
  target[o + 8] = 2 * (qx * qz + qy * qw) * scale;
  target[o + 9] = 2 * (qy * qz - qx * qw) * scale;
  target[o + 10] = (1 - 2 * (qx * qx + qy * qy)) * scale;
  target[o + 11] = 0;
  target[o + 12] = x - xy * origin;
  target[o + 13] = y - yy * origin;
  target[o + 14] = z - zy * origin;
  target[o + 15] = 1;
}

export class LooseSystem<Kind> {
  readonly bodies: LooseBody<Kind>[] = [];
  private readonly obstruction: Obstruction = { hit: false, nx: 0, nz: 0 };
  private leftover = 0;

  clear(): void {
    this.bodies.length = 0;
    this.leftover = 0;
  }

  spawn(kind: Kind, spec: LooseSpec, x: number, baseY: number, z: number, yaw: number, scale: number, scaleY: number): LooseBody<Kind> {
    const origin = spec.centre * scaleY;
    const points = new Float32Array(spec.points.length * 4);
    let reach = 0;
    spec.points.forEach(([px, py, pz, radius], i) => {
      const lx = px * scale;
      const ly = py * scaleY - origin;
      const lz = pz * scale;
      points[i * 4] = lx;
      points[i * 4 + 1] = ly;
      points[i * 4 + 2] = lz;
      points[i * 4 + 3] = radius * scale;
      reach = Math.max(reach, Math.hypot(lx, ly, lz) + radius * scale);
    });
    const mass = spec.mass * scale * scale;
    const body: LooseBody<Kind> = {
      kind,
      x,
      y: baseY + origin,
      z,
      vx: 0,
      vy: 0,
      vz: 0,
      qx: 0,
      qy: Math.sin(yaw / 2),
      qz: 0,
      qw: Math.cos(yaw / 2),
      wx: (Math.random() * 2 - 1) * UPROOT_SPIN,
      wy: (Math.random() * 2 - 1) * UPROOT_SPIN,
      wz: (Math.random() * 2 - 1) * UPROOT_SPIN,
      scale,
      scaleY,
      origin,
      mass,
      inertia: mass * (GYRATION * reach) ** 2,
      reach,
      girth: spec.radius * scale,
      points,
      calm: 0,
      asleep: false,
    };
    this.bodies.push(body);
    if (this.bodies.length > MAX_BODIES) this.bodies.shift();
    return body;
  }

  shove(mover: Mover, radius: number, mass: number, out: Shove): Shove {
    out.hit = false;
    out.impulse = 0;
    out.x = 0;
    out.z = 0;
    out.torn = 0;
    let ceiling = Number.NaN;
    for (const body of this.bodies) {
      const span = radius + body.reach;
      const offX = body.x - mover.x;
      const offZ = body.z - mover.z;
      if (offX * offX + offZ * offZ >= span * span) continue;
      if (Number.isNaN(ceiling)) ceiling = groundHeight(mover.x, mover.z) + SHOVE_CLEARANCE;
      orient(body);
      const points = body.points;
      for (let i = 0; i < points.length; i += 4) {
        const lx = points[i];
        const ly = points[i + 1];
        const lz = points[i + 2];
        const size = points[i + 3];
        const cx = basis[0] * lx + basis[1] * ly + basis[2] * lz;
        const cy = basis[3] * lx + basis[4] * ly + basis[5] * lz;
        const cz = basis[6] * lx + basis[7] * ly + basis[8] * lz;
        if (body.y + cy - size > ceiling) continue;
        let dx = body.x + cx - mover.x;
        let dz = body.z + cz - mover.z;
        const limit = radius + size;
        const distSq = dx * dx + dz * dz;
        if (distSq >= limit * limit) continue;
        let dist = Math.sqrt(distSq);
        if (dist < 0.001) {
          const speed = Math.hypot(mover.vx, mover.vz);
          dx = speed > 0 ? mover.vx / speed : 0;
          dz = speed > 0 ? mover.vz / speed : 1;
          dist = 1;
        }
        const nx = dx / dist;
        const nz = dz / dist;
        const rx = cx - nx * size;
        const ry = cy;
        const rz = cz - nz * size;
        const ux = body.vx + body.wy * rz - body.wz * ry;
        const uz = body.vz + body.wx * ry - body.wy * rx;
        const closing = (ux - mover.vx) * nx + (uz - mover.vz) * nz;
        const depth = limit - Math.sqrt(distSq);
        body.x += nx * depth;
        body.z += nz * depth;
        body.asleep = false;
        body.calm = 0;
        out.hit = true;
        if (closing >= 0) continue;
        const tx = ry * nz;
        const ty = rz * nx - rx * nz;
        const tz = -ry * nx;
        const resistance = 1 / body.mass + (tx * tx + ty * ty + tz * tz) / body.inertia + 1 / mass;
        const impulse = (-(1 + SHOVE_BOUNCE) * closing) / resistance;
        punch(body, rx, ry, rz, impulse * nx, 0, impulse * nz);
        body.vy += (impulse * SHOVE_LIFT) / body.mass;
        mover.vx -= (impulse * nx) / mass;
        mover.vz -= (impulse * nz) / mass;
        out.impulse += impulse;
        out.x += (mover.x + nx * radius) * impulse;
        out.z += (mover.z + nz * radius) * impulse;
      }
    }
    if (out.impulse > 0) {
      out.x /= out.impulse;
      out.z /= out.impulse;
    }
    return out;
  }

  step(dt: number, focusX: number, focusZ: number, obstacles?: Obstacles): void {
    for (let i = this.bodies.length - 1; i >= 0; i--) {
      const body = this.bodies[i];
      if (Math.abs(body.x - focusX) > DESPAWN_DISTANCE || Math.abs(body.z - focusZ) > DESPAWN_DISTANCE) this.bodies.splice(i, 1);
    }
    this.leftover += dt;
    let steps = 0;
    while (this.leftover >= STEP) {
      this.leftover -= STEP;
      if (steps++ >= MAX_STEPS) continue;
      for (const body of this.bodies) {
        if (!body.asleep) this.integrate(body, STEP, obstacles);
      }
    }
  }

  write(kind: Kind, target: Float32Array): number {
    let count = 0;
    for (const body of this.bodies) {
      if (body.kind !== kind) continue;
      writePose(target, count * 16, body.x, body.y, body.z, body.qx, body.qy, body.qz, body.qw, body.scale, body.scaleY, body.origin);
      count++;
    }
    return count;
  }

  private integrate(body: LooseBody<Kind>, dt: number, obstacles?: Obstacles): void {
    body.vy -= GRAVITY * dt;
    body.x += body.vx * dt;
    body.y += body.vy * dt;
    body.z += body.vz * dt;

    const { qx, qy, qz, qw, wx, wy, wz } = body;
    const half = dt * 0.5;
    body.qx = qx + half * (wx * qw + wy * qz - wz * qy);
    body.qy = qy + half * (wy * qw + wz * qx - wx * qz);
    body.qz = qz + half * (wz * qw + wx * qy - wy * qx);
    body.qw = qw - half * (wx * qx + wy * qy + wz * qz);
    const norm = Math.hypot(body.qx, body.qy, body.qz, body.qw) || 1;
    body.qx /= norm;
    body.qy /= norm;
    body.qz /= norm;
    body.qw /= norm;

    orient(body);
    const points = body.points;
    let sunk = 0;
    let grounded = false;
    for (let i = 0; i < points.length; i += 4) {
      const lx = points[i];
      const ly = points[i + 1];
      const lz = points[i + 2];
      const size = points[i + 3];
      const rx = basis[0] * lx + basis[1] * ly + basis[2] * lz;
      const ry = basis[3] * lx + basis[4] * ly + basis[5] * lz - size;
      const rz = basis[6] * lx + basis[7] * ly + basis[8] * lz;
      const depth = groundHeight(body.x + rx, body.z + rz) - (body.y + ry);
      if (depth <= 0) continue;
      grounded = true;
      if (depth > sunk) sunk = depth;
      const uy = body.vy + body.wz * rx - body.wx * rz;
      if (uy >= 0) continue;
      const bounce = uy < -BOUNCE_MIN_SPEED ? GROUND_BOUNCE : 0;
      const normal = (-(1 + bounce) * uy) / (1 / body.mass + (rx * rx + rz * rz) / body.inertia);
      punch(body, rx, ry, rz, 0, normal, 0);

      const ux = body.vx + body.wy * rz - body.wz * ry;
      const uz = body.vz + body.wx * ry - body.wy * rx;
      const slide = Math.hypot(ux, uz);
      if (slide < 0.001) continue;
      const tx = ux / slide;
      const tz = uz / slide;
      const ax = ry * tz;
      const ay = rz * tx - rx * tz;
      const az = -ry * tx;
      const grip = Math.min(GROUND_FRICTION * normal, slide / (1 / body.mass + (ax * ax + ay * ay + az * az) / body.inertia));
      punch(body, rx, ry, rz, -grip * tx, 0, -grip * tz);
    }

    if (grounded) {
      body.y += sunk;
      const spin = Math.exp(-GROUND_SPIN_DAMPING * dt);
      const slide = Math.exp(-GROUND_SLIDE_DAMPING * dt);
      body.wx *= spin;
      body.wy *= spin;
      body.wz *= spin;
      body.vx *= slide;
      body.vz *= slide;
    } else {
      const drag = Math.exp(-AIR_DAMPING * dt);
      body.vx *= drag;
      body.vz *= drag;
    }

    if (obstacles && obstacles(body, body.girth, this.obstruction).hit) {
      const into = body.vx * this.obstruction.nx + body.vz * this.obstruction.nz;
      if (into < 0) {
        body.vx -= (1 + OBSTACLE_BOUNCE) * into * this.obstruction.nx;
        body.vz -= (1 + OBSTACLE_BOUNCE) * into * this.obstruction.nz;
      }
    }

    const speedSq = body.vx * body.vx + body.vy * body.vy + body.vz * body.vz;
    const spinSq = body.wx * body.wx + body.wy * body.wy + body.wz * body.wz;
    if (grounded && speedSq < SLEEP_SPEED_SQ && spinSq < SLEEP_SPIN_SQ) {
      body.calm += dt;
      if (body.calm > SLEEP_SECONDS) {
        body.asleep = true;
        body.vx = body.vy = body.vz = body.wx = body.wy = body.wz = 0;
      }
    } else {
      body.calm = 0;
    }
  }
}

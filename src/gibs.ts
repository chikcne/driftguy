import { Color3, Material, Scene, ShadowGenerator, StandardMaterial } from "@babylonjs/core";
import { InstanceBatch, type Triple } from "./kit";
import { clamp, damp, randRange, randSigned, TAU, wrapAngle } from "./math";
import { buildGibModels, type EnemyKind, type GibShape } from "./models";
import { PALETTE as P } from "./palette";
import { PUFF, type SmokeSystem } from "./smoke";
import { groundHeight } from "./terrain";

interface Part {
  shape: GibShape;
  size: Triple;
  at: Triple;
  color: Color3;
}

const part = (shape: GibShape, size: Triple, at: Triple, color: Color3): Part => ({ shape, size, at, color });
const box = (size: Triple, at: Triple, color: Color3): Part => part("box", size, at, color);
const pipe = (diameter: number, length: number, at: Triple, color: Color3): Part => part("pipe", [diameter, diameter, length], at, color);
const spike = (length: number, at: Triple): Part => part("spike", [0.2, 0.2, length], at, P.raiderBone);
const skull = (diameter: number, at: Triple): Part => part("skull", [diameter, diameter, diameter], at, P.raiderBone);
const wheel = (diameter: number, width: number, at: Triple): Part => part("wheel", [width, diameter, diameter], at, P.rubber);
const axle = (x: number, z: number, diameter: number, width: number): Part[] => [
  wheel(diameter, width, [x, diameter / 2, z]),
  wheel(diameter, width, [-x, diameter / 2, z]),
];

const RECIPES: Record<EnemyKind, Part[]> = {
  bike: [
    wheel(0.72, 0.2, [0, 0.36, 0.85]),
    wheel(0.72, 0.24, [0, 0.36, -0.8]),
    box([0.26, 0.34, 0.8], [0, 0.62, 0.4], P.raiderRed),
    box([0.26, 0.34, 0.7], [0, 0.62, -0.4], P.raiderRed),
    box([0.34, 0.24, 0.5], [0, 0.82, 0.2], P.raiderBlack),
    box([0.8, 0.07, 0.07], [0, 1.02, 0.62], P.metalDark),
    box([0.46, 0.32, 0.62], [0, 1.2, -0.2], P.raiderBlack),
    skull(0.4, [0, 1.62, 0]),
    box([0.06, 0.06, 1.5], [0, 1.5, -0.85], P.metalDark),
    box([0.6, 0.04, 0.34], [0, 2.05, -1.15], P.raiderRed),
  ],
  buggy: [
    ...axle(0.95, 1.05, 0.9, 0.36),
    ...axle(1.0, -1.05, 1.0, 0.44),
    box([1.5, 0.3, 1.5], [0, 0.6, 0.75], P.rust),
    box([1.5, 0.3, 1.5], [0, 0.6, -0.75], P.rust),
    box([1.2, 0.34, 1.0], [0, 0.86, 1.0], P.raiderRed),
    box([1.0, 0.5, 0.8], [0, 0.98, -1.05], P.metalDark),
    pipe(0.14, 0.9, [0.3, 1.5, -1.2], P.metal),
    pipe(0.14, 0.9, [-0.3, 1.5, -1.2], P.metal),
    box([0.08, 0.08, 1.0], [0.66, 1.25, 0.45], P.raiderBlack),
    box([0.08, 0.08, 1.0], [-0.66, 1.25, 0.45], P.raiderBlack),
    box([0.08, 0.08, 1.0], [0.66, 1.25, -0.5], P.raiderBlack),
    box([0.08, 0.08, 1.0], [-0.66, 1.25, -0.5], P.raiderBlack),
    box([1.4, 0.08, 1.0], [0, 1.72, 0], P.raiderBlack),
    skull(0.44, [0, 1.3, -0.05]),
    box([1.7, 0.16, 0.16], [0, 0.6, 1.58], P.metalDark),
    spike(0.6, [0.6, 0.62, 1.86]),
    spike(0.7, [0, 0.62, 1.9]),
    spike(0.6, [-0.6, 0.62, 1.86]),
  ],
  truck: [
    ...axle(1.2, 1.8, 1.2, 0.5),
    ...axle(1.2, -0.9, 1.2, 0.5),
    ...axle(1.2, -2.2, 1.2, 0.5),
    box([2.2, 0.5, 2.8], [0, 0.95, 1.2], P.raiderBlack),
    box([2.2, 0.5, 2.8], [0, 0.95, -1.6], P.raiderBlack),
    box([2.2, 0.7, 1.7], [0, 1.55, 1.5], P.rustDark),
    box([2.2, 0.12, 1.7], [0, 2.45, 1.5], P.rustDark),
    box([1.9, 0.1, 0.5], [0, 2.0, 2.37], P.glass),
    box([2.3, 0.14, 1.6], [1.1, 1.7, -1.3], P.rust),
    box([2.3, 0.14, 1.6], [-1.1, 1.7, -1.3], P.rust),
    box([2.3, 0.14, 1.0], [0, 1.7, -2.9], P.rust),
    box([2.36, 0.14, 3.36], [0, 2.26, -1.3], P.rustLight),
    box([1.5, 0.14, 1.1], [0.7, 0.85, 2.85], P.metal),
    box([1.5, 0.14, 1.1], [-0.7, 0.85, 2.85], P.metal),
    pipe(0.2, 1.6, [1.0, 3.0, 0.55], P.metal),
    pipe(0.2, 1.6, [-1.0, 3.0, 0.55], P.metal),
    skull(0.68, [0, 1.5, 2.42]),
    box([0.08, 0.08, 1.7], [0.9, 3.1, -2.6], P.metalDark),
    box([0.8, 0.05, 0.5], [0.9, 3.7, -3.0], P.raiderRed),
  ],
  interceptor: [
    ...axle(0.95, 1.3, 0.76, 0.34),
    ...axle(1.0, -1.3, 0.86, 0.44),
    box([1.86, 0.46, 2.2], [0, 0.6, 1.1], P.raiderPurple),
    box([1.86, 0.46, 2.2], [0, 0.6, -1.1], P.raiderPurple),
    box([1.5, 0.4, 1.7], [0, 1.0, -0.5], P.raiderBlack),
    box([1.56, 0.08, 1.4], [0, 1.24, -0.55], P.raiderPurple),
    box([0.6, 0.42, 0.7], [0, 1.0, 1.15], P.metal),
    box([0.7, 0.16, 0.5], [0, 1.28, 1.2], P.raiderYellow),
    box([1.9, 0.08, 0.5], [0, 1.1, -2.1], P.raiderBlack),
    box([1.96, 0.2, 0.2], [0, 0.46, 2.26], P.metalDark),
    pipe(0.18, 1.6, [1.02, 0.5, -1.2], P.metal),
    pipe(0.18, 1.6, [-1.02, 0.5, -1.2], P.metal),
    spike(0.7, [0.7, 0.5, 2.6]),
    spike(0.7, [-0.7, 0.5, 2.6]),
  ],
  rig: [
    ...[3.6, 1.0, -0.3, -3.0, -4.3].flatMap((z) => axle(1.45, z, 1.4, 0.6)),
    box([2.7, 0.6, 3.6], [0, 1.15, 3.1], P.raiderBlack),
    box([2.7, 0.6, 3.5], [0, 1.15, -0.4], P.raiderBlack),
    box([2.7, 0.6, 3.5], [0, 1.15, -3.9], P.raiderBlack),
    box([2.7, 0.9, 2.2], [0, 1.9, 3.4], P.raiderRed),
    box([2.7, 0.16, 2.2], [0, 3.1, 3.4], P.raiderRed),
    box([2.3, 0.1, 0.6], [0, 2.6, 4.52], P.glass),
    box([2.4, 1.0, 1.4], [0, 1.9, 5.0], P.rustDark),
    pipe(2.6, 2.2, [0, 2.75, 0.3], P.rust),
    pipe(2.6, 2.2, [0, 2.75, -1.9], P.rust),
    pipe(2.6, 2.2, [0, 2.75, -4.1], P.rust),
    pipe(2.7, 0.3, [0, 2.75, 0.2], P.rustDark),
    pipe(2.7, 0.3, [0, 2.75, -4.0], P.rustDark),
    box([2.2, 0.18, 1.5], [0.95, 1.1, 5.95], P.metal),
    box([2.2, 0.18, 1.5], [-0.95, 1.1, 5.95], P.metal),
    pipe(0.26, 2.4, [1.2, 4.0, 2.5], P.metal),
    pipe(0.26, 2.4, [-1.2, 4.0, 2.5], P.metal),
    skull(1.0, [0, 2.2, 5.75]),
    spike(0.9, [0, 4.4, -3.4]),
    spike(0.9, [0, 4.4, -2.0]),
    spike(0.9, [0, 4.4, -0.6]),
    box([0.1, 0.1, 2.4], [1.2, 5.0, -4.6], P.metalDark),
    box([1.3, 0.06, 0.8], [1.2, 5.8, -5.3], P.raiderYellow),
  ],
};

const SHAPES: GibShape[] = ["box", "wheel", "pipe", "spike", "skull", "spark"];
const MAX_GIBS = 768;
const GRAVITY = 30;
const AIR_DRAG = 0.25;
const BOUNCE = 0.36;
const WHEEL_BOUNCE = 0.58;
const BOUNCE_KEEP = 0.72;
const SETTLE_SPEED = 3;
const SLIDE_FRICTION = 4.5;
const ROLL_FRICTION = 0.55;
const TOPPLE_SPEED = 2.2;
const TOPPLE_FRICTION = 3;
const REST_SPEED = 0.5;
const FADE_SECONDS = 0.6;
const INHERIT = 0.45;
const TRAIL_INTERVAL = 0.06;
const TRAIL_SECONDS = 1.4;
const HALF_TURN = Math.PI;

const AIR = 0;
const GROUND = 1;
const REST = 2;

const TRAIL_NONE = 0;
const TRAIL_SOOT = 1;
const TRAIL_FIRE = 2;

interface Gib {
  live: boolean;
  shape: GibShape;
  mode: number;
  x: number;
  y: number;
  z: number;
  vx: number;
  vy: number;
  vz: number;
  yaw: number;
  pitch: number;
  roll: number;
  spinYaw: number;
  spinPitch: number;
  spinRoll: number;
  sx: number;
  sy: number;
  sz: number;
  r: number;
  g: number;
  b: number;
  clearance: number;
  restClearance: number;
  age: number;
  life: number;
  trail: number;
  trailTimer: number;
}

export interface GibBurst {
  kind: EnemyKind;
  x: number;
  z: number;
  heading: number;
  vx: number;
  vz: number;
  pushX: number;
  pushZ: number;
  power: number;
  burning: boolean;
}

function nearestHalfTurn(angle: number): number {
  return Math.round(angle / HALF_TURN) * HALF_TURN;
}

export class GibSystem {
  private readonly pool: Gib[] = [];
  private readonly batches: Record<GibShape, InstanceBatch>;
  private cursor = 0;

  constructor(scene: Scene, material: Material, shadows: ShadowGenerator) {
    const models = buildGibModels(scene);
    const glow = new StandardMaterial("spark", scene);
    glow.disableLighting = true;
    glow.emissiveColor = new Color3(1, 0.8, 0.36);
    const batches = {} as Record<GibShape, InstanceBatch>;
    for (const shape of SHAPES) {
      const mesh = models[shape];
      mesh.isPickable = false;
      if (shape === "spark") {
        mesh.material = glow;
      } else {
        mesh.material = material;
        mesh.receiveShadows = true;
        shadows.addShadowCaster(mesh);
      }
      batches[shape] = new InstanceBatch(mesh, MAX_GIBS, shape !== "wheel" && shape !== "spark");
    }
    this.batches = batches;
    for (let i = 0; i < MAX_GIBS; i++) {
      this.pool.push({
        live: false,
        shape: "box",
        mode: AIR,
        x: 0,
        y: 0,
        z: 0,
        vx: 0,
        vy: 0,
        vz: 0,
        yaw: 0,
        pitch: 0,
        roll: 0,
        spinYaw: 0,
        spinPitch: 0,
        spinRoll: 0,
        sx: 1,
        sy: 1,
        sz: 1,
        r: 1,
        g: 1,
        b: 1,
        clearance: 0,
        restClearance: 0,
        age: 0,
        life: 0,
        trail: TRAIL_NONE,
        trailTimer: 0,
      });
    }
  }

  clear(): void {
    for (const gib of this.pool) gib.live = false;
    this.render();
  }

  burst(spec: GibBurst): void {
    const fx = Math.sin(spec.heading);
    const fz = Math.cos(spec.heading);
    const base = groundHeight(spec.x, spec.z);
    const trailChance = spec.burning ? 0.5 : 0.16;
    for (const piece of RECIPES[spec.kind]) {
      const [ox, oy, oz] = piece.at;
      const offX = oz * fx + ox * fz;
      const offZ = oz * fz - ox * fx;
      const reach = Math.hypot(offX, offZ);
      const stray = Math.random() * TAU;
      const dirX = reach > 0.25 ? offX / reach : Math.sin(stray);
      const dirZ = reach > 0.25 ? offZ / reach : Math.cos(stray);
      const largest = Math.max(piece.size[0], piece.size[1], piece.size[2]);
      const heft = 1 / (0.75 + largest * 0.22);
      const fling = randRange(3.5, 10) * spec.power * heft;
      const gib = this.take();
      gib.shape = piece.shape;
      gib.mode = AIR;
      gib.x = spec.x + offX;
      gib.y = base + oy;
      gib.z = spec.z + offZ;
      gib.vx = spec.vx * INHERIT + spec.pushX + dirX * fling + randSigned(2.5);
      gib.vz = spec.vz * INHERIT + spec.pushZ + dirZ * fling + randSigned(2.5);
      gib.vy = randRange(7, 15) * Math.sqrt(spec.power) * heft + oy * 0.8;
      gib.yaw = spec.heading;
      gib.pitch = 0;
      gib.roll = 0;
      const spin = 15 * heft;
      gib.spinYaw = randSigned(spin);
      gib.spinPitch = randSigned(spin);
      gib.spinRoll = randSigned(spin);
      gib.sx = piece.size[0];
      gib.sy = piece.size[1];
      gib.sz = piece.size[2];
      const char = spec.burning ? randRange(0.3, 0.7) : randRange(0.82, 1);
      gib.r = piece.color.r * char;
      gib.g = piece.color.g * char;
      gib.b = piece.color.b * char;
      gib.restClearance = piece.shape === "wheel" ? piece.size[0] / 2 : piece.size[1] / 2;
      gib.clearance = piece.shape === "wheel" ? piece.size[1] / 2 : Math.max(gib.restClearance, Math.min(largest * 0.35, 0.9));
      gib.age = 0;
      gib.life = randRange(4.5, 7.5);
      gib.trail = Math.random() < trailChance ? (spec.burning && Math.random() < 0.6 ? TRAIL_FIRE : TRAIL_SOOT) : TRAIL_NONE;
      gib.trailTimer = Math.random() * TRAIL_INTERVAL;
    }
  }

  sparks(x: number, y: number, z: number, count: number, speed: number, vx: number, vz: number): void {
    for (let i = 0; i < count; i++) {
      const angle = Math.random() * TAU;
      const out = randRange(0.3, 1) * speed;
      const size = randRange(0.12, 0.26);
      const gib = this.take();
      gib.shape = "spark";
      gib.mode = AIR;
      gib.x = x;
      gib.y = y;
      gib.z = z;
      gib.vx = vx * INHERIT + Math.sin(angle) * out;
      gib.vz = vz * INHERIT + Math.cos(angle) * out;
      gib.vy = randRange(0.3, 1) * speed;
      gib.yaw = angle;
      gib.pitch = 0;
      gib.roll = 0;
      gib.spinYaw = randSigned(20);
      gib.spinPitch = randSigned(20);
      gib.spinRoll = randSigned(20);
      gib.sx = size;
      gib.sy = size;
      gib.sz = size * randRange(1, 2.5);
      gib.clearance = size / 2;
      gib.restClearance = size / 2;
      gib.age = 0;
      gib.life = randRange(0.35, 0.9);
      gib.trail = TRAIL_NONE;
    }
  }

  update(dt: number, smoke: SmokeSystem): void {
    for (const gib of this.pool) {
      if (!gib.live) continue;
      gib.age += dt;
      if (gib.age >= gib.life) {
        gib.live = false;
        continue;
      }
      if (gib.mode === AIR) this.fly(gib, dt, smoke);
      else if (gib.mode === GROUND) this.settle(gib, dt);
    }
    this.render();
  }

  private take(): Gib {
    const gib = this.pool[this.cursor];
    this.cursor = (this.cursor + 1) % MAX_GIBS;
    gib.live = true;
    return gib;
  }

  private fly(gib: Gib, dt: number, smoke: SmokeSystem): void {
    const drag = Math.exp(-AIR_DRAG * dt);
    gib.vy -= GRAVITY * dt;
    gib.vx *= drag;
    gib.vz *= drag;
    gib.x += gib.vx * dt;
    gib.y += gib.vy * dt;
    gib.z += gib.vz * dt;
    gib.yaw += gib.spinYaw * dt;
    gib.pitch += gib.spinPitch * dt;
    gib.roll += gib.spinRoll * dt;

    if (gib.trail !== TRAIL_NONE && gib.age < TRAIL_SECONDS) {
      gib.trailTimer -= dt;
      if (gib.trailTimer <= 0) {
        gib.trailTimer = TRAIL_INTERVAL;
        const fire = gib.trail === TRAIL_FIRE && gib.age < TRAIL_SECONDS * 0.6;
        smoke.emit(
          fire ? PUFF.fire : PUFF.soot,
          gib.x,
          gib.y,
          gib.z,
          gib.vx * 0.15,
          1,
          gib.vz * 0.15,
          randRange(0.3, 0.5),
          1.1,
          fire ? randRange(0.3, 0.5) : randRange(0.5, 0.9),
          0.7,
          fire ? 1.2 : 0.5,
        );
      }
    }

    const floor = groundHeight(gib.x, gib.z) + gib.clearance;
    if (gib.y > floor || gib.vy > 0) return;
    gib.y = floor;
    const impact = -gib.vy;
    const speed = Math.hypot(gib.vx, gib.vz);
    if (gib.shape === "spark") {
      gib.life = Math.min(gib.life, gib.age + 0.12);
    }
    if (impact > SETTLE_SPEED) {
      gib.vy = impact * (gib.shape === "wheel" ? WHEEL_BOUNCE : BOUNCE);
      gib.vx *= BOUNCE_KEEP;
      gib.vz *= BOUNCE_KEEP;
      const tumble = clamp(speed * 0.9 + impact * 0.5, 2, 14);
      gib.spinYaw = randSigned(tumble);
      gib.spinPitch = randSigned(tumble);
      gib.spinRoll = randSigned(tumble);
      return;
    }
    gib.vy = 0;
    gib.mode = GROUND;
  }

  private settle(gib: Gib, dt: number): void {
    const speed = Math.hypot(gib.vx, gib.vz);
    let friction = SLIDE_FRICTION;
    let done = speed < REST_SPEED;
    if (gib.shape === "wheel") {
      if (speed > TOPPLE_SPEED) {
        friction = ROLL_FRICTION;
        gib.yaw += wrapAngle(Math.atan2(gib.vx, gib.vz) - gib.yaw) * Math.min(1, 12 * dt);
        gib.pitch += (speed / gib.clearance) * dt;
        gib.roll = damp(gib.roll, nearestHalfTurn(gib.roll), 12, dt);
        done = false;
      } else {
        friction = TOPPLE_FRICTION;
        const lying = nearestHalfTurn(gib.roll - HALF_TURN / 2) + HALF_TURN / 2;
        gib.roll = damp(gib.roll, lying, 8, dt);
        gib.pitch = damp(gib.pitch, nearestHalfTurn(gib.pitch), 8, dt);
        gib.clearance = damp(gib.clearance, gib.restClearance, 8, dt);
        done = done && Math.abs(gib.roll - lying) < 0.04;
      }
    } else {
      const flatPitch = nearestHalfTurn(gib.pitch);
      const flatRoll = nearestHalfTurn(gib.roll);
      gib.pitch = damp(gib.pitch, flatPitch, 14, dt);
      gib.roll = damp(gib.roll, flatRoll, 14, dt);
      gib.spinYaw *= Math.exp(-3 * dt);
      gib.yaw += gib.spinYaw * dt;
      gib.clearance = damp(gib.clearance, gib.restClearance, 14, dt);
      done = done && Math.abs(gib.pitch - flatPitch) + Math.abs(gib.roll - flatRoll) < 0.04;
    }
    const slow = Math.exp(-friction * dt);
    gib.vx *= slow;
    gib.vz *= slow;
    gib.x += gib.vx * dt;
    gib.z += gib.vz * dt;
    gib.y = groundHeight(gib.x, gib.z) + gib.clearance;
    if (!done) return;
    gib.mode = REST;
    gib.clearance = gib.restClearance;
    gib.y = groundHeight(gib.x, gib.z) + gib.clearance;
  }

  private render(): void {
    for (const shape of SHAPES) this.batches[shape].begin();
    for (const gib of this.pool) {
      if (!gib.live) continue;
      const batch = this.batches[gib.shape];
      const fade = Math.min(1, (gib.life - gib.age) / FADE_SECONDS);
      const sink = gib.mode === AIR ? 0 : gib.clearance * (1 - fade);
      batch.push(gib.x, gib.y - sink, gib.z, gib.yaw, gib.pitch, gib.roll, gib.sx * fade, gib.sy * fade, gib.sz * fade);
      batch.tint(gib.r, gib.g, gib.b);
    }
    for (const shape of SHAPES) this.batches[shape].commit();
  }
}

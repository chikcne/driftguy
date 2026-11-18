import { type Camera, type Color3, type Mesh, type Scene, Vector3 } from "@babylonjs/core";
import { saturate, smoothstep, TAU } from "./math";
import { type PuffLook, puffHeight, SmokeVolume, type VolumeView } from "./smokeVolume";
import { groundHeight } from "./terrain";

export const PUFF = {
  white: 0,
  ash: 1,
  ember: 2,
  toxic: 3,
  dust: 4,
  fire: 5,
  soot: 6,
} as const;

export type PuffKind = (typeof PUFF)[keyof typeof PUFF];

export const DAMAGING_KINDS = 4;

const LOOKS: PuffLook[] = [
  { color: [0.98, 0.97, 0.95], glow: 0 },
  { color: [0.5, 0.51, 0.55], glow: 0 },
  { color: [0.95, 0.34, 0.24], glow: 0.18 },
  { color: [0.58, 0.86, 0.36], glow: 0.12 },
  { color: [0.98, 0.86, 0.7], glow: 0 },
  { color: [1.0, 0.6, 0.18], glow: 0.95 },
  { color: [0.16, 0.14, 0.15], glow: 0 },
];

const MAX_PUFFS = 6000;
const GRID_CELL = 4;
const GRID_SPAN = 128;
const GRID_HALF = GRID_SPAN / 2;
const SAMPLE_REACH_CELLS = 2;
const MAX_RADIUS = SAMPLE_REACH_CELLS * GRID_CELL;
const AIR_DRAG = 2.2;
const JET_DRAG = 0.35;
const HEAT_FADE_SECONDS = 1.5;
const HOT_RISE_SPEED = 2.4;
const COOL_RISE_SPEED = 0.3;
const LOFT_MIN = 0.6;
const LOFT_SPREAD = 0.9;
const CEILING_HEIGHT = 10;
const GROUND_HUG = 0.55;
const WAKE_PULL = 4;
const WAKE_CARRY = 0.6;
const WAKE_LEAD = 2;
const WAKE_HALF_WIDTH = 1.8;
const WAKE_FLARE = 0.22;
const WAKE_INFLOW = 0.25;
const BOW_PUSH = 0.35;
const WAKE_UPWASH = 0.08;
const WAKE_CHURN = 3;
const VIGOR_FADE_SECONDS = 1.8;
const VIGOR_MAX = 1.6;
const BILLOW_WAVENUMBER = 0.85;
const BILLOW_HEIGHT_WAVENUMBER = 0.57;
const BILLOW_ROLL = BILLOW_HEIGHT_WAVENUMBER / BILLOW_WAVENUMBER;
const BILLOW_CALM = 0.45;
const BILLOW_GAIN = 2.6;
const EDDY_WAVENUMBER = 2.2;
const EDDY_SHEAR = 1.3;
const EDDY_CALM = 0.2;
const EDDY_GAIN = 1.8;
const WAVE_SIZE = 4096;
const WAVE_MASK = WAVE_SIZE - 1;
const WAVE_QUARTER = WAVE_SIZE / 4;
const WAVE_SCALE = WAVE_SIZE / TAU;
const WAVE = new Float32Array(WAVE_SIZE);
for (let i = 0; i < WAVE_SIZE; i++) WAVE[i] = Math.sin((i / WAVE_SIZE) * TAU);
const DILUTION_EXPONENT = 0.8;
const FLOOR_REFRESH_MASK = 3;

export interface SmokeEnvironment {
  time: number;
  carX: number;
  carZ: number;
  carVx: number;
  carVz: number;
  carFx: number;
  carFz: number;
  fanPower: number;
  fanRange: number;
  cameraForward: Vector3;
  cameraPosition: Vector3;
  sunDirection: Vector3;
}

export interface SmokeSample {
  total: number;
  byKind: Float32Array;
}

export function createSmokeSample(): SmokeSample {
  return { total: 0, byKind: new Float32Array(DAMAGING_KINDS) };
}

export class SmokeSystem {
  count = 0;
  readonly px = new Float32Array(MAX_PUFFS);
  readonly py = new Float32Array(MAX_PUFFS);
  readonly pz = new Float32Array(MAX_PUFFS);
  private readonly vx = new Float32Array(MAX_PUFFS);
  private readonly vy = new Float32Array(MAX_PUFFS);
  private readonly vz = new Float32Array(MAX_PUFFS);
  readonly age = new Float32Array(MAX_PUFFS);
  readonly life = new Float32Array(MAX_PUFFS);
  private readonly startRadius = new Float32Array(MAX_PUFFS);
  private readonly growth = new Float32Array(MAX_PUFFS);
  readonly radius = new Float32Array(MAX_PUFFS);
  private readonly density = new Float32Array(MAX_PUFFS);
  readonly strength = new Float32Array(MAX_PUFFS);
  private readonly heat = new Float32Array(MAX_PUFFS);
  private readonly vigor = new Float32Array(MAX_PUFFS);
  readonly floor = new Float32Array(MAX_PUFFS);
  readonly kind = new Uint8Array(MAX_PUFFS);

  private readonly gridHead = new Int32Array(GRID_SPAN * GRID_SPAN);
  private readonly gridNext = new Int32Array(MAX_PUFFS);
  private gridOriginX = 0;
  private gridOriginZ = 0;

  private readonly volume: SmokeVolume;
  private readonly view: VolumeView;
  private frame = 0;

  constructor(scene: Scene, camera: Camera, fogColor: Color3, fogStart: number, fogEnd: number) {
    this.volume = new SmokeVolume(scene, camera, LOOKS, fogColor, fogStart, fogEnd);
    this.view = { focusX: 0, focusY: 0, focusZ: 0, forwardX: 0, forwardZ: 1, sunDirection: Vector3.Down(), windX: 0, windZ: 0, carX: 0, carZ: 0 };
  }

  clear(): void {
    this.count = 0;
  }

  revealInside(meshes: Mesh[]): void {
    this.volume.revealInside(meshes);
  }

  emit(
    kind: PuffKind,
    x: number,
    y: number,
    z: number,
    vx: number,
    vy: number,
    vz: number,
    radius: number,
    growth: number,
    life: number,
    density: number,
    heat: number,
  ): void {
    let i = this.count;
    if (i >= MAX_PUFFS) {
      i = Math.floor(Math.random() * MAX_PUFFS);
    } else {
      this.count++;
    }
    this.kind[i] = kind;
    this.px[i] = x;
    this.py[i] = y;
    this.pz[i] = z;
    this.vx[i] = vx;
    this.vy[i] = vy;
    this.vz[i] = vz;
    this.age[i] = 0;
    this.life[i] = life;
    this.startRadius[i] = radius;
    this.radius[i] = radius;
    this.growth[i] = growth;
    this.density[i] = density;
    this.strength[i] = 0;
    this.heat[i] = heat * (LOFT_MIN + LOFT_SPREAD * Math.random() * Math.random());
    this.vigor[i] = Math.min(VIGOR_MAX, 0.35 + Math.hypot(vx, vy, vz) * 0.12);
    this.floor[i] = groundHeight(x, z);
  }

  update(dt: number, env: SmokeEnvironment): void {
    this.frame++;
    const t = env.time;
    const prevailingAngle = t * 0.05;
    const prevailingX = Math.cos(prevailingAngle) * 1.1;
    const prevailingZ = Math.sin(prevailingAngle) * 1.1;
    const heatKeep = Math.exp(-dt / HEAT_FADE_SECONDS);
    const vigorKeep = Math.exp(-dt / VIGOR_FADE_SECONDS);

    const carSpeed = Math.hypot(env.carVx, env.carVz);
    const moving = carSpeed > 0.5;
    const travelX = moving ? env.carVx / carSpeed : env.carFx;
    const travelZ = moving ? env.carVz / carSpeed : env.carFz;
    const wakeGate = saturate(carSpeed / 6);
    const wakeLength = Math.min(12, 2.5 + carSpeed * 0.4);
    const wakeReach = wakeLength + WAKE_LEAD;
    const wakeReachSq = wakeGate > 0 ? wakeReach * wakeReach : 0;
    const fanReachSq = env.fanPower > 0 ? env.fanRange * env.fanRange : 0;
    const nearSq = Math.max(wakeReachSq, fanReachSq);

    const windPhase1X = t * 0.25;
    const windPhase1Z = -t * 0.21;
    const windPhase2X = -t * 0.6;
    const windPhase2Z = t * 0.5;
    const billowPhaseX = t * 0.9;
    const billowPhaseZ = -t * 0.7;
    const eddyPhaseX = -t * 1.9;
    const eddyPhaseZ = t * 1.6;

    for (let i = this.count - 1; i >= 0; i--) {
      const age = this.age[i] + dt;
      if (age >= this.life[i]) {
        this.removeAt(i);
        continue;
      }
      this.age[i] = age;
      let x = this.px[i];
      let z = this.pz[i];
      const floor = this.floor[i];
      const height = this.py[i] - floor;
      const radius = Math.min(MAX_RADIUS, this.startRadius[i] + this.growth[i] * Math.sqrt(age));
      let vigor = this.vigor[i] * vigorKeep;
      const warmth = this.heat[i] * heatKeep;
      this.heat[i] = warmth;

      const a1 = ((x * 0.07 + windPhase1X) * WAVE_SCALE) | 0;
      const b1 = ((z * 0.07 + windPhase1Z) * WAVE_SCALE) | 0;
      const a2 = ((x * 0.23 + windPhase2X) * WAVE_SCALE) | 0;
      const b2 = ((z * 0.23 + windPhase2Z) * WAVE_SCALE) | 0;
      let flowX = prevailingX - WAVE[a1 & WAVE_MASK] * WAVE[b1 & WAVE_MASK] - 0.8 * WAVE[a2 & WAVE_MASK] * WAVE[b2 & WAVE_MASK];
      let flowZ =
        prevailingZ -
        WAVE[(a1 + WAVE_QUARTER) & WAVE_MASK] * WAVE[(b1 + WAVE_QUARTER) & WAVE_MASK] -
        0.8 * WAVE[(a2 + WAVE_QUARTER) & WAVE_MASK] * WAVE[(b2 + WAVE_QUARTER) & WAVE_MASK];

      const a3 = ((x * BILLOW_WAVENUMBER + billowPhaseX) * WAVE_SCALE) | 0;
      const b3 = ((z * BILLOW_WAVENUMBER + billowPhaseZ) * WAVE_SCALE) | 0;
      const c3 = (height * BILLOW_HEIGHT_WAVENUMBER * WAVE_SCALE) | 0;
      const sinA = WAVE[a3 & WAVE_MASK];
      const cosA = WAVE[(a3 + WAVE_QUARTER) & WAVE_MASK];
      const sinB = WAVE[b3 & WAVE_MASK];
      const cosB = WAVE[(b3 + WAVE_QUARTER) & WAVE_MASK];
      const sinC = WAVE[c3 & WAVE_MASK];
      const cosC = WAVE[(c3 + WAVE_QUARTER) & WAVE_MASK];
      const billow = BILLOW_CALM + BILLOW_GAIN * vigor;
      flowX += billow * (BILLOW_ROLL * cosA * cosC - sinA * sinB);
      flowZ += billow * (BILLOW_ROLL * sinB * cosC - cosA * cosB);
      const flowY = COOL_RISE_SPEED + HOT_RISE_SPEED * warmth + billow * (sinA - cosB) * sinC;

      const a4 = ((x * EDDY_WAVENUMBER + height * EDDY_SHEAR + eddyPhaseX) * WAVE_SCALE) | 0;
      const b4 = ((z * EDDY_WAVENUMBER + eddyPhaseZ) * WAVE_SCALE) | 0;
      const eddy = (EDDY_CALM + EDDY_GAIN * vigor) / (1 + 0.35 * radius);
      flowX -= eddy * WAVE[a4 & WAVE_MASK] * WAVE[b4 & WAVE_MASK];
      flowZ -= eddy * WAVE[(a4 + WAVE_QUARTER) & WAVE_MASK] * WAVE[(b4 + WAVE_QUARTER) & WAVE_MASK];

      let vx = this.vx[i];
      let vy = this.vy[i];
      let vz = this.vz[i];
      const slipX = flowX - vx;
      const slipY = flowY - vy;
      const slipZ = flowZ - vz;
      const dragStep = (AIR_DRAG + JET_DRAG * Math.sqrt(slipX * slipX + slipY * slipY + slipZ * slipZ)) * dt;
      const follow = dragStep / (1 + dragStep);
      vx += slipX * follow;
      vy += slipY * follow;
      vz += slipZ * follow;

      const dx = x - env.carX;
      const dz = z - env.carZ;
      const distSq = dx * dx + dz * dz;
      if (distSq < nearSq) {
        if (distSq < wakeReachSq) {
          const behind = -(dx * travelX + dz * travelZ);
          const across = dx * travelZ - dz * travelX;
          const halfWidth = WAKE_HALF_WIDTH + (behind > 0 ? behind * WAKE_FLARE : 0);
          const offset = across / halfWidth;
          const core = 1 - offset * offset;
          const taper = behind < 0 ? 1 + behind / WAKE_LEAD : 1 - behind / wakeLength;
          if (core > 0 && taper > 0) {
            const hold = wakeGate * core * taper;
            const pull = Math.min(1, hold * WAKE_PULL * dt);
            const sideways = (behind < 0 ? BOW_PUSH * (across >= 0 ? 1 : -1) : behind > 1 ? -WAKE_INFLOW * offset : 0) * carSpeed * pull;
            vx += (env.carVx * WAKE_CARRY - vx) * pull + travelZ * sideways;
            vz += (env.carVz * WAKE_CARRY - vz) * pull - travelX * sideways;
            vy += carSpeed * WAKE_UPWASH * pull;
            vigor = Math.min(VIGOR_MAX, vigor + hold * WAKE_CHURN * dt);
          }
        }
        if (distSq < fanReachSq && distSq > 0.01) {
          const dist = Math.sqrt(distSq);
          const behind = saturate(0.3 - (dx * env.carFx + dz * env.carFz) / dist);
          const push = env.fanPower * (1 - dist / env.fanRange) * (0.4 + 0.6 * behind) * dt;
          vx += (dx / dist) * push;
          vz += (dz / dist) * push;
        }
      }

      x += vx * dt;
      z += vz * dt;
      if (((i + this.frame) & FLOOR_REFRESH_MASK) === 0) this.floor[i] = groundHeight(x, z);
      let y = this.py[i] + vy * dt;
      const ceiling = floor + CEILING_HEIGHT;
      if (y > ceiling) vy -= (y - ceiling) * 3 * dt;
      const rest = floor + puffHeight(radius) * GROUND_HUG;
      if (y < rest) {
        y = rest;
        if (vy < 0) vy = 0;
      }

      const lifeFraction = age / this.life[i];
      const fadeIn = saturate(age / 0.12);
      const fadeOut = 1 - smoothstep(0.5, 1, lifeFraction);
      this.strength[i] = this.density[i] * Math.pow(this.startRadius[i] / radius, DILUTION_EXPONENT) * fadeIn * fadeOut;
      this.radius[i] = radius;
      this.px[i] = x;
      this.py[i] = y;
      this.pz[i] = z;
      this.vx[i] = vx;
      this.vy[i] = vy;
      this.vz[i] = vz;
      this.vigor[i] = vigor;
    }

    this.rebuildGrid(env.carX, env.carZ);

    const view = this.view;
    const forward = env.cameraForward;
    const focusY = groundHeight(env.carX, env.carZ);
    const reach = forward.y < -0.05 ? (env.cameraPosition.y - focusY) / -forward.y : 0;
    const flat = Math.hypot(forward.x, forward.z) || 1;
    view.focusX = env.cameraPosition.x + forward.x * reach;
    view.focusY = focusY;
    view.focusZ = env.cameraPosition.z + forward.z * reach;
    view.forwardX = forward.x / flat;
    view.forwardZ = forward.z / flat;
    view.sunDirection = env.sunDirection;
    view.windX = prevailingX;
    view.windZ = prevailingZ;
    view.carX = env.carX;
    view.carZ = env.carZ;
    this.volume.update(this, view, dt);
  }

  sample(x: number, z: number, out: SmokeSample, stirVx: number, stirVz: number, stirGain: number): SmokeSample {
    out.total = 0;
    out.byKind.fill(0);
    const cx = Math.floor(x / GRID_CELL) - this.gridOriginX;
    const cz = Math.floor(z / GRID_CELL) - this.gridOriginZ;
    const minX = Math.max(0, cx - SAMPLE_REACH_CELLS);
    const maxX = Math.min(GRID_SPAN - 1, cx + SAMPLE_REACH_CELLS);
    const minZ = Math.max(0, cz - SAMPLE_REACH_CELLS);
    const maxZ = Math.min(GRID_SPAN - 1, cz + SAMPLE_REACH_CELLS);
    for (let gz = minZ; gz <= maxZ; gz++) {
      for (let gx = minX; gx <= maxX; gx++) {
        let i = this.gridHead[gz * GRID_SPAN + gx];
        while (i >= 0) {
          const dx = this.px[i] - x;
          const dz = this.pz[i] - z;
          const r = this.radius[i];
          const distSq = dx * dx + dz * dz;
          if (distSq < r * r) {
            const contribution = this.strength[i] * (1 - distSq / (r * r));
            out.total += contribution;
            out.byKind[this.kind[i]] += contribution;
            if (stirGain > 0) {
              const churn = Math.hypot(stirVx - this.vx[i], stirVz - this.vz[i]) * stirGain;
              this.vx[i] += (stirVx - this.vx[i]) * stirGain;
              this.vz[i] += (stirVz - this.vz[i]) * stirGain;
              this.vigor[i] = Math.min(VIGOR_MAX, this.vigor[i] + churn * 0.12);
            }
          }
          i = this.gridNext[i];
        }
      }
    }
    return out;
  }

  shockwave(x: number, z: number, reach: number, speed: number): void {
    for (let i = 0; i < this.count; i++) {
      const dx = this.px[i] - x;
      const dz = this.pz[i] - z;
      const distSq = dx * dx + dz * dz;
      if (distSq > reach * reach || distSq < 0.01) continue;
      const dist = Math.sqrt(distSq);
      const kick = speed * (1 - dist / reach);
      this.vx[i] += (dx / dist) * kick;
      this.vz[i] += (dz / dist) * kick;
      this.vy[i] += kick * 0.25;
      this.vigor[i] = VIGOR_MAX;
    }
  }

  private removeAt(i: number): void {
    const last = --this.count;
    if (i === last) return;
    this.px[i] = this.px[last];
    this.py[i] = this.py[last];
    this.pz[i] = this.pz[last];
    this.vx[i] = this.vx[last];
    this.vy[i] = this.vy[last];
    this.vz[i] = this.vz[last];
    this.age[i] = this.age[last];
    this.life[i] = this.life[last];
    this.startRadius[i] = this.startRadius[last];
    this.growth[i] = this.growth[last];
    this.radius[i] = this.radius[last];
    this.density[i] = this.density[last];
    this.strength[i] = this.strength[last];
    this.heat[i] = this.heat[last];
    this.vigor[i] = this.vigor[last];
    this.floor[i] = this.floor[last];
    this.kind[i] = this.kind[last];
  }

  private rebuildGrid(centerX: number, centerZ: number): void {
    this.gridHead.fill(-1);
    this.gridOriginX = Math.floor(centerX / GRID_CELL) - GRID_HALF;
    this.gridOriginZ = Math.floor(centerZ / GRID_CELL) - GRID_HALF;
    for (let i = 0; i < this.count; i++) {
      if (this.kind[i] >= DAMAGING_KINDS) continue;
      const gx = Math.floor(this.px[i] / GRID_CELL) - this.gridOriginX;
      const gz = Math.floor(this.pz[i] / GRID_CELL) - this.gridOriginZ;
      if (gx < 0 || gz < 0 || gx >= GRID_SPAN || gz >= GRID_SPAN) continue;
      const cell = gz * GRID_SPAN + gx;
      this.gridNext[i] = this.gridHead[cell];
      this.gridHead[cell] = i;
    }
  }
}

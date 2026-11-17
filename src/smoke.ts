import { Buffer, Color3, Effect, Mesh, RawTexture, Scene, ShaderMaterial, Texture, Vector2, Vector3, VertexBuffer } from "@babylonjs/core";
import { saturate, smoothstep, TAU } from "./math";
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

interface PuffLook {
  color: [number, number, number];
  glow: number;
}

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
const HEAT_FADE_SECONDS = 1.1;
const HOT_RISE_SPEED = 2.6;
const COOL_RISE_SPEED = 0.3;
const CEILING_HEIGHT = 4.2;
const GROUND_HUG = 0.3;
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
const BILLOW_SPIN = 0.8;
const EDDY_SPIN = 1.1;
const DEPTH_BUCKETS = 2048;
const WAVE_SIZE = 4096;
const WAVE_MASK = WAVE_SIZE - 1;
const WAVE_QUARTER = WAVE_SIZE / 4;
const WAVE_SCALE = WAVE_SIZE / TAU;
const WAVE = new Float32Array(WAVE_SIZE);
for (let i = 0; i < WAVE_SIZE; i++) WAVE[i] = Math.sin((i / WAVE_SIZE) * TAU);
const DILUTION_EXPONENT = 0.8;
const TILE_SIZE = 128;
const ATLAS_TILES = 2;
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
  cameraRight: Vector3;
  cameraUp: Vector3;
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

function valueNoise(x: number, y: number, seed: number): number {
  const ix = Math.floor(x);
  const iy = Math.floor(y);
  const fx = x - ix;
  const fy = y - iy;
  const sx = fx * fx * (3 - 2 * fx);
  const sy = fy * fy * (3 - 2 * fy);
  const corner = (cx: number, cy: number): number => {
    let h = (Math.imul(cx, 374761393) + Math.imul(cy, 668265263) + Math.imul(seed, 2147483647)) | 0;
    h = Math.imul(h ^ (h >>> 13), 1274126177);
    return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
  };
  const top = corner(ix, iy) + (corner(ix + 1, iy) - corner(ix, iy)) * sx;
  const bottom = corner(ix, iy + 1) + (corner(ix + 1, iy + 1) - corner(ix, iy + 1)) * sx;
  return top + (bottom - top) * sy;
}

function fbm(x: number, y: number, seed: number): number {
  return valueNoise(x, y, seed) * 0.55 + valueNoise(x * 2.1, y * 2.1, seed + 17) * 0.3 + valueNoise(x * 4.3, y * 4.3, seed + 31) * 0.15;
}

function buildPuffAtlas(): Uint8Array {
  const size = TILE_SIZE * ATLAS_TILES;
  const data = new Uint8Array(size * size * 4);
  const gradientStep = 0.05;
  for (let tile = 0; tile < ATLAS_TILES * ATLAS_TILES; tile++) {
    const originX = (tile % ATLAS_TILES) * TILE_SIZE;
    const originY = Math.floor(tile / ATLAS_TILES) * TILE_SIZE;
    const seed = 5 + tile * 13;
    for (let y = 0; y < TILE_SIZE; y++) {
      for (let x = 0; x < TILE_SIZE; x++) {
        const u = ((x + 0.5) / TILE_SIZE) * 2 - 1;
        const v = ((y + 0.5) / TILE_SIZE) * 2 - 1;
        const d = Math.hypot(u, v);
        const lump = (px: number, py: number): number => fbm(px * 2.3 + 9, py * 2.3 + 9, seed);
        const here = lump(u, v);
        const shape = d + (here - 0.5) * 0.6;
        const alpha = (1 - smoothstep(0.4, 0.96, shape)) * (1 - smoothstep(0.88, 1, d));
        const detail = fbm(u * 4.5 + 3, v * 4.5 + 3, seed + 101);
        let nx = u * 0.85 - ((lump(u + gradientStep, v) - lump(u - gradientStep, v)) / gradientStep) * 0.28;
        let ny = v * 0.85 - ((lump(u, v + gradientStep) - lump(u, v - gradientStep)) / gradientStep) * 0.28;
        const length = Math.hypot(nx, ny);
        if (length > 0.97) {
          nx *= 0.97 / length;
          ny *= 0.97 / length;
        }
        const offset = ((originY + y) * size + originX + x) * 4;
        data[offset] = Math.round((nx * 0.5 + 0.5) * 255);
        data[offset + 1] = Math.round((ny * 0.5 + 0.5) * 255);
        data[offset + 2] = Math.round(detail * 255);
        data[offset + 3] = Math.round(alpha * 255);
      }
    }
  }
  return data;
}

Effect.ShadersStore["puffVertexShader"] = `
precision highp float;
attribute vec3 position;
attribute vec2 uv;
attribute vec4 color;
attribute vec4 params;
uniform mat4 viewProjection;
uniform vec3 camRight;
uniform vec3 camUp;
uniform vec3 camPos;
uniform vec2 fogRange;
varying vec2 vUV;
varying vec4 vColor;
varying vec4 vMisc;
varying float vFog;
void main() {
  float c = cos(params.y);
  float s = sin(params.y);
  vec2 corner = vec2(uv.x * c - uv.y * s, uv.x * s + uv.y * c);
  vec3 world = position + (camRight * corner.x + camUp * corner.y) * params.x;
  gl_Position = viewProjection * vec4(world, 1.0);
  float tile = floor(params.z);
  vec2 tileOrigin = vec2(mod(tile, 2.0), floor(tile / 2.0)) * 0.5;
  vUV = tileOrigin + (uv * 0.5 + 0.5) * 0.5;
  vColor = color;
  vMisc = vec4(c, s, params.w, fract(params.z) * 2.0);
  vFog = clamp((distance(world, camPos) - fogRange.x) / (fogRange.y - fogRange.x), 0.0, 1.0);
}`;

Effect.ShadersStore["puffFragmentShader"] = `
precision highp float;
uniform sampler2D puffTex;
uniform vec3 lightView;
uniform vec3 shadeColor;
uniform vec3 fogColor;
varying vec2 vUV;
varying vec4 vColor;
varying vec4 vMisc;
varying float vFog;
void main() {
  vec4 t = texture2D(puffTex, vUV);
  float body = t.a * (0.55 + 0.9 * t.b);
  float edge = vMisc.z * 0.36;
  float alpha = smoothstep(edge, edge + 0.4, body) * vColor.a;
  if (alpha < 0.004) discard;
  vec2 n = t.rg * 2.0 - 1.0;
  n = vec2(n.x * vMisc.x - n.y * vMisc.y, n.x * vMisc.y + n.y * vMisc.x);
  float nz = sqrt(max(0.0, 1.0 - dot(n, n)));
  float lit = clamp(dot(vec3(n, nz), lightView) * 0.6 + 0.5, 0.0, 1.0);
  vec3 col = vColor.rgb * mix(shadeColor, vec3(1.0), lit);
  col = mix(col, vColor.rgb * 1.5, vMisc.w);
  col = mix(col, fogColor, vFog);
  gl_FragColor = vec4(pow(col, vec3(2.2)), alpha);
}`;

export class SmokeSystem {
  count = 0;
  private readonly px = new Float32Array(MAX_PUFFS);
  private readonly py = new Float32Array(MAX_PUFFS);
  private readonly pz = new Float32Array(MAX_PUFFS);
  private readonly vx = new Float32Array(MAX_PUFFS);
  private readonly vy = new Float32Array(MAX_PUFFS);
  private readonly vz = new Float32Array(MAX_PUFFS);
  private readonly age = new Float32Array(MAX_PUFFS);
  private readonly life = new Float32Array(MAX_PUFFS);
  private readonly startRadius = new Float32Array(MAX_PUFFS);
  private readonly growth = new Float32Array(MAX_PUFFS);
  private readonly radius = new Float32Array(MAX_PUFFS);
  private readonly density = new Float32Array(MAX_PUFFS);
  private readonly strength = new Float32Array(MAX_PUFFS);
  private readonly heat = new Float32Array(MAX_PUFFS);
  private readonly vigor = new Float32Array(MAX_PUFFS);
  private readonly floor = new Float32Array(MAX_PUFFS);
  private readonly spin = new Float32Array(MAX_PUFFS);
  private readonly spinRate = new Float32Array(MAX_PUFFS);
  private readonly tile = new Uint8Array(MAX_PUFFS);
  private readonly kind = new Uint8Array(MAX_PUFFS);

  private readonly gridHead = new Int32Array(GRID_SPAN * GRID_SPAN);
  private readonly gridNext = new Int32Array(MAX_PUFFS);
  private gridOriginX = 0;
  private gridOriginZ = 0;

  private readonly depth = new Float32Array(MAX_PUFFS);
  private readonly depthKey = new Uint16Array(MAX_PUFFS);
  private readonly bucketStart = new Uint32Array(DEPTH_BUCKETS + 1);
  private readonly order = new Uint16Array(MAX_PUFFS);
  private readonly positions = new Float32Array(MAX_PUFFS * 12);
  private readonly colors = new Float32Array(MAX_PUFFS * 16);
  private readonly params = new Float32Array(MAX_PUFFS * 16);
  private readonly mesh: Mesh;
  private readonly positionBuffer: Buffer;
  private readonly colorBuffer: Buffer;
  private readonly paramBuffer: Buffer;
  private readonly material: ShaderMaterial;
  private readonly lightView = new Vector3();
  private frame = 0;

  constructor(scene: Scene, fogColor: Color3, fogStart: number, fogEnd: number) {
    const uvs = new Float32Array(MAX_PUFFS * 8);
    const indices = new Uint32Array(MAX_PUFFS * 6);
    const corners = [-1, -1, 1, -1, 1, 1, -1, 1];
    for (let i = 0; i < MAX_PUFFS; i++) {
      uvs.set(corners, i * 8);
      indices.set([i * 4, i * 4 + 1, i * 4 + 2, i * 4, i * 4 + 2, i * 4 + 3], i * 6);
    }
    this.mesh = new Mesh("smoke", scene);
    const engine = scene.getEngine();
    this.positionBuffer = new Buffer(engine, this.positions, true, 3);
    this.colorBuffer = new Buffer(engine, this.colors, true, 4);
    this.paramBuffer = new Buffer(engine, this.params, true, 4);
    this.mesh.setVerticesBuffer(this.positionBuffer.createVertexBuffer(VertexBuffer.PositionKind, 0, 3));
    this.mesh.setVerticesData(VertexBuffer.UVKind, uvs, false);
    this.mesh.setVerticesBuffer(this.colorBuffer.createVertexBuffer(VertexBuffer.ColorKind, 0, 4));
    this.mesh.setVerticesBuffer(this.paramBuffer.createVertexBuffer("params", 0, 4));
    this.mesh.setIndices(indices);
    this.mesh.alwaysSelectAsActiveMesh = true;
    this.mesh.isPickable = false;
    this.mesh.alphaIndex = 10;
    this.mesh.subMeshes[0].setBoundingInfo(this.mesh.getBoundingInfo());

    const atlasSize = TILE_SIZE * ATLAS_TILES;
    const atlas = RawTexture.CreateRGBATexture(buildPuffAtlas(), atlasSize, atlasSize, scene, true, false, Texture.TRILINEAR_SAMPLINGMODE);
    atlas.wrapU = Texture.CLAMP_ADDRESSMODE;
    atlas.wrapV = Texture.CLAMP_ADDRESSMODE;

    this.material = new ShaderMaterial(
      "puff",
      scene,
      { vertex: "puff", fragment: "puff" },
      {
        attributes: ["position", "uv", "color", "params"],
        uniforms: ["viewProjection", "camRight", "camUp", "camPos", "fogRange", "fogColor", "lightView", "shadeColor"],
        samplers: ["puffTex"],
        needAlphaBlending: true,
      },
    );
    this.material.backFaceCulling = false;
    this.material.disableDepthWrite = true;
    this.material.setTexture("puffTex", atlas);
    this.material.setColor3("fogColor", fogColor);
    this.material.setColor3("shadeColor", new Color3(0.56, 0.5, 0.6));
    this.material.setVector2("fogRange", new Vector2(fogStart, fogEnd));
    this.mesh.material = this.material;
  }

  clear(): void {
    this.count = 0;
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
    this.heat[i] = heat;
    this.vigor[i] = Math.min(VIGOR_MAX, 0.35 + Math.hypot(vx, vy, vz) * 0.12);
    this.floor[i] = groundHeight(x, z);
    this.spin[i] = Math.random() * Math.PI * 2;
    this.spinRate[i] = (Math.random() - 0.5) * 0.5;
    this.tile[i] = Math.floor(Math.random() * ATLAS_TILES * ATLAS_TILES);
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
      const sinE = WAVE[a4 & WAVE_MASK];
      const cosF = WAVE[(b4 + WAVE_QUARTER) & WAVE_MASK];
      const eddy = (EDDY_CALM + EDDY_GAIN * vigor) / (1 + 0.35 * radius);
      flowX -= eddy * sinE * WAVE[b4 & WAVE_MASK];
      flowZ -= eddy * WAVE[(a4 + WAVE_QUARTER) & WAVE_MASK] * cosF;

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
      const ceiling = floor + CEILING_HEIGHT + radius * 0.4;
      if (y > ceiling) vy -= (y - ceiling) * 3 * dt;
      const rest = floor + radius * GROUND_HUG;
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
      this.spin[i] += (this.spinRate[i] + BILLOW_SPIN * billow * sinA * cosB + EDDY_SPIN * eddy * sinE * cosF) * dt;
    }

    this.rebuildGrid(env.carX, env.carZ);
    this.writeBuffers(env);
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
    this.spin[i] = this.spin[last];
    this.spinRate[i] = this.spinRate[last];
    this.tile[i] = this.tile[last];
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

  private writeBuffers(env: SmokeEnvironment): void {
    const n = this.count;
    const forward = env.cameraForward;
    const depth = this.depth;
    let nearest = Infinity;
    let farthest = -Infinity;
    for (let i = 0; i < n; i++) {
      const d = this.px[i] * forward.x + this.py[i] * forward.y + this.pz[i] * forward.z;
      depth[i] = d;
      if (d < nearest) nearest = d;
      if (d > farthest) farthest = d;
    }
    const bucketStart = this.bucketStart;
    const depthKey = this.depthKey;
    const sorted = this.order;
    const bucketScale = farthest > nearest ? (DEPTH_BUCKETS - 1) / (farthest - nearest) : 0;
    bucketStart.fill(0);
    for (let i = 0; i < n; i++) {
      const key = ((farthest - depth[i]) * bucketScale) | 0;
      depthKey[i] = key;
      bucketStart[key + 1]++;
    }
    for (let bucket = 0; bucket < DEPTH_BUCKETS; bucket++) bucketStart[bucket + 1] += bucketStart[bucket];
    for (let i = 0; i < n; i++) sorted[bucketStart[depthKey[i]]++] = i;

    const positions = this.positions;
    const colors = this.colors;
    const params = this.params;
    for (let slot = 0; slot < n; slot++) {
      const i = sorted[slot];
      const look = LOOKS[this.kind[i]];
      const erosion = this.age[i] / this.life[i];
      const alpha = Math.min(1, this.strength[i]);
      const tileAndGlow = this.tile[i] + look.glow * 0.49 * (1 - erosion);
      for (let corner = 0; corner < 4; corner++) {
        const p = (slot * 4 + corner) * 3;
        const q = (slot * 4 + corner) * 4;
        positions[p] = this.px[i];
        positions[p + 1] = this.py[i];
        positions[p + 2] = this.pz[i];
        colors[q] = look.color[0];
        colors[q + 1] = look.color[1];
        colors[q + 2] = look.color[2];
        colors[q + 3] = alpha;
        params[q] = this.radius[i];
        params[q + 1] = this.spin[i];
        params[q + 2] = tileAndGlow;
        params[q + 3] = erosion;
      }
    }

    const vertexCount = n * 4;
    if (vertexCount > 0) {
      this.positionBuffer.updateDirectly(positions, 0, vertexCount);
      this.colorBuffer.updateDirectly(colors, 0, vertexCount);
      this.paramBuffer.updateDirectly(params, 0, vertexCount);
    }
    const subMesh = this.mesh.subMeshes[0];
    if (subMesh) subMesh.indexCount = n * 6;
    this.mesh.setEnabled(n > 0);

    const sun = env.sunDirection;
    this.lightView.set(
      -Vector3.Dot(sun, env.cameraRight),
      -Vector3.Dot(sun, env.cameraUp),
      Vector3.Dot(sun, env.cameraForward),
    );
    this.lightView.normalize();
    this.material.setVector3("lightView", this.lightView);
    this.material.setVector3("camRight", env.cameraRight);
    this.material.setVector3("camUp", env.cameraUp);
    this.material.setVector3("camPos", env.cameraPosition);
  }
}

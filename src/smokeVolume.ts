import { Camera, Color3, Color4, Constants, Effect, Mesh, MeshBuilder, RawTexture3D, RenderTargetTexture, Scene, ShaderMaterial, Texture, Vector2, Vector3 } from "@babylonjs/core";

export interface PuffField {
  count: number;
  px: Float32Array;
  py: Float32Array;
  pz: Float32Array;
  radius: Float32Array;
  strength: Float32Array;
  age: Float32Array;
  life: Float32Array;
  floor: Float32Array;
  kind: Uint8Array;
}

export interface PuffLook {
  color: [number, number, number];
  glow: number;
}

export interface VolumeView {
  focusX: number;
  focusY: number;
  focusZ: number;
  forwardX: number;
  forwardZ: number;
  carX: number;
  carZ: number;
  sunDirection: Vector3;
  windX: number;
  windZ: number;
}

const CX = 128;
const CZ = 80;
const CY = 20;
const CELL = 1.2;
const LAYER = 1;
const COARSE_SLICE = CX * CZ;
const FX = 96;
const FZ = 96;
const FY = 24;
const FINE_CELL = 0.6;
const FINE_LAYER = 0.5;
const FINE_LIFT = 3;
const FINE_SIZE_X = FX * FINE_CELL;
const FINE_SIZE_Y = FY * FINE_LAYER;
const FINE_SIZE_Z = FZ * FINE_CELL;
const SPLIT_LOW = 1.6;
const SPLIT_HIGH = 2.4;
const TINT_STRIDE = 2;
const TX = CX / TINT_STRIDE;
const TZ = CZ / TINT_STRIDE;
const TINT_LAYER_STRIDE = 4;
const TY = CY / TINT_LAYER_STRIDE;
const TINT_CELL = CELL * TINT_STRIDE;
const TINT_LAYER = LAYER * TINT_LAYER_STRIDE;
const TINT_SLICE = TX * TZ;
const SIZE_X = CX * CELL;
const SIZE_Y = CY * LAYER;
const SIZE_Z = CZ * CELL;
const GROUND_DEPTH = 5;
const FORWARD_BIAS = 8;
const SQUASH_RADIUS = 4.5;
const COLUMN_CENTER = 0.25;
const COLUMN_SPREAD = 0.68;
const COLUMN_ASPECT = 2.2;
const KERNEL_REACH = 1.3;
const MIN_KERNEL_CELLS = 1.3;
const MIN_REACH = 1.2;
const MIN_RISE = 1.1;
const TINT_REACH = 1.3;
const MIN_TINT_CELLS = 1.2;
const EXTINCTION = 2.6;
const DENSITY_RANGE = 16;
const ROOT_DENSITY_TO_BYTE = 255 / Math.sqrt(DENSITY_RANGE);
const SHADOW_DENSITY = 0.55;
const SHADOW_FLOOR = 0.4;
const SHADOW_DROP_LAYERS = 5;
const LIGHT_STEPS = 256;
const LIGHT_SCALE = 24;
const LIGHT_TABLE = new Uint8Array(LIGHT_STEPS);
for (let i = 0; i < LIGHT_STEPS; i++) {
  const depth = i / LIGHT_SCALE;
  LIGHT_TABLE[i] = Math.round(255 * (0.72 * Math.exp(-depth) + 0.28 * Math.exp(-0.22 * depth)));
}
const MARCH_STEPS = 128;
const STEP_LENGTH = 0.28;
const LEVEL_BULGE = 0.12;
const LEVEL_HOLLOW = 8;
const LIT_LEVEL = 0.9;
const LIT_LIFT = 0.09;
const MID_LUMPS = 0.8;
const SMALL_LUMPS = 0.5;
const YOUNG_LARGE = 0.85;
const YOUNG_SMALL = 0.6;
const DETAIL_SCALE = 3.3;
const NORMAL_REACH = 0.2;
const TERMINATOR = 0.5;
const BAND_EDGE = 0.025;
const SHADOW_STEPS = 24;
const SHADOW_START = 0.3;
const SHADOW_STEP = 0.3;
const SHADOW_GROWTH = 1.07;
const SHADOW_EDGE = 0.06;
const CREASE_REACH = 0.35;
const CREASE_WIDTH = 0.08;
const CREASE_SHADE = 0.09;
const HEAT_LOW = 0.08;
const HEAT_HIGH = 0.5;
const HEAT_GLOW = 0.3;
const SUN_FLATTEN = 0.75;
const RIM_START = 0.55;
const RIM_STRENGTH = 0.4;
const GHOST_SHADE = 0.52;
const GHOST_LIFT = 0.3;
const GHOST_DEPTH_SLACK = 0.5;
const GROUND_SHADOW = 0.34;
const GROUND_SHADOW_LEVEL = 0.3;
const PUFFS_PER_REBUILD_STEP = 700;
const NOISE_SIZE = 96;
const NOISE_CELLS = [6, 12];
const NOISE_PERIOD = 32;
const NOISE_RISE = 0.35;

export function puffHeight(radius: number): number {
  return radius / (1 + radius / SQUASH_RADIUS);
}

function buildLumpNoise(): Uint8Array {
  const size = NOISE_SIZE;
  const bytes = new Uint8Array(size * size * size * 2);
  for (let channel = 0; channel < NOISE_CELLS.length; channel++) {
    const cells = NOISE_CELLS[channel];
    const points = new Float32Array(cells * cells * cells * 3);
    let state = 0x9e3779b9 ^ (channel * 0x85ebca6b);
    for (let i = 0; i < points.length; i++) {
      state = (state + 0x6d2b79f5) | 0;
      let t = Math.imul(state ^ (state >>> 15), 1 | state);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      points[i] = ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    }
    const scale = cells / size;
    for (let z = 0; z < size; z++) {
      const pz = (z + 0.5) * scale;
      const cz = Math.floor(pz);
      for (let y = 0; y < size; y++) {
        const py = (y + 0.5) * scale;
        const cy = Math.floor(py);
        for (let x = 0; x < size; x++) {
          const px = (x + 0.5) * scale;
          const cx = Math.floor(px);
          let nearest = 4;
          for (let dz = -1; dz <= 1; dz++) {
            const wz = (cz + dz + cells) % cells;
            for (let dy = -1; dy <= 1; dy++) {
              const wy = (cy + dy + cells) % cells;
              for (let dx = -1; dx <= 1; dx++) {
                const wx = (cx + dx + cells) % cells;
                const p = (wx + cells * (wy + cells * wz)) * 3;
                const ex = cx + dx + points[p] - px;
                const ey = cy + dy + points[p + 1] - py;
                const ez = cz + dz + points[p + 2] - pz;
                const distSq = ex * ex + ey * ey + ez * ez;
                if (distSq < nearest) nearest = distSq;
              }
            }
          }
          bytes[(x + size * (y + size * z)) * 2 + channel] = Math.round(255 * (1 - Math.min(1, Math.sqrt(nearest))));
        }
      }
    }
  }
  return bytes;
}

Effect.ShadersStore["smokeVolumeVertexShader"] = `
precision highp float;
attribute vec3 position;
uniform mat4 world;
uniform mat4 viewProjection;
varying vec3 vWorld;
void main() {
  vec4 placed = world * vec4(position, 1.0);
  vWorld = placed.xyz;
  gl_Position = viewProjection * placed;
}`;

Effect.ShadersStore["smokeVolumeFragmentShader"] = `
precision highp float;
precision highp sampler3D;
uniform sampler3D coarseTex;
uniform sampler3D fineTex;
uniform sampler3D tintTex;
uniform sampler3D noiseTex;
uniform sampler2D depthMap;
uniform sampler2D ghostMap;
uniform vec3 camPos;
uniform vec3 camForward;
uniform vec3 volMin;
uniform vec3 volSize;
uniform vec3 fineMin;
uniform vec3 fineSize;
uniform vec3 fillMin;
uniform vec3 fillMax;
uniform vec3 sunDir;
uniform vec3 drift;
uniform vec3 shadeTint;
uniform vec3 rimColor;
uniform vec3 groundShade;
uniform vec3 fogColor;
uniform vec2 fogRange;
uniform vec2 screenSize;
uniform float pixelAngle;
varying vec3 vWorld;

const int MAX_STEPS = ${MARCH_STEPS};
const int REFINE_STEPS = 6;
const int SHADOW_STEPS = ${SHADOW_STEPS};
const float DENSITY_RANGE = ${DENSITY_RANGE.toFixed(1)};
const float NOISE_SCALE = ${(1 / NOISE_PERIOD).toFixed(5)};
const float STEP_LENGTH = ${STEP_LENGTH.toFixed(3)};
const float LEVEL_FLOOR = ${(LEVEL_BULGE * 0.5).toFixed(4)};
const float LEVEL_BULGE = ${LEVEL_BULGE.toFixed(4)};
const float LOG_BULGE = ${Math.log(LEVEL_BULGE).toFixed(4)};
const float LOG_HOLLOW = ${Math.log(LEVEL_HOLLOW).toFixed(4)};
const float LIT_LEVEL = ${LIT_LEVEL.toFixed(3)};
const float LIT_LIFT = ${LIT_LIFT.toFixed(3)};
const float MID_LUMPS = ${MID_LUMPS.toFixed(3)};
const float SMALL_LUMPS = ${SMALL_LUMPS.toFixed(3)};
const float YOUNG_LARGE = ${YOUNG_LARGE.toFixed(3)};
const float YOUNG_SMALL = ${YOUNG_SMALL.toFixed(3)};
const float DETAIL_SCALE = ${DETAIL_SCALE.toFixed(3)};
const float NORMAL_REACH = ${NORMAL_REACH.toFixed(3)};
const float TERMINATOR = ${TERMINATOR.toFixed(3)};
const float BAND_EDGE = ${BAND_EDGE.toFixed(3)};
const float SHADOW_START = ${SHADOW_START.toFixed(3)};
const float SHADOW_STEP = ${SHADOW_STEP.toFixed(3)};
const float SHADOW_GROWTH = ${SHADOW_GROWTH.toFixed(3)};
const float SHADOW_EDGE = ${SHADOW_EDGE.toFixed(3)};
const float CREASE_REACH = ${CREASE_REACH.toFixed(3)};
const float CREASE_WIDTH = ${CREASE_WIDTH.toFixed(3)};
const float CREASE_SHADE = ${CREASE_SHADE.toFixed(3)};
const float HEAT_LOW = ${HEAT_LOW.toFixed(3)};
const float HEAT_HIGH = ${HEAT_HIGH.toFixed(3)};
const float HEAT_GLOW = ${HEAT_GLOW.toFixed(3)};
const float RIM_START = ${RIM_START.toFixed(3)};
const float RIM_STRENGTH = ${RIM_STRENGTH.toFixed(3)};
const float GHOST_SHADE = ${GHOST_SHADE.toFixed(3)};
const float GHOST_LIFT = ${GHOST_LIFT.toFixed(3)};
const float GHOST_DEPTH_SLACK = ${GHOST_DEPTH_SLACK.toFixed(3)};
const float GROUND_SHADOW = ${GROUND_SHADOW.toFixed(3)};
const float GROUND_SHADOW_LEVEL = ${GROUND_SHADOW_LEVEL.toFixed(3)};

float edgeFade(vec3 uvw) {
  vec2 inset = min(uvw.xz, 1.0 - uvw.xz);
  return clamp(min(min(inset.x, inset.y), 1.0 - uvw.y) * 24.0, 0.0, 1.0);
}

vec2 densityAt(vec3 p) {
  vec3 uvw = (p - volMin) / volSize;
  float root = texture(coarseTex, uvw.xzy).r;
  float aged = root * root * edgeFade(uvw);
  float young = 0.0;
  vec3 near = (p - fineMin) / fineSize;
  if (near.x > 0.0 && near.x < 1.0 && near.y > 0.0 && near.y < 1.0 && near.z > 0.0 && near.z < 1.0) {
    float fineRoot = texture(fineTex, near.xzy).r;
    young = fineRoot * fineRoot;
  }
  return vec2(aged + young, young) * DENSITY_RANGE;
}

float solidAt(vec3 p) {
  vec2 amount = densityAt(p);
  float density = amount.x;
  float depth = log(max(density, 0.001));
  if (density < LEVEL_FLOOR) return depth - LOG_HOLLOW;
  vec3 q = (p - drift) * NOISE_SCALE;
  vec2 large = texture(noiseTex, q).rg;
  vec2 small = texture(noiseTex, q.zxy * DETAIL_SCALE + 0.37).rg;
  float agedLump = max(large.r, max(large.g * MID_LUMPS, small.r * SMALL_LUMPS));
  float youngLump = max(large.g * YOUNG_LARGE, max(small.r, small.g * YOUNG_SMALL));
  float lump = mix(agedLump, youngLump, amount.y / density);
  lump *= smoothstep(LEVEL_FLOOR, LEVEL_BULGE, density);
  return depth - mix(LOG_HOLLOW, LOG_BULGE, lump);
}

vec3 slopeAt(vec3 p) {
  vec2 e = vec2(NORMAL_REACH, 0.0);
  return vec3(
    solidAt(p + e.xyy) - solidAt(p - e.xyy),
    solidAt(p + e.yxy) - solidAt(p - e.yxy),
    solidAt(p + e.yyx) - solidAt(p - e.yyx)
  ) / (2.0 * NORMAL_REACH);
}

void main() {
  vec3 rd = normalize(vWorld - camPos);
  vec2 screenUv = gl_FragCoord.xy / screenSize;
  float sceneZ = texture2D(depthMap, screenUv).r;
  float ahead = max(dot(rd, camForward), 0.001);
  float tScene = sceneZ > 0.0 ? sceneZ / ahead : 1.0e6;

  vec3 inv = 1.0 / rd;
  vec3 ta = (fillMin - camPos) * inv;
  vec3 tb = (fillMax - camPos) * inv;
  vec3 tLow = min(ta, tb);
  vec3 tHigh = max(ta, tb);
  float tNear = max(max(tLow.x, tLow.y), max(tLow.z, 0.0));
  float tFar = min(min(tHigh.x, tHigh.y), min(tHigh.z, tScene));

  bool struck = false;
  float tSurface = 0.0;
  float peak = -1.0e3;
  if (tFar > tNear) {
    float stepLength = max(STEP_LENGTH, (tFar - tNear) / float(MAX_STEPS));
    float t = tNear;
    float before = -1.0e3;
    float last = -1.0e3;
    for (int i = 0; i < MAX_STEPS; i++) {
      if (t > tFar) break;
      float here = solidAt(camPos + rd * t);
      if (here > 0.0) {
        float outside = max(tNear, t - stepLength);
        float inside = t;
        for (int j = 0; j < REFINE_STEPS; j++) {
          float middle = 0.5 * (outside + inside);
          if (solidAt(camPos + rd * middle) > 0.0) inside = middle;
          else outside = middle;
        }
        tSurface = inside;
        struck = true;
        break;
      }
      if (before > -1.0e2 && last > before && last >= here) {
        float bend = before - 2.0 * last + here;
        float offset = bend < -1.0e-5 ? clamp(0.5 * (before - here) / bend, -0.5, 0.5) : 0.0;
        float crest = last - 0.25 * (before - here) * offset;
        if (crest > peak) {
          peak = crest;
          tSurface = t - stepLength + offset * stepLength;
        }
      }
      before = last;
      last = here;
      t += stepLength;
    }
  }

  float cover = 0.0;
  vec3 color = vec3(0.0);
  if (struck || peak > -1.0e2) {
    vec3 p = camPos + rd * tSurface;
    vec3 slope = slopeAt(p);
    float steep = max(length(slope), 1.0e-4);
    vec3 normal = -slope / steep;
    if (struck) {
      cover = 1.0;
    } else {
      float gap = max(-peak, 0.0) / steep;
      cover = clamp(1.0 - gap / (tSurface * pixelAngle), 0.0, 1.0);
    }
    if (cover > 0.0) {
      float blocked = -1.0e3;
      vec3 sp = p + normal * SHADOW_START;
      float reach = SHADOW_STEP;
      for (int k = 0; k < SHADOW_STEPS; k++) {
        sp += sunDir * reach;
        reach *= SHADOW_GROWTH;
        blocked = max(blocked, solidAt(sp));
        if (blocked > 0.0) break;
      }
      float open = 1.0 - smoothstep(-SHADOW_EDGE * steep, 0.0, blocked);
      float facing = dot(normal, sunDir);
      float lit = smoothstep(TERMINATOR - BAND_EDGE, TERMINATOR + BAND_EDGE, facing) * open;
      float pinch = solidAt(p + normal * CREASE_REACH) / steep;
      float crease = smoothstep(-CREASE_WIDTH, 0.0, pinch);
      float grazing = 1.0 - max(dot(normal, -rd), 0.0);
      float rim = smoothstep(RIM_START, 1.0, grazing) * RIM_STRENGTH;

      vec4 tint = texture(tintTex, ((p - volMin) / volSize).xzy);
      color = mix(tint.rgb * shadeTint, mix(tint.rgb, vec3(1.0), LIT_LIFT) * LIT_LEVEL, lit);
      color *= 1.0 - crease * CREASE_SHADE;
      color = mix(color, rimColor, rim * (1.0 - 0.5 * lit));
      float ghostZ = texture2D(ghostMap, screenUv).r;
      if (ghostZ > 0.0 && ghostZ <= sceneZ + GHOST_DEPTH_SLACK && ghostZ / ahead > tSurface) {
        float pale = smoothstep(0.25, 0.4, dot(tint.rgb, vec3(0.3, 0.6, 0.1)));
        color = mix(mix(tint.rgb, vec3(1.0), GHOST_LIFT), tint.rgb * GHOST_SHADE, pale);
      }
      float heat = smoothstep(HEAT_LOW - 0.03, HEAT_LOW + 0.03, tint.a) + smoothstep(HEAT_HIGH - 0.03, HEAT_HIGH + 0.03, tint.a);
      color += tint.rgb * heat * HEAT_GLOW;
      float fog = clamp((tSurface - fogRange.x) / (fogRange.y - fogRange.x), 0.0, 1.0);
      color = mix(color, fogColor, fog);
    }
  }

  float shadow = 0.0;
  if (sceneZ > 0.0) {
    vec3 ground = (camPos + rd * tScene + vec3(0.0, 0.3, 0.0) - volMin) / volSize;
    if (ground.x > 0.0 && ground.x < 1.0 && ground.z > 0.0 && ground.z < 1.0 && ground.y < 1.0) {
      ground.y = max(ground.y, 0.0);
      float dimmed = 1.0 - texture(coarseTex, ground.xzy).g;
      shadow = smoothstep(GROUND_SHADOW_LEVEL - 0.03, GROUND_SHADOW_LEVEL + 0.03, dimmed) * GROUND_SHADOW * edgeFade(ground);
    }
  }

  float alpha = 1.0 - (1.0 - cover) * (1.0 - shadow);
  if (alpha < 0.004) discard;
  vec3 smokeLight = pow(color, vec3(2.2)) * cover;
  vec3 shadowLight = pow(groundShade, vec3(2.2)) * shadow * (1.0 - cover);
  gl_FragColor = vec4(smokeLight + shadowLight, alpha);
}`;

Effect.ShadersStore["smokeGhostVertexShader"] = `
precision highp float;
attribute vec3 position;
#include<instancesDeclaration>
uniform mat4 view;
uniform mat4 viewProjection;
varying float vDepth;
void main() {
#include<instancesVertex>
  vec4 placed = finalWorld * vec4(position, 1.0);
  vDepth = (view * placed).z;
  gl_Position = viewProjection * placed;
}`;

Effect.ShadersStore["smokeGhostFragmentShader"] = `
precision highp float;
varying float vDepth;
void main() {
  gl_FragColor = vec4(vDepth, 0.0, 0.0, 1.0);
}`;

class DensityGrid {
  readonly data: Float32Array;
  readonly slice: number;
  originX = 0;
  originY = 0;
  originZ = 0;
  minX = 0;
  maxX = -1;
  minY = 0;
  maxY = -1;
  minZ = 0;
  maxZ = -1;
  private readonly weightX = new Float32Array(64);
  private readonly weightY = new Float32Array(64);
  private readonly weightZ = new Float32Array(64);

  constructor(
    readonly nx: number,
    readonly nz: number,
    readonly ny: number,
    readonly cell: number,
    readonly layer: number,
    private readonly border: number,
  ) {
    this.slice = nx * nz;
    this.data = new Float32Array(this.slice * ny);
  }

  get empty(): boolean {
    return this.maxX < 0;
  }

  reset(originX: number, originY: number, originZ: number): void {
    this.data.fill(0);
    this.originX = originX;
    this.originY = originY;
    this.originZ = originZ;
    this.minX = this.nx;
    this.maxX = -1;
    this.minY = this.ny;
    this.maxY = -1;
    this.minZ = this.nz;
    this.maxZ = -1;
  }

  contains(x: number, z: number, reach: number): boolean {
    const margin = reach + this.cell * (this.border + 1);
    const localX = x - this.originX;
    const localZ = z - this.originZ;
    return localX > margin && localZ > margin && localX < this.nx * this.cell - margin && localZ < this.nz * this.cell - margin;
  }

  splat(x: number, y: number, z: number, reach: number, rise: number, strength: number): void {
    const nx = this.nx;
    const border = this.border;
    let reachX = reach / this.cell;
    let reachY = rise / this.layer;
    let amplitude = strength;
    if (reachX < MIN_KERNEL_CELLS) {
      amplitude *= (reachX / MIN_KERNEL_CELLS) * (reachX / MIN_KERNEL_CELLS);
      reachX = MIN_KERNEL_CELLS;
    }
    if (reachY < MIN_KERNEL_CELLS) {
      amplitude *= reachY / MIN_KERNEL_CELLS;
      reachY = MIN_KERNEL_CELLS;
    }
    const cx = (x - this.originX) / this.cell - 0.5;
    const cy = (y - this.originY) / this.layer - 0.5;
    const cz = (z - this.originZ) / this.cell - 0.5;
    const x0 = Math.max(border, Math.ceil(cx - reachX));
    const x1 = Math.min(nx - 1 - border, Math.floor(cx + reachX));
    const y0 = Math.max(border, Math.ceil(cy - reachY));
    const y1 = Math.min(this.ny - 1 - border, Math.floor(cy + reachY));
    const z0 = Math.max(border, Math.ceil(cz - reachX));
    const z1 = Math.min(this.nz - 1 - border, Math.floor(cz + reachX));
    if (x0 > x1 || y0 > y1 || z0 > z1) return;

    const weightX = this.weightX;
    const weightY = this.weightY;
    const weightZ = this.weightZ;
    const spanX = x1 - x0;
    for (let i = 0; i <= spanX; i++) {
      const u = (x0 + i - cx) / reachX;
      const falloff = 1 - u * u;
      weightX[i] = falloff * falloff * falloff;
    }
    for (let j = y0; j <= y1; j++) {
      const u = (j - cy) / reachY;
      const falloff = 1 - u * u;
      weightY[j - y0] = falloff * falloff * falloff;
    }
    for (let k = z0; k <= z1; k++) {
      const u = (k - cz) / reachX;
      const falloff = 1 - u * u;
      weightZ[k - z0] = falloff * falloff * falloff;
    }
    const data = this.data;
    for (let j = y0; j <= y1; j++) {
      const layerWeight = amplitude * weightY[j - y0];
      const layerBase = this.slice * j + x0;
      for (let k = z0; k <= z1; k++) {
        const rowWeight = layerWeight * weightZ[k - z0];
        if (rowWeight < 0.002) continue;
        const row = layerBase + nx * k;
        for (let i = 0; i <= spanX; i++) data[row + i] += rowWeight * weightX[i];
      }
    }
    if (x0 < this.minX) this.minX = x0;
    if (x1 > this.maxX) this.maxX = x1;
    if (y0 < this.minY) this.minY = y0;
    if (y1 > this.maxY) this.maxY = y1;
    if (z0 < this.minZ) this.minZ = z0;
    if (z1 > this.maxZ) this.maxZ = z1;
  }
}

export class SmokeVolume {
  private readonly coarse = new DensityGrid(CX, CZ, CY, CELL, LAYER, 0);
  private readonly hidden = new DensityGrid(CX, CZ, CY, CELL, LAYER, 0);
  private readonly fine = new DensityGrid(FX, FZ, FY, FINE_CELL, FINE_LAYER, 1);
  private readonly coarseBytes = new Uint8Array(COARSE_SLICE * CY * 2);
  private readonly coarsePairs = new Uint16Array(this.coarseBytes.buffer);
  private readonly fineBytes = new Uint8Array(FX * FZ * FY);
  private readonly depthA = new Float32Array(COARSE_SLICE);
  private readonly depthB = new Float32Array(COARSE_SLICE);
  private readonly tintWeight = new Float32Array(TINT_SLICE * TY);
  private readonly tintRed = new Float32Array(TINT_SLICE * TY);
  private readonly tintGreen = new Float32Array(TINT_SLICE * TY);
  private readonly tintBlue = new Float32Array(TINT_SLICE * TY);
  private readonly tintGlow = new Float32Array(TINT_SLICE * TY);
  private readonly tintBytes = new Uint8Array(TINT_SLICE * TY * 4);
  private readonly coarseTexture: RawTexture3D;
  private readonly fineTexture: RawTexture3D;
  private readonly tintTexture: RawTexture3D;
  private readonly material: ShaderMaterial;
  private readonly ghostMaterial: ShaderMaterial;
  private readonly ghostTarget: RenderTargetTexture;
  private readonly mesh: Mesh;
  private readonly origin = new Vector3();
  private readonly fineOrigin = new Vector3();
  private readonly fillMin = new Vector3();
  private readonly fillMax = new Vector3();
  private readonly sunward = new Vector3();
  private readonly drift = new Vector3();
  private readonly screenSize = new Vector2();
  private fineWasFilled = false;
  private tick = 0;

  constructor(
    scene: Scene,
    camera: Camera,
    private readonly looks: PuffLook[],
    fogColor: Color3,
    fogStart: number,
    fogEnd: number,
  ) {
    this.coarsePairs.fill(0xff00);
    for (let i = 0; i < this.tintBytes.length; i += 4) {
      this.tintBytes[i] = 250;
      this.tintBytes[i + 1] = 247;
      this.tintBytes[i + 2] = 242;
    }

    const volumeTexture = (data: Uint8Array, width: number, height: number, depth: number, format: number, wrap: number): RawTexture3D => {
      const texture = new RawTexture3D(data, width, height, depth, format, scene, false, false, Texture.BILINEAR_SAMPLINGMODE, Constants.TEXTURETYPE_UNSIGNED_BYTE);
      texture.wrapU = wrap;
      texture.wrapV = wrap;
      texture.wrapR = wrap;
      return texture;
    };
    this.coarseTexture = volumeTexture(this.coarseBytes, CX, CZ, CY, Constants.TEXTUREFORMAT_RG, Texture.CLAMP_ADDRESSMODE);
    this.fineTexture = volumeTexture(this.fineBytes, FX, FZ, FY, Constants.TEXTUREFORMAT_R, Texture.CLAMP_ADDRESSMODE);
    this.tintTexture = volumeTexture(this.tintBytes, TX, TZ, TY, Constants.TEXTUREFORMAT_RGBA, Texture.CLAMP_ADDRESSMODE);
    const noise = volumeTexture(buildLumpNoise(), NOISE_SIZE, NOISE_SIZE, NOISE_SIZE, Constants.TEXTUREFORMAT_RG, Texture.WRAP_ADDRESSMODE);

    const depthRenderer = scene.enableDepthRenderer(camera, false, false, Texture.NEAREST_SAMPLINGMODE, true);

    this.material = new ShaderMaterial(
      "smokeVolume",
      scene,
      { vertex: "smokeVolume", fragment: "smokeVolume" },
      {
        attributes: ["position"],
        uniforms: [
          "world",
          "viewProjection",
          "camPos",
          "camForward",
          "volMin",
          "volSize",
          "fineMin",
          "fineSize",
          "fillMin",
          "fillMax",
          "sunDir",
          "drift",
          "shadeTint",
          "rimColor",
          "groundShade",
          "fogColor",
          "fogRange",
          "screenSize",
          "pixelAngle",
        ],
        samplers: ["coarseTex", "fineTex", "tintTex", "noiseTex", "depthMap", "ghostMap"],
        needAlphaBlending: true,
      },
    );
    this.material.alphaMode = Constants.ALPHA_PREMULTIPLIED;
    this.material.disableDepthWrite = true;
    this.material.setTexture("coarseTex", this.coarseTexture);
    this.material.setTexture("fineTex", this.fineTexture);
    this.material.setTexture("tintTex", this.tintTexture);
    this.material.setTexture("noiseTex", noise);
    this.material.setTexture("depthMap", depthRenderer.getDepthMap());

    this.ghostMaterial = new ShaderMaterial(
      "smokeGhost",
      scene,
      { vertex: "smokeGhost", fragment: "smokeGhost" },
      { attributes: ["position"], uniforms: ["world", "view", "viewProjection"] },
    );
    this.ghostTarget = new RenderTargetTexture(
      "smokeGhost",
      { ratio: 1 },
      scene,
      false,
      true,
      Constants.TEXTURETYPE_HALF_FLOAT,
      false,
      Texture.NEAREST_SAMPLINGMODE,
      true,
      false,
      false,
      Constants.TEXTUREFORMAT_R,
    );
    this.ghostTarget.activeCamera = camera;
    this.ghostTarget.clearColor = new Color4(0, 0, 0, 0);
    this.ghostTarget.renderList = [];
    scene.customRenderTargets.push(this.ghostTarget);
    this.material.setTexture("ghostMap", this.ghostTarget);
    this.material.setColor3("fogColor", fogColor);
    this.material.setColor3("shadeTint", new Color3(0.74, 0.69, 0.75));
    this.material.setColor3("rimColor", new Color3(1, 0.93, 0.84));
    this.material.setColor3("groundShade", new Color3(0.42, 0.2, 0.17));
    this.material.setVector2("fogRange", new Vector2(fogStart, fogEnd));
    this.material.setVector3("volSize", new Vector3(SIZE_X, SIZE_Y, SIZE_Z));
    this.material.setVector3("fineSize", new Vector3(FINE_SIZE_X, FINE_SIZE_Y, FINE_SIZE_Z));

    const engine = scene.getEngine();
    this.material.onBindObservable.add(() => {
      const effect = this.material.getEffect();
      if (!effect) return;
      effect.setVector3("camPos", camera.globalPosition);
      effect.setVector3("camForward", camera.getDirection(Vector3.Forward()));
      effect.setVector2("screenSize", this.screenSize.set(engine.getRenderWidth(), engine.getRenderHeight()));
      effect.setFloat("pixelAngle", (2 * Math.tan(camera.fov / 2)) / engine.getRenderHeight());
    });

    this.mesh = MeshBuilder.CreateBox("smokeVolume", { size: 1 }, scene);
    this.mesh.scaling.set(SIZE_X, SIZE_Y, SIZE_Z);
    this.mesh.material = this.material;
    this.mesh.isPickable = false;
    this.mesh.alwaysSelectAsActiveMesh = true;
    this.mesh.alphaIndex = 10;
    this.mesh.setEnabled(false);
  }

  revealInside(meshes: Mesh[]): void {
    for (const mesh of meshes) this.ghostTarget.renderList?.push(mesh);
    this.ghostTarget.setMaterialForRendering(meshes, this.ghostMaterial);
  }

  update(field: PuffField, view: VolumeView, dt: number): void {
    this.drift.x += view.windX * dt;
    this.drift.y += NOISE_RISE * dt;
    this.drift.z += view.windZ * dt;

    if (field.count === 0) {
      this.mesh.setEnabled(false);
      return;
    }

    this.tick++;
    const interval = 1 + Math.min(3, Math.floor(field.count / PUFFS_PER_REBUILD_STEP));
    const rebuild = !this.mesh.isEnabled() || this.tick % interval === 0;
    const origin = this.origin;
    if (rebuild) {
      const centerX = view.focusX + view.forwardX * FORWARD_BIAS;
      const centerZ = view.focusZ + view.forwardZ * FORWARD_BIAS;
      origin.set(
        Math.floor((centerX - SIZE_X / 2) / TINT_CELL) * TINT_CELL,
        Math.floor(view.focusY - GROUND_DEPTH),
        Math.floor((centerZ - SIZE_Z / 2) / TINT_CELL) * TINT_CELL,
      );
    }
    const fineOrigin = this.fineOrigin.set(
      Math.floor((view.carX - FINE_SIZE_X / 2) / CELL) * CELL,
      origin.y + FINE_LIFT,
      Math.floor((view.carZ - FINE_SIZE_Z / 2) / CELL) * CELL,
    );

    this.splat(field, rebuild);
    const coarse = this.coarse;
    const fine = this.fine;
    if (coarse.empty && fine.empty) {
      this.mesh.setEnabled(false);
      return;
    }
    if (rebuild) {
      this.packTint();
      this.packLight(view.sunDirection);
      this.coarseTexture.update(this.coarseBytes);
      this.tintTexture.update(this.tintBytes);
    }
    if (!fine.empty || this.fineWasFilled) {
      this.packFine();
      this.fineTexture.update(this.fineBytes);
      this.fineWasFilled = !fine.empty;
    }

    this.fillMin.set(Infinity, Infinity, Infinity);
    this.fillMax.set(-Infinity, -Infinity, -Infinity);
    this.includeBounds(coarse);
    this.includeBounds(fine);
    this.sunward.copyFrom(view.sunDirection).scaleInPlace(-1);
    this.sunward.y *= SUN_FLATTEN;
    this.sunward.normalize();
    this.material.setVector3("volMin", origin);
    this.material.setVector3("fineMin", fineOrigin);
    this.material.setVector3("fillMin", this.fillMin);
    this.material.setVector3("fillMax", this.fillMax);
    this.material.setVector3("sunDir", this.sunward);
    this.material.setVector3("drift", this.drift);
    this.mesh.position.set(origin.x + SIZE_X / 2, origin.y + SIZE_Y / 2, origin.z + SIZE_Z / 2);
    this.mesh.setEnabled(true);
  }

  private includeBounds(grid: DensityGrid): void {
    if (grid.empty) return;
    const low = this.fillMin;
    const high = this.fillMax;
    low.x = Math.min(low.x, grid.originX + (grid.minX - 1) * grid.cell);
    low.y = Math.min(low.y, grid.originY + (grid.minY - 1) * grid.layer);
    low.z = Math.min(low.z, grid.originZ + (grid.minZ - 1) * grid.cell);
    high.x = Math.max(high.x, grid.originX + (grid.maxX + 2) * grid.cell);
    high.y = Math.max(high.y, grid.originY + (grid.maxY + 2) * grid.layer);
    high.z = Math.max(high.z, grid.originZ + (grid.maxZ + 2) * grid.cell);
  }

  private splat(field: PuffField, rebuild: boolean): void {
    const coarse = this.coarse;
    const hidden = this.hidden;
    const fine = this.fine;
    const tintWeight = this.tintWeight;
    const tintRed = this.tintRed;
    const tintGreen = this.tintGreen;
    const tintBlue = this.tintBlue;
    const tintGlow = this.tintGlow;
    const originX = this.origin.x;
    const originY = this.origin.y;
    const originZ = this.origin.z;
    fine.reset(this.fineOrigin.x, this.fineOrigin.y, this.fineOrigin.z);
    if (rebuild) {
      coarse.reset(originX, originY, originZ);
      hidden.reset(originX, originY, originZ);
      tintWeight.fill(0);
      tintRed.fill(0);
      tintGreen.fill(0);
      tintBlue.fill(0);
      tintGlow.fill(0);
    }

    for (let p = 0; p < field.count; p++) {
      const strength = field.strength[p];
      if (strength < 0.003) continue;
      const radius = field.radius[p];
      const height = puffHeight(radius);
      const worldX = field.px[p];
      const worldZ = field.pz[p];
      const base = field.floor[p];
      const column = Math.max(2 * height, Math.min(field.py[p] + height - base, 2 * height + COLUMN_ASPECT * radius));
      const spread = COLUMN_SPREAD * column;
      const worldY = base + COLUMN_CENTER * column;
      const tightReach = radius * KERNEL_REACH;
      const tightRise = spread * KERNEL_REACH;
      const reach = Math.max(tightReach, MIN_REACH);
      const rise = Math.max(tightRise, MIN_RISE);
      const amplitude = strength * EXTINCTION * Math.sqrt(height / spread) * (tightReach / reach) * Math.sqrt(tightRise / rise);

      let broad = 1;
      if (radius < SPLIT_HIGH && fine.contains(worldX, worldZ, reach)) {
        const blend = (radius - SPLIT_LOW) / (SPLIT_HIGH - SPLIT_LOW);
        broad = blend <= 0 ? 0 : blend * blend * (3 - 2 * blend);
      }
      if (broad < 1) fine.splat(worldX, worldY, worldZ, reach, rise, amplitude * (1 - broad));
      if (!rebuild) continue;
      if (broad > 0) coarse.splat(worldX, worldY, worldZ, reach, rise, amplitude * broad);
      if (broad < 1) hidden.splat(worldX, worldY, worldZ, reach, rise, amplitude * (1 - broad));

      const look = this.looks[field.kind[p]];
      const glow = look.glow * (1 - field.age[p] / field.life[p]);
      const tintReachX = Math.max(MIN_TINT_CELLS, (radius * TINT_REACH) / TINT_CELL);
      const tintReachY = Math.max(MIN_TINT_CELLS, (spread * TINT_REACH) / TINT_LAYER);
      const tx = (worldX - originX) / TINT_CELL - 0.5;
      const ty = (worldY - originY) / TINT_LAYER - 0.5;
      const tz = (worldZ - originZ) / TINT_CELL - 0.5;
      const tx0 = Math.max(0, Math.ceil(tx - tintReachX));
      const tx1 = Math.min(TX - 1, Math.floor(tx + tintReachX));
      const ty0 = Math.max(0, Math.ceil(ty - tintReachY));
      const ty1 = Math.min(TY - 1, Math.floor(ty + tintReachY));
      const tz0 = Math.max(0, Math.ceil(tz - tintReachX));
      const tz1 = Math.min(TZ - 1, Math.floor(tz + tintReachX));
      const red = look.color[0];
      const green = look.color[1];
      const blue = look.color[2];
      for (let j = ty0; j <= ty1; j++) {
        const layerWeight = strength * (1 - Math.abs(j - ty) / tintReachY);
        for (let k = tz0; k <= tz1; k++) {
          const rowWeight = layerWeight * (1 - Math.abs(k - tz) / tintReachX);
          const row = TINT_SLICE * j + TX * k;
          for (let i = tx0; i <= tx1; i++) {
            const weight = rowWeight * (1 - Math.abs(i - tx) / tintReachX);
            const cell = row + i;
            tintWeight[cell] += weight;
            tintRed[cell] += weight * red;
            tintGreen[cell] += weight * green;
            tintBlue[cell] += weight * blue;
            tintGlow[cell] += weight * glow;
          }
        }
      }
    }
  }

  private packTint(): void {
    const bytes = this.tintBytes;
    const weights = this.tintWeight;
    for (let cell = 0; cell < weights.length; cell++) {
      const weight = weights[cell];
      if (weight < 0.0001) continue;
      const scale = 255 / weight;
      const offset = cell * 4;
      bytes[offset] = this.tintRed[cell] * scale;
      bytes[offset + 1] = this.tintGreen[cell] * scale;
      bytes[offset + 2] = this.tintBlue[cell] * scale;
      bytes[offset + 3] = this.tintGlow[cell] * scale;
    }
  }

  private packFine(): void {
    const fine = this.fine;
    const bytes = this.fineBytes;
    const data = fine.data;
    bytes.fill(0);
    for (let j = fine.minY; j <= fine.maxY; j++) {
      for (let k = fine.minZ; k <= fine.maxZ; k++) {
        const row = fine.slice * j + FX * k;
        for (let i = fine.minX; i <= fine.maxX; i++) {
          const amount = Math.sqrt(data[row + i]) * ROOT_DENSITY_TO_BYTE;
          bytes[row + i] = amount > 255 ? 255 : amount;
        }
      }
    }
  }

  private packLight(sunDirection: Vector3): void {
    const packed = this.coarseBytes;
    const shown = this.coarse.data;
    const unseen = this.hidden.data;
    this.coarsePairs.fill(0xff00);

    const minX = Math.min(this.coarse.minX, this.hidden.minX);
    const maxX = Math.max(this.coarse.maxX, this.hidden.maxX);
    const minY = Math.min(this.coarse.minY, this.hidden.minY);
    const maxY = Math.max(this.coarse.maxY, this.hidden.maxY);
    const minZ = Math.min(this.coarse.minZ, this.hidden.minZ);
    const maxZ = Math.max(this.coarse.maxZ, this.hidden.maxZ);
    if (maxX < 0) return;

    const climb = Math.max(0.2, -sunDirection.y);
    const shiftX = (-sunDirection.x / climb) * (LAYER / CELL);
    const shiftZ = (-sunDirection.z / climb) * (LAYER / CELL);
    const pathLength = (SHADOW_DENSITY * LAYER * sunDirection.length()) / climb;
    const top = maxY;
    const bottom = Math.max(0, minY - SHADOW_DROP_LAYERS);
    const drop = top - bottom;
    const x0 = Math.max(0, Math.floor(minX - Math.max(0, shiftX) * drop) - 1);
    const x1 = Math.min(CX - 1, Math.ceil(maxX + Math.max(0, -shiftX) * drop) + 1);
    const z0 = Math.max(0, Math.floor(minZ - Math.max(0, shiftZ) * drop) - 1);
    const z1 = Math.min(CZ - 1, Math.ceil(maxZ + Math.max(0, -shiftZ) * drop) + 1);

    let above = this.depthA;
    let here = this.depthB;
    for (let j = top; j >= bottom; j--) {
      const fall = top - j;
      const stepX = Math.round(fall * shiftX) - Math.round((fall - 1) * shiftX);
      const stepZ = Math.round(fall * shiftZ) - Math.round((fall - 1) * shiftZ);
      const layerBase = COARSE_SLICE * j;
      const aboveBase = layerBase + COARSE_SLICE;
      for (let k = z0; k <= z1; k++) {
        const sourceK = k + stepZ;
        const lit = fall === 0 || sourceK < z0 || sourceK > z1;
        const row = CX * k;
        const sourceRow = CX * sourceK + stepX;
        for (let i = x0; i <= x1; i++) {
          let depth = 0;
          if (!lit) {
            const sourceI = i + stepX;
            if (sourceI >= x0 && sourceI <= x1) {
              const source = sourceRow + i;
              const blocking = shown[aboveBase + source] + unseen[aboveBase + source] - SHADOW_FLOOR;
              depth = blocking > 0 ? above[source] + blocking * pathLength : above[source];
            }
          }
          const cell = row + i;
          here[cell] = depth;
          const offset = (layerBase + cell) * 2;
          const amount = Math.sqrt(shown[layerBase + cell]) * ROOT_DENSITY_TO_BYTE;
          packed[offset] = amount > 255 ? 255 : amount;
          const step = depth * LIGHT_SCALE;
          packed[offset + 1] = LIGHT_TABLE[step >= LIGHT_STEPS ? LIGHT_STEPS - 1 : step | 0];
        }
      }
      const swap = above;
      above = here;
      here = swap;
    }
  }
}

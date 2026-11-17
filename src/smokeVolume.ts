import { Camera, Color3, Constants, Effect, Mesh, MeshBuilder, RawTexture3D, Scene, ShaderMaterial, Texture, Vector2, Vector3, Vector4 } from "@babylonjs/core";

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
const COLUMN_CENTER = 0.42;
const COLUMN_SPREAD = 0.56;
const COLUMN_ASPECT = 2.2;
const KERNEL_REACH = 1.15;
const MIN_KERNEL_CELLS = 1.3;
const TINT_REACH = 1.3;
const MIN_TINT_CELLS = 1.2;
const EXTINCTION = 2.6;
const DENSITY_RANGE = 6;
const DENSITY_TO_BYTE = 255 / DENSITY_RANGE;
const SHADOW_DENSITY = 0.55;
const SHADOW_DROP_LAYERS = 5;
const LIGHT_STEPS = 256;
const LIGHT_SCALE = 24;
const LIGHT_TABLE = new Uint8Array(LIGHT_STEPS);
for (let i = 0; i < LIGHT_STEPS; i++) {
  const depth = i / LIGHT_SCALE;
  LIGHT_TABLE[i] = Math.round(255 * (0.72 * Math.exp(-depth) + 0.28 * Math.exp(-0.22 * depth)));
}
const STEP_LENGTH = 0.42;
const EROSION = 0.6;
const RELIEF = 3.6;
const GROUND_SHADOW = 0.55;
const PUFFS_PER_REBUILD_STEP = 700;
const NOISE_SIZE = 64;
const NOISE_PERIOD = 14;
const NOISE_RISE = 0.35;

export function puffHeight(radius: number): number {
  return radius / (1 + radius / SQUASH_RADIUS);
}

function buildBillowNoise(): Uint8Array {
  const size = NOISE_SIZE;
  const octaves = [
    { cells: 3, weight: 0.5 },
    { cells: 6, weight: 0.32 },
    { cells: 12, weight: 0.18 },
  ];
  const values = new Float32Array(size * size * size);
  for (let octave = 0; octave < octaves.length; octave++) {
    const { cells, weight } = octaves[octave];
    const points = new Float32Array(cells * cells * cells * 3);
    let state = 0x9e3779b9 ^ (octave * 0x85ebca6b);
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
          const closeness = 1 - Math.min(1, Math.sqrt(nearest));
          values[x + size * (y + size * z)] += closeness * weight;
        }
      }
    }
  }
  let low = Infinity;
  let high = -Infinity;
  for (let i = 0; i < values.length; i++) {
    if (values[i] < low) low = values[i];
    if (values[i] > high) high = values[i];
  }
  const bytes = new Uint8Array(values.length);
  for (let i = 0; i < values.length; i++) bytes[i] = Math.round(((values[i] - low) / (high - low)) * 255);
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
uniform vec3 shadeColor;
uniform vec3 fogColor;
uniform vec2 fogRange;
uniform vec2 screenSize;
uniform vec4 look;
varying vec3 vWorld;

const int MAX_STEPS = 80;
const float DENSITY_RANGE = ${DENSITY_RANGE.toFixed(1)};
const float NOISE_SCALE = ${(1 / NOISE_PERIOD).toFixed(5)};

float edgeFade(vec3 uvw) {
  vec2 inset = min(uvw.xz, 1.0 - uvw.xz);
  return clamp(min(inset.x, inset.y) * 24.0, 0.0, 1.0);
}

void main() {
  vec3 rd = normalize(vWorld - camPos);
  float sceneZ = texture2D(depthMap, gl_FragCoord.xy / screenSize).r;
  float tScene = sceneZ > 0.0 ? sceneZ / max(dot(rd, camForward), 0.001) : 1.0e6;

  vec3 inv = 1.0 / rd;
  vec3 ta = (fillMin - camPos) * inv;
  vec3 tb = (fillMax - camPos) * inv;
  vec3 tLow = min(ta, tb);
  vec3 tHigh = max(ta, tb);
  float tNear = max(max(tLow.x, tLow.y), max(tLow.z, 0.0));
  float tFar = min(min(tHigh.x, tHigh.y), min(tHigh.z, tScene));

  vec3 glowing = vec3(0.0);
  vec3 scattered = vec3(0.0);
  float through = 1.0;
  if (tFar > tNear) {
    float stepLength = max(look.x, (tFar - tNear) / float(MAX_STEPS));
    float dither = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
    float t = tNear + stepLength * dither;
    for (int i = 0; i < MAX_STEPS; i++) {
      if (t >= tFar || through < 0.02) break;
      vec3 p = camPos + rd * t;
      vec3 uvw = (p - volMin) / volSize;
      vec2 cell = texture(coarseTex, uvw.xzy).rg;
      float amount = cell.r * edgeFade(uvw);
      vec3 near = (p - fineMin) / fineSize;
      if (near.x > 0.0 && near.x < 1.0 && near.y > 0.0 && near.y < 1.0 && near.z > 0.0 && near.z < 1.0) amount += texture(fineTex, near.xzy).r;
      float density = amount * DENSITY_RANGE;
      if (density > 0.003) {
        vec3 q = (p - drift) * NOISE_SCALE;
        float broad = texture(noiseTex, q).r;
        float fine = texture(noiseTex, q * 3.3 + 0.37).r;
        float billow = broad * 0.68 + fine * 0.32;
        float cut = mix(look.y, 0.04, clamp(density * 0.6, 0.0, 1.0));
        float thick = density * 1.35 * smoothstep(cut - 0.13, cut + 0.13, billow);
        if (thick > 0.0) {
          float sunward = texture(noiseTex, q + sunDir * (0.9 * NOISE_SCALE)).r;
          float relief = clamp(1.0 + (broad - sunward) * look.z, 0.3, 1.6);
          float lit = clamp(cell.g * relief, 0.0, 1.0);
          vec4 tint = texture(tintTex, uvw.xzy);
          vec3 shaded = tint.rgb * mix(shadeColor, vec3(1.0), lit);
          float opacity = 1.0 - exp(-thick * stepLength);
          scattered += through * opacity * shaded;
          glowing += through * opacity * tint.rgb * tint.a * 1.5;
          through *= 1.0 - opacity;
        }
      }
      t += stepLength;
    }
  }

  float shadow = 0.0;
  if (sceneZ > 0.0) {
    vec3 ground = (camPos + rd * tScene + vec3(0.0, 0.3, 0.0) - volMin) / volSize;
    if (ground.x > 0.0 && ground.x < 1.0 && ground.z > 0.0 && ground.z < 1.0 && ground.y < 1.0) {
      ground.y = max(ground.y, 0.0);
      shadow = (1.0 - texture(coarseTex, ground.xzy).g) * look.w * edgeFade(ground);
    }
  }

  float cover = 1.0 - through;
  float alpha = 1.0 - through * (1.0 - shadow);
  if (alpha < 0.004) discard;
  vec3 color = (scattered + glowing) / max(cover, 0.0001);
  float fog = clamp((tNear - fogRange.x) / (fogRange.y - fogRange.x), 0.0, 1.0);
  color = mix(color, fogColor, fog);
  gl_FragColor = vec4(pow(color, vec3(2.2)) * cover, alpha);
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
      const falloff = 1 - u * u * u * u;
      weightY[j - y0] = falloff * falloff;
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
    const noise = volumeTexture(buildBillowNoise(), NOISE_SIZE, NOISE_SIZE, NOISE_SIZE, Constants.TEXTUREFORMAT_R, Texture.WRAP_ADDRESSMODE);

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
          "shadeColor",
          "fogColor",
          "fogRange",
          "screenSize",
          "look",
        ],
        samplers: ["coarseTex", "fineTex", "tintTex", "noiseTex", "depthMap"],
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
    this.material.setColor3("fogColor", fogColor);
    this.material.setColor3("shadeColor", new Color3(0.76, 0.71, 0.72));
    this.material.setVector2("fogRange", new Vector2(fogStart, fogEnd));
    this.material.setVector3("volSize", new Vector3(SIZE_X, SIZE_Y, SIZE_Z));
    this.material.setVector3("fineSize", new Vector3(FINE_SIZE_X, FINE_SIZE_Y, FINE_SIZE_Z));
    this.material.setVector4("look", new Vector4(STEP_LENGTH, EROSION, RELIEF, GROUND_SHADOW));

    const engine = scene.getEngine();
    this.material.onBindObservable.add(() => {
      const effect = this.material.getEffect();
      if (!effect) return;
      effect.setVector3("camPos", camera.globalPosition);
      effect.setVector3("camForward", camera.getDirection(Vector3.Forward()));
      effect.setVector2("screenSize", this.screenSize.set(engine.getRenderWidth(), engine.getRenderHeight()));
    });

    this.mesh = MeshBuilder.CreateBox("smokeVolume", { size: 1 }, scene);
    this.mesh.scaling.set(SIZE_X, SIZE_Y, SIZE_Z);
    this.mesh.material = this.material;
    this.mesh.isPickable = false;
    this.mesh.alwaysSelectAsActiveMesh = true;
    this.mesh.alphaIndex = 10;
    this.mesh.setEnabled(false);
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
    this.sunward.copyFrom(view.sunDirection).scaleInPlace(-1).normalize();
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
      const reach = radius * KERNEL_REACH;
      const rise = spread * KERNEL_REACH;
      const amplitude = strength * EXTINCTION * Math.sqrt(height / spread);

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
          const amount = data[row + i] * DENSITY_TO_BYTE;
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
              depth = above[source] + (shown[aboveBase + source] + unseen[aboveBase + source]) * pathLength;
            }
          }
          const cell = row + i;
          here[cell] = depth;
          const offset = (layerBase + cell) * 2;
          const amount = shown[layerBase + cell] * DENSITY_TO_BYTE;
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

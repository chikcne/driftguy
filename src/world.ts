import { Color3, Material, Mesh, Scene, ShadowGenerator, VertexData } from "@babylonjs/core";
import { writeTransform } from "./kit";
import { LooseSystem, type Mover, type Obstruction, type Shove } from "./loose";
import { hash2, lerp, type Rng, saturate, seededRng, TAU } from "./math";
import { PALETTE } from "./palette";
import { buildProps, type PropDef, type PropName } from "./props";
import { CELL_SIZE, CHUNK_CELLS, CHUNK_SIZE, groundHeight, vertexHeight } from "./terrain";

export interface Collider {
  x: number;
  z: number;
  r: number;
}

export interface Contact {
  hit: boolean;
  nx: number;
  nz: number;
}

interface Rooted {
  id: number;
  name: PropName;
  x: number;
  y: number;
  z: number;
  r: number;
  yaw: number;
  scale: number;
  scaleY: number;
  solid: boolean;
  alive: boolean;
  list: number[];
  offset: number;
}

interface Chunk {
  cx: number;
  cz: number;
  ground: Mesh;
  placements: Map<PropName, number[]>;
  colliders: Collider[];
  rooted: Rooted[];
}

interface LooseBatch {
  mesh: Mesh;
  matrices: Float32Array;
}

const VIEW_RADIUS_CHUNKS = 2;
const COLLIDER_CELL = 16;
const SPAWN_CLEARING = 28;
const KEY_OFFSET = 32768;
const KEY_STRIDE = 65536;
const OUTPOST_CHANCE = 0.16;
const PLACEMENT_ATTEMPTS = 5;
const ROOTED_ID_STRIDE = 256;
const LOOSE_CAPACITY = 64;

const SCATTER_TABLE: Array<[PropName, number]> = [
  ["rockA", 5],
  ["rockB", 4],
  ["spire", 1.4],
  ["wreck", 1.6],
  ["tires", 1],
  ["cactus", 3],
  ["deadTree", 2],
  ["ribs", 0.5],
  ["pylon", 0.8],
  ["wall", 0.7],
  ["barrel", 0.8],
];

const SCATTER_TOTAL = SCATTER_TABLE.reduce((sum, [, weight]) => sum + weight, 0);

function cellKey(a: number, b: number): number {
  return (a + KEY_OFFSET) * KEY_STRIDE + (b + KEY_OFFSET);
}

function pickScatter(rng: Rng): PropName {
  let roll = rng() * SCATTER_TOTAL;
  for (const [name, weight] of SCATTER_TABLE) {
    roll -= weight;
    if (roll <= 0) return name;
  }
  return "rockA";
}

function groundColor(ix: number, iz: number, variant: number, height: number, out: Color3): void {
  const patch = 0.5 + 0.5 * Math.sin(ix * 0.19 + 1.7) * Math.cos(iz * 0.23 - 0.6);
  const grain = hash2(ix * 2 + variant, iz);
  const t = saturate(0.55 - height * 0.09 + (grain - 0.5) * 0.3 + (patch - 0.5) * 0.35);
  Color3.LerpToRef(PALETTE.sandLight, PALETTE.sandDark, t, out);
  if (patch > 0.9 && grain > 0.5) Color3.LerpToRef(out, PALETTE.sandShadow, 0.5, out);
}

export class World {
  private readonly props: Record<PropName, PropDef>;
  private readonly chunks = new Map<number, Chunk>();
  private readonly colliderGrid = new Map<number, Collider[]>();
  private readonly rootedGrid = new Map<number, Rooted[]>();
  private readonly uprooted = new Set<number>();
  private readonly loose = new LooseSystem<PropName>();
  private readonly looseBatches = new Map<PropName, LooseBatch>();
  private readonly obstacles = (spot: { x: number; z: number }, radius: number, out: Obstruction): Obstruction => this.resolve(spot, radius, out);
  private centerX = Number.NaN;
  private centerZ = Number.NaN;

  constructor(
    private readonly scene: Scene,
    private readonly material: Material,
    shadows: ShadowGenerator,
  ) {
    this.props = buildProps(scene);
    for (const prop of Object.values(this.props)) {
      prop.mesh.material = material;
      prop.mesh.alwaysSelectAsActiveMesh = true;
      prop.mesh.receiveShadows = true;
      prop.mesh.setEnabled(false);
      if (prop.castsShadow) shadows.addShadowCaster(prop.mesh);
    }
    for (const [name, prop] of Object.entries(this.props) as Array<[PropName, PropDef]>) {
      if (!prop.loose) continue;
      const mesh = prop.mesh.clone(`${name}Loose`);
      mesh.makeGeometryUnique();
      const matrices = new Float32Array(LOOSE_CAPACITY * 16);
      mesh.material = material;
      mesh.alwaysSelectAsActiveMesh = true;
      mesh.receiveShadows = true;
      mesh.thinInstanceSetBuffer("matrix", matrices, 16, false);
      mesh.thinInstanceCount = 0;
      mesh.setEnabled(false);
      if (prop.castsShadow) shadows.addShadowCaster(mesh);
      this.looseBatches.set(name, { mesh, matrices });
    }
  }

  reset(): void {
    this.loose.clear();
    this.uprooted.clear();
    for (const chunk of this.chunks.values()) chunk.ground.dispose();
    this.chunks.clear();
    this.centerX = Number.NaN;
    this.centerZ = Number.NaN;
    this.renderLoose();
  }

  step(dt: number, x: number, z: number): void {
    this.loose.step(dt, x, z, this.obstacles);
    this.renderLoose();
  }

  shove(mover: Mover, radius: number, mass: number, out: Shove): Shove {
    const minX = Math.floor((mover.x - radius) / COLLIDER_CELL);
    const maxX = Math.floor((mover.x + radius) / COLLIDER_CELL);
    const minZ = Math.floor((mover.z - radius) / COLLIDER_CELL);
    const maxZ = Math.floor((mover.z + radius) / COLLIDER_CELL);
    for (let gz = minZ; gz <= maxZ; gz++) {
      for (let gx = minX; gx <= maxX; gx++) {
        const bucket = this.rootedGrid.get(cellKey(gx, gz));
        if (!bucket) continue;
        for (const plant of bucket) {
          if (!plant.alive) continue;
          const reach = radius + plant.r;
          const dx = plant.x - mover.x;
          const dz = plant.z - mover.z;
          if (dx * dx + dz * dz < reach * reach) this.uproot(plant);
        }
      }
    }
    return this.loose.shove(mover, radius, mass, out);
  }

  update(x: number, z: number): void {
    const cx = Math.floor(x / CHUNK_SIZE);
    const cz = Math.floor(z / CHUNK_SIZE);
    if (cx === this.centerX && cz === this.centerZ) return;
    this.centerX = cx;
    this.centerZ = cz;

    const wanted = new Set<number>();
    for (let dz = -VIEW_RADIUS_CHUNKS; dz <= VIEW_RADIUS_CHUNKS; dz++) {
      for (let dx = -VIEW_RADIUS_CHUNKS; dx <= VIEW_RADIUS_CHUNKS; dx++) {
        const key = cellKey(cx + dx, cz + dz);
        wanted.add(key);
        if (!this.chunks.has(key)) this.chunks.set(key, this.createChunk(cx + dx, cz + dz));
      }
    }
    for (const [key, chunk] of this.chunks) {
      if (wanted.has(key)) continue;
      chunk.ground.dispose();
      this.chunks.delete(key);
    }
    this.rebuildInstances();
    this.rebuildColliderGrid();
  }

  resolve(body: { x: number; z: number }, radius: number, contact: Contact): Contact {
    contact.hit = false;
    const minX = Math.floor((body.x - radius) / COLLIDER_CELL);
    const maxX = Math.floor((body.x + radius) / COLLIDER_CELL);
    const minZ = Math.floor((body.z - radius) / COLLIDER_CELL);
    const maxZ = Math.floor((body.z + radius) / COLLIDER_CELL);
    for (let gz = minZ; gz <= maxZ; gz++) {
      for (let gx = minX; gx <= maxX; gx++) {
        const bucket = this.colliderGrid.get(cellKey(gx, gz));
        if (!bucket) continue;
        for (const collider of bucket) {
          const dx = body.x - collider.x;
          const dz = body.z - collider.z;
          const reach = radius + collider.r;
          const distSq = dx * dx + dz * dz;
          if (distSq >= reach * reach) continue;
          const dist = Math.sqrt(distSq) || 0.001;
          const nx = dx / dist;
          const nz = dz / dist;
          body.x = collider.x + nx * reach;
          body.z = collider.z + nz * reach;
          contact.hit = true;
          contact.nx = nx;
          contact.nz = nz;
        }
      }
    }
    return contact;
  }

  private createChunk(cx: number, cz: number): Chunk {
    const chunk: Chunk = {
      cx,
      cz,
      ground: this.createGround(cx, cz),
      placements: new Map(),
      colliders: [],
      rooted: [],
    };
    const rng = seededRng(Math.floor(hash2(cx, cz) * 4294967296));
    const originX = cx * CHUNK_SIZE;
    const originZ = cz * CHUNK_SIZE;

    if (rng() < OUTPOST_CHANCE) this.placeOutpost(chunk, originX + lerp(18, 46, rng()), originZ + lerp(18, 46, rng()), rng);

    const scatterCount = 4 + Math.floor(rng() * 5);
    for (let i = 0; i < scatterCount; i++) {
      const name = pickScatter(rng);
      for (let attempt = 0; attempt < PLACEMENT_ATTEMPTS; attempt++) {
        const x = originX + rng() * CHUNK_SIZE;
        const z = originZ + rng() * CHUNK_SIZE;
        if (this.place(chunk, name, x, z, rng() * TAU, rng)) break;
      }
    }
    for (let i = 0; i < 16; i++) this.place(chunk, "pebble", originX + rng() * CHUNK_SIZE, originZ + rng() * CHUNK_SIZE, rng() * TAU, rng);
    for (let i = 0; i < 9; i++) this.place(chunk, "shrub", originX + rng() * CHUNK_SIZE, originZ + rng() * CHUNK_SIZE, rng() * TAU, rng);
    return chunk;
  }

  private placeOutpost(chunk: Chunk, x: number, z: number, rng: Rng): void {
    const facing = rng() * TAU;
    this.place(chunk, "shack", x, z, facing, rng);
    const ring = (name: PropName, distance: number, angle: number, yaw: number): void => {
      this.place(chunk, name, x + Math.sin(facing + angle) * distance, z + Math.cos(facing + angle) * distance, yaw, rng);
    };
    ring("tower", 9, 2.2, rng() * TAU);
    ring("wall", 13, 0.2, facing + 0.2 + Math.PI / 2);
    ring("wall", 14, 3.6, facing + 3.6 + Math.PI / 2);
    ring("wreck", 8, 4.6, rng() * TAU);
    ring("tires", 6.5, 1.0, rng() * TAU);
    ring("barrel", 5.2, 5.4, 0);
    ring("barrel", 6.1, 5.65, 0);
    ring("barrel", 10.5, 1.5, 0);
    ring("pylon", 11.5, 5.0, facing);
  }

  private place(chunk: Chunk, name: PropName, x: number, z: number, yaw: number, rng: Rng): boolean {
    const prop = this.props[name];
    const scale = lerp(prop.minScale, prop.maxScale, rng());
    if (prop.colliders.length > 0) {
      if (Math.hypot(x, z) < SPAWN_CLEARING) return false;
      const footprint = prop.colliders.reduce((reach, c) => Math.max(reach, Math.hypot(c.x, c.z) + c.r), 0) * scale;
      for (const other of chunk.colliders) {
        if (Math.hypot(other.x - x, other.z - z) < other.r + footprint + 1.5) return false;
      }
      for (const other of chunk.rooted) {
        if (other.solid && Math.hypot(other.x - x, other.z - z) < other.r + footprint + 1.5) return false;
      }
    }
    const sin = Math.sin(yaw);
    const cos = Math.cos(yaw);
    for (const local of prop.loose ? [] : prop.colliders) {
      chunk.colliders.push({
        x: x + (local.x * cos + local.z * sin) * scale,
        z: z + (-local.x * sin + local.z * cos) * scale,
        r: local.r * scale,
      });
    }
    let list = chunk.placements.get(name);
    if (!list) {
      list = [];
      chunk.placements.set(name, list);
    }
    const squash = lerp(0.85, 1.15, rng());
    const y = groundHeight(x, z) - prop.sink * scale;
    if (prop.loose) {
      const id = cellKey(chunk.cx, chunk.cz) * ROOTED_ID_STRIDE + chunk.rooted.length;
      const alive = !this.uprooted.has(id);
      chunk.rooted.push({
        id,
        name,
        x,
        y,
        z,
        r: prop.loose.radius * scale,
        yaw,
        scale,
        scaleY: scale * squash,
        solid: prop.colliders.length > 0,
        alive,
        list,
        offset: list.length,
      });
      if (!alive) return true;
    }
    writeTransform(list, list.length, x, y, z, yaw, 0, 0, scale, scale * squash, scale);
    return true;
  }

  private uproot(plant: Rooted): void {
    const spec = this.props[plant.name].loose;
    if (!spec) return;
    plant.alive = false;
    this.uprooted.add(plant.id);
    plant.list.fill(0, plant.offset, plant.offset + 16);
    this.rebuildInstancesOf(plant.name);
    this.loose.spawn(plant.name, spec, plant.x, plant.y, plant.z, plant.yaw, plant.scale, plant.scaleY);
  }

  private renderLoose(): void {
    for (const [name, batch] of this.looseBatches) {
      const count = this.loose.write(name, batch.matrices);
      batch.mesh.thinInstanceCount = count;
      batch.mesh.setEnabled(count > 0);
      if (count > 0) batch.mesh.thinInstanceBufferUpdated("matrix");
    }
  }

  private createGround(cx: number, cz: number): Mesh {
    const triangles = CHUNK_CELLS * CHUNK_CELLS * 2;
    const positions = new Float32Array(triangles * 9);
    const normals = new Float32Array(triangles * 9);
    const colors = new Float32Array(triangles * 12);
    const indices = new Uint32Array(triangles * 3);
    const color = new Color3();
    let v = 0;
    let c = 0;

    const emit = (ax: number, az: number, bx: number, bz: number, dx: number, dz: number, variant: number): void => {
      const ah = vertexHeight(ax, az);
      const bh = vertexHeight(bx, bz);
      const dh = vertexHeight(dx, dz);
      const ux = (bx - ax) * CELL_SIZE;
      const uy = bh - ah;
      const uz = (bz - az) * CELL_SIZE;
      const wx = (dx - ax) * CELL_SIZE;
      const wy = dh - ah;
      const wz = (dz - az) * CELL_SIZE;
      let nx = uy * wz - uz * wy;
      let ny = uz * wx - ux * wz;
      let nz = ux * wy - uy * wx;
      if (ny < 0) {
        nx = -nx;
        ny = -ny;
        nz = -nz;
      }
      const length = Math.hypot(nx, ny, nz);
      groundColor(Math.min(ax, bx, dx), Math.min(az, bz, dz), variant, (ah + bh + dh) / 3, color);
      const corners = [ax, ah, az, bx, bh, bz, dx, dh, dz];
      for (let i = 0; i < 3; i++) {
        positions[v] = corners[i * 3] * CELL_SIZE;
        positions[v + 1] = corners[i * 3 + 1];
        positions[v + 2] = corners[i * 3 + 2] * CELL_SIZE;
        normals[v] = nx / length;
        normals[v + 1] = ny / length;
        normals[v + 2] = nz / length;
        colors[c] = color.r;
        colors[c + 1] = color.g;
        colors[c + 2] = color.b;
        colors[c + 3] = 1;
        v += 3;
        c += 4;
      }
    };

    for (let j = 0; j < CHUNK_CELLS; j++) {
      for (let i = 0; i < CHUNK_CELLS; i++) {
        const ix = cx * CHUNK_CELLS + i;
        const iz = cz * CHUNK_CELLS + j;
        emit(ix, iz, ix + 1, iz, ix + 1, iz + 1, 0);
        emit(ix, iz, ix + 1, iz + 1, ix, iz + 1, 1);
      }
    }
    for (let i = 0; i < indices.length; i++) indices[i] = i;

    const data = new VertexData();
    data.positions = positions;
    data.normals = normals;
    data.colors = colors;
    data.indices = indices;
    const ground = new Mesh(`ground_${cx}_${cz}`, this.scene);
    data.applyToMesh(ground);
    ground.material = this.material;
    ground.receiveShadows = true;
    ground.isPickable = false;
    ground.freezeWorldMatrix();
    return ground;
  }

  private rebuildInstances(): void {
    for (const name of Object.keys(this.props) as PropName[]) this.rebuildInstancesOf(name);
  }

  private rebuildInstancesOf(name: PropName): void {
    const prop = this.props[name];
    let total = 0;
    for (const chunk of this.chunks.values()) total += chunk.placements.get(name)?.length ?? 0;
    if (total === 0) {
      prop.mesh.thinInstanceCount = 0;
      prop.mesh.setEnabled(false);
      return;
    }
    const buffer = new Float32Array(total);
    let offset = 0;
    for (const chunk of this.chunks.values()) {
      const list = chunk.placements.get(name);
      if (!list) continue;
      buffer.set(list, offset);
      offset += list.length;
    }
    prop.mesh.thinInstanceSetBuffer("matrix", buffer, 16, true);
    prop.mesh.setEnabled(true);
  }

  private rebuildColliderGrid(): void {
    this.colliderGrid.clear();
    this.rootedGrid.clear();
    for (const chunk of this.chunks.values()) {
      for (const plant of chunk.rooted) {
        if (!plant.alive) continue;
        const minX = Math.floor((plant.x - plant.r) / COLLIDER_CELL);
        const maxX = Math.floor((plant.x + plant.r) / COLLIDER_CELL);
        const minZ = Math.floor((plant.z - plant.r) / COLLIDER_CELL);
        const maxZ = Math.floor((plant.z + plant.r) / COLLIDER_CELL);
        for (let gz = minZ; gz <= maxZ; gz++) {
          for (let gx = minX; gx <= maxX; gx++) {
            const key = cellKey(gx, gz);
            let bucket = this.rootedGrid.get(key);
            if (!bucket) {
              bucket = [];
              this.rootedGrid.set(key, bucket);
            }
            bucket.push(plant);
          }
        }
      }
      for (const collider of chunk.colliders) {
        const minX = Math.floor((collider.x - collider.r) / COLLIDER_CELL);
        const maxX = Math.floor((collider.x + collider.r) / COLLIDER_CELL);
        const minZ = Math.floor((collider.z - collider.r) / COLLIDER_CELL);
        const maxZ = Math.floor((collider.z + collider.r) / COLLIDER_CELL);
        for (let gz = minZ; gz <= maxZ; gz++) {
          for (let gx = minX; gx <= maxX; gx++) {
            const key = cellKey(gx, gz);
            let bucket = this.colliderGrid.get(key);
            if (!bucket) {
              bucket = [];
              this.colliderGrid.set(key, bucket);
            }
            bucket.push(collider);
          }
        }
      }
    }
  }
}

import { Color3, Mesh, MeshBuilder, Scene, StandardMaterial, VertexBuffer } from "@babylonjs/core";
import { groundHeight } from "./terrain";

const BLAST_POOL = 12;
const BLAST_SECONDS = 0.38;
const BLAST_HOT = new Color3(1, 0.9, 0.6);
const BLAST_COOL = new Color3(1, 0.35, 0.12);

interface Blast {
  mesh: Mesh;
  material: StandardMaterial;
  age: number;
  radius: number;
  active: boolean;
}

export class BlastPool {
  private readonly blasts: Blast[] = [];
  private cursor = 0;

  constructor(scene: Scene) {
    for (let i = 0; i < BLAST_POOL; i++) {
      const mesh = MeshBuilder.CreateIcoSphere("blast", { radius: 1, subdivisions: 2, flat: true }, scene);
      const material = new StandardMaterial("blast", scene);
      material.disableLighting = true;
      material.emissiveColor = new Color3(1, 0.62, 0.22);
      material.alpha = 0;
      material.backFaceCulling = false;
      mesh.material = material;
      mesh.alphaIndex = 20;
      mesh.isPickable = false;
      mesh.setEnabled(false);
      this.blasts.push({ mesh, material, age: 0, radius: 1, active: false });
    }
  }

  clear(): void {
    for (const blast of this.blasts) {
      blast.active = false;
      blast.mesh.setEnabled(false);
    }
  }

  spawn(x: number, y: number, z: number, radius: number): void {
    const blast = this.blasts[this.cursor];
    this.cursor = (this.cursor + 1) % BLAST_POOL;
    blast.age = 0;
    blast.radius = radius;
    blast.active = true;
    blast.mesh.position.set(x, y, z);
    blast.mesh.setEnabled(true);
  }

  update(dt: number): void {
    for (const blast of this.blasts) {
      if (!blast.active) continue;
      blast.age += dt;
      const t = blast.age / BLAST_SECONDS;
      if (t >= 1) {
        blast.active = false;
        blast.mesh.setEnabled(false);
        continue;
      }
      const eased = 1 - (1 - t) * (1 - t);
      blast.mesh.scaling.setAll(blast.radius * (0.25 + 0.75 * eased));
      blast.material.alpha = 0.85 * (1 - t);
      Color3.LerpToRef(BLAST_HOT, BLAST_COOL, t, blast.material.emissiveColor);
    }
  }
}

const RING_POOL = 6;
const RING_SECONDS = 0.5;
const RING_LIFT = 0.7;

interface Ring {
  mesh: Mesh;
  material: StandardMaterial;
  age: number;
  radius: number;
  active: boolean;
}

export class ShockRings {
  private readonly rings: Ring[] = [];
  private cursor = 0;

  constructor(scene: Scene) {
    for (let i = 0; i < RING_POOL; i++) {
      const mesh = MeshBuilder.CreateTorus("ring", { diameter: 2, thickness: 0.09, tessellation: 40 }, scene);
      const material = new StandardMaterial("ring", scene);
      material.disableLighting = true;
      material.emissiveColor = new Color3(1, 0.82, 0.5);
      material.alpha = 0;
      mesh.material = material;
      mesh.alphaIndex = 19;
      mesh.isPickable = false;
      mesh.setEnabled(false);
      this.rings.push({ mesh, material, age: 0, radius: 1, active: false });
    }
  }

  clear(): void {
    for (const ring of this.rings) {
      ring.active = false;
      ring.mesh.setEnabled(false);
    }
  }

  spawn(x: number, z: number, radius: number): void {
    const ring = this.rings[this.cursor];
    this.cursor = (this.cursor + 1) % RING_POOL;
    ring.age = 0;
    ring.radius = radius;
    ring.active = true;
    ring.mesh.position.set(x, groundHeight(x, z) + RING_LIFT, z);
    ring.mesh.scaling.setAll(0.01);
    ring.mesh.setEnabled(true);
  }

  update(dt: number): void {
    for (const ring of this.rings) {
      if (!ring.active) continue;
      ring.age += dt;
      const t = ring.age / RING_SECONDS;
      if (t >= 1) {
        ring.active = false;
        ring.mesh.setEnabled(false);
        continue;
      }
      const eased = 1 - (1 - t) * (1 - t) * (1 - t);
      const reach = ring.radius * (0.15 + 0.85 * eased);
      ring.mesh.scaling.set(reach, 1 + 5 * (1 - t), reach);
      ring.material.alpha = 0.8 * (1 - t) * (1 - t);
      Color3.LerpToRef(BLAST_HOT, BLAST_COOL, t, ring.material.emissiveColor);
    }
  }
}

const MAX_TRACK_QUADS = 3000;
const TRACK_HALF_WIDTH = 0.16;
const TRACK_LIFT = 0.05;
const TRACK_MIN_STEP = 0.35;
const TRACK_MAX_STEP = 6;

interface TrackHead {
  x: number;
  z: number;
  active: boolean;
}

export class SkidTracks {
  private readonly positions = new Float32Array(MAX_TRACK_QUADS * 12);
  private readonly mesh: Mesh;
  private readonly heads: TrackHead[] = [];
  private cursor = 0;
  private dirty = false;

  constructor(scene: Scene, wheelCount: number) {
    const indices = new Uint32Array(MAX_TRACK_QUADS * 6);
    for (let i = 0; i < MAX_TRACK_QUADS; i++) indices.set([i * 4, i * 4 + 1, i * 4 + 2, i * 4 + 1, i * 4 + 3, i * 4 + 2], i * 6);
    this.mesh = new Mesh("tracks", scene);
    this.mesh.setVerticesData(VertexBuffer.PositionKind, this.positions, true);
    this.mesh.setIndices(indices);
    const material = new StandardMaterial("tracks", scene);
    material.disableLighting = true;
    material.emissiveColor = new Color3(0.52, 0.31, 0.2);
    material.alpha = 0.42;
    material.backFaceCulling = false;
    material.zOffset = -2;
    this.mesh.material = material;
    this.mesh.alwaysSelectAsActiveMesh = true;
    this.mesh.isPickable = false;
    this.mesh.alphaIndex = 0;
    for (let i = 0; i < wheelCount; i++) this.heads.push({ x: 0, z: 0, active: false });
  }

  clear(): void {
    this.positions.fill(0);
    this.dirty = true;
    for (const head of this.heads) head.active = false;
  }

  mark(wheel: number, x: number, z: number, sliding: boolean): void {
    const head = this.heads[wheel];
    if (!sliding) {
      head.active = false;
      return;
    }
    if (!head.active) {
      head.x = x;
      head.z = z;
      head.active = true;
      return;
    }
    const dx = x - head.x;
    const dz = z - head.z;
    const length = Math.hypot(dx, dz);
    if (length < TRACK_MIN_STEP) return;
    if (length < TRACK_MAX_STEP) {
      const sx = (dz / length) * TRACK_HALF_WIDTH;
      const sz = (-dx / length) * TRACK_HALF_WIDTH;
      const offset = this.cursor * 12;
      this.writeVertex(offset, head.x - sx, head.z - sz);
      this.writeVertex(offset + 3, head.x + sx, head.z + sz);
      this.writeVertex(offset + 6, x - sx, z - sz);
      this.writeVertex(offset + 9, x + sx, z + sz);
      this.cursor = (this.cursor + 1) % MAX_TRACK_QUADS;
      this.dirty = true;
    }
    head.x = x;
    head.z = z;
  }

  flush(): void {
    if (!this.dirty) return;
    this.dirty = false;
    this.mesh.updateVerticesData(VertexBuffer.PositionKind, this.positions, false, false);
  }

  private writeVertex(offset: number, x: number, z: number): void {
    this.positions[offset] = x;
    this.positions[offset + 1] = groundHeight(x, z) + TRACK_LIFT;
    this.positions[offset + 2] = z;
  }
}

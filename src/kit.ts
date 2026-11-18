import { Color3, Matrix, Mesh, MeshBuilder, Quaternion, Scene, Vector3, VertexBuffer } from "@babylonjs/core";
import { hash2 } from "./math";

export type Triple = [number, number, number];

const NO_ROTATION: Triple = [0, 0, 0];
const UNIT_SCALE: Triple = [1, 1, 1];
const JITTER_QUANTUM = 1000;

function paint(mesh: Mesh, color: Color3): void {
  const count = mesh.getTotalVertices();
  const colors = new Float32Array(count * 4);
  for (let i = 0; i < count; i++) {
    colors[i * 4] = color.r;
    colors[i * 4 + 1] = color.g;
    colors[i * 4 + 2] = color.b;
    colors[i * 4 + 3] = 1;
  }
  mesh.setVerticesData(VertexBuffer.ColorKind, colors);
}

function place(mesh: Mesh, position: Triple, rotation: Triple): void {
  mesh.position.set(position[0], position[1], position[2]);
  mesh.rotation.set(rotation[0], rotation[1], rotation[2]);
}

function roughen(mesh: Mesh, amount: number, seed: number): void {
  const positions = mesh.getVerticesData(VertexBuffer.PositionKind);
  if (!positions) return;
  for (let i = 0; i < positions.length; i += 3) {
    const qx = Math.round(positions[i] * JITTER_QUANTUM);
    const qy = Math.round(positions[i + 1] * JITTER_QUANTUM);
    const qz = Math.round(positions[i + 2] * JITTER_QUANTUM);
    const key = Math.imul(qx, 73856093) ^ Math.imul(qy, 19349663) ^ Math.imul(qz, 83492791);
    const factor = 1 + (hash2(key, seed) * 2 - 1) * amount;
    positions[i] *= factor;
    positions[i + 1] *= factor;
    positions[i + 2] *= factor;
  }
  mesh.setVerticesData(VertexBuffer.PositionKind, positions);
}

export interface CylinderShape {
  top: number;
  bottom: number;
  height: number;
  sides?: number;
}

export interface BlobShape {
  radius: number;
  scale?: Triple;
  roughness?: number;
  seed?: number;
  detail?: number;
}

export class ModelKit {
  private parts: Mesh[] = [];

  constructor(private readonly scene: Scene) {}

  box(size: Triple, position: Triple, color: Color3, rotation: Triple = NO_ROTATION): this {
    const mesh = MeshBuilder.CreateBox("part", { width: size[0], height: size[1], depth: size[2] }, this.scene);
    return this.add(mesh, position, rotation, color);
  }

  cylinder(shape: CylinderShape, position: Triple, color: Color3, rotation: Triple = NO_ROTATION): this {
    const mesh = MeshBuilder.CreateCylinder(
      "part",
      { diameterTop: shape.top, diameterBottom: shape.bottom, height: shape.height, tessellation: shape.sides ?? 8 },
      this.scene,
    );
    return this.add(mesh, position, rotation, color);
  }

  blob(shape: BlobShape, position: Triple, color: Color3, rotation: Triple = NO_ROTATION): this {
    const mesh = MeshBuilder.CreateIcoSphere("part", { radius: shape.radius, subdivisions: shape.detail ?? 1, flat: true }, this.scene);
    roughen(mesh, shape.roughness ?? 0.2, shape.seed ?? 1);
    const scale = shape.scale ?? UNIT_SCALE;
    mesh.scaling.set(scale[0], scale[1], scale[2]);
    return this.add(mesh, position, rotation, color);
  }

  build(name: string): Mesh {
    const merged = Mesh.MergeMeshes(this.parts, true, true);
    if (!merged) throw new Error(`Model ${name} has no parts`);
    this.parts = [];
    merged.name = name;
    merged.convertToFlatShadedMesh();
    return merged;
  }

  private add(mesh: Mesh, position: Triple, rotation: Triple, color: Color3): this {
    place(mesh, position, rotation);
    paint(mesh, color);
    this.parts.push(mesh);
    return this;
  }
}

const scratchScale = new Vector3();
const scratchPosition = new Vector3();
const scratchRotation = new Quaternion();
const scratchMatrix = new Matrix();
const scratchWorld = new Matrix();

export function composeTransform(
  out: Matrix,
  x: number,
  y: number,
  z: number,
  yaw: number,
  pitch: number,
  roll: number,
  sx: number,
  sy: number,
  sz: number,
): Matrix {
  scratchScale.set(sx, sy, sz);
  scratchPosition.set(x, y, z);
  Quaternion.RotationYawPitchRollToRef(yaw, pitch, roll, scratchRotation);
  Matrix.ComposeToRef(scratchScale, scratchRotation, scratchPosition, out);
  return out;
}

export function writeTransform(
  target: Float32Array | number[],
  offset: number,
  x: number,
  y: number,
  z: number,
  yaw: number,
  pitch: number,
  roll: number,
  sx: number,
  sy: number,
  sz: number,
): void {
  composeTransform(scratchMatrix, x, y, z, yaw, pitch, roll, sx, sy, sz).copyToArray(target as Float32Array, offset);
}

export class InstanceBatch {
  readonly matrices: Float32Array;
  count = 0;
  private readonly tints: Float32Array | null;

  constructor(
    readonly mesh: Mesh,
    readonly capacity: number,
    tinted = false,
  ) {
    this.matrices = new Float32Array(capacity * 16);
    mesh.thinInstanceSetBuffer("matrix", this.matrices, 16, false);
    this.tints = tinted ? new Float32Array(capacity * 4).fill(1) : null;
    if (this.tints) mesh.thinInstanceSetBuffer("color", this.tints, 4, false);
    mesh.thinInstanceCount = 0;
    mesh.alwaysSelectAsActiveMesh = true;
    mesh.setEnabled(false);
  }

  begin(): void {
    this.count = 0;
  }

  push(x: number, y: number, z: number, yaw: number, pitch: number, roll: number, sx: number, sy: number, sz: number): void {
    if (this.count >= this.capacity) return;
    writeTransform(this.matrices, this.count * 16, x, y, z, yaw, pitch, roll, sx, sy, sz);
    this.count++;
  }

  pushUnder(
    parent: Matrix,
    x: number,
    y: number,
    z: number,
    yaw: number,
    pitch: number,
    roll: number,
    sx: number,
    sy: number,
    sz: number,
    world: Matrix = scratchWorld,
  ): void {
    composeTransform(scratchMatrix, x, y, z, yaw, pitch, roll, sx, sy, sz).multiplyToRef(parent, world);
    if (this.count >= this.capacity) return;
    world.copyToArray(this.matrices, this.count * 16);
    this.count++;
  }

  tint(r: number, g: number, b: number): void {
    if (!this.tints || this.count === 0) return;
    const offset = (this.count - 1) * 4;
    this.tints[offset] = r;
    this.tints[offset + 1] = g;
    this.tints[offset + 2] = b;
  }

  commit(): void {
    this.mesh.thinInstanceCount = this.count;
    this.mesh.setEnabled(this.count > 0);
    if (this.count === 0) return;
    this.mesh.thinInstanceBufferUpdated("matrix");
    if (this.tints) this.mesh.thinInstanceBufferUpdated("color");
  }
}

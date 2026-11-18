import { Mesh, Scene } from "@babylonjs/core";
import { ModelKit } from "./kit";
import type { LoosePoint, LooseSpec } from "./loose";
import { PALETTE as P } from "./palette";

export interface LocalCollider {
  x: number;
  z: number;
  r: number;
}

export interface PropDef {
  name: string;
  mesh: Mesh;
  colliders: LocalCollider[];
  castsShadow: boolean;
  minScale: number;
  maxScale: number;
  sink: number;
  loose?: LooseSpec;
}

export type PropName =
  | "rockA"
  | "rockB"
  | "spire"
  | "wreck"
  | "tire"
  | "tireDark"
  | "shack"
  | "tower"
  | "wall"
  | "cactus"
  | "deadTree"
  | "barrel"
  | "ribs"
  | "pylon"
  | "pebble"
  | "shrub";

const HALF_PI = Math.PI / 2;
const TIRE_DIAMETER = 1.1;
const TIRE_HEIGHT = 0.36;
const TIRE_TREAD_POINTS = 8;

export interface StackPart {
  name: PropName;
  x: number;
  y: number;
  z: number;
}

export const TIRE_STACK: StackPart[] = [
  { name: "tire", x: 0, y: 0, z: 0 },
  { name: "tireDark", x: 0.08, y: TIRE_HEIGHT + 0.01, z: 0.05 },
  { name: "tire", x: -0.05, y: TIRE_HEIGHT * 2 + 0.02, z: -0.04 },
  { name: "tire", x: 1.15, y: 0, z: 0.4 },
];
export const TIRE_STACK_FOOTPRINT = 1.75;

function solid(r: number): LocalCollider[] {
  return [{ x: 0, z: 0, r }];
}

function stalk(mass: number, height: number, radius: number, limbs: LoosePoint[] = []): LooseSpec {
  const points: LoosePoint[] = [];
  for (let i = 0; i < 4; i++) points.push([0, radius + ((height - radius * 2) * i) / 3, 0, radius]);
  return { mass, radius, centre: height * 0.45, points: [...points, ...limbs] };
}

function tread(mass: number, diameter: number, height: number): LooseSpec {
  const half = height / 2;
  const ring = diameter / 2 - half;
  const points: LoosePoint[] = [];
  for (let i = 0; i < TIRE_TREAD_POINTS; i++) {
    const angle = (i / TIRE_TREAD_POINTS) * Math.PI * 2;
    points.push([Math.sin(angle) * ring, half, Math.cos(angle) * ring, half]);
  }
  return { mass, radius: diameter / 2, centre: half, points };
}

function tuft(mass: number, height: number, radius: number): LooseSpec {
  return { mass, radius, centre: height, points: [[0, height, 0, radius]] };
}

export function buildProps(scene: Scene): Record<PropName, PropDef> {
  const kit = new ModelKit(scene);

  const rockA = kit
    .blob({ radius: 1, scale: [1.25, 0.8, 1], roughness: 0.28, seed: 3 }, [0, 0.35, 0], P.rockMid)
    .build("rockA");

  const rockB = kit
    .blob({ radius: 1, scale: [1, 0.9, 1.1], roughness: 0.3, seed: 7 }, [-0.3, 0.4, 0], P.rockLight)
    .blob({ radius: 0.7, scale: [1, 0.8, 1], roughness: 0.3, seed: 11 }, [0.75, 0.2, 0.35], P.rockMid)
    .blob({ radius: 0.45, roughness: 0.3, seed: 13 }, [0.2, 0.1, -0.95], P.rockDark)
    .build("rockB");

  const spire = kit
    .cylinder({ top: 5.2, bottom: 6.6, height: 4.6, sides: 7 }, [0, 2.1, 0], P.rockDark)
    .cylinder({ top: 4.6, bottom: 5.0, height: 1.2, sides: 7 }, [0.1, 5.0, 0], P.rockPale, [0, 0.4, 0])
    .cylinder({ top: 4.0, bottom: 4.7, height: 3.6, sides: 7 }, [0.15, 7.4, 0.1], P.rockMid, [0, 0.2, 0])
    .cylinder({ top: 3.6, bottom: 4.2, height: 0.9, sides: 7 }, [0.2, 9.6, 0.1], P.rockPale, [0, 0.9, 0])
    .cylinder({ top: 2.4, bottom: 3.7, height: 2.4, sides: 6 }, [0.3, 11.2, 0.2], P.rockLight, [0, 0.5, 0])
    .blob({ radius: 1.6, scale: [1.2, 0.6, 1], roughness: 0.3, seed: 5 }, [2.9, 0.4, 1.2], P.rockMid)
    .blob({ radius: 1.1, scale: [1, 0.7, 1.2], roughness: 0.3, seed: 9 }, [-2.6, 0.3, -1.8], P.rockDark)
    .build("spire");

  const wreck = kit
    .box([1.8, 0.6, 4.0], [0, 0.55, 0], P.rust, [0.03, 0, 0.1])
    .box([1.5, 0.5, 1.7], [0.05, 1.05, -0.3], P.rustDark, [0.03, 0, 0.1])
    .box([1.7, 0.12, 1.2], [0.0, 0.92, 1.3], P.rustLight, [-0.25, 0, 0.1])
    .cylinder({ top: 0.72, bottom: 0.72, height: 0.3, sides: 8 }, [1.3, 0.16, 1.5], P.rubber, [0.1, 0, 0])
    .box([0.3, 0.3, 0.3], [-0.8, 0.2, -1.5], P.metalDark)
    .build("wreck");

  const tireShape = { top: TIRE_DIAMETER, bottom: TIRE_DIAMETER, height: TIRE_HEIGHT, sides: 9 };
  const tire = kit.cylinder(tireShape, [0, TIRE_HEIGHT / 2, 0], P.rubber).build("tire");
  const tireDark = kit.cylinder(tireShape, [0, TIRE_HEIGHT / 2, 0], P.metalDark).build("tireDark");

  const shack = kit
    .box([5, 2.6, 4], [0, 1.3, 0], P.teal)
    .box([5.8, 0.16, 4.9], [0, 2.85, 0], P.rust, [0, 0, 0.09])
    .box([1.0, 1.9, 0.12], [-1.1, 0.95, 2.02], P.rustDark)
    .box([1.3, 0.8, 0.12], [1.2, 1.6, 2.02], P.glass)
    .box([5.1, 0.5, 4.1], [0, 0.25, 0], P.tealDark)
    .cylinder({ top: 0.3, bottom: 0.3, height: 1.6, sides: 6 }, [1.6, 3.6, -1.1], P.metalDark)
    .box([1.6, 1.0, 0.9], [3.3, 0.5, -0.8], P.rustLight, [0, 0.3, 0])
    .build("shack");

  const tower = kit
    .box([0.26, 6.2, 0.26], [1.3, 3.1, 1.3], P.metalDark, [0.06, 0, -0.06])
    .box([0.26, 6.2, 0.26], [-1.3, 3.1, 1.3], P.metalDark, [0.06, 0, 0.06])
    .box([0.26, 6.2, 0.26], [1.3, 3.1, -1.3], P.metalDark, [-0.06, 0, -0.06])
    .box([0.26, 6.2, 0.26], [-1.3, 3.1, -1.3], P.metalDark, [-0.06, 0, 0.06])
    .box([3.0, 0.14, 0.14], [0, 2.4, 1.38], P.metal, [0, 0, 0.5])
    .box([3.0, 0.14, 0.14], [0, 2.4, -1.38], P.metal, [0, 0, -0.5])
    .box([0.14, 0.14, 3.0], [1.38, 3.8, 0], P.metal, [0.5, 0, 0])
    .box([0.14, 0.14, 3.0], [-1.38, 3.8, 0], P.metal, [-0.5, 0, 0])
    .cylinder({ top: 3.5, bottom: 3.5, height: 2.6, sides: 9 }, [0, 7.4, 0], P.rustLight)
    .cylinder({ top: 3.6, bottom: 3.6, height: 0.3, sides: 9 }, [0, 7.0, 0], P.rustDark)
    .cylinder({ top: 0.2, bottom: 3.8, height: 1.1, sides: 9 }, [0, 9.2, 0], P.rust)
    .build("tower");

  const wall = kit
    .box([3.0, 2.6, 0.55], [-3.1, 1.3, 0.1], P.concrete, [0, 0.06, 0.02])
    .box([3.1, 2.1, 0.55], [0, 1.05, -0.1], P.concreteDark, [0.04, -0.05, 0])
    .box([2.9, 1.3, 0.55], [3.1, 0.65, 0.05], P.concrete, [0, 0.04, -0.05])
    .box([0.12, 1.5, 0.12], [3.6, 1.9, 0.05], P.rustDark, [0, 0, 0.2])
    .box([0.12, 1.2, 0.12], [2.7, 1.8, 0.05], P.rustDark, [0, 0, -0.15])
    .box([1.2, 0.5, 0.9], [1.4, 0.25, 0.9], P.concreteDark, [0, 0.5, 0])
    .build("wall");

  const cactus = kit
    .cylinder({ top: 0.42, bottom: 0.5, height: 3.2, sides: 6 }, [0, 1.6, 0], P.cactus)
    .cylinder({ top: 0.3, bottom: 0.3, height: 0.9, sides: 6 }, [0.55, 1.5, 0], P.cactusDark, [0, 0, HALF_PI])
    .cylinder({ top: 0.26, bottom: 0.3, height: 1.2, sides: 6 }, [0.95, 2.0, 0], P.cactus)
    .cylinder({ top: 0.28, bottom: 0.28, height: 0.7, sides: 6 }, [-0.45, 2.0, 0], P.cactusDark, [0, 0, HALF_PI])
    .cylinder({ top: 0.24, bottom: 0.28, height: 0.9, sides: 6 }, [-0.75, 2.4, 0], P.cactus)
    .build("cactus");

  const deadTree = kit
    .cylinder({ top: 0.2, bottom: 0.42, height: 3.4, sides: 5 }, [0, 1.7, 0], P.deadWood, [0, 0, 0.08])
    .cylinder({ top: 0.08, bottom: 0.18, height: 1.8, sides: 5 }, [0.55, 3.0, 0], P.deadWood, [0, 0, -0.8])
    .cylinder({ top: 0.07, bottom: 0.16, height: 1.5, sides: 5 }, [-0.55, 3.4, 0.2], P.deadWood, [0.3, 0, 0.9])
    .cylinder({ top: 0.06, bottom: 0.14, height: 1.3, sides: 5 }, [0, 3.8, -0.4], P.deadWood, [-0.7, 0, 0])
    .build("deadTree");

  const barrel = kit
    .cylinder({ top: 0.7, bottom: 0.7, height: 1.0, sides: 8 }, [0, 0.5, 0], P.raiderRed)
    .cylinder({ top: 0.74, bottom: 0.74, height: 0.1, sides: 8 }, [0, 0.72, 0], P.rustDark)
    .cylinder({ top: 0.74, bottom: 0.74, height: 0.1, sides: 8 }, [0, 0.28, 0], P.rustDark)
    .build("barrel");

  const ribSpacing = 1.7;
  for (let i = 0; i < 5; i++) {
    const z = (i - 2) * ribSpacing;
    const size = 1 - Math.abs(i - 2) * 0.12;
    kit
      .box([0.28, 3.2 * size, 0.28], [-1.5 * size, 1.5 * size, z], P.bone, [0, 0, -0.32])
      .box([0.24, 1.7 * size, 0.24], [-0.62 * size, 3.25 * size, z], P.bone, [0, 0, -1.05])
      .box([0.28, 3.2 * size, 0.28], [1.5 * size, 1.5 * size, z], P.bone, [0, 0, 0.32])
      .box([0.24, 1.7 * size, 0.24], [0.62 * size, 3.25 * size, z], P.bone, [0, 0, 1.05]);
  }
  const ribs = kit.box([0.4, 0.4, 9.4], [0, 3.55, 0], P.bone).build("ribs");

  const pylon = kit
    .cylinder({ top: 0.18, bottom: 0.3, height: 7.5, sides: 5 }, [0, 3.75, 0], P.deadWood, [0, 0, 0.05])
    .box([2.6, 0.16, 0.16], [0.15, 6.6, 0], P.deadWood)
    .box([1.6, 0.14, 0.14], [0.12, 5.8, 0], P.deadWood)
    .box([0.1, 0.3, 0.1], [1.2, 6.8, 0], P.teal)
    .box([0.1, 0.3, 0.1], [-0.9, 6.8, 0], P.teal)
    .build("pylon");

  const pebble = kit.blob({ radius: 0.3, scale: [1.2, 0.6, 1], roughness: 0.3, seed: 21 }, [0, 0.05, 0], P.rockLight).build("pebble");

  const shrub = kit
    .box([0.08, 0.9, 0.08], [0, 0.4, 0], P.shrub, [0.5, 0, 0.3])
    .box([0.08, 0.8, 0.08], [0.1, 0.35, 0], P.shrub, [-0.4, 0, -0.5])
    .box([0.08, 0.7, 0.08], [-0.1, 0.3, 0.1], P.shrub, [0.2, 0, 0.7])
    .box([0.08, 0.75, 0.08], [0, 0.3, -0.1], P.shrub, [-0.6, 0, 0.1])
    .blob({ radius: 0.3, scale: [1.3, 0.5, 1.3], roughness: 0.4, seed: 4 }, [0, 0.12, 0], P.cactusDark)
    .build("shrub");

  const def = (
    mesh: Mesh,
    colliders: LocalCollider[],
    minScale: number,
    maxScale: number,
    castsShadow = true,
    sink = 0.1,
    loose?: LooseSpec,
  ): PropDef => ({ name: mesh.name, mesh, colliders, castsShadow, minScale, maxScale, sink, loose });

  return {
    rockA: def(rockA, solid(0.95), 1.2, 3.6, true, 0.25),
    rockB: def(rockB, solid(1.15), 1.2, 3.2, true, 0.25),
    spire: def(spire, solid(3.3), 0.8, 1.5, true, 0.6),
    wreck: def(wreck, solid(1.9), 1, 1.15),
    tire: def(tire, solid(TIRE_DIAMETER / 2), 1, 1.2, true, 0.02, tread(0.07, TIRE_DIAMETER, TIRE_HEIGHT)),
    tireDark: def(tireDark, solid(TIRE_DIAMETER / 2), 1, 1.2, true, 0.02, tread(0.07, TIRE_DIAMETER, TIRE_HEIGHT)),
    shack: def(shack, solid(3.0), 1, 1.2),
    tower: def(tower, solid(2.0), 1, 1.25),
    wall: def(
      wall,
      [
        { x: -3.1, z: 0, r: 1.5 },
        { x: 0, z: 0, r: 1.5 },
        { x: 3.1, z: 0, r: 1.5 },
      ],
      1,
      1.3,
    ),
    cactus: def(
      cactus,
      solid(0.45),
      0.8,
      1.5,
      true,
      0.1,
      stalk(0.2, 3.2, 0.45, [
        [0.95, 2.4, 0, 0.3],
        [-0.75, 2.65, 0, 0.28],
      ]),
    ),
    deadTree: def(
      deadTree,
      solid(0.4),
      0.9,
      1.6,
      true,
      0.1,
      stalk(0.15, 3.4, 0.32, [
        [1.15, 3.55, 0, 0.14],
        [-1.1, 3.85, 0.3, 0.14],
        [0, 4.2, -0.8, 0.14],
      ]),
    ),
    barrel: def(barrel, solid(0.45), 1, 1.1),
    ribs: def(ribs, [], 0.9, 1.6, true, 0.3),
    pylon: def(pylon, solid(0.35), 1, 1.2),
    pebble: def(pebble, [], 0.5, 1.6, false, 0),
    shrub: def(shrub, [], 0.8, 1.8, false, 0, tuft(0.012, 0.32, 0.36)),
  };
}

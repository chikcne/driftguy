import { Mesh, Scene, TransformNode } from "@babylonjs/core";
import { ModelKit, type Triple } from "./kit";
import { PALETTE as P } from "./palette";
import { AXLE_FRONT, AXLE_REAR, HALF_TRACK } from "./vehicle";

const HALF_PI = Math.PI / 2;
const WHEEL_AXIS: Triple = [0, 0, HALF_PI];

export interface PlayerCarModel {
  root: TransformNode;
  lean: TransformNode;
  body: Mesh;
  steerPivots: TransformNode[];
  wheels: Mesh[];
  gun: Mesh;
  fan: Mesh;
  plow: Mesh;
  shadowCasters: Mesh[];
}

export const WHEEL_RADIUS = 0.37;
const WHEEL_X = HALF_TRACK + 0.08;

function buildWheel(kit: ModelKit, name: string): Mesh {
  return kit
    .cylinder({ top: WHEEL_RADIUS * 2, bottom: WHEEL_RADIUS * 2, height: 0.32, sides: 10 }, [0, 0, 0], P.rubber, WHEEL_AXIS)
    .cylinder({ top: 0.4, bottom: 0.4, height: 0.34, sides: 6 }, [0, 0, 0], P.carStripeAlt, WHEEL_AXIS)
    .box([0.36, 0.1, 0.5], [0, 0, 0], P.metalDark)
    .build(name);
}

export function buildPlayerCar(scene: Scene): PlayerCarModel {
  const kit = new ModelKit(scene);
  const root = new TransformNode("car", scene);
  const lean = new TransformNode("carLean", scene);
  lean.parent = root;

  const body = kit
    .box([1.8, 0.5, 4.2], [0, 0.62, 0], P.carBody)
    .box([1.84, 0.16, 4.24], [0, 0.42, 0], P.carStripe)
    .box([0.46, 0.03, 1.5], [-0.2, 0.885, 1.32], P.carStripe)
    .box([0.16, 0.03, 1.5], [0.24, 0.885, 1.32], P.carStripeAlt)
    .box([1.56, 0.46, 1.9], [0, 1.08, -0.3], P.glass)
    .box([1.62, 0.1, 1.7], [0, 1.36, -0.32], P.carBody)
    .box([0.46, 0.03, 1.7], [-0.2, 1.42, -0.32], P.carStripe)
    .box([0.16, 0.03, 1.7], [0.24, 1.42, -0.32], P.carStripeAlt)
    .box([0.14, 0.5, 0.14], [0.74, 1.08, 0.6], P.carBody, [0.5, 0, 0])
    .box([0.14, 0.5, 0.14], [-0.74, 1.08, 0.6], P.carBody, [0.5, 0, 0])
    .box([0.46, 0.03, 0.9], [-0.2, 0.885, -1.65], P.carStripe)
    .box([0.16, 0.03, 0.9], [0.24, 0.885, -1.65], P.carStripeAlt)
    .box([1.92, 0.2, 0.22], [0, 0.44, 2.16], P.metalDark)
    .box([1.92, 0.2, 0.22], [0, 0.44, -2.16], P.metalDark)
    .box([1.3, 0.34, 0.1], [0, 0.7, 2.24], P.metal)
    .box([0.36, 0.16, 0.06], [0.62, 0.7, 2.11], P.headlight)
    .box([0.36, 0.16, 0.06], [-0.62, 0.7, 2.11], P.headlight)
    .box([0.4, 0.14, 0.06], [0.62, 0.72, -2.11], P.tailLight)
    .box([0.4, 0.14, 0.06], [-0.62, 0.72, -2.11], P.tailLight)
    .box([0.2, 0.18, 0.14], [0.45, 1.5, 0.42], P.headlight)
    .box([0.2, 0.18, 0.14], [0.15, 1.5, 0.42], P.headlight)
    .box([0.2, 0.18, 0.14], [-0.15, 1.5, 0.42], P.headlight)
    .box([0.2, 0.18, 0.14], [-0.45, 1.5, 0.42], P.headlight)
    .box([1.76, 0.07, 0.42], [0, 1.28, -2.02], P.carStripe, [-0.12, 0, 0])
    .box([0.1, 0.36, 0.3], [0.7, 1.06, -1.98], P.metalDark)
    .box([0.1, 0.36, 0.3], [-0.7, 1.06, -1.98], P.metalDark)
    .box([0.16, 0.36, 1.0], [0.94, 0.6, AXLE_FRONT], P.metalDark)
    .box([0.16, 0.36, 1.0], [-0.94, 0.6, AXLE_FRONT], P.metalDark)
    .box([0.16, 0.36, 1.0], [0.94, 0.6, -AXLE_REAR], P.metalDark)
    .box([0.16, 0.36, 1.0], [-0.94, 0.6, -AXLE_REAR], P.metalDark)
    .cylinder({ top: 0.16, bottom: 0.16, height: 0.8, sides: 6 }, [0.98, 0.5, -1.9], P.metal, [HALF_PI, 0, 0])
    .cylinder({ top: 0.16, bottom: 0.16, height: 0.8, sides: 6 }, [-0.98, 0.5, -1.9], P.metal, [HALF_PI, 0, 0])
    .box([0.5, 0.36, 0.3], [0.45, 1.06, -1.55], P.raiderRed)
    .build("carBody");
  body.parent = lean;

  const steerPivots: TransformNode[] = [];
  const wheels: Mesh[] = [];
  const wheelSpots: Array<[number, number]> = [
    [-WHEEL_X, AXLE_FRONT],
    [WHEEL_X, AXLE_FRONT],
    [-WHEEL_X, -AXLE_REAR],
    [WHEEL_X, -AXLE_REAR],
  ];
  for (const [x, z] of wheelSpots) {
    const pivot = new TransformNode("wheelPivot", scene);
    pivot.parent = root;
    pivot.position.set(x, WHEEL_RADIUS, z);
    const wheel = buildWheel(kit, "wheel");
    wheel.parent = pivot;
    steerPivots.push(pivot);
    wheels.push(wheel);
  }

  const gun = kit
    .cylinder({ top: 0.5, bottom: 0.62, height: 0.24, sides: 8 }, [0, 0.12, 0], P.metalDark)
    .box([0.34, 0.3, 0.6], [0, 0.36, 0], P.metal)
    .box([0.1, 0.1, 1.2], [0.09, 0.4, 0.8], P.metalDark)
    .box([0.1, 0.1, 1.2], [-0.09, 0.4, 0.8], P.metalDark)
    .box([0.26, 0.2, 0.3], [0.28, 0.34, -0.05], P.raiderYellow)
    .build("gun");
  gun.parent = lean;
  gun.position.set(0, 1.42, -0.4);
  gun.setEnabled(false);

  const fan = kit
    .box([1.5, 0.16, 0.06], [0, 0, 0], P.metal)
    .box([0.16, 1.5, 0.06], [0, 0, 0], P.metal)
    .box([1.1, 0.14, 0.06], [0, 0, 0], P.metalDark, [0, 0, Math.PI / 4])
    .box([0.14, 1.1, 0.06], [0, 0, 0], P.metalDark, [0, 0, Math.PI / 4])
    .cylinder({ top: 0.34, bottom: 0.34, height: 0.2, sides: 8 }, [0, 0, 0], P.carStripeAlt, [HALF_PI, 0, 0])
    .build("fan");
  fan.parent = lean;
  fan.position.set(0, 1.25, -2.42);
  fan.setEnabled(false);

  const plow = kit
    .box([1.1, 0.7, 0.12], [0.5, 0, 0.12], P.metal, [0.25, 0.45, 0])
    .box([1.1, 0.7, 0.12], [-0.5, 0, 0.12], P.metal, [0.25, -0.45, 0])
    .box([0.16, 0.5, 0.5], [0, 0.05, 0.38], P.raiderYellow)
    .cylinder({ top: 0, bottom: 0.18, height: 0.5, sides: 5 }, [0.6, 0.1, 0.42], P.metalDark, [HALF_PI, 0, 0])
    .cylinder({ top: 0, bottom: 0.18, height: 0.5, sides: 5 }, [-0.6, 0.1, 0.42], P.metalDark, [HALF_PI, 0, 0])
    .build("plow");
  plow.parent = lean;
  plow.position.set(0, 0.55, 2.28);
  plow.setEnabled(false);

  return { root, lean, body, steerPivots, wheels, gun, fan, plow, shadowCasters: [body, ...wheels, gun, fan, plow] };
}

export type EnemyKind = "bike" | "buggy" | "truck" | "interceptor" | "rig";

function wheelPair(kit: ModelKit, x: number, z: number, diameter: number, width: number): void {
  const shape = { top: diameter, bottom: diameter, height: width, sides: 8 };
  kit.cylinder(shape, [x, diameter / 2, z], P.rubber, WHEEL_AXIS).cylinder(shape, [-x, diameter / 2, z], P.rubber, WHEEL_AXIS);
}

function spike(kit: ModelKit, position: Triple, length: number): void {
  kit.cylinder({ top: 0, bottom: 0.16, height: length, sides: 5 }, position, P.raiderBone, [HALF_PI, 0, 0]);
}

export function buildEnemyModels(scene: Scene): Record<EnemyKind, Mesh> {
  const kit = new ModelKit(scene);

  kit
    .cylinder({ top: 0.72, bottom: 0.72, height: 0.2, sides: 8 }, [0, 0.36, 0.85], P.rubber, WHEEL_AXIS)
    .cylinder({ top: 0.72, bottom: 0.72, height: 0.24, sides: 8 }, [0, 0.36, -0.8], P.rubber, WHEEL_AXIS)
    .box([0.26, 0.34, 1.5], [0, 0.62, 0], P.raiderRed)
    .box([0.34, 0.24, 0.5], [0, 0.82, 0.2], P.raiderBlack)
    .box([0.8, 0.07, 0.07], [0, 1.02, 0.62], P.metalDark)
    .box([0.1, 0.5, 0.1], [0, 0.78, 0.74], P.metalDark, [0.4, 0, 0])
    .box([0.46, 0.62, 0.32], [0, 1.2, -0.2], P.raiderBlack, [0.3, 0, 0])
    .blob({ radius: 0.2, roughness: 0.05 }, [0, 1.62, 0.0], P.raiderBone)
    .box([0.06, 1.5, 0.06], [0, 1.5, -0.85], P.metalDark)
    .box([0.04, 0.34, 0.6], [0, 2.05, -1.15], P.raiderRed);
  const bike = kit.build("bike");

  wheelPair(kit, 0.95, 1.05, 0.9, 0.36);
  wheelPair(kit, 1.0, -1.05, 1.0, 0.44);
  kit
    .box([1.5, 0.3, 3.0], [0, 0.6, 0], P.rust)
    .box([1.2, 0.34, 1.0], [0, 0.86, 1.0], P.raiderRed, [0.12, 0, 0])
    .box([1.0, 0.5, 0.8], [0, 0.98, -1.05], P.metalDark)
    .cylinder({ top: 0.14, bottom: 0.14, height: 0.9, sides: 5 }, [0.3, 1.5, -1.2], P.metal)
    .cylinder({ top: 0.14, bottom: 0.14, height: 0.9, sides: 5 }, [-0.3, 1.5, -1.2], P.metal)
    .box([0.08, 1.0, 0.08], [0.66, 1.25, 0.45], P.raiderBlack, [0.25, 0, 0])
    .box([0.08, 1.0, 0.08], [-0.66, 1.25, 0.45], P.raiderBlack, [0.25, 0, 0])
    .box([0.08, 1.0, 0.08], [0.66, 1.25, -0.5], P.raiderBlack, [-0.25, 0, 0])
    .box([0.08, 1.0, 0.08], [-0.66, 1.25, -0.5], P.raiderBlack, [-0.25, 0, 0])
    .box([1.4, 0.08, 1.0], [0, 1.72, -0.02], P.raiderBlack)
    .blob({ radius: 0.22, roughness: 0.05 }, [0, 1.3, -0.05], P.raiderBone)
    .box([1.7, 0.16, 0.16], [0, 0.6, 1.58], P.metalDark);
  spike(kit, [0.6, 0.62, 1.86], 0.6);
  spike(kit, [0, 0.62, 1.9], 0.7);
  spike(kit, [-0.6, 0.62, 1.86], 0.6);
  const buggy = kit.build("buggy");

  wheelPair(kit, 1.2, 1.8, 1.2, 0.5);
  wheelPair(kit, 1.2, -0.9, 1.2, 0.5);
  wheelPair(kit, 1.2, -2.2, 1.2, 0.5);
  kit
    .box([2.2, 0.5, 5.6], [0, 0.95, -0.2], P.raiderBlack)
    .box([2.2, 1.3, 1.7], [0, 1.85, 1.5], P.rustDark)
    .box([1.9, 0.5, 0.1], [0, 2.0, 2.37], P.glass)
    .box([2.3, 1.0, 3.3], [0, 1.7, -1.3], P.rust)
    .box([2.36, 0.14, 3.36], [0, 2.26, -1.3], P.rustLight)
    .box([1.5, 1.1, 0.14], [0.7, 0.85, 2.85], P.metal, [0.2, 0.5, 0])
    .box([1.5, 1.1, 0.14], [-0.7, 0.85, 2.85], P.metal, [0.2, -0.5, 0])
    .cylinder({ top: 0.2, bottom: 0.2, height: 1.6, sides: 6 }, [1.0, 3.0, 0.55], P.metal)
    .cylinder({ top: 0.2, bottom: 0.2, height: 1.6, sides: 6 }, [-1.0, 3.0, 0.55], P.metal)
    .blob({ radius: 0.34, roughness: 0.08 }, [0, 1.5, 2.42], P.raiderBone)
    .box([0.08, 1.7, 0.08], [0.9, 3.1, -2.6], P.metalDark)
    .box([0.05, 0.5, 0.8], [0.9, 3.7, -3.0], P.raiderRed);
  const truck = kit.build("truck");

  wheelPair(kit, 0.95, 1.3, 0.76, 0.34);
  wheelPair(kit, 1.0, -1.3, 0.86, 0.44);
  kit
    .box([1.86, 0.46, 4.4], [0, 0.6, 0], P.raiderPurple)
    .box([1.5, 0.4, 1.7], [0, 1.0, -0.5], P.raiderBlack)
    .box([1.56, 0.08, 1.4], [0, 1.24, -0.55], P.raiderPurple)
    .box([0.6, 0.42, 0.7], [0, 1.0, 1.15], P.metal)
    .box([0.7, 0.16, 0.5], [0, 1.28, 1.2], P.raiderYellow)
    .box([1.9, 0.08, 0.5], [0, 1.1, -2.1], P.raiderBlack, [-0.2, 0, 0])
    .box([1.96, 0.2, 0.2], [0, 0.46, 2.26], P.metalDark)
    .cylinder({ top: 0.18, bottom: 0.18, height: 1.6, sides: 6 }, [1.02, 0.5, -1.2], P.metal, [HALF_PI, 0, 0])
    .cylinder({ top: 0.18, bottom: 0.18, height: 1.6, sides: 6 }, [-1.02, 0.5, -1.2], P.metal, [HALF_PI, 0, 0]);
  spike(kit, [0.7, 0.5, 2.6], 0.7);
  spike(kit, [-0.7, 0.5, 2.6], 0.7);
  const interceptor = kit.build("interceptor");

  for (const z of [3.6, 1.0, -0.3, -3.0, -4.3]) wheelPair(kit, 1.45, z, 1.4, 0.6);
  kit
    .box([2.7, 0.6, 10.6], [0, 1.15, -0.4], P.raiderBlack)
    .box([2.7, 1.7, 2.2], [0, 2.3, 3.4], P.raiderRed)
    .box([2.3, 0.6, 0.1], [0, 2.6, 4.52], P.glass)
    .box([2.4, 1.0, 1.4], [0, 1.9, 5.0], P.rustDark)
    .cylinder({ top: 2.6, bottom: 2.6, height: 6.6, sides: 10 }, [0, 2.75, -1.9], P.rust, [HALF_PI, 0, 0])
    .cylinder({ top: 2.7, bottom: 2.7, height: 0.3, sides: 10 }, [0, 2.75, 0.2], P.rustDark, [HALF_PI, 0, 0])
    .cylinder({ top: 2.7, bottom: 2.7, height: 0.3, sides: 10 }, [0, 2.75, -4.0], P.rustDark, [HALF_PI, 0, 0])
    .box([2.2, 1.5, 0.18], [0.95, 1.1, 5.95], P.metal, [0.25, 0.55, 0])
    .box([2.2, 1.5, 0.18], [-0.95, 1.1, 5.95], P.metal, [0.25, -0.55, 0])
    .cylinder({ top: 0.26, bottom: 0.26, height: 2.4, sides: 6 }, [1.2, 4.0, 2.5], P.metal)
    .cylinder({ top: 0.26, bottom: 0.26, height: 2.4, sides: 6 }, [-1.2, 4.0, 2.5], P.metal)
    .blob({ radius: 0.5, roughness: 0.08 }, [0, 2.2, 5.75], P.raiderBone)
    .box([0.1, 2.4, 0.1], [1.2, 5.0, -4.6], P.metalDark)
    .box([0.06, 0.8, 1.3], [1.2, 5.8, -5.3], P.raiderYellow);
  for (const z of [-3.4, -2.0, -0.6]) {
    kit.cylinder({ top: 0, bottom: 0.3, height: 0.9, sides: 5 }, [0, 4.4, z], P.raiderBone);
  }
  const rig = kit.build("rig");

  return { bike, buggy, truck, interceptor, rig };
}

export function buildScrapModel(scene: Scene): Mesh {
  return new ModelKit(scene)
    .cylinder({ top: 0.7, bottom: 0.7, height: 0.2, sides: 6 }, [0, 0, 0], P.scrap, [HALF_PI, 0, 0])
    .box([0.26, 0.26, 0.26], [0, 0, 0], P.metalDark)
    .build("scrap");
}

export function buildRepairModel(scene: Scene): Mesh {
  return new ModelKit(scene)
    .box([0.9, 0.9, 0.5], [0, 0, 0], P.carBody)
    .box([0.7, 0.22, 0.54], [0, 0, 0], P.repair)
    .box([0.22, 0.7, 0.54], [0, 0, 0], P.repair)
    .build("repair");
}

export function buildBulletModel(scene: Scene): Mesh {
  return new ModelKit(scene).box([0.14, 0.14, 1.4], [0, 0, 0], P.headlight).build("bullet");
}

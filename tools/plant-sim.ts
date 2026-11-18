import { LooseSystem, type LooseSpec, type Shove } from "../src/loose";
import { type Anchor, type Strain, strain, sway } from "../src/roots";
import { groundHeight } from "../src/terrain";

const cactus: LooseSpec = {
  mass: 0.2,
  radius: 0.45,
  centre: 1.44,
  points: [
    [0, -0.3, 0, 0.4],
    [0, 0.45, 0, 0.45],
    [0, 1.22, 0, 0.45],
    [0, 1.98, 0, 0.45],
    [0, 2.75, 0, 0.45],
    [0.95, 2.4, 0, 0.3],
    [-0.75, 2.65, 0, 0.28],
  ],
};
const shrub: LooseSpec = { mass: 0.012, radius: 0.36, centre: 0.32, points: [[0, 0.32, 0, 0.36]] };

function run(label: string, spec: LooseSpec, scale: number, speed: number, lateral: number): void {
  const system = new LooseSystem<string>();
  const startZ = 40;
  const body = system.spawn(label, spec, 100 + lateral, groundHeight(100 + lateral, startZ) - 0.1, startZ, 0.4, scale, scale);
  const car = { x: 100, z: startZ - 6, vx: 0, vz: speed };
  const shove: Shove = { hit: false, impulse: 0, x: 0, z: 0, torn: 0 };
  const dt = 1 / 60;
  let total = 0;
  let hits = 0;
  let peak = 0;
  let settled = -1;
  const target = new Float32Array(16);
  for (let frame = 0; frame < 600; frame++) {
    car.x += car.vx * dt;
    car.z += car.vz * dt;
    system.shove(car, 1.45, 1, shove);
    if (shove.impulse > 0) {
      total += shove.impulse;
      hits++;
    }
    system.step(dt, car.x, car.z);
    peak = Math.max(peak, body.y - groundHeight(body.x, body.z));
    if (body.asleep && settled < 0) settled = frame * dt;
    if (system.bodies.length === 0) break;
  }
  system.write(label, target);
  const finite = target.every((value) => Number.isFinite(value));
  const up = 1 - 2 * (body.qx * body.qx + body.qz * body.qz);
  console.log(
    `${label} scale=${scale} speed=${speed} lateral=${lateral}: car ${speed.toFixed(1)} -> ${Math.hypot(car.vx, car.vz).toFixed(1)} m/s (side ${car.vx.toFixed(2)}), ` +
      `hits=${hits} impulse=${total.toFixed(2)}, plant travelled ${Math.hypot(body.x - 100 - lateral, body.z - startZ).toFixed(1)} m, peak ${peak.toFixed(1)} m, ` +
      `settled ${settled.toFixed(2)} s, upright ${up.toFixed(2)}, rest height ${(body.y - groundHeight(body.x, body.z)).toFixed(2)}, finite=${finite}`,
  );
}

run("cactus", cactus, 0.8, 30, 0);
run("cactus", cactus, 1, 30, 0);
run("cactus", cactus, 1.5, 30, 0);
run("cactus", cactus, 1.5, 30, 1.2);
run("cactus", cactus, 1, 10, 0.8);
run("cactus", cactus, 1, 2, 0);
run("shrub", shrub, 1.2, 30, 0.3);

function ram(label: string, spec: LooseSpec, hold: number, tear: number, scale: number, speed: number, lateral: number, mass = 1, thrust = 0): void {
  const system = new LooseSystem<string>();
  const startZ = 40;
  const radius = 1.45;
  const anchor: Anchor = { x: 100 + lateral, z: startZ, r: spec.radius * scale, hold: hold * scale * scale, tear: tear * scale * scale, leanX: 0, leanZ: 0, swayX: 0, swayZ: 0 };
  const car = { x: 100, z: startZ - 6, vx: 0, vz: speed };
  const grip: Strain = { impulse: 0, x: 0, z: 0 };
  const shove: Shove = { hit: false, impulse: 0, x: 0, z: 0, torn: 0 };
  const dt = 1 / 60;
  let rooted = true;
  let peakLean = 0;
  let restLean = 0;
  let tornAt = -1;
  let slowest = speed;
  for (let frame = 0; frame < 360; frame++) {
    car.vz += thrust * dt;
    car.x += car.vx * dt;
    car.z += car.vz * dt;
    if (rooted && strain(anchor, car, radius, mass, grip) === "torn") {
      rooted = false;
      tornAt = frame * dt;
      system.spawn(label, spec, anchor.x, groundHeight(anchor.x, anchor.z) - 0.1, anchor.z, 0.4, scale, scale);
    }
    system.shove(car, radius, mass, shove);
    system.step(dt, car.x, car.z);
    if (rooted) sway(anchor, dt);
    restLean = Math.hypot(anchor.leanX, anchor.leanZ);
    peakLean = Math.max(peakLean, restLean);
    slowest = Math.min(slowest, Math.hypot(car.vx, car.vz));
  }
  console.log(
    `${label} rooted scale=${scale} mass=${mass} speed=${speed} lateral=${lateral} thrust=${thrust}: ${rooted ? "HELD" : `torn at ${tornAt.toFixed(2)} s`}, ` +
      `car ${speed.toFixed(1)} -> ${Math.hypot(car.vx, car.vz).toFixed(1)} m/s (vx ${car.vx.toFixed(1)}, vz ${car.vz.toFixed(1)}, slowest ${slowest.toFixed(1)}), ` +
      `peak lean ${((peakLean * 180) / Math.PI).toFixed(1)} deg, final lean ${((restLean * 180) / Math.PI).toFixed(2)} deg`,
  );
}

const tree: LooseSpec = {
  mass: 0.15,
  radius: 0.32,
  centre: 1.53,
  points: [
    [0, -0.3, 0, 0.38],
    [0, 0.32, 0, 0.32],
    [0, 1.24, 0, 0.32],
    [0, 2.16, 0, 0.32],
    [0, 3.08, 0, 0.32],
  ],
};

for (const scale of [0.8, 1, 1.5]) for (const speed of [4, 8, 12, 20, 30]) ram("cactus", cactus, 9, 4.5, scale, speed, 0);
ram("cactus", cactus, 9, 4.5, 1, 30, 1.5);
ram("cactus", cactus, 9, 4.5, 1, 12, 1.2);
ram("cactus", cactus, 9, 4.5, 1, 0, 0, 1, 14);
ram("cactus", cactus, 9, 4.5, 1, 30, 0, 0.2);
ram("cactus", cactus, 9, 4.5, 1, 19, 0, 1.5);
for (const scale of [0.9, 1.6]) for (const speed of [8, 20, 33]) ram("tree", tree, 10, 5, scale, speed, 0);

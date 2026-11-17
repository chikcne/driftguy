import { LooseSystem, type LooseSpec, type Shove } from "../src/loose";
import { groundHeight } from "../src/terrain";

const cactus: LooseSpec = {
  mass: 0.2,
  radius: 0.45,
  centre: 1.44,
  points: [
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
  const shove: Shove = { hit: false, impulse: 0, x: 0, z: 0 };
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

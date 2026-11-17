import { Color3, FreeCamera, InternalTexture, InternalTextureSource, NullEngine, Scene, Vector3 } from "@babylonjs/core";
import { PUFF, type SmokeEnvironment, SmokeSystem } from "../src/smoke";

const engine = new NullEngine();
engine.createRawTexture3D = () => new InternalTexture(engine, InternalTextureSource.Raw3D);
engine.updateRawTexture3D = () => undefined;
const scene = new Scene(engine);
const camera = new FreeCamera("camera", new Vector3(0, 56, -42), scene);
const smoke = new SmokeSystem(scene, camera, new Color3(0.8, 0.7, 0.6), 60, 160);
const forward = new Vector3(0, -0.8, 0.6).normalize();
const env: SmokeEnvironment = {
  time: 0,
  carX: 0,
  carZ: 0,
  carVx: 0,
  carVz: 0,
  carFx: 0,
  carFz: 1,
  fanPower: 0,
  fanRange: 0,
  cameraForward: forward,
  cameraPosition: camera.position,
  sunDirection: new Vector3(-0.4, -0.8, 0.3).normalize(),
};

const dt = 1 / 60;
const puffsPerFrame = Number(process.argv[2] ?? 18);
const warmupFrames = 600;
const measuredFrames = 1800;
let heading = 0;
let elapsed = 0;
let peak = 0;
let population = 0;

for (let frame = 0; frame < warmupFrames + measuredFrames; frame++) {
  heading += 0.9 * dt;
  const speed = 18;
  env.time += dt;
  env.carFx = Math.sin(heading);
  env.carFz = Math.cos(heading);
  env.carVx = Math.sin(heading - 0.6) * speed;
  env.carVz = Math.cos(heading - 0.6) * speed;
  env.carX += env.carVx * dt;
  env.carZ += env.carVz * dt;
  camera.position.set(env.carX, 56, env.carZ - 42);
  for (let i = 0; i < puffsPerFrame; i++) {
    smoke.emit(
      PUFF.white,
      env.carX - env.carFx * 1.4 + (Math.random() - 0.5) * 1.6,
      0.35,
      env.carZ - env.carFz * 1.4 + (Math.random() - 0.5) * 1.6,
      env.carVx * 0.3 - env.carFx * 2,
      1.8,
      env.carVz * 0.3 - env.carFz * 2,
      0.85,
      1.25,
      5.5,
      0.9,
      1,
    );
  }
  const start = performance.now();
  smoke.update(dt, env);
  const cost = performance.now() - start;
  if (frame >= warmupFrames) {
    elapsed += cost;
    peak = Math.max(peak, cost);
    population += smoke.count;
  }
}

console.log(`puffs=${Math.round(population / measuredFrames)} mean=${(elapsed / measuredFrames).toFixed(3)}ms peak=${peak.toFixed(3)}ms`);

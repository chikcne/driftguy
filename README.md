<img src="assets/icon.svg" width="64" height="64" alt="">

# driftguy

A wasteland drift-survival game built with Babylon.js. Your tyre smoke is the weapon: slide the car, engulf the raiders chasing you, collect their scrap, and bolt on upgrades.

## Run

```sh
pnpm install
pnpm dev -- --host <address>
```

`pnpm build` type-checks and produces a static bundle in `dist/`.

## Controls

| Action          | Controller  | Keyboard     |
| --------------- | ----------- | ------------ |
| Throttle        | RT          | W / ↑        |
| Brake / reverse | LT          | S / ↓        |
| Steer           | Left stick  | A D / ← →    |
| Handbrake       | B / X / RB  | Space        |
| Nitrous         | A           | E            |
| Pause           | Start       | Esc          |
| Mute            |             | M            |

Damaging raiders fills the nitrous gauge; each full gauge banks a tank, up to three. On the upgrade screen the controller's A button is ignored for the first second so a nitrous press can't pick a card by accident.

## Layout

- `src/vehicle.ts` — car handling model. `pnpm sim` prints drift telemetry for tuning it without a browser.
- `src/smoke.ts` — smoke puff simulation and the density grid enemies are damaged through. `pnpm smoke-bench` measures its CPU cost headless.
- `src/smokeVolume.ts` — volumetric smoke rendering: voxelises the puffs into 3D textures each frame and ray-marches them as a solid, cel-shaded surface of clustered lumps with hard two-tone sun shading.
- `src/world.ts`, `src/terrain.ts`, `src/props.ts` — infinite chunked desert and its obstacles.
- `src/loose.ts` — tumbling physics for plants knocked out of the ground. `pnpm plant-sim` prints what a hit costs the car.
- `src/enemies.ts` — raider vehicles and the spawn director.
- `src/gibs.ts` — the wreckage a dead raider bursts into: per-vehicle part lists and their bounce, roll and settle physics.
- `src/upgrades.ts` — upgrade definitions and the stats derived from them.
- `src/main.ts` — game loop and state.

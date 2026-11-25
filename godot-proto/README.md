# Driftguy — Godot 4 / iOS Port

Full Godot 4.7 (Metal / `Mobile` renderer) port of **Driftguy**, complete with gyroscope steering and a **counter-rotating horizon-locked screen** (camera counter-rotates around its view axis so the desert stays physically level as you turn the iPhone like a steering wheel).

## Ported Systems

- `scripts/car_body.gd` — 1:1 port of `src/vehicle.ts` (240 Hz substeps, Pacejka tyre curves, handbrake lock, drift catch, nitrous).
- `scripts/car_model.gd`, `scripts/model_kit.gd`, `scripts/models.gd` — Procedural player car + upgrade attachments (`Spiral Gun`, `Turbine Fan`, `Ram Plow`), all 5 enemy archetypes (`bike`, `buggy`, `truck`, `interceptor`, `rig`), animated bike riders, pickups, bullets, and 7 gib piece shapes.
- `scripts/world.gd`, `scripts/props.gd`, `scripts/roots.gd`, `scripts/loose.gd`, `scripts/terrain.gd` — Infinite chunked desert heightfield, deterministic outposts & 16 wasteland props via `MultiMeshInstance3D`, breakable scrap barrels, rooted cacti/dead trees that resist, bend, sway, and uproot, and 120 Hz loose rigid-body physics for plants and knocked-over tyre stacks.
- `scripts/smoke.gd`, `shaders/smoke_lump.gdshader`, `shaders/smoke_dust.gdshader`, `shaders/enemy_silhouette.gdshader` — Full puff simulation (wind, billows, eddies, car wake, turbine fan push, shockwaves, spatial damage/stir grid) rendered as GPU cel-shaded clustered 3D smoke clouds, plus view-space depth occluded grey silhouettes for enemies inside smoke or behind scenery.
- `scripts/enemies.gd` — All 5 raider classes, smoke blindness/slow/ember/toxic reactions, bike rider face-covering animation, skidding out-of-control wrecks, enemy-enemy bumping, thrown bike riders, and progressive `Spawner` with War Party waves and War Rig bosses.
- `scripts/combat.gd`, `scripts/gibs.gd`, `scripts/effects.gd`, `scripts/skid_tracks.gd` — Spiral turret gun, scrap & repair crate pickups with magnet pull, flying vehicle wreckage gibs with soot/fire trails and bouncing/rolling wheels, explosion spheres, shockwave rings, and ring-buffer tyre tracks.
- `scripts/upgrades.gd` — All 14 upgrades + Field Repair, weighted choice rolling, and stat derivation.
- `scripts/game_audio.gd` — Procedural synthesized audio (4-gear engine, tyre skid, nitrous roar, explosions, wrecks, screeches, crunches, gunshots, pickups, chimes, warnings) using pre-generated PCM buffers and native `AudioServer` DSP buses.
- `scripts/gyro_stabilizer.gd`, `scripts/hud.gd`, `shaders/vignette.gdshader`, `scripts/main.gd` — Complete game loop (`Title`, `Playing`, `Level Up`, `Paused`, `Dying`, `Game Over`), continuous hold-to-boost nitrous bar, horizon-aware off-screen threat indicators, fixed-to-glass touch controls, gamepad + keyboard support, and live Gyro Tuning drawer.

## Controls

### iPhone (Gyro + Touch)
- **Tilt phone** — Steer (with horizon-locked counter-rotating camera)
- **AUTO GAS** — Hands-free throttle toggle (ON by default)
- **BRAKE / REV** — Left thumb pad
- **NITRO** — Right thumb pad (hold to boost, tap/feather to sharpen drifts)
- **DRIFT** — Right thumb handbrake pad
- **GYRO** (top-right) — Live tuning drawer (Screen Lock `100% / 50% / 0%`, Max Tilt, IMU Fusion, Tilt Zoom Comp, Horizon Bar, Invert Roll, Zero Tilt)

### macOS Desktop Preview / Controller
- `W` / `S` or `↑` / `↓` (or `RT` / `LT`) — Throttle / Brake & Reverse
- `A` / `D` or `←` / `→` (or Left Stick) — Steer
- `Space` / `Shift` (or `B` / `X` / `RB`) — Handbrake (Drift)
- `E` / `N` / `F` (or `A`) — Nitrous (hold to boost / feather in drifts)
- `Esc` / `P` (or `Start`) — Pause, `M` — Mute, `R` — Zero Tilt

## Running & Exporting to iOS

1. **Preview on macOS:** Open `godot-proto/project.godot` in Godot 4.7+ and press **Play** (`Cmd+B`).
2. **Deploy to iPhone:**
   - Open `godot-proto/project.godot` in Godot 4.7+ with iOS Export Templates installed.
   - Go to **Project → Export → iOS**, set **Application → App Store Team ID**, and export `build/ios/DriftguyProto.xcodeproj`.
   - Open the generated `.xcodeproj` in Xcode, enable automatic signing, connect your iPhone, and hit **Run** (`Cmd+R`).

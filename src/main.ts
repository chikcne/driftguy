import {
  Color3,
  Color4,
  DefaultRenderingPipeline,
  DirectionalLight,
  Engine,
  FreeCamera,
  HemisphericLight,
  Scene,
  ShadowGenerator,
  StandardMaterial,
  Vector3,
} from "@babylonjs/core";
import { GameAudio } from "./audio";
import { GunSystem, type PickupKind, PickupSystem, REPAIR_CRATE_VALUE, REPAIR_DROP_VALUE } from "./combat";
import { BlastPool, SkidTracks } from "./effects";
import { type Enemy, EnemySystem, Spawner } from "./enemies";
import { Hud } from "./hud";
import { Input } from "./input";
import type { Shove } from "./loose";
import { clamp, damp, lerp, randRange, randSigned, saturate } from "./math";
import { buildPlayerCar, type PlayerCarModel, WHEEL_RADIUS } from "./models";
import { PALETTE } from "./palette";
import { PUFF, type PuffKind, type SmokeEnvironment, SmokeSystem } from "./smoke";
import { groundHeight, sampleSlope, type Slope } from "./terrain";
import { deriveStats, emptyLevels, HEAL_ON_PICK, rollChoices, type Stats, type UpgradeDef, type UpgradeLevels } from "./upgrades";
import { AXLE_FRONT, AXLE_REAR, CarBody, type CarInput, HALF_TRACK } from "./vehicle";
import { type Contact, World } from "./world";

type Phase = "title" | "playing" | "levelup" | "paused" | "dying" | "gameover";

interface PendingBlast {
  x: number;
  z: number;
  delay: number;
  damage: number;
  radius: number;
}

const MAX_FRAME_SECONDS = 1 / 20;
const FOG_START = 120;
const FOG_END = 320;
const SUN_DIRECTION = new Vector3(-0.5, -0.7, 0.42).normalize();
const CAMERA_OFFSET = new Vector3(0, 0.8, -0.6).normalize();
const CAMERA_DISTANCE_SLOW = 70;
const CAMERA_DISTANCE_FAST = 100;
const CAMERA_LOOK_AHEAD_SECONDS = 0.45;
const CAMERA_FOV = 0.55;
const SHADOW_FRUSTUM = 190;
const SHADOW_DISTANCE = 160;
const CAR_RADIUS = 1.45;
const WALL_BOUNCE = 0.3;
const PLANT_TWIST = 0.35;
const PLANT_TWIST_LIMIT = 1.6;
const PLANT_THUD_IMPULSE = 1.2;
const SMOKE_PUFFS_PER_SECOND = 22;
const SMOKE_LIFE_SECONDS = 5.5;
const SMOKE_GROWTH = 1.25;
const SMOKE_CARRY = 0.45;
const SMOKE_FLING = 1.5;
const FRONT_SMOKE_SLIP = 6;
const DUST_PER_METRE = 0.3;
const HIT_INVULNERABILITY = 0.5;
const LEVEL_UP_GRACE = 0.6;
const DEATH_SECONDS = 1.3;
const REPAIR_DROP_CHANCE = 0.025;
const CRATE_INTERVAL_MIN = 50;
const CRATE_INTERVAL_MAX = 80;
const CRATE_DISTANCE_MIN = 45;
const CRATE_DISTANCE_MAX = 80;
const CRATE_HEADING_SPREAD = 1.2;
const CRATE_CLEARANCE = 2.5;
const BLAST_CHAIN_DELAY = 0.09;
const TRACK_SLIP_SPEED = 2.5;
const COMPOUND_BAND_SECONDS = 0.7;

function scrapNeeded(level: number): number {
  return Math.floor(3 + level * 3 + Math.pow(level, 1.7));
}

class Game {
  private readonly engine: Engine;
  private readonly scene: Scene;
  private readonly camera: FreeCamera;
  private readonly sun: DirectionalLight;
  private readonly input = new Input();
  private readonly audio = new GameAudio();
  private readonly hud = new Hud();
  private readonly world: World;
  private readonly smoke: SmokeSystem;
  private readonly enemies: EnemySystem;
  private readonly spawner = new Spawner();
  private readonly gun: GunSystem;
  private readonly pickups: PickupSystem;
  private readonly blasts: BlastPool;
  private readonly tracks: SkidTracks;
  private readonly carModel: PlayerCarModel;
  private readonly car = new CarBody();
  private readonly controls: CarInput = { throttle: 0, brake: 0, steer: 0, handbrake: false };
  private readonly contact: Contact = { hit: false, nx: 0, nz: 0 };
  private readonly shove: Shove = { hit: false, impulse: 0, x: 0, z: 0 };
  private readonly slope: Slope = { height: 0, pitch: 0, roll: 0 };
  private readonly cameraTarget = new Vector3();
  private readonly cameraForward = new Vector3();
  private readonly cameraRight = new Vector3();
  private readonly cameraUp = new Vector3();
  private readonly pendingBlasts: PendingBlast[] = [];
  private readonly smokeAccumulator = [0, 0, 0, 0];
  private readonly previousWheel = [0, 0, 0, 0, 0, 0, 0, 0];
  private readonly smokeEnvironment: SmokeEnvironment;

  private phase: Phase = "title";
  private levels: UpgradeLevels = emptyLevels();
  private stats: Stats = deriveStats(this.levels);
  private hp = this.stats.maxHp;
  private scrap = 0;
  private level = 1;
  private kills = 0;
  private time = 0;
  private clock = 0;
  private invulnerable = 0;
  private shake = 0;
  private cameraDistance = CAMERA_DISTANCE_SLOW;
  private dustAccumulator = 0;
  private deathTimer = 0;
  private smokeOutput = 0;
  private rumbleTimer = 0;
  private nextCrate = randRange(CRATE_INTERVAL_MIN, CRATE_INTERVAL_MAX);

  constructor(canvas: HTMLCanvasElement) {
    this.engine = new Engine(canvas, true, { stencil: false, powerPreference: "high-performance" });
    this.scene = new Scene(this.engine);
    this.scene.clearColor = new Color4(PALETTE.haze.r, PALETTE.haze.g, PALETTE.haze.b, 1);
    this.scene.fogMode = Scene.FOGMODE_LINEAR;
    this.scene.fogColor = PALETTE.haze;
    this.scene.fogStart = FOG_START;
    this.scene.fogEnd = FOG_END;
    this.scene.skipPointerMovePicking = true;
    this.scene.autoClear = true;

    this.camera = new FreeCamera("camera", new Vector3(0, 60, -45), this.scene);
    this.camera.fov = CAMERA_FOV;
    this.camera.minZ = 5;
    this.camera.maxZ = 700;

    const sky = new HemisphericLight("sky", new Vector3(0, 1, 0), this.scene);
    sky.diffuse = new Color3(0.86, 0.8, 0.98);
    sky.groundColor = new Color3(0.72, 0.5, 0.46);
    sky.specular = Color3.Black();
    sky.intensity = 0.64;

    this.sun = new DirectionalLight("sun", SUN_DIRECTION, this.scene);
    this.sun.diffuse = new Color3(1, 0.9, 0.74);
    this.sun.specular = Color3.Black();
    this.sun.intensity = 0.62;
    this.sun.shadowFrustumSize = SHADOW_FRUSTUM;
    this.sun.shadowMinZ = 1;
    this.sun.shadowMaxZ = SHADOW_DISTANCE * 2.4;

    const shadows = new ShadowGenerator(2048, this.sun);
    shadows.usePercentageCloserFiltering = true;
    shadows.filteringQuality = ShadowGenerator.QUALITY_MEDIUM;
    shadows.bias = 0.002;
    shadows.normalBias = 0.03;
    shadows.darkness = 0.12;

    const flat = new StandardMaterial("flat", this.scene);
    flat.specularColor = Color3.Black();
    flat.backFaceCulling = false;

    this.world = new World(this.scene, flat, shadows);
    this.smoke = new SmokeSystem(this.scene, PALETTE.haze, FOG_START, FOG_END);
    this.enemies = new EnemySystem(this.scene, flat, shadows);
    this.gun = new GunSystem(this.scene);
    this.pickups = new PickupSystem(this.scene, flat);
    this.blasts = new BlastPool(this.scene);
    this.tracks = new SkidTracks(this.scene, 4);

    this.carModel = buildPlayerCar(this.scene);
    for (const mesh of this.carModel.shadowCasters) {
      mesh.material = flat;
      mesh.receiveShadows = true;
      shadows.addShadowCaster(mesh);
    }

    const pipeline = new DefaultRenderingPipeline("pipeline", true, this.scene, [this.camera]);
    pipeline.samples = 4;
    pipeline.fxaaEnabled = true;
    pipeline.bloomEnabled = true;
    pipeline.bloomThreshold = 0.82;
    pipeline.bloomWeight = 0.3;
    pipeline.bloomKernel = 48;
    pipeline.bloomScale = 0.5;
    pipeline.imageProcessing.contrast = 1.12;
    pipeline.imageProcessing.exposure = 1.02;
    pipeline.imageProcessing.vignetteEnabled = true;
    pipeline.imageProcessing.vignetteWeight = 1.4;
    pipeline.imageProcessing.vignetteColor = new Color4(0.25, 0.12, 0.1, 0);

    this.smokeEnvironment = {
      time: 0,
      carX: 0,
      carZ: 0,
      carVx: 0,
      carVz: 0,
      carFx: 0,
      carFz: 1,
      fanPower: 0,
      fanRange: 0,
      cameraForward: this.cameraForward,
      cameraRight: this.cameraRight,
      cameraUp: this.cameraUp,
      cameraPosition: this.camera.position,
      sunDirection: SUN_DIRECTION,
    };

    this.input.onFirstGesture = () => this.audio.unlock();
    this.hud.onStart = () => this.startRun();
    this.hud.onRetry = () => this.startRun();
    this.hud.onPick = (upgrade) => this.applyUpgrade(upgrade);
    this.spawner.onThreat = (threat) => this.audio.warning(threat.kind === "boss");

    this.resetRun();
    this.snapCamera();
    window.addEventListener("resize", () => this.engine.resize());
    this.engine.runRenderLoop(() => this.frame());
  }

  private frame(): void {
    const dt = Math.min(this.engine.getDeltaTime() / 1000, MAX_FRAME_SECONDS);
    this.clock += dt;
    this.input.poll();
    if (this.input.mute) this.audio.toggleMute();
    if (this.input.usingGamepad && (this.input.confirm || this.input.throttle > 0)) this.audio.unlock();

    switch (this.phase) {
      case "title":
        this.hud.setInputMode(this.input.usingGamepad, this.input.padConnected);
        if (this.input.confirm) this.startRun();
        this.idle(dt);
        break;
      case "playing":
        if (this.input.pause) {
          this.setPhase("paused");
          break;
        }
        this.simulate(dt);
        break;
      case "levelup":
        if (this.input.menuMove !== 0) this.hud.moveSelection(this.input.menuMove);
        if (this.input.confirm) this.hud.confirmSelection();
        break;
      case "paused":
        if (this.input.pause || this.input.confirm) this.setPhase("playing");
        break;
      case "dying":
        this.deathTimer -= dt;
        this.idle(dt);
        if (this.deathTimer <= 0) this.setPhase("gameover");
        break;
      case "gameover":
        if (this.input.confirm) this.startRun();
        this.idle(dt);
        break;
    }

    const driving = this.phase === "playing";
    this.audio.drive(saturate(this.car.speed / this.stats.tuning.topSpeed), driving ? this.input.throttle : 0, this.smokeOutput, driving);
    this.scene.render();
  }

  private setPhase(phase: Phase): void {
    this.phase = phase;
    this.hud.showTitle(phase === "title");
    this.hud.showPause(phase === "paused");
    this.hud.showPlaying(phase !== "title");
    if (phase !== "levelup") this.hud.closeLevelUp();
    if (phase === "dying" || phase === "gameover") this.hud.setThreats([]);
    this.hud.showGameOver(phase === "gameover" ? { seconds: this.time, kills: this.kills, level: this.level } : null);
  }

  private resetRun(): void {
    this.levels = emptyLevels();
    this.stats = deriveStats(this.levels);
    this.hp = this.stats.maxHp;
    this.scrap = 0;
    this.level = 1;
    this.kills = 0;
    this.time = 0;
    this.invulnerable = 0;
    this.shake = 0;
    this.pendingBlasts.length = 0;
    this.nextCrate = randRange(CRATE_INTERVAL_MIN, CRATE_INTERVAL_MAX);
    this.car.reset();
    this.enemies.clear();
    this.spawner.reset();
    this.gun.clear();
    this.pickups.clear();
    this.blasts.clear();
    this.tracks.clear();
    this.smoke.clear();
    this.world.reset();
    this.world.update(0, 0);
    this.rememberWheels();
    this.carModel.root.setEnabled(true);
    this.syncAttachments();
    this.hud.setLoadout(this.levels);
  }

  private startRun(): void {
    this.audio.unlock();
    this.resetRun();
    this.snapCamera();
    this.setPhase("playing");
  }

  private idle(dt: number): void {
    this.world.step(dt, this.car.x, this.car.z);
    this.blasts.update(dt);
    this.updateSmoke(dt);
    this.updateCarVisuals(dt);
    this.updateCamera(dt);
    this.enemies.render(this.clock);
    this.pickups.render(this.clock);
    this.gun.render();
  }

  private simulate(dt: number): void {
    this.time += dt;
    this.invulnerable -= dt;

    this.controls.throttle = this.input.throttle;
    this.controls.brake = this.input.brake;
    this.controls.steer = this.input.steer;
    this.controls.handbrake = this.input.handbrake;
    this.car.step(dt, this.controls, this.stats.tuning);
    this.collideCarWithWorld();
    this.world.update(this.car.x, this.car.z);

    this.emitTyreSmoke(dt);
    this.spawner.update(dt, this.time, this.car, this.enemies);
    this.enemies.update({
      dt,
      time: this.time,
      car: this.car,
      stats: this.stats,
      world: this.world,
      smoke: this.smoke,
      damageScale: this.spawner.damageScale(this.time),
      onPlayerHit: (enemy, damage, closing) => this.hurtPlayer(enemy, damage, closing),
      onKill: (enemy) => this.onEnemyKilled(enemy),
    });
    this.world.step(dt, this.car.x, this.car.z);
    this.gun.update(dt, this.car, this.stats, this.enemies, this.audio);
    this.enemies.sweepDead((enemy) => this.onEnemyKilled(enemy));
    this.updateBlasts(dt);
    this.updateCrates(dt);
    this.pickups.update(dt, this.car, this.stats.magnetRadius, (kind, value) => this.collect(kind, value));

    this.blasts.update(dt);
    this.updateSmoke(dt);
    this.updateCarVisuals(dt);
    this.updateCamera(dt);
    this.enemies.render(this.clock);
    this.pickups.render(this.clock);
    this.gun.render();
    this.tracks.flush();
    this.updateRumble(dt);

    this.hud.setFrame(
      this.hp,
      this.stats.maxHp,
      this.scrap / scrapNeeded(this.level),
      this.level,
      this.time,
      this.kills,
      this.car.speed * 3.6,
      this.smokeOutput,
    );
    this.hud.setThreats(this.spawner.threats);

    if (this.hp <= 0) {
      this.die();
    } else if (this.scrap >= scrapNeeded(this.level)) {
      this.scrap -= scrapNeeded(this.level);
      this.level++;
      this.audio.levelUp();
      this.hud.openLevelUp(rollChoices(this.levels, 3), this.levels);
      this.setPhase("levelup");
    }
  }

  private collideCarWithWorld(): void {
    const car = this.car;
    this.ploughThroughPlants();
    if (!this.world.resolve(car, CAR_RADIUS, this.contact).hit) return;
    const into = car.vx * this.contact.nx + car.vz * this.contact.nz;
    if (into >= 0) return;
    car.vx -= (1 + WALL_BOUNCE) * into * this.contact.nx;
    car.vz -= (1 + WALL_BOUNCE) * into * this.contact.nz;
    car.yawRate *= 0.6;
    const impact = -into;
    if (impact > 5) {
      this.shake = Math.max(this.shake, saturate(impact / 25));
      this.audio.thud(impact / 25);
      this.input.rumble(saturate(impact / 20), 0.3, 160);
    }
  }

  private ploughThroughPlants(): void {
    const car = this.car;
    const speed = Math.hypot(car.vx, car.vz);
    const dirX = speed > 0.01 ? car.vx / speed : 0;
    const dirZ = speed > 0.01 ? car.vz / speed : 0;
    const impulse = this.world.shove(car, CAR_RADIUS, 1, this.shove).impulse;
    if (impulse <= 0) return;
    const offX = this.shove.x - car.x;
    const offZ = this.shove.z - car.z;
    const twist = (offX * dirZ - offZ * dirX) * impulse * PLANT_TWIST;
    car.yawRate += clamp(twist, -PLANT_TWIST_LIMIT, PLANT_TWIST_LIMIT);
    if (impulse > PLANT_THUD_IMPULSE) {
      this.shake = Math.max(this.shake, saturate(impulse / 14));
      this.audio.thud(impulse / 10);
      this.input.rumble(saturate(impulse / 8), 0.2, 120);
    }
  }

  private wheelPosition(index: number, out: { x: number; z: number }): void {
    const car = this.car;
    const fx = Math.sin(car.heading);
    const fz = Math.cos(car.heading);
    const along = index < 2 ? AXLE_FRONT : -AXLE_REAR;
    const across = index % 2 === 0 ? -HALF_TRACK : HALF_TRACK;
    out.x = car.x + fx * along + fz * across;
    out.z = car.z + fz * along - fx * across;
  }

  private rememberWheels(): void {
    const spot = { x: 0, z: 0 };
    for (let wheel = 0; wheel < 4; wheel++) {
      this.wheelPosition(wheel, spot);
      this.previousWheel[wheel * 2] = spot.x;
      this.previousWheel[wheel * 2 + 1] = spot.z;
    }
  }

  private pickSmokeKind(): PuffKind {
    const owned: PuffKind[] = [];
    if (this.levels.ash > 0) owned.push(PUFF.ash);
    if (this.levels.ember > 0) owned.push(PUFF.ember);
    if (this.levels.toxic > 0) owned.push(PUFF.toxic);
    if (owned.length === 0) return PUFF.white;
    return owned[Math.floor(this.time / COMPOUND_BAND_SECONDS) % owned.length];
  }

  private emitTyreSmoke(dt: number): void {
    const car = this.car;
    const stats = this.stats;
    const rearIntensity = car.smokeIntensity();
    const frontIntensity = saturate((car.frontSlipSpeed - FRONT_SMOKE_SLIP) / 10) * 0.4;
    this.smokeOutput = damp(this.smokeOutput, rearIntensity / 1.2, 8, dt);
    const fx = Math.sin(car.heading);
    const fz = Math.cos(car.heading);
    const spot = { x: 0, z: 0 };

    for (let wheel = 0; wheel < 4; wheel++) {
      this.wheelPosition(wheel, spot);
      const fromX = this.previousWheel[wheel * 2];
      const fromZ = this.previousWheel[wheel * 2 + 1];
      const intensity = wheel < 2 ? frontIntensity : rearIntensity;
      const slipSpeed = wheel < 2 ? car.frontSlipSpeed : car.rearSlipSpeed;
      this.tracks.mark(wheel, spot.x, spot.z, slipSpeed > TRACK_SLIP_SPEED || (wheel >= 2 && car.burnout > 0.3));

      if (intensity > 0.04) {
        this.smokeAccumulator[wheel] += SMOKE_PUFFS_PER_SECOND * intensity * stats.smokeRate * dt;
        const count = Math.floor(this.smokeAccumulator[wheel]);
        this.smokeAccumulator[wheel] -= count;
        for (let i = 0; i < count; i++) {
          const t = (i + Math.random()) / count;
          const x = lerp(fromX, spot.x, t);
          const z = lerp(fromZ, spot.z, t);
          const fling = SMOKE_FLING + car.burnout * 5 + Math.min(4, slipSpeed * 0.3);
          const spill = (wheel % 2 === 0 ? -1 : 1) * randRange(0.2, 1.4);
          this.smoke.emit(
            this.pickSmokeKind(),
            x,
            groundHeight(x, z) + 0.35,
            z,
            car.vx * SMOKE_CARRY - fx * fling + fz * spill + randSigned(0.6),
            randRange(1, 2.6),
            car.vz * SMOKE_CARRY - fz * fling - fx * spill + randSigned(0.6),
            randRange(0.7, 1.0),
            SMOKE_GROWTH * stats.smokeSpread * randRange(0.85, 1.15),
            SMOKE_LIFE_SECONDS * stats.smokeLife * randRange(0.8, 1.2),
            0.9,
            1,
          );
        }
      }
      this.previousWheel[wheel * 2] = spot.x;
      this.previousWheel[wheel * 2 + 1] = spot.z;
    }

    this.dustAccumulator += car.speed * DUST_PER_METRE * dt;
    while (this.dustAccumulator >= 1) {
      this.dustAccumulator -= 1;
      const side = Math.random() < 0.5 ? -HALF_TRACK : HALF_TRACK;
      const x = car.x - fx * AXLE_REAR + fz * side;
      const z = car.z - fz * AXLE_REAR - fx * side;
      this.smoke.emit(PUFF.dust, x, groundHeight(x, z) + 0.25, z, car.vx * 0.25 + randSigned(0.8), randRange(0.5, 1.4), car.vz * 0.25 + randSigned(0.8), 0.45, 0.95, randRange(1, 1.6), 0.4, 0.2);
    }
  }

  private hurtPlayer(enemy: Enemy, damage: number, closingSpeed: number): void {
    this.shake = Math.max(this.shake, 0.35 + saturate(closingSpeed / 30) * 0.4);
    this.audio.thud(0.5 + enemy.spec.mass * 0.2);
    if (this.invulnerable > 0) return;
    this.invulnerable = HIT_INVULNERABILITY;
    this.hp -= damage;
    this.hud.flashDamage();
    this.input.rumble(0.9, 0.6, 220);
  }

  private onEnemyKilled(enemy: Enemy): void {
    this.kills++;
    const spec = enemy.spec;
    const pieces = Math.min(10, Math.ceil(spec.scrap / 3));
    this.pickups.drop("scrap", enemy.x, enemy.z, pieces, spec.scrap / pieces);
    if (Math.random() < REPAIR_DROP_CHANCE * (1 + spec.mass * 2)) this.pickups.drop("repair", enemy.x, enemy.z, 1, REPAIR_DROP_VALUE);

    const y = groundHeight(enemy.x, enemy.z) + 1;
    this.blasts.spawn(enemy.x, y, enemy.z, spec.radius * 1.6);
    for (let i = 0; i < 3 + Math.round(spec.radius * 2); i++) {
      this.smoke.emit(
        i % 3 === 0 ? PUFF.fire : PUFF.soot,
        enemy.x + randSigned(spec.radius),
        y,
        enemy.z + randSigned(spec.radius),
        enemy.vx * 0.3 + randSigned(3),
        randRange(2, 5),
        enemy.vz * 0.3 + randSigned(3),
        randRange(0.6, 1.1) * (0.7 + spec.radius * 0.3),
        1.6,
        randRange(0.9, 1.8),
        0.85,
        2,
      );
    }
    if (enemy.emberTimer > 0 && this.stats.emberDamage > 0) {
      this.pendingBlasts.push({ x: enemy.x, z: enemy.z, delay: BLAST_CHAIN_DELAY, damage: this.stats.emberDamage, radius: this.stats.emberRadius });
    }
  }

  private updateBlasts(dt: number): void {
    let detonated = false;
    for (let i = this.pendingBlasts.length - 1; i >= 0; i--) {
      const blast = this.pendingBlasts[i];
      blast.delay -= dt;
      if (blast.delay > 0) continue;
      this.pendingBlasts.splice(i, 1);
      this.detonate(blast.x, blast.z, blast.radius, blast.damage);
      detonated = true;
    }
    if (detonated) this.enemies.sweepDead((enemy) => this.onEnemyKilled(enemy));
  }

  private detonate(x: number, z: number, radius: number, damage: number): void {
    const y = groundHeight(x, z) + 1.2;
    this.blasts.spawn(x, y, z, radius);
    this.smoke.shockwave(x, z, radius * 2.4, 16);
    for (let i = 0; i < 9; i++) {
      this.smoke.emit(PUFF.fire, x + randSigned(radius * 0.5), y, z + randSigned(radius * 0.5), randSigned(7), randRange(2, 7), randSigned(7), randRange(1, 1.8), 3, randRange(0.4, 0.8), 0.9, 2.5);
    }
    this.enemies.hurtArea(x, z, radius, damage);
    this.audio.explosion();
    const distance = Math.hypot(x - this.car.x, z - this.car.z);
    this.shake = Math.max(this.shake, 0.5 * saturate(1 - distance / 60));
  }

  private updateCrates(dt: number): void {
    this.nextCrate -= dt;
    if (this.nextCrate > 0) return;
    this.nextCrate = randRange(CRATE_INTERVAL_MIN, CRATE_INTERVAL_MAX);
    const moving = Math.hypot(this.car.vx, this.car.vz) > 1;
    const heading = moving ? Math.atan2(this.car.vx, this.car.vz) + randSigned(CRATE_HEADING_SPREAD) : Math.random() * Math.PI * 2;
    const distance = randRange(CRATE_DISTANCE_MIN, CRATE_DISTANCE_MAX);
    const spot = { x: this.car.x + Math.sin(heading) * distance, z: this.car.z + Math.cos(heading) * distance };
    this.world.resolve(spot, CRATE_CLEARANCE, { hit: false, nx: 0, nz: 0 });
    this.pickups.place("repair", spot.x, spot.z, REPAIR_CRATE_VALUE);
  }

  private collect(kind: PickupKind, value: number): void {
    if (kind === "scrap") {
      this.scrap += value;
      this.audio.pickup(Math.min(8, value));
    } else {
      this.hp = Math.min(this.stats.maxHp, this.hp + value);
      this.audio.levelUp();
    }
  }

  private applyUpgrade(upgrade: UpgradeDef): void {
    if (this.phase !== "levelup") return;
    this.levels[upgrade.id]++;
    this.stats = deriveStats(this.levels);
    this.hp = Math.min(this.stats.maxHp, this.hp + (HEAL_ON_PICK[upgrade.id] ?? 0));
    this.invulnerable = LEVEL_UP_GRACE;
    this.syncAttachments();
    this.hud.setLoadout(this.levels);
    this.setPhase("playing");
  }

  private syncAttachments(): void {
    this.carModel.gun.setEnabled(this.levels.gun > 0);
    this.carModel.fan.setEnabled(this.levels.fan > 0);
    this.carModel.plow.setEnabled(this.levels.ram > 0);
  }

  private die(): void {
    this.deathTimer = DEATH_SECONDS;
    this.detonate(this.car.x, this.car.z, 9, 0);
    this.carModel.root.setEnabled(false);
    this.car.vx = this.car.vz = this.car.yawRate = 0;
    this.shake = 1;
    this.smokeOutput = 0;
    this.audio.defeat();
    this.input.rumble(1, 1, 500);
    this.setPhase("dying");
  }

  private updateSmoke(dt: number): void {
    const car = this.car;
    const env = this.smokeEnvironment;
    env.time = this.clock;
    env.carX = car.x;
    env.carZ = car.z;
    env.carVx = car.vx;
    env.carVz = car.vz;
    env.carFx = Math.sin(car.heading);
    env.carFz = Math.cos(car.heading);
    env.fanPower = this.stats.fanPower;
    env.fanRange = this.stats.fanRange;
    this.cameraForward.copyFrom(CAMERA_OFFSET).scaleInPlace(-1);
    Vector3.CrossToRef(Vector3.UpReadOnly, this.cameraForward, this.cameraRight);
    this.cameraRight.normalize();
    Vector3.CrossToRef(this.cameraForward, this.cameraRight, this.cameraUp);
    this.smoke.update(dt, env);
  }

  private updateCarVisuals(dt: number): void {
    const car = this.car;
    const model = this.carModel;
    const slope = sampleSlope(car.x, car.z, car.heading, AXLE_FRONT, HALF_TRACK, this.slope);
    model.root.position.set(car.x, slope.height, car.z);
    model.root.rotation.set(slope.pitch, car.heading, slope.roll);
    model.lean.rotation.z = damp(model.lean.rotation.z, clamp(car.latAccel * 0.011, -0.16, 0.16), 10, dt);
    model.lean.rotation.x = damp(model.lean.rotation.x, clamp(-car.longAccel * 0.006, -0.08, 0.08), 10, dt);

    const steer = clamp(car.steerAngle, -0.62, 0.62);
    model.steerPivots[0].rotation.y = steer;
    model.steerPivots[1].rotation.y = steer;
    const rolling = (car.forwardSpeed / WHEEL_RADIUS) * dt;
    const rearSpin = this.controls.handbrake ? 0 : rolling * (1 + car.burnout * 3);
    model.wheels[0].rotation.x += rolling;
    model.wheels[1].rotation.x += rolling;
    model.wheels[2].rotation.x += rearSpin;
    model.wheels[3].rotation.x += rearSpin;

    model.gun.rotation.y = this.gun.angle - car.heading;
    model.fan.rotation.z += 26 * dt;
  }

  private snapCamera(): void {
    this.cameraTarget.set(this.car.x, groundHeight(this.car.x, this.car.z), this.car.z);
    this.cameraDistance = CAMERA_DISTANCE_SLOW;
    this.updateCamera(0);
  }

  private updateCamera(dt: number): void {
    const car = this.car;
    const speedFraction = saturate(car.speed / this.stats.tuning.topSpeed);
    const aimX = car.x + car.vx * CAMERA_LOOK_AHEAD_SECONDS;
    const aimZ = car.z + car.vz * CAMERA_LOOK_AHEAD_SECONDS;
    this.cameraTarget.x = damp(this.cameraTarget.x, aimX, 5, dt);
    this.cameraTarget.z = damp(this.cameraTarget.z, aimZ, 5, dt);
    this.cameraTarget.y = damp(this.cameraTarget.y, groundHeight(car.x, car.z), 3, dt);
    this.cameraDistance = damp(this.cameraDistance, lerp(CAMERA_DISTANCE_SLOW, CAMERA_DISTANCE_FAST, speedFraction), 1.5, dt);

    this.shake = Math.max(0, this.shake - dt * 2.2);
    const jolt = this.shake * this.shake * 1.6;
    this.camera.position.set(
      this.cameraTarget.x + CAMERA_OFFSET.x * this.cameraDistance + randSigned(jolt),
      this.cameraTarget.y + CAMERA_OFFSET.y * this.cameraDistance + randSigned(jolt),
      this.cameraTarget.z + CAMERA_OFFSET.z * this.cameraDistance + randSigned(jolt),
    );
    this.camera.setTarget(this.cameraTarget);
    this.sun.position.set(
      this.cameraTarget.x - SUN_DIRECTION.x * SHADOW_DISTANCE,
      this.cameraTarget.y - SUN_DIRECTION.y * SHADOW_DISTANCE,
      this.cameraTarget.z - SUN_DIRECTION.z * SHADOW_DISTANCE,
    );
  }

  private updateRumble(dt: number): void {
    this.rumbleTimer -= dt;
    if (this.rumbleTimer > 0 || this.smokeOutput < 0.15) return;
    this.rumbleTimer = 0.1;
    this.input.rumble(0, this.smokeOutput * 0.35, 130);
  }
}

const canvas = document.getElementById("view");
if (!(canvas instanceof HTMLCanvasElement)) throw new Error("Missing game canvas");
const game = new Game(canvas);
if (import.meta.env.DEV) Object.assign(window, { driftguy: game });
